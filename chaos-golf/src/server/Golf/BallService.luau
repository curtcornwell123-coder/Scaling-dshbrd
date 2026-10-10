--!strict
-- Server-authoritative golf balls. Roblox physics handles collisions; this
-- module adds rolling resistance, surfaces (sand / ice / boost), rest detection,
-- sinking, out-of-bounds resets and validated shots. Whoever owns a ball (a
-- match, a practice lane, the tutorial) supplies a Context with callbacks.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))
local Abilities = require(Shared:WaitForChild("Abilities"))

local BallService = {}

export type Context = {
	CanShoot: (Ball) -> boolean,
	OnShot: ((Ball) -> ())?,
	OnRest: ((Ball) -> ())?,
	OnSink: ((Ball) -> ())?,
	OnOOB: ((Ball) -> ())?,
	OnKnockout: ((Ball, Player) -> ())?, -- (victim, attacker) a recent hit sent this ball out of bounds
	Tick: ((Ball, number) -> ())?, -- every heartbeat while the ball exists (pickups, scoring)
}

export type Ball = {
	Player: Player,
	Part: Part,
	Context: Context,
	Strokes: number,
	AtRest: boolean,
	Sunk: boolean,
	RestTimer: number,
	MovingTime: number,
	LastRest: Vector3,
	PrevRest: Vector3?,
	Cup: Vector3?,
	CupScale: number,
	TinyCupUntil: number,
	OOBY: number,
	Upgrades: { [string]: number },
	Frost: boolean, -- pending: applies to the next shot
	Gust: boolean,
	Magnet: boolean,
	ShotFrost: boolean, -- active for the shot in flight
	ShotMagnet: boolean,
	LastShot: number,
	MaxDistance: number, -- furthest projected distance this shot (practice drive scoring)
	LastHitBy: Player?,
	LastHitTime: number,
	LastHitEffect: string?,
	Data: { [string]: any }, -- owner scratch space
}

export type Loadout = { Skin: string, Trail: string, Knockout: string, Arrow: string }

local HIT_SPEED = 14 -- relative speed that counts as a hit
local KNOCKOUT_WINDOW = 5 -- seconds after a hit in which going out of bounds is a knockout

local GROUP_SOLID = "GolfBalls"
local GROUP_GHOST = "GolfGhostBalls"
local GROUP_CHARACTERS = "GolfCharacters"

local balls: { [Player]: Ball } = {}
local folder: Folder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function registerGroups()
	for _, g in { GROUP_SOLID, GROUP_GHOST, GROUP_CHARACTERS } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(g)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP_SOLID, GROUP_CHARACTERS, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_GHOST, GROUP_CHARACTERS, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_GHOST, GROUP_GHOST, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_GHOST, GROUP_SOLID, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP_CHARACTERS, GROUP_CHARACTERS, true)
end

local function setCharacterGroup(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP_CHARACTERS
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP_CHARACTERS
		end
	end)
end

local function physicalProps(upgrades: { [string]: number }): PhysicalProperties
	local bounce = 1 + (upgrades.Bounce or 0) * 0.06
	return PhysicalProperties.new(Config.Ball.Density, Config.Ball.Friction, math.min(Config.Ball.Elasticity * bounce, 0.95), 1, 1)
end

local function sound(part: BasePart, id: string, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 120
	s.Parent = part
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function BallService.get(player: Player): Ball?
	return balls[player]
end

export type CreateOpts = {
	Position: Vector3,
	Context: Context,
	Ghost: boolean?,
	Upgrades: { [string]: number }?,
	Cup: Vector3?,
	OOBY: number,
	Loadout: Loadout?,
}

function BallService.create(player: Player, opts: CreateOpts): Ball
	BallService.destroy(player)

	local part = Instance.new("Part")
	part.Name = player.Name .. "_Ball"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * Config.Ball.Diameter
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(opts.Position)
	part.CollisionGroup = if opts.Ghost then GROUP_GHOST else GROUP_SOLID
	local upgrades = opts.Upgrades or { Power = 0, Control = 0, Bounce = 0 }
	part.CustomPhysicalProperties = physicalProps(upgrades)
	part:SetAttribute("Owner", player.UserId)
	part:SetAttribute("CanShoot", false)
	part:SetAttribute("Strokes", 0)
	-- Equipped cosmetics: the skin (with its built-in aura) is applied here; the
	-- trail, knockout effect and arrow skin are read by clients from attributes.
	local loadout = opts.Loadout
	Skins.apply(part, loadout and loadout.Skin)
	part:SetAttribute("Trail", loadout and loadout.Trail or "none")
	part:SetAttribute("Knockout", loadout and loadout.Knockout or "pop")
	part:SetAttribute("Arrow", loadout and loadout.Arrow or "classic")

	local tag = Instance.new("BillboardGui")
	tag.Name = "BallTag"
	tag.Size = UDim2.fromOffset(140, 26)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 90
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Config.Font
	label.TextScaled = true
	label.TextColor3 = Config.Colors.Text
	label.Text = player.DisplayName
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = label
	label.Parent = tag
	tag.Parent = part

	part.Parent = folder
	pcall(function()
		part:SetNetworkOwner(nil)
	end)

	local ball: Ball = {
		Player = player,
		Part = part,
		Context = opts.Context,
		Strokes = 0,
		AtRest = true,
		Sunk = false,
		RestTimer = 0,
		MovingTime = 0,
		LastRest = opts.Position,
		PrevRest = nil,
		Cup = opts.Cup,
		CupScale = 1,
		TinyCupUntil = 0,
		OOBY = opts.OOBY,
		Upgrades = upgrades,
		Frost = false,
		Gust = false,
		Magnet = false,
		ShotFrost = false,
		ShotMagnet = false,
		LastShot = 0,
		MaxDistance = 0,
		LastHitBy = nil,
		LastHitTime = 0,
		LastHitEffect = nil,
		Data = {},
	}
	balls[player] = ball
	BallService.refresh(ball)
	return ball
end

function BallService.destroy(player: Player)
	local ball = balls[player]
	if ball then
		balls[player] = nil
		ball.Part:Destroy()
	end
end

-- Re-evaluate CanShoot for the owner's client.
function BallService.refresh(ball: Ball)
	local can = ball.AtRest and not ball.Sunk and ball.Context.CanShoot(ball)
	ball.Part:SetAttribute("CanShoot", can)
	ball.Part:SetAttribute("Strokes", ball.Strokes)
	ball.Part:SetAttribute("Frosted", ball.Frost)
	ball.Part:SetAttribute("Gusted", ball.Gust)
	ball.Part:SetAttribute("Magnet", ball.Magnet)
	ball.Part:SetAttribute("TinyCup", ball.CupScale < 1)
end

function BallService.refreshAll()
	for _, ball in balls do
		BallService.refresh(ball)
	end
end

-- Place a ball (at rest) somewhere, e.g. the next tee or a reset point.
function BallService.place(ball: Ball, position: Vector3)
	local part = ball.Part
	part.Anchored = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CFrame = CFrame.new(position)
	ball.AtRest = true
	ball.RestTimer = 0
	ball.MovingTime = 0
	ball.LastRest = position
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	BallService.refresh(ball)
end

function BallService.setUpgrades(ball: Ball, upgrades: { [string]: number })
	ball.Upgrades = upgrades
	ball.Part.CustomPhysicalProperties = physicalProps(upgrades)
end

function BallService.maxSpeed(ball: Ball): number
	return Config.Physics.MaxShotSpeed * (1 + (ball.Upgrades.Power or 0) * 0.05)
end

-- Kick a ball with an external impulse (abilities); it becomes a moving ball again.
function BallService.push(ball: Ball, velocity: Vector3, by: Ball?)
	if ball.Sunk then
		return
	end
	if by then
		ball.LastHitBy = by.Player
		ball.LastHitTime = os.clock()
		ball.LastHitEffect = by.Part:GetAttribute("Knockout") :: string?
	end
	ball.AtRest = false
	ball.RestTimer = 0
	ball.MovingTime = 0
	ball.Part.AssemblyLinearVelocity += velocity
	BallService.refresh(ball)
end

local function shoot(player: Player, dir: any, power: any)
	local ball = balls[player]
	if not ball or ball.Sunk or not ball.AtRest then
		return
	end
	if typeof(dir) ~= "Vector3" or type(power) ~= "number" then
		return
	end
	if power ~= power or dir.X ~= dir.X or dir.Z ~= dir.Z then -- NaN guard
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	local now = os.clock()
	if now - ball.LastShot < 0.35 then
		return
	end
	if not ball.Context.CanShoot(ball) then
		return
	end
	power = math.clamp(power, Config.Physics.MinPower, 1)
	ball.LastShot = now

	local velocity = flat.Unit * BallService.maxSpeed(ball) * power
	if ball.Gust then
		ball.Gust = false
		local side = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X) * (if math.random() < 0.5 then -1 else 1)
		velocity += side * Abilities.GustSpeed
		Net.event("Fx"):FireAllClients("gust", { Ball = ball.Part })
	end
	ball.ShotFrost = ball.Frost
	ball.Frost = false
	ball.ShotMagnet = ball.Magnet
	ball.Magnet = false

	ball.PrevRest = ball.LastRest
	ball.Strokes += 1
	ball.AtRest = false
	ball.RestTimer = 0
	ball.MovingTime = 0
	ball.MaxDistance = 0
	local part = ball.Part
	part.Anchored = false
	part.AssemblyAngularVelocity = Vector3.zero
	part.AssemblyLinearVelocity = velocity
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	sound(part, Config.Sounds.Putt, 0.5 + power * 0.5)
	BallService.refresh(ball)
	if ball.Context.OnShot then
		ball.Context.OnShot(ball)
	end
end

local function sink(ball: Ball)
	ball.Sunk = true
	ball.AtRest = true
	local part = ball.Part
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	local cup = ball.Cup :: Vector3
	part.CanCollide = false
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(cup - Vector3.new(0, 1.2, 0)),
		Transparency = 1,
	}):Play()
	sound(part, Config.Sounds.Sink, 0.9)
	Net.event("Fx"):FireAllClients("sink", { Position = cup, Player = ball.Player, Strokes = ball.Strokes })
	BallService.refresh(ball)
	if ball.Context.OnSink then
		ball.Context.OnSink(ball)
	end
end

local function outOfBounds(ball: Ball)
	local where = ball.Part.Position
	Net.event("Fx"):FireAllClients("splash", { Position = where })
	local attacker = ball.LastHitBy
	if attacker and os.clock() - ball.LastHitTime < KNOCKOUT_WINDOW and attacker ~= ball.Player then
		Net.event("Fx"):FireAllClients("knockout", {
			Position = where,
			Effect = ball.LastHitEffect,
			Attacker = attacker,
			Victim = ball.Player,
		})
		if ball.Context.OnKnockout then
			ball.Context.OnKnockout(ball, attacker)
		end
	end
	ball.LastHitBy = nil
	ball.Strokes += 1 -- penalty stroke
	BallService.place(ball, ball.LastRest)
	ball.ShotFrost = false
	ball.ShotMagnet = false
	if ball.Context.OnOOB then
		ball.Context.OnOOB(ball)
	end
	BallService.refresh(ball)
end

local function rest(ball: Ball)
	local part = ball.Part
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	ball.AtRest = true
	ball.RestTimer = 0
	ball.LastRest = part.Position
	ball.ShotFrost = false
	ball.ShotMagnet = false
	BallService.refresh(ball)
	if ball.Context.OnRest then
		ball.Context.OnRest(ball)
	end
end

local function step(ball: Ball, dt: number)
	local part = ball.Part
	if ball.Sunk or not part.Parent or part.Anchored then
		return
	end
	local P = Config.Physics
	local pos = part.Position
	local vel = part.AssemblyLinearVelocity

	if ball.TinyCupUntil > 0 and os.clock() > ball.TinyCupUntil then
		ball.TinyCupUntil = 0
		ball.CupScale = 1
		BallService.refresh(ball)
	end

	if pos.Y < ball.OOBY then
		outOfBounds(ball)
		return
	end

	rayParams.CollisionGroup = part.CollisionGroup
	rayParams.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(pos, Vector3.new(0, -(Config.Ball.Diameter / 2 + 0.45), 0), rayParams)
	local grounded = hit ~= nil
	local surface = if hit then hit.Instance:GetAttribute("Surface") else nil

	if ball.AtRest then
		-- Hold still unless something (a spinner, another ball, an ability) shoves it.
		if vel.Magnitude > 3.5 or not grounded then
			ball.AtRest = false
			ball.RestTimer = 0
			ball.MovingTime = 0
			BallService.refresh(ball)
		else
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			-- A resting ball inside the cup (e.g. Tiny Cup just wore off) drops in.
			local cup = ball.Cup
			if cup and Vector2.new(cup.X - pos.X, cup.Z - pos.Z).Magnitude < Config.Physics.CupRadius * ball.CupScale then
				sink(ball)
			end
			return
		end
	end

	ball.MovingTime += dt
	local horizontal = Vector3.new(vel.X, 0, vel.Z)
	local speed = horizontal.Magnitude

	if grounded and hit then
		local control = ball.Upgrades.Control or 0
		local mult = 1
		if surface == "Sand" then
			mult = P.SandMultiplier
		elseif surface == "Ice" then
			mult = P.IceMultiplier * (1 + control * 0.08 * 3)
		end
		if ball.ShotFrost then
			mult = math.min(mult, P.IceMultiplier)
		end
		local decel = (P.RollResistance + P.Drag * speed) * mult
		if hit.Normal.Y < 0.985 then
			decel += control * 0.08 * P.RollResistance -- extra grip on slopes
		end
		if surface == "Boost" then
			local dir = hit.Instance:GetAttribute("BoostDir")
			if typeof(dir) == "Vector3" and dir.Magnitude > 0 then
				local target = dir.Unit * P.BoostSpeed
				if horizontal:Dot(dir.Unit) < P.BoostSpeed then
					horizontal = horizontal:Lerp(target, math.clamp(dt * 8, 0, 1))
					speed = horizontal.Magnitude
					decel = 0
				end
			end
		end
		if speed > 0 then
			local newSpeed = math.max(0, speed - decel * dt)
			horizontal = horizontal.Unit * newSpeed
			speed = newSpeed
		end

		local cup = ball.Cup
		if cup then
			local toCup = Vector3.new(cup.X - pos.X, 0, cup.Z - pos.Z)
			local dist = toCup.Magnitude
			if ball.ShotMagnet and dist < P.CupMagnetRadius and dist > 0.05 then
				horizontal += toCup.Unit * 60 * dt
				if horizontal.Magnitude > P.MaxSinkSpeed * 0.7 then
					horizontal = horizontal.Unit * P.MaxSinkSpeed * 0.7
				end
				speed = horizontal.Magnitude
			end
			if dist < P.CupRadius * ball.CupScale and math.abs(pos.Y - (cup.Y + Config.Ball.Diameter / 2)) < 1.4 then
				if speed < P.MaxSinkSpeed then
					sink(ball)
					return
				end
			end
		end
		part.AssemblyLinearVelocity = Vector3.new(horizontal.X, vel.Y, horizontal.Z)
	end

	if ball.Context.Tick then
		ball.Context.Tick(ball, dt)
	end

	local total = part.AssemblyLinearVelocity.Magnitude
	if grounded and total < P.RestSpeed then
		ball.RestTimer += dt
		if ball.RestTimer >= P.RestTime then
			rest(ball)
		end
	else
		ball.RestTimer = 0
	end

	if ball.MovingTime > P.MaxRollTime then
		if grounded then
			rest(ball)
		else
			outOfBounds(ball)
		end
	end
end

-- Ball-on-ball hits (solid balls only): knockout effect + attribution for knockouts.
local pairCooldown: { [string]: number } = {}

local function detectHits()
	local list = {}
	for _, b in balls do
		if not b.Sunk and b.Part.Parent and b.Part.CollisionGroup == GROUP_SOLID then
			table.insert(list, b)
		end
	end
	if #list < 2 then
		return
	end
	local t = os.clock()
	local reach = Config.Ball.Diameter + 0.25
	for i = 1, #list - 1 do
		local a = list[i]
		local pa = a.Part.Position
		for j = i + 1, #list do
			local b = list[j]
			local pb = b.Part.Position
			if (pa - pb).Magnitude < reach then
				local va, vb = a.Part.AssemblyLinearVelocity, b.Part.AssemblyLinearVelocity
				if (va - vb).Magnitude > HIT_SPEED then
					local key = if a.Player.UserId < b.Player.UserId then a.Player.UserId .. ":" .. b.Player.UserId else b.Player.UserId .. ":" .. a.Player.UserId
					if (pairCooldown[key] or 0) < t then
						pairCooldown[key] = t + 0.6
						local attacker, victim = a, b
						if vb.Magnitude > va.Magnitude then
							attacker, victim = b, a
						end
						victim.LastHitBy = attacker.Player
						victim.LastHitTime = t
						victim.LastHitEffect = attacker.Part:GetAttribute("Knockout") :: string?
						sound(victim.Part, Config.Sounds.Bonk, 0.8)
						Net.event("Fx"):FireAllClients("hit", {
							Position = (pa + pb) / 2,
							Effect = victim.LastHitEffect,
							Attacker = attacker.Player,
						})
					end
				end
			end
		end
	end
end

-- Abilities helpers ---------------------------------------------------------

function BallService.mulligan(ball: Ball): boolean
	if ball.Sunk or not ball.AtRest or not ball.PrevRest or ball.Strokes <= 0 then
		return false
	end
	ball.Strokes -= 1
	BallService.place(ball, ball.PrevRest :: Vector3)
	ball.PrevRest = nil
	BallService.refresh(ball)
	return true
end

function BallService.tinyCup(ball: Ball, seconds: number, scale: number)
	ball.CupScale = scale
	ball.TinyCupUntil = os.clock() + seconds
	BallService.refresh(ball)
end

function BallService.start()
	registerGroups()
	folder = Instance.new("Folder")
	folder.Name = "GolfBalls"
	folder.Parent = workspace

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(setCharacterGroup)
	end)
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(setCharacterGroup)
		if p.Character then
			setCharacterGroup(p.Character)
		end
	end
	Players.PlayerRemoving:Connect(BallService.destroy)

	Net.event("Shoot").OnServerEvent:Connect(shoot)

	RunService.Heartbeat:Connect(function(dt)
		pcall(detectHits)
		for _, ball in balls do
			local ok, err = pcall(function()
				step(ball, dt)
			end)
			if not ok then
				warn("[UltimateGolf] ball step error:", err)
			end
		end
	end)
end

BallService.Groups = { Solid = GROUP_SOLID, Ghost = GROUP_GHOST, Characters = GROUP_CHARACTERS }

return BallService

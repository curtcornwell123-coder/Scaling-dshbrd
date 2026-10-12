--!strict
-- Server-authoritative golf balls. Roblox physics handles collisions; this
-- module adds rolling resistance, surfaces (sand / ice / boost), rest detection,
-- sinking (cup physics in CupPhysics), out-of-bounds resets and validated shots. Whoever owns a ball (a
-- match, a practice lane, the tutorial) supplies a Context with callbacks.

local AssetService = game:GetService("AssetService")
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
local CupPhysics = require(Shared:WaitForChild("CupPhysics"))

local CupHole = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("CupHole"))

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
	CupState: CupPhysics.State, -- running over / hanging on the lip of the cup
	RealCup: boolean, -- the cup is a real hole (CupHole): physics drops the ball in
	PrevPos: Vector3?, -- position last step (the cup test sweeps the path between)
	OOBY: number,
	Upgrades: { [string]: number },
	Frost: boolean, -- pending: applies to the next shot
	Gust: boolean,
	Magnet: boolean,
	ShotFrost: boolean, -- active for the shot in flight
	ShotMagnet: boolean,
	LastShot: number,
	MaxDistance: number, -- furthest projected distance this shot (practice drive scoring)
	LastBoost: number, -- server time the ball last touched a boost floor (drives the "Boost" attribute)
	LastHitBy: Player?,
	LastHitTime: number,
	LastHitEffect: string?,
	Data: { [string]: any }, -- owner scratch space
}

export type Loadout = { Skin: string, Trail: string, Knockout: string, Arrow: string, Serial: number? }

local HIT_SPEED = 14 -- relative speed that counts as a hit
local KNOCKOUT_WINDOW = 5 -- seconds after a hit in which going out of bounds is a knockout

local GROUP_SOLID = "GolfBalls"
local GROUP_GHOST = "GolfGhostBalls"
local GROUP_CHARACTERS = "GolfCharacters"
-- While Tiny Cup is on, a ball moves to the matching group that also stands on cup lids.
local GROUP_SOLID_TINY = "GolfBallsTiny"
local GROUP_GHOST_TINY = "GolfGhostBallsTiny"
local GROUP_LID = CupHole.LidGroup
local CAPTURE_DROP = 0.3 -- centre this far below the rim inside a real cup = holed (it can't climb out)

local balls: { [Player]: Ball } = {}
local folder: Folder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function registerGroups()
	for _, g in { GROUP_SOLID, GROUP_GHOST, GROUP_CHARACTERS, GROUP_SOLID_TINY, GROUP_GHOST_TINY, GROUP_LID } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(g)
		end)
	end
	local function set(a: string, b: string, on: boolean)
		PhysicsService:CollisionGroupSetCollidable(a, b, on)
	end
	set(GROUP_CHARACTERS, GROUP_CHARACTERS, true)
	-- Solid balls hit each other; ghost balls pass through every ball; no ball hits characters.
	for _, solid in { GROUP_SOLID, GROUP_SOLID_TINY } do
		set(solid, GROUP_CHARACTERS, false)
		for _, other in { GROUP_SOLID, GROUP_SOLID_TINY } do
			set(solid, other, true)
		end
		for _, ghost in { GROUP_GHOST, GROUP_GHOST_TINY } do
			set(solid, ghost, false)
		end
	end
	for _, ghost in { GROUP_GHOST, GROUP_GHOST_TINY } do
		set(ghost, GROUP_CHARACTERS, false)
		for _, other in { GROUP_GHOST, GROUP_GHOST_TINY } do
			set(ghost, other, false)
		end
	end
	-- Cup lids hold up Tiny-Cup balls and feet only (default queries go straight through).
	set(GROUP_LID, "Default", false)
	set(GROUP_LID, GROUP_SOLID, false)
	set(GROUP_LID, GROUP_GHOST, false)
	set(GROUP_LID, GROUP_SOLID_TINY, true)
	set(GROUP_LID, GROUP_GHOST_TINY, true)
	set(GROUP_LID, GROUP_CHARACTERS, true)
end

local function isGhost(part: BasePart): boolean
	return part.CollisionGroup == GROUP_GHOST or part.CollisionGroup == GROUP_GHOST_TINY
end

-- Tiny Cup on/off: the ball stands on cup lids while it lasts.
local function setTiny(ball: Ball, on: boolean)
	local ghost = isGhost(ball.Part)
	ball.Part.CollisionGroup = if on then (if ghost then GROUP_GHOST_TINY else GROUP_SOLID_TINY) else (if ghost then GROUP_GHOST else GROUP_SOLID)
	CupPhysics.reset(ball.CupState)
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
	Skins.apply(part, loadout and loadout.Skin, loadout and loadout.Serial)
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
		CupState = CupPhysics.newState(),
		RealCup = opts.Cup ~= nil and CupHole.lidAt(opts.Cup) ~= nil,
		PrevPos = nil,
		OOBY = opts.OOBY,
		Upgrades = upgrades,
		Frost = false,
		Gust = false,
		Magnet = false,
		ShotFrost = false,
		ShotMagnet = false,
		LastShot = 0,
		MaxDistance = 0,
		LastBoost = 0,
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
	ball.PrevPos = nil
	CupPhysics.reset(ball.CupState)
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

-- Hides a holed ball where it lies: the ball and its printed plates fade, then it stops colliding.
local function fadeOut(part: BasePart, seconds: number)
	part.Anchored = true
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("LayerCollector") then
			d.Enabled = false
		end
	end
	TweenService:Create(part, info, { Transparency = 1 }):Play()
	task.delay(seconds, function()
		part.CanCollide = false
	end)
end

local function sink(ball: Ball)
	ball.Sunk = true
	ball.AtRest = true
	local part = ball.Part
	local cup = ball.Cup :: Vector3
	ball.PrevPos = nil
	local r = Config.Ball.Diameter / 2
	if CupHole.lidAt(cup) then
		-- A real hole: nothing is moved by script - physics carries the ball down and it rattles
		-- to rest on the bottom, as on a real green (a Tiny-Cup ball judged on the lid drops
		-- through it once it's back in its normal group). It sits in the cup for a moment, then
		-- fades where it lies.
		if ball.CupScale < 1 then
			setTiny(ball, false)
			local toCup = Vector3.new(cup.X - part.Position.X, 0, cup.Z - part.Position.Z)
			part.AssemblyLinearVelocity = toCup * 4 + Vector3.new(0, -2, 0)
		end
		task.delay(1.8, function()
			if part.Parent and ball.Sunk then
				fadeOut(part, 0.35)
			end
		end)
	else
		-- Painted cup (no hole to fall into): over the centre and dipping, then down and away.
		part.Anchored = true
		part.AssemblyLinearVelocity = Vector3.zero
		part.CanCollide = false
		local lip = Vector3.new(cup.X, cup.Y + r - 0.3, cup.Z)
		TweenService:Create(part, TweenInfo.new(0.1, Enum.EasingStyle.Linear), { CFrame = CFrame.new(lip) }):Play()
		task.delay(0.1, function()
			if not part.Parent then
				return
			end
			TweenService:Create(part, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(cup - Vector3.new(0, 1.2, 0)),
				Transparency = 1,
			}):Play()
		end)
	end
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

-- The ball ran over (or round) the cup and out again: everyone sees the lip-out.
local function lipOut(ball: Ball, at: Vector3)
	Net.event("Fx"):FireAllClients("lipOut", { Position = at, Player = ball.Player })
end

-- At cup level: is the ball inside the cup (resting) or hanging over its lip?
local function cupContact(ball: Ball, pos: Vector3): ("in" | "lip")?
	local cup = ball.Cup
	if not cup or math.abs(pos.Y - (cup.Y + Config.Ball.Diameter / 2)) >= 1.4 then
		return nil
	end
	local R = Config.Physics.CupRadius * ball.CupScale
	local d = Vector2.new(cup.X - pos.X, cup.Z - pos.Z).Magnitude
	return if d < R then "in" elseif d < R + CupPhysics.lipZone(R) then "lip" else nil
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
		setTiny(ball, false)
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
		-- A resting ball inside the cup (e.g. Tiny Cup just wore off) drops in; one left
		-- hanging over the lip wakes up and tips in.
		local contact = cupContact(ball, pos)
		if contact == "in" then
			sink(ball)
			return
		end
		-- Hold still unless something (a spinner, another ball, an ability) shoves it.
		if vel.Magnitude > 3.5 or not grounded or contact == "lip" then
			ball.AtRest = false
			ball.RestTimer = 0
			ball.MovingTime = 0
			BallService.refresh(ball)
		else
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			ball.PrevPos = pos
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
			local inst = hit.Instance
			local dir = inst:GetAttribute("BoostDir")
			if typeof(dir) == "Vector3" and dir.Magnitude > 0 then
				local target = dir.Unit * P.BoostSpeed
				if horizontal:Dot(dir.Unit) < P.BoostSpeed then
					-- Jump launch lanes pull harder (BoostRate) so any ball reaches launch speed.
					local rate = inst:GetAttribute("BoostRate")
					horizontal = horizontal:Lerp(target, math.clamp(dt * (if type(rate) == "number" then rate else 8), 0, 1))
					speed = horizontal.Magnitude
					decel = 0
				end
				-- Clients play the boost effect when this attribute changes.
				local now = workspace:GetServerTimeNow()
				if now - ball.LastBoost > 0.8 then
					ball.LastBoost = now
					part:SetAttribute("Boost", now)
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
		end
		part.AssemblyLinearVelocity = Vector3.new(horizontal.X, vel.Y, horizontal.Z)
	end

	-- The cup. A real hole (CupHole): physics drops the ball in, or it hits the far rim and
	-- hops out / lips out; a ball whose centre gets below the rim inside the cup can't climb
	-- out and is holed. A slow ball hanging half over the rim is drawn in (CupPhysics.lip).
	-- A Tiny-Cup ball rides the cup's lid and, like a painted cup, is judged on the flat
	-- (CupPhysics.step: drop speed by line, rim hop, lip). Low over the green only.
	local onLip = false
	local cup = ball.Cup
	local prev = ball.PrevPos
	ball.PrevPos = pos
	if cup then
		local height = pos.Y - (cup.Y + Config.Ball.Diameter / 2)
		local x1, z1 = pos.X - cup.X, pos.Z - cup.Z
		local d2 = x1 * x1 + z1 * z1
		local state = ball.CupState
		if ball.RealCup and ball.CupScale >= 1 then
			local R = P.CupRadius
			if d2 < R * R and pos.Y < cup.Y - CAPTURE_DROP then
				sink(ball)
				return
			end
			if d2 < R * R and height < 0.6 then
				state.Pass = 1 -- over the hole, low enough to dip into it
			elseif state.Pass and d2 > (R + 0.4) * (R + 0.4) then
				state.Pass = nil
				lipOut(ball, Vector3.new(pos.X, cup.Y + 0.1, pos.Z))
			end
			if height > -1.4 and height < 0.9 then
				local vx, vz, lip = CupPhysics.lip(state, x1, z1, horizontal.X, horizontal.Z, grounded, dt, os.clock(), R)
				onLip = lip
				if vx ~= horizontal.X or vz ~= horizontal.Z then
					part.AssemblyLinearVelocity = Vector3.new(vx, part.AssemblyLinearVelocity.Y, vz)
				end
			end
		elseif height > -1.4 and height < 0.9 and d2 < 400 then
			local from = prev or pos
			local R = P.CupRadius * ball.CupScale
			local sunk, vx, vz, hop, lip = CupPhysics.step(state, from.X - cup.X, from.Z - cup.Z, x1, z1, horizontal.X, horizontal.Z, grounded, dt, os.clock(), R)
			if sunk then
				sink(ball)
				return
			end
			onLip = lip
			if hop > 0 or vx ~= horizontal.X or vz ~= horizontal.Z then
				local vy = part.AssemblyLinearVelocity.Y
				if hop > 0 then
					vy = math.max(vy, 0) + hop
					lipOut(ball, pos)
				end
				part.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
			end
		else
			CupPhysics.reset(state)
		end
	end

	if ball.Context.Tick then
		ball.Context.Tick(ball, dt)
	end

	local total = part.AssemblyLinearVelocity.Magnitude
	if grounded and total < P.RestSpeed and not onLip then
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
		if not b.Sunk and b.Part.Parent and (b.Part.CollisionGroup == GROUP_SOLID or b.Part.CollisionGroup == GROUP_SOLID_TINY) then
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
	setTiny(ball, scale < 1)
	BallService.refresh(ball)
end

-- The dimpled ball mesh, loaded once in the background (a web call). The group's copy is
-- tried first when the game belongs to a group, otherwise the owner's copy; whichever
-- loads is shared with clients (id + native size) and Skins fits every ball from it.
local function loadBallMesh()
	local ids = Config.Ball.MeshIds
	local order: { string } = if game.CreatorType == Enum.CreatorType.Group then { ids.Group, ids.User } else { ids.User, ids.Group }
	task.spawn(function()
		local last: any = nil
		for _, id in order do
			if id ~= "" then
				local ok, result = pcall(function()
					return AssetService:CreateMeshPartAsync(id)
				end)
				if ok and result then
					local part = result :: MeshPart
					ReplicatedStorage:SetAttribute("BallMeshId", id)
					ReplicatedStorage:SetAttribute("BallMeshSize", part.MeshSize)
					part:Destroy()
					return
				end
				last = result
			end
		end
		warn("[UltimateGolf] golf ball mesh unavailable, using smooth balls:", last)
	end)
end

function BallService.start()
	registerGroups()
	loadBallMesh()
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

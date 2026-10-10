-- Merge A Egg: the Golem King, boss of the Cave.
-- Spawns in the cave arena on a timer. Players bonk it with bats while dodging
-- telegraphed ground slams and thrown rocks. When it falls, a Boss Egg appears in
-- the middle: everyone who fought can claim one per day (it hatches the Cave King).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Boss = {}

local ctx
local Config
local Models
local Net
local World
local Eggs
local Economy

local rng = Random.new()
local active = nil
local nextSpawnAt = 0
local SPEAKER_COLOR = Color3.fromRGB(255, 140, 60)
local WALK_SPEED = 7
local HIT_RADIUS = 11

local function say(line: string)
	Net.announce(`{Config.Boss.name}: {line}`, SPEAKER_COLOR)
end

local function playersNear(center: Vector3, radius: number)
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
			if flat.Magnitude <= radius then
				table.insert(list, { player = player, root = root, offset = flat })
			end
		end
	end
	return list
end

local function knock(entry, power: number)
	local dir = if entry.offset.Magnitude > 0.1 then entry.offset.Unit else Vector3.new(0, 0, 1)
	Economy.grantGrace(entry.player, 2)
	local humanoid = entry.root.Parent and entry.root.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(Config.Boss.hitDamage)
	end
	Net.fx(entry.player, "Knockback", dir * power + Vector3.new(0, 50, 0))
	if Eggs.getCarry(entry.player) then
		Eggs.drop(entry.player, "bonked")
	end
end

local function telegraph(position: Vector3, radius: number, duration: number): BasePart
	local ring = Models.part({
		Name = "Telegraph",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1, 1),
		CFrame = CFrame.new(position.X, position.Y + 0.25, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 50, 50),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Parent = workspace,
	})
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, radius * 2, radius * 2) }):Play()
	return ring
end

local function slam()
	local b = active
	local center = b.pos
	local ring = telegraph(center, Config.Boss.slamRadius, Config.Boss.telegraphTime)
	task.wait(Config.Boss.telegraphTime)
	ring:Destroy()
	if active ~= b then
		return
	end
	Net.fxAll("BossSlam", center, Config.Boss.slamRadius)
	for _, entry in playersNear(center, Config.Boss.slamRadius) do
		knock(entry, 90)
	end
end

local function throwRock()
	local b = active
	local targets = playersNear(World.arena.center, 80)
	if #targets == 0 then
		return
	end
	local pick = targets[rng:NextInteger(1, #targets)]
	local landing = Vector3.new(pick.root.Position.X, World.arena.center.Y, pick.root.Position.Z)
	local ring = telegraph(landing, 8, Config.Boss.telegraphTime)
	local rock = Models.part({
		Name = "Rock",
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(b.pos + Vector3.new(0, 22, 0)),
		Color = Color3.fromRGB(100, 95, 92),
		Material = Enum.Material.Slate,
		Parent = workspace,
	})
	TweenService:Create(rock, TweenInfo.new(Config.Boss.telegraphTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(landing + Vector3.new(0, 2.5, 0)) * CFrame.Angles(2, 1, 3),
	}):Play()
	task.wait(Config.Boss.telegraphTime)
	ring:Destroy()
	if active ~= b then
		rock:Destroy()
		return
	end
	Net.fxAll("BossSlam", landing, 8)
	for _, entry in playersNear(landing, 8) do
		local offset = Vector3.new(entry.root.Position.X - landing.X, 0, entry.root.Position.Z - landing.Z)
		knock({ player = entry.player, root = entry.root, offset = offset }, 70)
	end
	task.delay(1.5, function()
		TweenService:Create(rock, TweenInfo.new(0.6), { Transparency = 1, Size = Vector3.one }):Play()
		task.wait(0.7)
		rock:Destroy()
	end)
end

local function updateBar()
	local b = active
	if not b then
		return
	end
	local ratio = math.clamp(b.health / b.maxHealth, 0, 1)
	b.bar.Size = UDim2.fromScale(ratio, 1)
	b.barText.Text = `{Config.Boss.name}  {math.ceil(b.health)}/{b.maxHealth}`
end

local function despawn(defeated: boolean)
	local b = active
	if not b then
		return
	end
	active = nil
	nextSpawnAt = os.clock() + Config.Boss.interval
	workspace:SetAttribute("BossActive", false)
	b.heartbeat:Disconnect()
	if defeated then
		say(Config.Boss.taunts.defeated)
		Net.announce("⚔️ The Golem King has fallen! Fighters can claim a Boss Egg in the Cave!", Color3.fromRGB(255, 220, 90))
		Eggs.spawnBossEgg(World.arena.center + Vector3.new(0, 0.5, 0), b.contributors, Config.Boss.eggLifetime)
		Net.fxAll("BossDefeated", b.pos)
	else
		say(Config.Boss.taunts.win)
	end
	-- Sinks into the floor, then disappears.
	task.spawn(function()
		for i = 1, 30 do
			b.model:PivotTo(CFrame.new(b.pos - Vector3.new(0, i * b.rootHeight * 0.15, 0)) * b.model:GetPivot().Rotation)
			task.wait(1 / 15)
		end
		b.model:Destroy()
	end)
end

function Boss.spawn()
	if active or not World.arena then
		return
	end
	local model = Models.golemKing()
	model.Name = "GolemKing"
	local center = World.arena.center
	local rootHeight = (model.PrimaryPart :: BasePart).Size.Y / 2
	-- Stays anchored; the server moves it with PivotTo (its pivot is at its feet).
	model:PivotTo(CFrame.new(center))
	local root = model.PrimaryPart :: BasePart

	-- Health bar.
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromScale(16, 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, rootHeight + 4, 0)
	gui.MaxDistance = 200
	gui.LightInfluence = 0
	gui.Parent = root
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	back.Parent = gui
	Instance.new("UICorner").Parent = back
	local backStroke = Instance.new("UIStroke")
	backStroke.Thickness = 3
	backStroke.Parent = back
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	bar.Parent = back
	Instance.new("UICorner").Parent = bar
	local barText = Instance.new("TextLabel")
	barText.Size = UDim2.fromScale(1, 1)
	barText.BackgroundTransparency = 1
	barText.Font = Enum.Font.FredokaOne
	barText.TextScaled = true
	barText.TextColor3 = Color3.new(1, 1, 1)
	barText.ZIndex = 2
	barText.Parent = back
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2
	textStroke.Parent = barText

	model.Parent = workspace

	local playerCount = #Players:GetPlayers()
	local maxHealth = Config.Boss.baseHealth + math.max(0, playerCount - 1) * Config.Boss.healthPerPlayer
	local b = {
		model = model,
		root = root,
		pos = center,
		rootHeight = rootHeight,
		health = maxHealth,
		maxHealth = maxHealth,
		contributors = {},
		spawnedAt = os.clock(),
		nextAttack = os.clock() + 4,
		halfTaunted = false,
		bar = bar,
		barText = barText,
		facing = Vector3.new(0, 0, -1),
		attacking = false,
	}
	active = b
	workspace:SetAttribute("BossActive", true)
	updateBar()
	say(Config.Boss.taunts.spawn)
	Net.announce("⚔️ The Golem King awakened in the Cave! Grab your bat!", Color3.fromRGB(255, 120, 60))

	b.heartbeat = RunService.Heartbeat:Connect(function(dt)
		if active ~= b then
			return
		end
		local now = os.clock()
		if now - b.spawnedAt > Config.Boss.duration then
			despawn(false)
			return
		end
		local near = playersNear(World.arena.center, World.arena.radius + 6)
		if #near > 0 and not b.attacking then
			local closest = near[1]
			for _, entry in near do
				if (entry.root.Position - b.pos).Magnitude < (closest.root.Position - b.pos).Magnitude then
					closest = entry
				end
			end
			-- Stay on the dungeon floor: only move across X/Z.
			local goal = Vector3.new(closest.root.Position.X, b.pos.Y, closest.root.Position.Z)
			local delta = goal - b.pos
			if delta.Magnitude > 9 then
				b.pos += delta.Unit * math.min(delta.Magnitude - 9, WALK_SPEED * dt)
			end
			local fromCenter = (b.pos - World.arena.center) * Vector3.new(1, 0, 1)
			if fromCenter.Magnitude > World.arena.radius - 8 then
				b.pos = World.arena.center + fromCenter.Unit * (World.arena.radius - 8)
			end
			if delta.Magnitude > 0.1 then
				b.facing = delta.Unit
			end
		end
		b.model:PivotTo(CFrame.lookAt(b.pos, b.pos + Vector3.new(b.facing.X, 0, b.facing.Z)))

		if now >= b.nextAttack and not b.attacking then
			b.nextAttack = now + Config.Boss.attackInterval
			local inArena = playersNear(World.arena.center, 90)
			if #inArena > 0 then
				b.attacking = true
				task.spawn(function()
					if #playersNear(b.pos, Config.Boss.slamRadius) > 0 and rng:NextNumber() < 0.6 then
						slam()
					else
						throwRock()
					end
					b.attacking = false
				end)
			end
		end
	end)
end

local function damage(player: Player, amount: number, point: Vector3)
	local b = active
	if not b or amount <= 0 then
		return
	end
	b.health -= amount
	b.contributors[player] = true
	Net.fxAll("BossHit", point)
	updateBar()
	if not b.halfTaunted and b.health <= b.maxHealth / 2 then
		b.halfTaunted = true
		say(Config.Boss.taunts.half)
	end
	if b.health <= 0 then
		despawn(true)
	end
end

-- Battle pets of everyone near the arena attack on a timer.
local function petAttackLoop()
	while true do
		task.wait(Config.PetAttackInterval)
		local b = active
		if b then
			local target = b.pos + Vector3.new(0, b.rootHeight, 0)
			for _, entry in playersNear(World.arena.center, Config.PetAttackRange) do
				local amount = Economy.followerDamage(entry.player)
				if amount > 0 and active == b then
					Net.fxAll("PetAttack", entry.player, target)
					damage(entry.player, amount, target)
				end
			end
		end
	end
end

-- Called by bat swings. Returns true if the boss was hit.
function Boss.hit(player: Player, strikePoint: Vector3): boolean
	local b = active
	if not b then
		return false
	end
	local center = b.pos + Vector3.new(0, b.rootHeight, 0)
	if (Vector3.new(strikePoint.X, center.Y, strikePoint.Z) - center).Magnitude > HIT_RADIUS then
		return false
	end
	damage(player, Config.BatBossDamage, strikePoint)
	return true
end

function Boss.isActive(): boolean
	return active ~= nil
end

function Boss.init(context)
	ctx = context
	Config = ctx.Config
	Models = ctx.Models
	Net = ctx.Net
	World = ctx.World
	Eggs = ctx.Eggs
	Economy = ctx.Economy
end

function Boss.start()
	task.spawn(petAttackLoop)
	nextSpawnAt = os.clock() + 120
	workspace:SetAttribute("BossActive", false)
	task.spawn(function()
		while true do
			task.wait(5)
			if not active and os.clock() >= nextSpawnAt and #Players:GetPlayers() > 0 then
				Boss.spawn()
			end
		end
	end)
end

return Boss

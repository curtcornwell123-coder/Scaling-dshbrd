-- Merge A Egg: biome guardians. One giant animal per nest cluster.
-- Day: asleep until an egg is stolen nearby. Night: awake and wandering near the nest.
-- Further biomes have faster guardians with bigger aggro ranges.
-- Catching a carrier inside its biome makes them drop the egg.

local RunService = game:GetService("RunService")

local Guardians = {}

local ctx
local Config
local Models
local Net
local World
local Eggs
local Economy

local guardians = {}
local folder: Folder
local rng = Random.new()

local GUARDIAN_SCALE = 2.6
local WAKE_SECONDS = 20
local ARRIVE_DISTANCE = 2

local function setStatus(g, text: string)
	if g.statusText ~= text then
		g.statusText = text
		g.statusLabel.Text = text
	end
end

local function createGuardian(biome, clusterIndex: number, cluster)
	local def = Config.PetsByName[biome.def.guardian]
	local model = Models.pet(def, { scale = GUARDIAN_SCALE, rarityFx = false })
	model.Name = `{biome.def.guardian}Guardian`
	local height = model:GetAttribute("Height") or 6
	local home = cluster.home
	local lift = (model.PrimaryPart :: BasePart).Size.Y / 2
	model:PivotTo(CFrame.lookAt(home, cluster.center) + Vector3.new(0, lift, 0))
	local root = Models.rigForPhysics(model)

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Position = root.Position
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.RigidityEnabled = true
	orient.CFrame = root.CFrame.Rotation
	orient.Parent = root

	local gui, label = Models.billboard(root, "💤", Color3.new(1, 1, 1), UDim2.fromScale(4, 2), Vector3.new(0, height / 2 + 2.5, 0), 120)
	gui.Name = "Status"
	model.Parent = folder
	root:SetNetworkOwner(nil)

	local g = {
		biome = biome,
		cluster = clusterIndex,
		model = model,
		root = root,
		align = align,
		orient = orient,
		home = home,
		lookAt = cluster.center,
		pos = home,
		rootHeight = root.Size.Y / 2,
		state = "sleep",
		target = nil,
		awakeUntil = 0,
		stunnedUntil = 0,
		stunReadyAt = 0,
		wanderTarget = nil,
		nextWander = 0,
		statusLabel = label,
		statusText = "💤",
		bob = rng:NextNumber(0, 10),
	}
	table.insert(guardians, g)
end

local function inZone(g, position: Vector3): boolean
	return math.abs(position.X) <= World.CORRIDOR_HALF and position.Z >= g.biome.zStart and position.Z <= g.biome.zEnd
end

local function speedOf(g): number
	local speed = Config.guardianSpeed(g.biome.index)
	if World.isNight() then
		speed *= 1 + Config.NightGuardianSpeedBonus
	end
	return speed
end

local function carrierRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Closest carrier inside this guardian's biome and within range.
local function findTarget(g, range: number): Player?
	local best, bestDist = nil, range
	for player in Eggs.getCarriers() do
		local root = carrierRoot(player)
		if root and inZone(g, root.Position) then
			local dist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(g.pos.X, 0, g.pos.Z)).Magnitude
			if dist < bestDist then
				best, bestDist = player, dist
			end
		end
	end
	return best
end

local function moveToward(g, goal: Vector3, speed: number, dt: number): number
	local flatGoal = Vector3.new(goal.X, g.home.Y, goal.Z)
	local delta = flatGoal - g.pos
	local dist = delta.Magnitude
	if dist > 0.05 then
		local step = math.min(dist, speed * dt)
		g.pos += delta.Unit * step
		g.facing = delta.Unit
	end
	-- Stay inside the biome.
	g.pos = Vector3.new(
		math.clamp(g.pos.X, -World.CORRIDOR_HALF + 4, World.CORRIDOR_HALF - 4),
		g.home.Y,
		math.clamp(g.pos.Z, g.biome.zStart + 4, g.biome.zEnd - 4)
	)
	return dist
end

local function catchPlayer(g, player: Player)
	local root = carrierRoot(player)
	Eggs.drop(player, "caught")
	if root then
		local away = (root.Position - g.pos) * Vector3.new(1, 0, 1)
		if away.Magnitude < 0.1 then
			away = Vector3.new(0, 0, -1)
		end
		Economy.grantGrace(player, 2)
		Net.fx(player, "Knockback", away.Unit * Config.GuardianKnockback + Vector3.new(0, 40, 0))
	end
	Net.fxAll("GuardianRoar", g.root.Position)
	g.target = nil
	g.state = "return"
end

local function update(g, dt: number, now: number)
	local night = World.isNight()
	local moving = false

	if now < g.stunnedUntil then
		setStatus(g, "💫")
	else
		-- Acquire or drop targets.
		if g.target then
			local carry = Eggs.getCarry(g.target)
			local root = carrierRoot(g.target)
			if not carry or not root or not inZone(g, root.Position) or not g.target.Parent then
				g.target = nil
				g.state = "return"
			end
		end
		if not g.target then
			local awake = night or now < g.awakeUntil
			local range = Config.guardianAggroRange(g.biome.index) * (if awake then 1 else 0.5)
			local found = findTarget(g, range)
			if found then
				g.target = found
				g.state = "chase"
				g.awakeUntil = now + WAKE_SECONDS
			end
		end

		if g.state == "chase" and g.target then
			setStatus(g, "❗")
			local root = carrierRoot(g.target)
			if root then
				local dist = moveToward(g, root.Position, speedOf(g), dt)
				moving = true
				if dist <= Config.GuardianCatchDistance + g.rootHeight * 0.4 then
					catchPlayer(g, g.target)
				end
			end
		elseif g.state == "return" then
			setStatus(g, "😤")
			local dist = moveToward(g, g.home, speedOf(g) * 0.6, dt)
			moving = true
			if dist <= ARRIVE_DISTANCE then
				g.state = if night then "wander" else "sleep"
				g.facing = (g.lookAt - g.home).Unit
			end
		elseif night then
			g.state = "wander"
			setStatus(g, "👀")
			if not g.wanderTarget or now >= g.nextWander then
				local angle = rng:NextNumber(0, math.pi * 2)
				local radius = rng:NextNumber(4, 22)
				g.wanderTarget = g.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				g.nextWander = now + rng:NextNumber(3, 6)
			end
			local dist = moveToward(g, g.wanderTarget, speedOf(g) * 0.3, dt)
			moving = dist > ARRIVE_DISTANCE
		else
			if g.state == "wander" then
				g.state = "return"
			else
				g.state = "sleep"
				setStatus(g, if now < g.awakeUntil then "❓" else "💤")
			end
		end
	end

	-- Walk bob and facing.
	if moving then
		g.bob += dt * 12
	end
	local hop = if moving then math.abs(math.sin(g.bob)) * 0.8 else 0
	local facing = g.facing or (g.lookAt - g.home).Unit
	local position = g.pos + Vector3.new(0, g.rootHeight + hop, 0)
	g.align.Position = position
	g.orient.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(facing.X, 0, facing.Z)).Rotation
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Called when an egg is stolen from a cluster: that guardian wakes and chases.
function Guardians.alert(biomeIndex: number, clusterIndex: number, player: Player)
	for _, g in guardians do
		if g.biome.index == biomeIndex and g.cluster == clusterIndex then
			g.awakeUntil = os.clock() + WAKE_SECONDS
			if os.clock() >= g.stunnedUntil then
				g.target = player
				g.state = "chase"
			end
		end
	end
end

-- Bat hit: stuns guardians in range (with a per-guardian cooldown). Returns how many.
function Guardians.hitNear(position: Vector3, radius: number): number
	local now = os.clock()
	local count = 0
	for _, g in guardians do
		local center = g.pos + Vector3.new(0, g.rootHeight, 0)
		if (center - position).Magnitude <= radius + g.rootHeight and now >= g.stunReadyAt then
			g.stunnedUntil = now + Config.BatGuardianStun
			g.stunReadyAt = now + Config.GuardianStunCooldown
			count += 1
		end
	end
	return count
end

function Guardians.init(context)
	ctx = context
	Config = ctx.Config
	Models = ctx.Models
	Net = ctx.Net
	World = ctx.World
	Eggs = ctx.Eggs
	Economy = ctx.Economy
end

function Guardians.start()
	folder = Instance.new("Folder")
	folder.Name = "Guardians"
	folder.Parent = workspace
	for _, biome in World.biomes do
		for ci, cluster in biome.clusters do
			createGuardian(biome, ci, cluster)
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, g in guardians do
			update(g, dt, now)
		end
	end)
end

return Guardians

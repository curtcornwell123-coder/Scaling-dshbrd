--!strict
--[[
	JunkyardBuilder
	Generates the Junkyard map template from Parts: a military-held scrapyard with one winding
	lane. The result follows exactly the same layout convention as hand-built maps (Waypoints,
	TowerSlots, BaseSpawn, PlayerSpawns, optional Camera), so MapService treats it like any other
	template. All coordinates are local to the template; MapService moves clones into place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PartFactory = require(script.Parent.PartFactory)

local Layout = Constants.MapLayout
local Military = Theme.Military

local GROUND_SIZE = Vector3.new(190, 1, 130)
local LANE_WIDTH = 9
local SLOT_SIZE = Vector3.new(6, 1, 6)

-- Lane centre line at ground height, from the robot gate to the enemy HQ.
local WAYPOINTS = {
	Vector3.new(-82, 0, -30),
	Vector3.new(-40, 0, -30),
	Vector3.new(-40, 0, 25),
	Vector3.new(10, 0, 25),
	Vector3.new(10, 0, -25),
	Vector3.new(50, 0, -25),
	Vector3.new(50, 0, 20),
	Vector3.new(74, 0, 20),
}

-- Numbered by placement priority: the AI fills slot 1 first.
local TOWER_SLOTS = {
	Vector3.new(30, 0, -13),
	Vector3.new(-28, 0, -5),
	Vector3.new(62, 0, -5),
	Vector3.new(-2, 0, 0),
	Vector3.new(-15, 0, 13),
	Vector3.new(30, 0, 8),
	Vector3.new(-60, 0, -42),
	Vector3.new(62, 0, 32),
}

local BASE_POSITION = Vector3.new(83, 0, 20)
local DECK_CENTER = Vector3.new(0, 6, 54)
local CAMERA_POSITION = Vector3.new(0, 96, 94)
local CAMERA_TARGET = Vector3.new(0, 0, -4)

local JunkyardBuilder = {}

local function buildLane(model: Model)
	local lane = Instance.new("Folder")
	lane.Name = "Lane"
	lane.Parent = model

	for index = 1, #WAYPOINTS - 1 do
		local from = WAYPOINTS[index]
		local to = WAYPOINTS[index + 1]
		local length = (to - from).Magnitude
		local center = (from + to) * 0.5
		local frame = CFrame.lookAt(center, to)

		PartFactory.part({
			name = "Road",
			size = Vector3.new(LANE_WIDTH, 0.2, length + LANE_WIDTH),
			cframe = frame + Vector3.new(0, 0.1, 0),
			color = Military.Gunmetal,
			material = Enum.Material.Asphalt,
			parent = lane,
		})
		-- Hazard stripes along both kerbs mark the lane edge the robots must follow.
		for _, side in { -1, 1 } do
			PartFactory.part({
				name = "Kerb",
				size = Vector3.new(0.5, 0.3, length + LANE_WIDTH),
				cframe = frame * CFrame.new(side * (LANE_WIDTH * 0.5 - 0.25), 0.15, 0),
				color = Military.Amber,
				material = Enum.Material.SmoothPlastic,
				canCollide = false,
				parent = lane,
			})
		end
	end
end

local function buildMarkers(model: Model)
	local waypoints = Instance.new("Folder")
	waypoints.Name = Layout.WAYPOINTS
	waypoints.Parent = model
	for index, position in WAYPOINTS do
		PartFactory.marker(Layout.WAYPOINT_PREFIX .. index, CFrame.new(position), Vector3.one, waypoints)
	end

	local slots = Instance.new("Folder")
	slots.Name = Layout.TOWER_SLOTS
	slots.Parent = model
	for index, position in TOWER_SLOTS do
		local slot = PartFactory.part({
			name = Layout.TOWER_SLOT_PREFIX .. index,
			size = SLOT_SIZE,
			cframe = CFrame.new(position + Vector3.new(0, SLOT_SIZE.Y * 0.5, 0)),
			color = Military.OliveDark,
			material = Enum.Material.Concrete,
			parent = slots,
		})
		slot.CanQuery = false
	end

	local baseSpawn = PartFactory.marker(
		Layout.BASE_SPAWN,
		CFrame.new(BASE_POSITION + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(14, 1, 12),
		model
	)
	baseSpawn.CanCollide = true

	local spawns = Instance.new("Folder")
	spawns.Name = Layout.PLAYER_SPAWNS
	spawns.Parent = model
	for index, x in { -15, -5, 5, 15 } do
		PartFactory.marker(
			"Spawn_" .. index,
			CFrame.lookAt(DECK_CENTER + Vector3.new(x, 0.5, 0), Vector3.new(x, DECK_CENTER.Y, 0)),
			Vector3.new(2, 1, 2),
			spawns
		)
	end

	PartFactory.marker(Layout.CAMERA, CFrame.lookAt(CAMERA_POSITION, CAMERA_TARGET), Vector3.one, model)
end

local function buildDeck(scenery: Folder)
	-- The observation deck is the players' side, so it carries the neon cyber accents.
	PartFactory.part({
		name = "Deck",
		size = Vector3.new(44, 1, 10),
		cframe = CFrame.new(DECK_CENTER),
		color = Theme.Colors.Panel,
		material = Enum.Material.DiamondPlate,
		parent = scenery,
	})
	for _, x in { -20, 20 } do
		PartFactory.part({
			name = "DeckLeg",
			size = Vector3.new(1.5, DECK_CENTER.Y, 1.5),
			cframe = CFrame.new(x, DECK_CENTER.Y * 0.5, DECK_CENTER.Z),
			color = Theme.Colors.Metal,
			material = Enum.Material.Metal,
			parent = scenery,
		})
	end
	PartFactory.neon("DeckRail", Vector3.new(44, 0.3, 0.3), CFrame.new(DECK_CENTER + Vector3.new(0, 1.6, -5)), Theme.Colors.Primary, scenery)
	PartFactory.neon("DeckTrim", Vector3.new(44, 0.2, 0.3), CFrame.new(DECK_CENTER + Vector3.new(0, 0.5, 5)), Theme.Colors.Secondary, scenery)
	-- Invisible guard rail so nobody walks off the front edge.
	local guard = PartFactory.part({
		name = "DeckGuard",
		size = Vector3.new(44, 6, 1),
		cframe = CFrame.new(DECK_CENTER + Vector3.new(0, 3, -5.5)),
		color = Theme.Colors.Primary,
		transparency = 1,
		parent = scenery,
	})
	guard.CanQuery = false
end

local function buildRobotGate(scenery: Folder)
	local gate = WAYPOINTS[1]
	for _, side in { -1, 1 } do
		PartFactory.neon("GatePost", Vector3.new(1, 12, 1), CFrame.new(gate + Vector3.new(0, 6, side * (LANE_WIDTH * 0.5 + 1))), Theme.Colors.Primary, scenery)
	end
	PartFactory.neon("GateBeam", Vector3.new(1, 1, LANE_WIDTH + 3), CFrame.new(gate + Vector3.new(0, 12, 0)), Theme.Colors.Secondary, scenery)
end

local function scrapHeap(scenery: Folder, center: Vector3, seed: number)
	local rng = Random.new(seed)
	local rust = { Color3.fromRGB(110, 66, 40), Color3.fromRGB(84, 70, 58), Military.Steel, Military.Gunmetal }
	for index = 1, 7 do
		local size = Vector3.new(rng:NextNumber(2, 6), rng:NextNumber(1, 3.5), rng:NextNumber(2, 6))
		local offset = Vector3.new(rng:NextNumber(-4, 4), size.Y * 0.5 + (index - 1) * 0.6, rng:NextNumber(-4, 4))
		PartFactory.part({
			name = "Scrap",
			size = size,
			cframe = CFrame.new(center + offset)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
			color = rust[rng:NextInteger(1, #rust)],
			material = Enum.Material.CorrodedMetal,
			parent = scenery,
		})
	end
end

local function ammoCrates(scenery: Folder, center: Vector3)
	for index, offset in { Vector3.new(0, 1, 0), Vector3.new(3.2, 1, 0.4), Vector3.new(1.4, 3, 0.2), Vector3.new(-2.8, 1, 1.6) } do
		PartFactory.part({
			name = "AmmoCrate",
			size = Vector3.new(3, 2, 2.2),
			cframe = CFrame.new(center + offset) * CFrame.Angles(0, index * 0.3, 0),
			color = if index % 2 == 0 then Military.Olive else Military.OliveDark,
			material = Enum.Material.WoodPlanks,
			parent = scenery,
		})
	end
end

local function fuelBarrels(scenery: Folder, center: Vector3)
	for index, offset in { Vector3.new(0, 0, 0), Vector3.new(2.2, 0, 0.5), Vector3.new(1, 0, 2.1) } do
		local barrel = PartFactory.part({
			name = "Barrel",
			size = Vector3.new(3, 2, 2),
			cframe = CFrame.new(center + offset + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color = if index == 2 then Military.AlertRed else Military.Olive,
			material = Enum.Material.Metal,
			shape = Enum.PartType.Cylinder,
			parent = scenery,
		})
		barrel.CanCollide = true
	end
end

local function barbedWire(scenery: Folder, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local frame = CFrame.lookAt((from + to) * 0.5, to)
	for _, height in { 0.8, 1.6 } do
		PartFactory.part({
			name = "Wire",
			size = Vector3.new(0.12, 0.12, length),
			cframe = frame + Vector3.new(0, height, 0),
			color = Military.Steel,
			material = Enum.Material.Metal,
			canCollide = false,
			parent = scenery,
		})
	end
	local posts = math.max(2, math.floor(length / 6))
	for index = 0, posts do
		PartFactory.part({
			name = "WirePost",
			size = Vector3.new(0.3, 2.2, 0.3),
			cframe = CFrame.new(from:Lerp(to, index / posts) + Vector3.new(0, 1.1, 0)),
			color = Military.OliveDark,
			material = Enum.Material.Wood,
			parent = scenery,
		})
	end
end

local function watchtower(scenery: Folder, center: Vector3)
	for _, corner in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
		PartFactory.part({
			name = "TowerLeg",
			size = Vector3.new(0.6, 12, 0.6),
			cframe = CFrame.new(center + corner + Vector3.new(0, 6, 0)),
			color = Military.OliveDark,
			material = Enum.Material.Wood,
			parent = scenery,
		})
	end
	PartFactory.part({
		name = "TowerFloor",
		size = Vector3.new(6, 0.6, 6),
		cframe = CFrame.new(center + Vector3.new(0, 12, 0)),
		color = Military.Olive,
		material = Enum.Material.WoodPlanks,
		parent = scenery,
	})
	PartFactory.part({
		name = "TowerRoof",
		size = Vector3.new(7, 0.6, 7),
		cframe = CFrame.new(center + Vector3.new(0, 16, 0)),
		color = Military.OliveDark,
		material = Enum.Material.CorrodedMetal,
		parent = scenery,
	})
	PartFactory.neon("Searchlight", Vector3.new(1.2, 1.2, 1.2), CFrame.new(center + Vector3.new(0, 13.4, -2.6)), Military.Amber, scenery).Shape =
		Enum.PartType.Ball
end

local function camoNet(scenery: Folder, center: Vector3, size: Vector2)
	local net = PartFactory.part({
		name = "CamoNet",
		size = Vector3.new(size.X, 0.15, size.Y),
		cframe = CFrame.new(center + Vector3.new(0, 5, 0)) * CFrame.Angles(0.08, 0, -0.05),
		color = Military.Olive,
		material = Enum.Material.Fabric,
		transparency = 0.25,
		canCollide = false,
		parent = scenery,
	})
	net.CastShadow = true
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		PartFactory.part({
			name = "NetPole",
			size = Vector3.new(0.3, 5, 0.3),
			cframe = CFrame.new(center + Vector3.new(corner.X * size.X * 0.45, 2.5, corner.Z * size.Y * 0.45)),
			color = Military.OliveDark,
			material = Enum.Material.Wood,
			parent = scenery,
		})
	end
end

local function perimeter(scenery: Folder)
	-- Fence posts with red warning lights ring the yard.
	local halfX = GROUND_SIZE.X * 0.5 - 1
	local halfZ = GROUND_SIZE.Z * 0.5 - 1
	local step = 19
	local function post(position: Vector3)
		PartFactory.part({
			name = "FencePost",
			size = Vector3.new(0.6, 6, 0.6),
			cframe = CFrame.new(position + Vector3.new(0, 3, 0)),
			color = Military.Steel,
			material = Enum.Material.Metal,
			parent = scenery,
		})
		PartFactory.neon("FenceLight", Vector3.new(0.5, 0.5, 0.5), CFrame.new(position + Vector3.new(0, 6.3, 0)), Military.AlertRed, scenery)
	end
	for x = -halfX, halfX, step do
		post(Vector3.new(x, 0, -halfZ))
		post(Vector3.new(x, 0, halfZ))
	end
	for z = -halfZ + step, halfZ - step, step do
		post(Vector3.new(-halfX, 0, z))
		post(Vector3.new(halfX, 0, z))
	end
end

function JunkyardBuilder.build(): Model
	local model = Instance.new("Model")
	model.Name = "Junkyard"

	PartFactory.part({
		name = "Ground",
		size = GROUND_SIZE,
		cframe = CFrame.new(0, -GROUND_SIZE.Y * 0.5, 0),
		color = Military.Dirt,
		material = Enum.Material.Ground,
		parent = model,
	})

	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = model

	buildLane(model)
	buildMarkers(model)
	buildDeck(scenery)
	buildRobotGate(scenery)
	perimeter(scenery)

	scrapHeap(scenery, Vector3.new(-72, 0, 22), 11)
	scrapHeap(scenery, Vector3.new(-62, 0, 48), 23)
	scrapHeap(scenery, Vector3.new(76, 0, -44), 37)
	scrapHeap(scenery, Vector3.new(28, 0, -50), 41)
	scrapHeap(scenery, Vector3.new(-14, 0, -50), 53)
	ammoCrates(scenery, Vector3.new(-32, 0, 42))
	ammoCrates(scenery, Vector3.new(36, 0, 42))
	camoNet(scenery, Vector3.new(-32, 0, 42), Vector2.new(12, 10))
	fuelBarrels(scenery, Vector3.new(-50, 0, -52))
	fuelBarrels(scenery, Vector3.new(66, 0, -56))
	fuelBarrels(scenery, Vector3.new(-86, 0, -8))
	barbedWire(scenery, Vector3.new(68, 0, 36), Vector3.new(90, 0, 36))
	barbedWire(scenery, Vector3.new(68, 0, 4), Vector3.new(90, 0, 4))
	watchtower(scenery, Vector3.new(84, 0, -14))

	-- Hand-built maps pivot wherever the author leaves them; the generated one pivots at its origin.
	model.WorldPivot = CFrame.identity
	return model
end

return JunkyardBuilder

--!strict
--[[
	TestYardBuilder
	Generates the Test Realm's outdoor training yard: a grass yard with a sample lane, concrete
	cover walls, training dummies, tower slots, and a viewing deck with the RETURN pad. It follows
	the same map layout convention as every other map (Waypoints, TowerSlots, BaseSpawn,
	PlayerSpawns, Camera), so MapService loads it like any template.

	Players are not frozen in Test Realm matches: they can walk the deck and step on the RETURN pad
	(tagged TestRealmReturn) to go back to the main game.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PartFactory = require(script.Parent.PartFactory)

local Layout = Constants.MapLayout
local World = Theme.World
local Military = Theme.Military

local GROUND_SIZE = Vector3.new(170, 1, 120)
local LANE_WIDTH = 9

local WAYPOINTS = {
	Vector3.new(-72, 0, -20),
	Vector3.new(-10, 0, -20),
	Vector3.new(-10, 0, 10),
	Vector3.new(66, 0, 10),
}

local TOWER_SLOTS = {
	Vector3.new(20, 0, -2),
	Vector3.new(-30, 0, -6),
	Vector3.new(44, 0, 24),
	Vector3.new(4, 0, 24),
	Vector3.new(-40, 0, -34),
	Vector3.new(30, 0, -4),
	Vector3.new(54, 0, -6),
	Vector3.new(-22, 0, 24),
}

local BASE_POSITION = Vector3.new(75, 0, 10)
local DECK_CENTER = Vector3.new(0, 4, 46)
local CAMERA_POSITION = Vector3.new(0, 80, 86)
local CAMERA_TARGET = Vector3.new(0, 0, 0)

local TestYardBuilder = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
	return PartFactory.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		material = material,
		canCollide = if collide == nil then true else collide,
		parent = parent,
	})
end

local function buildLane(model: Model)
	local lane = Instance.new("Folder")
	lane.Name = "Lane"
	lane.Parent = model
	for index = 1, #WAYPOINTS - 1 do
		local from = WAYPOINTS[index]
		local to = WAYPOINTS[index + 1]
		local length = (to - from).Magnitude
		local frame = CFrame.lookAt((from + to) * 0.5, to)
		block(lane, "Road", Vector3.new(LANE_WIDTH, 0.2, length + LANE_WIDTH), frame + Vector3.new(0, 0.1, 0), World.ConcreteMid, Enum.Material.Concrete)
		for _, side in { -1, 1 } do
			block(lane, "Kerb", Vector3.new(0.5, 0.3, length + LANE_WIDTH), frame * CFrame.new(side * (LANE_WIDTH * 0.5 - 0.25), 0.15, 0), World.Hazard, Enum.Material.SmoothPlastic, false)
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
		local slot = block(slots, Layout.TOWER_SLOT_PREFIX .. index, Vector3.new(6, 1, 6), CFrame.new(position + Vector3.new(0, 0.5, 0)), World.ConcreteMid, Enum.Material.Concrete)
		slot.CanQuery = false
	end
	local baseSpawn = PartFactory.marker(Layout.BASE_SPAWN, CFrame.new(BASE_POSITION + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(14, 1, 12), model)
	baseSpawn.CanCollide = true
	local spawns = Instance.new("Folder")
	spawns.Name = Layout.PLAYER_SPAWNS
	spawns.Parent = model
	for index, x in { -12, -4, 4, 12 } do
		PartFactory.marker("Spawn_" .. index, CFrame.lookAt(DECK_CENTER + Vector3.new(x, 0.5, 0), Vector3.new(x, DECK_CENTER.Y, 0)), Vector3.new(2, 1, 2), spawns)
	end
	PartFactory.marker(Layout.CAMERA, CFrame.lookAt(CAMERA_POSITION, CAMERA_TARGET), Vector3.one, model)
end

local function buildDeck(scenery: Folder)
	block(scenery, "Deck", Vector3.new(40, 1, 12), CFrame.new(DECK_CENTER - Vector3.new(0, 0.5, 0)), World.Concrete, Enum.Material.Concrete)
	block(scenery, "DeckSupport", Vector3.new(38, DECK_CENTER.Y - 1, 10), CFrame.new(DECK_CENTER.X, (DECK_CENTER.Y - 1) * 0.5, DECK_CENTER.Z), World.ConcreteMid, Enum.Material.Concrete)
	block(scenery, "DeckRail", Vector3.new(40, 1.2, 0.4), CFrame.new(DECK_CENTER + Vector3.new(0, 0.6, -6)), World.Hazard, Enum.Material.Metal)
	-- RETURN pad at the back of the deck.
	local pad = block(scenery, "ReturnPad", Vector3.new(7, 0.4, 5), CFrame.new(DECK_CENTER + Vector3.new(16, 0.2, 3.5)), Theme.Areas.TestRealm, Enum.Material.Glass, true)
	pad.Transparency = 0.25
	CollectionService:AddTag(pad, Constants.Tags.TestRealmReturn)
	local _, label = PartFactory.billboard(pad, "RETURN", Theme.Areas.TestRealm, Vector2.new(6, 1.6), 3, 80)
	label.Font = Theme.Fonts.Title
end

local function buildYard(scenery: Folder)
	for index, cframe in {
		CFrame.new(-40, 2, -6),
		CFrame.new(-50, 2, 8) * CFrame.Angles(0, math.rad(30), 0),
		CFrame.new(20, 2, 30),
		CFrame.new(46, 2, -12) * CFrame.Angles(0, math.rad(-20), 0),
	} do
		block(scenery, `CoverWall_{index}`, Vector3.new(10, 4, 1.6), cframe, World.Concrete, Enum.Material.Concrete)
	end
	for index, position in { Vector3.new(-56, 0, -36), Vector3.new(-20, 0, 34), Vector3.new(60, 0, 34), Vector3.new(36, 0, -30) } do
		block(scenery, `DummyPost_{index}`, Vector3.new(0.5, 3, 0.5), CFrame.new(position + Vector3.new(0, 1.5, 0)), Color3.fromRGB(132, 108, 70), Enum.Material.Wood)
		block(scenery, `DummyBody_{index}`, Vector3.new(2, 2.4, 1), CFrame.new(position + Vector3.new(0, 3.8, 0)), Military.Khaki, Enum.Material.Fabric)
		block(scenery, `DummyHead_{index}`, Vector3.new(1.2, 1.2, 1.2), CFrame.new(position + Vector3.new(0, 5.6, 0)), Military.Khaki, Enum.Material.Fabric)
	end
	-- Low perimeter fence posts.
	for x = -80, 80, 20 do
		for _, z in { -58, 58 } do
			block(scenery, "FencePost", Vector3.new(0.6, 4, 0.6), CFrame.new(x, 2, z), World.Steel, Enum.Material.Metal)
		end
	end
end

function TestYardBuilder.build(): Model
	local model = Instance.new("Model")
	model.Name = "TestYard"
	block(model, "Ground", GROUND_SIZE, CFrame.new(0, -GROUND_SIZE.Y * 0.5, 0), Color3.fromRGB(104, 122, 78), Enum.Material.Grass)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = model
	buildLane(model)
	buildMarkers(model)
	buildDeck(scenery)
	buildYard(scenery)
	model.WorldPivot = CFrame.identity
	return model
end

return TestYardBuilder

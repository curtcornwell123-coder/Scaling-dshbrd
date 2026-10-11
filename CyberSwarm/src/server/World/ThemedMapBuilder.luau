--!strict
--[[
	ThemedMapBuilder
	Generates the multi-lane built-in maps (Factory Floor, Neon City, Frozen Lab, Volcano Core)
	from one layout with per-map colours and props. Lanes are Waypoints/Lane_<n> folders that all
	end at one HQ, so MapService loads them like any hand-built template. A Studio-built model in
	ServerStorage/Maps with the same name still replaces the generated one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PartFactory = require(script.Parent.PartFactory)

local Layout = Constants.MapLayout
local LANE_WIDTH = 9
local BASE_POSITION = Vector3.new(84, 0, 0)
local DECK_CENTER = Vector3.new(0, 6, 78)

export type Theme = {
	name: string,
	ground: Color3,
	groundMaterial: Enum.Material,
	road: Color3,
	kerb: Color3,
	prop: Color3,
	propMaterial: Enum.Material,
	glow: Color3,
	lanes: number,
}

local ThemedMapBuilder = {}

-- Each lane keeps its own band of the map and only meets the others at the final merge in
-- front of the HQ, so roads never cross or overlap.
local function lanePoints(z: number, jog: number): { Vector3 }
	local points = {
		Vector3.new(-86, 0, z),
		Vector3.new(-46, 0, z),
		Vector3.new(-46, 0, z + jog),
		Vector3.new(14, 0, z + jog),
		Vector3.new(14, 0, z),
		Vector3.new(62, 0, z),
	}
	if z ~= 0 then
		table.insert(points, Vector3.new(62, 0, 0))
	end
	table.insert(points, Vector3.new(76, 0, 0))
	return points
end

local function laneLayout(count: number): { { z: number, jog: number } }
	if count <= 1 then
		return { { z = 0, jog = 18 } }
	elseif count == 2 then
		return { { z = -38, jog = 13 }, { z = 38, jog = -13 } }
	end
	return { { z = -52, jog = 13 }, { z = 0, jog = 14 }, { z = 52, jog = -13 } }
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	collide: boolean?
): Part
	return PartFactory.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		material = material,
		canCollide = collide,
		parent = parent,
	})
end

function ThemedMapBuilder.build(theme: Theme): Model
	local model = Instance.new("Model")
	model.Name = theme.name
	part(model, "Ground", Vector3.new(200, 1, 190), CFrame.new(0, -0.5, 0), theme.ground, theme.groundMaterial)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = model

	local waypoints = Instance.new("Folder")
	waypoints.Name = Layout.WAYPOINTS
	waypoints.Parent = model
	for laneIndex, lane in laneLayout(theme.lanes) do
		local folder = Instance.new("Folder")
		folder.Name = Layout.LANE_PREFIX .. laneIndex
		folder.Parent = waypoints
		local points = lanePoints(lane.z, lane.jog)
		for index, position in points do
			PartFactory.marker(Layout.WAYPOINT_PREFIX .. index, CFrame.new(position), Vector3.one, folder)
			local nextPoint = points[index + 1]
			if nextPoint ~= nil then
				local length = (nextPoint - position).Magnitude
				local frame = CFrame.lookAt((position + nextPoint) * 0.5, nextPoint)
				-- Road pieces overlap by a lane width so corners are filled; kerbs stop short of each
				-- corner so edge lines never stack into a grid where pieces meet.
				part(
					scenery,
					"Road",
					Vector3.new(LANE_WIDTH, 0.2, length + LANE_WIDTH),
					frame + Vector3.new(0, 0.1, 0),
					theme.road,
					Enum.Material.Concrete
				)
				local kerbLength = length - LANE_WIDTH
				if kerbLength > 0 then
					for _, side in { -1, 1 } do
						part(
							scenery,
							"Kerb",
							Vector3.new(0.4, 0.25, kerbLength),
							frame * CFrame.new(side * (LANE_WIDTH * 0.5 + 0.2), 0.12, 0),
							theme.kerb,
							Enum.Material.Slate,
							false
						)
					end
				end
			end
		end
	end

	local slots = Instance.new("Folder")
	slots.Name = Layout.TOWER_SLOTS
	slots.Parent = model
	-- Slots sit between the lane bands, never on a road.
	local slotPositions: { Vector3 } = if theme.lanes >= 3
		then {
			Vector3.new(-16, 0, -26),
			Vector3.new(-16, 0, 28),
			Vector3.new(36, 0, -26),
			Vector3.new(36, 0, 28),
			Vector3.new(76, 0, -16),
			Vector3.new(76, 0, 16),
			Vector3.new(-66, 0, -26),
			Vector3.new(-66, 0, 28),
			Vector3.new(36, 0, -72),
			Vector3.new(-16, 0, 72),
		}
		else {
			Vector3.new(-20, 0, 0),
			Vector3.new(36, 0, 0),
			Vector3.new(-66, 0, 0),
			Vector3.new(76, 0, -14),
			Vector3.new(76, 0, 14),
			Vector3.new(-16, 0, -58),
			Vector3.new(-16, 0, 58),
			Vector3.new(40, 0, -58),
			Vector3.new(40, 0, 58),
			Vector3.new(0, 0, 14),
		}
	for index, position in slotPositions do
		local slot = part(
			slots,
			Layout.TOWER_SLOT_PREFIX .. index,
			Vector3.new(6, 1, 6),
			CFrame.new(position + Vector3.new(0, 0.5, 0)),
			theme.prop,
			Enum.Material.Concrete
		)
		slot.CanQuery = false
	end

	local base = PartFactory.marker(
		Layout.BASE_SPAWN,
		CFrame.new(BASE_POSITION + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(14, 1, 12),
		model
	)
	base.CanCollide = true
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
	PartFactory.marker(
		Layout.CAMERA,
		CFrame.lookAt(Vector3.new(0, 120, 120), Vector3.new(0, 0, -4)),
		Vector3.one,
		model
	)
	part(scenery, "Deck", Vector3.new(44, 1, 10), CFrame.new(DECK_CENTER), theme.prop, theme.propMaterial)
	PartFactory.neon(
		"DeckEdge",
		Vector3.new(44, 0.2, 0.3),
		CFrame.new(DECK_CENTER + Vector3.new(0, 0.6, -5)),
		theme.glow,
		scenery
	)

	-- Theme props: pillars/blocks scattered away from the lanes, with a little glow.
	local rng = Random.new(#theme.name * 7919)
	for index = 1, 22 do
		local x = rng:NextNumber(-95, 95)
		local z = if rng:NextNumber() < 0.5 then rng:NextNumber(-94, -82) else rng:NextNumber(88, 94)
		if math.abs(x) < 26 and z > 0 then
			continue
		end
		local height = rng:NextNumber(4, 18)
		local width = rng:NextNumber(3, 9)
		part(
			scenery,
			`Prop_{index}`,
			Vector3.new(width, height, width),
			CFrame.new(x, height * 0.5, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			theme.prop,
			theme.propMaterial
		)
		if index % 3 == 0 then
			PartFactory.neon(
				`PropGlow_{index}`,
				Vector3.new(width + 0.2, 0.3, width + 0.2),
				CFrame.new(x, height * 0.75, z),
				theme.glow,
				scenery
			)
		end
	end
	model.WorldPivot = CFrame.identity
	return model
end

ThemedMapBuilder.Themes = {
	FactoryFloor = {
		name = "FactoryFloor",
		ground = Color3.fromRGB(70, 72, 76),
		groundMaterial = Enum.Material.DiamondPlate,
		road = Color3.fromRGB(46, 48, 52),
		kerb = Color3.fromRGB(190, 152, 20),
		prop = Color3.fromRGB(120, 92, 60),
		propMaterial = Enum.Material.CorrodedMetal,
		glow = Color3.fromRGB(255, 150, 40),
		lanes = 2,
	},
	NeonCity = {
		name = "NeonCity",
		ground = Color3.fromRGB(24, 26, 40),
		groundMaterial = Enum.Material.Asphalt,
		road = Color3.fromRGB(36, 38, 56),
		kerb = Color3.fromRGB(64, 196, 226),
		prop = Color3.fromRGB(40, 44, 70),
		propMaterial = Enum.Material.Glass,
		glow = Color3.fromRGB(214, 78, 166),
		lanes = 3,
	},
	FrozenLab = {
		name = "FrozenLab",
		ground = Color3.fromRGB(200, 220, 235),
		groundMaterial = Enum.Material.Slate,
		road = Color3.fromRGB(150, 170, 190),
		kerb = Color3.fromRGB(120, 200, 255),
		prop = Color3.fromRGB(170, 200, 225),
		propMaterial = Enum.Material.Glass,
		glow = Color3.fromRGB(120, 220, 255),
		lanes = 2,
	},
	VolcanoCore = {
		name = "VolcanoCore",
		ground = Color3.fromRGB(46, 30, 26),
		groundMaterial = Enum.Material.Slate,
		road = Color3.fromRGB(78, 62, 56),
		kerb = Color3.fromRGB(120, 60, 36),
		prop = Color3.fromRGB(60, 40, 34),
		propMaterial = Enum.Material.Slate,
		glow = Color3.fromRGB(255, 80, 20),
		lanes = 3,
	},
} :: { [string]: Theme }

return ThemedMapBuilder

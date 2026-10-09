--!strict
--[[
	MapService
	Loads arena maps by id from ServerStorage/Maps and turns their marker parts into lane paths,
	tower slots, and spawn points. Every map, generated or hand-built, follows one convention:

		<Map Model>
			Waypoints     Folder of Parts Waypoint_1..N (single lane), or Lane_1..N folders of them
			TowerSlots    Folder of Parts TowerSlot_1..N (tower stands on the part's top face)
			BaseSpawn     Part; the enemy HQ stands on its top face, facing its -Z
			PlayerSpawns  Folder of Parts (or a single Part) where players stand to watch
			Camera        Optional Part whose CFrame is the match camera

	Each loaded copy gets its own spatial slot so concurrent matches never overlap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local JunkyardBuilder = require(script.Parent.Parent.World.JunkyardBuilder)

local Layout = Constants.MapLayout

-- Generators for builtIn maps, keyed by map id.
local GENERATORS: { [string]: () -> Model } = {
	Junkyard = JunkyardBuilder.build,
}

local MapService = {}

local mapsFolder: Folder
local activeFolder: Folder
local usedSlots: { [number]: boolean } = {}

local function findTemplate(mapId: string): Model?
	local def = MapConfig.Maps[mapId]
	if def == nil then
		return nil
	end
	local template = mapsFolder:FindFirstChild(def.templateName)
	if template ~= nil and template:IsA("Model") then
		return template
	end
	return nil
end

local function numberSuffix(name: string, prefix: string): number?
	if string.sub(name, 1, #prefix) ~= prefix then
		return nil
	end
	return tonumber(string.sub(name, #prefix + 1))
end

-- Children named <prefix><n> that are BaseParts, sorted by n.
local function orderedParts(container: Instance, prefix: string): { BasePart }
	local entries: { { index: number, part: BasePart } } = {}
	for _, child in container:GetChildren() do
		local index = numberSuffix(child.Name, prefix)
		if index ~= nil and child:IsA("BasePart") then
			table.insert(entries, { index = index, part = child })
		end
	end
	table.sort(entries, function(a, b)
		return a.index < b.index
	end)
	local parts = {}
	for _, entry in entries do
		table.insert(parts, entry.part)
	end
	return parts
end

local function buildLane(waypoints: { BasePart }): ServerTypes.Lane?
	if #waypoints < 2 then
		return nil
	end
	local points: { Vector3 } = {}
	local lengths: { number } = {}
	local total = 0
	for index, part in waypoints do
		points[index] = part.Position
		if index > 1 then
			local length = (points[index] - points[index - 1]).Magnitude
			lengths[index - 1] = length
			total += length
		end
	end
	if total <= 0 then
		return nil
	end
	return { points = points, segmentLengths = lengths, length = total }
end

-- Lane_<n> folders inside Waypoints, sorted by n.
local function orderedFolders(container: Instance): { Instance }
	local entries: { { index: number, folder: Instance } } = {}
	for _, child in container:GetChildren() do
		local index = numberSuffix(child.Name, Layout.LANE_PREFIX)
		if index ~= nil and (child:IsA("Folder") or child:IsA("Model")) then
			table.insert(entries, { index = index, folder = child })
		end
	end
	table.sort(entries, function(a, b)
		return a.index < b.index
	end)
	local folders = {}
	for _, entry in entries do
		table.insert(folders, entry.folder)
	end
	return folders
end

local function parseLanes(model: Model): { ServerTypes.Lane }
	local lanes: { ServerTypes.Lane } = {}
	local waypointsFolder = model:FindFirstChild(Layout.WAYPOINTS)
	if waypointsFolder == nil then
		return lanes
	end
	local laneFolders = orderedFolders(waypointsFolder)
	if #laneFolders == 0 then
		local lane = buildLane(orderedParts(waypointsFolder, Layout.WAYPOINT_PREFIX))
		if lane ~= nil then
			table.insert(lanes, lane)
		end
	else
		for _, folder in laneFolders do
			local lane = buildLane(orderedParts(folder, Layout.WAYPOINT_PREFIX))
			if lane ~= nil then
				table.insert(lanes, lane)
			end
		end
	end
	return lanes
end

local function topOf(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, part.Size.Y * 0.5, 0)
end

local function parseSpawns(model: Model): { CFrame }
	local spawns: { CFrame } = {}
	local container = model:FindFirstChild(Layout.PLAYER_SPAWNS)
	if container == nil then
		return spawns
	end
	if container:IsA("BasePart") then
		table.insert(spawns, topOf(container))
		return spawns
	end
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawns, topOf(child))
		end
	end
	table.sort(spawns, function(a, b)
		return a.Position.X < b.Position.X
	end)
	return spawns
end

local function fallbackCamera(model: Model): CFrame
	local boxCFrame, boxSize = model:GetBoundingBox()
	local footprint = math.max(boxSize.X, boxSize.Z)
	local center = boxCFrame.Position
	local eye = center + Vector3.new(0, footprint * Constants.Camera.HEIGHT_FACTOR, footprint * Constants.Camera.BACK_FACTOR)
	return CFrame.lookAt(eye, center)
end

local function allocateSlot(): number
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

function MapService.isAvailable(mapId: string): boolean
	return findTemplate(mapId) ~= nil
end

-- Clones the map into its own slot and parses it. Returns nil (with a warning) if the template
-- is missing or does not follow the layout convention.
function MapService.load(mapId: string): ServerTypes.LoadedMap?
	local template = findTemplate(mapId)
	if template == nil then
		warn(`[MapService] No template for map "{mapId}" in ServerStorage/{Layout.MAPS_FOLDER}.`)
		return nil
	end

	local slotIndex = allocateSlot()
	local model = template:Clone()
	model.Name = `{mapId}_{slotIndex}`
	local origin = Constants.World.MAP_ORIGIN + Vector3.new(Constants.World.MAP_SPACING * (slotIndex - 1), 0, 0)
	model:PivotTo(CFrame.new(origin))

	local lanes = parseLanes(model)
	local slotsFolder = model:FindFirstChild(Layout.TOWER_SLOTS)
	local towerSlots: { CFrame } = {}
	if slotsFolder ~= nil then
		for _, slot in orderedParts(slotsFolder, Layout.TOWER_SLOT_PREFIX) do
			table.insert(towerSlots, topOf(slot))
		end
	end
	local baseSpawn = model:FindFirstChild(Layout.BASE_SPAWN)
	local playerSpawns = parseSpawns(model)

	local problems: { string } = {}
	if #lanes == 0 then
		table.insert(problems, "no valid lane (needs at least two Waypoint_N parts)")
	end
	if baseSpawn == nil or not baseSpawn:IsA("BasePart") then
		table.insert(problems, "missing BaseSpawn part")
	end
	if #playerSpawns == 0 then
		table.insert(problems, "no PlayerSpawns")
	end
	if #problems > 0 then
		warn(`[MapService] Map "{mapId}" is invalid: {table.concat(problems, "; ")}.`)
		model:Destroy()
		usedSlots[slotIndex] = nil
		return nil
	end

	local cameraPart = model:FindFirstChild(Layout.CAMERA)
	local cameraCFrame = if cameraPart ~= nil and cameraPart:IsA("BasePart") then cameraPart.CFrame else fallbackCamera(model)

	local unitFolder = Instance.new("Folder")
	unitFolder.Name = Layout.UNITS_FOLDER
	unitFolder.Parent = model

	CollectionService:AddTag(model, Constants.Tags.ActiveMap)
	model.Parent = activeFolder

	return {
		mapId = mapId,
		model = model,
		slotIndex = slotIndex,
		lanes = lanes,
		towerSlots = towerSlots,
		baseCFrame = topOf(baseSpawn :: BasePart),
		playerSpawns = playerSpawns,
		cameraCFrame = cameraCFrame,
		unitFolder = unitFolder,
	}
end

-- Destroys the map (and every robot/tower parented under it) and frees its slot.
function MapService.unload(map: ServerTypes.LoadedMap)
	map.model:Destroy()
	usedSlots[map.slotIndex] = nil
end

function MapService.init()
	local existing = ServerStorage:FindFirstChild(Layout.MAPS_FOLDER)
	if existing ~= nil and existing:IsA("Folder") then
		mapsFolder = existing
	else
		mapsFolder = Instance.new("Folder")
		mapsFolder.Name = Layout.MAPS_FOLDER
		mapsFolder.Parent = ServerStorage
	end

	-- Built-in maps are generated only when nobody has saved a hand-made version in Studio.
	for _, mapId in MapConfig.Order do
		local def = MapConfig.Maps[mapId]
		local generator = GENERATORS[mapId]
		if def.builtIn and generator ~= nil and findTemplate(mapId) == nil then
			local template = generator()
			template.Name = def.templateName
			template.Parent = mapsFolder
		end
	end

	activeFolder = Instance.new("Folder")
	activeFolder.Name = "ActiveMaps"
	activeFolder.Parent = workspace
end

return MapService

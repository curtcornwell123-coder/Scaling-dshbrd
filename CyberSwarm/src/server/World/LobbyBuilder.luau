--!strict
--[[
	LobbyBuilder
	Generates the hub lobby from Parts: a neon-gridded deck, a spawn, the title sign, and one queue
	pad per mode in ModeConfig.Order. Each pad is self-describing: the QueuePad tag, a ModeId
	attribute, and a "Status" billboard. QueueService discovers pads through CollectionService, so
	pads placed by hand in Studio work the same way.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local PartFactory = require(script.Parent.PartFactory)

local FLOOR_SIZE = 150
local FLOOR_THICKNESS = 2
local GRID_STEP = 15
local PAD_SIZE = 16
local PAD_ROW_Z = 28
local PAD_SPACING = 34
local SPAWN_Z = -30
local WALL_HEIGHT = 14

export type PadInfo = {
	pad: BasePart,
	modeId: string,
	statusLabel: TextLabel,
}

export type Lobby = {
	model: Model,
	spawn: SpawnLocation,
	pads: { PadInfo },
}

local LobbyBuilder = {}

local function applyLighting()
	-- Night lighting makes neon read as glowing light rather than flat colour.
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(40, 42, 64)
	Lighting.OutdoorAmbient = Color3.fromRGB(56, 58, 86)
	if Lighting:FindFirstChild("CyberSwarmBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "CyberSwarmBloom"
		bloom.Intensity = 0.8
		bloom.Size = 28
		bloom.Threshold = 0.95
		bloom.Parent = Lighting
	end
end

local function buildPad(model: Model, origin: Vector3, modeId: string, index: number, count: number): PadInfo
	local mode = ModeConfig.Modes[modeId]
	local x = (index - (count + 1) * 0.5) * PAD_SPACING
	local center = origin + Vector3.new(x, 0.25, PAD_ROW_Z)

	local pad = PartFactory.part({
		name = "QueuePad_" .. modeId,
		size = Vector3.new(PAD_SIZE, 0.5, PAD_SIZE),
		cframe = CFrame.new(center),
		color = Theme.Colors.PanelLight,
		material = Enum.Material.Glass,
		parent = model,
	})
	pad:SetAttribute(Constants.Attributes.ModeId, modeId)
	CollectionService:AddTag(pad, Constants.Tags.QueuePad)

	-- Glowing frame around the pad in the mode's colour.
	local half = PAD_SIZE * 0.5
	for _, edge in
		{
			{ Vector3.new(0, 0.3, half), Vector3.new(PAD_SIZE + 1, 0.3, 0.6) },
			{ Vector3.new(0, 0.3, -half), Vector3.new(PAD_SIZE + 1, 0.3, 0.6) },
			{ Vector3.new(half, 0.3, 0), Vector3.new(0.6, 0.3, PAD_SIZE + 1) },
			{ Vector3.new(-half, 0.3, 0), Vector3.new(0.6, 0.3, PAD_SIZE + 1) },
		}
	do
		PartFactory.neon("PadEdge", edge[2], CFrame.new(center + edge[1]), mode.padColor, model)
	end

	-- Holographic pillars on each back corner.
	for _, side in { -1, 1 } do
		PartFactory.neon(
			"PadPillar",
			Vector3.new(0.6, 9, 0.6),
			CFrame.new(center + Vector3.new(side * half, 4.5, half)),
			mode.padColor,
			model
		)
	end

	local title =
		PartFactory.billboard(pad, string.upper(mode.displayName), mode.padColor, Vector2.new(14, 3.5), 10.8, 220)
	title.Name = "Title"
	local status, statusLabel =
		PartFactory.billboard(pad, "STEP ON TO QUEUE", Theme.Colors.Text, Vector2.new(14, 1.6), 8.4, 160)
	status.Name = "Status"
	statusLabel.Font = Theme.Fonts.Body

	return {
		pad = pad,
		modeId = modeId,
		statusLabel = statusLabel,
	}
end

function LobbyBuilder.build(parent: Instance): Lobby
	applyLighting()

	local origin = Constants.World.LOBBY_ORIGIN
	local model = Instance.new("Model")
	model.Name = "Lobby"

	PartFactory.part({
		name = "Floor",
		size = Vector3.new(FLOOR_SIZE, FLOOR_THICKNESS, FLOOR_SIZE),
		cframe = CFrame.new(origin - Vector3.new(0, FLOOR_THICKNESS * 0.5, 0)),
		color = Theme.Colors.Background,
		material = Enum.Material.DiamondPlate,
		parent = model,
	})

	-- Alternating cyan / magenta grid lines across the deck.
	local half = FLOOR_SIZE * 0.5
	local lineIndex = 0
	for offset = -half + GRID_STEP, half - GRID_STEP, GRID_STEP do
		lineIndex += 1
		local color = if lineIndex % 2 == 0 then Theme.Colors.Primary else Theme.Colors.Secondary
		PartFactory.neon(
			"GridX",
			Vector3.new(FLOOR_SIZE, 0.06, 0.25),
			CFrame.new(origin + Vector3.new(0, 0.03, offset)),
			color,
			model
		)
		PartFactory.neon(
			"GridZ",
			Vector3.new(0.25, 0.06, FLOOR_SIZE),
			CFrame.new(origin + Vector3.new(offset, 0.03, 0)),
			color,
			model
		)
	end

	-- Invisible walls keep players on the deck; neon rails show where the edge is.
	for _, wall in
		{
			{ Vector3.new(0, WALL_HEIGHT * 0.5, half), Vector3.new(FLOOR_SIZE, WALL_HEIGHT, 1) },
			{ Vector3.new(0, WALL_HEIGHT * 0.5, -half), Vector3.new(FLOOR_SIZE, WALL_HEIGHT, 1) },
			{ Vector3.new(half, WALL_HEIGHT * 0.5, 0), Vector3.new(1, WALL_HEIGHT, FLOOR_SIZE) },
			{ Vector3.new(-half, WALL_HEIGHT * 0.5, 0), Vector3.new(1, WALL_HEIGHT, FLOOR_SIZE) },
		}
	do
		local barrier = PartFactory.part({
			name = "Barrier",
			size = wall[2],
			cframe = CFrame.new(origin + wall[1]),
			color = Theme.Colors.Primary,
			transparency = 1,
			parent = model,
		})
		barrier.CanQuery = false
		local railSize = Vector3.new(math.max(wall[2].X, 1), 0.4, math.max(wall[2].Z, 1))
		PartFactory.neon(
			"Rail",
			railSize,
			CFrame.new(origin + Vector3.new(wall[1].X, 1.2, wall[1].Z)),
			Theme.Colors.Secondary,
			model
		)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.5, SPAWN_Z))
	spawn.Color = Theme.Colors.Primary
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.35
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model

	-- Title sign floating behind the spawn.
	local titleAnchor =
		PartFactory.marker("TitleAnchor", CFrame.new(origin + Vector3.new(0, 22, -half + 8)), Vector3.one, model)
	PartFactory.billboard(
		titleAnchor,
		string.upper(Constants.GAME_NAME),
		Theme.Colors.Primary,
		Vector2.new(60, 12),
		0,
		600
	)
	PartFactory.billboard(
		titleAnchor,
		"SEND THE SWARM. BREAK THE DEFENSE.",
		Theme.Colors.Secondary,
		Vector2.new(50, 3),
		-7.5,
		600
	)

	local pads: { PadInfo } = {}
	for index, modeId in ModeConfig.Order do
		table.insert(pads, buildPad(model, origin, modeId, index, #ModeConfig.Order))
	end

	model.Parent = parent
	return {
		model = model,
		spawn = spawn,
		pads = pads,
	}
end

return LobbyBuilder

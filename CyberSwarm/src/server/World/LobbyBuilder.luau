--!strict
--[[
	LobbyBuilder
	Generates the hub lobby from Parts: an enclosed arena hall (tall panelled walls with neon trim,
	pillars, corner towers, overhead light beams and big wall screens), a neon-gridded deck, a spawn
	facing the pads, and one queue pad per mode in ModeConfig.Order. Each pad is self-describing: the QueuePad tag, a ModeId
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
local WALL_HEIGHT = 40
local WALL_THICKNESS = 3
local PILLAR_SPACING = 25
local CORNER_TOWER_SIZE = 7
local BEAM_ROWS = { -30, 0, 30 }
local SCREEN_PIXELS_PER_STUD = 20

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

-- Each wall is built in its own frame: local X runs along the wall, -Z faces into the lobby and
-- Y = 0 is floor level, so every wall uses the same decoration code.
local function buildWall(model: Model, base: Vector3, inward: Vector3, length: number): CFrame
	local frame = CFrame.lookAt(base, base + inward)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	PartFactory.part({
		name = "Wall",
		size = Vector3.new(length, WALL_HEIGHT, WALL_THICKNESS),
		cframe = at(0, WALL_HEIGHT * 0.5, WALL_THICKNESS * 0.5),
		color = Theme.Colors.Panel,
		material = Enum.Material.SmoothPlastic,
		parent = model,
	})

	-- Lighter inset panels between the pillars give the wall depth.
	local bays = math.max(1, math.floor(length / PILLAR_SPACING + 0.5))
	local bayWidth = length / bays
	for bay = 1, bays do
		local x = -length * 0.5 + (bay - 0.5) * bayWidth
		PartFactory.part({
			name = "WallPanel",
			size = Vector3.new(bayWidth - 4, WALL_HEIGHT - 14, 0.3),
			cframe = at(x, WALL_HEIGHT * 0.5, -0.15),
			color = Theme.Colors.PanelLight,
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = model,
		})
	end

	-- Metal pillars with alternating cyan / magenta light stripes.
	for pillar = 1, bays - 1 do
		local x = -length * 0.5 + pillar * bayWidth
		PartFactory.part({
			name = "Pillar",
			size = Vector3.new(3, WALL_HEIGHT, 1.6),
			cframe = at(x, WALL_HEIGHT * 0.5, -0.8),
			color = Theme.Colors.Metal,
			material = Enum.Material.Metal,
			parent = model,
		})
		local stripeColor = if pillar % 2 == 0 then Theme.Colors.Secondary else Theme.Colors.Primary
		PartFactory.neon(
			"PillarStripe",
			Vector3.new(0.5, WALL_HEIGHT - 8, 0.2),
			at(x, WALL_HEIGHT * 0.5, -1.7),
			stripeColor,
			model
		)
	end

	PartFactory.neon("BaseTrim", Vector3.new(length, 0.5, 0.3), at(0, 0.9, -0.3), Theme.Colors.Primary, model)
	PartFactory.neon(
		"TopTrim",
		Vector3.new(length, 0.6, 0.3),
		at(0, WALL_HEIGHT - 4, -0.3),
		Theme.Colors.Secondary,
		model
	)
	PartFactory.part({
		name = "Cornice",
		size = Vector3.new(length, 1.5, WALL_THICKNESS + 2),
		cframe = at(0, WALL_HEIGHT + 0.75, WALL_THICKNESS * 0.5 - 1),
		color = Theme.Colors.Metal,
		material = Enum.Material.Metal,
		parent = model,
	})
	return frame
end

-- A glowing wall screen with a title and body text, mounted in front of the pillars.
local function buildScreen(
	model: Model,
	wallFrame: CFrame,
	x: number,
	y: number,
	size: Vector2,
	title: string,
	body: string,
	accent: Color3
)
	local cframe = wallFrame * CFrame.new(x, y, -2.2)
	PartFactory.neon(
		"ScreenBorder",
		Vector3.new(size.X + 1, size.Y + 1, 0.3),
		cframe * CFrame.new(0, 0, 0.3),
		accent,
		model
	)
	local screen = PartFactory.part({
		name = "Screen",
		size = Vector3.new(size.X, size.Y, 0.4),
		cframe = cframe,
		color = Theme.Colors.PanelDark,
		material = Enum.Material.SmoothPlastic,
		canCollide = false,
		parent = model,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SCREEN_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Adornee = screen

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0.05, 0.06)
	titleLabel.Size = UDim2.fromScale(0.9, 0.36)
	titleLabel.Font = Theme.Fonts.Title
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = accent
	titleLabel.Text = title
	titleLabel.Parent = gui

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Position = UDim2.fromScale(0.07, 0.46)
	bodyLabel.Size = UDim2.fromScale(0.86, 0.46)
	bodyLabel.Font = Theme.Fonts.Body
	bodyLabel.TextScaled = true
	bodyLabel.TextWrapped = true
	bodyLabel.TextColor3 = Theme.Colors.Text
	bodyLabel.Text = body
	bodyLabel.Parent = gui

	gui.Parent = screen
end

local function buildCeiling(model: Model, origin: Vector3, span: number)
	for _, z in BEAM_ROWS do
		PartFactory.part({
			name = "Beam",
			size = Vector3.new(span, 2, 2.5),
			cframe = CFrame.new(origin + Vector3.new(0, WALL_HEIGHT, z)),
			color = Theme.Colors.Metal,
			material = Enum.Material.Metal,
			parent = model,
		})
		PartFactory.neon(
			"BeamLight",
			Vector3.new(span, 0.3, 0.9),
			CFrame.new(origin + Vector3.new(0, WALL_HEIGHT - 1.15, z)),
			Theme.Colors.Primary,
			model
		)
	end
end

local function buildCornerTowers(model: Model, origin: Vector3, half: number)
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local center = origin + Vector3.new(corner.X * (half + 1), 0, corner.Z * (half + 1))
		PartFactory.part({
			name = "CornerTower",
			size = Vector3.new(CORNER_TOWER_SIZE, WALL_HEIGHT + 6, CORNER_TOWER_SIZE),
			cframe = CFrame.new(center + Vector3.new(0, (WALL_HEIGHT + 6) * 0.5, 0)),
			color = Theme.Colors.Metal,
			material = Enum.Material.Metal,
			parent = model,
		})
		PartFactory.neon(
			"TowerCap",
			Vector3.new(CORNER_TOWER_SIZE + 0.6, 0.8, CORNER_TOWER_SIZE + 0.6),
			CFrame.new(center + Vector3.new(0, WALL_HEIGHT + 6.4, 0)),
			Theme.Colors.Secondary,
			model
		)
	end
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

	-- Enclosed arena hall: four panelled walls, corner towers, and overhead light beams.
	local backWall = buildWall(model, origin + Vector3.new(0, 0, half), Vector3.new(0, 0, -1), FLOOR_SIZE)
	buildWall(model, origin + Vector3.new(0, 0, -half), Vector3.new(0, 0, 1), FLOOR_SIZE)
	local leftWall = buildWall(model, origin + Vector3.new(-half, 0, 0), Vector3.new(1, 0, 0), FLOOR_SIZE)
	local rightWall = buildWall(model, origin + Vector3.new(half, 0, 0), Vector3.new(-1, 0, 0), FLOOR_SIZE)
	buildCornerTowers(model, origin, half)
	buildCeiling(model, origin, FLOOR_SIZE)

	-- Big screens: the title above the queue pads, and a short briefing on each side wall.
	buildScreen(
		model,
		backWall,
		0,
		24,
		Vector2.new(48, 16),
		string.upper(Constants.GAME_NAME),
		"SEND THE SWARM. BREAK THE DEFENSE.",
		Theme.Colors.Primary
	)
	buildScreen(
		model,
		leftWall,
		0,
		18,
		Vector2.new(34, 18),
		"HOW TO PLAY",
		"Step on a pad or press PLAY.\nBuy robots between waves.\nSurvivors damage the enemy HQ.",
		Theme.Colors.Secondary
	)
	buildScreen(
		model,
		rightWall,
		0,
		18,
		Vector2.new(34, 18),
		"THE DEFENSE MUTATES",
		"Every wave the enemy gains a military upgrade. Check the incoming mutation and counter it.",
		Theme.Military.Amber
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	-- Turned to face +Z so players spawn looking at the queue pads and the title screen.
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.5, SPAWN_Z)) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = Theme.Colors.Primary
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.35
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model

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

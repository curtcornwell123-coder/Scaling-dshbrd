--!strict
--[[
	LobbyBuilder
	Generates the hub lobby from Parts: an enclosed hall (tall painted walls, metal pillars, corner
	towers, ceiling beams with real lights), wall screens, and one round queue pad per mode in
	ModeConfig.Order. Glow is limited to small accents; surfaces are lit by the scene.

	Queueing is entirely in-world. Each pad is self-describing for QueueService: the QueuePad tag,
	a ModeId and QueueRadius attribute, and a "Ring" folder of segments that fill as players join.
	The back-wall queue board (tagged QueueBoard) has one "Mode_<ModeId>" line per mode. The game's
	name appears only as a small stencil painted on a wall.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local PartFactory = require(script.Parent.PartFactory)

local World = Theme.World

local FLOOR_SIZE = 150
local FLOOR_THICKNESS = 2
local SEAM_STEP = 15
local SPAWN_Z = -30

local PAD_RADIUS = 8
local PAD_THICKNESS = 0.6
local PAD_ROW_Z = 28
local PAD_SPACING = 34
local RING_RADIUS = 9.8
local SIGN_DISTANCE = 12

local WALL_HEIGHT = 40
local WALL_THICKNESS = 3
local PILLAR_SPACING = 25
local CORNER_TOWER_SIZE = 7
local BEAM_ROWS = { -30, 0, 30 }
local SCREEN_PIXELS_PER_STUD = 20

-- A flat cylinder: Roblox cylinders run along X, so roll it 90 degrees to lie on the floor.
local LIE_FLAT = CFrame.Angles(0, 0, math.rad(90))

export type PadInfo = {
	pad: BasePart,
	modeId: string,
}

export type Lobby = {
	model: Model,
	spawn: SpawnLocation,
	pads: { PadInfo },
}

local LobbyBuilder = {}

local function applyLighting()
	-- A bright hall reads clean and lets accents stand out without everything glowing.
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(96, 100, 112)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 140)
	if Lighting:FindFirstChild("CyberSwarmBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "CyberSwarmBloom"
		bloom.Intensity = 0.15
		bloom.Size = 18
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
end

local function playerCountText(mode: Types.ModeDef): string
	if mode.minPlayers == mode.maxPlayers then
		return if mode.maxPlayers == 1 then "1 PLAYER" else `{mode.maxPlayers} PLAYERS`
	end
	return `{mode.minPlayers}-{mode.maxPlayers} PLAYERS`
end

local function surfaceGui(adornee: BasePart): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SCREEN_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

local function screenText(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	font: Enum.Font,
	position: UDim2,
	size: UDim2
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	return label
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
		color = World.Wall,
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
			color = World.WallPanel,
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = model,
		})
	end
	for pillar = 1, bays - 1 do
		PartFactory.part({
			name = "Pillar",
			size = Vector3.new(3, WALL_HEIGHT, 1.6),
			cframe = at(-length * 0.5 + pillar * bayWidth, WALL_HEIGHT * 0.5, -0.8),
			color = World.Pillar,
			material = Enum.Material.Metal,
			parent = model,
		})
	end

	-- Painted (non-glowing) accent stripe and a dark skirting board.
	PartFactory.part({
		name = "Skirting",
		size = Vector3.new(length, 1.6, 0.4),
		cframe = at(0, 0.8, -0.2),
		color = World.Trim,
		material = Enum.Material.SmoothPlastic,
		canCollide = false,
		parent = model,
	})
	PartFactory.part({
		name = "AccentStripe",
		size = Vector3.new(length, 0.5, 0.3),
		cframe = at(0, WALL_HEIGHT - 6, -0.3),
		color = Theme.Colors.Primary,
		material = Enum.Material.SmoothPlastic,
		canCollide = false,
		parent = model,
	})
	PartFactory.part({
		name = "Cornice",
		size = Vector3.new(length, 1.5, WALL_THICKNESS + 2),
		cframe = at(0, WALL_HEIGHT + 0.75, WALL_THICKNESS * 0.5 - 1),
		color = World.Trim,
		material = Enum.Material.Metal,
		parent = model,
	})
	return frame
end

-- A wall-mounted screen in front of the pillars. Returns the screen part and its SurfaceGui.
local function buildScreen(
	model: Model,
	wallFrame: CFrame,
	x: number,
	y: number,
	size: Vector2,
	accent: Color3
): (BasePart, SurfaceGui)
	local cframe = wallFrame * CFrame.new(x, y, -2.2)
	PartFactory.part({
		name = "ScreenFrame",
		size = Vector3.new(size.X + 1.2, size.Y + 1.2, 0.3),
		cframe = cframe * CFrame.new(0, 0, 0.3),
		color = World.Trim,
		material = Enum.Material.Metal,
		canCollide = false,
		parent = model,
	})
	PartFactory.part({
		name = "ScreenAccent",
		size = Vector3.new(size.X + 1.2, 0.25, 0.35),
		cframe = cframe * CFrame.new(0, -size.Y * 0.5 - 0.6, 0.1),
		color = accent,
		material = Enum.Material.SmoothPlastic,
		canCollide = false,
		parent = model,
	})
	local screen = PartFactory.part({
		name = "Screen",
		size = Vector3.new(size.X, size.Y, 0.4),
		cframe = cframe,
		color = World.Screen,
		material = Enum.Material.SmoothPlastic,
		canCollide = false,
		parent = model,
	})
	return screen, surfaceGui(screen)
end

local function buildCeiling(model: Model, origin: Vector3, span: number)
	for _, z in BEAM_ROWS do
		local beam = PartFactory.part({
			name = "Beam",
			size = Vector3.new(span, 2, 2.5),
			cframe = CFrame.new(origin + Vector3.new(0, WALL_HEIGHT, z)),
			color = World.Beam,
			material = Enum.Material.Metal,
			parent = model,
		})
		-- Real light pointing down instead of a glowing strip.
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 45
		light.Brightness = 1.2
		light.Angle = 120
		light.Color = Color3.fromRGB(255, 244, 228)
		light.Parent = beam
	end
end

local function buildCornerTowers(model: Model, origin: Vector3, half: number)
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local center = origin + Vector3.new(corner.X * (half + 1), 0, corner.Z * (half + 1))
		PartFactory.part({
			name = "CornerTower",
			size = Vector3.new(CORNER_TOWER_SIZE, WALL_HEIGHT + 6, CORNER_TOWER_SIZE),
			cframe = CFrame.new(center + Vector3.new(0, (WALL_HEIGHT + 6) * 0.5, 0)),
			color = World.Pillar,
			material = Enum.Material.Metal,
			parent = model,
		})
	end
end

local function buildFloor(model: Model, origin: Vector3)
	PartFactory.part({
		name = "Floor",
		size = Vector3.new(FLOOR_SIZE, FLOOR_THICKNESS, FLOOR_SIZE),
		cframe = CFrame.new(origin - Vector3.new(0, FLOOR_THICKNESS * 0.5, 0)),
		color = World.Floor,
		material = Enum.Material.Concrete,
		parent = model,
	})
	-- Subtle tile seams instead of a glowing grid.
	local half = FLOOR_SIZE * 0.5
	for offset = -half + SEAM_STEP, half - SEAM_STEP, SEAM_STEP do
		for _, alongX in { true, false } do
			local seam = PartFactory.part({
				name = "Seam",
				size = if alongX then Vector3.new(FLOOR_SIZE, 0.04, 0.2) else Vector3.new(0.2, 0.04, FLOOR_SIZE),
				cframe = CFrame.new(
					origin + (if alongX then Vector3.new(0, 0.02, offset) else Vector3.new(offset, 0.02, 0))
				),
				color = World.FloorSeam,
				material = Enum.Material.SmoothPlastic,
				canCollide = false,
				parent = model,
			})
			seam.CanQuery = false
		end
	end
end

local function buildPad(model: Model, origin: Vector3, modeId: string, index: number, count: number): PadInfo
	local mode = ModeConfig.Modes[modeId]
	local x = (index - (count + 1) * 0.5) * PAD_SPACING
	local center = origin + Vector3.new(x, 0, PAD_ROW_Z)

	-- Painted rim in the mode's colour, then the dark pad on top.
	PartFactory.part({
		name = "PadRim",
		size = Vector3.new(PAD_THICKNESS - 0.2, PAD_RADIUS * 2 + 1.4, PAD_RADIUS * 2 + 1.4),
		cframe = CFrame.new(center + Vector3.new(0, (PAD_THICKNESS - 0.2) * 0.5, 0)) * LIE_FLAT,
		color = mode.padColor,
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
		parent = model,
	})
	local pad = PartFactory.part({
		name = "QueuePad_" .. modeId,
		size = Vector3.new(PAD_THICKNESS, PAD_RADIUS * 2, PAD_RADIUS * 2),
		cframe = CFrame.new(center + Vector3.new(0, PAD_THICKNESS * 0.5, 0)) * LIE_FLAT,
		color = World.Trim,
		material = Enum.Material.DiamondPlate,
		shape = Enum.PartType.Cylinder,
		parent = model,
	})
	pad:SetAttribute(Constants.Attributes.ModeId, modeId)
	pad:SetAttribute(Constants.Attributes.QueueRadius, PAD_RADIUS + 0.5)
	CollectionService:AddTag(pad, Constants.Tags.QueuePad)

	-- Floor ring around the pad; QueueService lights segments as players join.
	local ring = Instance.new("Folder")
	ring.Name = "Ring"
	local segments = Constants.Queue.RING_SEGMENTS
	for segment = 1, segments do
		-- Start at the front (facing the spawn) and go round.
		local angle = math.rad(-90) + (segment - 1) / segments * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * RING_RADIUS, 0.12, math.sin(angle) * RING_RADIUS)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local part = PartFactory.part({
			name = "Segment_" .. segment,
			size = Vector3.new(0.9, 0.24, 2),
			cframe = CFrame.lookAt(position, position + tangent),
			color = World.RingUnlit,
			material = Enum.Material.SmoothPlastic,
			canCollide = false,
			parent = ring,
		})
		part.CanQuery = false
	end
	ring.Parent = pad

	-- Painted mode sign behind the pad, facing the spawn.
	for _, side in { -1, 1 } do
		PartFactory.part({
			name = "SignPost",
			size = Vector3.new(0.6, 7, 0.6),
			cframe = CFrame.new(center + Vector3.new(side * 5.5, 3.5, SIGN_DISTANCE + 0.4)),
			color = World.Pillar,
			material = Enum.Material.Metal,
			parent = model,
		})
	end
	local signPosition = center + Vector3.new(0, 5.5, SIGN_DISTANCE)
	local sign = PartFactory.part({
		name = "ModeSign",
		size = Vector3.new(13, 3.6, 0.4),
		cframe = CFrame.lookAt(signPosition, signPosition - Vector3.zAxis),
		color = World.Screen,
		material = Enum.Material.SmoothPlastic,
		parent = model,
	})
	local gui = surfaceGui(sign)
	screenText(
		gui,
		"Mode",
		string.upper(mode.displayName),
		mode.padColor,
		Theme.Fonts.Title,
		UDim2.fromScale(0.05, 0.06),
		UDim2.fromScale(0.9, 0.56)
	)
	screenText(
		gui,
		"Players",
		playerCountText(mode),
		Theme.Colors.TextDim,
		Theme.Fonts.Body,
		UDim2.fromScale(0.05, 0.64),
		UDim2.fromScale(0.9, 0.28)
	)

	return {
		pad = pad,
		modeId = modeId,
	}
end

local function buildQueueBoard(model: Model, backWall: CFrame)
	local rows = #ModeConfig.Order
	local screen, gui = buildScreen(model, backWall, 0, 24, Vector2.new(46, 6 + rows * 3.4), Theme.Colors.Primary)
	CollectionService:AddTag(screen, Constants.Tags.QueueBoard)

	local rowHeight = 1 / (rows + 2)
	screenText(
		gui,
		"Header",
		"QUEUE PADS",
		Theme.Colors.Primary,
		Theme.Fonts.Title,
		UDim2.fromScale(0.05, rowHeight * 0.1),
		UDim2.fromScale(0.9, rowHeight * 0.8)
	)
	for index, modeId in ModeConfig.Order do
		local mode = ModeConfig.Modes[modeId]
		screenText(
			gui,
			"Mode_" .. modeId,
			`{string.upper(mode.displayName)}   0/{mode.maxPlayers}   STEP ON THE PAD TO QUEUE`,
			Theme.Colors.Text,
			Theme.Fonts.Body,
			UDim2.fromScale(0.05, rowHeight * index + rowHeight * 0.1),
			UDim2.fromScale(0.9, rowHeight * 0.8)
		)
	end
	screenText(
		gui,
		"Footer",
		"STEP ON A PAD TO QUEUE  -  STEP OFF TO LEAVE",
		Theme.Colors.TextDim,
		Theme.Fonts.Light,
		UDim2.fromScale(0.05, rowHeight * (rows + 1) + rowHeight * 0.15),
		UDim2.fromScale(0.9, rowHeight * 0.7)
	)
end

local function buildBriefing(model: Model, wall: CFrame, title: string, body: string, accent: Color3)
	local _, gui = buildScreen(model, wall, 0, 18, Vector2.new(34, 16), accent)
	screenText(gui, "Title", title, accent, Theme.Fonts.Title, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.3))
	screenText(
		gui,
		"Body",
		body,
		Theme.Colors.Text,
		Theme.Fonts.Body,
		UDim2.fromScale(0.07, 0.44),
		UDim2.fromScale(0.86, 0.48)
	)
end

-- The only place the game's name appears: a small stencil painted high on the back wall.
local function buildStencil(model: Model, backWall: CFrame)
	local plate = PartFactory.part({
		name = "Stencil",
		-- Sits in a clear wall bay (between pillars) above the accent stripe.
		size = Vector3.new(18, 3, 0.1),
		cframe = backWall * CFrame.new(-37.5, 36.5, -0.4),
		color = World.Wall,
		transparency = 1,
		canCollide = false,
		parent = model,
	})
	plate.CanQuery = false
	local label = screenText(
		surfaceGui(plate),
		"Name",
		"C Y B E R   S W A R M",
		World.Stencil,
		Theme.Fonts.Title,
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 1)
	)
	label.TextTransparency = 0.25
end

function LobbyBuilder.build(parent: Instance): Lobby
	applyLighting()

	local origin = Constants.World.LOBBY_ORIGIN
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local half = FLOOR_SIZE * 0.5

	buildFloor(model, origin)
	local backWall = buildWall(model, origin + Vector3.new(0, 0, half), Vector3.new(0, 0, -1), FLOOR_SIZE)
	buildWall(model, origin + Vector3.new(0, 0, -half), Vector3.new(0, 0, 1), FLOOR_SIZE)
	local leftWall = buildWall(model, origin + Vector3.new(-half, 0, 0), Vector3.new(1, 0, 0), FLOOR_SIZE)
	local rightWall = buildWall(model, origin + Vector3.new(half, 0, 0), Vector3.new(-1, 0, 0), FLOOR_SIZE)
	buildCornerTowers(model, origin, half)
	buildCeiling(model, origin, FLOOR_SIZE)

	buildQueueBoard(model, backWall)
	buildStencil(model, backWall)
	buildBriefing(
		model,
		leftWall,
		"HOW TO PLAY",
		"Step on a mode pad to queue.\nBuy robots between waves.\nSurvivors damage the enemy HQ.",
		Theme.Colors.Secondary
	)
	buildBriefing(
		model,
		rightWall,
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
	-- Turned to face +Z so players spawn looking at the queue pads and the queue board.
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.5, SPAWN_Z)) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = World.Trim
	spawn.Material = Enum.Material.DiamondPlate
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

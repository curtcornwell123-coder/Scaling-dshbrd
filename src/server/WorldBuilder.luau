--!strict
-- Builds the map: a conveyor down the middle and player bases on both sides.
-- Everything is made from parts so the place works from an empty Baseplate.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldBuilder = {}

export type PlotParts = {
	Index: number,
	Model: Model,
	CFrame: CFrame, -- center of the floor; LookVector points at the conveyor
	Pedestals: { BasePart },
	CollectPad: BasePart,
	LockPad: BasePart,
	Lasers: { BasePart },
	WallFolders: { [number]: Folder },
	Stories: { [number]: Folder }, -- floors 2+; parented only once bought
	Stairs: { { Carpet: Folder, Base: CFrame } }, -- Base: bottom-front-center of each staircase
	Floors: { BasePart }, -- ground floor + every upper slab
	LightSets: { [number]: { Ceiling: Folder, Posts: Folder } },
	Roof: Folder, -- parented only when every floor is built
	SignPost: BasePart,
	UpgradePost: BasePart,
	UpgradeLabel: TextLabel,
	OwnerLabel: TextLabel,
	PendingLabel: TextLabel,
	LockLabel: TextLabel,
	SpawnCFrame: CFrame,
}

export type World = {
	Plots: { PlotParts },
	ConveyorStart: Vector3,
	ConveyorEnd: Vector3,
	CarriedFolder: Folder,
	ConveyorFolder: Folder,
	ShopPosition: Vector3, -- center of the shop tent
	StatuePosition: Vector3, -- where the event statue stands
}

local PLOT_SIZE = 60
local PLOT_DISTANCE = 75 -- from the conveyor to each plot's center
local PLOT_SPACING = 70
local SIGN_HEIGHT = 24
local ENTRANCE_WIDTH = 16
local FLOOR_TOP = 1
local WALL_COLOR = Color3.fromRGB(140, 140, 145) -- every base's fence is the same grey
local CAVE_DEPTH = 30
local SIGN_STUDS_PER_UNIT = 0.035 -- billboard sizes below are in "units"; 400 units = 14 studs
local TUNNEL_TOP = 16.5 -- roughly where the carved tunnel's ceiling is
local MOUNTAIN_RING = 255 -- distance from the map center to the mountain peaks
local BARRIER_RADIUS = 205 -- invisible wall just inside the mountains

local PLOT_COLORS = {
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(120, 180, 255),
	Color3.fromRGB(140, 230, 140),
	Color3.fromRGB(255, 210, 110),
	Color3.fromRGB(200, 140, 255),
	Color3.fromRGB(110, 230, 220),
	Color3.fromRGB(255, 160, 210),
	Color3.fromRGB(230, 230, 230),
}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, size: Vector2, offset: Vector3, text: string, color: Color3): TextLabel
	local gui = Instance.new("BillboardGui")
	-- Sized in studs, so signs shrink with distance like real signs.
	gui.Size = UDim2.fromScale(size.X * SIGN_STUDS_PER_UNIT, size.Y * SIGN_STUDS_PER_UNIT)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 400
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.Parent = gui
	return l
end

local STORY_HEIGHT = 20
local DOOR_HEIGHT = 10
local STAIR_STEPS = 14
local STAIR_WIDTH = 8
local STAIR_RUN = 30 -- stairs climb from z = -26 (front) to z = 4
local WALL_THICKNESS = 2
local LASER_COUNT = 12
local GLASS_COLOR = Color3.fromRGB(80, 150, 255)

-- Ramps alternate sides: floor 1 -> 2 on the left, floor 2 -> 3 on the right...
local function rampSide(fromStory: number): number
	return if fromStory % 2 == 1 then -1 else 1
end

local function storyBase(story: number): number
	return FLOOR_TOP + (story - 1) * STORY_HEIGHT
end

-- Pedestal spots on upper floors, kept clear of the ramps on both sides.
local UPPER_PEDESTALS = {
	{ -15, 8 }, { -5, 8 }, { 5, 8 }, { 15, 8 },
	{ -15, 20 }, { -5, 20 }, { 5, 20 }, { 15, 20 },
	{ -5, -8 }, { 5, -8 },
}

-- One straight wall. `cf` is the bottom-center with local X running along the
-- wall. Walls 5+ studs tall get blue tinted windows set into real openings.
export type WallStyle = {
	Color: Color3,
	Material: Enum.Material,
	Glass: Color3,
	GlassNeon: boolean?,
}

local function wallSegment(folder: Instance, cf: CFrame, length: number, height: number, style: WallStyle)
	local function piece(name: string, x: number, y: number, width: number, h: number): Part
		local p = block(folder, name, Vector3.new(width, h, WALL_THICKNESS), cf * CFrame.new(x, y + h / 2, 0), style.Color, style.Material)
		return p
	end

	if height < 5 then
		piece("Wall", 0, 0, length, height)
		return
	end

	local sill = math.max(1, height * 0.3)
	local head = height * 0.78
	piece("WallBottom", 0, 0, length, sill)
	piece("WallTop", 0, head, length, height - head)

	local windowWidth = 4
	local count = math.max(1, math.floor(length / 12))
	local spacing = length / count
	local left = -length / 2
	for i = 1, count do
		local center = -length / 2 + spacing * (i - 0.5)
		local gapStart = center - windowWidth / 2
		if gapStart - left > 0.01 then
			piece("WallPillar", (left + gapStart) / 2, sill, gapStart - left, head - sill)
		end
		local glass = block(folder, "Window", Vector3.new(windowWidth, head - sill, 0.4), cf * CFrame.new(center, sill + (head - sill) / 2, 0), style.Glass, if style.GlassNeon then Enum.Material.Neon else Enum.Material.Glass)
		glass.Transparency = if style.GlassNeon then 0.35 else 0.45
		glass.Reflectance = 0.1
		left = center + windowWidth / 2
	end
	if length / 2 - left > 0.01 then
		piece("WallPillar", (left + length / 2) / 2, sill, length / 2 - left, head - sill)
	end
end

local function buildPlot(parent: Instance, index: number, center: Vector3): PlotParts
	local cf = CFrame.lookAt(center, Vector3.new(center.X, center.Y, 0))
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local half = PLOT_SIZE / 2

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("Locked", false)
	model.Parent = parent

	-- Local helper: x = right, y = up, z = toward the back of the base.
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- Floors are restyled by SetWallLevel to match the wall skin.
	local floors: { BasePart } = {
		block(model, "Floor", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), at(0, FLOOR_TOP - 0.5, 0), color, Enum.Material.Plastic),
	}

	local wallFolders: { [number]: Folder } = {}
	local groundWalls = Instance.new("Folder")
	groundWalls.Name = "Walls"
	groundWalls.Parent = model
	wallFolders[1] = groundWalls

	-- Entrance lasers: horizontal beams across the door. SetWallLevel marks
	-- which ones fit under the current wall height.
	local lasers: { BasePart } = {}
	for i = 1, LASER_COUNT do
		local beam = block(model, "Laser", Vector3.new(ENTRANCE_WIDTH, 0.3, 0.3), at(0, FLOOR_TOP + 0.8 + (i - 1) * 1.4, -half + 1), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
		beam.CanCollide = false
		beam.CastShadow = false
		beam.Transparency = 1
		beam:SetAttribute("Active", false)
		lasers[i] = beam
	end

	-- Ground floor pedestals: two rows of six at the back of the base.
	local pedestals: { BasePart } = {}
	local columns = { -25, -15, -5, 5, 15, 25 }
	local rows = { 8, 20 }
	for r, z in rows do
		for c, x in columns do
			local i = (r - 1) * #columns + c
			local pedestal = block(model, "Pedestal" .. i, Vector3.new(6, 1, 6), at(x, FLOOR_TOP + 0.5, z), Color3.fromRGB(60, 60, 70))
			pedestal:SetAttribute("Slot", i)
			pedestals[i] = pedestal
		end
	end

	-- Upper floors are built now and shown when bought (SetStories).
	local stories: { [number]: Folder } = {}
	local stairs: { { Carpet: Folder, Base: CFrame } } = {}
	for story = 2, #Config.Stories do
		local folder = Instance.new("Folder")
		folder.Name = "Story" .. story
		local y = storyBase(story)
		local side = rampSide(story - 1)

		-- Slab with a hole where the ramp from the floor below comes up.
		-- Edges stop inside the walls (x/z = +-29) so faces never overlap and flicker.
		local mainX = if side == -1 then 4.5 else -4.5
		table.insert(floors, block(folder, "Slab", Vector3.new(49, 1, 58), at(mainX, y - 0.5, 0), color, Enum.Material.Plastic))
		table.insert(floors, block(folder, "Slab", Vector3.new(9, 1, 25), at(side * 24.5, y - 0.5, 16.5), color, Enum.Material.Plastic))

		-- Open staircase up from the floor below: floating treads on two side
		-- beams, so brainrots behind and under it stay visible. Players walk on
		-- a thin invisible plank along the slope (smooth, and open underneath).
		local stairBase = at(side * 24, storyBase(story - 1), -26)
		local rise = STORY_HEIGHT / STAIR_STEPS
		local run = STAIR_RUN / STAIR_STEPS
		local slopeLength = math.sqrt(STAIR_RUN ^ 2 + STORY_HEIGHT ^ 2)
		local slopeAngle = math.atan2(STORY_HEIGHT, STAIR_RUN)
		-- Center of the slope line, tilted so local +Z climbs toward the back.
		local slope = stairBase * CFrame.new(0, STORY_HEIGHT / 2, STAIR_RUN / 2) * CFrame.Angles(-slopeAngle, 0, 0)

		local walkway = block(folder, "StairWalkway", Vector3.new(STAIR_WIDTH, 1, slopeLength), slope * CFrame.new(0, -0.5, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		walkway.Transparency = 1

		local wood = Color3.fromRGB(150, 105, 65)
		for _, beamSide in { -1, 1 } do
			local beam = block(folder, "StairBeam", Vector3.new(0.5, 1, slopeLength), slope * CFrame.new(beamSide * (STAIR_WIDTH / 2 - 0.25), -0.7, 0), wood:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.WoodPlanks)
			beam.CanCollide = false
		end
		for step = 1, STAIR_STEPS do
			local top = (step - 0.5) * rise
			local tread = block(folder, "Step", Vector3.new(STAIR_WIDTH - 1, 0.4, run * 0.9), stairBase * CFrame.new(0, top - 0.2, (step - 0.5) * run), wood, Enum.Material.WoodPlanks)
			tread.CanCollide = false
		end
		local carpet = Instance.new("Folder")
		carpet.Name = "Carpet"
		carpet.Parent = folder
		table.insert(stairs, { Carpet = carpet, Base = stairBase })

		for _, spot in UPPER_PEDESTALS do
			local i = #pedestals + 1
			local pedestal = block(folder, "Pedestal" .. i, Vector3.new(6, 1, 6), at(spot[1], y + 0.5, spot[2]), Color3.fromRGB(60, 60, 70))
			pedestal:SetAttribute("Slot", i)
			pedestals[i] = pedestal
		end

		local walls = Instance.new("Folder")
		walls.Name = "Walls"
		walls.Parent = folder
		wallFolders[story] = walls
		stories[story] = folder
	end

	-- Lights for every floor: ceiling panels when something is above, lamp
	-- posts on an open top floor. SetStories shows the right set.
	local lightSets: { [number]: { Ceiling: Folder, Posts: Folder } } = {}
	for story = 1, #Config.Stories do
		local y = storyBase(story)
		local holder: Instance = if story == 1 then model else stories[story]
		local ceiling = Instance.new("Folder")
		ceiling.Name = "CeilingLights"
		for _, spot in { { -12, -8 }, { 12, -8 }, { -12, 16 }, { 12, 16 } } do
			local panel = block(ceiling, "LightPanel", Vector3.new(6, 0.3, 2), at(spot[1], y + STORY_HEIGHT - 1.3, spot[2]), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
			panel.CanCollide = false
			panel.CastShadow = false
		end
		local ceilingLight = Instance.new("PointLight")
		ceilingLight.Range = 40
		ceilingLight.Brightness = 1.3
		ceilingLight.Color = Color3.fromRGB(255, 235, 200)
		ceilingLight.Parent = ceiling:FindFirstChild("LightPanel")

		local posts = Instance.new("Folder")
		posts.Name = "PostLights"
		for i, spot in { { -25, -20 }, { 25, -20 }, { -25, 25 }, { 25, 25 } } do
			local pole = block(posts, "LampPole", Vector3.new(0.4, 6, 0.4), at(spot[1], y + 3, spot[2]), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
			pole.CanCollide = false
			local lamp = block(posts, "Lamp", Vector3.new(1.2, 1.2, 1.2), at(spot[1], y + 6.4, spot[2]), Color3.fromRGB(255, 235, 180), Enum.Material.Neon)
			lamp.Shape = Enum.PartType.Ball
			lamp.CanCollide = false
			if i == 1 then
				local light = Instance.new("PointLight")
				light.Range = 45
				light.Brightness = 1.2
				light.Color = Color3.fromRGB(255, 230, 180)
				light.Parent = lamp
			end
		end
		ceiling.Parent = holder
		posts.Parent = holder
		lightSets[story] = { Ceiling = ceiling, Posts = posts }
	end

	-- Roof: only once the base is fully upgraded.
	local roof = Instance.new("Folder")
	roof.Name = "Roof"
	do
		local top = storyBase(#Config.Stories) + STORY_HEIGHT
		local roofColor = Color3.fromRGB(90, 60, 55)
		block(roof, "RoofSlab", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), at(0, top + 0.5, 0), WALL_COLOR, Enum.Material.Concrete)
		for _, side in { -1, 1 } do
			-- Two wedges meet at a ridge along the middle (wedges rise toward local +Z).
			local wedge = Instance.new("WedgePart")
			wedge.Name = "RoofSlope"
			wedge.Anchored = true
			wedge.Size = Vector3.new(PLOT_SIZE + 2, 10, PLOT_SIZE / 2 + 1)
			wedge.CFrame = at(0, top + 6, side * (PLOT_SIZE / 4 + 0.5)) * CFrame.Angles(0, if side == 1 then math.pi else 0, 0)
			wedge.Color = roofColor
			wedge.Material = Enum.Material.Slate
			wedge.Parent = roof
		end
		local ridge = block(roof, "RoofRidge", Vector3.new(PLOT_SIZE + 3, 1.2, 1.2), at(0, top + 11.2, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
		ridge.Shape = Enum.PartType.Cylinder
		local star = block(roof, "RoofStar", Vector3.new(3, 3, 3), at(0, top + 13.5, 0), Color3.fromRGB(255, 215, 80), Enum.Material.Neon)
		star.Shape = Enum.PartType.Ball
	end

	local collectPad = block(model, "CollectPad", Vector3.new(8, 0.4, 8), at(12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(60, 220, 90), Enum.Material.Neon)
	local pendingLabel = billboard(collectPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "COLLECT\n$0", Color3.fromRGB(140, 255, 140))

	local lockPad = block(model, "LockPad", Vector3.new(8, 0.4, 8), at(-12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(230, 60, 60), Enum.Material.Neon)
	local lockLabel = billboard(lockPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "STEP TO LOCK", Color3.fromRGB(255, 140, 140))

	-- The upgrade post opens the upgrades panel (see HUD.client).
	local upgradePost = block(model, "UpgradePost", Vector3.new(2, 4, 2), at(-14, FLOOR_TOP + 2, -24), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	local upgradeLabel = billboard(upgradePost, Vector2.new(260, 80), Vector3.new(0, 5, 0), "UPGRADES", Color3.fromRGB(255, 210, 120))
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "UpgradePrompt"
	upgradePrompt.ActionText = "Open Upgrades"
	upgradePrompt.ObjectText = "Base Upgrades"
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = 10
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt:SetAttribute("Action", "OpenUpgrades")
	upgradePrompt.Parent = upgradePost

	local signPost = block(model, "Sign", Vector3.new(1, 1, 1), at(0, FLOOR_TOP + SIGN_HEIGHT, half - 1), WALL_COLOR)
	signPost.Transparency = 1
	signPost.CanCollide = false
	local ownerLabel = billboard(signPost, Vector2.new(400, 80), Vector3.zero, "EMPTY BASE", Color3.new(1, 1, 1))
	local labelGui = ownerLabel.Parent :: BillboardGui
	labelGui.MaxDistance = 500

	return {
		Index = index,
		Model = model,
		CFrame = cf * CFrame.new(0, FLOOR_TOP, 0),
		Pedestals = pedestals,
		CollectPad = collectPad,
		LockPad = lockPad,
		Lasers = lasers,
		WallFolders = wallFolders,
		Stories = stories,
		Stairs = stairs,
		Floors = floors,
		LightSets = lightSets,
		Roof = roof,
		SignPost = signPost,
		UpgradePost = upgradePost,
		UpgradeLabel = upgradeLabel,
		OwnerLabel = ownerLabel,
		PendingLabel = pendingLabel,
		LockLabel = lockLabel,
		SpawnCFrame = at(0, FLOOR_TOP + 4, -6) * CFrame.Angles(0, math.pi, 0),
	}
end

-- Rebuilds every floor's walls (with windows) for a wall level, and marks
-- which entrance laser beams cover the doorway. Floors with another floor
-- above get walls all the way up to it, so there are no gaps.
function WorldBuilder.SetWallLevel(parts: PlotParts, level: number, stories: number, skin: Config.WallSkin?)
	local info = Config.WallLevels[level] or Config.WallLevels[1]
	local style: WallStyle = {
		Color = if skin and skin.Color then skin.Color else WALL_COLOR,
		Material = if skin and skin.Material then skin.Material else info.Material,
		Glass = if skin and skin.Glass then skin.Glass else GLASS_COLOR,
		GlassNeon = if skin then skin.GlassNeon else nil,
	}
	-- Floors match the skin; Classic floors are grey in the walls' material.
	for _, floor in parts.Floors do
		floor.Color = if skin and skin.FloorColor then skin.FloorColor else style.Color
		floor.Material = if skin and skin.FloorMaterial then skin.FloorMaterial else style.Material
	end

	local half = PLOT_SIZE / 2
	local inner = PLOT_SIZE - WALL_THICKNESS * 2 -- back/front walls fit between the side walls
	local frontWidth = (inner - ENTRANCE_WIDTH) / 2
	local turn = CFrame.Angles(0, math.pi / 2, 0)
	local roofed = stories >= #Config.Stories

	-- Floors with a floor (or the roof) above get walls all the way up to it.
	local function heightOf(story: number): number
		return if story < stories or roofed then STORY_HEIGHT else info.Height
	end
	local doorHeight = math.min(heightOf(1), DOOR_HEIGHT)
	for story, folder in parts.WallFolders do
		folder:ClearAllChildren()
		local y = storyBase(story)
		local height = heightOf(story)
		local function at(x: number, z: number): CFrame
			return parts.CFrame * CFrame.new(x, y - FLOOR_TOP, z)
		end
		wallSegment(folder, at(-half + 1, 0) * turn, PLOT_SIZE, height, style)
		wallSegment(folder, at(half - 1, 0) * turn, PLOT_SIZE, height, style)
		wallSegment(folder, at(0, half - 1), inner, height, style)
		if story == 1 then
			local frontX = ENTRANCE_WIDTH / 2 + frontWidth / 2
			wallSegment(folder, at(-frontX, -half + 1), frontWidth, height, style)
			wallSegment(folder, at(frontX, -half + 1), frontWidth, height, style)
			-- Solid lintel above the doorway when the walls are taller than it.
			if height > doorHeight + 0.1 then
				block(folder, "Lintel", Vector3.new(ENTRANCE_WIDTH, height - doorHeight, WALL_THICKNESS), at(0, -half + 1) * CFrame.new(0, doorHeight + (height - doorHeight) / 2, 0), style.Color, style.Material)
			end
			-- Laser emitter posts on both sides of the door.
			for _, side in { -1, 1 } do
				local x = side * (ENTRANCE_WIDTH / 2 + 0.5)
				block(folder, "LaserPost", Vector3.new(1, doorHeight, 2.4), at(x, -half + 1) * CFrame.new(0, doorHeight / 2, 0), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
				block(folder, "LaserStrip", Vector3.new(0.25, doorHeight - 0.4, 0.25), at(x - side * 0.55, -half + 1) * CFrame.new(0, doorHeight / 2, 0), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
			end
		else
			wallSegment(folder, at(0, -half + 1), inner, height, style)
		end
	end

	for i, beam in parts.Lasers do
		beam:SetAttribute("Active", 0.8 + (i - 1) * 1.4 <= doorHeight - 0.4)
	end
end

-- Lays carpet on every staircase. Tier 0 = bare wood (see Config.CarpetTiers).
function WorldBuilder.SetCarpet(parts: PlotParts, tier: number)
	local info = Config.CarpetTiers[tier]
	local rise = STORY_HEIGHT / STAIR_STEPS
	local run = STAIR_RUN / STAIR_STEPS
	for _, stair in parts.Stairs do
		stair.Carpet:ClearAllChildren()
		if not info then
			continue
		end
		local width = STAIR_WIDTH - 1.6
		for step = 1, STAIR_STEPS do
			local top = (step - 0.5) * rise
			local z = (step - 0.5) * run
			local color = if info.Rainbow then Color3.fromHSV((step / STAIR_STEPS) % 1, 0.65, 1) else info.Color
			local function piece(name: string, size: Vector3, offset: CFrame, c: Color3, material: Enum.Material): Part
				local p = block(stair.Carpet, name, size, stair.Base * offset, c, material)
				p.CanCollide = false
				p.CastShadow = false
				return p
			end
			piece("CarpetTop", Vector3.new(width, 0.12, run * 0.9), CFrame.new(0, top + 0.06, z), color, info.Material)
			if info.Trim then
				for _, side in { -1, 1 } do
					piece("CarpetTrim", Vector3.new(0.3, 0.16, run * 0.9), CFrame.new(side * (width / 2 + 0.15), top + 0.08, z), info.Trim, Enum.Material.Foil)
				end
			end
			if info.Glow then
				piece("CarpetGlow", Vector3.new(width, 0.1, 0.18), CFrame.new(0, top + 0.14, z - run / 2 + 0.1), info.Glow, Enum.Material.Neon)
			end
		end
		if info.Sparkle then
			local emitterPart = block(stair.Carpet, "CarpetSparkles", Vector3.new(width, 0.2, STAIR_RUN), stair.Base * CFrame.new(0, STORY_HEIGHT / 2, STAIR_RUN / 2) * CFrame.Angles(math.atan2(STORY_HEIGHT, STAIR_RUN), 0, 0), info.Color, Enum.Material.SmoothPlastic)
			emitterPart.Transparency = 1
			emitterPart.CanCollide = false
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkles.Color = ColorSequence.new(info.Glow or info.Color)
			sparkles.LightEmission = 1
			sparkles.Rate = 15
			sparkles.Lifetime = NumberRange.new(0.6, 1.2)
			sparkles.Speed = NumberRange.new(0.5, 1.5)
			sparkles.Size = NumberSequence.new(0.3)
			sparkles.Parent = emitterPart
		end
	end
end

-- Shows the floors a base has bought and lifts the owner sign above them.
function WorldBuilder.SetStories(parts: PlotParts, count: number)
	local roofed = count >= #Config.Stories
	for story, folder in parts.Stories do
		folder.Parent = if story <= count then parts.Model else nil
	end
	for story, set in parts.LightSets do
		-- Ceiling lights under every floor or roof; lamp posts on an open top floor.
		local holder: Instance = if story == 1 then parts.Model else parts.Stories[story]
		local covered = story < count or roofed
		set.Ceiling.Parent = if covered then holder else nil
		set.Posts.Parent = if covered then nil else holder
	end
	parts.Roof.Parent = if roofed then parts.Model else nil
	local sign = parts.SignPost
	local signY = if roofed then storyBase(count) + STORY_HEIGHT + 17 else storyBase(count) + SIGN_HEIGHT
	sign.CFrame = sign.CFrame.Rotation + Vector3.new(sign.Position.X, signY, sign.Position.Z)
end

-- A rocky cave around one end of the conveyor. `facing` is the direction
-- its mouth opens (+1 = toward +X, -1 = toward -X). It's built with the
-- mouth at the origin and then moved into place.
local function buildCave(parent: Instance, name: string, mouthPosition: Vector3, facing: number, seed: number)
	local cave = Instance.new("Model")
	cave.Name = name
	cave.Parent = parent
	local mouthX = 0

	local darkRock = Color3.fromRGB(45, 40, 40)
	local backX = mouthX - CAVE_DEPTH
	local centerX = (mouthX + backX) / 2
	local halfWidth = 9 -- tunnel half-width; the belt and rails fit inside
	local height = 15 -- tunnel height

	-- The rock itself is Terrain: carveTunnel cuts this tunnel into the
	-- mountains. These parts are the dressing inside it.
	block(cave, "CaveFloor", Vector3.new(CAVE_DEPTH, 0.6, halfWidth * 2), CFrame.new(centerX, 0.3, 0), darkRock, Enum.Material.Slate)
	local rng = Random.new(seed)

	-- Stalactites hanging in the entrance.
	for _, z in { -6, -2.5, 1.5, 5 } do
		local length = rng:NextNumber(1.5, 3)
		local spike = Instance.new("WedgePart")
		spike.Name = "Stalactite"
		spike.Anchored = true
		spike.Size = Vector3.new(1.2, length, 1.2)
		spike.CFrame = CFrame.new(mouthX - 3, TUNNEL_TOP - length / 2 + 0.5, z) * CFrame.Angles(math.pi, 0, 0)
		spike.Color = darkRock
		spike.Material = Enum.Material.Slate
		spike.Parent = cave
	end

	-- Glowing crystals inside so you can see brainrots coming.
	local crystalColors = { Color3.fromRGB(170, 80, 255), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 80, 200) }
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local crystal = Instance.new("Part")
		crystal.Name = "Crystal"
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.Size = Vector3.new(0.8, rng:NextNumber(1.5, 3), 0.8)
		crystal.CFrame = CFrame.new(backX + 3 + (i - 1) * 3.2, rng:NextNumber(2, height - 3), side * (halfWidth - 0.3))
			* CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5))
		crystal.Color = crystalColors[(i - 1) % #crystalColors + 1]
		crystal.Material = Enum.Material.Neon
		crystal.Parent = cave
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 120, 255)
	glow.Range = 24
	glow.Brightness = 1.5
	local lightPart = block(cave, "CaveLight", Vector3.new(1, 1, 1), CFrame.new(centerX, height - 3, 0), Color3.new(0, 0, 0))
	lightPart.Transparency = 1
	lightPart.CanCollide = false
	glow.Parent = lightPart

	cave.WorldPivot = CFrame.new()
	cave:PivotTo(CFrame.new(mouthPosition) * CFrame.Angles(0, if facing < 0 then math.pi else 0, 0))
end

-- Mountains ---------------------------------------------------------------------
-- A ring of Terrain mountains around the whole map: grassy foothills, rocky
-- slopes and snowy peaks. Built once when the server starts.

-- Material by height, like real mountains: grass at the bottom, banded
-- rock up the slopes, and a slightly ragged snowline near the top.
local function materialFor(y: number, rng: Random): Enum.Material
	local snowline = 95 + rng:NextNumber(-10, 10)
	if y > snowline then
		return Enum.Material.Snow
	elseif y > snowline - 14 then
		return if rng:NextNumber() < 0.4 then Enum.Material.Snow else Enum.Material.Rock
	elseif y > 22 then
		-- Alternating rock bands read as layered cliffs.
		return if (y // 14) % 3 == 0 then Enum.Material.Slate else Enum.Material.Rock
	elseif y > 8 then
		return if rng:NextNumber() < 0.5 then Enum.Material.Ground else Enum.Material.Grass
	end
	return Enum.Material.Grass
end

-- One stack of shrinking, slightly wobbly terrain balls.
local function stack(terrain: Terrain, rng: Random, x: number, z: number, radius: number, height: number)
	local steps = math.max(5, math.floor(height / 16))
	for i = 0, steps do
		local t = i / steps
		local r = radius * (1 - t) ^ 0.85 + 4
		local wobble = radius * 0.18 * (1 - t)
		local center = Vector3.new(x + rng:NextNumber(-wobble, wobble), height * t * 0.92, z + rng:NextNumber(-wobble, wobble))
		terrain:FillBall(center, r, materialFor(center.Y, rng))
	end
end

-- One mountain: a grassy skirt, a main peak, a couple of lower side peaks
-- for a jagged silhouette, and snow patches on the tall ones.
local function mountain(terrain: Terrain, rng: Random, x: number, z: number, radius: number, height: number)
	terrain:FillBall(Vector3.new(x, -radius * 0.55, z), radius * 1.15, Enum.Material.Grass)
	stack(terrain, rng, x, z, radius, height)
	if height > 70 then
		for _ = 1, 2 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local offset = radius * rng:NextNumber(0.45, 0.65)
			stack(terrain, rng, x + math.cos(angle) * offset, z + math.sin(angle) * offset, radius * 0.6, height * rng:NextNumber(0.5, 0.72))
		end
	end
	if height > 115 then
		for _ = 1, 3 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local y = height * rng:NextNumber(0.62, 0.8)
			local reach = radius * (1 - y / height) * 0.9
			terrain:FillBall(Vector3.new(x + math.cos(angle) * reach, y, z + math.sin(angle) * reach), rng:NextNumber(6, 10), Enum.Material.Snow)
		end
	end
end

local function buildMountains(rng: Random)
	local terrain = workspace.Terrain
	-- Front ring of peaks, joined by lower ridges, then a taller back ring.
	local count = 28
	local previous: Vector3? = nil
	local first: Vector3? = nil
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
		local distance = MOUNTAIN_RING + rng:NextNumber(-8, 14)
		local point = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		mountain(terrain, rng, point.X, point.Z, rng:NextNumber(42, 58), rng:NextNumber(95, 175))
		if previous then
			local mid = (previous + point) / 2
			mountain(terrain, rng, mid.X, mid.Z, rng:NextNumber(34, 44), rng:NextNumber(45, 75))
		end
		previous = point
		first = first or point
	end
	if previous and first then
		local mid = (previous + first) / 2
		mountain(terrain, rng, mid.X, mid.Z, 40, 60)
	end
	for i = 1, 18 do
		local angle = (i / 18) * math.pi * 2 + 0.17
		local distance = MOUNTAIN_RING + 60 + rng:NextNumber(-10, 10)
		mountain(terrain, rng, math.cos(angle) * distance, math.sin(angle) * distance, rng:NextNumber(60, 75), rng:NextNumber(160, 240))
	end
end

-- Terrain grass for the whole map (instead of a flat plate), plus colors.
local LAKES = { Vector3.new(0, 0, 150), Vector3.new(0, 0, -150) }

local function buildGround()
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(92, 165, 72))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(118, 96, 70))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(128, 121, 114))
	terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(92, 90, 92))
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(240, 245, 252))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(222, 206, 152))
	terrain.WaterColor = Color3.fromRGB(55, 140, 170)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.4
	terrain.WaterWaveSize = 0.1
	pcall(function()
		(terrain :: any).Decoration = true -- swaying grass blades, where supported
	end)
	-- Top of the grass sits exactly at y = 0, where everything is built.
	terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(720, 8, 720), Enum.Material.Grass)
end

-- Small lakes with sandy edges in the open grass behind the bases.
local function buildLakes()
	local terrain = workspace.Terrain
	for _, lake in LAKES do
		terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -1, 0)), 2, 25, Enum.Material.Sand)
		terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -2.5, 0)), 5, 21, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -3, 0)), 4.5, 21, Enum.Material.Water)
	end
end

-- A rocky hill at one end of the conveyor, joined to the mountain ring,
-- with a rough tunnel carved through it for the conveyor.
local function carveTunnel(rng: Random, mouthX: number, facing: number)
	local terrain = workspace.Terrain
	local inward = -facing -- direction from the mouth into the mountain
	for i, offset in { 24, 50, 78, 104 } do
		local x = mouthX + inward * offset
		mountain(terrain, rng, x, rng:NextNumber(-4, 4), 34 + i * 3, 38 + i * 10)
	end
	-- Rounded tunnel along the conveyor, flared at the mouth.
	local length = 120
	local tunnel = CFrame.new(mouthX + inward * (length / 2 - 4), 7, 0) * CFrame.Angles(0, 0, math.pi / 2)
	terrain:FillCylinder(tunnel, length, 10, Enum.Material.Air)
	terrain:FillBall(Vector3.new(mouthX - inward * 2, 7, 0), 12, Enum.Material.Air)
	-- Flat stone floor (the carve dips below ground level).
	terrain:FillBlock(CFrame.new(mouthX + inward * (length / 2 - 8), -4, 0), Vector3.new(length + 8, 8, 24), Enum.Material.Slate)
	-- Keep the area in front of the mouth clear of foothills.
	terrain:FillBlock(CFrame.new(mouthX - inward * 12, 12, 0), Vector3.new(20, 24, 30), Enum.Material.Air)
end

-- Trees ------------------------------------------------------------------------

local function treeAt(parent: Instance, rng: Random, position: Vector3, pine: boolean)
	local tree = Instance.new("Model")
	tree.Name = if pine then "PineTree" else "Tree"
	tree.Parent = parent
	local scale = rng:NextNumber(0.85, 1.3)
	local trunkHeight = (if pine then 4 else 6) * scale
	local trunk = block(tree, "Trunk", Vector3.new(trunkHeight, 1.1 * scale, 1.1 * scale), CFrame.new(position + Vector3.new(0, trunkHeight / 2 - 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(105, 75, 50), Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	local top = position + Vector3.new(0, trunkHeight, 0)
	if pine then
		-- Fir: stacked, shrinking tiers of dark needles.
		local tiers = { { 7.5, 3.6, 0.6 }, { 6, 3.2, 2.9 }, { 4.4, 2.8, 5 }, { 2.6, 2.4, 6.8 } }
		for i, tier in tiers do
			local needles = block(tree, "Needles", Vector3.new(tier[1], tier[2], tier[1]) * scale, CFrame.new(top + Vector3.new(0, tier[3] * scale, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(38, 92 + i * 6, 52), Enum.Material.Grass)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = needles
			needles.CanCollide = false
		end
	else
		-- Round leafy canopy made of a few overlapping blobs.
		for i = 1, 3 do
			local size = rng:NextNumber(5.5, 7.5) * scale
			local offset = Vector3.new(rng:NextNumber(-1.6, 1.6), 1.2 + i * 0.8, rng:NextNumber(-1.6, 1.6)) * scale
			local leaves = block(tree, "Leaves", Vector3.new(size, size, size), CFrame.new(top + offset), Color3.fromRGB(70 + i * 8, 145 + i * 10, 60), Enum.Material.Grass)
			leaves.Shape = Enum.PartType.Ball
			leaves.CanCollide = false
		end
	end
end

-- Round trees along the foothills and firs up the mountain slopes, dropped
-- onto the terrain with raycasts (skipping water, snow and the play area).
local function buildTrees(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Trees"
	folder.Parent = parent
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local function clearOfPlayArea(x: number, z: number): boolean
		if math.abs(x) < 165 and math.abs(z) < 125 then
			return false -- bases, conveyor, shop
		end
		if math.abs(z) < 50 and math.abs(x) > 120 then
			return false -- the conveyor tunnels
		end
		for _, lake in LAKES do
			if (Vector3.new(x, 0, z) - lake).Magnitude < 32 then
				return false
			end
		end
		return true
	end
	local function place(minRadius: number, maxRadius: number, attempts: number, pine: boolean, maxHeight: number)
		for _ = 1, attempts do
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(minRadius, maxRadius)
			local x, z = math.cos(angle) * distance, math.sin(angle) * distance
			if clearOfPlayArea(x, z) then
				local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), params)
				if hit and hit.Material ~= Enum.Material.Water and hit.Material ~= Enum.Material.Snow and hit.Position.Y < maxHeight then
					treeAt(folder, rng, hit.Position, pine)
				end
			end
		end
	end
	place(150, 200, 45, false, 20) -- leafy trees in the open grass and foothills
	place(195, 300, 140, true, 85) -- firs up the slopes, below the snow
end

-- Gentle color grading so everything looks a bit richer.
local function buildLighting()
	if not Lighting:FindFirstChild("BrainrotGrade") then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "BrainrotGrade"
		grade.Saturation = 0.12
		grade.Contrast = 0.06
		grade.Brightness = 0.02
		grade.Parent = Lighting
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "BrainrotBloom"
		bloom.Intensity = 0.35
		bloom.Size = 20
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
		local rays = Instance.new("SunRaysEffect")
		rays.Name = "BrainrotSunRays"
		rays.Intensity = 0.04
		rays.Spread = 0.6
		rays.Parent = Lighting
	end
end

-- Invisible wall just inside the mountains so nobody can climb out.
local function buildBarrier(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "MapBarrier"
	folder.Parent = parent
	local segments = 64
	local width = 2 * math.pi * BARRIER_RADIUS / segments + 2
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local position = Vector3.new(math.cos(angle) * BARRIER_RADIUS, 250, math.sin(angle) * BARRIER_RADIUS)
		local wall = Instance.new("Part")
		wall.Name = "Barrier"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Size = Vector3.new(width, 500, 2)
		wall.CFrame = CFrame.lookAt(position, Vector3.new(0, 250, 0))
		wall.Parent = folder
	end
end

-- The shop tent: a round, striped circus-style tent (like Bee Swarm's) by
-- the cave the brainrots come out of. Inside: a Diamond counter (left) and
-- a Robux counter (right). The entrance faces the conveyor (-Z).
local function buildShop(parent: Instance, center: Vector3)
	local shop = Instance.new("Model")
	shop.Name = "ShopTent"
	shop.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(center + Vector3.new(x, y, z))
	end

	local blue = Color3.fromRGB(45, 95, 200)
	local cream = Color3.fromRGB(246, 240, 225)
	local gold = Color3.fromRGB(255, 200, 60)
	local radius = 11.5
	local wallHeight = 8
	local apex = 19
	local panels = 18

	-- Round wooden floor with a gold rim
	local floor = block(shop, "TentFloor", Vector3.new(1, radius * 2 + 1, radius * 2 + 1), at(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(165, 120, 80), Enum.Material.WoodPlanks)
	floor.Shape = Enum.PartType.Cylinder
	local rim = block(shop, "TentRim", Vector3.new(0.6, radius * 2 + 2, radius * 2 + 2), at(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), gold, Enum.Material.Foil)
	rim.Shape = Enum.PartType.Cylinder

	-- Striped canvas walls, open at the front for the entrance
	local panelWidth = 2 * math.pi * radius / panels + 0.3
	for i = 0, panels - 1 do
		local angle = (i + 0.5) / panels * math.pi * 2
		local direction = Vector3.new(math.sin(angle), 0, -math.cos(angle)) -- angle 0 = front (-Z)
		if math.abs(math.deg(angle) - 360 * math.round(angle / (2 * math.pi))) > 32 then
			local position = center + direction * radius + Vector3.new(0, 1 + wallHeight / 2, 0)
			local panel = block(shop, "Canvas", Vector3.new(panelWidth, wallHeight, 0.4), CFrame.lookAt(position, center + Vector3.new(0, 1 + wallHeight / 2, 0)), if i % 2 == 0 then blue else cream, Enum.Material.Fabric)
			panel.CastShadow = true
		end
	end

	-- Peaked striped roof: canvas strips from the rim up to the top
	local slant = math.sqrt(radius ^ 2 + (apex - wallHeight - 1) ^ 2)
	for i = 0, panels - 1 do
		local angle = (i + 0.5) / panels * math.pi * 2
		local direction = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local rimPoint = center + direction * (radius + 0.6) + Vector3.new(0, wallHeight + 0.7, 0)
		local top = center + Vector3.new(0, apex, 0)
		local mid = (rimPoint + top) / 2
		local strip = block(shop, "RoofCanvas", Vector3.new(panelWidth + 0.4, 0.35, slant + 0.8), CFrame.lookAt(mid, top), if i % 2 == 0 then blue else cream, Enum.Material.Fabric)
		strip.CastShadow = true
		-- Scalloped gold trim hanging off the edge of the roof
		local scallop = block(shop, "Scallop", Vector3.new(1.6, 1.6, 1.6), CFrame.new(center + direction * (radius + 0.9) + Vector3.new(0, wallHeight + 0.2, 0)), if i % 2 == 0 then gold else cream, Enum.Material.SmoothPlastic)
		scallop.Shape = Enum.PartType.Ball
		scallop.CanCollide = false
	end

	-- Center pole, gold top and a flag
	local pole = block(shop, "TentPole", Vector3.new(0.6, apex + 4, 0.6), at(0, (apex + 4) / 2, 0), Color3.fromRGB(120, 85, 55), Enum.Material.WoodPlanks)
	pole.CanCollide = false
	local finial = block(shop, "Finial", Vector3.new(1.4, 1.4, 1.4), at(0, apex + 4.4, 0), gold, Enum.Material.Foil)
	finial.Shape = Enum.PartType.Ball
	local flag = block(shop, "Flag", Vector3.new(0.15, 2, 3.2), at(0, apex + 3, 1.7), blue, Enum.Material.Fabric)
	flag.CanCollide = false

	-- Small spinning diamond floating over the tent (spun by Effects.client)
	local cyan = Color3.fromRGB(80, 220, 255)
	local diamond = block(shop, "BigDiamond", Vector3.new(3, 3, 3), at(0, apex + 8, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), cyan, Enum.Material.Neon)
	diamond.CanCollide = false
	diamond:SetAttribute("SpinCenter", diamond.CFrame)
	CollectionService:AddTag(diamond, "Spinner")
	local glow = Instance.new("PointLight")
	glow.Color = cyan
	glow.Range = 20
	glow.Brightness = 1
	glow.Parent = diamond

	-- Two counters inside, each with a prompt and a sign
	local counters = {
		{ X = -4.5, Color = cyan, Action = "DiamondShop", Text = "Diamond Shop", Sign = "DIAMONDS" },
		{ X = 4.5, Color = Color3.fromRGB(70, 220, 100), Action = "RobuxShop", Text = "Robux Shop", Sign = "ROBUX & EVENT" },
	}
	for _, info in counters do
		local counter = block(shop, "Counter", Vector3.new(7, 3.5, 2.5), at(info.X, 2.75, 4), Color3.fromRGB(150, 105, 70), Enum.Material.WoodPlanks)
		block(shop, "CounterTop", Vector3.new(7.4, 0.4, 2.9), at(info.X, 4.7, 4), info.Color, Enum.Material.Neon)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = info.Text
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", info.Action)
		prompt.Parent = counter
		local label = billboard(counter, Vector2.new(220, 45), Vector3.new(0, 4.5, 0), info.Sign, info.Color)
		;(label.Parent :: BillboardGui).MaxDistance = 250
	end
	-- Warm lantern light inside
	local lantern = block(shop, "Lantern", Vector3.new(1.2, 1.2, 1.2), at(0, wallHeight + 1, 0), Color3.fromRGB(255, 220, 150), Enum.Material.Neon)
	lantern.Shape = Enum.PartType.Ball
	lantern.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lantern

	-- Sign over the entrance
	local signAnchor = block(shop, "ShopSignAnchor", Vector3.new(1, 1, 1), at(0, wallHeight + 4, -radius - 1), Color3.new(0, 0, 0))
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	local sign = billboard(signAnchor, Vector2.new(420, 80), Vector3.zero, "SHOP", gold)
	;(sign.Parent :: BillboardGui).MaxDistance = 500
end

function WorldBuilder.Build(): World
	local existing = workspace:FindFirstChild("BrainrotHeist")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "BrainrotHeist"
	root.Parent = workspace

	-- A Baseplate sitting too high would bury the map; put its top at y = 0.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		-- Tucked under the terrain grass (which tops out at y = 0).
		baseplate.CFrame = CFrame.new(0, -12 - baseplate.Size.Y / 2, 0)
	end

	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	-- Light haze so the distant mountains fade into the sky.
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(200, 215, 230)
		atmosphere.Decay = Color3.fromRGB(110, 125, 145)
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end

	-- Ground under everything, in case the Baseplate was removed. Its top sits
	-- slightly above the Baseplate's so the two surfaces don't flicker.
	buildGround()
	buildLighting()

	-- Conveyor
	local columnsPerSide = Config.PlotCount // 2
	local length = columnsPerSide * PLOT_SPACING + 40
	local conveyorFolder = Instance.new("Folder")
	conveyorFolder.Name = "Conveyor"
	conveyorFolder.Parent = root

	block(conveyorFolder, "Belt", Vector3.new(length, 1, 12), CFrame.new(0, 0.5, 0), Color3.fromRGB(40, 40, 45), Enum.Material.DiamondPlate)
	for _, z in { -6.5, 6.5 } do
		block(conveyorFolder, "Rail", Vector3.new(length, 1.5, 1), CFrame.new(0, 1.25, z), Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
	end

	-- Brainrots spawn inside one cave, ride out of its mouth, and disappear
	-- into a second cave at the far end.
	local mouthX = -length / 2 + 14
	local exitMouthX = length / 2 - 14
	local terrainRng = Random.new(2026)
	buildMountains(terrainRng)
	buildLakes()
	carveTunnel(terrainRng, mouthX, 1)
	carveTunnel(terrainRng, exitMouthX, -1)
	buildTrees(root, terrainRng)
	buildBarrier(root)
	buildCave(root, "BrainrotCave", Vector3.new(mouthX, 0, 0), 1, 7)
	buildCave(root, "ExitCave", Vector3.new(exitMouthX, 0, 0), -1, 11)
	local startX = mouthX - 10
	local endX = exitMouthX + 10
	local sign = block(conveyorFolder, "ShopSign", Vector3.new(1, 1, 1), CFrame.new(mouthX + 6, 28, 0), Color3.new(1, 1, 1))
	sign.Transparency = 1
	sign.CanCollide = false
	local signLabel = billboard(sign, Vector2.new(420, 90), Vector3.zero, "BRAINROT CONVEYOR\nBuy one before it's gone!", Color3.fromRGB(255, 230, 80))
	;(signLabel.Parent :: BillboardGui).MaxDistance = 500

	-- Plots: half on each side of the conveyor, entrances facing it.
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root

	local plots = {}
	for i = 1, Config.PlotCount do
		local side = if i <= columnsPerSide then 1 else -1
		local column = (i - 1) % columnsPerSide
		local x = (column - (columnsPerSide - 1) / 2) * PLOT_SPACING
		plots[i] = buildPlot(plotsFolder, i, Vector3.new(x, 0, side * PLOT_DISTANCE))
		WorldBuilder.SetWallLevel(plots[i], 1, 1)
		WorldBuilder.SetStories(plots[i], 1)
		WorldBuilder.SetCarpet(plots[i], 0)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	-- Beside the middle of the conveyor, right in front of the Diamond Shop.
	-- The shop tent and the event statue sit by the cave the brainrots come
	-- out of, on either side of the conveyor, keeping the middle clear.
	local shopPosition = Vector3.new(startX + 38, 0, 27)
	local statuePosition = Vector3.new(startX + 38, 0, -27)
	buildShop(root, shopPosition)
	spawn.Size = Vector3.new(10, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 14)
	-- Invisible pad: players still spawn here, there's just no plate to see.
	spawn.Transparency = 1
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	-- Any template spawn would drop players onto the conveyor; ours replaces it.
	for _, other in workspace:GetChildren() do
		if other:IsA("SpawnLocation") then
			other.Enabled = false
		end
	end

	local carried = Instance.new("Folder")
	carried.Name = "Carried"
	carried.Parent = root

	return {
		Plots = plots,
		ConveyorStart = Vector3.new(startX, 1, 0),
		ConveyorEnd = Vector3.new(endX, 1, 0),
		CarriedFolder = carried,
		ConveyorFolder = conveyorFolder,
		ShopPosition = shopPosition,
		StatuePosition = statuePosition,
	}
end

return WorldBuilder

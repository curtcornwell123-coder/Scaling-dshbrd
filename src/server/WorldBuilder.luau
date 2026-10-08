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
	ShopPosition: Vector3, -- center of the Diamond Shop booth
}

local PLOT_SIZE = 60
local PLOT_DISTANCE = 75 -- from the conveyor to each plot's center
local PLOT_SPACING = 70
local SIGN_HEIGHT = 24
local ENTRANCE_WIDTH = 16
local FLOOR_TOP = 1
local WALL_COLOR = Color3.fromRGB(140, 140, 145) -- every base's fence is the same grey
local CAVE_DEPTH = 30

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
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 120
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

	block(model, "Floor", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), at(0, FLOOR_TOP - 0.5, 0), color, Enum.Material.Plastic)

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
		block(folder, "Slab", Vector3.new(49, 1, 58), at(mainX, y - 0.5, 0), color, Enum.Material.Plastic)
		block(folder, "Slab", Vector3.new(9, 1, 25), at(side * 24.5, y - 0.5, 16.5), color, Enum.Material.Plastic)

		-- Staircase up from the floor below. Players walk on an invisible
		-- ramp so climbing is smooth; the steps on top are just for looks.
		local ramp = Instance.new("WedgePart")
		ramp.Name = "StairRamp"
		ramp.Anchored = true
		ramp.Transparency = 1
		ramp.Size = Vector3.new(STAIR_WIDTH, STORY_HEIGHT, STAIR_RUN)
		ramp.CFrame = at(side * 24, storyBase(story - 1) + STORY_HEIGHT / 2, -26 + STAIR_RUN / 2)
		ramp.Parent = folder

		local stairBase = at(side * 24, storyBase(story - 1), -26)
		local rise = STORY_HEIGHT / STAIR_STEPS
		local run = STAIR_RUN / STAIR_STEPS
		for step = 1, STAIR_STEPS do
			local top = (step - 0.5) * rise
			local stepPart = block(folder, "Step", Vector3.new(STAIR_WIDTH, top, run), stairBase * CFrame.new(0, top / 2, (step - 0.5) * run), Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
			stepPart.CanCollide = false
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
	labelGui.MaxDistance = 250

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
		local width = STAIR_WIDTH - 2
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
			piece("CarpetTop", Vector3.new(width, 0.12, run), CFrame.new(0, top + 0.06, z), color, info.Material)
			piece("CarpetRiser", Vector3.new(width, math.min(rise, top), 0.12), CFrame.new(0, top - math.min(rise, top) / 2, z - run / 2 - 0.06), color, info.Material)
			if info.Trim then
				for _, side in { -1, 1 } do
					piece("CarpetTrim", Vector3.new(0.35, 0.16, run), CFrame.new(side * (width / 2 + 0.17), top + 0.08, z), info.Trim, Enum.Material.Foil)
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

	local rock = Color3.fromRGB(105, 95, 90)
	local darkRock = Color3.fromRGB(45, 40, 40)
	local backX = mouthX - CAVE_DEPTH
	local centerX = (mouthX + backX) / 2
	local halfWidth = 9 -- tunnel half-width; the belt and rails fit inside
	local height = 15 -- tunnel height
	local wall = 10

	-- Shell: two side walls, a roof and a back wall, leaving a tunnel open at the mouth.
	for _, side in { -1, 1 } do
		block(cave, "CaveWall", Vector3.new(CAVE_DEPTH, height + 6, wall), CFrame.new(centerX, (height + 6) / 2, side * (halfWidth + wall / 2)), rock, Enum.Material.Rock)
		block(cave, "CaveInner", Vector3.new(CAVE_DEPTH, height, 0.4), CFrame.new(centerX, height / 2, side * (halfWidth + 0.2)), darkRock, Enum.Material.Slate)
	end
	block(cave, "CaveRoof", Vector3.new(CAVE_DEPTH, 8, halfWidth * 2 + wall * 2), CFrame.new(centerX, height + 4, 0), rock, Enum.Material.Rock)
	block(cave, "CaveCeiling", Vector3.new(CAVE_DEPTH, 0.4, halfWidth * 2), CFrame.new(centerX, height - 0.2, 0), darkRock, Enum.Material.Slate)
	block(cave, "CaveBack", Vector3.new(4, height + 8, halfWidth * 2 + wall * 2), CFrame.new(backX - 2, (height + 8) / 2, 0), rock, Enum.Material.Rock)
	block(cave, "CaveFloor", Vector3.new(CAVE_DEPTH, 0.6, halfWidth * 2), CFrame.new(centerX, 0.3, 0), darkRock, Enum.Material.Slate)

	-- Boulders piled over the shell so it reads as a hill, not a box.
	local rng = Random.new(seed)
	local function boulder(position: Vector3, size: number, color: Color3)
		local b = Instance.new("Part")
		b.Name = "Boulder"
		b.Shape = Enum.PartType.Ball
		b.Anchored = true
		b.Size = Vector3.new(size, size, size)
		b.CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		b.Color = color
		b.Material = Enum.Material.Rock
		b.TopSurface = Enum.SurfaceType.Smooth
		b.BottomSurface = Enum.SurfaceType.Smooth
		b.Parent = cave
	end
	for _ = 1, 26 do
		local x = rng:NextNumber(backX, mouthX - 2)
		local z = rng:NextNumber(-halfWidth - wall, halfWidth + wall)
		local y = if math.abs(z) < halfWidth + 2 then rng:NextNumber(height + 6, height + 10) else rng:NextNumber(6, height + 8)
		local shade = rng:NextNumber(0.85, 1.15)
		boulder(Vector3.new(x, y, z), rng:NextNumber(7, 13), Color3.new(rock.R * shade, rock.G * shade, rock.B * shade))
	end

	-- Arch of rocks framing the mouth.
	for i = 0, 10 do
		local angle = math.pi * i / 10
		local z = math.cos(angle) * (halfWidth + 2.5)
		local y = math.sin(angle) * (height - 2) + 1.5
		boulder(Vector3.new(mouthX + 0.5, y, z), rng:NextNumber(3.5, 5), rock:Lerp(darkRock, 0.25))
	end

	-- Stalactites hanging in the entrance.
	for _, z in { -6, -2.5, 1.5, 5 } do
		local length = rng:NextNumber(1.5, 3)
		local spike = Instance.new("WedgePart")
		spike.Name = "Stalactite"
		spike.Anchored = true
		spike.Size = Vector3.new(1.2, length, 1.2)
		spike.CFrame = CFrame.new(mouthX - 2, height - length / 2 - 0.3, z) * CFrame.Angles(math.pi, 0, 0)
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

-- The Diamond Shop: a bright booth by the spawn with a giant spinning
-- diamond on top. Left counter = Diamond Shop, right counter = Robux Shop.
-- Its front (the counters) faces the conveyor (-Z).
local function buildShop(parent: Instance, center: Vector3)
	local shop = Instance.new("Model")
	shop.Name = "DiamondShop"
	shop.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(center + Vector3.new(x, y, z))
	end

	local cyan = Color3.fromRGB(80, 220, 255)
	local pink = Color3.fromRGB(255, 90, 200)
	local gold = Color3.fromRGB(255, 200, 60)
	local purple = Color3.fromRGB(110, 50, 190)

	-- Platform with a glowing trim
	block(shop, "ShopFloor", Vector3.new(26, 1, 14), at(0, 0.5, 0), Color3.fromRGB(245, 240, 255), Enum.Material.Marble)
	block(shop, "ShopTrim", Vector3.new(26.6, 0.4, 14.6), at(0, 0.2, 0), cyan, Enum.Material.Neon)
	block(shop, "ShopBack", Vector3.new(26, 12, 1), at(0, 7, 6.5), purple, Enum.Material.SmoothPlastic)
	for _, x in { -12.5, 12.5 } do
		for _, z in { -6.5, 6.5 } do
			block(shop, "ShopPillar", Vector3.new(1, 12, 1), at(x, 7, z), gold, Enum.Material.Foil)
		end
	end

	-- Striped awning roof, tilted down toward the front
	for i = 0, 7 do
		local stripe = block(shop, "Awning", Vector3.new(3.4, 0.5, 15.5), at(-11.9 + i * 3.4, 13.4, 0) * CFrame.Angles(math.rad(-10), 0, 0), if i % 2 == 0 then pink else Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		stripe.CastShadow = false
	end
	for i = 0, 12 do
		local scallop = block(shop, "Scallop", Vector3.new(2, 2, 2), at(-12 + i * 2, 12.1, -7.6), if i % 2 == 0 then pink else Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		scallop.Shape = Enum.PartType.Ball
	end

	-- Two counters, each with a prompt and a sign
	local counters = {
		{ X = -6, Color = cyan, Action = "DiamondShop", Text = "Diamond Shop", Sign = "DIAMONDS" },
		{ X = 6, Color = Color3.fromRGB(70, 220, 100), Action = "RobuxShop", Text = "Robux Shop", Sign = "ROBUX & EVENT" },
	}
	for _, info in counters do
		local counter = block(shop, "Counter", Vector3.new(9, 3.5, 2.5), at(info.X, 2.75, -3), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic)
		block(shop, "CounterTop", Vector3.new(9.4, 0.4, 2.9), at(info.X, 4.7, -3), info.Color, Enum.Material.Neon)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = info.Text
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", info.Action)
		prompt.Parent = counter
		local label = billboard(counter, Vector2.new(260, 50), Vector3.new(0, 5.5, 0), info.Sign, info.Color)
		;(label.Parent :: BillboardGui).MaxDistance = 90
	end

	-- Big glowing sign on the back wall
	local signAnchor = block(shop, "ShopSignAnchor", Vector3.new(1, 1, 1), at(0, 10, 5.8), Color3.new(0, 0, 0))
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	local sign = billboard(signAnchor, Vector2.new(460, 90), Vector3.zero, "DIAMOND SHOP", cyan)
	;(sign.Parent :: BillboardGui).MaxDistance = 300

	-- Giant spinning diamond on top (spun by Effects.client via the tag)
	block(shop, "DiamondStand", Vector3.new(3, 2, 3), at(0, 15, 0), gold, Enum.Material.Foil)
	local diamond = block(shop, "BigDiamond", Vector3.new(4.5, 4.5, 4.5), at(0, 19.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), cyan, Enum.Material.Neon)
	diamond.CanCollide = false
	diamond:SetAttribute("SpinCenter", diamond.CFrame)
	CollectionService:AddTag(diamond, "Spinner")
	local glow = Instance.new("PointLight")
	glow.Color = cyan
	glow.Range = 35
	glow.Brightness = 2
	glow.Parent = diamond
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(cyan, Color3.new(1, 1, 1))
	sparkles.LightEmission = 1
	sparkles.Rate = 20
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.5)
	sparkles.Parent = diamond

	-- Searchlights sweeping up from the front corners
	for _, side in { -1, 1 } do
		local beam = block(shop, "Searchlight", Vector3.new(1.2, 60, 1.2), at(side * 12.5, 30, -6.5) * CFrame.Angles(0, 0, side * math.rad(-12)), if side < 0 then cyan else pink, Enum.Material.Neon)
		beam.Transparency = 0.7
		beam.CanCollide = false
		beam.CastShadow = false
	end
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
		baseplate.CFrame = CFrame.new(0, -baseplate.Size.Y / 2, 0)
	end

	Lighting.ClockTime = 14
	Lighting.Brightness = 2

	-- Ground under everything, in case the Baseplate was removed. Its top sits
	-- slightly above the Baseplate's so the two surfaces don't flicker.
	block(root, "Ground", Vector3.new(700, 2, 400), CFrame.new(0, -0.9, 0), Color3.fromRGB(90, 160, 80), Enum.Material.Grass)

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
	buildCave(root, "BrainrotCave", Vector3.new(mouthX, 0, 0), 1, 7)
	buildCave(root, "ExitCave", Vector3.new(exitMouthX, 0, 0), -1, 11)
	local startX = mouthX - 10
	local endX = exitMouthX + 10
	local sign = block(conveyorFolder, "ShopSign", Vector3.new(1, 1, 1), CFrame.new(mouthX - CAVE_DEPTH / 2, 30, 0), Color3.new(1, 1, 1))
	sign.Transparency = 1
	sign.CanCollide = false
	local signLabel = billboard(sign, Vector2.new(420, 90), Vector3.zero, "BRAINROT CONVEYOR\nBuy one before it's gone!", Color3.fromRGB(255, 230, 80))
	;(signLabel.Parent :: BillboardGui).MaxDistance = 300

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
	local shopPosition = Vector3.new(0, 0, 28)
	buildShop(root, shopPosition)
	spawn.Size = Vector3.new(10, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 14)
	spawn.Color = Color3.fromRGB(255, 200, 40)
	spawn.Material = Enum.Material.Neon
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
	}
end

return WorldBuilder

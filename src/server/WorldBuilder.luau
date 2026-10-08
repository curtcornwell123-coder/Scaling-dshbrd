--!strict
-- Builds the map: a conveyor down the middle and player bases on both sides.
-- Everything is made from parts so the place works from an empty Baseplate.

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
local function wallSegment(folder: Instance, cf: CFrame, length: number, height: number, material: Enum.Material)
	local function piece(name: string, x: number, y: number, width: number, h: number): Part
		local p = block(folder, name, Vector3.new(width, h, WALL_THICKNESS), cf * CFrame.new(x, y + h / 2, 0), WALL_COLOR, material)
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
		local glass = block(folder, "Window", Vector3.new(windowWidth, head - sill, 0.4), cf * CFrame.new(center, sill + (head - sill) / 2, 0), GLASS_COLOR, Enum.Material.Glass)
		glass.Transparency = 0.45
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
	for story = 2, #Config.Stories do
		local folder = Instance.new("Folder")
		folder.Name = "Story" .. story
		local y = storyBase(story)
		local side = rampSide(story - 1)

		-- Slab with a hole where the ramp from the floor below comes up.
		local mainX = if side == -1 then 5 else -5
		block(folder, "Slab", Vector3.new(50, 1, PLOT_SIZE), at(mainX, y - 0.5, 0), color, Enum.Material.Plastic)
		block(folder, "Slab", Vector3.new(10, 1, 26), at(side * 25, y - 0.5, 17), color, Enum.Material.Plastic)

		local ramp = Instance.new("WedgePart")
		ramp.Name = "Ramp"
		ramp.Anchored = true
		ramp.Size = Vector3.new(8, STORY_HEIGHT, 30)
		ramp.CFrame = at(side * 24, storyBase(story - 1) + STORY_HEIGHT / 2, -11)
		ramp.Color = Color3.fromRGB(110, 110, 120)
		ramp.Material = Enum.Material.DiamondPlate
		ramp.Parent = folder

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

	local collectPad = block(model, "CollectPad", Vector3.new(8, 0.4, 8), at(12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(60, 220, 90), Enum.Material.Neon)
	local pendingLabel = billboard(collectPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "COLLECT\n$0", Color3.fromRGB(140, 255, 140))

	local lockPad = block(model, "LockPad", Vector3.new(8, 0.4, 8), at(-12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(230, 60, 60), Enum.Material.Neon)
	local lockLabel = billboard(lockPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "STEP TO LOCK", Color3.fromRGB(255, 140, 140))

	-- One post, three upgrades, each on its own key.
	local upgradePost = block(model, "UpgradePost", Vector3.new(2, 4, 2), at(-14, FLOOR_TOP + 2, -24), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	local upgradeLabel = billboard(upgradePost, Vector2.new(300, 110), Vector3.new(0, 6, 0), "UPGRADES", Color3.fromRGB(255, 210, 120))
	local upgrades: { { Kind: string, Text: string, Key: Enum.KeyCode } } = {
		{ Kind = "Walls", Text = "Upgrade Walls", Key = Enum.KeyCode.E },
		{ Kind = "Floors", Text = "Build Floor", Key = Enum.KeyCode.R },
		{ Kind = "Lock", Text = "Upgrade Lock", Key = Enum.KeyCode.T },
	}
	for _, info in upgrades do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = info.Kind .. "Prompt"
		prompt.ActionText = info.Text
		prompt.ObjectText = "Base Upgrades"
		prompt.KeyboardKeyCode = info.Key
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", "Upgrade")
		prompt:SetAttribute("UpgradeType", info.Kind)
		prompt.Parent = upgradePost
	end

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
-- which entrance laser beams fit under the new height.
function WorldBuilder.SetWallLevel(parts: PlotParts, level: number)
	local info = Config.WallLevels[level] or Config.WallLevels[1]
	local height = info.Height
	local half = PLOT_SIZE / 2
	local frontWidth = (PLOT_SIZE - ENTRANCE_WIDTH) / 2
	local turn = CFrame.Angles(0, math.pi / 2, 0)

	for story, folder in parts.WallFolders do
		folder:ClearAllChildren()
		local y = storyBase(story)
		local function at(x: number, z: number): CFrame
			return parts.CFrame * CFrame.new(x, y - FLOOR_TOP, z)
		end
		wallSegment(folder, at(0, half - 1), PLOT_SIZE, height, info.Material)
		wallSegment(folder, at(-half + 1, 0) * turn, PLOT_SIZE, height, info.Material)
		wallSegment(folder, at(half - 1, 0) * turn, PLOT_SIZE, height, info.Material)
		if story == 1 then
			wallSegment(folder, at(-half + frontWidth / 2, -half + 1), frontWidth, height, info.Material)
			wallSegment(folder, at(half - frontWidth / 2, -half + 1), frontWidth, height, info.Material)
			-- Laser emitter posts on both sides of the door.
			for _, side in { -1, 1 } do
				local x = side * (ENTRANCE_WIDTH / 2 + 0.5)
				block(folder, "LaserPost", Vector3.new(1, height, 2.4), at(x, -half + 1) * CFrame.new(0, height / 2, 0), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
				block(folder, "LaserStrip", Vector3.new(0.25, height - 0.4, 0.25), at(x - side * 0.55, -half + 1) * CFrame.new(0, height / 2, 0), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
			end
		else
			wallSegment(folder, at(0, -half + 1), PLOT_SIZE, height, info.Material)
		end
	end

	for i, beam in parts.Lasers do
		beam:SetAttribute("Active", 0.8 + (i - 1) * 1.4 <= height - 0.4)
	end
end

-- Shows the floors a base has bought and lifts the owner sign above them.
function WorldBuilder.SetStories(parts: PlotParts, count: number)
	for story, folder in parts.Stories do
		folder.Parent = if story <= count then parts.Model else nil
	end
	local sign = parts.SignPost
	sign.CFrame = sign.CFrame.Rotation + Vector3.new(sign.Position.X, storyBase(count) + SIGN_HEIGHT, sign.Position.Z)
end

-- A rocky cave around the start of the conveyor, opening toward +X.
local function buildCave(parent: Instance, mouthX: number)
	local cave = Instance.new("Model")
	cave.Name = "BrainrotCave"
	cave.Parent = parent

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
	local rng = Random.new(7)
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

	-- Brainrots spawn inside the cave and ride out of its mouth.
	local mouthX = -length / 2 + 14
	buildCave(root, mouthX)
	local startX = mouthX - 10
	local endX = length / 2 - 6
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
		WorldBuilder.SetWallLevel(plots[i], 1)
		WorldBuilder.SetStories(plots[i], 1)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(endX + 20, 0.5, 0)
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
	}
end

return WorldBuilder

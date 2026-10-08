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
	Laser: BasePart,
	Walls: { BasePart },
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

	-- Walls are built 1 stud tall here; SetWallLevel sizes them.
	local wallColor = WALL_COLOR
	local frontWidth = (PLOT_SIZE - ENTRANCE_WIDTH) / 2
	local walls = {
		block(model, "WallBack", Vector3.new(PLOT_SIZE, 1, 2), at(0, FLOOR_TOP, half - 1), wallColor),
		block(model, "WallLeft", Vector3.new(2, 1, PLOT_SIZE), at(-half + 1, FLOOR_TOP, 0), wallColor),
		block(model, "WallRight", Vector3.new(2, 1, PLOT_SIZE), at(half - 1, FLOOR_TOP, 0), wallColor),
		block(model, "WallFrontL", Vector3.new(frontWidth, 1, 2), at(-half + frontWidth / 2, FLOOR_TOP, -half + 1), wallColor),
		block(model, "WallFrontR", Vector3.new(frontWidth, 1, 2), at(half - frontWidth / 2, FLOOR_TOP, -half + 1), wallColor),
	} :: { BasePart }

	local laser = block(model, "Laser", Vector3.new(ENTRANCE_WIDTH, 1, 0.6), at(0, FLOOR_TOP, -half + 1), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	laser.CanCollide = false
	laser.Transparency = 1

	-- Pedestals: two rows of six at the back of the base.
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

	local collectPad = block(model, "CollectPad", Vector3.new(8, 0.4, 8), at(12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(60, 220, 90), Enum.Material.Neon)
	local pendingLabel = billboard(collectPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "COLLECT\n$0", Color3.fromRGB(140, 255, 140))

	local lockPad = block(model, "LockPad", Vector3.new(8, 0.4, 8), at(-12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(230, 60, 60), Enum.Material.Neon)
	local lockLabel = billboard(lockPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "STEP TO LOCK", Color3.fromRGB(255, 140, 140))

	local upgradePost = block(model, "UpgradePost", Vector3.new(2, 4, 2), at(-22, FLOOR_TOP + 2, -22), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	local upgradeLabel = billboard(upgradePost, Vector2.new(240, 70), Vector3.new(0, 5, 0), "WALLS", Color3.fromRGB(255, 210, 120))
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "UpgradePrompt"
	upgradePrompt.ActionText = "Upgrade Walls"
	upgradePrompt.ObjectText = "Walls"
	upgradePrompt.HoldDuration = 0.4
	upgradePrompt.MaxActivationDistance = 10
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt:SetAttribute("Action", "Upgrade")
	upgradePrompt.Parent = upgradePost

	local signPost = block(model, "Sign", Vector3.new(1, 1, 1), at(0, FLOOR_TOP + SIGN_HEIGHT, half - 1), wallColor)
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
		Laser = laser,
		Walls = walls,
		UpgradePost = upgradePost,
		UpgradeLabel = upgradeLabel,
		OwnerLabel = ownerLabel,
		PendingLabel = pendingLabel,
		LockLabel = lockLabel,
		SpawnCFrame = at(0, FLOOR_TOP + 4, -6) * CFrame.Angles(0, math.pi, 0),
	}
end

-- Resizes a base's walls and entrance laser to a wall level from Config.
function WorldBuilder.SetWallLevel(parts: PlotParts, level: number)
	local info = Config.WallLevels[level] or Config.WallLevels[1]
	local function resize(part: BasePart)
		part.Size = Vector3.new(part.Size.X, info.Height, part.Size.Z)
		local p = part.Position
		part.CFrame = part.CFrame.Rotation + Vector3.new(p.X, FLOOR_TOP + info.Height / 2, p.Z)
	end
	for _, wall in parts.Walls do
		resize(wall)
		wall.Material = info.Material
		wall.Transparency = if info.Material == Enum.Material.Glass then 0.3 else 0
	end
	resize(parts.Laser)

	local nextInfo = Config.WallLevels[level + 1]
	parts.UpgradeLabel.Text = if nextInfo
		then string.format("%s (Lv %d)\nNext: %s", info.Name, level, Config.FormatCash(nextInfo.Cost))
		else string.format("%s (MAX)", info.Name)
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

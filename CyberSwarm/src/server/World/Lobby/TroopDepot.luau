--!strict
--[[
	TroopDepot
	The troop shop room. Entrance: a rounded concrete arch with a hazard-striped grated lip, a
	purple "TROOPS" sign with a low-poly robot icon, and a coin/gem counter screen. Inside: a red
	and white concentric floor emblem, six display tables with rotating plinths (three permanent,
	three daily), each with a name plate screen and rarity trim, a rotation timer screen, and the
	Troop Shop terminal. The plinth models, plates, and trim colours are filled in by each client
	from TroopRotation, which every server and client computes the same way.

	At the back: the TEST REALM glass wall (cyan grid), its sign and target icon, and the portal
	pad; the training yard is visible through the glass.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Room = require(script.Parent.Room)

local World = Theme.World
local Areas = Theme.Areas
local Screen = Constants.ScreenKind

local HEIGHT = 24
local TABLE_SIZE = Vector3.new(7, 3, 5)
local TABLE_COUNT = 6

local TroopDepot = {}

-- Low-poly robot head icon built from blocks, facing local -Z.
local function robotIcon(model: Model, frame: CFrame, scale: number, color: Color3)
	Kit.glow(model, "IconHead", Vector3.new(2.4, 1.8, 0.2) * scale, frame, color)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"IconEye",
			Vector3.new(0.5, 0.5, 0.25) * scale,
			frame * CFrame.new(side * 0.55 * scale, 0.15 * scale, -0.1 * scale),
			World.Steel,
			Enum.Material.SmoothPlastic,
			false
		)
	end
	Kit.glow(model, "IconAntenna", Vector3.new(0.18, 0.9, 0.2) * scale, frame * CFrame.new(0, 1.3 * scale, 0), color)
end

local function buildEntrance(model: Model, frame: CFrame, depth: number)
	local entry = frame * CFrame.new(0, 0, -(depth * 0.5 + Layout.WALL_THICKNESS * 0.5))
	-- Grated, hazard-striped lip across the doorway.
	Kit.block(
		model,
		"GrateLip",
		Vector3.new(Layout.HALL_WIDTH, 0.25, 3),
		entry * CFrame.new(0, 0.12, 0),
		World.SteelLight,
		Enum.Material.DiamondPlate
	)
	Kit.hazardStripe(model, entry * CFrame.new(0, 0.27, -1.8), Layout.HALL_WIDTH, 0.6, 0.06)
	Kit.hazardStripe(model, entry * CFrame.new(0, 0.27, 1.8), Layout.HALL_WIDTH, 0.6, 0.06)
	-- Sign faces the hallway (outward = local -Z of the room frame).
	local outside = entry * CFrame.new(0, 0, -(Layout.WALL_THICKNESS * 0.5 + 0.3))
	Kit.sign(
		model,
		"TroopsSign",
		outside * CFrame.new(1.5, 21.5, 0),
		Vector2.new(13, 3.6),
		"TROOPS",
		Areas.Troops,
		World.Steel,
		Areas.Troops,
		Theme.Fonts.Title
	)
	robotIcon(model, outside * CFrame.new(-7.5, 21.5, -0.3), 1.2, Areas.Troops)
	Kit.screen(model, "CurrencyCounter", outside * CFrame.new(0, 17.6, -0.2), Vector2.new(9, 1.8), Screen.Currency)
end

local function buildEmblem(model: Model, frame: CFrame)
	local colors = { World.EmblemRed, World.EmblemWhite, World.EmblemRed, World.EmblemWhite, World.EmblemRed }
	for index, color in colors do
		local radius = 12 - (index - 1) * 2.4
		Kit.disc(
			model,
			"Emblem",
			radius,
			0.05,
			frame * CFrame.new(0, 0.03 + index * 0.012, 0),
			color,
			Enum.Material.SmoothPlastic
		).CanCollide =
			false
	end
end

local function buildTable(model: Model, floor: CFrame, index: number)
	local tableModel = Instance.new("Model")
	tableModel.Name = `Table_{index}`
	Kit.block(
		tableModel,
		"Table",
		TABLE_SIZE,
		floor * CFrame.new(0, TABLE_SIZE.Y * 0.5, 0),
		World.Steel,
		Enum.Material.Metal
	)
	-- Rarity trim: clients recolour it for the troop on the plinth.
	local trim = Kit.glow(
		tableModel,
		"RarityTrim",
		Vector3.new(TABLE_SIZE.X + 0.2, 0.2, TABLE_SIZE.Z + 0.2),
		floor * CFrame.new(0, TABLE_SIZE.Y - 0.3, 0),
		World.RingUnlit
	)
	trim.Material = Enum.Material.SmoothPlastic
	local plinth = Kit.disc(
		tableModel,
		"Plinth",
		1.9,
		0.6,
		floor * CFrame.new(0, TABLE_SIZE.Y + 0.3, 0),
		World.SteelLight,
		Enum.Material.Metal
	)
	plinth:SetAttribute(Constants.Attributes.TableIndex, index)
	plinth:SetAttribute(Constants.Attributes.SpinSpeed, 40)
	CollectionService:AddTag(plinth, Constants.Tags.Spinner)
	CollectionService:AddTag(plinth, Constants.Tags.TroopTable)
	-- Name plate on the front edge, facing the aisle.
	Kit.screen(
		tableModel,
		"NamePlate",
		floor * CFrame.new(0, TABLE_SIZE.Y * 0.5, -(TABLE_SIZE.Z * 0.5 + 0.15)),
		Vector2.new(6, 2.2),
		Screen.Table,
		{
			[Constants.Attributes.TableIndex] = index,
		}
	)
	tableModel.Parent = model
end

local function buildTestRealm(model: Model, frame: CFrame, width: number, depth: number)
	local back = frame * CFrame.new(0, 0, depth * 0.5 - 0.5)
	-- Blue holographic glass with a cyan grid, set into the back wall.
	local glassWidth = width - 14
	local glass = Kit.block(
		model,
		"TestRealmGlass",
		Vector3.new(glassWidth, 16, 0.4),
		back * CFrame.new(0, 9, 0.2),
		World.Glass,
		Enum.Material.Glass
	)
	glass.Transparency = 0.55
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Grid"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0
	gui.Adornee = glass
	for column = 1, math.floor(glassWidth / 2) - 1 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Areas.TestRealm
		line.BackgroundTransparency = 0.55
		line.Size = UDim2.new(0, 2, 1, 0)
		line.Position = UDim2.new(column * 2 / glassWidth, 0, 0, 0)
		line.Parent = gui
	end
	for row = 1, 7 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Areas.TestRealm
		line.BackgroundTransparency = 0.55
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Position = UDim2.new(0, 0, row / 8, 0)
		line.Parent = gui
	end
	gui.Parent = glass
	Kit.sign(
		model,
		"TestRealmSign",
		back * CFrame.new(2, 19.5, 0),
		Vector2.new(14, 3),
		"TEST REALM",
		Areas.TestRealm,
		World.Steel,
		Areas.TestRealm,
		Theme.Fonts.Title
	)
	-- Target icon: concentric glowing squares.
	local target = back * CFrame.new(-8.5, 19.5, -0.3)
	Kit.glow(model, "TargetOuter", Vector3.new(2.6, 2.6, 0.1), target, Areas.TestRealm)
	Kit.block(
		model,
		"TargetGap",
		Vector3.new(1.9, 1.9, 0.12),
		target * CFrame.new(0, 0, -0.02),
		World.Steel,
		Enum.Material.SmoothPlastic,
		false
	)
	Kit.glow(model, "TargetCore", Vector3.new(0.8, 0.8, 0.14), target * CFrame.new(0, 0, -0.04), Areas.TestRealm)
	Kit.screen(
		model,
		"TestRealmInfo",
		back * CFrame.new(glassWidth * 0.5 + 3.5, 8, -0.5),
		Vector2.new(5, 6),
		Screen.TestRealm
	)

	-- Portal pad in front of the glass: stand on it to go (no key press).
	local padFrame = back * CFrame.new(0, 0, -6)
	local portal = Kit.disc(
		model,
		"TestRealmPortal",
		5,
		0.6,
		padFrame * CFrame.new(0, 0.3, 0),
		Areas.TestRealm,
		Enum.Material.Glass
	)
	portal.Transparency = 0.2
	CollectionService:AddTag(portal, Constants.Tags.TestRealmPortal)
	Kit.ring(
		model,
		"PortalRing",
		padFrame * CFrame.new(0, 0.62, 0),
		5.6,
		0.5,
		0.1,
		24,
		Areas.TestRealm,
		Enum.Material.Neon
	)

	-- The training yard seen through the glass: cover walls, dummies, a lane strip.
	local yard = back * CFrame.new(0, 0, 4)
	local yardModel = Instance.new("Model")
	yardModel.Name = "YardView"
	Kit.block(
		yardModel,
		"YardGround",
		Vector3.new(glassWidth + 20, 1, 50),
		yard * CFrame.new(0, -0.5, 25),
		Color3.fromRGB(110, 120, 88),
		Enum.Material.Grass
	)
	Kit.block(
		yardModel,
		"YardLane",
		Vector3.new(6, 0.1, 46),
		yard * CFrame.new(0, 0.05, 25),
		World.ConcreteMid,
		Enum.Material.Concrete
	)
	for index, offset in { Vector3.new(-12, 0, 12), Vector3.new(10, 0, 20), Vector3.new(-8, 0, 32) } do
		Kit.block(
			yardModel,
			`Cover_{index}`,
			Vector3.new(7, 4, 1.4),
			yard * CFrame.new(offset + Vector3.new(0, 2, 0)),
			World.Concrete,
			Enum.Material.Concrete
		)
	end
	for index, offset in { Vector3.new(6, 0, 10), Vector3.new(-5, 0, 24), Vector3.new(14, 0, 34) } do
		local dummy = yard * CFrame.new(offset)
		Kit.block(
			yardModel,
			`DummyPost_{index}`,
			Vector3.new(0.5, 3, 0.5),
			dummy * CFrame.new(0, 1.5, 0),
			Color3.fromRGB(132, 108, 70),
			Enum.Material.Wood
		)
		Kit.block(
			yardModel,
			`DummyBody_{index}`,
			Vector3.new(2, 2.4, 1),
			dummy * CFrame.new(0, 3.8, 0),
			Theme.Military.Khaki,
			Enum.Material.Fabric
		)
		Kit.block(
			yardModel,
			`DummyHead_{index}`,
			Vector3.new(1.2, 1.2, 1.2),
			dummy * CFrame.new(0, 5.6, 0),
			Theme.Military.Khaki,
			Enum.Material.Fabric
		)
	end
	yardModel.Parent = model
end

function TroopDepot.build(parent: Instance, origin: CFrame): BasePart
	local model = Instance.new("Model")
	model.Name = "TroopDepot"
	local width = Layout.DEPOT_HALF_Z * 2
	local depth = Layout.DEPOT_MAX_X - Layout.DEPOT_MIN_X
	local centerX = (Layout.DEPOT_MIN_X + Layout.DEPOT_MAX_X) * 0.5
	-- Room frame: -Z toward the hub (-X in the lobby), X across.
	local frame = origin * CFrame.lookAt(Vector3.new(centerX, 0, 0), Vector3.new(centerX - 1, 0, 0))
	-- The back wall is open where the Test Realm glass sits.
	Room.build(model, frame, width, depth, HEIGHT, Layout.HALL_WIDTH, World.Concrete, width - 14)
	buildEntrance(model, frame, depth)
	buildEmblem(model, frame)

	for index = 1, TABLE_COUNT do
		local row = if index <= 3 then -1 else 1
		local column = ((index - 1) % 3) - 1
		-- Permanent tables (1-3) on one side of the emblem, daily tables (4-6) on the other.
		local floor = frame * CFrame.new(row * 18, 0, column * 14) * CFrame.Angles(0, math.rad(90 * row), 0)
		buildTable(model, floor, index)
	end
	-- Rotation timer on the side wall above the daily tables.
	local sideWall = frame * CFrame.new(width * 0.5 - 0.6, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	Kit.screen(model, "RotationScreen", sideWall * CFrame.new(0, 10, 0), Vector2.new(14, 5), Screen.Rotation)
	local permanentWall = frame * CFrame.new(-(width * 0.5 - 0.6), 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
	Kit.sign(
		model,
		"PermanentSign",
		permanentWall * CFrame.new(0, 10, 0),
		Vector2.new(14, 2.4),
		"ALWAYS IN STOCK",
		Areas.Troops,
		World.Steel,
		Areas.Troops,
		Theme.Fonts.Title
	)

	local terminal = Kit.terminal(
		model,
		"TroopShopTerminal",
		frame * CFrame.new(8, 0, -(depth * 0.5 - 6)) * CFrame.Angles(0, math.pi, 0),
		"TroopShop",
		"Browse",
		"Troop Shop",
		Areas.Troops
	)
	buildTestRealm(model, frame, width, depth)
	model.Parent = parent
	return terminal
end

return TroopDepot

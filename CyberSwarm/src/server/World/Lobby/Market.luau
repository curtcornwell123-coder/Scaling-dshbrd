--!strict
--[[
	Market
	The Market room: a gold sign at the entrance, yellow floor guide lines, and two bays facing
	each other.
	- BAY 01 ROBUX SHOP: a small stage with red wedge curtains, a truss with spotlights,
	  stanchions, a "ROBUX SHOP" sign, a "BAY 01" plate, and product stands (terminal opens the shop).
	- BAY 02 SEASON PASS: a green screen with an original winged shield emblem, a truss with
	  spotlights, a director's chair, a clapperboard, a blue "SEASON 1 / PASS" banner, a "BAY 02"
	  plate, and the pass board screen with its countdown (terminal opens the pass).
	- A collectible statue on a glowing pedestal near the entrance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Room = require(script.Parent.Room)

local World = Theme.World
local Areas = Theme.Areas
local Screen = Constants.ScreenKind

local HEIGHT = 24
local PASS_BLUE = Color3.fromRGB(46, 104, 196)

local Market = {}

-- `bay` frame: floor centre of the bay at the room's side wall; -Z faces the room centre.
local function buildRobuxBay(model: Model, bay: CFrame)
	local stage = Instance.new("Model")
	stage.Name = "Bay01_RobuxShop"
	Kit.block(stage, "Stage", Vector3.new(22, 1.2, 10), bay * CFrame.new(0, 0.6, -5), World.Steel, Enum.Material.WoodPlanks)
	Kit.hazardStripe(stage, bay * CFrame.new(0, 1.24, -9.6), 22, 0.6, 0.06)
	-- Red wedge curtains framing the stage.
	for _, side in { -1, 1 } do
		Kit.wedge(stage, "Curtain", Vector3.new(1, 16, 5), bay * CFrame.new(side * 11.5, 9.2, -1.5) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), World.Curtain)
		Kit.block(stage, "TrussLeg", Vector3.new(0.6, 18, 0.6), bay * CFrame.new(side * 12.5, 9, -8), World.Steel, Enum.Material.Metal)
	end
	Kit.block(stage, "CurtainTop", Vector3.new(24, 2, 1.5), bay * CFrame.new(0, 17.5, -1), World.Curtain, Enum.Material.Fabric)
	Kit.truss(stage, (bay * CFrame.new(-12.5, 18, -8)).Position, (bay * CFrame.new(12.5, 18, -8)).Position, 4, Color3.fromRGB(255, 226, 180))
	Kit.sign(stage, "RobuxSign", bay * CFrame.new(0, 14, -0.4), Vector2.new(14, 3), "ROBUX SHOP", Areas.Market, World.Steel, Areas.Market, Theme.Fonts.Title)
	Kit.sign(stage, "BayPlate", bay * CFrame.new(-8, 4, -0.4), Vector2.new(4, 1.2), "BAY 01", World.HazardBlack, World.Hazard, nil, Theme.Fonts.Title)
	-- Product stands: three short plinths with display crates.
	for index, x in { -6, 0, 6 } do
		local stand = bay * CFrame.new(x, 1.2, -5)
		Kit.block(stage, `Stand_{index}`, Vector3.new(3, 2.4, 3), stand * CFrame.new(0, 1.2, 0), World.SteelLight, Enum.Material.Metal)
		Kit.glow(stage, `StandTop_{index}`, Vector3.new(3.1, 0.15, 3.1), stand * CFrame.new(0, 2.45, 0), Areas.Market)
		Kit.crate(stage, stand * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, math.rad(25 * index), 0), 1.6)
	end
	-- Stanchions with a rope line in front of the stage.
	for index = 0, 4 do
		local post = bay * CFrame.new(-10 + index * 5, 0, -12)
		Kit.block(stage, "Stanchion", Vector3.new(0.4, 3, 0.4), post * CFrame.new(0, 1.5, 0), Areas.Market, Enum.Material.Metal, false)
		if index < 4 then
			Kit.block(stage, "Rope", Vector3.new(5, 0.2, 0.2), post * CFrame.new(2.5, 2.6, 0), World.Curtain, Enum.Material.Fabric, false)
		end
	end
	Kit.terminal(stage, "RobuxTerminal", bay * CFrame.new(13, 0, -13) * CFrame.Angles(0, math.rad(-30), 0), "RobuxShop", "Shop", "Robux Shop", Areas.Market)
	stage.Parent = model
end

-- Original emblem: a shield with two swept wings, from blocks and wedges.
local function wingedShield(model: Model, frame: CFrame)
	Kit.block(model, "ShieldBody", Vector3.new(3.2, 3.4, 0.3), frame, Areas.Market, Enum.Material.SmoothPlastic, false)
	Kit.wedge(model, "ShieldPoint", Vector3.new(0.3, 1.6, 3.2), frame * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, math.rad(90), math.pi), Areas.Market).CanCollide = false
	Kit.block(model, "ShieldStripe", Vector3.new(0.6, 3.4, 0.32), frame * CFrame.new(0, 0, -0.02), PASS_BLUE, Enum.Material.SmoothPlastic, false)
	for _, side in { -1, 1 } do
		for feather = 1, 3 do
			Kit.block(
				model,
				"Wing",
				Vector3.new(3.2 - feather * 0.5, 0.55, 0.25),
				frame * CFrame.new(side * (2.6 + feather * 0.25), 1.1 - feather * 0.75, 0.05) * CFrame.Angles(0, 0, math.rad(side * (18 + feather * 8))),
				World.EmblemWhite,
				Enum.Material.SmoothPlastic,
				false
			)
		end
	end
end

local function buildPassBay(model: Model, bay: CFrame)
	local set = Instance.new("Model")
	set.Name = "Bay02_SeasonPass"
	Kit.block(set, "GreenScreen", Vector3.new(22, 16, 0.5), bay * CFrame.new(0, 8, -0.4), World.GreenScreen, Enum.Material.SmoothPlastic)
	Kit.block(set, "GreenFloor", Vector3.new(22, 0.1, 8), bay * CFrame.new(0, 0.05, -4.6), World.GreenScreen, Enum.Material.SmoothPlastic, false)
	wingedShield(set, bay * CFrame.new(0, 12, -0.8))
	for _, side in { -1, 1 } do
		Kit.block(set, "TrussLeg", Vector3.new(0.6, 18, 0.6), bay * CFrame.new(side * 12.5, 9, -9), World.Steel, Enum.Material.Metal)
	end
	Kit.truss(set, (bay * CFrame.new(-12.5, 18, -9)).Position, (bay * CFrame.new(12.5, 18, -9)).Position, 4)
	-- Pass board with tiers and the season countdown (client drawn).
	Kit.screen(set, "PassBoard", bay * CFrame.new(0, 5.5, -0.8), Vector2.new(14, 6), Screen.Pass)
	Kit.sign(set, "PassBanner", bay * CFrame.new(-14.5, 8, -3) * CFrame.Angles(0, math.rad(25), 0), Vector2.new(4, 9), `{SeasonConfig.DisplayName}\nPASS`, World.EmblemWhite, PASS_BLUE, nil, Theme.Fonts.Title)
	Kit.sign(set, "BayPlate", bay * CFrame.new(8, 1.8, -0.8), Vector2.new(4, 1.2), "BAY 02", World.HazardBlack, World.Hazard, nil, Theme.Fonts.Title)
	-- Director's chair and clapperboard.
	local chair = bay * CFrame.new(7, 0, -8) * CFrame.Angles(0, math.rad(200), 0)
	for _, side in { -1, 1 } do
		Kit.block(set, "ChairLeg", Vector3.new(0.2, 3, 0.2), chair * CFrame.new(side * 0.9, 1.5, 0) * CFrame.Angles(math.rad(14), 0, 0), Color3.fromRGB(132, 108, 70), Enum.Material.Wood)
		Kit.block(set, "ChairLeg", Vector3.new(0.2, 3, 0.2), chair * CFrame.new(side * 0.9, 1.5, 0) * CFrame.Angles(math.rad(-14), 0, 0), Color3.fromRGB(132, 108, 70), Enum.Material.Wood)
	end
	Kit.block(set, "ChairSeat", Vector3.new(2, 0.15, 1.4), chair * CFrame.new(0, 2.8, 0), World.HazardBlack, Enum.Material.Fabric)
	Kit.block(set, "ChairBack", Vector3.new(2, 1, 0.15), chair * CFrame.new(0, 4.1, 0.7), World.HazardBlack, Enum.Material.Fabric)
	local clapper = bay * CFrame.new(-6, 0, -8)
	Kit.block(set, "ClapperStand", Vector3.new(1.4, 2.4, 1.4), clapper * CFrame.new(0, 1.2, 0), World.Steel, Enum.Material.Metal)
	Kit.block(set, "Clapperboard", Vector3.new(1.8, 1.3, 0.15), clapper * CFrame.new(0, 3.1, 0) * CFrame.Angles(math.rad(-15), 0, 0), World.HazardBlack, Enum.Material.SmoothPlastic)
	Kit.hazardStripe(set, clapper * CFrame.new(0, 3.85, 0.1) * CFrame.Angles(0, 0, math.rad(8)), 1.8, 0.16, 0.3)
	Kit.terminal(set, "PassTerminal", bay * CFrame.new(-11, 0, -12) * CFrame.Angles(0, math.rad(30), 0), "Pass", "Open", "Season Pass", PASS_BLUE)
	set.Parent = model
end

local function buildStatue(model: Model, floor: CFrame)
	local statue = Instance.new("Model")
	statue.Name = "CollectibleStatue"
	Kit.disc(statue, "Pedestal", 2.6, 3, floor * CFrame.new(0, 1.5, 0), World.Steel, Enum.Material.Metal)
	Kit.ring(statue, "PedestalGlow", floor * CFrame.new(0, 3.02, 0), 2.4, 0.3, 0.06, 20, Areas.Market, Enum.Material.Neon)
	-- A gold low-poly robot on a mid-stride pose.
	local base = floor * CFrame.new(0, 3, 0)
	local gold = Color3.fromRGB(214, 170, 60)
	local function piece(name: string, size: Vector3, offset: CFrame)
		local part = Kit.block(statue, name, size, base * offset, gold, Enum.Material.Metal, false)
		part.Reflectance = 0.1
	end
	piece("Legs", Vector3.new(1.6, 2, 0.8), CFrame.new(0, 1, 0))
	piece("Torso", Vector3.new(2.4, 2.2, 1.4), CFrame.new(0, 3.1, 0))
	piece("Head", Vector3.new(1.4, 1.2, 1.2), CFrame.new(0, 4.9, 0))
	piece("ArmL", Vector3.new(0.6, 2, 0.6), CFrame.new(-1.6, 3, 0) * CFrame.Angles(math.rad(20), 0, 0))
	piece("ArmR", Vector3.new(0.6, 2, 0.6), CFrame.new(1.6, 3.4, 0) * CFrame.Angles(math.rad(-50), 0, 0))
	local light = Instance.new("PointLight")
	light.Color = Areas.Market
	light.Range = 12
	light.Brightness = 0.7
	light.Parent = statue:FindFirstChild("Pedestal")
	statue.Parent = model
end

function Market.build(parent: Instance, origin: CFrame)
	local model = Instance.new("Model")
	model.Name = "Market"
	local width = Layout.MARKET_HALF_Z * 2
	local depth = Layout.MARKET_MAX_X - Layout.MARKET_MIN_X
	local centerX = (Layout.MARKET_MIN_X + Layout.MARKET_MAX_X) * 0.5
	-- -Z faces the hub (+X in the lobby).
	local frame = origin * CFrame.lookAt(Vector3.new(centerX, 0, 0), Vector3.new(centerX + 1, 0, 0))
	Room.build(model, frame, width, depth, HEIGHT, Layout.HALL_WIDTH, World.Concrete)

	local entry = frame * CFrame.new(0, 0, -(depth * 0.5 + Layout.WALL_THICKNESS + 0.3))
	Kit.sign(model, "MarketSign", entry * CFrame.new(0, 21.5, 0), Vector2.new(14, 3.6), "MARKET", Areas.Market, World.Steel, Areas.Market, Theme.Fonts.Title)
	-- Yellow guide lines from the entrance to each bay.
	local doorway = (frame * CFrame.new(0, 0, -(depth * 0.5 - 2))).Position
	Kit.floorLine(model, doorway, (frame * CFrame.new(-(width * 0.5 - 16), 0, 0)).Position, 0.6, World.Hazard)
	Kit.floorLine(model, doorway, (frame * CFrame.new(width * 0.5 - 16, 0, 0)).Position, 0.6, World.Hazard)
	Kit.floorLine(model, doorway, (frame * CFrame.new(0, 0, depth * 0.5 - 4)).Position, 0.6, World.Hazard)

	-- Bays on opposite side walls, each facing the room centre.
	buildRobuxBay(model, frame * CFrame.new(width * 0.5, 0, 4) * CFrame.Angles(0, math.rad(90), 0))
	buildPassBay(model, frame * CFrame.new(-width * 0.5, 0, 4) * CFrame.Angles(0, math.rad(-90), 0))
	buildStatue(model, frame * CFrame.new(10, 0, -(depth * 0.5 - 9)))
	model.Parent = parent
end

return Market

--!strict
--[[
	Hub
	The circular main hub: a raised platform with yellow and cyan ring trim and a step, a roof with
	a round glass skylight, the Halloween update corner (countdown sign and the blacked-out
	mystery unit) on the floor, a curved concrete wall with four openings (DUELS ahead, TROOP DEPOT left,
	MARKET right, party alcove behind), the DUELS archway framed by angled screens (Daily Supply,
	Code, Win Streaks, Daily Tasks), props, and the spawns. The game's name appears only as a small
	stencil on one wall panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local World = Theme.World
local Areas = Theme.Areas
local Screen = Constants.ScreenKind

local PLATFORM_RADIUS = 18
local PLATFORM_HEIGHT = 1.6
local STEP_RADIUS = 21.5
local STEP_HEIGHT = 0.8
-- Radius of the round glass skylight in the hub roof.
local SKYLIGHT_RADIUS = 24
local WALL_SEGMENTS = 36

export type HubResult = {
	spawns: { SpawnLocation },
}

local Hub = {}

local function isOpening(degrees: number): boolean
	for _, opening in Layout.Openings do
		local delta = math.abs(((degrees - opening + 180) % 360) - 180)
		if delta < Layout.OPENING_HALF_ANGLE then
			return true
		end
	end
	return false
end

local function buildWall(model: Model, origin: CFrame)
	local radius = Layout.HUB_RADIUS
	local height = Layout.HUB_WALL_HEIGHT
	local arc = 2 * math.pi * radius / WALL_SEGMENTS
	for index = 0, WALL_SEGMENTS - 1 do
		local degrees = (index + 0.5) * 360 / WALL_SEGMENTS
		if isOpening(degrees) then
			continue
		end
		local frame = origin * Layout.facingCenter(Vector3.zero, degrees, radius + Layout.WALL_THICKNESS * 0.5)
		Kit.block(
			model,
			"HubWall",
			Vector3.new(arc * 1.06, height, Layout.WALL_THICKNESS),
			frame * CFrame.new(0, height * 0.5, 0),
			World.Concrete,
			Enum.Material.Concrete
		)
		-- Mid-grey base course and a steel cap break up the concrete.
		Kit.block(
			model,
			"WallBase",
			Vector3.new(arc * 1.06, 3, 0.6),
			frame * CFrame.new(0, 1.5, -1.7),
			World.ConcreteMid,
			Enum.Material.Concrete,
			false
		)
		Kit.block(
			model,
			"WallCap",
			Vector3.new(arc * 1.06, 1, Layout.WALL_THICKNESS + 1),
			frame * CFrame.new(0, height + 0.5, 0),
			World.Steel,
			Enum.Material.Metal
		)
		if index % 3 == 0 then
			Kit.block(
				model,
				"Buttress",
				Vector3.new(2.4, height - 4, 1.6),
				frame * CFrame.new(0, (height - 4) * 0.5, -2.2),
				World.ConcreteMid,
				Enum.Material.Concrete
			)
		end
	end
	-- Arches over the four openings.
	for _, degrees in Layout.Openings do
		local frame = origin * Layout.facingCenter(Vector3.zero, degrees, radius + Layout.WALL_THICKNESS * 0.5)
		Kit.arch(model, "OpeningArch", frame, Layout.HALL_WIDTH + 1, 19, Layout.WALL_THICKNESS + 1, World.Concrete)
		Kit.hazardStripe(model, frame * CFrame.new(0, 0.04, -2.5), Layout.HALL_WIDTH, 1.2, 0.08)
	end
end

local function buildPlatform(model: Model, origin: CFrame)
	Kit.disc(
		model,
		"Step",
		STEP_RADIUS,
		STEP_HEIGHT,
		origin * CFrame.new(0, STEP_HEIGHT * 0.5, 0),
		World.ConcreteMid,
		Enum.Material.Concrete
	)
	Kit.disc(
		model,
		"Platform",
		PLATFORM_RADIUS,
		PLATFORM_HEIGHT,
		origin * CFrame.new(0, PLATFORM_HEIGHT * 0.5, 0),
		World.Concrete,
		Enum.Material.Concrete
	)
	-- Yellow outer trim with a thin cyan inner line: the only glow on the platform.
	Kit.ring(
		model,
		"TrimYellow",
		origin * CFrame.new(0, PLATFORM_HEIGHT + 0.03, 0),
		PLATFORM_RADIUS - 0.6,
		0.8,
		0.06,
		40,
		Areas.HubRing,
		Enum.Material.SmoothPlastic
	)
	Kit.ring(
		model,
		"TrimCyan",
		origin * CFrame.new(0, PLATFORM_HEIGHT + 0.03, 0),
		PLATFORM_RADIUS - 1.8,
		0.25,
		0.07,
		40,
		Areas.HubRingAccent,
		Enum.Material.Neon
	)
	Kit.ring(
		model,
		"StepEdge",
		origin * CFrame.new(0, STEP_HEIGHT + 0.02, 0),
		STEP_RADIUS - 0.5,
		0.6,
		0.05,
		44,
		Areas.HubRing,
		Enum.Material.SmoothPlastic
	)
end

-- Enclosed hall with a round skylight over the platform: a ring roof on the wall tops, a glass
-- dome-ish window in the middle with a steel frame, and warm lights around the ring.
local function buildRoof(model: Model, origin: CFrame)
	local height = Layout.HUB_WALL_HEIGHT + 1
	local outer = Layout.HUB_RADIUS + Layout.WALL_THICKNESS
	local inner = SKYLIGHT_RADIUS
	local segments = 36
	local width = outer - inner
	for index = 0, segments - 1 do
		local degrees = (index + 0.5) * 360 / segments
		local frame = origin * Layout.facingCenter(Vector3.zero, degrees, inner + width * 0.5, height)
		local arc = 2 * math.pi * outer / segments
		Kit.block(model, "Roof", Vector3.new(arc * 1.05, 1.4, width), frame, World.ConcreteMid, Enum.Material.Concrete)
		if index % 3 == 0 then
			-- Ceiling lights hanging under the roof ring.
			local lamp = Kit.block(
				model,
				"CeilingLamp",
				Vector3.new(2.4, 0.4, 2.4),
				frame * CFrame.new(0, -0.9, -width * 0.2),
				World.Steel,
				Enum.Material.Metal,
				false
			)
			local light = Instance.new("PointLight")
			light.Range = 34
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 240, 220)
			light.Parent = lamp
			Kit.glow(
				model,
				"LampGlow",
				Vector3.new(2, 0.08, 2),
				frame * CFrame.new(0, -1.12, -width * 0.2),
				Color3.fromRGB(255, 244, 228)
			)
		end
	end
	-- Skylight: tinted glass with a steel ring and cross beams.
	local glass = Kit.disc(
		model,
		"Skylight",
		inner + 0.5,
		0.4,
		origin * CFrame.new(0, height, 0),
		Color3.fromRGB(170, 214, 240),
		Enum.Material.Glass
	)
	glass.Transparency = 0.65
	glass.CastShadow = false
	Kit.ring(
		model,
		"SkylightFrame",
		origin * CFrame.new(0, height, 0),
		inner,
		1.2,
		1.6,
		32,
		World.Steel,
		Enum.Material.Metal
	)
	for _, degrees in { 0, 45, 90, 135 } do
		Kit.block(
			model,
			"SkylightBeam",
			Vector3.new(0.8, 0.8, inner * 2),
			origin * CFrame.new(0, height + 0.3, 0) * CFrame.Angles(0, math.rad(degrees), 0),
			World.Steel,
			Enum.Material.Metal,
			false
		)
	end
end

-- Halloween update corner on the floor near the platform: the countdown sign framed with
-- pumpkins, bats, cobwebs and gravestones, and a blacked-out silhouette of the upcoming
-- Halloween unit on a pedestal.
local PUMPKIN = Color3.fromRGB(232, 120, 24)
local SPOOKY_PURPLE = Color3.fromRGB(150, 70, 230)

local function pumpkin(model: Model, floor: CFrame, size: number)
	local body = Kit.block(
		model,
		"Pumpkin",
		Vector3.new(size * 1.2, size, size * 1.2),
		floor * CFrame.new(0, size * 0.5, 0),
		PUMPKIN,
		Enum.Material.SmoothPlastic
	)
	body.Shape = Enum.PartType.Ball
	Kit.block(
		model,
		"Stem",
		Vector3.new(size * 0.15, size * 0.3, size * 0.15),
		floor * CFrame.new(0, size * 1.05, 0),
		Color3.fromRGB(70, 110, 40),
		Enum.Material.Wood,
		false
	)
	-- Carved, glowing face.
	for _, x in { -1, 1 } do
		Kit.glow(
			model,
			"Eye",
			Vector3.new(size * 0.18, size * 0.18, 0.1),
			floor * CFrame.new(x * size * 0.22, size * 0.62, -size * 0.6),
			Color3.fromRGB(255, 200, 60)
		)
	end
	Kit.glow(
		model,
		"Mouth",
		Vector3.new(size * 0.5, size * 0.1, 0.1),
		floor * CFrame.new(0, size * 0.35, -size * 0.6),
		Color3.fromRGB(255, 200, 60)
	)
	local light = Instance.new("PointLight")
	light.Color = PUMPKIN
	light.Range = 10
	light.Brightness = 0.8
	light.Parent = body
end

local function bat(model: Model, cframe: CFrame)
	Kit.block(
		model,
		"BatBody",
		Vector3.new(0.5, 0.5, 0.7),
		cframe,
		Color3.fromRGB(18, 16, 22),
		Enum.Material.SmoothPlastic,
		false
	)
	for _, side in { -1, 1 } do
		Kit.wedge(
			model,
			"BatWing",
			Vector3.new(0.1, 0.8, 1.4),
			cframe * CFrame.new(side * 0.8, 0.1, 0) * CFrame.Angles(0, 0, math.rad(side * 70)),
			Color3.fromRGB(18, 16, 22)
		).CanCollide =
			false
	end
end

local function silhouette(model: Model, floor: CFrame)
	-- Original placeholder shape for the Halloween unit: a hunched mech with a lantern head and a
	-- long scythe arm. Fully blacked out until release.
	local black = Color3.fromRGB(8, 8, 10)
	local base = floor * CFrame.new(0, 3, 0)
	local function piece(name: string, size: Vector3, offset: CFrame)
		Kit.block(model, name, size, base * offset, black, Enum.Material.SmoothPlastic, false)
	end
	piece("Legs", Vector3.new(2.4, 2.6, 1.2), CFrame.new(0, 1.3, 0))
	piece("Torso", Vector3.new(3.2, 2.8, 2), CFrame.new(0, 3.9, 0.2) * CFrame.Angles(math.rad(-12), 0, 0))
	piece("Head", Vector3.new(2, 1.8, 2), CFrame.new(0, 6, -0.4) * CFrame.Angles(0, math.rad(45), 0))
	piece("Horn", Vector3.new(0.3, 1.4, 0.3), CFrame.new(-0.7, 7.2, -0.4) * CFrame.Angles(0, 0, math.rad(25)))
	piece("Horn", Vector3.new(0.3, 1.4, 0.3), CFrame.new(0.7, 7.2, -0.4) * CFrame.Angles(0, 0, math.rad(-25)))
	piece("Arm", Vector3.new(0.7, 3, 0.7), CFrame.new(2.1, 3.8, -0.4) * CFrame.Angles(math.rad(30), 0, 0))
	piece(
		"ScytheShaft",
		Vector3.new(0.3, 7, 0.3),
		CFrame.new(2.6, 4.6, -1.6) * CFrame.Angles(math.rad(-15), 0, math.rad(-10))
	)
	piece("ScytheBlade", Vector3.new(0.2, 0.6, 3.2), CFrame.new(2.9, 8, -0.4) * CFrame.Angles(math.rad(20), 0, 0))
	piece("Cape", Vector3.new(3.4, 3.4, 0.2), CFrame.new(0, 3.6, 1.3) * CFrame.Angles(math.rad(10), 0, 0))
end

local function buildHalloween(model: Model, origin: CFrame)
	local corner = Instance.new("Model")
	corner.Name = "HalloweenUpdate"
	local floor = origin * Layout.facingCenter(Vector3.zero, -48, 34)
	-- Countdown sign on two posts.
	for _, x in { -8.5, 8.5 } do
		Kit.block(
			corner,
			"SignPost",
			Vector3.new(0.8, 9, 0.8),
			floor * CFrame.new(x, 4.5, 0.6),
			Color3.fromRGB(40, 30, 26),
			Enum.Material.Wood
		)
	end
	Kit.block(
		corner,
		"SignFrame",
		Vector3.new(18, 6.4, 0.8),
		floor * CFrame.new(0, 6.2, 0.6),
		Color3.fromRGB(30, 22, 30),
		Enum.Material.Wood
	)
	Kit.glow(corner, "SignTrimTop", Vector3.new(18.2, 0.25, 0.9), floor * CFrame.new(0, 9.45, 0.6), PUMPKIN)
	Kit.glow(corner, "SignTrimBottom", Vector3.new(18.2, 0.25, 0.9), floor * CFrame.new(0, 2.95, 0.6), SPOOKY_PURPLE)
	Kit.screen(corner, "EventScreen", floor * CFrame.new(0, 6.2, 0), Vector2.new(16.4, 5.4), Constants.ScreenKind.Event)
	-- Pumpkins and gravestones at the foot of the sign.
	for index, x in { -9, -6, 6, 9.5 } do
		pumpkin(
			corner,
			floor * CFrame.new(x, 0, -2) * CFrame.Angles(0, math.rad(index * 17), 0),
			if index % 2 == 0 then 1.6 else 2.2
		)
	end
	for index, x in { -3, 3 } do
		local stone = Kit.block(
			corner,
			"Gravestone",
			Vector3.new(2, 2.6, 0.6),
			floor * CFrame.new(x, 1.3, -1.5) * CFrame.Angles(math.rad(index * 4), 0, 0),
			Color3.fromRGB(110, 110, 118),
			Enum.Material.Slate
		)
		Kit.stencil(stone, Enum.NormalId.Front, "R.I.P.", Color3.fromRGB(50, 50, 56))
	end
	-- Cobwebs in the top corners and bats around the sign.
	for _, x in { -8.6, 8.6 } do
		Kit.wedge(
			corner,
			"Cobweb",
			Vector3.new(0.05, 2.4, 2.4),
			floor * CFrame.new(x, 8.4, 0.1) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(230, 230, 236)
		).Transparency =
			0.55
	end
	for index, offset in { Vector3.new(-6, 11, -1), Vector3.new(4, 12, -2), Vector3.new(10, 10.5, -1) } do
		bat(corner, floor * CFrame.new(offset) * CFrame.Angles(0, math.rad(index * 30), 0))
	end
	local spooky = Instance.new("PointLight")
	spooky.Color = SPOOKY_PURPLE
	spooky.Range = 22
	spooky.Brightness = 1
	spooky.Parent = corner:FindFirstChild("SignFrame")

	-- The mystery unit: blacked-out silhouette on a glowing pedestal.
	local pedestalFloor = floor * CFrame.new(-15, 0, -1) * CFrame.Angles(0, math.rad(20), 0)
	Kit.disc(
		corner,
		"MysteryPedestal",
		3.4,
		3,
		pedestalFloor * CFrame.new(0, 1.5, 0),
		Color3.fromRGB(26, 20, 32),
		Enum.Material.Slate
	)
	Kit.ring(
		corner,
		"MysteryGlow",
		pedestalFloor * CFrame.new(0, 3.02, 0),
		3.1,
		0.35,
		0.06,
		24,
		SPOOKY_PURPLE,
		Enum.Material.Neon
	)
	silhouette(corner, pedestalFloor)
	Kit.sign(
		corner,
		"MysteryPlate",
		pedestalFloor * CFrame.new(0, 1.6, -3.5),
		Vector2.new(6, 1.2),
		"??? COMING HALLOWEEN",
		PUMPKIN,
		Color3.fromRGB(20, 14, 24),
		PUMPKIN,
		Theme.Fonts.Title
	)
	corner.Parent = model
end

local function buildDuelsFront(model: Model, origin: CFrame)
	local radius = Layout.HUB_RADIUS
	local front = origin * Layout.facingCenter(Vector3.zero, Layout.Openings.Duels, radius - 0.5)
	-- DUELS lettering: white outline with gold and purple accent bars, softly lit.
	Kit.block(
		model,
		"DuelsSignBack",
		Vector3.new(22, 5.5, 0.6),
		front * CFrame.new(0, 23.5, 0.2),
		World.Steel,
		Enum.Material.Metal,
		false
	)
	Kit.sign(
		model,
		"DuelsSign",
		front * CFrame.new(0, 23.5, -0.2),
		Vector2.new(20, 5),
		"DUELS",
		Areas.Duels,
		nil,
		Areas.Duels,
		Theme.Fonts.Title,
		Areas.DuelsPurple
	)
	Kit.glow(model, "DuelsGold", Vector3.new(20, 0.25, 0.2), front * CFrame.new(0, 20.6, -0.4), Areas.DuelsGold)
	Kit.glow(model, "DuelsPurple", Vector3.new(20, 0.25, 0.2), front * CFrame.new(0, 26.4, -0.4), Areas.DuelsPurple)
	-- Live total of queued players.
	Kit.screen(model, "DuelsStatus", front * CFrame.new(0, 19.6, -0.4), Vector2.new(9, 1.4), Screen.DuelsStatus)

	-- Angled side screens framing the arch.
	local function sideScreen(
		degrees: number,
		name: string,
		kind: string,
		size: Vector2,
		attributes: { [string]: any }?
	): CFrame
		local floor = origin * Layout.facingCenter(Vector3.zero, degrees, radius - 7)
		Kit.angledScreen(model, name, floor, size, kind, attributes)
		return floor
	end
	sideScreen(-20, "SupplyScreen", Screen.Supply, Vector2.new(10, 6.5))
	sideScreen(
		20,
		"StreakScreen",
		Screen.Leaderboard,
		Vector2.new(10, 8),
		{ [Constants.Attributes.Board] = Constants.Leaderboard.WIN_STREAK }
	)
	local codeFloor = sideScreen(-38, "CodeScreen", Screen.Code, Vector2.new(8, 5))
	sideScreen(38, "TasksScreen", Screen.Tasks, Vector2.new(10, 7.5))

	-- Supply crate terminal and code terminal sit in front of their screens.
	local supplyFloor = origin * Layout.facingCenter(Vector3.zero, -20, radius - 12)
	Kit.terminal(model, "SupplyTerminal", supplyFloor, "Supply", "Claim", "Daily Supply", Areas.HubRing)
	Kit.terminal(
		model,
		"CodeTerminal",
		codeFloor * CFrame.new(0, 0, -5),
		"Code",
		"Redeem",
		"Code Terminal",
		Areas.HubRingAccent
	)
end

local function buildProps(model: Model, origin: CFrame)
	local radius = Layout.HUB_RADIUS
	local barrelColors = { Color3.fromRGB(46, 96, 150), Color3.fromRGB(170, 46, 40), Color3.fromRGB(60, 110, 60) }
	-- Each cluster between the openings gets a different mix so nothing reads as copy-paste.
	local clusters: { (CFrame, number) -> () } = {
		function(floor: CFrame, seed: number)
			Kit.crate(model, floor * CFrame.new(-6, 0, 0), 3.6, seed)
			Kit.crate(model, floor * CFrame.new(-6.2, 3.6, 0.2) * CFrame.Angles(0, math.rad(18), 0), 2.6, seed + 1)
			Kit.crate(model, floor * CFrame.new(-2.4, 0, 0.6) * CFrame.Angles(0, math.rad(-8), 0), 2.4, seed + 2)
			Kit.barrel(model, floor * CFrame.new(3, 0, 0.5), barrelColors[1])
			Kit.barrel(model, floor * CFrame.new(5.9, 0, 0.2), barrelColors[2])
			Kit.cone(model, floor * CFrame.new(1, 0, -3))
		end,
		function(floor: CFrame, seed: number)
			Kit.pallet(model, floor * CFrame.new(-5, 0, 0), true)
			Kit.toolbox(model, floor * CFrame.new(1.5, 0, 0.4))
			Kit.gasCylinders(model, floor * CFrame.new(6, 0, 0.8))
			Kit.crate(model, floor * CFrame.new(-1.5, 0, -3) * CFrame.Angles(0, math.rad(30), 0), 2.2, seed)
		end,
		function(floor: CFrame, _seed: number)
			Kit.lockers(model, floor * CFrame.new(-3, 0, 1), 4)
			Kit.spool(model, floor * CFrame.new(5, 0, -0.5))
			Kit.cone(model, floor * CFrame.new(2.4, 0, -3.2))
			Kit.cone(model, floor * CFrame.new(-6.6, 0, -2.6))
		end,
		function(floor: CFrame, seed: number)
			Kit.tarpStack(model, floor * CFrame.new(-3, 0, 0.4), Color3.fromRGB(70, 92, 60))
			Kit.sandbags(model, floor * CFrame.new(4.5, 0, -1.5), 6)
			Kit.barrel(model, floor * CFrame.new(5, 0, 2), barrelColors[3])
			Kit.crate(model, floor * CFrame.new(1, 0, 2), 2.8, seed)
		end,
	}
	for index, degrees in { 55, 125, 235, 305 } do
		local floor = origin * Layout.facingCenter(Vector3.zero, degrees, radius - 9)
		clusters[index](floor, index * 3)
	end
	Kit.container(
		model,
		origin * Layout.facingCenter(Vector3.zero, 145, radius - 7) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(120, 66, 48)
	)
	Kit.container(
		model,
		origin * Layout.facingCenter(Vector3.zero, 215, radius - 7) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(58, 84, 104)
	)
	for _, degrees in { 30, 150, 210, 330 } do
		local a = (origin * CFrame.new(Layout.direction(degrees) * (STEP_RADIUS + 1))).Position
		local b = (origin * CFrame.new(Layout.direction(degrees + 8) * (radius - 4))).Position
		Kit.cable(model, a, b)
	end
	-- Small stenciled name on one wall panel: the only place the game's name appears.
	local stencilFrame = origin * Layout.facingCenter(Vector3.zero, 160, radius - 0.1)
	Kit.sign(
		model,
		"Stencil",
		stencilFrame * CFrame.new(0, 9, -0.25),
		Vector2.new(9, 1.4),
		string.upper(Constants.GAME_NAME),
		World.Stencil,
		nil,
		nil,
		Theme.Fonts.Body
	)
end

local function buildSpawns(model: Model, origin: CFrame): { SpawnLocation }
	local spawns: { SpawnLocation } = {}
	local function add(cframe: CFrame, size: Vector3)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "HubSpawn"
		spawn.Anchored = true
		spawn.Size = size
		spawn.CFrame = cframe
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = model
		table.insert(spawns, spawn)
	end
	add(origin * CFrame.new(0, PLATFORM_HEIGHT + 0.1, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(10, 0.2, 10))
	for _, degrees in { 45, 135, 225, 315 } do
		local position = Layout.direction(degrees) * (STEP_RADIUS + 6)
		add(
			CFrame.lookAt(
				(origin * CFrame.new(position + Vector3.new(0, 0.1, 0))).Position,
				origin.Position + Vector3.new(0, 0.1, 0)
			),
			Vector3.new(6, 0.2, 6)
		)
	end
	return spawns
end

function Hub.build(parent: Instance, origin: CFrame): HubResult
	local model = Instance.new("Model")
	model.Name = "Hub"
	Kit.disc(
		model,
		"HubFloor",
		Layout.HUB_RADIUS + 2,
		2,
		origin * CFrame.new(0, -1, 0),
		World.Floor,
		Enum.Material.Concrete
	)
	Kit.ring(model, "FloorSeam", origin * CFrame.new(0, 0.02, 0), 38, 0.3, 0.04, 48, World.FloorSeam)
	buildWall(model, origin)
	buildPlatform(model, origin)
	buildRoof(model, origin)
	buildHalloween(model, origin)
	buildDuelsFront(model, origin)
	buildProps(model, origin)
	local spawns = buildSpawns(model, origin)
	model.Parent = parent
	return { spawns = spawns }
end

return Hub

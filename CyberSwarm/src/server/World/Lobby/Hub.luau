--!strict
--[[
	Hub
	The circular main hub: a raised platform with yellow and cyan ring trim and a step, the floating
	update countdown, a curved concrete wall with four openings (DUELS ahead, TROOP DEPOT left,
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
local BILLBOARD_HEIGHT = 20
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

local function buildBillboard(model: Model, origin: CFrame)
	local center = origin * CFrame.new(0, BILLBOARD_HEIGHT, 0)
	Kit.block(model, "BillboardFrame", Vector3.new(17, 6, 1.2), center, World.Steel, Enum.Material.Metal, false)
	-- Two faces so the countdown reads from either side of the platform.
	Kit.screen(model, "EventScreenFront", center * CFrame.new(0, 0, -0.75), Vector2.new(16, 5), Screen.Event)
	Kit.screen(
		model,
		"EventScreenBack",
		center * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -0.75),
		Vector2.new(16, 5),
		Screen.Event
	)
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"Hanger",
			Vector3.new(0.3, 12, 0.3),
			center * CFrame.new(side * 7, 9, 0),
			World.Steel,
			Enum.Material.Metal,
			false
		)
	end
	Kit.glow(model, "BillboardEdge", Vector3.new(17.2, 0.15, 1.3), center * CFrame.new(0, -3.05, 0), Areas.HubRing)
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
	for _, degrees in { 55, 125, 235, 305 } do
		local floor = origin * Layout.facingCenter(Vector3.zero, degrees, radius - 9)
		Kit.crate(model, floor * CFrame.new(-6, 0, 0), 3.5)
		Kit.crate(model, floor * CFrame.new(-6, 3.5, 0) * CFrame.Angles(0, math.rad(20), 0), 2.6)
		Kit.sandbags(model, floor * CFrame.new(5, 0, -2), 7)
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
	buildBillboard(model, origin)
	buildDuelsFront(model, origin)
	buildProps(model, origin)
	local spawns = buildSpawns(model, origin)
	model.Parent = parent
	return { spawns = spawns }
end

return Hub

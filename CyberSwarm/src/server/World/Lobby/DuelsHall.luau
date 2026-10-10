--!strict
--[[
	DuelsHall
	A wide curved concrete hall with one bay per Duels mode, generated from ModeConfig: each mode
	with bayOrder > 0 gets the bay at that position. A bay is a floor pad with a ring of segments
	(clients fill and colour it), a wall screen, a neon sign in its category colour (casual white,
	ranked gold, co-op green), and a blast door that slides open when its match starts. The slot
	at ModeConfig.LimitedBayOrder stays a closed "coming soon" bay until a Limited mode exists.

	Also: hazard floor guides from the entrance to each pad, a grated ceiling truss with
	spotlights, ranked leaderboard walls (one per rating key), and a rank card screen.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local RankConfig = require(ReplicatedStorage.Shared.Config.RankConfig)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local World = Theme.World
local Screen = Constants.ScreenKind

local WALL_HEIGHT = 26
local WALL_SEGMENTS = 40
local ENTRY_HALF_ANGLE = 13
local BAY_SPREAD = 150
local PAD_RADIUS = 6
local PAD_DISTANCE = 30
local RING_RADIUS = 7.2
local DOOR_WIDTH = 9
local DOOR_HEIGHT = 12

export type BlastDoor = {
	modeId: string,
	door: BasePart,
	closed: CFrame,
}

export type DuelsResult = {
	returnPoint: CFrame,
	doors: { BlastDoor },
}

local DuelsHall = {}

-- Bay angle (clockwise from +Z, around the hall centre) for a bay order.
local function bayAngle(order: number, bayCount: number): number
	if bayCount <= 1 then
		return 0
	end
	return -BAY_SPREAD * 0.5 + (order - 1) * BAY_SPREAD / (bayCount - 1)
end

local function buildShell(model: Model, center: CFrame)
	local radius = Layout.DUELS_RADIUS
	Kit.disc(model, "HallFloor", radius + 2, 2, center * CFrame.new(0, -1, 0), World.Floor, Enum.Material.Concrete)
	local arc = 2 * math.pi * radius / WALL_SEGMENTS
	for index = 0, WALL_SEGMENTS - 1 do
		local degrees = (index + 0.5) * 360 / WALL_SEGMENTS
		local fromEntry = math.abs(((degrees - 180 + 180) % 360) - 180)
		if fromEntry < ENTRY_HALF_ANGLE then
			continue
		end
		local frame = center * Layout.facingCenter(Vector3.zero, degrees, radius + 1.5)
		Kit.block(
			model,
			"HallWall",
			Vector3.new(arc * 1.06, WALL_HEIGHT, Layout.WALL_THICKNESS),
			frame * CFrame.new(0, WALL_HEIGHT * 0.5, 0),
			World.ConcreteMid,
			Enum.Material.Concrete
		)
		Kit.block(
			model,
			"WallCap",
			Vector3.new(arc * 1.06, 1, Layout.WALL_THICKNESS + 1),
			frame * CFrame.new(0, WALL_HEIGHT + 0.5, 0),
			World.Steel,
			Enum.Material.Metal
		)
	end
	-- Grated ceiling truss: a ring and spokes with spotlights over the bays.
	local trussHeight = WALL_HEIGHT - 3
	for _, degrees in { -60, -20, 20, 60 } do
		local from = (center * CFrame.new(0, trussHeight, 0)).Position
		local to = (center * CFrame.new(Layout.direction(degrees) * (radius - 3) + Vector3.new(0, trussHeight, 0))).Position
		Kit.truss(model, from, to, 3)
	end
	local entryWall = center * Layout.facingCenter(Vector3.zero, 180, radius + 1.5)
	Kit.arch(model, "EntryArch", entryWall, Layout.HALL_WIDTH + 1, 19, Layout.WALL_THICKNESS + 1, World.Concrete)
end

local function buildPad(model: Model, padFrame: CFrame, mode: Types.ModeDef): BasePart
	local pad = Kit.disc(
		model,
		"QueuePad_" .. mode.id,
		PAD_RADIUS,
		0.6,
		padFrame * CFrame.new(0, 0.3, 0),
		World.SteelLight,
		Enum.Material.DiamondPlate
	)
	pad:SetAttribute(Constants.Attributes.ModeId, mode.id)
	pad:SetAttribute(Constants.Attributes.QueueRadius, PAD_RADIUS + 0.5)
	CollectionService:AddTag(pad, Constants.Tags.QueuePad)
	-- Ring segments live in a folder under the pad; each client colours them for its own player.
	local ringFolder = Instance.new("Folder")
	ringFolder.Name = "Ring"
	local segments = Kit.ring(
		ringFolder,
		"Segment",
		padFrame * CFrame.new(0, 0.08, 0),
		RING_RADIUS,
		0.9,
		0.12,
		Constants.Queue.RING_SEGMENTS,
		World.RingUnlit
	)
	for index, segment in segments do
		segment.Name = `Segment_{index}`
		segment.CanQuery = false
	end
	ringFolder.Parent = pad
	Kit.hazardStripe(model, padFrame * CFrame.new(0, 0.03, -(RING_RADIUS + 1.6)), 10, 1, 0.05)
	return pad
end

local function buildBay(model: Model, center: CFrame, degrees: number, mode: Types.ModeDef?, order: number): BlastDoor?
	local radius = Layout.DUELS_RADIUS
	local bay = Instance.new("Model")
	bay.Name = if mode ~= nil then "Bay_" .. mode.id else "Bay_Limited"
	local wallFrame = center * Layout.facingCenter(Vector3.zero, degrees, radius)
	local color = if mode ~= nil then mode.signColor else ModeConfig.CategoryColors.Limited

	-- Blast door recess and door.
	Kit.block(
		bay,
		"DoorFrame",
		Vector3.new(DOOR_WIDTH + 2.4, DOOR_HEIGHT + 1.2, 1.2),
		wallFrame * CFrame.new(0, (DOOR_HEIGHT + 1.2) * 0.5, -0.4),
		World.Steel,
		Enum.Material.Metal
	)
	local closed = wallFrame * CFrame.new(0, DOOR_HEIGHT * 0.5, -1.1)
	local door: BasePart = Kit.block(
		bay,
		"BlastDoor",
		Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 0.6),
		closed,
		World.SteelLight,
		Enum.Material.DiamondPlate
	)
	Kit.hazardStripe(bay, closed * CFrame.new(0, -DOOR_HEIGHT * 0.5 + 0.8, -0.35), DOOR_WIDTH, 0.1, 1.2)
	-- Category sign over the door.
	local title = if mode ~= nil then string.upper(mode.displayName) else "LIMITED TIME"
	Kit.sign(
		bay,
		"BaySign",
		wallFrame * CFrame.new(0, DOOR_HEIGHT + 3.2, -0.9),
		Vector2.new(DOOR_WIDTH + 2, 2.4),
		title,
		color,
		World.Steel,
		color,
		Theme.Fonts.Title
	)
	Kit.glow(
		bay,
		"SignUnderline",
		Vector3.new(DOOR_WIDTH + 2, 0.15, 0.15),
		wallFrame * CFrame.new(0, DOOR_HEIGHT + 1.85, -1.15),
		color
	)

	-- Wall screen beside the door with mode name, team size, queued, wait, countdown.
	local screenFrame = wallFrame * CFrame.new(0, DOOR_HEIGHT + 8, -0.9)
	local attributes: { [string]: any } = { [Constants.Attributes.ModeId] = if mode ~= nil then mode.id else "" }
	Kit.screen(
		bay,
		"BayScreen",
		screenFrame,
		Vector2.new(DOOR_WIDTH + 2, 5.5),
		if mode ~= nil then Screen.Bay else Screen.LimitedBay,
		attributes
	)

	local padFrame = center * Layout.facingCenter(Vector3.zero, degrees, PAD_DISTANCE)
	if mode ~= nil then
		buildPad(bay, padFrame, mode)
		-- Hazard guide from the entrance to this pad.
		local entry = (center * CFrame.new(0, 0, -(radius - 8))).Position
		Kit.floorLine(
			bay,
			entry,
			padFrame.Position + (entry - padFrame.Position).Unit * (RING_RADIUS + 1),
			0.6,
			World.Hazard
		)
	else
		Kit.disc(
			bay,
			"ClosedPad",
			PAD_RADIUS,
			0.3,
			padFrame * CFrame.new(0, 0.15, 0),
			World.ConcreteMid,
			Enum.Material.Concrete
		)
	end
	bay:SetAttribute("BayOrder", order)
	bay.Parent = model

	if mode == nil then
		return nil
	end
	door:SetAttribute(Constants.Attributes.ModeId, mode.id)
	CollectionService:AddTag(door, Constants.Tags.BlastDoor)
	return { modeId = mode.id, door = door, closed = closed }
end

function DuelsHall.build(parent: Instance, origin: CFrame): DuelsResult
	local model = Instance.new("Model")
	model.Name = "DuelsHall"
	local center = origin * CFrame.new(Layout.DUELS_CENTER)
	buildShell(model, center)

	local bays = ModeConfig.bayModes()
	local bayCount = 0
	for _, mode in bays do
		bayCount = math.max(bayCount, mode.bayOrder)
	end
	local limitedOrder = ModeConfig.LimitedBayOrder
	local hasLimited = false
	for _, mode in bays do
		if mode.bayOrder == limitedOrder then
			hasLimited = true
		end
	end
	bayCount = math.max(bayCount, limitedOrder)

	local doors: { BlastDoor } = {}
	for _, mode in bays do
		local door = buildBay(model, center, bayAngle(mode.bayOrder, bayCount), mode, mode.bayOrder)
		if door ~= nil then
			table.insert(doors, door)
		end
	end
	if not hasLimited then
		buildBay(model, center, bayAngle(limitedOrder, bayCount), nil, limitedOrder)
	end

	-- Ranked leaderboard walls on the side walls near the entrance, one per rating key.
	local boardAngles = { -118, 118 }
	local index = 0
	for _, modeId in ModeConfig.Order do
		local ratingKey = RankConfig.RatingKeys[modeId]
		if ratingKey ~= nil then
			index += 1
			local degrees = boardAngles[index]
			if degrees == nil then
				break
			end
			local frame = center * Layout.facingCenter(Vector3.zero, degrees, Layout.DUELS_RADIUS - 0.6)
			Kit.screen(
				model,
				"RankedBoard_" .. ratingKey,
				frame * CFrame.new(0, 10, 0),
				Vector2.new(14, 12),
				Screen.Leaderboard,
				{
					[Constants.Attributes.Board] = "Rank_" .. ratingKey,
				}
			)
			Kit.sign(
				model,
				"RankedBoardTitle",
				frame * CFrame.new(0, 17.6, 0),
				Vector2.new(14, 1.8),
				`{RankConfig.RatingKeyNames[ratingKey]} RANKED`,
				Theme.Areas.DuelsGold,
				World.Steel,
				Theme.Areas.DuelsGold,
				Theme.Fonts.Title
			)
		end
	end
	-- Rank card (each player sees their own) beside the entrance.
	local cardFrame = center * Layout.facingCenter(Vector3.zero, 152, Layout.DUELS_RADIUS - 0.6)
	Kit.screen(model, "RankCard", cardFrame * CFrame.new(0, 7, 0), Vector2.new(9, 6), Screen.RankCard)

	model.Parent = parent
	local returnPoint = center * CFrame.new(0, 3, -(Layout.DUELS_RADIUS - 12)) * CFrame.Angles(0, math.pi, 0)
	return { returnPoint = returnPoint, doors = doors }
end

return DuelsHall

--!strict
-- Code-built lobby: a modern country-club clubhouse. A round marble atrium with a
-- premium three-tier fountain under a glass lantern, an oak ceiling on black-steel
-- crossbeams and pillars, steel-framed window bays with leather lounges, and four
-- service stations (Locker, Daily Rewards, Upgrades, Creator Code) at the edges.
-- Four wings off the atrium: N Matchmaking, E Shop, S Practice, W Leaderboards.
-- Outside: meadow grounds with trees and a pond. Geometry only: services attach
-- prompts, SurfaceGuis and logic through the LobbyTypes.Lobby contract.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Skins = require(Shared:WaitForChild("Skins"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local LobbyKit = require(script.Parent:WaitForChild("LobbyKit"))
local Fountain = require(script.Parent:WaitForChild("Fountain"))
local CourseNature = require(script.Parent:WaitForChild("CourseNature"))
local LobbyTypes = require(script.Parent:WaitForChild("LobbyTypes"))

type Props = Parts.Props

local LobbyBuilder = {}

-- Palette -------------------------------------------------------------------
-- Marble, walnut, oak, black steel, brass, cognac leather, forest-green carpet.

local C = Config.Colors
local hex = Color3.fromHex
local M = Enum.Material

local MARBLE = hex("#EEEAE3")
local MARBLE_DARK = hex("#35383C")
local GRANITE = hex("#2B2D30")
local WALNUT = hex("#4B3324")
local WALNUT_DARK = hex("#30221A")
local WALNUT_MID = hex("#6A4A35")
local OAK = hex("#BC8F63") -- ceiling planks
local FLOOR_A = hex("#A97C54") -- floor planks
local FLOOR_B = hex("#9A6F4A")
local PLASTER = hex("#F1ECE3")
local STEEL = hex("#2A2C30")
local BRASS = hex("#C8A15A")
local LEATHER = hex("#8B4F2E")
local RUG = hex("#2E4A3B")
local RUG_BORDER = hex("#C8B489")
local QUARTZ = hex("#F6F3ED")
local STONE = hex("#A79E90") -- exterior limestone
local MOSAIC = hex("#1E4D59")
local POT = hex("#E3DDD3")
local SOIL = hex("#3A2A20")
local LEAF = hex("#4E7A39")
local SCREEN = hex("#12151B")
local WHITE = hex("#F7F2E8")
local GOLD = C.Gold
local SILVER = hex("#C9D3E6")
local BRONZE = hex("#D9895B")
local MYTHIC = hex("#B3203D")
local LANE_GREEN = hex("#4E9A4A")
local LAMP = hex("#FFE3B3")
local WATER = hex("#69B4D2")
local GLASS = hex("#A8C4CF")
local HEDGE = hex("#3F6A2E")

-- Names the room builders use.
local WALL = PLASTER
local WOOD_DARK = WALNUT
local WOOD = WALNUT_MID

-- Plain parts in these colours get the matching material in naturalize().
local MATERIAL_OF: { [string]: Enum.Material } = {
	[MARBLE:ToHex()] = M.Marble,
	[MARBLE_DARK:ToHex()] = M.Marble,
	[QUARTZ:ToHex()] = M.Marble,
	[GRANITE:ToHex()] = M.Granite,
	[WALNUT:ToHex()] = M.Wood,
	[WALNUT_DARK:ToHex()] = M.Wood,
	[WALNUT_MID:ToHex()] = M.Wood,
	[OAK:ToHex()] = M.WoodPlanks,
	[FLOOR_A:ToHex()] = M.WoodPlanks,
	[FLOOR_B:ToHex()] = M.WoodPlanks,
	[PLASTER:ToHex()] = M.Plaster,
	[STEEL:ToHex()] = M.Metal,
	[BRASS:ToHex()] = M.Metal,
	[GOLD:ToHex()] = M.Metal,
	[LEATHER:ToHex()] = M.Leather,
	[RUG:ToHex()] = M.Carpet,
	[RUG_BORDER:ToHex()] = M.Carpet,
	[STONE:ToHex()] = M.Limestone,
	[MOSAIC:ToHex()] = M.Slate,
	[SOIL:ToHex()] = M.Ground,
	[LEAF:ToHex()] = M.LeafyGrass,
	[LANE_GREEN:ToHex()] = M.Fabric,
}
-- Walkable parts keep plastic physics whatever they look like (balls roll the same).
local SMOOTH_PHYS = PhysicalProperties.new(0.7, 0.2, 0.5, 1, 1)

local NEON = M.Neon
local PI = math.pi
local UP = Vector3.yAxis

-- Dimensions (floor top is Y = 0, fountain at the origin) ---------------------

local LOBBY_R = 56 -- inner face of the atrium wall
local WALL_T = 2
local HUB_H = 18 -- ceiling height at the atrium edge
local LANTERN_R = 22 -- glass lantern over the fountain
local LANTERN_H = 27
local PLAZA_R = 26 -- brass ring around the fountain plaza
local DOOR_HALF = 12
local ARCH_H = 13 -- doorway height (atrium and wings)
local ROOM_DIST = 100
local ROOM_W = 44 -- half width
local ROOM_D = 32 -- half depth
local ROOM_H = 22
local HALL_HALF = 12
local NEAR_WALL = ROOM_DIST - ROOM_D -- axial distance of a room's entrance wall (inside face)
local STATION_R = 51 -- station frame distance from the centre

-- Yaw offsets for along(): which way a part's LookVector points in a quadrant/room frame.
local TO_BACK = 0 -- away from the lobby
local TO_ENTRANCE = PI -- back toward the lobby
local TO_PLUS_X = -PI / 2
local TO_MINUS_X = PI / 2

-- Small helpers -------------------------------------------------------------

local function solid(color: Color3, name: string?): Props
	return { Color = color, Name = name }
end

-- Non-colliding detail (trims, inlays, painted accent strips).
local function deco(color: Color3, name: string?): Props
	return { Color = color, CanCollide = false, CanQuery = false, Name = name }
end

-- Lamp glass: the only glowing parts in the lobby (naturalize keeps names starting "Lamp").
local function lamp(): Props
	return { Color = LAMP, Material = NEON, CanCollide = false, CanQuery = false, Name = "Lamp" }
end

local function mat(color: Color3, material: Enum.Material, name: string?): Props
	return { Color = color, Material = material, Name = name }
end

local function glassProps(name: string): Props
	return { Name = name, Color = GLASS, Material = M.Glass, Transparency = 0.7, Reflectance = 0.1, CastShadow = false }
end

local BARRIER: Props = { Name = "Barrier", Transparency = 1, CastShadow = false }

local KIT: LobbyKit.Palette = {
	Leather = mat(LEATHER, M.Leather),
	Wood = mat(WALNUT, M.Wood),
	Metal = mat(STEEL, M.Metal),
	Brass = mat(BRASS, M.Metal),
	Stone = mat(QUARTZ, M.Marble),
	Fabric = mat(RUG, M.Fabric),
	Lamp = lamp(),
	Leaf = mat(LEAF, M.LeafyGrass),
	Pot = { Color = POT, Material = M.SmoothPlastic, Reflectance = 0.08 },
	Soil = mat(SOIL, M.Ground),
}

-- Frame helpers. A quadrant frame sits at the fountain with its LookVector
-- pointing out toward the room; a room frame sits at the room centre with the
-- same orientation. (x, y, d): x lateral (+x = frame right), d = distance along the look.
local function along(frame: CFrame, x: number, y: number, d: number, yaw: number?): CFrame
	return frame * CFrame.new(x, y, -d) * CFrame.Angles(0, yaw or 0, 0)
end

local function at(frame: CFrame, x: number, y: number, d: number): Vector3
	return frame:PointToWorldSpace(Vector3.new(x, y, -d))
end

-- Compass position: deg measured clockwise from North (-Z) toward East (+X).
local function polar(r: number, deg: number, y: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(r * math.sin(a), y, -r * math.cos(a))
end

local function inward(r: number, deg: number, y: number): CFrame
	local p = polar(r, deg, y)
	return CFrame.lookAt(p, Vector3.new(0, y, 0))
end

-- Upright panel with rounded corners in its face plane (cf's LookVector faces the viewer).
local function roundPanel(parent: Instance, cf: CFrame, w: number, h: number, depth: number, radius: number, props: Props?): Part
	return Parts.roundedBox(parent, cf * CFrame.Angles(PI / 2, 0, 0), Vector3.new(w, depth, h), radius, props)
end

-- Static text on an invisible carrier part (Front = cf's LookVector). Lit by the
-- scene unless `glowing` is true.
local function text(parent: Instance, cf: CFrame, w: number, h: number, str: string, color: Color3, stroke: Color3?, glowing: boolean?, font: Enum.Font?): Part
	local p = Parts.block(parent, cf, Vector3.new(w, h, 0.1), {
		Name = "Text",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	Parts.label(p, Enum.NormalId.Front, str, {
		TextColor = color,
		Stroke = stroke,
		Glow = glowing == true,
		Font = font or Config.Font,
		PixelsPerStud = if w > 20 then 20 else 30,
	})
	return p
end

-- Contract screen: dark display (Front = cf's LookVector) in a black-steel bezel with
-- a hairline brass edge. Returns the screen part.
local function screen(parent: Instance, name: string, cf: CFrame, w: number, h: number, _accent: Color3?): BasePart
	local m = Parts.model(parent, name)
	roundPanel(m, cf * CFrame.new(0, 0, 0.35), w + 0.9, h + 0.9, 0.5, 0.35, solid(STEEL, "Bezel"))
	local e = 0.08
	Parts.block(m, cf * CFrame.new(0, h / 2 + e / 2, 0.02), Vector3.new(w + 2 * e, e, 0.16), deco(BRASS, "Edge"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 - e / 2, 0.02), Vector3.new(w + 2 * e, e, 0.16), deco(BRASS, "Edge"))
	Parts.block(m, cf * CFrame.new(w / 2 + e / 2, 0, 0.02), Vector3.new(e, h, 0.16), deco(BRASS, "Edge"))
	Parts.block(m, cf * CFrame.new(-w / 2 - e / 2, 0, 0.02), Vector3.new(e, h, 0.16), deco(BRASS, "Edge"))
	return Parts.block(m, cf, Vector3.new(w, h, 0.2), { Name = name, Color = SCREEN, CanCollide = false })
end

-- Walnut sign board with brass lettering and a slim accent line under the text.
local function titlePlate(parent: Instance, cf: CFrame, w: number, h: number, str: string, accent: Color3)
	local m = Parts.model(parent, "Title")
	roundPanel(m, cf * CFrame.new(0, 0, 0.4), w, h, 0.8, math.min(0.6, h / 4), solid(WALNUT_DARK, "Plate"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 + 0.22, 0), Vector3.new(w * 0.32, math.min(0.12, h * 0.06), 0.06), deco(accent, "Accent"))
	text(m, cf * CFrame.new(0, 0.08, -0.06), w - 1.2, h * 0.62, str, BRASS:Lerp(WHITE, 0.25))
end

local function display(part: BasePart, worldPos: Vector3)
	local a = Instance.new("Attachment")
	a.Name = "Display"
	a.CFrame = part.CFrame:ToObjectSpace(CFrame.new(worldPos))
	a.Parent = part
end

-- Flat floor pad: dark marble disc flush with the floor inside a brass ring.
local function pad(parent: Instance, name: string, pos: Vector3, diameter: number, accent: Color3): BasePart
	Parts.disc(parent, pos + Vector3.new(0, -0.03, 0), diameter + 0.7, 0.14, deco(BRASS, name .. "Ring"))
	Parts.disc(parent, pos + Vector3.new(0, -0.02, 0), diameter + 0.25, 0.14, deco(accent, name .. "Accent"))
	local p = Parts.disc(parent, pos + Vector3.new(0, -0.01, 0), diameter, 0.2, { Name = name, Color = MARBLE_DARK, CanCollide = false })
	p:SetAttribute("Radius", diameter / 2)
	return p
end

-- Showcase pedestal: walnut foot, brass band, marble drum, quartz cap. Returns the cap.
local function roundPedestal(parent: Instance, name: string, pos: Vector3, ring: Color3, capColor: Color3?, lift: number?): BasePart
	local m = Parts.model(parent, name)
	Parts.disc(m, pos + Vector3.new(0, 0.2, 0), 4.2, 0.4, solid(WALNUT_DARK, "Base"))
	Parts.disc(m, pos + Vector3.new(0, 0.46, 0), 3.7, 0.12, deco(BRASS, "Band"))
	Parts.disc(m, pos + Vector3.new(0, 1.6, 0), 3.3, 2.2, solid(MARBLE, "Column"))
	Parts.disc(m, pos + Vector3.new(0, 2.76, 0), 3.5, 0.1, deco(ring, "Ring"))
	local cap = Parts.disc(m, pos + Vector3.new(0, 2.975, 0), 3.7, 0.35, solid(capColor or QUARTZ, name))
	display(cap, pos + Vector3.new(0, 3.15 + (lift or 2.5), 0))
	return cap
end

-- Leather bench (rooms). cf faces the way a sitter looks.
local function bench(parent: Instance, cf: CFrame, _accent: Color3?)
	LobbyKit.sofa(parent, cf, KIT, 7)
end

-- Quadrants -------------------------------------------------------------------

type Quad = {
	Key: string,
	Frame: CFrame, -- at the fountain, LookVector toward the room
	Color: Color3,
	Arch: string, -- doorway sign
}

local QUADS: { Quad } = {
	{ Key = "North", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1)), Color = C.North, Arch = "MATCHMAKING" },
	{ Key = "East", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0)), Color = C.East, Arch = "PRO SHOP" },
	{ Key = "South", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1)), Color = C.South, Arch = "PRACTICE RANGE" },
	{ Key = "West", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(-1, 0, 0)), Color = C.West, Arch = "LEADERBOARDS" },
}

local function roomFrame(quad: Quad): CFrame
	return quad.Frame * CFrame.new(0, 0, -ROOM_DIST)
end

-- Grounds (terrain) -------------------------------------------------------------

local MEADOW: CourseNature.Palette = {
	Foliage = hex("#5C8A3A"),
	Accent = hex("#F4C542"),
	Rock = hex("#8C8A84"),
	Trim = WHITE,
	Water = WATER,
}

local POND = polar(96, 45, 0)
local HUB_OUT = LOBBY_R + WALL_T + 3 -- roof edge

-- Meadow around the clubhouse, carved out under every floor, a pond in the
-- north-east corner and low hills on the horizon.
local function buildGrounds(rng: Random)
	local terrain = workspace.Terrain
	local ext = ROOM_DIST + ROOM_D + 170
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(ext * 2, 12, ext * 2), M.Grass)
	for _ = 1, 18 do
		local p = polar(rng:NextNumber(HUB_OUT + 30, ext - 20), rng:NextNumber(0, 360), -0.8)
		local size = Vector3.new(rng:NextNumber(14, 30), 1.4, rng:NextNumber(14, 30))
		terrain:FillBlock(CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, PI), 0), size, M.LeafyGrass)
	end
	-- Stone paving round the building, then carve the top layer out under the floors.
	terrain:FillCylinder(CFrame.new(0, -2, 0), 4, HUB_OUT + 2, M.Pavement)
	terrain:FillCylinder(CFrame.new(0, -2, 0), 4, LOBBY_R + WALL_T, M.Air)
	for _, quad in QUADS do
		local R = roomFrame(quad)
		terrain:FillBlock(R * CFrame.new(0, -2, 0), Vector3.new(2 * ROOM_W + 12, 4, 2 * ROOM_D + 12), M.Pavement)
		terrain:FillBlock(R * CFrame.new(0, -2, 0), Vector3.new(2 * ROOM_W + 2, 4, 2 * ROOM_D + 2), M.Air)
		terrain:FillBlock(along(quad.Frame, 0, -2, (LOBBY_R + NEAR_WALL) / 2), Vector3.new(HALL_HALF * 2 + 2, 4, NEAR_WALL - LOBBY_R + 2), M.Air)
	end
	terrain:FillCylinder(CFrame.new(POND + Vector3.new(0, -2, 0)), 3.4, 10, M.Water)
	for i = 0, 17 do
		local r = rng:NextNumber(26, 44)
		terrain:FillBall(polar(rng:NextNumber(225, 265), i * 20 + rng:NextNumber(-6, 6), -r * 0.55), r, M.Grass)
	end
end

-- True when a prop of radius `r` at p stays clear of the buildings and the pond.
local function openGround(p: Vector3, r: number): boolean
	local flat = Vector3.new(p.X, 0, p.Z)
	if flat.Magnitude < HUB_OUT + 4 + r or (flat - POND).Magnitude < 12 + r then
		return false
	end
	for _, quad in QUADS do
		local l = roomFrame(quad):PointToObjectSpace(flat)
		if math.abs(l.X) < ROOM_W + 8 + r and math.abs(l.Z) < ROOM_D + 8 + r then
			return false
		end
		local h = quad.Frame:PointToObjectSpace(flat)
		if math.abs(h.X) < HALL_HALF + 4 + r and -h.Z > 0 and -h.Z < NEAR_WALL + 2 then
			return false
		end
	end
	return true
end

-- Trees, bushes and rocks on the grounds (decoration: they never collide).
local function buildScenery(parent: Instance, rng: Random)
	local m = Parts.model(parent, "Scenery")
	local placed = 0
	for _ = 1, 500 do
		if placed >= 30 then
			break
		end
		local p = polar(rng:NextNumber(HUB_OUT + 6, 175), rng:NextNumber(0, 360), 0)
		if openGround(p, 5) then
			CourseNature.prop(m, if rng:NextNumber() < 0.7 then "Oak" else "Bush", p, -p.Unit, rng, MEADOW)
			placed += 1
		end
	end
	for i = 0, 39 do
		local p = polar(rng:NextNumber(185, 215), i * 9 + rng:NextNumber(-3, 3), 0)
		CourseNature.prop(m, "Oak", p, -p.Unit, rng, MEADOW, true)
	end
	for _ = 1, 5 do
		local p = POND + polar(rng:NextNumber(11, 13), rng:NextNumber(0, 360), 0)
		CourseNature.prop(m, "Rock", p, -p.Unit, rng, MEADOW)
	end
	-- Clipped hedges along the building's outer walls between the wings.
	for q = 0, 3 do
		for _, deg in { q * 90 + 30, q * 90 + 60 } do
			local cf = CFrame.lookAt(polar(HUB_OUT + 2.5, deg, 1.6), Vector3.new(0, 1.6, 0))
			Parts.roundedBox(m, cf, Vector3.new(12, 3.2, 2.4), 1, mat(HEDGE, M.LeafyGrass, "Hedge"))
		end
	end
end

-- Atrium floor ----------------------------------------------------------------
-- Marble field, granite border with a brass inlay, walnut runners to each door, a
-- brass-ringed plaza with a 16-point compass star around the fountain.

local function buildFloor(parent: Instance)
	local f = Parts.model(parent, "Floor")
	Parts.disc(f, Vector3.new(0, -0.5, 0), (LOBBY_R + WALL_T) * 2, 1, solid(MARBLE, "Base"))
	LobbyKit.ring(f, Vector3.zero, 47.4, LOBBY_R + 0.4, -0.02, 0.03, 72, deco(GRANITE, "Border"))
	LobbyKit.ring(f, Vector3.zero, 46.9, 47.4, -0.02, 0.04, 72, deco(BRASS, "BorderInlay"))
	LobbyKit.ring(f, Vector3.zero, PLAZA_R - 0.6, PLAZA_R, -0.02, 0.04, 64, deco(WALNUT, "PlazaInlay"))
	LobbyKit.ring(f, Vector3.zero, PLAZA_R, PLAZA_R + 0.3, -0.02, 0.045, 64, deco(BRASS, "PlazaBrass"))
	-- Compass star between the fountain step and the plaza ring.
	local rIn = Fountain.Radius + 0.4
	for i = 0, 15 do
		local deg = i * 22.5
		local long = i % 2 == 0
		local tip = polar(if long then PLAZA_R - 0.8 else PLAZA_R - 4.5, deg, 0.035)
		local half = if long then 5 else 3.4
		local mid = polar(rIn, deg, 0.035)
		Parts.triangle(f, mid, polar(rIn, deg - half, 0.035), tip, 0.05, deco(MARBLE_DARK, "Star"))
		Parts.triangle(f, mid, polar(rIn, deg + half, 0.035), tip, 0.05, deco(if long then WALNUT else GRANITE, "Star"))
	end
	-- Walnut runners from the plaza to each doorway (they continue into the walkways).
	for _, quad in QUADS do
		local d0, d1 = PLAZA_R + 0.3, LOBBY_R + 0.4
		local len = d1 - d0
		Parts.block(f, along(quad.Frame, 0, 0.02, d0 + len / 2), Vector3.new(7, 0.06, len), deco(WALNUT, "Runner"))
		for _, s in { -1, 1 } do
			Parts.block(f, along(quad.Frame, s * 3.65, 0.025, d0 + len / 2), Vector3.new(0.3, 0.07, len), deco(BRASS, "RunnerEdge"))
		end
	end
end

-- Atrium wall -----------------------------------------------------------------
-- Per quarter (degrees from the quarter's doorway axis): door surround, window bay,
-- solid station wall, window bay, door surround. Steel pillars stand at every zone
-- boundary. Windows are steel-framed glass curtain walls onto the grounds.

local DOOR_DEG = math.deg(math.asin((DOOR_HALF + 0.6) / LOBBY_R))
local ZONES = {
	{ From = DOOR_DEG, To = 17.5, Kind = "Solid" },
	{ From = 17.5, To = 31.5, Kind = "Window" },
	{ From = 31.5, To = 58.5, Kind = "Solid" },
	{ From = 58.5, To = 72.5, Kind = "Window" },
	{ From = 72.5, To = 90 - DOOR_DEG, Kind = "Solid" },
}
local PILLAR_DEGS = { 17.5, 31.5, 58.5, 72.5 }
local BAY_DEGS = { 24.5, 65.5 }

local function wallSegment(m: Instance, deg: number, step: number, kind: string)
	local rMid = LOBBY_R + WALL_T / 2
	local w = 2 * (LOBBY_R + WALL_T) * math.tan(math.rad(step / 2)) + 0.06
	local wIn = 2 * LOBBY_R * math.tan(math.rad(step / 2)) + 0.06
	local top = HUB_H + 0.6
	if kind == "Solid" then
		Parts.block(m, inward(rMid, deg, top / 2), Vector3.new(w, top, WALL_T), solid(PLASTER, "Wall"))
		Parts.block(m, inward(LOBBY_R - 0.15, deg, 2.1), Vector3.new(wIn, 3.6, 0.3), solid(WALNUT, "Wainscot"))
		Parts.block(m, inward(LOBBY_R - 0.25, deg, 0.3), Vector3.new(wIn, 0.6, 0.5), solid(WALNUT_DARK, "Skirting"))
		Parts.block(m, inward(LOBBY_R - 0.32, deg, 3.95), Vector3.new(wIn, 0.14, 0.3), deco(BRASS, "Rail"))
		Parts.block(m, inward(LOBBY_R - 0.3, deg, HUB_H - 0.35), Vector3.new(wIn, 0.7, 0.6), solid(WALNUT, "Crown"))
		-- Outside: limestone cladding.
		Parts.block(m, inward(LOBBY_R + WALL_T + 0.2, deg, top / 2), Vector3.new(w + 0.1, top, 0.4), solid(STONE, "Cladding"))
	else
		-- Glass curtain wall: walnut sill, glass, steel transom and head.
		Parts.block(m, inward(rMid, deg, 0.5), Vector3.new(w, 1, WALL_T + 0.4), solid(WALNUT_DARK, "Sill"))
		Parts.block(m, inward(rMid, deg, (1 + HUB_H - 1.2) / 2), Vector3.new(w, HUB_H - 2.2, 0.3), glassProps("Glass"))
		Parts.block(m, inward(rMid, deg, 12.4), Vector3.new(w, 0.35, 0.6), solid(STEEL, "Transom"))
		Parts.block(m, inward(rMid, deg, HUB_H - 0.5), Vector3.new(w, 2.2, WALL_T), solid(PLASTER, "Head"))
		Parts.block(m, inward(LOBBY_R - 0.3, deg, HUB_H - 0.35), Vector3.new(wIn, 0.7, 0.6), solid(WALNUT, "Crown"))
		Parts.block(m, inward(rMid, deg, 10), Vector3.new(w, 20, WALL_T), BARRIER)
	end
end

local function mullion(m: Instance, deg: number)
	Parts.block(m, inward(LOBBY_R + WALL_T / 2, deg, (1 + HUB_H - 1.4) / 2), Vector3.new(0.3, HUB_H - 2.4, 0.55), solid(STEEL, "Mullion"))
end

local function buildWall(parent: Instance)
	local m = Parts.model(parent, "Wall")
	for q = 0, 3 do
		local base = q * 90
		for _, z in ZONES do
			local span = z.To - z.From
			local n = math.max(1, math.ceil(span / 3.6))
			local step = span / n
			for i = 0, n - 1 do
				local deg = base + z.From + (i + 0.5) * step
				wallSegment(m, deg, step, z.Kind)
				if z.Kind == "Window" and i > 0 then
					mullion(m, base + z.From + i * step)
				end
			end
		end
		for _, pd in PILLAR_DEGS do
			local deg = base + pd
			LobbyKit.column(m, polar(LOBBY_R - 1.2, deg, 0), HUB_H, 1.5, solid(STEEL, "Pillar"))
			mullion(m, deg)
		end
	end
	-- Roof edge: a steel fascia ring and the flat roof over the atrium.
	LobbyKit.ring(m, Vector3.zero, LOBBY_R + WALL_T + 0.4, HUB_OUT, HUB_H + 0.2, HUB_H + 1.8, 64, solid(STEEL, "Fascia"))
	LobbyKit.ring(m, Vector3.zero, LANTERN_R, LOBBY_R + WALL_T + 0.5, HUB_H + 0.6, HUB_H + 1.2, 48, solid(STONE, "Roof"))
end

-- Doorway: steel portal, walnut lining, header wall with the brass-lettered sign
-- and sconces either side.
local function buildDoorway(parent: Instance, quad: Quad)
	local m = Parts.model(parent, "Door" .. quad.Key)
	local q = quad.Frame
	local d = LOBBY_R + WALL_T / 2
	local x = DOOR_HALF + 0.6
	local top = HUB_H + 0.6
	Parts.block(m, along(q, 0, (ARCH_H + top) / 2, d), Vector3.new(2 * x + 2.4, top - ARCH_H, WALL_T), solid(PLASTER, "Header"))
	Parts.block(m, along(q, 0, (ARCH_H + top) / 2, d + WALL_T / 2 + 0.2), Vector3.new(2 * x + 2.4, top - ARCH_H, 0.4), solid(STONE, "Cladding"))
	for _, s in { -1, 1 } do
		Parts.block(m, along(q, s * x, ARCH_H / 2, d), Vector3.new(1.2, ARCH_H, WALL_T + 1.2), solid(STEEL, "Jamb"))
		Parts.block(m, along(q, s * (x - 0.75), ARCH_H / 2, d), Vector3.new(0.3, ARCH_H - 0.2, WALL_T + 0.6), solid(WALNUT, "Lining"))
		LobbyKit.sconce(m, along(q, s * (x + 3), 8.5, LOBBY_R - 0.4, TO_ENTRANCE), KIT)
	end
	Parts.block(m, along(q, 0, ARCH_H + 0.6, d), Vector3.new(2 * x + 1.2, 1.2, WALL_T + 1.2), solid(STEEL, "Head"))
	Parts.block(m, along(q, 0, ARCH_H - 0.15, d), Vector3.new(2 * x - 1.2, 0.3, WALL_T + 0.6), solid(WALNUT, "Soffit"))
	Parts.block(m, along(q, 0, 0.02, d), Vector3.new(2 * x, 0.06, WALL_T + 1), deco(BRASS, "Threshold"))
	titlePlate(m, along(q, 0, ARCH_H + 2.9, LOBBY_R - 0.55, TO_ENTRANCE), 2 * x - 1, 3.1, quad.Arch, quad.Color)
end

-- Ceiling ---------------------------------------------------------------------
-- Oak plank ceiling on radial black-steel I-beams with a ring beam, an LED cove
-- round the lantern, the glass lantern itself and a halo chandelier over the fountain.

local function buildCeiling(parent: Instance)
	local m = Parts.model(parent, "Ceiling")
	local oak = solid(OAK, "Ceiling")
	LobbyKit.ring(m, Vector3.zero, LANTERN_R, 34, HUB_H, HUB_H + 0.6, 40, oak)
	LobbyKit.ring(m, Vector3.zero, 34, 46, HUB_H + 0.01, HUB_H + 0.6, 56, oak)
	LobbyKit.ring(m, Vector3.zero, 46, LOBBY_R + WALL_T, HUB_H + 0.02, HUB_H + 0.6, 72, oak)
	local steel = solid(STEEL, "Beam")
	local beamY = HUB_H - 0.75
	local degs = {}
	for q = 0, 3 do
		table.insert(degs, q * 90)
		for _, pd in PILLAR_DEGS do
			table.insert(degs, q * 90 + pd)
		end
	end
	table.sort(degs)
	for _, deg in degs do
		LobbyKit.ibeam(m, polar(LANTERN_R + 0.6, deg, beamY), polar(LOBBY_R - 0.2, deg, beamY), 1.5, 0.8, steel)
	end
	for i, deg in degs do
		local nextDeg = degs[i % #degs + 1] + (if i == #degs then 360 else 0)
		LobbyKit.ibeam(m, polar(39, deg, beamY - 0.05), polar(39, nextDeg, beamY - 0.05), 1.2, 0.7, steel)
	end
	-- Ring beam round the lantern and the LED cove under it.
	LobbyKit.ring(m, Vector3.zero, LANTERN_R - 0.6, LANTERN_R + 0.6, HUB_H - 1.2, HUB_H + 0.6, 36, solid(STEEL, "RingBeam"))
	local cove = LobbyKit.ring(m, Vector3.zero, LANTERN_R + 0.6, LANTERN_R + 0.9, HUB_H - 0.25, HUB_H - 0.05, 48, lamp())
	for i, child in cove:GetChildren() do
		if i % 8 == 1 and child:IsA("BasePart") then
			Parts.light(child, LAMP, 16, 0.5, "Surface")
		end
	end
	-- Glass lantern: clerestory drum and a glass roof on steel ribs.
	local n = 24
	local w = 2 * LANTERN_R * math.tan(PI / n) + 0.05
	for i = 0, n - 1 do
		local deg = (i + 0.5) / n * 360
		Parts.block(m, inward(LANTERN_R, deg, (HUB_H + 0.6 + LANTERN_H) / 2), Vector3.new(w, LANTERN_H - HUB_H - 0.6, 0.3), glassProps("LanternGlass"))
		Parts.block(m, inward(LANTERN_R, i / n * 360, (HUB_H + 0.6 + LANTERN_H) / 2), Vector3.new(0.35, LANTERN_H - HUB_H - 0.6, 0.6), solid(STEEL, "LanternMullion"))
	end
	LobbyKit.ring(m, Vector3.zero, LANTERN_R - 0.5, LANTERN_R + 0.5, LANTERN_H, LANTERN_H + 0.9, 36, solid(STEEL, "LanternRing"))
	LobbyKit.ring(m, Vector3.zero, LANTERN_R - 0.3, LANTERN_R + 0.3, (HUB_H + LANTERN_H) / 2, (HUB_H + LANTERN_H) / 2 + 0.3, 36, solid(STEEL, "LanternTransom"))
	Parts.cylinder(m, CFrame.new(0, LANTERN_H + 0.7, 0), 0.25, LANTERN_R * 2, glassProps("LanternRoof"))
	for i = 0, 11 do
		local deg = i * 30
		LobbyKit.ibeam(m, polar(3, deg, LANTERN_H + 0.3), polar(LANTERN_R - 0.4, deg, LANTERN_H + 0.3), 0.9, 0.5, steel)
	end
	Parts.cylinder(m, CFrame.new(0, LANTERN_H + 0.4, 0), 1, 6.2, solid(STEEL, "Hub"))
	-- Halo chandelier: a brass ring of candle lamps hung from the lantern roof.
	local ringY = LANTERN_H - 4.2
	LobbyKit.torus(m, Vector3.new(0, ringY, 0), 9, 0.4, 40, deco(BRASS, "Halo"), false)
	LobbyKit.torus(m, Vector3.new(0, ringY - 0.55, 0), 8.6, 0.25, 40, deco(BRASS, "Halo"), false)
	for i = 0, 15 do
		local p = polar(9, i * 22.5, ringY + 0.5)
		Parts.cylinder(m, CFrame.new(p - UP * 0.2), 0.3, 0.55, deco(BRASS, "Cup"))
		local bulb = Parts.cylinder(m, CFrame.new(p + UP * 0.35), 0.8, 0.32, lamp())
		if i % 4 == 0 then
			Parts.light(bulb, LAMP, 22, 0.8)
		end
	end
	for i = 0, 3 do
		Parts.rod(m, polar(9, i * 90 + 45, ringY), polar(3, i * 90 + 45, LANTERN_H + 0.1), 0.08, deco(STEEL, "Hanger"))
	end
end

-- Lounges, planters, totems ------------------------------------------------------

-- Leather lounge in a window bay: rug, sofa with its back to the glass, two armchairs,
-- a coffee table and a pendant overhead.
local function buildLounge(parent: Instance, deg: number)
	local m = Parts.model(parent, "Lounge")
	local F = CFrame.lookAt(polar(47, deg, 0), Vector3.zero) -- looks toward the centre
	LobbyKit.rug(m, F, 11, 9, mat(RUG, M.Carpet), mat(RUG_BORDER, M.Carpet))
	LobbyKit.sofa(m, F * CFrame.new(0, 0, 2.8), KIT, 8)
	LobbyKit.coffeeTable(m, (F * CFrame.new(0, 0, -0.4)).Position, 3.6, KIT)
	for _, s in { -1, 1 } do
		LobbyKit.armchair(m, F * CFrame.new(s * 3.2, 0, -3.4) * CFrame.Angles(0, PI + s * 0.5, 0), KIT)
	end
	LobbyKit.pendant(m, (F * CFrame.new(0, 0, -0.4)).Position, HUB_H, 4.2, KIT, 16)
end

-- Slim monolith facing the spawn: marble base, steel frame, walnut face.
local function totem(parent: Instance, name: string, base: Vector3, faceTo: Vector3): (Model, CFrame)
	local m = Parts.model(parent, name)
	local cf = CFrame.lookAt(base, Vector3.new(faceTo.X, 0, faceTo.Z))
	Parts.roundedBox(m, cf * CFrame.new(0, 0.35, 0.2), Vector3.new(7.6, 0.7, 3), 0.6, solid(MARBLE, "Base"))
	Parts.block(m, cf * CFrame.new(0, 0.74, 0.2), Vector3.new(7, 0.08, 2.4), deco(BRASS, "BaseInlay"))
	Parts.block(m, cf * CFrame.new(0, 6.5, 0.45), Vector3.new(7, 11.6, 0.6), solid(STEEL, "Frame"))
	Parts.block(m, cf * CFrame.new(0, 6.5, 0.1), Vector3.new(6.4, 11, 0.2), solid(WALNUT, "Face"))
	Parts.block(m, cf * CFrame.new(0, 12.45, 0.45), Vector3.new(7.4, 0.3, 1), solid(STEEL, "Cap"))
	return m, cf
end

local SPAWN_POS = Vector3.new(0, 0.5, -31)

local function buildSpawn(parent: Instance): SpawnLocation
	local m = Parts.model(parent, "Spawn")
	local c = Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z)
	LobbyKit.ring(m, c, 4.2, 4.6, -0.01, 0.07, 32, deco(BRASS, "SpawnRing"))
	Parts.disc(m, c + UP * 0.03, 8.4, 0.08, deco(MARBLE_DARK, "SpawnPad"))
	for i = 0, 3 do
		local deg = i * 90
		Parts.triangle(m, c + polar(3.6, deg, 0.08), c + polar(0.5, deg - 45, 0.08), c + polar(0.5, deg + 45, 0.08), 0.04, deco(BRASS, "Needle"))
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.lookAt(SPAWN_POS, Vector3.new(0, SPAWN_POS.Y, 0))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CastShadow = false
	spawn.Duration = 0
	spawn.Parent = m
	return spawn
end

-- Directory totem (front-left of the spawn). Arrow directions are as seen from the
-- spawn looking south: +X (East) is to the player's left.
local function buildDirectory(parent: Instance): (BasePart, Vector3)
	local m, cf = totem(parent, "Directory", Vector3.new(12.5, 0, -21.5), Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z))
	local sign = Parts.block(m, cf * CFrame.new(0, 6.5, 0.02), Vector3.new(6.2, 10.8, 0.1), { Name = "DirectorySign", Color = WALNUT, Transparency = 1, CanCollide = false })
	text(m, cf * CFrame.new(0, 11.2, -0.05), 5.6, 1.3, "WHERE TO?", BRASS:Lerp(WHITE, 0.25))
	Parts.block(m, cf * CFrame.new(0, 10.35, -0.02), Vector3.new(3, 0.08, 0.06), deco(BRASS, "Rule"))
	local arrows = {
		{ Text = "▲  PRACTICE RANGE", Color = C.South },
		{ Text = "◀  PRO SHOP", Color = C.East },
		{ Text = "LEADERBOARDS  ▶", Color = C.West },
		{ Text = "▼  MATCHMAKING", Color = C.North },
	}
	for i, a in arrows do
		local y = 10.3 - i * 2.05
		Parts.block(m, cf * CFrame.new(-2.75, y, -0.04), Vector3.new(0.18, 1.3, 0.06), deco(a.Color, "Accent"))
		text(m, cf * CFrame.new(0.15, y, -0.06), 5.4, 1.2, a.Text, WHITE)
	end
	return sign, (cf * CFrame.new(0, 3, -5)).Position
end

local NEWS = {
	"Power-ups: earn them by sinking holes and knockouts",
	"More obstacles on every hole",
	"The new clubhouse is open",
	"Join Corny Games for updates",
}

local function buildNews(parent: Instance)
	local m, cf = totem(parent, "WhatsNew", Vector3.new(-12.5, 0, -21.5), Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z))
	text(m, cf * CFrame.new(0, 11.2, -0.05), 5.6, 1.3, "WHAT'S NEW", BRASS:Lerp(WHITE, 0.25))
	Parts.block(m, cf * CFrame.new(0, 10.35, -0.02), Vector3.new(3, 0.08, 0.06), deco(BRASS, "Rule"))
	for i, line in NEWS do
		local y = 10.1 - i * 2.05
		Parts.ball(m, (cf * CFrame.new(-2.65, y + 0.3, -0.06)).Position, 0.22, deco(BRASS, "Bullet"))
		local t = text(m, cf * CFrame.new(0.25, y, -0.06), 5.1, 1.7, line, WHITE, nil, false, Config.FontBody)
		local label = t:FindFirstChildWhichIsA("SurfaceGui") and (t:FindFirstChildWhichIsA("SurfaceGui") :: SurfaceGui):FindFirstChildWhichIsA("TextLabel")
		if label then
			label.TextWrapped = true
			label.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
end

-- Stations ---------------------------------------------------------------------
-- A walnut-fin feature wall with a brass-lettered header, a recessed screen and a
-- two-tier marble dais. Station frame F: on the floor at STATION_R on the diagonal,
-- LookVector toward the centre (local -Z = toward the visitor, +X = visitor's left).

local STATION_W = 20

local function stationShell(parent: Instance, deg: number, title: string, rng: Random): (Model, CFrame)
	local m = Parts.model(parent, title:gsub("%s", "") .. "Station")
	local F = CFrame.lookAt(polar(STATION_R, deg, 0), Vector3.zero)
	local w = STATION_W
	-- Dais.
	Parts.roundedBox(m, F * CFrame.new(0, 0.2, -1), Vector3.new(w, 0.4, 9.4), 1.2, solid(MARBLE, "Dais"))
	Parts.block(m, F * CFrame.new(0, 0.41, -5.62), Vector3.new(w - 2.4, 0.04, 0.16), deco(BRASS, "DaisInlay"))
	Parts.roundedBox(m, F * CFrame.new(0, 0.6, 0.7), Vector3.new(w - 3, 0.4, 5.6), 0.9, solid(WALNUT, "DaisUpper"))
	-- Feature wall: dark backing, walnut fins, brass reveals, a lit valance.
	Parts.block(m, F * CFrame.new(0, 6.8, 3.6), Vector3.new(w, 13.6, 0.6), solid(WALNUT_DARK, "Backdrop"))
	local fins = math.floor(w / 0.95)
	for i = 0, fins - 1 do
		local x = -w / 2 + 0.475 + i * (w / fins)
		Parts.block(m, F * CFrame.new(x, 6.8, 3.05), Vector3.new(0.42, 12.6, 0.5), solid(WALNUT, "Fin"))
	end
	Parts.block(m, F * CFrame.new(0, 0.5, 3.0), Vector3.new(w, 0.12, 0.7), deco(BRASS, "Reveal"))
	local valance = Parts.block(m, F * CFrame.new(0, 13.4, 2.7), Vector3.new(w + 0.6, 0.8, 1.6), solid(STEEL, "Valance"))
	Parts.light(valance, LAMP, 16, 0.9, "Surface")
	Parts.block(m, F * CFrame.new(0, 12.98, 2.6), Vector3.new(w - 0.6, 0.06, 1.2), lamp())
	-- Header with brass lettering.
	Parts.block(m, F * CFrame.new(0, 11.95, 2.55), Vector3.new(13, 1.9, 0.3), solid(WALNUT_DARK, "Header"))
	text(m, F * CFrame.new(0, 11.95, 2.33), 12, 1.5, title, BRASS:Lerp(WHITE, 0.25))
	-- Planters either side.
	for _, s in { -1, 1 } do
		LobbyKit.planter(m, (F * CFrame.new(s * (w / 2 + 1.6), 0, 1)).Position, KIT, rng, 7)
	end
	return m, F
end

-- Counter with labelled push-buttons on top (F-local position). `buttons` from the
-- visitor's left to right; returns the button parts.
local function counter(parent: Instance, cf: CFrame, buttons: { { Name: string, Label: string, Color: Color3 } }): { BasePart }
	local m = Parts.model(parent, "Console")
	local w = 3.2 * #buttons + 0.8
	Parts.roundedBox(m, cf * CFrame.new(0, 1.55, 0), Vector3.new(w, 3.1, 2.2), 0.4, solid(WALNUT, "Body"))
	Parts.roundedBox(m, cf * CFrame.new(0, 3.2, 0), Vector3.new(w + 0.4, 0.2, 2.6), 0.5, solid(QUARTZ, "Top"))
	Parts.block(m, cf * CFrame.new(0, 0.18, -0.95), Vector3.new(w - 0.4, 0.36, 0.4), solid(STEEL, "Kick"))
	Parts.block(m, cf * CFrame.new(0, 2.6, -1.12), Vector3.new(w - 0.6, 0.1, 0.06), deco(BRASS, "Inlay"))
	local out: { BasePart } = {}
	for i, b in buttons do
		-- cf's +X is the visitor's left (the visitor faces the counter's front).
		local bx = ((#buttons + 1) / 2 - i) * 3.2
		Parts.cylinder(m, cf * CFrame.new(bx, 3.33, 0), 0.06, 2.2, deco(BRASS, "ButtonRing"))
		local part = Parts.cylinder(m, cf * CFrame.new(bx, 3.5, 0), 0.4, 1.8, { Name = b.Name, Color = b.Color, Material = M.SmoothPlastic, Reflectance = 0.05 })
		table.insert(out, part)
		text(m, cf * CFrame.new(bx, 1.75, -1.16), 2.9, 0.9, b.Label, BRASS:Lerp(WHITE, 0.4))
	end
	return out
end

local function buildLocker(parent: Instance, rng: Random): LobbyTypes.LockerStation
	local m, F = stationShell(parent, 45, "LOCKER", rng)
	local scr = screen(m, "LockerScreen", F * CFrame.new(0, 6.4, 2.5), 14, 8)
	local buttons = counter(m, F * CFrame.new(1.6, 0.4, -3.6), {
		{ Name = "LockerPrev", Label = "◀ PREV", Color = QUARTZ },
		{ Name = "LockerEquip", Label = "EQUIP", Color = BRASS },
		{ Name = "LockerNext", Label = "NEXT ▶", Color = QUARTZ },
	})
	local ped = roundPedestal(m, "LockerPedestal", (F * CFrame.new(-6.4, 0.4, -3.4)).Position, BRASS, QUARTZ, 2.2)
	return { Pedestal = ped, Screen = scr, Prev = buttons[1], Equip = buttons[2], Next = buttons[3] }
end

local function buildUpgrades(parent: Instance, rng: Random): LobbyTypes.UpgradeStation
	local m, F = stationShell(parent, 225, "BALL UPGRADES", rng)
	local scr = screen(m, "UpgradeScreen", F * CFrame.new(0, 6.6, 2.5), 12, 7)
	local b = counter(m, F * CFrame.new(0, 0.4, -3.6), {
		{ Name = "Power", Label = "POWER", Color = C.North },
		{ Name = "Control", Label = "CONTROL", Color = C.West },
		{ Name = "Bounce", Label = "BOUNCE", Color = C.South },
	})
	return { Screen = scr, Buttons = { Power = b[1], Control = b[2], Bounce = b[3] } }
end

local function buildCreator(parent: Instance, rng: Random): LobbyTypes.CreatorStation
	local m, F = stationShell(parent, 315, "CREATOR CODE", rng)
	local scr = screen(m, "CreatorScreen", F * CFrame.new(0, 6.6, 2.5), 11, 6.5)
	LobbyKit.armchair(m, F * CFrame.new(-4.5, 0.4, -3) * CFrame.Angles(0, PI - 0.35, 0), KIT)
	LobbyKit.armchair(m, F * CFrame.new(4.5, 0.4, -3) * CFrame.Angles(0, PI + 0.35, 0), KIT)
	return { Screen = scr }
end

local function buildDaily(parent: Instance, rng: Random): (BasePart, BasePart)
	local m, F = stationShell(parent, 135, "DAILY REWARDS", rng)
	local scr = screen(m, "DailyScreen", F * CFrame.new(0, 6.5, 2.5), 13, 7.5)
	-- Claim button on a turned marble plinth in front of the wall.
	local base = (F * CFrame.new(0, 0.4, -3.4)).Position
	LobbyKit.lathe(m, base, {
		Vector2.new(1.5, 0),
		Vector2.new(1.25, 0.4),
		Vector2.new(0.95, 1.2),
		Vector2.new(1.0, 2.4),
		Vector2.new(1.45, 2.85),
	}, 20, 0.25, deco(MARBLE, "ButtonPlinth"))
	Parts.cylinder(m, CFrame.new(base + UP * 1.45), 2.9, 2, solid(MARBLE, "ButtonCore"))
	Parts.cylinder(m, CFrame.new(base + UP * 2.95), 0.12, 2.9, deco(BRASS, "ButtonRing"))
	local button = Parts.cylinder(m, CFrame.new(base + UP * 3.15), 0.5, 2.1, solid(GOLD, "DailyButton"))
	text(m, CFrame.lookAt(base + UP * 1.6, base + UP * 1.6 + F.LookVector) * CFrame.new(0, 0, -1.02), 1.8, 0.8, "CLAIM", BRASS:Lerp(WHITE, 0.4))
	return scr, button
end

-- Painted outline hugging a w x h face centred on cf.
local function outline(parent: Instance, cf: CFrame, w: number, h: number, color: Color3)
	local e = 0.12
	Parts.block(parent, cf * CFrame.new(0, h / 2 + e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), deco(color, "Edge"))
	Parts.block(parent, cf * CFrame.new(0, -h / 2 - e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), deco(color, "Edge"))
	Parts.block(parent, cf * CFrame.new(w / 2 + e / 2, 0, 0), Vector3.new(e, h, 0.2), deco(color, "Edge"))
	Parts.block(parent, cf * CFrame.new(-w / 2 - e / 2, 0, 0), Vector3.new(e, h, 0.2), deco(color, "Edge"))
end

-- Gradient hero panel (plain block so the gradient sits on its Front face).
local function heroPanel(parent: Instance, cf: CFrame, w: number, h: number, top: Color3, bottom: Color3)
	local p = Parts.block(parent, cf, Vector3.new(w, h, 0.1), deco(bottom, "HeroPanel"))
	Parts.gradientFace(p, Enum.NormalId.Front, top, bottom, 90)
end

-- Atrium ----------------------------------------------------------------------------

local function buildAtrium(parent: Instance, rng: Random)
	local hub = Parts.model(parent, "Hub")
	buildFloor(hub)
	buildWall(hub)
	buildCeiling(hub)
	for _, quad in QUADS do
		buildDoorway(hub, quad)
		for _, s in { -1, 1 } do
			LobbyKit.planter(hub, at(quad.Frame, s * 16.5, 0, LOBBY_R - 3.4), KIT, rng, 7.5)
		end
	end
	for q = 0, 3 do
		for _, bay in BAY_DEGS do
			buildLounge(hub, q * 90 + bay)
		end
	end
	Fountain.build(hub, Vector3.zero, {
		Marble = mat(MARBLE, M.Marble),
		MarbleDark = mat(MARBLE_DARK, M.Marble),
		Brass = mat(BRASS, M.Metal),
		Mosaic = mat(MOSAIC, M.Slate),
		Water = {
			Color = WATER,
			Material = M.Glass,
			Transparency = 0.32,
			Reflectance = 0.32,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		},
	})
	-- Invisible collider round the fountain so nobody wades through the water.
	Parts.cylinder(hub, CFrame.new(0, 5, 0), 10, 31.2, { Name = "FountainCollider", Transparency = 1, CastShadow = false })
	buildNews(hub)
end

-- Walkways -----------------------------------------------------------------------
-- Glass link corridor from each atrium doorway to its wing: marble floor with the
-- walnut runner, steel-framed glass sides and an oak ceiling.

local function buildHall(parent: Instance, quad: Quad)
	local m = Parts.model(parent, "Hall" .. quad.Key)
	local q = quad.Frame
	local d0 = LOBBY_R + WALL_T - 0.2
	local d1 = NEAR_WALL - 2 -- outside face of the wing's entrance wall
	local len = d1 - d0
	local mid = (d0 + d1) / 2
	local x = HALL_HALF + 0.6
	Parts.block(m, along(q, 0, -0.5, (LOBBY_R + NEAR_WALL) / 2), Vector3.new(2 * x + 1, 1, NEAR_WALL - LOBBY_R + 0.4), solid(MARBLE, "Floor"))
	Parts.block(m, along(q, 0, 0.02, (LOBBY_R + NEAR_WALL) / 2), Vector3.new(7, 0.06, NEAR_WALL - LOBBY_R + 0.4), deco(WALNUT, "Runner"))
	local h = ARCH_H + 1
	for _, s in { -1, 1 } do
		Parts.block(m, along(q, s * x, 0.5, mid), Vector3.new(0.8, 1, len), solid(WALNUT_DARK, "Sill"))
		Parts.block(m, along(q, s * x, (1 + h) / 2, mid), Vector3.new(0.3, h - 1, len), glassProps("Glass"))
		for _, d in { d0 + 0.4, mid, d1 - 0.4 } do
			Parts.block(m, along(q, s * x, h / 2, d), Vector3.new(0.6, h, 0.6), solid(STEEL, "Post"))
		end
		Parts.block(m, along(q, s * x, h, mid), Vector3.new(0.8, 0.6, len), solid(STEEL, "Rail"))
	end
	Parts.block(m, along(q, 0, h + 0.5, mid), Vector3.new(2 * x + 1.6, 1, len), solid(OAK, "Ceiling"))
	Parts.block(m, along(q, 0, h + 1.2, mid), Vector3.new(2 * x + 2.4, 0.5, len + 0.6), solid(STEEL, "Roof"))
	local strip = Parts.block(m, along(q, 0, h - 0.05, mid), Vector3.new(2, 0.1, len - 1), lamp())
	Parts.light(strip, LAMP, 14, 0.7, "Surface")
end

-- Wing shell ------------------------------------------------------------------
-- Room frame R: centre of the room floor, LookVector away from the lobby.
-- Room-local coordinates (x, y, u): u = +ROOM_D is the back wall, -ROOM_D the entrance.

type FloorStyle = "Oak" | "Marble" | "Walnut"

local function trimRun(m: Instance, R: CFrame, x0: number, u0: number, x1: number, u1: number, nx: number, nu: number, accent: Color3)
	local function run(off: number, y: number, h: number, depth: number, props: Props)
		Parts.beam(m, at(R, x0 + nx * off, y, u0 + nu * off), at(R, x1 + nx * off, y, u1 + nu * off), depth, h, props)
	end
	run(0.25, 0.3, 0.6, 0.5, solid(WALNUT_DARK, "Skirting"))
	run(0.15, 2.3, 3.4, 0.3, solid(WALNUT, "Wainscot"))
	run(0.33, 4.05, 0.14, 0.3, deco(BRASS, "Rail"))
	run(0.33, 0.85, 0.08, 0.3, deco(accent, "Accent"))
	run(0.3, ROOM_H - 0.35, 0.7, 0.6, solid(WALNUT, "Crown"))
end

-- Modern window on an outside wall (cf = glass centre, LookVector out): slim steel frame, two panes.
local function window(m: Instance, cf: CFrame, w: number, h: number)
	Parts.block(m, cf * CFrame.new(0, 0, 0.1), Vector3.new(w + 0.6, h + 0.6, 0.3), solid(STEEL, "WindowFrame"))
	Parts.block(m, cf, Vector3.new(w, h, 0.1), { Name = "Glass", Color = hex("#33444F"), Material = M.Glass, Reflectance = 0.35, CanCollide = false, CanQuery = false })
	Parts.block(m, cf * CFrame.new(0, 0, -0.05), Vector3.new(0.22, h, 0.12), deco(STEEL, "Mullion"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 - 0.45, -0.15), Vector3.new(w + 1, 0.3, 0.6), solid(STONE, "Sill"))
end

-- Outside of a wing: limestone base course, vertical walnut cladding bays between
-- black-steel posts, tall windows and a flat roof with a deep steel fascia.
local function buildExterior(m: Instance, R: CFrame, top: number)
	local W, D = ROOM_W, ROOM_D
	local ox, ou = W + 2, D + 2 -- outside faces
	local base = solid(STONE, "BaseCourse")
	Parts.block(m, along(R, 0, 1.75, ou + 0.25), Vector3.new(2 * ox + 1, 3.5, 0.5), base)
	for _, s in { -1, 1 } do
		Parts.block(m, along(R, s * (ox + 0.25), 1.75, 0), Vector3.new(0.5, 3.5, 2 * ou + 1), base)
		local len = ox - HALL_HALF
		Parts.block(m, along(R, s * (HALL_HALF + len / 2), 1.75, -ou - 0.25), Vector3.new(len + 0.5, 3.5, 0.5), base)
	end
	-- Walnut cladding above the base course (one board per bay) and steel posts.
	local clad = solid(WALNUT, "Cladding")
	local h = top - 3.5
	local y = 3.5 + h / 2
	Parts.block(m, along(R, 0, y, ou + 0.15), Vector3.new(2 * ox, h, 0.3), clad)
	for _, s in { -1, 1 } do
		Parts.block(m, along(R, s * (ox + 0.15), y, 0), Vector3.new(0.3, h, 2 * ou), clad)
		local len = ox - HALL_HALF
		Parts.block(m, along(R, s * (HALL_HALF + len / 2), y, -ou - 0.15), Vector3.new(len, h, 0.3), clad)
	end
	for _, x in { -ox, -ox / 2, 0, ox / 2, ox } do
		Parts.block(m, along(R, x, top / 2, ou + 0.35), Vector3.new(0.8, top, 0.5), solid(STEEL, "Post"))
	end
	for _, s in { -1, 1 } do
		for _, u in { -ou, -ou / 2, 0, ou / 2, ou } do
			Parts.block(m, along(R, s * (ox + 0.35), top / 2, u), Vector3.new(0.5, top, 0.8), solid(STEEL, "Post"))
		end
		Parts.block(m, along(R, s * (HALL_HALF + 0.4), top / 2, -ou - 0.35), Vector3.new(0.8, top, 0.5), solid(STEEL, "Post"))
	end
	for _, x in { -34, -22, 22, 34 } do
		window(m, along(R, x, 10.5, -ou - 0.35, TO_ENTRANCE), 5, 11)
	end
	for _, s in { -1, 1 } do
		for _, u in { -22, -11, 0, 11, 22 } do
			window(m, along(R, s * (ox + 0.35), 10.5, u, if s > 0 then TO_MINUS_X else TO_PLUS_X), 5, 11)
		end
	end
	for _, x in { -33, -11, 11, 33 } do
		window(m, along(R, x, 10.5, ou + 0.35, TO_BACK), 5, 11)
	end
	-- Flat roof with a deep overhang and a steel fascia band.
	local over = 3
	Parts.block(m, along(R, 0, top + 0.6, 0), Vector3.new(2 * (ox + over), 1.2, 2 * (ou + over)), solid(STONE, "Roof"))
	Parts.block(m, along(R, 0, top + 0.6, ou + over), Vector3.new(2 * (ox + over) + 0.6, 1.8, 0.6), solid(STEEL, "Fascia"))
	Parts.block(m, along(R, 0, top + 0.6, -ou - over), Vector3.new(2 * (ox + over) + 0.6, 1.8, 0.6), solid(STEEL, "Fascia"))
	for _, s in { -1, 1 } do
		Parts.block(m, along(R, s * (ox + over), top + 0.6, 0), Vector3.new(0.6, 1.8, 2 * (ou + over)), solid(STEEL, "Fascia"))
		-- Ridge skylight strip on each half of the roof.
		Parts.block(m, along(R, s * W / 2, top + 1.35, 0), Vector3.new(6, 0.5, 2 * D - 8), solid(STEEL, "SkylightCurb"))
		Parts.block(m, along(R, s * W / 2, top + 1.7, 0), Vector3.new(5.2, 0.3, 2 * D - 8.8), glassProps("Skylight"))
		for k = -3, 3 do
			Parts.block(m, along(R, s * W / 2, top + 1.9, k * (D - 4) / 3.5), Vector3.new(5.4, 0.2, 0.3), solid(STEEL, "SkylightBar"))
		end
	end
end

local function buildRoomShell(parent: Instance, quad: Quad, floorStyle: FloorStyle): (Model, CFrame)
	local m = Parts.model(parent, quad.Key .. "Room")
	local R = roomFrame(quad)
	local accent = quad.Color
	local W, D, H = ROOM_W, ROOM_D, ROOM_H
	local shell = Parts.model(m, "Shell")
	-- Floor with a walnut border band and brass inlay.
	local floorColor = if floorStyle == "Marble" then MARBLE elseif floorStyle == "Walnut" then WALNUT_MID else FLOOR_A
	Parts.block(shell, along(R, 0, -0.5, 1), Vector3.new(2 * W + 4, 1, 2 * D + 2), solid(floorColor, "Floor"))
	for _, s in { -1, 1 } do
		Parts.block(shell, along(R, s * (W - 1.2), 0.02, 0), Vector3.new(2.4, 0.06, 2 * D), deco(WALNUT_DARK, "Border"))
		Parts.block(shell, along(R, 0, 0.02, s * (D - 1.2)), Vector3.new(2 * W, 0.06, 2.4), deco(WALNUT_DARK, "Border"))
		Parts.block(shell, along(R, s * (W - 2.5), 0.03, 0), Vector3.new(0.2, 0.06, 2 * D - 4.8), deco(BRASS, "Inlay"))
		Parts.block(shell, along(R, 0, 0.03, s * (D - 2.5)), Vector3.new(2 * W - 4.8, 0.06, 0.2), deco(BRASS, "Inlay"))
	end
	if floorStyle == "Marble" then
		for i = -3, 3 do
			Parts.block(shell, along(R, i * 11, 0.01, 0), Vector3.new(0.12, 0.04, 2 * D - 5), deco(MARBLE_DARK, "Joint"))
		end
	end
	Parts.block(shell, along(R, 0, 0.02, -D + 1.2), Vector3.new(24, 0.06, 2.4), deco(BRASS, "Threshold"))
	-- Walls and ceiling (2 thick, outside the interior box).
	local top = H + 1.5
	local yc = (top - 1) / 2
	local wallH = top + 1
	Parts.block(shell, along(R, 0, yc, D + 1), Vector3.new(2 * W + 4, wallH, 2), solid(PLASTER, "BackWall"))
	for _, s in { -1, 1 } do
		Parts.block(shell, along(R, s * (W + 1), yc, 0), Vector3.new(2, wallH, 2 * D + 4), solid(PLASTER, "SideWall"))
		local len = W + 2 - HALL_HALF
		Parts.block(shell, along(R, s * (HALL_HALF + len / 2), yc, -D - 1), Vector3.new(len, wallH, 2), solid(PLASTER, "FrontWall"))
	end
	Parts.block(shell, along(R, 0, (ARCH_H + 0.5 + top) / 2, -D - 1), Vector3.new(HALL_HALF * 2 + 0.2, top - ARCH_H - 0.5, 2), solid(PLASTER, "DoorHeader"))
	Parts.block(shell, along(R, 0, H + 0.75, 0), Vector3.new(2 * W + 4, 1.5, 2 * D + 4), solid(OAK, "Ceiling"))
	-- Interior trims.
	trimRun(shell, R, -W, D, W, D, 0, -1, accent)
	trimRun(shell, R, -W, -D, -W, D, 1, 0, accent)
	trimRun(shell, R, W, -D, W, D, -1, 0, accent)
	trimRun(shell, R, -W, -D, -HALL_HALF - 1.5, -D, 0, 1, accent)
	trimRun(shell, R, HALL_HALF + 1.5, -D, W, -D, 0, 1, accent)
	-- Steel door portal on the room side.
	for _, s in { -1, 1 } do
		Parts.block(shell, along(R, s * 12.6, ARCH_H / 2, -D + 0.3), Vector3.new(1.2, ARCH_H, 1.4), solid(STEEL, "Jamb"))
	end
	Parts.block(shell, along(R, 0, ARCH_H + 0.6, -D + 0.3), Vector3.new(26.4, 1.2, 1.4), solid(STEEL, "Head"))
	-- Black-steel pillars (corners and side walls) carrying I-beam crossbeams under the oak ceiling.
	local pillar = solid(STEEL, "Pillar")
	for _, sx in { -1, 1 } do
		for _, u in { -(D - 1.2), D - 1.2 } do
			LobbyKit.column(shell, at(R, sx * (W - 1.2), 0, u), H, 1.4, pillar)
		end
		LobbyKit.column(shell, at(R, sx * (HALL_HALF + 3.5), 0, -(D - 1.2)), H, 1.4, pillar)
	end
	for _, u in { -(D - 8), -8, 8, D - 8 } do
		LobbyKit.ibeam(shell, at(R, -W, H - 0.7, u), at(R, W, H - 0.7, u), 1.4, 0.8, solid(STEEL, "Beam"))
	end
	LobbyKit.ibeam(shell, at(R, 0, H - 0.75, -D), at(R, 0, H - 0.75, D), 1.2, 0.7, solid(STEEL, "Beam"))
	-- Brass pendants between the beams.
	for _, x in { -22, 22 } do
		for _, u in { -16, 0, 16 } do
			LobbyKit.pendant(shell, at(R, x, 0, u), H, 4, KIT, 30, u == 0 or (x > 0) == (u > 0))
		end
	end
	buildExterior(shell, R, top)
	return m, R
end
-- NORTH: Matchmaking & voting --------------------------------------------------

local function buildNorth(room: Model, R: CFrame)
	local m = Parts.model(room, "Matchmaking")
	local accent = C.North
	local portals: { [string]: LobbyTypes.Portal } = {}
	for i, key in Config.ModeOrder do
		local col = Config.Modes[key].Color
		local x = (i - 2) * 22
		local p = Parts.model(m, "Portal" .. key)
		-- Backdrop on the back wall.
		roundPanel(p, along(R, x, 10.2, ROOM_D - 0.25, TO_ENTRANCE), 19.5, 15.6, 0.5, 1.2, solid(WALNUT_DARK, "Backdrop"))
		heroPanel(p, along(R, x, 10.2, ROOM_D - 0.55, TO_ENTRANCE), 17.5, 13.6, col:Lerp(WALNUT_DARK, 0.55), WALNUT_DARK)
		-- Plinth + hoop frame + force-field film.
		Parts.trimmedSlab(p, along(R, x, 0.4, 29, TO_ENTRANCE), Vector3.new(19, 0.8, 4.6), 1.2, WOOD, col)
		local hc = along(R, x, 8.6, 29, TO_ENTRANCE)
		Parts.hoop(p, hc, 7.2, 1.4, 2.2, 20, solid(WOOD, "Frame"))
		Parts.hoop(p, hc, 6.35, 0.3, 2.4, 20, deco(col, "FrameGlow"))
		Parts.hoop(p, hc * CFrame.new(0, 0, -1.15), 7.2, 0.35, 0.15, 20, deco(col, "FrameEdge"))
		local film = Parts.cylinder(p, hc * CFrame.Angles(PI / 2, 0, 0), 0.2, 12.6, {
			Name = "Film",
			Color = col,
			Material = Enum.Material.ForceField,
			Transparency = 0.1,
			CanCollide = false,
			CanQuery = false,
		})
		Parts.light(film, col, 18, 1.4)
		-- Status screen above the portal, bracketed to the wall.
		local sign = screen(p, "Sign", along(R, x, 17.4, 29, TO_ENTRANCE), 12, 4, col)
		for _, s in { -1, 1 } do
			Parts.block(p, along(R, x + s * 4, 17.4, 30.5), Vector3.new(0.6, 0.6, 1.8), solid(STEEL, "Bracket"))
		end
		-- Queue bubble (bottom on the floor) with a floor ring.
		local bubble = Parts.ball(p, at(R, x, 7, 19), 14, {
			Name = "Bubble",
			Color = col,
			Material = Enum.Material.ForceField,
			Transparency = 0.75,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		bubble:SetAttribute("Radius", 7)
		Parts.disc(p, at(R, x, 0.02, 19), 14.8, 0.08, deco(col, "BubbleRing"))
		Parts.disc(p, at(R, x, 0.04, 19), 13.6, 0.08, deco(WOOD, "BubbleFloor"))
		portals[key] = { Bubble = bubble, Sign = sign }
	end

	-- Voting enclave on the west wall: three holographic screens + floor pads.
	local vm = Parts.model(m, "Voting")
	local votes: { LobbyTypes.VoteSign } = {}
	for i = 1, 3 do
		local u = (i - 2) * 12
		local cf = along(R, -42.2, 6.8, u, TO_PLUS_X)
		Parts.trimmedSlab(vm, along(R, -42, 0.5, u, TO_PLUS_X), Vector3.new(7, 1, 2.4), 0.8, WOOD, accent)
		for _, s in { -1, 1 } do
			Parts.rod(vm, (cf * CFrame.new(s * 3, -5.8, 0.3)).Position, (cf * CFrame.new(s * 3, -3.9, 0.3)).Position, 0.35, deco(accent, "Beam"))
		end
		Parts.block(vm, cf * CFrame.new(0, 0, 0.3), Vector3.new(11, 8, 0.3), {
			Name = "HoloFrame",
			Color = STEEL,
			Transparency = 0.35,
			CanCollide = false,
		})
		outline(vm, cf, 10, 7, accent)
		local disp = Parts.block(vm, cf, Vector3.new(10, 7, 0.2), {
			Name = "VoteDisplay" .. i,
			Color = SCREEN,
			Transparency = 0.1,
			CanCollide = false,
		})
		local p = pad(vm, "VotePad" .. i, at(R, -35, 0, u), 8, accent)
		local entry: LobbyTypes.VoteSign = { Display = disp, Pad = p }
		table.insert(votes, entry)
	end
	local header = screen(vm, "VoteHeader", along(R, -43.3, 13.8, 0, TO_PLUS_X), 30, 4.5, accent)
	titlePlate(vm, along(R, -43, 17.6, 0, TO_PLUS_X), 16, 2.6, "MAP VOTE", accent)

	-- Invite Friends kiosk on the east side, plus a small lounge.
	local km = Parts.model(m, "Invite")
	local kcf = along(R, 38, 0, 0, TO_MINUS_X)
	Parts.trimmedSlab(km, kcf * CFrame.new(0, 0.3, 0), Vector3.new(6, 0.6, 3.6), 0.9, WOOD, accent)
	Parts.roundedBox(km, kcf * CFrame.new(0, 2.4, 0.3), Vector3.new(4, 3.6, 2), 0.6, solid(WALL, "Body"))
	local kiosk = screen(km, "InviteKiosk", kcf * CFrame.new(0, 6.3, 0.3) * CFrame.Angles(math.rad(-12), 0, 0), 5, 3.4, accent)
	titlePlate(km, kcf * CFrame.new(0, 9.6, 0.6), 7, 1.6, "INVITE FRIENDS", accent)
	for _, u in { -16, 16 } do
		bench(m, along(R, 37, 0, u, TO_MINUS_X), accent)
	end

	return {
		Portals = portals,
		VoteSigns = votes,
		VoteHeader = header,
		InviteKiosk = kiosk,
	}
end

-- EAST: Mega Shop ------------------------------------------------------------------

local function commas(n: number): string
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return s
end

local function buildEast(room: Model, R: CFrame)
	local m = Parts.model(room, "Shop")
	local accent = C.East

	-- 12 coin-shop skin pedestals in a U around the room centre, open toward the entrance.
	-- 12 coin-shop pedestals in two straight rows either side of a carpet runner.
	local sm = Parts.model(m, "SkinPedestals")
	LobbyKit.rug(sm, along(R, 0, 0, -6), 8, 36, mat(RUG, M.Carpet), mat(RUG_BORDER, M.Carpet))
	local skins: { BasePart } = {}
	for i = 1, 12 do
		local side = if i <= 6 then -1 else 1
		local k = (i - 1) % 6
		table.insert(skins, roundPedestal(sm, "SkinPedestal" .. i, at(R, side * 8.5, 0, -21 + k * 6), accent))
	end

	-- Mythic shrine: isolated alcove in the middle of the back wall.
	local am = Parts.model(m, "MythicShrine")
	for _, s in { -1, 1 } do
		Parts.roundedBox(am, along(R, s * 11, 9.5, 26.5), Vector3.new(1.5, 19, 11), 0.75, solid(WALNUT, "Partition"))
		Parts.block(am, along(R, s * 11, 19.05, 26.75), Vector3.new(0.5, 0.1, 10.5), deco(BRASS, "PartitionInlay"))
		local pillar = Parts.cylinder(am, along(R, s * 11, 9.5, 21), 19, 1.7, solid(BRASS, "Pillar"))
		Parts.disc(am, at(R, s * 11, 19.3, 21), 2.3, 0.6, solid(STEEL, "PillarCap"))
		Parts.disc(am, at(R, s * 11, 0.3, 21), 2.6, 0.6, solid(STEEL, "PillarFoot"))
		Parts.light(pillar, MYTHIC, 16, 1.5)
	end
	heroPanel(am, along(R, 0, 9.6, ROOM_D - 0.55, TO_ENTRANCE), 20.4, 15, MYTHIC:Lerp(WALNUT_DARK, 0.5), WALNUT_DARK)
	local counter = screen(am, "MythicCounter", along(R, 0, 15.6, ROOM_D - 0.8, TO_ENTRANCE), 16, 4.6, GOLD)
	local odds = screen(am, "MythicOdds", along(R, 0, 9.4, ROOM_D - 0.8, TO_ENTRANCE), 10, 5.4, MYTHIC)
	local base = at(R, 0, 0, 26)
	local up = Vector3.yAxis
	Parts.disc(am, base + up * 0.25, 11.4, 0.3, deco(GOLD, "StepGlow"))
	Parts.disc(am, base + up * 0.3, 11, 0.6, solid(WOOD_DARK, "Step"))
	Parts.disc(am, base + up * 0.8, 8.3, 0.2, deco(MYTHIC, "StepGlow"))
	Parts.disc(am, base + up * 0.9, 8, 0.6, solid(hex("#8E1B35"), "Step"))
	Parts.disc(am, base + up * 2.4, 4.6, 2.4, solid(WOOD_DARK, "Column"))
	Parts.disc(am, base + up * 2.4, 4.8, 0.3, deco(GOLD, "ColumnGlow"))
	local mythic: BasePart = Parts.disc(am, base + up * 3.85, 5.4, 0.5, solid(GOLD, "MythicPedestal"))
	display(mythic, base + up * 7.1)
	Parts.light(mythic, GOLD, 18, 1.6)

	-- Four category crates flanking the shrine, odds boards behind them.
	local cm = Parts.model(m, "Crates")
	local cratePeds: { [string]: BasePart } = {}
	local crateScreens: { [string]: BasePart } = {}
	local xs = { -33, -21, 21, 33 }
	for i, id in Crates.ShopOrder do
		local x = xs[i]
		if x then
			local crate = Crates.get(id)
			local col = if crate then crate.Color else accent
			Parts.trimmedSlab(cm, along(R, x, 0.3, 25, TO_ENTRANCE), Vector3.new(5.4, 0.6, 5.4), 1.2, WOOD_DARK, col)
			cratePeds[id] = roundPedestal(cm, "Crate" .. id, at(R, x, 0.6, 25), col, WOOD)
			crateScreens[id] = screen(cm, "CrateScreen" .. id, along(R, x, 11, ROOM_D - 0.8, TO_ENTRANCE), 9, 7, col)
			titlePlate(cm, along(R, x, 16.2, ROOM_D - 1, TO_ENTRANCE), 9.5, 1.8, string.upper(if crate then crate.Name else id), col)
		end
	end

	-- Game pass pedestals along the north (local -x) wall.
	local pm = Parts.model(m, "Passes")
	local passPeds: { [string]: BasePart } = {}
	for i, key in Config.GamePassOrder do
		local cf = along(R, -38, 0, -14 + (i - 1) * 9, TO_PLUS_X)
		Parts.trimmedSlab(pm, cf * CFrame.new(0, 0.3, 0), Vector3.new(5, 0.6, 5), 1, WOOD_DARK, GOLD)
		Parts.roundedBox(pm, cf * CFrame.new(0, 1.9, 0), Vector3.new(3.6, 2.6, 3.6), 0.8, solid(WALL, "Column"))
		local cap = Parts.roundedBox(pm, cf * CFrame.new(0, 3.4, 0), Vector3.new(4.2, 0.4, 4.2), 0.9, solid(GOLD, "PassPedestal"))
		cap.Name = "Pass" .. key
		display(cap, (cf * CFrame.new(0, 6.1, 0)).Position)
		passPeds[key] = cap
	end
	titlePlate(pm, along(R, -ROOM_W + 1, 13, -0.5, TO_PLUS_X), 26, 3.4, "★ GAME PASSES", GOLD)

	-- Coin pack kiosks along the south (local +x) wall.
	local km = Parts.model(m, "CoinPacks")
	local coinPads: { [string]: BasePart } = {}
	for i = 1, 4 do
		local key = "Coins" .. i
		local cf = along(R, 38.5, 0, -14 + (i - 1) * 9, TO_MINUS_X)
		Parts.trimmedSlab(km, cf * CFrame.new(0, 0.3, 0), Vector3.new(5, 0.6, 4.4), 1, WOOD_DARK, GOLD)
		local body = Parts.roundedBox(km, cf * CFrame.new(0, 2.1, 0), Vector3.new(4, 3, 3.4), 0.7, solid(WALL, key))
		body.Name = key
		for c = 1, i + 1 do
			local pos = (cf * CFrame.new(((c % 2) - 0.5) * 0.3, 3.6 + (c - 0.5) * 0.36, 0)).Position
			Parts.disc(km, pos, 2.2, 0.34, solid(GOLD, "Coin"))
		end
		local product: { Name: string, Coins: number? }? = (Config.DevProducts :: any)[key]
		local label = if product then string.upper(product.Name) .. "\n" .. commas(product.Coins or 0) .. " COINS" else key
		text(km, cf * CFrame.new(0, 2.2, -1.76), 3.4, 2.2, label, WOOD_DARK, nil, false)
		coinPads[key] = body
	end
	titlePlate(km, along(R, ROOM_W - 1, 13, -0.5, TO_MINUS_X), 26, 3.4, "COIN PACKS", GOLD)

	return {
		SkinPedestals = skins,
		CratePedestals = cratePeds,
		CrateScreens = crateScreens,
		Mythic = { Pedestal = mythic, Counter = counter, OddsBoard = odds },
		PassPedestals = passPeds,
		CoinPackPads = coinPads,
	}
end

-- SOUTH: Practice range ------------------------------------------------------------

local function buildSouth(room: Model, R: CFrame)
	local m = Parts.model(room, "Practice")
	local accent = C.South
	local count = Config.Practice.Lanes
	local W, L = 9, 48
	local pitch = 10.6
	local u0 = -21 -- lane start (Origin) in room coordinates
	local half = count * pitch / 2
	local lanesModel = Parts.model(m, "Lanes")

	-- Gantry over the lane heads carrying the per-lane screens.
	local gantry = Parts.model(lanesModel, "Gantry")
	for k = 0, count do
		Parts.roundedBox(gantry, along(R, -half + k * pitch, 5.5, u0 - 0.4), Vector3.new(0.9, 11, 0.9), 0.3, solid(WOOD, "Post"))
	end
	Parts.roundedBox(gantry, along(R, 0, 11.4, u0 - 0.4), Vector3.new(2 * half + 1.4, 0.8, 1.4), 0.4, solid(WOOD_DARK, "Beam"))
	local beamGlow = Parts.block(gantry, along(R, 0, 11.1, u0 - 1.15), Vector3.new(2 * half - 1, 0.16, 0.12), deco(accent, "BeamGlow"))
	Parts.light(beamGlow, accent, 16, 0.8)

	local lanes: { LobbyTypes.Lane } = {}
	for i = 1, count do
		local x = -half + (i - 0.5) * pitch
		local lm = Parts.model(lanesModel, "Lane" .. i)
		local origin = along(R, x, 0, u0)
		Parts.block(lm, origin * CFrame.new(0, -0.09, -L / 2), Vector3.new(W, 0.22, L), solid(LANE_GREEN, "Turf"))
		Parts.block(lm, origin * CFrame.new(0, 0.02, -0.2), Vector3.new(W - 0.02, 0.04, 0.3), deco(WHITE, "TeeLine"))
		for _, s in { -1, 1 } do
			Parts.block(lm, origin * CFrame.new(s * (W / 2 + 0.4), 0.6, -L / 2), Vector3.new(0.8, 1.2, L), solid(WHITE, "Rail"))
			Parts.block(lm, origin * CFrame.new(s * (W / 2 + 0.4), 1.26, -L / 2), Vector3.new(0.5, 0.12, L), deco(accent, "RailGlow"))
		end
		Parts.block(lm, origin * CFrame.new(0, 1.5, -(L + 0.5)), Vector3.new(pitch, 3, 1), solid(WOOD, "BackWall"))
		Parts.block(lm, origin * CFrame.new(0, 3.06, -(L + 0.5)), Vector3.new(pitch, 0.12, 0.6), deco(accent, "BackGlow"))
		local start = pad(lm, "StartPad", (origin * CFrame.new(0, 0, 3.5)).Position, 6, accent)
		local scr = screen(lm, "LaneScreen", along(R, x, 9.2, u0 - 0.4, TO_ENTRANCE), 7, 2.6, accent)
		text(lm, along(R, x, 11.45, u0 - 1.16, TO_ENTRANCE), 3, 0.6, "LANE " .. i, WHITE, nil, true, Config.FontBody)
		local lane: LobbyTypes.Lane = {
			Origin = origin,
			Length = L,
			Width = W,
			StartPad = start,
			Props = Parts.folder(lm, "Props"),
			Screen = scr,
		}
		table.insert(lanes, lane)
	end

	-- Rotation sign on the back wall, above the lane ends.
	heroPanel(m, along(R, 0, 13.2, ROOM_D - 0.55, TO_ENTRANCE), 34, 10.4, accent:Lerp(WALNUT_DARK, 0.55), WALNUT_DARK)
	local rotation = screen(m, "RotationSign", along(R, 0, 13.3, ROOM_D - 0.8, TO_ENTRANCE), 28, 8, accent)

	-- Token kiosk on the west (local +x) side.
	local tm = Parts.model(m, "TokenKiosk")
	local tokenScreen = screen(tm, "TokenScreen", along(R, ROOM_W - 0.6, 7.5, 6, TO_MINUS_X), 12, 6, accent)
	titlePlate(tm, along(R, ROOM_W - 1, 12.4, 6, TO_MINUS_X), 12, 1.8, "TOKEN SHOP", accent)
	Parts.trimmedSlab(tm, along(R, 38, 0.3, 6, TO_MINUS_X), Vector3.new(5.4, 0.6, 5.4), 1.2, WOOD_DARK, accent)
	local tokenCrate = roundPedestal(tm, "TokenCrate", at(R, 38, 0.6, 6), accent, WOOD)
	local tokenSkins: { BasePart } = {}
	for i, u in { -8, -2.5, 14.5, 20 } do
		table.insert(tokenSkins, roundPedestal(tm, "TokenSkin" .. i, at(R, 37.5, 0, u), accent))
	end

	-- Replay-tutorial pad near the entrance on the east (local -x) side, plus seating.
	local tut = pad(m, "TutorialPad", at(R, -35, 0, -24), 8, accent)
	titlePlate(m, along(R, -ROOM_W + 1, 7, -24, TO_PLUS_X), 10, 2.4, "REPLAY TUTORIAL", accent)
	local badge = along(R, -ROOM_W + 0.5, 10.6, -24, TO_PLUS_X)
	Parts.cylinder(m, badge * CFrame.Angles(PI / 2, 0, 0), 0.6, 3, solid(WOOD_DARK, "Badge"))
	Parts.cylinder(m, badge * CFrame.new(0, 0, 0.1) * CFrame.Angles(PI / 2, 0, 0), 0.5, 3.4, deco(accent, "BadgeRing"))
	text(m, badge * CFrame.new(0, 0, -0.4), 2.2, 2.2, "?", accent, WOOD_DARK)
	for _, u in { 2, 14 } do
		bench(m, along(R, -38, 0, u, TO_PLUS_X), accent)
	end

	return {
		Lanes = lanes,
		RotationSign = rotation,
		TokenKiosk = { Screen = tokenScreen, CratePedestal = tokenCrate, SkinPedestals = tokenSkins },
		TutorialPad = tut,
	}
end

-- WEST: Leaderboards ------------------------------------------------------------------

-- One leaderboard unit. F: floor point on the wall face, LookVector into the room.
-- A walnut-fin feature wall with the board screen and its console on the left, and a
-- stepped marble podium (the board's exclusive ball) under a spotlight on the right.
local function buildBoard(parent: Instance, F: CFrame, stat: string, medal: Color3, accent: Color3): LobbyTypes.Board
	local m = Parts.model(parent, "Board" .. stat)
	-- vx: viewer's right when facing the wall; dist: distance out from the wall.
	local function v(vx: number, y: number, dist: number): CFrame
		return F * CFrame.new(-vx, y, -dist)
	end
	local w = 30
	Parts.block(m, v(0, 9.6, 0.3), Vector3.new(w, 19.2, 0.6), solid(WALNUT_DARK, "Backdrop"))
	for i = 0, 29 do
		Parts.block(m, v(-w / 2 + 0.5 + i, 9.4, 0.85), Vector3.new(0.42, 17.8, 0.5), solid(WALNUT, "Fin"))
	end
	Parts.block(m, v(0, 0.55, 1.05), Vector3.new(w, 0.12, 0.2), deco(BRASS, "Reveal"))
	local valance = Parts.block(m, v(0, 19.5, 1.2), Vector3.new(w + 0.6, 0.8, 1.8), solid(STEEL, "Valance"))
	Parts.block(m, v(0, 19.08, 1.2), Vector3.new(w - 0.6, 0.06, 1.3), lamp())
	Parts.light(valance, LAMP, 18, 0.8, "Surface")
	-- Board screen, header and console.
	local panel = screen(m, "Panel", v(-5, 9.8, 1.4), 14, 13, medal)
	Parts.block(m, v(-5, 17.8, 1.25), Vector3.new(10, 1.7, 0.3), solid(WALNUT_DARK, "Header"))
	text(m, v(-5, 17.8, 1.45), 9, 1.3, string.upper(stat), BRASS:Lerp(WHITE, 0.25))
	Parts.roundedBox(m, v(-5, 1.6, 2.4), Vector3.new(12, 3.2, 2.2), 0.4, solid(WALNUT, "Console"))
	Parts.roundedBox(m, v(-5, 3.3, 2.4), Vector3.new(12.4, 0.2, 2.6), 0.5, solid(QUARTZ, "ConsoleTop"))
	Parts.block(m, v(-5, 0.18, 3.35), Vector3.new(11.6, 0.36, 0.4), solid(STEEL, "Kick"))
	local function button(vx: number, name: string, label: string): Part
		local b = Parts.cylinder(m, v(vx, 2.2, 3.6) * CFrame.Angles(PI / 2, 0, 0), 0.4, 2, solid(WALNUT_DARK, name))
		Parts.cylinder(m, v(vx, 2.2, 3.5) * CFrame.Angles(PI / 2, 0, 0), 0.08, 2.4, deco(BRASS, "ButtonRing"))
		text(m, v(vx, 2.2, 3.82), 1.6, 1.6, label, BRASS:Lerp(WHITE, 0.4))
		return b
	end
	local prev = button(-9.5, "Prev", "◀")
	local nxt = button(-0.5, "Next", "▶")
	local period = roundPanel(m, v(-5, 2.2, 3.6), 4.4, 1.6, 0.4, 0.6, solid(QUARTZ, "Period"))
	period.Name = "Period"
	text(m, v(-5, 2.2, 3.84), 4, 1.2, "PERIOD", WALNUT_DARK)
	-- Stepped marble podium with brass bands; the exclusive ball floats above it.
	local pc = v(8.5, 0, 6.5)
	local base = pc.Position
	for i, t in { { D = 9, Y = 0.3 }, { D = 7.2, Y = 0.9 }, { D = 5.6, Y = 1.5 } } do
		Parts.cylinder(m, CFrame.new(base + UP * t.Y), 0.6, t.D, solid(if i == 2 then WALNUT else MARBLE, "Step"))
		LobbyKit.torus(m, base + UP * (t.Y + 0.3), t.D / 2 - 0.05, 0.12, 32, deco(BRASS, "StepBand"), false)
	end
	Parts.cylinder(m, CFrame.new(base + UP * 2.85), 2.1, 3.6, solid(MARBLE, "Drum"))
	local podium = Parts.cylinder(m, CFrame.new(base + UP * 4.05), 0.3, 4.4, solid(QUARTZ, "Podium"))
	podium.Name = "Podium"
	LobbyKit.torus(m, base + UP * 3.9, 2.15, 0.16, 28, deco(medal, "MedalBand"), false)
	display(podium, base + UP * 7.2)
	local plateCf = CFrame.lookAt(base + UP * 2.85, base + UP * 2.85 + F.LookVector) * CFrame.new(0, 0, -1.82)
	local plate = Parts.block(m, plateCf, Vector3.new(3.2, 1.5, 0.12), { Name = "Nameplate", Color = SCREEN, CanCollide = false })
	outline(m, plateCf * CFrame.new(0, 0, 0.02), 3.2, 1.5, BRASS)
	local can = Parts.cylinder(m, CFrame.new(base + UP * (ROOM_H - 0.35)), 0.7, 1.4, solid(STEEL, "Downlight"))
	local spot = Parts.light(can, Color3.fromRGB(255, 236, 205), 26, 2.2, "Spot") :: SpotLight
	spot.Angle = 38
	-- Reward plaque above the podium.
	local skin = Skins.get((Config.Leaderboards.Rewards :: any)[stat])
	Parts.block(m, v(8.5, 13.6, 1.25), Vector3.new(9.4, 3.4, 0.3), solid(WALNUT_DARK, "Plaque"))
	Parts.block(m, v(8.5, 13.6, 1.12), Vector3.new(9.8, 3.8, 0.1), deco(BRASS, "PlaqueFrame"))
	text(m, v(8.5, 14.45, 1.44), 8.4, 0.9, "WEEKLY TOP 3 UNLOCK", WHITE)
	text(m, v(8.5, 13.25, 1.44), 8.4, 1.5, string.upper(skin.Name) .. " BALL", BRASS:Lerp(WHITE, 0.25))
	Parts.block(m, v(8.5, 12.2, 1.42), Vector3.new(2.6, 0.1, 0.05), deco(accent, "Accent"))
	local board: LobbyTypes.Board = {
		Panel = panel,
		Prev = prev,
		Next = nxt,
		Period = period,
		Podium = podium,
		Nameplate = plate,
	}
	return board
end

local function buildWest(room: Model, R: CFrame)
	local m = Parts.model(room, "Leaderboards")
	local accent = C.West
	local boards: { [string]: LobbyTypes.Board } = {
		Wins = buildBoard(m, along(R, 0, 0, ROOM_D, TO_ENTRANCE), "Wins", GOLD, accent),
		Coins = buildBoard(m, along(R, -ROOM_W, 0, 0, TO_PLUS_X), "Coins", SILVER, accent),
		Sabotages = buildBoard(m, along(R, ROOM_W, 0, 0, TO_MINUS_X), "Sabotages", BRONZE, accent),
	}
	-- Centrepiece: a turned brass championship cup on a marble plinth, on a rug.
	local tm = Parts.model(m, "Trophy")
	local c = at(R, 0, 0, 0)
	LobbyKit.rug(tm, CFrame.new(c), 18, 18, mat(RUG, M.Carpet), mat(RUG_BORDER, M.Carpet))
	LobbyKit.lathe(tm, c, {
		Vector2.new(3.4, 0.1),
		Vector2.new(3.4, 0.6),
		Vector2.new(2.6, 0.9),
		Vector2.new(2.2, 1.4),
		Vector2.new(2.2, 3.6),
		Vector2.new(2.7, 3.9),
		Vector2.new(2.8, 4.2),
	}, 28, 0.3, solid(MARBLE, "Plinth"))
	Parts.cylinder(tm, CFrame.new(c + UP * 2.15), 4.1, 4.6, solid(MARBLE, "PlinthCore"))
	LobbyKit.torus(tm, c + UP * 3.7, 2.25, 0.14, 28, deco(BRASS, "PlinthBand"), false)
	local brass = solid(BRASS, "Cup")
	LobbyKit.lathe(tm, c, {
		Vector2.new(1.5, 4.25),
		Vector2.new(1.2, 4.6),
		Vector2.new(0.4, 5.0),
		Vector2.new(0.35, 6.3),
		Vector2.new(0.9, 6.7),
		Vector2.new(1.9, 7.6),
		Vector2.new(2.3, 8.8),
		Vector2.new(2.2, 9.6),
		Vector2.new(2.45, 9.8),
	}, 24, 0.22, brass)
	Parts.cylinder(tm, CFrame.new(c + UP * 4.4), 0.4, 3, brass)
	for _, s in { -1, 1 } do
		Parts.hoop(tm, CFrame.lookAt(c + Vector3.new(s * 2.5, 8.4, 0), c + Vector3.new(s * 2.5, 8.4, 0) + Vector3.zAxis), 0.9, 0.3, 0.3, 14, deco(BRASS, "Handle"))
	end
	Parts.ball(tm, c + UP * 9.9, 1.6, solid(QUARTZ, "Ball"))
	local can = Parts.cylinder(tm, CFrame.new(c + UP * (ROOM_H - 0.35)), 0.7, 1.4, solid(STEEL, "Downlight"))
	local spot = Parts.light(can, Color3.fromRGB(255, 232, 196), 26, 2, "Spot") :: SpotLight
	spot.Angle = 34
	return { Boards = boards }
end

-- Final pass: palette colours become real materials, accent trims lose any glow
-- (only lamp glass stays emissive) and anything solid keeps plastic physics.
local function naturalize(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Material == NEON and string.sub(d.Name, 1, 4) ~= "Lamp" then
				d.Material = M.SmoothPlastic
			end
			if d.Material == M.SmoothPlastic then
				local m = MATERIAL_OF[d.Color:ToHex()]
				if m then
					d.Material = m
				end
			end
			if d.CanCollide and d.Material ~= M.SmoothPlastic and not (d.CustomPhysicalProperties :: PhysicalProperties?) then
				d.CustomPhysicalProperties = SMOOTH_PHYS
			end
		end
	end
end

-- Entry point -------------------------------------------------------------------------

function LobbyBuilder.build(): LobbyTypes.Lobby
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local rng = Random.new(20261011)

	buildGrounds(rng)
	buildAtrium(model, rng)
	for _, quad in QUADS do
		buildHall(model, quad)
	end
	buildScenery(model, rng)

	local northRoom, northR = buildRoomShell(model, QUADS[1], "Oak")
	local eastRoom, eastR = buildRoomShell(model, QUADS[2], "Marble")
	local southRoom, southR = buildRoomShell(model, QUADS[3], "Oak")
	local westRoom, westR = buildRoomShell(model, QUADS[4], "Walnut")

	local stations = Parts.model(model, "Stations")
	local spawn = buildSpawn(model)
	local sign, stand = buildDirectory(model)
	local dailyScreen, dailyButton = buildDaily(stations, rng)

	local lobby: LobbyTypes.Lobby = {
		Model = model,
		Spawn = spawn,
		SpawnCFrame = CFrame.lookAt(SPAWN_POS + Vector3.new(0, 2.5, 0), Vector3.new(0, 3, 0)),
		Directory = { Sign = sign, StandPoint = stand },
		Daily = { Screen = dailyScreen, Button = dailyButton },
		Stations = {
			Locker = buildLocker(stations, rng),
			Upgrades = buildUpgrades(stations, rng),
			CreatorKiosk = buildCreator(stations, rng),
		},
		North = buildNorth(northRoom, northR),
		East = buildEast(eastRoom, eastR),
		South = buildSouth(southRoom, southR),
		West = buildWest(westRoom, westR),
	}
	naturalize(model)
	model.Parent = workspace
	return lobby
end

return LobbyBuilder

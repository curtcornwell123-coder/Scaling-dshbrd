--!strict
-- Code-built lobby: an open-air garden plaza (grass lawn, dirt paths, stone
-- fountain, hedge-topped stone wall) in rolling meadow terrain, with four
-- clubhouse buildings around it (N Matchmaking, E Shop, S Practice,
-- W Leaderboards). Geometry only: services attach prompts, SurfaceGuis and
-- logic through the LobbyTypes.Lobby contract returned by build().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local CourseNature = require(script.Parent:WaitForChild("CourseNature"))
local LobbyTypes = require(script.Parent:WaitForChild("LobbyTypes"))

type Props = Parts.Props

local LobbyBuilder = {}

-- Palette -------------------------------------------------------------------
-- Clubhouse materials: plaster walls, oiled timber, limestone, terracotta roofs.

local C = Config.Colors
local hex = Color3.fromHex
local M = Enum.Material

local WALL = hex("#EEE5D3") -- plaster
local WALL2 = hex("#D9CAAE") -- limestone trim
local WOOD_DARK = hex("#4A3426")
local WOOD = hex("#6E4D35")
local FLOOR_A = hex("#B78C61") -- floor planks
local FLOOR_B = hex("#A67C53")
local SCREEN = hex("#161A22")
local WHITE = hex("#F7F2E8")
local GOLD = C.Gold
local SILVER = hex("#C9D3E6")
local BRONZE = hex("#D9895B")
local MYTHIC = hex("#FF2D55")
local LANE_GREEN = hex("#4E9A4A")
local STONE = hex("#A39A8C")
local STONE_DARK = hex("#7F776C")
local HEDGE = hex("#3F6A2E")
local ROOF = hex("#A65A3C")
local IRON = hex("#2F3033")
local LAMP = hex("#FFE3B3")
local WATER = hex("#6FB7D4")

-- Plain parts in these colours get the matching material in naturalize().
local MATERIAL_OF: { [string]: Enum.Material } = {
	[WALL:ToHex()] = M.Plaster,
	[WALL2:ToHex()] = M.Limestone,
	[WOOD_DARK:ToHex()] = M.Wood,
	[WOOD:ToHex()] = M.Wood,
	[FLOOR_A:ToHex()] = M.WoodPlanks,
	[FLOOR_B:ToHex()] = M.WoodPlanks,
	[STONE:ToHex()] = M.Cobblestone,
	[STONE_DARK:ToHex()] = M.Slate,
	[GOLD:ToHex()] = M.Metal,
	[IRON:ToHex()] = M.Metal,
	[LANE_GREEN:ToHex()] = M.Fabric,
}
-- Walkable parts keep plastic physics whatever they look like (balls roll the same).
local SMOOTH_PHYS = PhysicalProperties.new(0.7, 0.2, 0.5, 1, 1)

local NEON = M.Neon
local PI = math.pi

-- Dimensions (ground level is Y = 0, fountain at the origin) ---------------------

local LOBBY_R = 60 -- inner radius of the garden wall
local WALL_T = 3
local STONE_H = 2.4 -- stone course under the hedge
local HEDGE_H = 5.2
local BARRIER_H = 30 -- invisible, keeps everyone inside the grounds
local ARCH_HALF = 13 -- half width of each gateway
local ARCH_H = 16
local PLAZA_R = 19 -- cobbled circle round the fountain
local ROOM_DIST = 104
local ROOM_W = 44 -- half width
local ROOM_D = 32 -- half depth
local ROOM_H = 30
local HALL_HALF = 12
local NEAR_WALL = ROOM_DIST - ROOM_D -- axial distance of a room's entrance wall (inside face)

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

local BARRIER: Props = { Name = "Barrier", Transparency = 1, CastShadow = false }

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

-- Contract screen: dark display (Front = cf's LookVector) in a walnut bezel with a
-- thin painted accent edge. Returns the screen part.
local function screen(parent: Instance, name: string, cf: CFrame, w: number, h: number, accent: Color3): BasePart
	local m = Parts.model(parent, name)
	roundPanel(m, cf * CFrame.new(0, 0, 0.35), w + 1, h + 1, 0.5, 0.6, solid(WOOD_DARK, "Frame"))
	local e = 0.12
	Parts.block(m, cf * CFrame.new(0, h / 2 + e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), deco(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 - e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), deco(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(w / 2 + e / 2, 0, 0), Vector3.new(e, h, 0.2), deco(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(-w / 2 - e / 2, 0, 0), Vector3.new(e, h, 0.2), deco(accent, "Edge"))
	return Parts.block(m, cf, Vector3.new(w, h, 0.2), { Name = name, Color = SCREEN, CanCollide = false })
end

-- Walnut sign board: cream lettering tinted with the accent, accent stripes top and
-- bottom (cf = board front centre, facing the viewer).
local function titlePlate(parent: Instance, cf: CFrame, w: number, h: number, str: string, accent: Color3)
	local m = Parts.model(parent, "Title")
	local r = math.min(1.4, h / 3)
	roundPanel(m, cf * CFrame.new(0, 0, 0.5), w, h, 1, r, solid(WOOD_DARK, "Plate"))
	local t = math.min(0.22, h * 0.08)
	for _, s in { -1, 1 } do
		Parts.block(m, cf * CFrame.new(0, s * (h / 2 - 0.18 - t / 2), 0), Vector3.new(w - 2 * r, t, 0.1), deco(accent, "Stripe"))
	end
	text(m, cf * CFrame.new(0, 0, -0.08), w - 2, h - 0.8, str, accent:Lerp(WHITE, 0.6), WOOD_DARK)
end

local function display(part: BasePart, worldPos: Vector3)
	local a = Instance.new("Attachment")
	a.Name = "Display"
	a.CFrame = part.CFrame:ToObjectSpace(CFrame.new(worldPos))
	a.Parent = part
end

-- Flat floor pad: slate disc flush with the floor inside a painted accent ring.
local function pad(parent: Instance, name: string, pos: Vector3, diameter: number, accent: Color3): BasePart
	Parts.disc(parent, pos + Vector3.new(0, -0.03, 0), diameter + 0.6, 0.14, deco(accent, name .. "Ring"))
	local p = Parts.disc(parent, pos + Vector3.new(0, -0.04, 0), diameter, 0.2, { Name = name, Color = STONE_DARK, CanCollide = false })
	p:SetAttribute("Radius", diameter / 2)
	return p
end

-- Round showcase pedestal (timber foot, accent band, limestone column). Returns the cap.
local function roundPedestal(parent: Instance, name: string, pos: Vector3, ring: Color3, capColor: Color3?, lift: number?): BasePart
	local m = Parts.model(parent, name)
	Parts.disc(m, pos + Vector3.new(0, 0.25, 0), 4.6, 0.5, solid(WOOD_DARK, "Base"))
	Parts.disc(m, pos + Vector3.new(0, 0.6, 0), 4.0, 0.2, deco(ring, "Ring"))
	Parts.disc(m, pos + Vector3.new(0, 1.65, 0), 3.4, 2.3, solid(WALL2, "Column"))
	local cap = Parts.disc(m, pos + Vector3.new(0, 2.975, 0), 3.9, 0.35, solid(capColor or WHITE, name))
	display(cap, pos + Vector3.new(0, 3.15 + (lift or 2.5), 0))
	return cap
end

-- Park bench: iron frame, timber slats. cf faces the way a sitter looks.
local function bench(parent: Instance, cf: CFrame, _accent: Color3?)
	local m = Parts.model(parent, "Bench")
	for _, s in { -1, 1 } do
		Parts.block(m, cf * CFrame.new(s * 2.9, 0.85, 0), Vector3.new(0.35, 1.7, 2.2), solid(IRON, "Leg"))
		Parts.block(m, cf * CFrame.new(s * 2.9, 2.6, 1.05), Vector3.new(0.35, 2.2, 0.3), solid(IRON, "Leg"))
	end
	for i = 0, 2 do
		Parts.block(m, cf * CFrame.new(0, 1.82, -0.75 + i * 0.75), Vector3.new(7, 0.25, 0.62), solid(WOOD, "Slat"))
	end
	for i = 0, 1 do
		Parts.block(m, cf * CFrame.new(0, 2.6 + i * 0.85, 1.2), Vector3.new(7, 0.55, 0.2), solid(WOOD, "Slat"))
	end
end

-- Iron street lamp with a warm lantern.
local function lampPost(parent: Instance, pos: Vector3)
	local m = Parts.model(parent, "LampPost")
	Parts.disc(m, pos + Vector3.new(0, 0.35, 0), 1.5, 0.7, solid(IRON, "Foot"))
	Parts.disc(m, pos + Vector3.new(0, 4.3, 0), 0.42, 8, solid(IRON, "Pole"))
	Parts.disc(m, pos + Vector3.new(0, 8.4, 0), 1.3, 0.3, solid(IRON, "Collar"))
	local glass = Parts.block(m, CFrame.new(pos + Vector3.new(0, 9.35, 0)), Vector3.new(1.1, 1.6, 1.1), lamp())
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Parts.block(m, CFrame.new(pos + Vector3.new(sx * 0.6, 9.35, sz * 0.6)), Vector3.new(0.16, 1.7, 0.16), deco(IRON, "Frame"))
		end
	end
	Parts.block(m, CFrame.new(pos + Vector3.new(0, 10.3, 0)), Vector3.new(1.7, 0.3, 1.7), deco(IRON, "Hood"))
	Parts.ball(m, pos + Vector3.new(0, 10.65, 0), 0.5, deco(IRON, "Finial"))
	Parts.light(glass, LAMP, 20, 0.9)
end

-- Quadrants -------------------------------------------------------------------

type Quad = {
	Key: string,
	Frame: CFrame, -- at the fountain, LookVector toward the room
	Color: Color3,
	Arch: string, -- gateway sign
}

local QUADS: { Quad } = {
	{ Key = "North", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1)), Color = C.North, Arch = "MATCHMAKING" },
	{ Key = "East", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0)), Color = C.East, Arch = "SHOP" },
	{ Key = "South", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1)), Color = C.South, Arch = "PRACTICE" },
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

local POND = polar(98, 45, 0)

-- Grass lawn and meadow, a cobbled plaza, dirt paths to the gates, slate under the
-- buildings (no grass blades through floors), a pond and low hills on the horizon.
local function buildGrounds(rng: Random)
	local terrain = workspace.Terrain
	local ext = ROOM_DIST + ROOM_D + 170
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(ext * 2, 12, ext * 2), M.Grass)
	for _ = 1, 18 do
		local p = polar(rng:NextNumber(LOBBY_R + 30, ext - 20), rng:NextNumber(0, 360), -0.8)
		local size = Vector3.new(rng:NextNumber(14, 30), 1.4, rng:NextNumber(14, 30))
		terrain:FillBlock(CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, PI), 0), size, M.LeafyGrass)
	end
	terrain:FillCylinder(CFrame.new(0, -2, 0), 4, PLAZA_R + 1, M.Cobblestone)
	for _, quad in QUADS do
		local d0, d1 = PLAZA_R - 1, LOBBY_R + 1
		terrain:FillBlock(along(quad.Frame, 0, -1, (d0 + d1) / 2), Vector3.new(10, 2, d1 - d0), M.Ground)
		terrain:FillBlock(along(quad.Frame, 0, -2, (LOBBY_R + NEAR_WALL) / 2), Vector3.new(HALL_HALF * 2 + 6, 4, NEAR_WALL - LOBBY_R + 2), M.Slate)
		-- Room interiors: carve the top layer out so the plank floor never meets the ground.
		local R = roomFrame(quad)
		terrain:FillBlock(R * CFrame.new(0, -6, 0), Vector3.new(2 * ROOM_W + 6, 4, 2 * ROOM_D + 6), M.Slate)
		terrain:FillBlock(R * CFrame.new(0, -2, 0), Vector3.new(2 * ROOM_W, 4, 2 * ROOM_D), M.Air)
	end
	terrain:FillCylinder(CFrame.new(POND + Vector3.new(0, -2, 0)), 3.4, 10, M.Water)
	for i = 0, 17 do
		local r = rng:NextNumber(26, 44)
		terrain:FillBall(polar(rng:NextNumber(225, 265), i * 20 + rng:NextNumber(-6, 6), -r * 0.55), r, M.Grass)
	end
end

-- True when a prop of radius `r` at p stays clear of the buildings, walls and pond.
local function openGround(p: Vector3, r: number): boolean
	local flat = Vector3.new(p.X, 0, p.Z)
	if flat.Magnitude < LOBBY_R + 6 + r or (flat - POND).Magnitude < 12 + r then
		return false
	end
	for _, quad in QUADS do
		local l = roomFrame(quad):PointToObjectSpace(flat)
		if math.abs(l.X) < ROOM_W + 6 + r and math.abs(l.Z) < ROOM_D + 6 + r then
			return false
		end
	end
	return true
end

-- Trees, flower beds and bushes (decoration: they never collide).
local function buildScenery(parent: Instance, rng: Random)
	local m = Parts.model(parent, "Scenery")
	-- Four shade trees on the lawn diagonals, each with an invisible trunk collider.
	for k = 0, 3 do
		local base = polar(44, 45 + k * 90, 0)
		CourseNature.prop(m, "Oak", base, -base.Unit, rng, MEADOW)
		Parts.cylinder(m, CFrame.new(base + Vector3.new(0, 5, 0)), 10, 2.2, { Name = "TrunkCollider", Transparency = 1, CastShadow = false })
		for j = 0, 4 do
			local p = base + polar(rng:NextNumber(4.5, 6.5), j * 72 + rng:NextNumber(-15, 15), 0)
			CourseNature.prop(m, if j % 2 == 0 then "Flowers" else "Bush", p, -p.Unit, rng, MEADOW)
		end
	end
	-- Planting along the inside of the wall, clear of the gateways.
	for q = 0, 3 do
		for i = 0, 5 do
			local p = polar(LOBBY_R - 2.6, q * 90 + 24 + i * 8.4, 0)
			CourseNature.prop(m, if i % 2 == 0 then "Flowers" else "Bush", p, -p.Unit, rng, MEADOW)
		end
	end
	-- Meadow outside the walls: trees in the open corners, a far ring on the horizon.
	local placed = 0
	for _ = 1, 400 do
		if placed >= 26 then
			break
		end
		local p = polar(rng:NextNumber(LOBBY_R + 12, 175), rng:NextNumber(0, 360), 0)
		if openGround(p, 5) then
			CourseNature.prop(m, if rng:NextNumber() < 0.75 then "Oak" else "Bush", p, -p.Unit, rng, MEADOW)
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
end

-- Plaza ---------------------------------------------------------------------------

local function buildPlaza(parent: Instance)
	local m = Parts.model(parent, "Plaza")
	Parts.flatRing(m, Vector3.new(0, 0.12, 0), PLAZA_R, 0.9, 0.36, 32, mat(WALL2, M.Limestone, "Kerb"))
	for k = 0, 3 do
		lampPost(m, polar(PLAZA_R + 2.6, 45 + k * 90, 0))
	end
	-- Benches facing the fountain on the south half (the spawn side stays open).
	for _, deg in { 122, 148, 212, 238 } do
		bench(m, inward(PLAZA_R + 3.6, deg, 0))
	end
	-- Lamps where the paths reach the gates.
	for _, quad in QUADS do
		for _, s in { -1, 1 } do
			lampPost(m, at(quad.Frame, s * 7.5, 0, LOBBY_R - 9))
		end
	end
end

-- Garden wall ---------------------------------------------------------------------
-- Stone course with a clipped hedge on top, limestone piers at every other joint and
-- an invisible barrier above (the ring leaves a gap at each gateway).

local function hedgeProps(name: string): Props
	return mat(HEDGE, M.LeafyGrass, name)
end

local function buildWall(parent: Instance)
	local m = Parts.model(parent, "Wall")
	local rMid = LOBBY_R + WALL_T / 2
	local rOut = LOBBY_R + WALL_T
	local alpha = math.deg(math.asin(ARCH_HALF / LOBBY_R))
	local perQuarter = 10
	local step = (90 - 2 * alpha) / perQuarter
	local w = 2 * rOut * math.tan(math.rad(step / 2)) + 0.1
	local hedgeY = STONE_H + 0.3
	for q = 0, 3 do
		for i = 0, perQuarter - 1 do
			local deg = q * 90 + alpha + (i + 0.5) * step
			local seg = Parts.model(m, "Segment")
			Parts.block(seg, inward(rMid, deg, STONE_H / 2), Vector3.new(w, STONE_H, WALL_T + 0.6), solid(STONE, "Stone"))
			Parts.block(seg, inward(rMid, deg, STONE_H + 0.15), Vector3.new(w, 0.3, WALL_T + 0.9), solid(WALL2, "Coping"))
			Parts.block(seg, inward(rMid, deg, hedgeY + HEDGE_H / 2), Vector3.new(w + 0.2, HEDGE_H, WALL_T - 0.2), hedgeProps("Hedge"))
			Parts.cylinder(seg, inward(rMid, deg, hedgeY + HEDGE_H) * CFrame.Angles(0, 0, PI / 2), w + 0.2, WALL_T - 0.2, hedgeProps("HedgeTop"))
			Parts.block(seg, inward(rMid, deg, BARRIER_H / 2), Vector3.new(w, BARRIER_H, WALL_T), BARRIER)
			if i % 2 == 1 and i < perQuarter - 1 then
				local jd = q * 90 + alpha + (i + 1) * step
				local top = hedgeY + HEDGE_H + 1.6
				Parts.block(seg, inward(rMid, jd, top / 2), Vector3.new(2.6, top, WALL_T + 1.2), solid(WALL2, "Pier"))
				Parts.block(seg, inward(rMid, jd, top + 0.25), Vector3.new(3.2, 0.5, WALL_T + 1.8), solid(WALL2, "PierCap"))
				Parts.ball(seg, polar(rMid, jd, top + 1), 1.4, solid(WALL2, "PierBall"))
			end
		end
	end
end

-- Gateway: limestone piers, a timber lintel and the hanging sign facing the plaza.
local function buildGate(parent: Instance, quad: Quad)
	local m = Parts.model(parent, "Gate" .. quad.Key)
	local q = quad.Frame
	local d = LOBBY_R + WALL_T / 2
	for _, s in { -1, 1 } do
		local x = s * 14.6
		Parts.block(m, along(q, x, 0.6, d), Vector3.new(4.8, 1.2, 4.8), solid(STONE_DARK, "PierFoot"))
		Parts.block(m, along(q, x, ARCH_H / 2, d), Vector3.new(4, ARCH_H, 4), solid(STONE, "Pier"))
		Parts.block(m, along(q, x, ARCH_H + 0.35, d), Vector3.new(4.8, 0.7, 4.8), solid(WALL2, "PierCap"))
		Parts.block(m, along(q, x, ARCH_H + 0.5, d - 2.6), Vector3.new(1.1, 1.6, 1.1), lamp())
		Parts.block(m, along(q, x, ARCH_H + 1.45, d - 2.6), Vector3.new(1.5, 0.3, 1.5), deco(IRON, "Hood"))
		Parts.block(m, along(q, x, ARCH_H + 0.5, d - 2.05), Vector3.new(0.3, 0.3, 1.1), deco(IRON, "Bracket"))
	end
	Parts.block(m, along(q, 0, ARCH_H + 1.5, d), Vector3.new(34, 1.6, 2.4), solid(WOOD_DARK, "Lintel"))
	titlePlate(m, along(q, 0, ARCH_H + 4.4, d - 0.9, TO_ENTRANCE), 22, 4.4, quad.Arch, quad.Color)
	for _, s in { -1, 1 } do
		Parts.block(m, along(q, s * 9, ARCH_H + 2.3, d - 0.5), Vector3.new(0.4, 0.4, 0.4), deco(IRON, "Hook"))
	end
end

-- Central fountain ----------------------------------------------------------

local function waterEmitter(anchor: BasePart, cf: CFrame, rate: number, speed: NumberRange, life: NumberRange, size: NumberSequence, spread: number, gravity: number): ParticleEmitter
	local a = Instance.new("Attachment")
	a.Name = "Water"
	a.CFrame = anchor.CFrame:ToObjectSpace(cf)
	a.Parent = anchor
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(hex("#F2FAFF"), hex("#B5DCEE"))
	e.LightEmission = 0.15
	e.LightInfluence = 0.9
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = size
	e.Rate = rate
	e.Lifetime = life
	e.Speed = speed
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = Vector3.new(0, -gravity, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Parent = a
	return e
end

local function waterSurface(name: string): Props
	return {
		Name = name,
		Color = WATER,
		Material = M.Glass,
		Transparency = 0.3,
		Reflectance = 0.25,
		CanCollide = false,
		CanQuery = false,
	}
end

local function buildFountain(parent: Instance)
	local m = Parts.model(parent, "Fountain")
	local marble = mat(WHITE, M.Marble, "Marble")
	-- Step plinth and the collecting bowl: stone floor, rim wall, marble cap, water.
	Parts.disc(m, Vector3.new(0, 0.1, 0), 29.6, 0.5, solid(STONE_DARK, "Step"))
	Parts.disc(m, Vector3.new(0, 0.6, 0), 24.2, 1.2, solid(STONE_DARK, "BowlBody"))
	Parts.flatRing(m, Vector3.new(0, 0.95, 0), 12.3, 1.4, 1.9, 28, solid(WALL2, "Rim"))
	Parts.flatRing(m, Vector3.new(0, 2.05, 0), 12.3, 1.9, 0.3, 28, marble)
	Parts.flatRing(m, Vector3.new(0, 0.55, 0), 13.1, 0.4, 0.5, 28, solid(STONE_DARK, "RimBase"))
	Parts.disc(m, Vector3.new(0, 1.5, 0), 23.6, 0.2, waterSurface("Water"))
	-- Pedestal column and upper basin (radius 4.5, rim at y 7.7).
	Parts.disc(m, Vector3.new(0, 1.6, 0), 4.2, 0.8, solid(STONE_DARK, "Collar"))
	Parts.disc(m, Vector3.new(0, 3.7, 0), 3, 5, solid(WALL2, "Column"))
	Parts.disc(m, Vector3.new(0, 5.9, 0), 6, 0.6, solid(WALL2, "BasinTaper"))
	Parts.disc(m, Vector3.new(0, 6.7, 0), 9, 1, solid(WALL2, "Basin"))
	Parts.flatRing(m, Vector3.new(0, 7.45, 0), 4.25, 0.7, 0.5, 18, marble)
	Parts.disc(m, Vector3.new(0, 7.35, 0), 8, 0.2, waterSurface("Water"))
	-- Top spout.
	Parts.disc(m, Vector3.new(0, 8.8, 0), 1, 3.2, solid(WALL2, "Spout"))
	Parts.ball(m, Vector3.new(0, 10.6, 0), 1.4, marble)

	-- Flowing water: jet up from the spout, cascades over the upper rim, splashes below.
	local anchor = Parts.block(m, CFrame.new(0, 6, 0), Vector3.one, {
		Name = "WaterFx",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local flowSize = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.3) })
	waterEmitter(anchor, CFrame.new(0, 11.2, 0), 45, NumberRange.new(6, 8), NumberRange.new(1.2, 1.8), flowSize, 10, 30)
	for j = 0, 5 do
		local deg = j * 60 + 30
		local out = polar(1, deg, 0)
		local tangent = Vector3.new(-out.Z, 0, out.X)
		local up = (out * 0.8 + Vector3.yAxis * 0.6).Unit
		waterEmitter(anchor, CFrame.fromMatrix(polar(4.6, deg, 7.75), tangent, up), 45, NumberRange.new(4, 6), NumberRange.new(1.2, 1.8), flowSize, 8, 30)
	end
	local splashSize = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	for j = 0, 5 do
		local splash = waterEmitter(anchor, CFrame.new(polar(7.4, j * 60 + 30, 1.65)), 18, NumberRange.new(1.5, 3), NumberRange.new(0.4, 0.7), splashSize, 35, 10)
		splash.Transparency = NumberSequence.new(0.55, 1)
	end
end

-- Walkways ------------------------------------------------------------------
-- Flagstones from the gate to the clubhouse door between hedged side walls, under
-- a timber pergola.

local function buildHall(parent: Instance, quad: Quad)
	local m = Parts.model(parent, "Hall" .. quad.Key)
	local q = quad.Frame
	local d0 = LOBBY_R - 1
	local dWall = NEAR_WALL - 2 -- outside face of the clubhouse front wall
	Parts.block(m, along(q, 0, -0.45, (d0 + NEAR_WALL) / 2), Vector3.new(HALL_HALF * 2 + 2, 1, NEAR_WALL - d0), solid(STONE_DARK, "Floor"))
	local w0, w1 = LOBBY_R - 3, dWall
	local wm, wl = (w0 + w1) / 2, w1 - w0
	for _, s in { -1, 1 } do
		local x = s * (HALL_HALF + 1.5)
		Parts.block(m, along(q, x, STONE_H / 2, wm), Vector3.new(3.6, STONE_H, wl), solid(STONE, "Stone"))
		Parts.block(m, along(q, x, STONE_H + 0.15, wm), Vector3.new(3.9, 0.3, wl), solid(WALL2, "Coping"))
		Parts.block(m, along(q, x, STONE_H + 0.3 + HEDGE_H / 2, wm), Vector3.new(2.8, HEDGE_H, wl), hedgeProps("Hedge"))
		Parts.block(m, along(q, x, BARRIER_H / 2, wm), Vector3.new(3, BARRIER_H, wl), BARRIER)
		Parts.block(m, along(q, s * (HALL_HALF - 0.45), (ARCH_H + 1) / 2, dWall - 0.8), Vector3.new(0.9, ARCH_H + 1, 0.9), solid(WOOD_DARK, "Post"))
		Parts.block(m, along(q, s * (HALL_HALF - 0.45), ARCH_H + 1.45, (d0 + 3 + dWall) / 2), Vector3.new(0.9, 0.9, dWall - d0 - 2), solid(WOOD_DARK, "Beam"))
	end
	local d = LOBBY_R + 4.2
	while d < dWall - 0.4 do
		Parts.block(m, along(q, 0, ARCH_H + 2.15, d), Vector3.new(HALL_HALF * 2 + 1.5, 0.5, 0.45), solid(WOOD, "Rafter"))
		d += 1.5
	end
end

-- Clubhouse shell -------------------------------------------------------------
-- Room frame R: centre of the room floor, LookVector away from the lobby.
-- Room-local coordinates (x, y, u): u = +ROOM_D is the back wall, -ROOM_D the entrance.

local function trimRun(m: Instance, R: CFrame, x0: number, u0: number, x1: number, u1: number, nx: number, nu: number, accent: Color3)
	local function run(off: number, y: number, h: number, depth: number, props: Props)
		Parts.beam(m, at(R, x0 + nx * off, y, u0 + nu * off), at(R, x1 + nx * off, y, u1 + nu * off), depth, h, props)
	end
	run(0.3, 1.2, 2.4, 0.6, solid(WOOD_DARK, "Skirting"))
	run(0.25, 2.575, 0.35, 0.5, deco(accent, "Band"))
	run(0.5, ROOM_H - 1, 2, 1, solid(WOOD_DARK, "Crown"))
end

-- Fake sash window on an outside wall (cf = glass centre, LookVector out).
local function window(m: Instance, cf: CFrame, w: number, h: number)
	Parts.block(m, cf * CFrame.new(0, 0, 0.1), Vector3.new(w + 0.8, h + 0.8, 0.3), solid(WOOD_DARK, "WindowFrame"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 - 0.55, -0.1), Vector3.new(w + 1.4, 0.35, 0.7), solid(WALL2, "Sill"))
	Parts.block(m, cf, Vector3.new(w, h, 0.1), { Name = "Glass", Color = hex("#33444F"), Material = M.Glass, Reflectance = 0.3, CanCollide = false, CanQuery = false })
	Parts.block(m, cf * CFrame.new(0, 0, -0.05), Vector3.new(0.22, h, 0.12), deco(WOOD_DARK, "Mullion"))
	Parts.block(m, cf * CFrame.new(0, 0, -0.05), Vector3.new(w, 0.22, 0.12), deco(WOOD_DARK, "Mullion"))
end

-- Outside of a clubhouse: stone plinth, timber corners and eaves, windows and a
-- terracotta gable roof (ridge parallel to the entrance wall).
local function buildExterior(m: Instance, R: CFrame, top: number)
	local W, D = ROOM_W, ROOM_D
	local ox, ou = W + 2, D + 2 -- outside faces
	local plinth = solid(STONE, "Plinth")
	Parts.block(m, along(R, 0, 1.5, ou + 0.3), Vector3.new(2 * ox + 1.2, 3, 0.6), plinth)
	for _, s in { -1, 1 } do
		Parts.block(m, along(R, s * (ox + 0.3), 1.5, 0), Vector3.new(0.6, 3, 2 * ou + 1.2), plinth)
		local len = ox - HALL_HALF
		Parts.block(m, along(R, s * (HALL_HALF + len / 2), 1.5, -ou - 0.3), Vector3.new(len + 0.6, 3, 0.6), plinth)
		for _, su in { -1, 1 } do
			Parts.block(m, along(R, s * ox, top / 2, su * ou), Vector3.new(1.8, top, 1.8), solid(WOOD_DARK, "Corner"))
		end
	end
	local eave = solid(WOOD_DARK, "Eave")
	Parts.block(m, along(R, 0, top - 0.7, ou + 0.35), Vector3.new(2 * ox + 1.4, 1.4, 0.7), eave)
	Parts.block(m, along(R, 0, top - 0.7, -ou - 0.35), Vector3.new(2 * ox + 1.4, 1.4, 0.7), eave)
	for _, s in { -1, 1 } do
		Parts.block(m, along(R, s * (ox + 0.35), top - 0.7, 0), Vector3.new(0.7, 1.4, 2 * ou + 1.4), eave)
	end
	-- Windows: either side of the door, along both side walls and the back.
	for _, x in { -36, -24, 24, 36 } do
		window(m, along(R, x, 12, -ou - 0.05, TO_ENTRANCE), 5.6, 8)
	end
	for _, s in { -1, 1 } do
		for _, u in { -18, 0, 18 } do
			window(m, along(R, s * (ox + 0.05), 12, u, if s > 0 then TO_MINUS_X else TO_PLUS_X), 5.6, 8)
		end
	end
	for _, x in { -30, -10, 10, 30 } do
		window(m, along(R, x, 12, ou + 0.05, TO_BACK), 5.6, 8)
	end
	-- Gable roof: two tiled slopes, plaster gable ends, ridge cap.
	local rise, over = 13, 3
	local theta = math.atan(rise / ou)
	local run = ou + over
	local roofW = 2 * ox + 2 * over
	local tiles = mat(ROOF, M.ClayRoofTiles, "Roof")
	for _, s in { -1, 1 } do
		local cf = along(R, 0, top + rise - rise * (run / 2) / ou, s * run / 2) * CFrame.Angles(-s * theta, 0, 0) * CFrame.new(0, 0.5, 0)
		Parts.block(m, cf, Vector3.new(roofW, 1, run / math.cos(theta)), tiles)
	end
	Parts.block(m, along(R, 0, top + rise + 0.75, 0), Vector3.new(roofW, 0.9, 1.8), mat(ROOF:Lerp(Color3.new(0, 0, 0), 0.25), M.ClayRoofTiles, "Ridge"))
	for _, s in { -1, 1 } do
		local x = s * (ox - 1)
		Parts.triangle(m, at(R, x, top, -ou), at(R, x, top, ou), at(R, x, top + rise, 0), 2, solid(WALL, "Gable"))
	end
end

local function buildRoomShell(parent: Instance, quad: Quad, title: string, checker: boolean): (Model, CFrame)
	local m = Parts.model(parent, quad.Key .. "Room")
	local R = roomFrame(quad)
	local accent = quad.Color
	local W, D, H = ROOM_W, ROOM_D, ROOM_H
	local shell = Parts.model(m, "Shell")
	-- Plank floor (+ large alternating boards 0.02 above it).
	Parts.block(shell, along(R, 0, -0.5, 1), Vector3.new(2 * W + 4, 1, 2 * D + 2), solid(FLOOR_A, "Floor"))
	if checker then
		for ix = 0, 3 do
			for iu = 0, 3 do
				if (ix + iu) % 2 == 0 then
					Parts.block(shell, along(R, -W + 11 + 22 * ix, 0, -D + 8 + 16 * iu), Vector3.new(22, 0.04, 16), deco(FLOOR_B, "Tile"))
				end
			end
		end
	end
	Parts.block(shell, along(R, 0, 0, -D + 0.4), Vector3.new(22, 0.08, 2.8), deco(STONE_DARK, "Threshold"))
	-- Walls and ceiling (2 thick, outside the interior box).
	local top = H + 1.5
	local yc = (top - 1) / 2
	local wallH = top + 1
	Parts.block(shell, along(R, 0, yc, D + 1), Vector3.new(2 * W + 4, wallH, 2), solid(WALL, "BackWall"))
	for _, s in { -1, 1 } do
		Parts.block(shell, along(R, s * (W + 1), yc, 0), Vector3.new(2, wallH, 2 * D + 4), solid(WALL, "SideWall"))
		local len = W + 2 - HALL_HALF
		Parts.block(shell, along(R, s * (HALL_HALF + len / 2), yc, -D - 1), Vector3.new(len, wallH, 2), solid(WALL, "FrontWall"))
	end
	Parts.block(shell, along(R, 0, (ARCH_H + 0.5 + top) / 2, -D - 1), Vector3.new(HALL_HALF * 2 + 0.2, top - ARCH_H - 0.5, 2), solid(WALL, "DoorHeader"))
	Parts.block(shell, along(R, 0, H + 0.75, 0), Vector3.new(2 * W + 4, 1.5, 2 * D + 4), solid(WALL, "Ceiling"))
	-- Interior trims.
	trimRun(shell, R, -W, D, W, D, 0, -1, accent)
	trimRun(shell, R, -W, -D, -W, D, 1, 0, accent)
	trimRun(shell, R, W, -D, W, D, -1, 0, accent)
	trimRun(shell, R, -W, -D, -HALL_HALF - 1.5, -D, 0, 1, accent)
	trimRun(shell, R, HALL_HALF + 1.5, -D, W, -D, 0, 1, accent)
	-- Door frame on the room side.
	for _, s in { -1, 1 } do
		Parts.block(shell, along(R, s * 13, ARCH_H / 2, -D + 0.5), Vector3.new(2.6, ARCH_H, 2.6), solid(WOOD_DARK, "DoorPost"))
	end
	Parts.block(shell, along(R, 0, ARCH_H + 1.1, -D + 0.5), Vector3.new(28.6, 2.2, 2.6), solid(WOOD_DARK, "DoorLintel"))
	-- Corner columns, exposed ceiling beams and warm light panels.
	for _, sx in { -1, 1 } do
		for _, su in { -1, 1 } do
			Parts.block(shell, along(R, sx * (W - 1), (H - 2) / 2, su * (D - 1)), Vector3.new(2.4, H - 2, 2.4), solid(WOOD, "Column"))
		end
	end
	for _, u in { -D / 3, D / 3 } do
		Parts.block(shell, along(R, 0, H - 0.6, u), Vector3.new(2 * W, 1.2, 1.4), solid(WOOD_DARK, "Beam"))
	end
	for _, x in { -W * 0.6, 0, W * 0.6 } do
		for _, u in { -D / 1.6, 0, D / 1.6 } do
			Parts.block(shell, along(R, x, H - 0.1, u), Vector3.new(7.4, 0.2, 3.6), solid(WOOD_DARK, "Fixture"))
			local panel = Parts.block(shell, along(R, x, H - 0.25, u), Vector3.new(6.6, 0.2, 2.8), lamp())
			if u ~= 0 then
				Parts.light(panel, LAMP, 30, 1.3, "Surface")
			end
		end
	end
	-- Room title on the back wall.
	titlePlate(shell, along(R, 0, 24.6, D - 1, TO_ENTRANCE), 44, 5, title, accent)
	buildExterior(shell, R, top)
	return m, R
end

-- Spawn, directory sign, daily calendar -----------------------------------------

local SPAWN_POS = Vector3.new(0, 0.5, -25)

local function buildSpawn(parent: Instance): SpawnLocation
	local m = Parts.model(parent, "Spawn")
	Parts.disc(m, Vector3.new(0, 0.08, -25), 10, 0.16, deco(WALL2, "SpawnRim"))
	Parts.disc(m, Vector3.new(0, 0.1, -25), 8.8, 0.16, deco(STONE, "SpawnPad"))
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

-- Timber 4-way signpost facing the spawn. Arrow directions are as seen from the
-- spawn looking south: +X (East) is to the player's left.
local function buildDirectory(parent: Instance): (BasePart, Vector3)
	local m = Parts.model(parent, "Directory")
	local base = Vector3.new(10, 0, -20)
	local cf = CFrame.lookAt(base, Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z))
	Parts.roundedBox(m, cf * CFrame.new(0, 0.3, 0.6), Vector3.new(5, 0.6, 3), 0.8, solid(STONE, "Base"))
	Parts.roundedBox(m, cf * CFrame.new(0, 0.7, 0.6), Vector3.new(4.2, 0.2, 2.2), 0.6, solid(WALL2, "BaseCap"))
	Parts.block(m, cf * CFrame.new(0, 3.2, 0.9), Vector3.new(1.3, 5.8, 1.3), solid(WOOD_DARK, "Post"))
	roundPanel(m, cf * CFrame.new(0, 7.6, 0.35), 8.6, 10.2, 0.4, 0.9, solid(WOOD_DARK, "Frame"))
	local sign = Parts.block(m, cf * CFrame.new(0, 7.6, 0), Vector3.new(7.8, 9.4, 0.3), solid(WOOD, "DirectorySign"))
	local head = Parts.block(m, cf * CFrame.new(0, 11.3, -0.22), Vector3.new(7.8, 1.6, 0.15), solid(WHITE, "Header"))
	text(m, head.CFrame * CFrame.new(0, 0, -0.1), 7.4, 1.5, "WHERE TO?", WOOD_DARK)
	-- Arrow boards: label, colour, tip side (+1 = viewer's left = cf +X, -1 = right, 0 = none).
	local arrows = {
		{ Text = "▲  PRACTICE · SOUTH", Color = C.South, Tip = 0 },
		{ Text = "◀  SHOP · EAST", Color = C.East, Tip = 1 },
		{ Text = "LEADERBOARDS · WEST  ▶", Color = C.West, Tip = -1 },
		{ Text = "▼  MATCHMAKING · BEHIND YOU", Color = C.North, Tip = 0 },
	}
	for i, a in arrows do
		local y = 11.225 - i * 1.8
		local body = cf * CFrame.new(a.Tip * -0.4, y, -0.3)
		local board = Parts.block(m, body, Vector3.new(6.4, 1.55, 0.3), mat(a.Color, M.WoodPlanks, "Arrow"))
		if a.Tip ~= 0 then
			local tx = a.Tip * -0.4 + a.Tip * 3.2
			local p1 = (cf * CFrame.new(tx, y + 0.775, -0.3)).Position
			local p2 = (cf * CFrame.new(tx, y - 0.775, -0.3)).Position
			local p3 = (cf * CFrame.new(tx + a.Tip * 0.9, y, -0.3)).Position
			Parts.triangle(m, p1, p2, p3, 0.3, mat(a.Color, M.WoodPlanks, "ArrowTip"))
		end
		text(m, board.CFrame * CFrame.new(0, 0, -0.2), 6.2, 1.4, a.Text, WHITE, WOOD_DARK)
	end
	return sign, (cf * CFrame.new(0, 3, -5)).Position
end

local function buildDaily(parent: Instance): (BasePart, BasePart)
	local m = Parts.model(parent, "Daily")
	local base = Vector3.new(-12, 0, -34)
	local cf = CFrame.lookAt(base, Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z))
	Parts.block(m, cf * CFrame.new(0, 0.25, 0.6), Vector3.new(12, 0.5, 3.4), solid(STONE, "Base"))
	for _, s in { -1, 1 } do
		Parts.block(m, cf * CFrame.new(s * 5.6, 5.6, 0.8), Vector3.new(0.9, 11.2, 0.9), solid(WOOD_DARK, "Post"))
	end
	local scr = screen(m, "DailyScreen", cf * CFrame.new(0, 7.5, 0.5), 10, 6, GOLD)
	titlePlate(m, cf * CFrame.new(0, 11.9, 0.3), 11.4, 1.8, "DAILY REWARDS", GOLD)
	-- Claim button on a stone pedestal in front of the board.
	Parts.cylinder(m, cf * CFrame.new(0, 1.5, -3), 3, 2.6, solid(WALL2, "ButtonPedestal"))
	Parts.cylinder(m, cf * CFrame.new(0, 3.08, -3), 0.16, 2.9, deco(WOOD_DARK, "ButtonRing"))
	local button = Parts.cylinder(m, cf * CFrame.new(0, 3.3, -3), 0.6, 2.1, solid(GOLD, "DailyButton"))
	text(m, cf * CFrame.new(0, 1.8, -4.36), 2, 0.9, "CLAIM", WOOD_DARK)
	return scr, button
end

-- Painted outline hugging a w x h face centred on cf.
local function outline(parent: Instance, cf: CFrame, w: number, h: number, color: Color3)
	local e = 0.16
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

-- Final pass: palette colours become real materials, accent trims lose their glow
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
		roundPanel(p, along(R, x, 11.75, ROOM_D - 0.25, TO_ENTRANCE), 19.5, 17.5, 0.5, 2, solid(WOOD_DARK, "Backdrop"))
		heroPanel(p, along(R, x, 11.75, ROOM_D - 0.55, TO_ENTRANCE), 17.5, 15.5, col:Lerp(WOOD_DARK, 0.3), WOOD)
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
		local sign = screen(p, "Sign", along(R, x, 19.6, 29, TO_ENTRANCE), 12, 4, col)
		for _, s in { -1, 1 } do
			Parts.block(p, along(R, x + s * 4, 19.6, 30.5), Vector3.new(0.6, 0.6, 1.8), solid(WOOD_DARK, "Bracket"))
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
			Color = WOOD_DARK,
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
	titlePlate(vm, along(R, -43, 18.6, 0, TO_PLUS_X), 16, 2.6, "MAP VOTE", accent)

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

-- Console with three labelled buttons on top, facing `yaw` in room frame R.
-- `buttons` lists the labels from the user's left to right; returns the button parts.
local function console(parent: Instance, R: CFrame, x: number, u: number, yaw: number, buttons: { { Name: string, Label: string, Color: Color3 } }, accent: Color3): { BasePart }
	local m = Parts.model(parent, "Console")
	local cf = along(R, x, 0, u, yaw)
	Parts.roundedBox(m, cf * CFrame.new(0, 1.6, 0), Vector3.new(9, 3.2, 2.2), 0.6, solid(WOOD, "Desk"))
	Parts.block(m, cf * CFrame.new(0, 2.95, -1.12), Vector3.new(7.6, 0.16, 0.16), deco(accent, "Trim"))
	local out: { BasePart } = {}
	for i, b in buttons do
		-- cf's +X is the user's left (the user faces the console's front).
		local bx = (2 - i) * 3
		Parts.cylinder(m, cf * CFrame.new(bx, 3.24, 0), 0.08, 2.3, deco(b.Color, "ButtonRing"))
		local part = Parts.cylinder(m, cf * CFrame.new(bx, 3.45, 0), 0.5, 1.9, solid(b.Color, b.Name))
		table.insert(out, part)
		text(m, cf * CFrame.new(bx, 1.7, -1.16), 2.8, 1.1, b.Label, WHITE, WOOD_DARK, false)
	end
	return out
end

local function buildEast(room: Model, R: CFrame)
	local m = Parts.model(room, "Shop")
	local accent = C.East

	-- 12 coin-shop skin pedestals in a U around the room centre, open toward the entrance.
	local sm = Parts.model(m, "SkinPedestals")
	Parts.disc(sm, at(R, 0, 0.02, -2), 35.2, 0.08, deco(accent, "MedallionRing"))
	Parts.disc(sm, at(R, 0, 0.04, -2), 34, 0.08, deco(WALL2, "Medallion"))
	local skins: { BasePart } = {}
	for i = 1, 12 do
		local theta = math.rad(-125 + (i - 1) * 250 / 11)
		local pos = at(R, 14 * math.sin(theta), 0, -2 + 14 * math.cos(theta))
		table.insert(skins, roundPedestal(sm, "SkinPedestal" .. i, pos, accent))
	end

	-- Mythic shrine: isolated alcove in the middle of the back wall.
	local am = Parts.model(m, "MythicShrine")
	for _, s in { -1, 1 } do
		Parts.roundedBox(am, along(R, s * 11, 12, 26.5), Vector3.new(1.5, 24, 11), 0.75, solid(WOOD, "Partition"))
		Parts.block(am, along(R, s * 11, 24.05, 26.75), Vector3.new(0.5, 0.1, 10.5), deco(GOLD, "PartitionGlow"))
		local pillar = Parts.cylinder(am, along(R, s * 11, 12, 21), 24, 1.7, deco(MYTHIC, "Pillar"))
		Parts.disc(am, at(R, s * 11, 24.3, 21), 2.3, 0.6, solid(GOLD, "PillarCap"))
		Parts.disc(am, at(R, s * 11, 0.3, 21), 2.6, 0.6, solid(GOLD, "PillarFoot"))
		Parts.light(pillar, MYTHIC, 16, 1.5)
	end
	heroPanel(am, along(R, 0, 11.5, ROOM_D - 0.55, TO_ENTRANCE), 20.4, 18, MYTHIC:Lerp(WOOD_DARK, 0.35), WOOD_DARK)
	local counter = screen(am, "MythicCounter", along(R, 0, 18.5, ROOM_D - 0.8, TO_ENTRANCE), 16, 5, GOLD)
	local odds = screen(am, "MythicOdds", along(R, 0, 11.7, ROOM_D - 0.8, TO_ENTRANCE), 10, 5.4, MYTHIC)
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

	-- Locker (left of the door) and upgrades + creator code (right of the door), on the entrance wall.
	local lm = Parts.model(m, "Locker")
	local lockerScreen = screen(lm, "LockerScreen", along(R, -28, 7.5, -ROOM_D + 0.6, TO_BACK), 14, 8, accent)
	titlePlate(lm, along(R, -28, 13.4, -ROOM_D + 1, TO_BACK), 12, 1.8, "LOCKER", accent)
	local lockerButtons = console(lm, R, -28, -25, TO_BACK, {
		{ Name = "LockerPrev", Label = "◀ PREV", Color = WHITE },
		{ Name = "LockerEquip", Label = "EQUIP", Color = accent },
		{ Name = "LockerNext", Label = "NEXT ▶", Color = WHITE },
	}, accent)
	local mp = at(R, -38.6, 0, -25)
	Parts.disc(lm, mp + up * 0.3, 5.4, 0.6, solid(WOOD_DARK, "Base"))
	Parts.disc(lm, mp + up * 0.7, 4.6, 0.2, deco(accent, "Ring"))
	Parts.disc(lm, mp + up * 2, 3.6, 2.6, { Name = "Chrome", Color = SILVER, Reflectance = 0.45 })
	local lockerPed: BasePart = Parts.disc(lm, mp + up * 3.5, 4.2, 0.4, { Name = "LockerPedestal", Color = WHITE, Reflectance = 0.3 })
	display(lockerPed, mp + up * 6.2)
	roundPanel(lm, along(R, -38.6, 7.5, -ROOM_D + 0.2, TO_BACK), 5.2, 9.8, 0.4, 1, solid(WOOD_DARK, "MirrorFrame"))
	Parts.block(lm, along(R, -38.6, 7.5, -ROOM_D + 0.5, TO_BACK), Vector3.new(4.4, 9, 0.2), {
		Name = "Mirror",
		Color = hex("#DCE6F5"),
		Reflectance = 0.5,
		CanCollide = false,
	})

	local um = Parts.model(m, "Upgrades")
	local upScreen = screen(um, "UpgradeScreen", along(R, 24, 7.5, -ROOM_D + 0.6, TO_BACK), 10, 6, accent)
	titlePlate(um, along(R, 24, 12.6, -ROOM_D + 1, TO_BACK), 10, 1.8, "UPGRADES", accent)
	local upButtons = console(um, R, 24, -25, TO_BACK, {
		{ Name = "Power", Label = "POWER", Color = C.North },
		{ Name = "Control", Label = "CONTROL", Color = C.West },
		{ Name = "Bounce", Label = "BOUNCE", Color = C.South },
	}, accent)

	local upgradeButtons: { [string]: BasePart } = { Power = upButtons[1], Control = upButtons[2], Bounce = upButtons[3] }

	local crm = Parts.model(m, "CreatorKiosk")
	local creatorScreen = screen(crm, "CreatorScreen", along(R, 36, 7.5, -ROOM_D + 0.6, TO_BACK), 8, 5, accent)
	titlePlate(crm, along(R, 36, 11.4, -ROOM_D + 1, TO_BACK), 8.5, 1.6, "CREATOR CODE", accent)

	return {
		SkinPedestals = skins,
		CratePedestals = cratePeds,
		CrateScreens = crateScreens,
		Locker = {
			Pedestal = lockerPed,
			Screen = lockerScreen,
			Prev = lockerButtons[1],
			Equip = lockerButtons[2],
			Next = lockerButtons[3],
		},
		Upgrades = {
			Screen = upScreen,
			Buttons = upgradeButtons,
		},
		CreatorKiosk = { Screen = creatorScreen },
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
	heroPanel(m, along(R, 0, 15.3, ROOM_D - 0.55, TO_ENTRANCE), 34, 12.6, accent:Lerp(WOOD_DARK, 0.3), WOOD)
	local rotation = screen(m, "RotationSign", along(R, 0, 15.5, ROOM_D - 0.8, TO_ENTRANCE), 28, 9, accent)

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
local function buildBoard(parent: Instance, F: CFrame, stat: string, medal: Color3, accent: Color3): LobbyTypes.Board
	local m = Parts.model(parent, "Board" .. stat)
	-- vx: viewer's right when facing the wall; dist: distance out from the wall.
	local function v(vx: number, y: number, dist: number): CFrame
		return F * CFrame.new(-vx, y, -dist)
	end
	heroPanel(m, v(1, 12.2, 0.05), 28, 18.8, medal:Lerp(WOOD_DARK, 0.45), WOOD)
	local panel = screen(m, "Panel", v(-4, 13, 0.6), 14, 16, medal)
	Parts.roundedBox(m, v(-4, 2, 1.6), Vector3.new(12, 4, 2.2), 0.6, solid(WOOD, "Console"))
	Parts.block(m, v(-4, 3.8, 2.72), Vector3.new(10.6, 0.16, 0.16), deco(accent, "Trim"))
	local function button(vx: number, name: string, label: string): Part
		local b = Parts.cylinder(m, v(vx, 2.4, 2.95) * CFrame.Angles(PI / 2, 0, 0), 0.5, 2.2, solid(WOOD_DARK, name))
		Parts.cylinder(m, v(vx, 2.4, 2.75) * CFrame.Angles(PI / 2, 0, 0), 0.1, 2.6, deco(accent, "ButtonRing"))
		text(m, v(vx, 2.4, 3.26), 1.8, 1.8, label, accent, WOOD_DARK)
		return b
	end
	local prev = button(-8.5, "Prev", "◀")
	local nxt = button(0.5, "Next", "▶")
	local period = roundPanel(m, v(-4, 2.4, 2.95), 4.4, 1.6, 0.5, 0.8, solid(WHITE, "Period"))
	period.Name = "Period"
	text(m, v(-4, 2.4, 3.26), 4, 1.3, "PERIOD", WOOD_DARK, nil, false)
	-- Stepped podium with a nameplate on its front.
	local pc = v(9.5, 0, 5)
	Parts.trimmedSlab(m, pc * CFrame.new(0, 0.5, 0), Vector3.new(8, 1, 8), 1.6, WOOD_DARK, accent)
	Parts.trimmedSlab(m, pc * CFrame.new(0, 1.6, 0), Vector3.new(6, 1.2, 6), 1.2, WALL, medal)
	Parts.roundedBox(m, pc * CFrame.new(0, 3.4, 0), Vector3.new(4.4, 2.4, 4.4), 0.5, solid(WOOD, "Column"))
	local podium = Parts.roundedBox(m, pc * CFrame.new(0, 4.8, 0), Vector3.new(4.8, 0.4, 4.8), 1, solid(medal, "Podium"))
	podium.Name = "Podium"
	display(podium, (pc * CFrame.new(0, 8, 0)).Position)
	Parts.light(podium, medal, 12, 1)
	local plateCf = pc * CFrame.new(0, 3.4, -2.31)
	local plate = Parts.block(m, plateCf, Vector3.new(3.3, 1.6, 0.2), { Name = "Nameplate", Color = SCREEN, CanCollide = false })
	outline(m, plateCf, 3.3, 1.6, medal)
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
		Wins = buildBoard(m, along(R, -1, 0, ROOM_D, TO_ENTRANCE), "Wins", GOLD, accent),
		Coins = buildBoard(m, along(R, -ROOM_W, 0, 0, TO_PLUS_X), "Coins", SILVER, accent),
		Sabotages = buildBoard(m, along(R, ROOM_W, 0, 0, TO_MINUS_X), "Sabotages", BRONZE, accent),
	}
	-- Central trophy on a limestone medallion.
	local tm = Parts.model(m, "Trophy")
	local c = at(R, 0, 0, 0)
	local up = Vector3.yAxis
	Parts.disc(tm, c + up * 0.02, 17.2, 0.08, deco(accent, "MedallionRing"))
	Parts.disc(tm, c + up * 0.04, 16, 0.08, deco(WALL2, "Medallion"))
	Parts.disc(tm, c + up * 0.6, 6, 1.2, solid(WOOD_DARK, "Base"))
	Parts.disc(tm, c + up * 0.9, 6.3, 0.2, deco(accent, "BaseGlow"))
	Parts.disc(tm, c + up * 1.5, 4.4, 0.6, solid(WOOD, "Step"))
	Parts.disc(tm, c + up * 3, 1.8, 2.4, solid(GOLD, "Stem"))
	Parts.disc(tm, c + up * 4.4, 3.2, 0.5, solid(GOLD, "Collar"))
	local cup = Parts.disc(tm, c + up * 6.2, 5, 3.1, solid(GOLD, "Cup"))
	for _, s in { -1, 1 } do
		Parts.hoop(tm, CFrame.new(c + Vector3.new(s * 2.9, 6.4, 0)), 1.1, 0.35, 0.35, 10, solid(GOLD, "Handle"))
	end
	Parts.ball(tm, c + up * 8.7, 2.2, solid(WHITE, "Ball"))
	Parts.light(cup, GOLD, 16, 1.2)
	return { Boards = boards }
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
	local hub = Parts.model(model, "Hub")
	buildPlaza(hub)
	buildWall(hub)
	buildFountain(hub)
	for _, quad in QUADS do
		buildGate(hub, quad)
		buildHall(model, quad)
	end
	buildScenery(model, rng)

	local northRoom, northR = buildRoomShell(model, QUADS[1], "MATCHMAKING", true)
	local eastRoom, eastR = buildRoomShell(model, QUADS[2], "MEGA SHOP", true)
	local southRoom, southR = buildRoomShell(model, QUADS[3], "PRACTICE RANGE", false)
	local westRoom, westR = buildRoomShell(model, QUADS[4], "LEADERBOARDS", true)

	local spawn = buildSpawn(model)
	local sign, stand = buildDirectory(model)
	local dailyScreen, dailyButton = buildDaily(model)

	local lobby: LobbyTypes.Lobby = {
		Model = model,
		Spawn = spawn,
		SpawnCFrame = CFrame.lookAt(Vector3.new(0, 3, -25), Vector3.new(0, 3, 0)),
		Directory = { Sign = sign, StandPoint = stand },
		Daily = { Screen = dailyScreen, Button = dailyButton },
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

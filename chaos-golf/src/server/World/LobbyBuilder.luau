--!strict
-- Code-built lobby hub: a circular glass-domed hall with a tiered fountain,
-- neon floor paths and four themed rooms (N Matchmaking, E Shop, S Practice,
-- W Leaderboards). Geometry only: services attach prompts, SurfaceGuis and
-- logic through the LobbyTypes.Lobby contract returned by build().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local LobbyTypes = require(script.Parent:WaitForChild("LobbyTypes"))

type Props = Parts.Props

local LobbyBuilder = {}

-- Palette -------------------------------------------------------------------

local C = Config.Colors
local hex = Color3.fromHex

local WALL = hex("#E6EAF2")
local WALL2 = hex("#D5DCE8")
local NAVY = hex("#1B2033")
local NAVY2 = hex("#262C45")
local TILE_A = hex("#C9D1E3")
local TILE_B = hex("#BCC5D9")
local SEAM = hex("#AAB4CB")
local SCREEN = hex("#141828")
local WHITE = hex("#F4F6FA")
local BORDER = hex("#EEF1F7")
local GOLD = C.Gold
local SILVER = hex("#C9D3E6")
local BRONZE = hex("#D9895B")
local WATER = hex("#7FE3FF")
local DEEP_WATER = hex("#0E4C78")
local NEON_WHITE = hex("#EAF6FF")
local MYTHIC = hex("#FF2D55")
local LANE_GREEN = hex("#3BB273")

local NEON = Enum.Material.Neon
local PI = math.pi

local ACCENT: { [string]: Color3 } = {
	North = C.North,
	East = C.East,
	South = C.South,
	West = C.West,
}

-- Dimensions (floor top is Y = 0, fountain at the origin) ---------------------

local LOBBY_R = 80
local WALL_T = 3
local WALL_H = 45
local ARCH_HALF = 13 -- half width of the archway gap in the lobby wall
local ARCH_H = 22
local ROOM_DIST = 120
local ROOM_W = 44 -- half width
local ROOM_D = 32 -- half depth
local ROOM_H = 30
local HALL_HALF = 12
local NEAR_WALL = ROOM_DIST - ROOM_D -- axial distance of a room's entrance wall (88)

-- Yaw offsets for along(): which way a part's LookVector points in a quadrant/room frame.
local TO_BACK = 0 -- away from the lobby
local TO_ENTRANCE = PI -- back toward the lobby
local TO_PLUS_X = -PI / 2
local TO_MINUS_X = PI / 2

-- Small helpers -------------------------------------------------------------

local function solid(color: Color3, name: string?): Props
	return { Color = color, Name = name }
end

local function glow(color: Color3, name: string?): Props
	return { Color = color, Material = NEON, CanCollide = false, CanQuery = false, Name = name }
end

local function deco(color: Color3, name: string?): Props
	return { Color = color, CanCollide = false, CanQuery = false, Name = name }
end

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

local function accentAt(deg: number): Color3
	local keys = { "North", "East", "South", "West" }
	local i = math.floor(((deg + 45) % 360) / 90) + 1
	return ACCENT[keys[i]]
end

-- Upright panel with rounded corners in its face plane (cf's LookVector faces the viewer).
local function roundPanel(parent: Instance, cf: CFrame, w: number, h: number, depth: number, radius: number, props: Props?): Part
	return Parts.roundedBox(parent, cf * CFrame.Angles(PI / 2, 0, 0), Vector3.new(w, depth, h), radius, props)
end

-- Static text on an invisible carrier part (Front = cf's LookVector).
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
		Glow = glowing ~= false,
		Font = font or Config.Font,
		PixelsPerStud = if w > 20 then 20 else 30,
	})
	return p
end

-- Contract screen: dark navy face (Front = cf's LookVector) on a rounded navy
-- frame with a thin neon outline. Returns the screen part.
local function screen(parent: Instance, name: string, cf: CFrame, w: number, h: number, accent: Color3): BasePart
	local m = Parts.model(parent, name)
	roundPanel(m, cf * CFrame.new(0, 0, 0.35), w + 1, h + 1, 0.5, 0.6, solid(NAVY, "Frame"))
	local e = 0.16
	Parts.block(m, cf * CFrame.new(0, h / 2 + e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), glow(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 - e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), glow(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(w / 2 + e / 2, 0, 0), Vector3.new(e, h, 0.2), glow(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(-w / 2 - e / 2, 0, 0), Vector3.new(e, h, 0.2), glow(accent, "Edge"))
	return Parts.block(m, cf, Vector3.new(w, h, 0.2), { Name = name, Color = SCREEN, CanCollide = false })
end

-- Navy title plate with neon typography (cf = plate front centre, facing the viewer).
local function titlePlate(parent: Instance, cf: CFrame, w: number, h: number, str: string, accent: Color3)
	local m = Parts.model(parent, "Title")
	roundPanel(m, cf * CFrame.new(0, 0, 0.5), w, h, 1, math.min(1.4, h / 3), solid(NAVY, "Plate"))
	local r = math.min(1.4, h / 3)
	Parts.block(m, cf * CFrame.new(0, h / 2 + 0.12, 0.5), Vector3.new(w - 2 * r, 0.24, 1.1), glow(accent, "Edge"))
	Parts.block(m, cf * CFrame.new(0, -h / 2 - 0.12, 0.5), Vector3.new(w - 2 * r, 0.24, 1.1), glow(accent, "Edge"))
	text(m, cf * CFrame.new(0, 0, -0.08), w - 2, h - 0.8, str, accent, NAVY)
end

local function display(part: BasePart, worldPos: Vector3)
	local a = Instance.new("Attachment")
	a.Name = "Display"
	a.CFrame = part.CFrame:ToObjectSpace(CFrame.new(worldPos))
	a.Parent = part
end

-- Flat floor pad: navy disc flush with the floor plus a neon edge ring.
local function pad(parent: Instance, name: string, pos: Vector3, diameter: number, accent: Color3): BasePart
	Parts.disc(parent, pos + Vector3.new(0, -0.03, 0), diameter + 0.6, 0.14, glow(accent, name .. "Ring"))
	local p = Parts.disc(parent, pos + Vector3.new(0, -0.04, 0), diameter, 0.2, { Name = name, Color = NAVY2, CanCollide = false })
	p:SetAttribute("Radius", diameter / 2)
	return p
end

-- Round showcase pedestal (cylinder stack with a neon ring). Returns the cap.
local function roundPedestal(parent: Instance, name: string, pos: Vector3, ring: Color3, capColor: Color3?, lift: number?): BasePart
	local m = Parts.model(parent, name)
	Parts.disc(m, pos + Vector3.new(0, 0.25, 0), 4.6, 0.5, solid(NAVY2, "Base"))
	Parts.disc(m, pos + Vector3.new(0, 0.6, 0), 4.0, 0.2, glow(ring, "Ring"))
	Parts.disc(m, pos + Vector3.new(0, 1.65, 0), 3.4, 2.3, solid(WALL, "Column"))
	local cap = Parts.disc(m, pos + Vector3.new(0, 2.975, 0), 3.9, 0.35, solid(capColor or WHITE, name))
	display(cap, pos + Vector3.new(0, 3.15 + (lift or 2.5), 0))
	return cap
end

-- Rounded bench (decor).
local function bench(parent: Instance, cf: CFrame, accent: Color3)
	local m = Parts.model(parent, "Bench")
	Parts.block(m, cf * CFrame.new(0, 0.6, 0), Vector3.new(5, 1.2, 1.2), solid(NAVY, "Leg"))
	Parts.trimmedSlab(m, cf * CFrame.new(0, 1.55, 0), Vector3.new(7, 0.7, 2.4), 0.8, WALL, accent)
end

-- Lobby floor ---------------------------------------------------------------

local function buildFloor(parent: Instance)
	local f = Parts.model(parent, "Floor")
	Parts.disc(f, Vector3.new(0, -1, 0), LOBBY_R * 2, 2, solid(TILE_B, "Base"))
	-- Concentric bands: each disc sits 0.02 above the previous one.
	local bands = {
		{ D = 148.4, Color = NAVY2 },
		{ D = 147, Color = TILE_A },
		{ D = 89.4, Color = NAVY2 },
		{ D = 88, Color = TILE_B },
		{ D = 44.4, Color = NAVY2 },
		{ D = 43, Color = TILE_A },
	}
	for i, b in bands do
		Parts.disc(f, Vector3.new(0, i * 0.02 - 0.1, 0), b.D, 0.2, deco(b.Color, "Band"))
	end
	-- Radial tile seams (offset from the compass axes so they never meet a path).
	for i = 0, 15 do
		local deg = (i + 0.5) * 22.5
		Parts.beam(f, polar(45.2, deg, 0.04), polar(73.2, deg, 0.04), 0.35, 0.04, deco(SEAM, "Seam"))
	end
	for i = 0, 7 do
		local deg = 22.5 + i * 45
		Parts.beam(f, polar(22.7, deg, 0.08), polar(43.6, deg, 0.08), 0.35, 0.04, deco(SEAM, "Seam"))
	end
end

-- Lobby wall ----------------------------------------------------------------

type Quad = {
	Key: string,
	Frame: CFrame, -- at the fountain, LookVector toward the room
	Color: Color3,
	Arch: string, -- archway title
	Letter: string,
	PathEnd: number, -- axial distance where the neon path stops
}

local QUADS: { Quad } = {
	{ Key = "North", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, -1)), Color = C.North, Arch = "MATCHMAKING", Letter = "N", PathEnd = ROOM_DIST },
	{ Key = "East", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0)), Color = C.East, Arch = "SHOP", Letter = "E", PathEnd = ROOM_DIST },
	{ Key = "South", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1)), Color = C.South, Arch = "▲ PRACTICE", Letter = "S", PathEnd = NEAR_WALL + 3.5 },
	{ Key = "West", Frame = CFrame.lookAt(Vector3.zero, Vector3.new(-1, 0, 0)), Color = C.West, Arch = "LEADERBOARDS", Letter = "W", PathEnd = ROOM_DIST - 8.5 },
}

local function buildWall(parent: Instance)
	local m = Parts.model(parent, "Wall")
	local rMid = LOBBY_R + WALL_T / 2
	local rOut = LOBBY_R + WALL_T
	local alpha = math.deg(math.asin(ARCH_HALF / LOBBY_R))
	local perQuarter = 10
	local step = (90 - 2 * alpha) / perQuarter
	local w = 2 * rOut * math.tan(math.rad(step / 2)) + 0.1
	local wIn = 2 * LOBBY_R * math.tan(math.rad(step / 2)) + 0.2
	for q = 0, 3 do
		for i = 0, perQuarter - 1 do
			local deg = q * 90 + alpha + (i + 0.5) * step
			local accent = accentAt(deg)
			local seg = Parts.model(m, "Segment")
			Parts.block(seg, inward(rMid, deg, (WALL_H - 2) / 2), Vector3.new(w, WALL_H + 2, WALL_T), solid(WALL, "Wall"))
			Parts.block(seg, inward(LOBBY_R - 0.1, deg, 1.1), Vector3.new(wIn, 4.2, 1), solid(NAVY, "Skirting"))
			Parts.block(seg, inward(LOBBY_R - 0.25, deg, 3.4), Vector3.new(wIn, 0.4, 0.6), glow(accent, "Band"))
			Parts.block(seg, inward(LOBBY_R - 0.2, deg, 23), Vector3.new(wIn, 1.6, 0.6), solid(WALL2, "Belt"))
			Parts.block(seg, inward(LOBBY_R - 0.4, deg, 44), Vector3.new(wIn + 0.2, 2, 1.6), solid(NAVY, "Cornice"))
			local strip = Parts.block(seg, inward(LOBBY_R - 0.3, deg, 42.75), Vector3.new(wIn, 0.35, 0.5), glow(NEON_WHITE, "CorniceGlow"))
			if i == 2 or i == perQuarter - 3 then
				Parts.light(strip, NEON_WHITE, 44, 1)
			end
			if i == 0 or i == perQuarter - 1 then
				-- Hero gradient panel beside each archway, in that archway's colour.
				local panel = Parts.block(seg, inward(LOBBY_R - 0.1, deg, 33), Vector3.new(wIn - 2.8, 14, 0.3), deco(WALL2, "Gradient"))
				Parts.gradientFace(panel, Enum.NormalId.Front, accent:Lerp(WALL, 0.15), WALL, 90)
			end
			if i > 0 then
				local jd = q * 90 + alpha + i * step
				Parts.cylinder(seg, CFrame.new(polar(LOBBY_R, jd, 23.1)), 39, 2.2, solid(WALL2, "Pilaster"))
			end
		end
	end
end

local function buildArch(parent: Instance, quad: Quad)
	local m = Parts.model(parent, "Arch" .. quad.Key)
	local q = quad.Frame
	local accent = quad.Color
	local d = LOBBY_R + WALL_T / 2
	-- Wall section above the opening (the ring leaves a gap here).
	Parts.block(m, along(q, 0, (ARCH_H + 0.5 + WALL_H) / 2, d), Vector3.new(ARCH_HALF * 2 + 1, WALL_H - ARCH_H - 0.5, WALL_T), solid(WALL, "Header"))
	Parts.block(m, along(q, 0, 44, LOBBY_R - 0.4), Vector3.new(ARCH_HALF * 2 + 1.5, 2, 1.6), solid(NAVY, "Cornice"))
	Parts.block(m, along(q, 0, 42.75, LOBBY_R - 0.3), Vector3.new(ARCH_HALF * 2 + 1, 0.35, 0.5), glow(NEON_WHITE, "CorniceGlow"))
	-- Framed arch: rounded posts + lintel with accent trims.
	for _, s in { -1, 1 } do
		Parts.roundedBox(m, along(q, s * 12.5, ARCH_H / 2, 80.5), Vector3.new(3, ARCH_H, 5.4), 0.9, solid(NAVY2, "Post"))
		Parts.block(m, along(q, s * 12.5, ARCH_H / 2, 77.72), Vector3.new(0.4, ARCH_H, 0.2), glow(accent, "Trim"))
		Parts.block(m, along(q, s * 10.92, ARCH_H / 2, 80.5), Vector3.new(0.2, ARCH_H, 0.6), glow(accent, "Trim"))
	end
	Parts.roundedBox(m, along(q, 0, ARCH_H + 1.75, 80.5), Vector3.new(28, 3.5, 5.4), 0.9, solid(NAVY2, "Lintel"))
	Parts.block(m, along(q, 0, ARCH_H + 1.75, 77.72), Vector3.new(26, 0.4, 0.2), glow(accent, "Trim"))
	local under = Parts.block(m, along(q, 0, ARCH_H - 0.08, 80.5), Vector3.new(21.8, 0.2, 0.6), glow(accent, "Trim"))
	Parts.light(under, accent, 20, 1.2)
	-- Threshold plate over the lobby / hallway floor seam.
	Parts.block(m, along(q, 0, 0, 80), Vector3.new(22, 0.08, 4.8), deco(NAVY2, "Threshold"))
	-- Title + compass badge facing into the lobby.
	titlePlate(m, along(q, 0, 31.5, 79, TO_ENTRANCE), 24, 6.5, quad.Arch, accent)
	local badge = along(q, 0, 37.6, 79.5, TO_ENTRANCE)
	Parts.cylinder(m, badge * CFrame.Angles(PI / 2, 0, 0), 0.8, 4.4, solid(NAVY, "Badge"))
	Parts.cylinder(m, badge * CFrame.new(0, 0, 0.2) * CFrame.Angles(PI / 2, 0, 0), 0.6, 5, glow(accent, "BadgeRing"))
	text(m, badge * CFrame.new(0, 0, -0.5), 3.2, 3.2, quad.Letter, accent, NAVY)
end

-- Big wall billboard facing the spawn side of the lobby (East/West archways
-- are outside the spawn field of view).
local function billboard(parent: Instance, deg: number, str: string, accent: Color3)
	local m = Parts.model(parent, "Wayfinding")
	local cf = inward(77.6, deg, 22)
	titlePlate(m, cf, 30, 8, str, accent)
	local l = Parts.block(m, cf * CFrame.new(0, -4.6, 0.5), Vector3.new(24, 0.3, 0.4), glow(accent, "Underglow"))
	Parts.light(l, accent, 16, 0.8)
end

-- Glass sky-roof ------------------------------------------------------------
-- Geodesic-style dome: N meridians x K rings, every ring rotated half a step so
-- the panels form a triangulated shell, closed by an apex fan. Ribs on every edge.

local function buildDome(parent: Instance)
	local m = Parts.model(parent, "Dome")
	local glass: Props = {
		Name = "Glass",
		Color = hex("#DCEEFF"),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		Reflectance = 0.2,
		CastShadow = false,
	}
	local ringRib = solid(WHITE, "Rib")
	local diagRib = solid(NAVY2, "Rib")
	local N, K = 20, 6
	local radius = LOBBY_R + WALL_T / 2
	local squash = 0.75
	local apex = Vector3.new(0, WALL_H + radius * squash, 0)
	local function vert(k: number, i: number): Vector3
		if k >= K then
			return apex
		end
		local e = math.rad(k * 90 / K)
		return polar(radius * math.cos(e), (i + 0.5 * k) * 360 / N, WALL_H + radius * squash * math.sin(e))
	end
	for k = 0, K - 1 do
		for i = 0, N - 1 do
			local a, b, c = vert(k, i), vert(k, i + 1), vert(k + 1, i)
			Parts.triangle(m, a, b, c, 0.3, glass)
			Parts.rod(m, a, b, if k == 0 then 1.2 else 0.9, if k == 0 then diagRib else ringRib)
			Parts.rod(m, a, c, 0.7, diagRib)
			if k < K - 1 then
				local dd = vert(k + 1, i + 1)
				Parts.triangle(m, c, dd, b, 0.3, glass)
				Parts.rod(m, c, b, 0.7, diagRib)
			end
		end
	end
	Parts.disc(m, apex, 5, 0.9, solid(NAVY, "Hub"))
	Parts.disc(m, apex - Vector3.new(0, 0.5, 0), 3.2, 0.2, glow(NEON_WHITE, "HubGlow"))
end

-- Central fountain ----------------------------------------------------------

local function waterEmitter(anchor: BasePart, cf: CFrame, rate: number, speed: NumberRange, life: NumberRange, size: NumberSequence, spread: number, gravity: number): ParticleEmitter
	local a = Instance.new("Attachment")
	a.Name = "Water"
	a.CFrame = anchor.CFrame:ToObjectSpace(cf)
	a.Parent = anchor
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(C.West, hex("#0050FF"))
	e.LightEmission = 0.6
	e.LightInfluence = 0.2
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

local function buildFountain(parent: Instance)
	local m = Parts.model(parent, "Fountain")
	local cyan = C.West
	-- Step plinth with a neon edge.
	Parts.disc(m, Vector3.new(0, 0.19, 0), 30.2, 0.1, glow(cyan, "StepGlow"))
	Parts.disc(m, Vector3.new(0, 0.1, 0), 29.6, 0.5, solid(NAVY2, "Step"))
	-- Collecting bowl: solid body, rim ring, rounded cap, neon trim, water surface.
	Parts.disc(m, Vector3.new(0, 0.6, 0), 24.2, 1.2, solid(DEEP_WATER, "BowlBody"))
	Parts.flatRing(m, Vector3.new(0, 0.95, 0), 12.3, 1.4, 1.9, 28, solid(WALL, "Rim"))
	Parts.flatRing(m, Vector3.new(0, 2.05, 0), 12.3, 1.9, 0.3, 28, solid(WHITE, "RimCap"))
	Parts.flatRing(m, Vector3.new(0, 1.55, 0), 13.05, 0.2, 0.25, 28, glow(cyan, "RimGlow"))
	Parts.flatRing(m, Vector3.new(0, 0.55, 0), 13.1, 0.4, 0.5, 28, solid(NAVY, "RimBase"))
	local water = Parts.disc(m, Vector3.new(0, 1.5, 0), 23.6, 0.2, {
		Name = "Water",
		Color = WATER,
		Material = NEON,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	Parts.light(water, cyan, 24, 1.3)
	-- Pedestal column.
	Parts.disc(m, Vector3.new(0, 1.6, 0), 4.2, 0.8, solid(NAVY, "Collar"))
	Parts.disc(m, Vector3.new(0, 3.7, 0), 3, 5, solid(WALL, "Column"))
	Parts.disc(m, Vector3.new(0, 4.2, 0), 3.15, 0.2, glow(cyan, "ColumnGlow"))
	-- Upper basin (radius 4.5, rim at y 7.7).
	Parts.disc(m, Vector3.new(0, 5.9, 0), 6, 0.6, solid(WALL2, "BasinTaper"))
	Parts.disc(m, Vector3.new(0, 6.7, 0), 9, 1, solid(WALL, "Basin"))
	Parts.disc(m, Vector3.new(0, 6.6, 0), 9.3, 0.15, glow(cyan, "BasinGlow"))
	Parts.flatRing(m, Vector3.new(0, 7.45, 0), 4.25, 0.7, 0.5, 18, solid(WHITE, "BasinRim"))
	Parts.disc(m, Vector3.new(0, 7.35, 0), 8, 0.2, {
		Name = "Water",
		Color = WATER,
		Material = NEON,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	-- Top spout.
	Parts.disc(m, Vector3.new(0, 8.8, 0), 1, 3.2, solid(WALL, "Spout"))
	local cap = Parts.ball(m, Vector3.new(0, 10.6, 0), 1.4, solid(WHITE, "SpoutCap"))
	Parts.light(cap, cyan, 14, 1)

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

-- Hallways ------------------------------------------------------------------

local function buildHall(parent: Instance, quad: Quad)
	local m = Parts.model(parent, "Hall" .. quad.Key)
	local q = quad.Frame
	local accent = quad.Color
	-- Floor runs from inside the lobby wall to the room door (same colour as the
	-- lobby rim band, so the small overlap with the lobby disc never shows).
	Parts.block(m, along(q, 0, -0.5, (78 + NEAR_WALL) / 2), Vector3.new(HALL_HALF * 2 + 4, 1, NEAR_WALL - 78), solid(TILE_B, "Floor"))
	for _, s in { -1, 1 } do
		Parts.block(m, along(q, s * (HALL_HALF + 1), (ARCH_H - 1 + 1.5) / 2, 83), Vector3.new(2, ARCH_H + 2.5, 7), solid(WALL, "Wall"))
		Parts.block(m, along(q, s * (HALL_HALF - 0.3), 1.2, 84.6), Vector3.new(0.6, 2.4, 2.8), solid(NAVY, "Skirting"))
		Parts.block(m, along(q, s * (HALL_HALF - 0.25), 2.575, 84.6), Vector3.new(0.5, 0.35, 2.8), glow(accent, "Band"))
	end
	Parts.block(m, along(q, 0, ARCH_H + 0.75, 85.1), Vector3.new(HALL_HALF * 2 + 4, 1.5, 3.8), solid(WALL2, "Ceiling"))
	local strip = Parts.block(m, along(q, 0, ARCH_H - 0.15, 85), Vector3.new(16, 0.2, 1.2), glow(NEON_WHITE, "Light"))
	Parts.light(strip, NEON_WHITE, 18, 1.2, "Surface")
end

-- Room shell ----------------------------------------------------------------
-- Room frame R: centre of the room floor, LookVector away from the lobby.
-- Room-local coordinates (x, y, u): u = +ROOM_D is the back wall, -ROOM_D the entrance.

local function trimRun(m: Instance, R: CFrame, x0: number, u0: number, x1: number, u1: number, nx: number, nu: number, accent: Color3)
	local function run(off: number, y: number, h: number, depth: number, props: Props)
		Parts.beam(m, at(R, x0 + nx * off, y, u0 + nu * off), at(R, x1 + nx * off, y, u1 + nu * off), depth, h, props)
	end
	run(0.3, 1.2, 2.4, 0.6, solid(NAVY, "Skirting"))
	run(0.25, 2.575, 0.35, 0.5, glow(accent, "Band"))
	run(0.5, ROOM_H - 1, 2, 1, solid(NAVY, "Crown"))
	run(0.25, ROOM_H - 2.2, 0.35, 0.5, glow(NEON_WHITE, "CrownGlow"))
end

local function buildRoomShell(parent: Instance, quad: Quad, title: string, checker: boolean): (Model, CFrame)
	local m = Parts.model(parent, quad.Key .. "Room")
	local R = quad.Frame * CFrame.new(0, 0, -ROOM_DIST)
	local accent = quad.Color
	local W, D, H = ROOM_W, ROOM_D, ROOM_H
	local shell = Parts.model(m, "Shell")
	-- Floor (+ large checker tiles 0.02 above it).
	Parts.block(shell, along(R, 0, -0.5, 1), Vector3.new(2 * W + 4, 1, 2 * D + 2), solid(TILE_A, "Floor"))
	if checker then
		for ix = 0, 3 do
			for iu = 0, 3 do
				if (ix + iu) % 2 == 0 then
					Parts.block(shell, along(R, -W + 11 + 22 * ix, 0, -D + 8 + 16 * iu), Vector3.new(22, 0.04, 16), deco(TILE_B, "Tile"))
				end
			end
		end
	end
	Parts.block(shell, along(R, 0, 0, -D + 0.4), Vector3.new(22, 0.08, 2.8), deco(NAVY2, "Threshold"))
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
		Parts.roundedBox(shell, along(R, s * 13, ARCH_H / 2, -D + 0.5), Vector3.new(3, ARCH_H, 3), 0.8, solid(NAVY2, "DoorPost"))
		Parts.block(shell, along(R, s * 13, ARCH_H / 2, -D + 2.05), Vector3.new(0.4, ARCH_H, 0.2), glow(accent, "Trim"))
	end
	Parts.roundedBox(shell, along(R, 0, ARCH_H + 1.25, -D + 0.5), Vector3.new(29, 2.5, 3), 0.8, solid(NAVY2, "DoorLintel"))
	Parts.block(shell, along(R, 0, ARCH_H + 1.25, -D + 2.05), Vector3.new(27, 0.4, 0.2), glow(accent, "Trim"))
	-- Corner columns, ceiling beams and light panels.
	for _, sx in { -1, 1 } do
		for _, su in { -1, 1 } do
			Parts.cylinder(shell, along(R, sx * (W - 1), (H - 2) / 2, su * (D - 1)), H - 2, 3, solid(NAVY2, "Column"))
		end
	end
	for _, u in { -D / 3, D / 3 } do
		Parts.block(shell, along(R, 0, H - 0.6, u), Vector3.new(2 * W, 1.2, 1.4), solid(WALL2, "Beam"))
	end
	for _, x in { -W * 0.6, 0, W * 0.6 } do
		for _, u in { -D / 1.6, 0, D / 1.6 } do
			local panel = Parts.block(shell, along(R, x, H - 0.15, u), Vector3.new(9, 0.2, 4), glow(NEON_WHITE, "CeilingLight"))
			if u ~= 0 then
				Parts.light(panel, NEON_WHITE, 30, 1.3, "Surface")
			end
		end
	end
	-- Room title on the back wall.
	titlePlate(shell, along(R, 0, 24.6, D - 1, TO_ENTRANCE), 44, 5, title, accent)
	return m, R
end

-- Neon floor paths ------------------------------------------------------------

local function buildPaths(parent: Instance)
	local m = Parts.model(parent, "Paths")
	local d0 = 15.1 -- fountain step edge
	for _, quad in QUADS do
		local q = quad.Frame
		local len = quad.PathEnd - d0
		local mid = (d0 + quad.PathEnd) / 2
		Parts.block(m, along(q, 0, 0.08, mid), Vector3.new(2, 0.16, len), glow(quad.Color, "Path" .. quad.Key))
		for _, s in { -1, 1 } do
			Parts.block(m, along(q, s * 1.3, 0.07, mid), Vector3.new(0.6, 0.14, len), deco(BORDER, "Border"))
		end
		Parts.disc(m, at(q, 0, 0.08, quad.PathEnd), 3.2, 0.16, glow(quad.Color, "PathEnd"))
	end
end

-- Spawn, directory sign, daily calendar -----------------------------------------

local SPAWN_POS = Vector3.new(0, 0.5, -25)

local function buildSpawn(parent: Instance): SpawnLocation
	local m = Parts.model(parent, "Spawn")
	Parts.disc(m, Vector3.new(0, 0.13, -25), 9.6, 0.1, glow(NEON_WHITE, "SpawnGlow"))
	Parts.disc(m, Vector3.new(0, 0.14, -25), 9, 0.12, deco(NAVY2, "SpawnPad"))
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

-- Solid (non-neon) 4-way signpost facing the spawn. Arrow directions are as seen
-- from the spawn looking south: +X (East) is to the player's left.
local function buildDirectory(parent: Instance): (BasePart, Vector3)
	local m = Parts.model(parent, "Directory")
	local base = Vector3.new(10, 0, -20)
	local cf = CFrame.lookAt(base, Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z))
	Parts.roundedBox(m, cf * CFrame.new(0, 0.3, 0.6), Vector3.new(5, 0.6, 3), 0.8, solid(NAVY, "Base"))
	Parts.roundedBox(m, cf * CFrame.new(0, 0.7, 0.6), Vector3.new(4.2, 0.2, 2.2), 0.6, solid(WALL2, "BaseCap"))
	Parts.roundedBox(m, cf * CFrame.new(0, 3.2, 0.9), Vector3.new(1.4, 5.8, 1.4), 0.5, solid(NAVY2, "Post"))
	roundPanel(m, cf * CFrame.new(0, 7.6, 0.35), 8.6, 10.2, 0.4, 0.9, solid(NAVY2, "Frame"))
	local sign = Parts.block(m, cf * CFrame.new(0, 7.6, 0), Vector3.new(7.8, 9.4, 0.3), solid(NAVY, "DirectorySign"))
	local head = Parts.block(m, cf * CFrame.new(0, 11.3, -0.22), Vector3.new(7.8, 1.6, 0.15), solid(WHITE, "Header"))
	text(m, head.CFrame * CFrame.new(0, 0, -0.1), 7.4, 1.5, "WHERE TO?", NAVY, nil, false)
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
		local board = Parts.block(m, body, Vector3.new(6.4, 1.55, 0.3), solid(a.Color, "Arrow"))
		if a.Tip ~= 0 then
			local tx = a.Tip * -0.4 + a.Tip * 3.2
			local p1 = (cf * CFrame.new(tx, y + 0.775, -0.3)).Position
			local p2 = (cf * CFrame.new(tx, y - 0.775, -0.3)).Position
			local p3 = (cf * CFrame.new(tx + a.Tip * 0.9, y, -0.3)).Position
			Parts.triangle(m, p1, p2, p3, 0.3, solid(a.Color, "ArrowTip"))
		end
		text(m, board.CFrame * CFrame.new(0, 0, -0.2), 6.2, 1.4, a.Text, WHITE, NAVY, false)
	end
	return sign, (cf * CFrame.new(0, 3, -5)).Position
end

local function buildDaily(parent: Instance): (BasePart, BasePart)
	local m = Parts.model(parent, "Daily")
	local base = Vector3.new(-12, 0, -34)
	local cf = CFrame.lookAt(base, Vector3.new(SPAWN_POS.X, 0, SPAWN_POS.Z))
	Parts.trimmedSlab(m, cf * CFrame.new(0, 0.25, 0.6), Vector3.new(12, 0.5, 3.4), 1, NAVY2, GOLD, { CanCollide = true })
	for _, s in { -1, 1 } do
		Parts.roundedBox(m, cf * CFrame.new(s * 4, 2.5, 0.8), Vector3.new(0.9, 4.2, 0.9), 0.4, solid(NAVY, "Leg"))
	end
	local scr = screen(m, "DailyScreen", cf * CFrame.new(0, 7.5, 0.5), 10, 6, GOLD)
	titlePlate(m, cf * CFrame.new(0, 11.9, 0.3), 10, 1.8, "DAILY REWARDS", GOLD)
	-- Claim button on a pedestal in front of the screen.
	Parts.cylinder(m, cf * CFrame.new(0, 1.5, -3), 3, 2.6, solid(WALL, "ButtonPedestal"))
	Parts.cylinder(m, cf * CFrame.new(0, 3.08, -3), 0.16, 2.9, glow(GOLD, "ButtonRing"))
	local button = Parts.cylinder(m, cf * CFrame.new(0, 3.3, -3), 0.6, 2.1, solid(GOLD, "DailyButton"))
	Parts.light(button, GOLD, 10, 0.8)
	text(m, cf * CFrame.new(0, 1.8, -4.36), 2, 0.9, "CLAIM", NAVY, nil, false)
	return scr, button
end

-- Neon outline hugging a w x h face centred on cf.
local function outline(parent: Instance, cf: CFrame, w: number, h: number, color: Color3)
	local e = 0.16
	Parts.block(parent, cf * CFrame.new(0, h / 2 + e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), glow(color, "Edge"))
	Parts.block(parent, cf * CFrame.new(0, -h / 2 - e / 2, 0), Vector3.new(w + 2 * e, e, 0.2), glow(color, "Edge"))
	Parts.block(parent, cf * CFrame.new(w / 2 + e / 2, 0, 0), Vector3.new(e, h, 0.2), glow(color, "Edge"))
	Parts.block(parent, cf * CFrame.new(-w / 2 - e / 2, 0, 0), Vector3.new(e, h, 0.2), glow(color, "Edge"))
end

-- Gradient hero panel (plain block so the gradient sits on its Front face).
local function heroPanel(parent: Instance, cf: CFrame, w: number, h: number, top: Color3, bottom: Color3)
	local p = Parts.block(parent, cf, Vector3.new(w, h, 0.1), deco(bottom, "HeroPanel"))
	Parts.gradientFace(p, Enum.NormalId.Front, top, bottom, 90)
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
		roundPanel(p, along(R, x, 11.75, ROOM_D - 0.25, TO_ENTRANCE), 19.5, 17.5, 0.5, 2, solid(NAVY, "Backdrop"))
		heroPanel(p, along(R, x, 11.75, ROOM_D - 0.55, TO_ENTRANCE), 17.5, 15.5, col:Lerp(NAVY, 0.3), NAVY2)
		-- Plinth + hoop frame + force-field film.
		Parts.trimmedSlab(p, along(R, x, 0.4, 29, TO_ENTRANCE), Vector3.new(19, 0.8, 4.6), 1.2, NAVY2, col)
		local hc = along(R, x, 8.6, 29, TO_ENTRANCE)
		Parts.hoop(p, hc, 7.2, 1.4, 2.2, 20, solid(NAVY2, "Frame"))
		Parts.hoop(p, hc, 6.35, 0.3, 2.4, 20, glow(col, "FrameGlow"))
		Parts.hoop(p, hc * CFrame.new(0, 0, -1.15), 7.2, 0.35, 0.15, 20, glow(col, "FrameEdge"))
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
			Parts.block(p, along(R, x + s * 4, 19.6, 30.5), Vector3.new(0.6, 0.6, 1.8), solid(NAVY, "Bracket"))
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
		Parts.disc(p, at(R, x, 0.02, 19), 14.8, 0.08, glow(col, "BubbleRing"))
		Parts.disc(p, at(R, x, 0.04, 19), 13.6, 0.08, deco(NAVY2, "BubbleFloor"))
		portals[key] = { Bubble = bubble, Sign = sign }
	end

	-- Voting enclave on the west wall: three holographic screens + floor pads.
	local vm = Parts.model(m, "Voting")
	local votes: { LobbyTypes.VoteSign } = {}
	for i = 1, 3 do
		local u = (i - 2) * 12
		local cf = along(R, -42.2, 6.8, u, TO_PLUS_X)
		Parts.trimmedSlab(vm, along(R, -42, 0.5, u, TO_PLUS_X), Vector3.new(7, 1, 2.4), 0.8, NAVY2, accent)
		for _, s in { -1, 1 } do
			Parts.rod(vm, (cf * CFrame.new(s * 3, -5.8, 0.3)).Position, (cf * CFrame.new(s * 3, -3.9, 0.3)).Position, 0.35, glow(accent, "Beam"))
		end
		Parts.block(vm, cf * CFrame.new(0, 0, 0.3), Vector3.new(11, 8, 0.3), {
			Name = "HoloFrame",
			Color = NAVY,
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
	Parts.trimmedSlab(km, kcf * CFrame.new(0, 0.3, 0), Vector3.new(6, 0.6, 3.6), 0.9, NAVY2, accent)
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
	Parts.roundedBox(m, cf * CFrame.new(0, 1.6, 0), Vector3.new(9, 3.2, 2.2), 0.6, solid(NAVY2, "Desk"))
	Parts.block(m, cf * CFrame.new(0, 2.95, -1.12), Vector3.new(7.6, 0.16, 0.16), glow(accent, "Trim"))
	local out: { BasePart } = {}
	for i, b in buttons do
		-- cf's +X is the user's left (the user faces the console's front).
		local bx = (2 - i) * 3
		Parts.cylinder(m, cf * CFrame.new(bx, 3.24, 0), 0.08, 2.3, glow(b.Color, "ButtonRing"))
		local part = Parts.cylinder(m, cf * CFrame.new(bx, 3.45, 0), 0.5, 1.9, solid(b.Color, b.Name))
		table.insert(out, part)
		text(m, cf * CFrame.new(bx, 1.7, -1.16), 2.8, 1.1, b.Label, WHITE, NAVY, false)
	end
	return out
end

local function buildEast(room: Model, R: CFrame)
	local m = Parts.model(room, "Shop")
	local accent = C.East

	-- 12 coin-shop skin pedestals in a U around the room centre, open toward the entrance.
	local sm = Parts.model(m, "SkinPedestals")
	Parts.disc(sm, at(R, 0, 0.02, -2), 35.2, 0.08, glow(accent, "MedallionRing"))
	Parts.disc(sm, at(R, 0, 0.04, -2), 34, 0.08, deco(TILE_B, "Medallion"))
	local skins: { BasePart } = {}
	for i = 1, 12 do
		local theta = math.rad(-125 + (i - 1) * 250 / 11)
		local pos = at(R, 14 * math.sin(theta), 0, -2 + 14 * math.cos(theta))
		table.insert(skins, roundPedestal(sm, "SkinPedestal" .. i, pos, accent))
	end

	-- Mythic shrine: isolated alcove in the middle of the back wall.
	local am = Parts.model(m, "MythicShrine")
	for _, s in { -1, 1 } do
		Parts.roundedBox(am, along(R, s * 11, 12, 26.5), Vector3.new(1.5, 24, 11), 0.75, solid(NAVY2, "Partition"))
		Parts.block(am, along(R, s * 11, 24.05, 26.75), Vector3.new(0.5, 0.1, 10.5), glow(GOLD, "PartitionGlow"))
		local pillar = Parts.cylinder(am, along(R, s * 11, 12, 21), 24, 1.7, glow(MYTHIC, "Pillar"))
		Parts.disc(am, at(R, s * 11, 24.3, 21), 2.3, 0.6, solid(GOLD, "PillarCap"))
		Parts.disc(am, at(R, s * 11, 0.3, 21), 2.6, 0.6, solid(GOLD, "PillarFoot"))
		Parts.light(pillar, MYTHIC, 16, 1.5)
	end
	heroPanel(am, along(R, 0, 11.5, ROOM_D - 0.55, TO_ENTRANCE), 20.4, 18, MYTHIC:Lerp(NAVY, 0.35), NAVY)
	local counter = screen(am, "MythicCounter", along(R, 0, 18.5, ROOM_D - 0.8, TO_ENTRANCE), 16, 5, GOLD)
	local odds = screen(am, "MythicOdds", along(R, 0, 11.7, ROOM_D - 0.8, TO_ENTRANCE), 10, 5.4, MYTHIC)
	local base = at(R, 0, 0, 26)
	local up = Vector3.yAxis
	Parts.disc(am, base + up * 0.25, 11.4, 0.3, glow(GOLD, "StepGlow"))
	Parts.disc(am, base + up * 0.3, 11, 0.6, solid(NAVY, "Step"))
	Parts.disc(am, base + up * 0.8, 8.3, 0.2, glow(MYTHIC, "StepGlow"))
	Parts.disc(am, base + up * 0.9, 8, 0.6, solid(hex("#8E1B35"), "Step"))
	Parts.disc(am, base + up * 2.4, 4.6, 2.4, solid(NAVY, "Column"))
	Parts.disc(am, base + up * 2.4, 4.8, 0.3, glow(GOLD, "ColumnGlow"))
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
			Parts.trimmedSlab(cm, along(R, x, 0.3, 25, TO_ENTRANCE), Vector3.new(5.4, 0.6, 5.4), 1.2, NAVY, col)
			cratePeds[id] = roundPedestal(cm, "Crate" .. id, at(R, x, 0.6, 25), col, NAVY2)
			crateScreens[id] = screen(cm, "CrateScreen" .. id, along(R, x, 11, ROOM_D - 0.8, TO_ENTRANCE), 9, 7, col)
			titlePlate(cm, along(R, x, 16.2, ROOM_D - 1, TO_ENTRANCE), 9.5, 1.8, string.upper(if crate then crate.Name else id), col)
		end
	end

	-- Game pass pedestals along the north (local -x) wall.
	local pm = Parts.model(m, "Passes")
	local passPeds: { [string]: BasePart } = {}
	for i, key in Config.GamePassOrder do
		local cf = along(R, -38, 0, -14 + (i - 1) * 9, TO_PLUS_X)
		Parts.trimmedSlab(pm, cf * CFrame.new(0, 0.3, 0), Vector3.new(5, 0.6, 5), 1, NAVY, GOLD)
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
		Parts.trimmedSlab(km, cf * CFrame.new(0, 0.3, 0), Vector3.new(5, 0.6, 4.4), 1, NAVY, GOLD)
		local body = Parts.roundedBox(km, cf * CFrame.new(0, 2.1, 0), Vector3.new(4, 3, 3.4), 0.7, solid(WALL, key))
		body.Name = key
		for c = 1, i + 1 do
			local pos = (cf * CFrame.new(((c % 2) - 0.5) * 0.3, 3.6 + (c - 0.5) * 0.36, 0)).Position
			Parts.disc(km, pos, 2.2, 0.34, solid(GOLD, "Coin"))
		end
		local product: { Name: string, Coins: number? }? = (Config.DevProducts :: any)[key]
		local label = if product then string.upper(product.Name) .. "\n" .. commas(product.Coins or 0) .. " COINS" else key
		text(km, cf * CFrame.new(0, 2.2, -1.76), 3.4, 2.2, label, NAVY, nil, false)
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
	Parts.disc(lm, mp + up * 0.3, 5.4, 0.6, solid(NAVY, "Base"))
	Parts.disc(lm, mp + up * 0.7, 4.6, 0.2, glow(accent, "Ring"))
	Parts.disc(lm, mp + up * 2, 3.6, 2.6, { Name = "Chrome", Color = SILVER, Reflectance = 0.45 })
	local lockerPed: BasePart = Parts.disc(lm, mp + up * 3.5, 4.2, 0.4, { Name = "LockerPedestal", Color = WHITE, Reflectance = 0.3 })
	display(lockerPed, mp + up * 6.2)
	roundPanel(lm, along(R, -38.6, 7.5, -ROOM_D + 0.2, TO_BACK), 5.2, 9.8, 0.4, 1, solid(NAVY, "MirrorFrame"))
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
		Parts.roundedBox(gantry, along(R, -half + k * pitch, 5.5, u0 - 0.4), Vector3.new(0.9, 11, 0.9), 0.3, solid(NAVY2, "Post"))
	end
	Parts.roundedBox(gantry, along(R, 0, 11.4, u0 - 0.4), Vector3.new(2 * half + 1.4, 0.8, 1.4), 0.4, solid(NAVY, "Beam"))
	local beamGlow = Parts.block(gantry, along(R, 0, 11.1, u0 - 1.15), Vector3.new(2 * half - 1, 0.16, 0.12), glow(accent, "BeamGlow"))
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
			Parts.block(lm, origin * CFrame.new(s * (W / 2 + 0.4), 1.26, -L / 2), Vector3.new(0.5, 0.12, L), glow(accent, "RailGlow"))
		end
		Parts.block(lm, origin * CFrame.new(0, 1.5, -(L + 0.5)), Vector3.new(pitch, 3, 1), solid(NAVY2, "BackWall"))
		Parts.block(lm, origin * CFrame.new(0, 3.06, -(L + 0.5)), Vector3.new(pitch, 0.12, 0.6), glow(accent, "BackGlow"))
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
	heroPanel(m, along(R, 0, 15.3, ROOM_D - 0.55, TO_ENTRANCE), 34, 12.6, accent:Lerp(NAVY, 0.3), NAVY2)
	local rotation = screen(m, "RotationSign", along(R, 0, 15.5, ROOM_D - 0.8, TO_ENTRANCE), 28, 9, accent)

	-- Token kiosk on the west (local +x) side.
	local tm = Parts.model(m, "TokenKiosk")
	local tokenScreen = screen(tm, "TokenScreen", along(R, ROOM_W - 0.6, 7.5, 6, TO_MINUS_X), 12, 6, accent)
	titlePlate(tm, along(R, ROOM_W - 1, 12.4, 6, TO_MINUS_X), 12, 1.8, "TOKEN SHOP", accent)
	Parts.trimmedSlab(tm, along(R, 38, 0.3, 6, TO_MINUS_X), Vector3.new(5.4, 0.6, 5.4), 1.2, NAVY, accent)
	local tokenCrate = roundPedestal(tm, "TokenCrate", at(R, 38, 0.6, 6), accent, NAVY2)
	local tokenSkins: { BasePart } = {}
	for i, u in { -8, -2.5, 14.5, 20 } do
		table.insert(tokenSkins, roundPedestal(tm, "TokenSkin" .. i, at(R, 37.5, 0, u), accent))
	end

	-- Replay-tutorial pad near the entrance on the east (local -x) side, plus seating.
	local tut = pad(m, "TutorialPad", at(R, -35, 0, -24), 8, accent)
	titlePlate(m, along(R, -ROOM_W + 1, 7, -24, TO_PLUS_X), 10, 2.4, "REPLAY TUTORIAL", accent)
	local badge = along(R, -ROOM_W + 0.5, 10.6, -24, TO_PLUS_X)
	Parts.cylinder(m, badge * CFrame.Angles(PI / 2, 0, 0), 0.6, 3, solid(NAVY, "Badge"))
	Parts.cylinder(m, badge * CFrame.new(0, 0, 0.1) * CFrame.Angles(PI / 2, 0, 0), 0.5, 3.4, glow(accent, "BadgeRing"))
	text(m, badge * CFrame.new(0, 0, -0.4), 2.2, 2.2, "?", accent, NAVY)
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
	heroPanel(m, v(1, 12.2, 0.05), 28, 18.8, medal:Lerp(NAVY, 0.45), NAVY2)
	local panel = screen(m, "Panel", v(-4, 13, 0.6), 14, 16, medal)
	Parts.roundedBox(m, v(-4, 2, 1.6), Vector3.new(12, 4, 2.2), 0.6, solid(NAVY2, "Console"))
	Parts.block(m, v(-4, 3.8, 2.72), Vector3.new(10.6, 0.16, 0.16), glow(accent, "Trim"))
	local function button(vx: number, name: string, label: string): Part
		local b = Parts.cylinder(m, v(vx, 2.4, 2.95) * CFrame.Angles(PI / 2, 0, 0), 0.5, 2.2, solid(NAVY, name))
		Parts.cylinder(m, v(vx, 2.4, 2.75) * CFrame.Angles(PI / 2, 0, 0), 0.1, 2.6, glow(accent, "ButtonRing"))
		text(m, v(vx, 2.4, 3.26), 1.8, 1.8, label, accent, NAVY)
		return b
	end
	local prev = button(-8.5, "Prev", "◀")
	local nxt = button(0.5, "Next", "▶")
	local period = roundPanel(m, v(-4, 2.4, 2.95), 4.4, 1.6, 0.5, 0.8, solid(WHITE, "Period"))
	period.Name = "Period"
	text(m, v(-4, 2.4, 3.26), 4, 1.3, "PERIOD", NAVY, nil, false)
	-- Stepped podium with a nameplate on its front.
	local pc = v(9.5, 0, 5)
	Parts.trimmedSlab(m, pc * CFrame.new(0, 0.5, 0), Vector3.new(8, 1, 8), 1.6, NAVY, accent)
	Parts.trimmedSlab(m, pc * CFrame.new(0, 1.6, 0), Vector3.new(6, 1.2, 6), 1.2, WALL, medal)
	Parts.roundedBox(m, pc * CFrame.new(0, 3.4, 0), Vector3.new(4.4, 2.4, 4.4), 0.5, solid(NAVY2, "Column"))
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
	-- Central trophy on a medallion (the neon path ends at its rim).
	local tm = Parts.model(m, "Trophy")
	local c = at(R, 0, 0, 0)
	local up = Vector3.yAxis
	Parts.disc(tm, c + up * 0.02, 17.2, 0.08, glow(accent, "MedallionRing"))
	Parts.disc(tm, c + up * 0.04, 16, 0.08, deco(TILE_B, "Medallion"))
	Parts.disc(tm, c + up * 0.6, 6, 1.2, solid(NAVY, "Base"))
	Parts.disc(tm, c + up * 0.9, 6.3, 0.2, glow(accent, "BaseGlow"))
	Parts.disc(tm, c + up * 1.5, 4.4, 0.6, solid(NAVY2, "Step"))
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

	local hub = Parts.model(model, "Hub")
	buildFloor(hub)
	buildWall(hub)
	buildDome(hub)
	buildFountain(hub)
	billboard(hub, 135, "◀  SHOP", C.East)
	billboard(hub, 225, "LEADERBOARDS  ▶", C.West)
	for _, quad in QUADS do
		buildArch(hub, quad)
		buildHall(model, quad)
	end
	buildPaths(model)

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
	model.Parent = workspace
	return lobby
end

return LobbyBuilder

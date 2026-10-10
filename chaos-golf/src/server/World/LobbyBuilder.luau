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
local function screen(parent: Instance, name: string, cf: CFrame, w: number, h: number, accent: Color3): Part
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
local function pad(parent: Instance, name: string, pos: Vector3, diameter: number, accent: Color3): Part
	Parts.disc(parent, pos + Vector3.new(0, -0.03, 0), diameter + 0.6, 0.14, glow(accent, name .. "Ring"))
	local p = Parts.disc(parent, pos + Vector3.new(0, -0.04, 0), diameter, 0.2, { Name = name, Color = NAVY2, CanCollide = false })
	p:SetAttribute("Radius", diameter / 2)
	return p
end

-- Round showcase pedestal (cylinder stack with a neon ring). Returns the cap.
local function roundPedestal(parent: Instance, name: string, pos: Vector3, ring: Color3, capColor: Color3?, lift: number?): Part
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

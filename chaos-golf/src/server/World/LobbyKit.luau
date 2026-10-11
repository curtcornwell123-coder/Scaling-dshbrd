--!strict
-- High-detail building kit for the lobby: smooth rings, tori and lathed (turned)
-- surfaces, steel I-beams and columns, club furniture, planters, lights, and
-- textured Beam ribbons for running water. Everything is anchored.

local Parts = require(script.Parent:WaitForChild("Parts"))

type Props = Parts.Props

local LobbyKit = {}

local PI = math.pi
local UP = Vector3.yAxis

local function with(props: Props, name: string): Props
	local p = table.clone(props)
	p.Name = name
	return p
end

-- Rings and turned shapes --------------------------------------------------------

-- Flat annulus band from rIn to rOut between heights y0 and y1 (N blocks; the outer
-- edge is an exact tangent polygon, blocks overlap toward the inside).
function LobbyKit.ring(parent: Instance, center: Vector3, rIn: number, rOut: number, y0: number, y1: number, n: number, props: Props): Model
	local m = Parts.model(parent, props.Name or "Ring")
	local len = 2 * rOut * math.tan(PI / n) + 0.04
	local depth = rOut - rIn
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * 2 * PI
		-- Odd blocks sit 0.012 higher so overlapping faces never z-fight.
		local lift = if i % 2 == 1 then 0.012 else 0
		local cf = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(0, (y0 + y1) / 2 + lift, -(rIn + depth / 2))
		Parts.block(m, cf, Vector3.new(len, y1 - y0, depth), props)
	end
	return m
end

-- Torus: N tangent cylinders (radius R, tube diameter `tube`) with ball joints, at height y.
function LobbyKit.torus(parent: Instance, center: Vector3, radius: number, tube: number, n: number, props: Props, joints: boolean?): Model
	local m = Parts.model(parent, props.Name or "Torus")
	local len = 2 * radius * math.tan(PI / n) + 0.02
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * 2 * PI
		local cf = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
		-- Parts.cylinder puts the axis along cf's Y; tip it onto the tangent (cf's X).
		Parts.cylinder(m, cf * CFrame.Angles(0, 0, PI / 2), len, tube, props)
		if joints ~= false then
			local j = i / n * 2 * PI
			Parts.ball(m, center + Vector3.new(math.sin(j) * radius, 0, -math.cos(j) * radius), tube, props)
		end
	end
	return m
end

-- Surface of revolution through `profile` points (Vector2: X = radius, Y = height),
-- N segments around, each profile step a ring of tilted plates `thickness` thick.
function LobbyKit.lathe(parent: Instance, center: Vector3, profile: { Vector2 }, n: number, thickness: number, props: Props): Model
	local m = Parts.model(parent, props.Name or "Lathe")
	for k = 1, #profile - 1 do
		local p0, p1 = profile[k], profile[k + 1]
		local rMax = math.max(p0.X, p1.X)
		local width = 2 * rMax * math.tan(PI / n) + 0.03
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * 2 * PI
			local d = Vector3.new(math.sin(a), 0, -math.cos(a))
			local t = Vector3.new(math.cos(a), 0, math.sin(a))
			local q0 = center + d * p0.X + UP * p0.Y
			local q1 = center + d * p1.X + UP * p1.Y
			local v = q1 - q0
			if v.Magnitude > 1e-3 then
				local dir = v.Unit
				local normal = dir:Cross(t).Unit
				local cf = CFrame.fromMatrix((q0 + q1) / 2, t, normal)
				Parts.block(m, cf, Vector3.new(width, thickness, v.Magnitude + 0.02), props)
			end
		end
	end
	return m
end

-- Fluted column: core cylinder plus `flutes` slim reeds around it, from y0 to y1.
function LobbyKit.flutedColumn(parent: Instance, base: Vector3, y0: number, y1: number, diameter: number, flutes: number, props: Props)
	local h = y1 - y0
	local mid = base + UP * (y0 + h / 2)
	Parts.cylinder(parent, CFrame.new(mid), h, diameter, with(props, "Shaft"))
	local r = diameter / 2
	local reed = math.max(0.12, 2 * PI * r / flutes * 0.55)
	for i = 0, flutes - 1 do
		local a = i / flutes * 2 * PI
		local p = mid + Vector3.new(math.sin(a) * r, 0, -math.cos(a) * r)
		Parts.cylinder(parent, CFrame.new(p), h - 0.1, reed, with(props, "Reed"))
	end
end

-- Steel ----------------------------------------------------------------------------

-- I-beam between two points (web vertical, flanges top and bottom), `depth` tall.
function LobbyKit.ibeam(parent: Instance, a: Vector3, b: Vector3, depth: number, width: number, props: Props): Model
	local m = Parts.model(parent, "IBeam")
	local dir = b - a
	local len = dir.Magnitude
	local x = dir.Unit
	local y = if math.abs(x.Y) < 0.95 then UP else Vector3.zAxis
	local z = x:Cross(y).Unit
	y = z:Cross(x).Unit
	local cf = CFrame.fromMatrix((a + b) / 2, x, y, z)
	local f = math.max(0.14, depth * 0.12)
	Parts.block(m, cf, Vector3.new(len, depth - 2 * f, math.max(0.14, width * 0.18)), with(props, "Web"))
	Parts.block(m, cf * CFrame.new(0, depth / 2 - f / 2, 0), Vector3.new(len, f, width), with(props, "Flange"))
	Parts.block(m, cf * CFrame.new(0, -depth / 2 + f / 2, 0), Vector3.new(len, f, width), with(props, "Flange"))
	return m
end

-- Round steel column with a base plate and a capital collar, from the floor to `h`.
function LobbyKit.column(parent: Instance, base: Vector3, h: number, diameter: number, props: Props, collar: Props?)
	local m = Parts.model(parent, "Column")
	Parts.cylinder(m, CFrame.new(base + UP * (h / 2)), h, diameter, with(props, "Shaft"))
	local c = collar or props
	Parts.cylinder(m, CFrame.new(base + UP * 0.15), 0.3, diameter + 0.9, with(c, "Plate"))
	Parts.cylinder(m, CFrame.new(base + UP * 0.45), 0.3, diameter + 0.4, with(c, "Plate"))
	Parts.cylinder(m, CFrame.new(base + UP * (h - 0.25)), 0.5, diameter + 0.5, with(c, "Capital"))
	Parts.cylinder(m, CFrame.new(base + UP * 3.2), 0.12, diameter + 0.08, with(c, "Band"))
end

-- Furniture ------------------------------------------------------------------------

export type Palette = {
	Leather: Props,
	Wood: Props,
	Metal: Props, -- dark steel
	Brass: Props,
	Stone: Props, -- marble / quartz tops
	Fabric: Props, -- cushions, rugs
	Lamp: Props, -- emissive shade glass
	Leaf: Props,
	Pot: Props,
	Soil: Props,
}

local function deco(props: Props, name: string): Props
	local p = with(props, name)
	p.CanCollide = false
	p.CanQuery = false
	return p
end

-- Leather cushion: a slab with a rolled front edge (two parts, reads as rounded).
local function cushion(m: Instance, cf: CFrame, w: number, h: number, d: number, props: Props)
	Parts.block(m, cf * CFrame.new(0, 0, h / 4), Vector3.new(w, h, d - h / 2), props)
	Parts.cylinder(m, cf * CFrame.new(0, 0, -d / 2 + h / 2) * CFrame.Angles(0, 0, PI / 2), w, h, props)
end

-- Three-seat leather sofa; cf at floor centre, LookVector = the way a sitter faces.
function LobbyKit.sofa(parent: Instance, cf: CFrame, pal: Palette, width: number?)
	local m = Parts.model(parent, "Sofa")
	local w = width or 8
	local seat = (w - 1.8) / 3
	Parts.block(m, cf * CFrame.new(0, 0.95, 0.15), Vector3.new(w - 1.6, 0.9, 2.9), with(pal.Leather, "Base"))
	for i = 0, 2 do
		local x = (i - 1) * seat
		cushion(m, cf * CFrame.new(x, 1.64, -0.1), seat - 0.08, 0.5, 2.5, deco(pal.Leather, "Cushion"))
		Parts.block(m, cf * CFrame.new(x, 2.5, 1.2), Vector3.new(seat - 0.08, 1.8, 0.7), deco(pal.Leather, "BackCushion"))
		Parts.cylinder(m, cf * CFrame.new(x, 3.4, 1.2) * CFrame.Angles(0, 0, PI / 2), seat - 0.08, 0.7, deco(pal.Leather, "BackRoll"))
	end
	Parts.block(m, cf * CFrame.new(0, 2.3, 1.6), Vector3.new(w - 1.4, 2.9, 0.45), with(pal.Leather, "Back"))
	for _, s in { -1, 1 } do
		Parts.block(m, cf * CFrame.new(s * (w / 2 - 0.45), 1.3, 0.15), Vector3.new(0.9, 1.6, 3.2), with(pal.Leather, "Arm"))
		Parts.cylinder(m, cf * CFrame.new(s * (w / 2 - 0.45), 2.1, 0.15) * CFrame.Angles(PI / 2, 0, 0), 3.2, 0.9, deco(pal.Leather, "ArmRoll"))
		for _, z in { -1.05, 1.35 } do
			Parts.cylinder(m, cf * CFrame.new(s * (w / 2 - 0.6), 0.25, z), 0.5, 0.28, deco(pal.Brass, "Foot"))
		end
	end
end

function LobbyKit.armchair(parent: Instance, cf: CFrame, pal: Palette)
	local m = Parts.model(parent, "Armchair")
	Parts.block(m, cf * CFrame.new(0, 0.95, 0.1), Vector3.new(2.8, 0.9, 2.8), with(pal.Leather, "Base"))
	cushion(m, cf * CFrame.new(0, 1.64, -0.1), 2.6, 0.5, 2.4, deco(pal.Leather, "Cushion"))
	Parts.block(m, cf * CFrame.new(0, 2.35, 1.25), Vector3.new(3.6, 2.4, 0.5), with(pal.Leather, "Back"))
	Parts.cylinder(m, cf * CFrame.new(0, 3.55, 1.25) * CFrame.Angles(0, 0, PI / 2), 3.6, 0.5, deco(pal.Leather, "BackRoll"))
	for _, s in { -1, 1 } do
		Parts.block(m, cf * CFrame.new(s * 1.6, 1.3, 0.1), Vector3.new(0.8, 1.6, 3), with(pal.Leather, "Arm"))
		Parts.cylinder(m, cf * CFrame.new(s * 1.6, 2.1, 0.1) * CFrame.Angles(PI / 2, 0, 0), 3, 0.8, deco(pal.Leather, "ArmRoll"))
		for _, z in { -1, 1.2 } do
			Parts.cylinder(m, cf * CFrame.new(s * 1.45, 0.25, z), 0.5, 0.26, deco(pal.Brass, "Foot"))
		end
	end
end

-- Round coffee table: stone top, brass ring, walnut drum base.
function LobbyKit.coffeeTable(parent: Instance, pos: Vector3, diameter: number, pal: Palette)
	local m = Parts.model(parent, "CoffeeTable")
	Parts.cylinder(m, CFrame.new(pos + UP * 1.55), 0.22, diameter, with(pal.Stone, "Top"))
	Parts.cylinder(m, CFrame.new(pos + UP * 1.4), 0.12, diameter - 0.1, deco(pal.Brass, "Edge"))
	Parts.cylinder(m, CFrame.new(pos + UP * 0.75), 1.3, diameter * 0.45, with(pal.Wood, "Drum"))
	Parts.cylinder(m, CFrame.new(pos + UP * 0.06), 0.12, diameter * 0.6, deco(pal.Brass, "Foot"))
	-- A small stack of books and a brass bowl.
	Parts.block(m, CFrame.new(pos + Vector3.new(-diameter * 0.18, 1.78, 0.2)) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.4, 0.22, 1), deco(pal.Fabric, "Book"))
	Parts.block(m, CFrame.new(pos + Vector3.new(-diameter * 0.18, 1.98, 0.2)) * CFrame.Angles(0, 0.1, 0), Vector3.new(1.2, 0.18, 0.9), deco(pal.Wood, "Book"))
	Parts.cylinder(m, CFrame.new(pos + Vector3.new(diameter * 0.2, 1.82, -0.2)), 0.32, 1.1, deco(pal.Brass, "Bowl"))
end

-- Area rug with a contrasting border (flush with the floor).
function LobbyKit.rug(parent: Instance, cf: CFrame, w: number, d: number, field: Props, border: Props)
	local m = Parts.model(parent, "Rug")
	Parts.block(m, cf * CFrame.new(0, 0.03, 0), Vector3.new(w, 0.06, d), deco(border, "Border"))
	Parts.block(m, cf * CFrame.new(0, 0.05, 0), Vector3.new(w - 1.2, 0.06, d - 1.2), deco(field, "Field"))
	Parts.block(m, cf * CFrame.new(0, 0.06, 0), Vector3.new(w - 2.4, 0.06, d - 2.4), deco(border, "Inlay"))
	Parts.block(m, cf * CFrame.new(0, 0.07, 0), Vector3.new(w - 2.7, 0.06, d - 2.7), deco(field, "Field"))
end

-- Tall ceramic planter with an olive-style tree (many small leaf clusters).
function LobbyKit.planter(parent: Instance, pos: Vector3, pal: Palette, rng: Random, height: number?)
	local m = Parts.model(parent, "Planter")
	local h = height or 7
	LobbyKit.lathe(m, pos, {
		Vector2.new(0.95, 0),
		Vector2.new(1.45, 1.4),
		Vector2.new(1.5, 2.6),
	}, 12, 0.18, deco(pal.Pot, "Pot"))
	Parts.cylinder(m, CFrame.new(pos + UP * 0.6), 1.2, 2.2, with(pal.Pot, "PotCore"))
	Parts.cylinder(m, CFrame.new(pos + UP * 2.45), 0.1, 2.75, deco(pal.Soil, "Soil"))
	local top = pos + UP * h
	Parts.rod(m, pos + UP * 2.4, top - UP * 0.5, 0.32, deco(pal.Wood, "Trunk"))
	for _ = 1, 3 do
		local a = rng:NextNumber(0, 2 * PI)
		local from = pos + UP * rng:NextNumber(h * 0.55, h * 0.75)
		Parts.rod(m, from, from + Vector3.new(math.cos(a) * 1.2, 1.1, math.sin(a) * 1.2), 0.16, deco(pal.Wood, "Branch"))
	end
	for _ = 1, 10 do
		local a = rng:NextNumber(0, 2 * PI)
		local r = rng:NextNumber(0, 1.7)
		local p = top + Vector3.new(math.cos(a) * r, rng:NextNumber(-1.4, 1), math.sin(a) * r)
		Parts.ball(m, p, rng:NextNumber(0.9, 1.5), deco(pal.Leaf, "Leaves"))
	end
end

-- Pendant lamp hanging from the ceiling at `ceilingY` over `pos` (drop = cord length).
function LobbyKit.pendant(parent: Instance, pos: Vector3, ceilingY: number, drop: number, pal: Palette, range: number?)
	local m = Parts.model(parent, "Pendant")
	local y = ceilingY - drop
	Parts.cylinder(m, CFrame.new(Vector3.new(pos.X, ceilingY - 0.08, pos.Z)), 0.16, 0.9, deco(pal.Brass, "Canopy"))
	Parts.rod(m, Vector3.new(pos.X, ceilingY - 0.1, pos.Z), Vector3.new(pos.X, y + 0.9, pos.Z), 0.06, deco(pal.Metal, "Cord"))
	LobbyKit.lathe(m, Vector3.new(pos.X, y, pos.Z), {
		Vector2.new(0.3, 1.0),
		Vector2.new(1.0, 0.6),
		Vector2.new(1.45, 0),
	}, 12, 0.1, deco(pal.Brass, "Shade"))
	local bulb = Parts.ball(m, Vector3.new(pos.X, y + 0.25, pos.Z), 0.75, deco(pal.Lamp, "LampBulb"))
	Parts.light(bulb, Color3.fromRGB(255, 214, 160), range or 18, 0.9)
end

-- Wall sconce on a face (cf = wall surface point, LookVector out of the wall).
function LobbyKit.sconce(parent: Instance, cf: CFrame, pal: Palette)
	local m = Parts.model(parent, "Sconce")
	Parts.block(m, cf * CFrame.new(0, 0, -0.05), Vector3.new(0.5, 1.6, 0.1), deco(pal.Brass, "Plate"))
	Parts.block(m, cf * CFrame.new(0, 0, -0.35), Vector3.new(0.18, 0.18, 0.6), deco(pal.Brass, "Arm"))
	local shade = Parts.cylinder(m, cf * CFrame.new(0, 0.2, -0.7), 1.1, 0.7, deco(pal.Lamp, "LampShade"))
	Parts.light(shade, Color3.fromRGB(255, 210, 150), 10, 0.6)
end

-- Running water -----------------------------------------------------------------------

export type WaterStyle = {
	Color: ColorSequence,
	Transparency: NumberSequence,
	Width0: number,
	Width1: number,
	Speed: number,
	FaceCamera: boolean?,
	Segments: number?,
}

local WATER_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- A textured Beam ribbon from p0 (leaving along dir0) to p1 (arriving along dir1).
-- `side` sets which way the ribbon's width spreads (ignored when it faces the camera).
function LobbyKit.waterBeam(anchor: BasePart, p0: Vector3, dir0: Vector3, p1: Vector3, dir1: Vector3, curve0: number, curve1: number, side: Vector3, style: WaterStyle): Beam
	local function attach(p: Vector3, dir: Vector3): Attachment
		local x = dir.Unit
		local y = (side - x * side:Dot(x))
		if y.Magnitude < 1e-3 then
			y = if math.abs(x.Y) < 0.9 then UP else Vector3.xAxis
		end
		y = y.Unit
		local a = Instance.new("Attachment")
		a.Name = "Water"
		a.CFrame = anchor.CFrame:ToObjectSpace(CFrame.fromMatrix(p, x, y))
		a.Parent = anchor
		return a
	end
	local a0 = attach(p0, dir0)
	local a1 = attach(p1, dir1)
	local beam = Instance.new("Beam")
	beam.Name = "WaterFlow"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.CurveSize0 = curve0
	beam.CurveSize1 = curve1 -- control point sits behind the end, against the arrival direction
	beam.Texture = WATER_TEXTURE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 2.5
	beam.TextureSpeed = style.Speed
	beam.Color = style.Color
	beam.Transparency = style.Transparency
	beam.LightEmission = 0.25
	beam.LightInfluence = 0.75
	beam.Width0 = style.Width0
	beam.Width1 = style.Width1
	beam.FaceCamera = style.FaceCamera == true
	beam.Segments = style.Segments or 14
	beam.Parent = anchor
	return beam
end

-- Particle emitter at a world point on `anchor` (spray, splash, mist).
export type SprayStyle = {
	Rate: number,
	Speed: NumberRange,
	Lifetime: NumberRange,
	Size: NumberSequence,
	Spread: number,
	Gravity: number,
	Transparency: NumberSequence?,
	Color: ColorSequence?,
}

function LobbyKit.spray(anchor: BasePart, cf: CFrame, style: SprayStyle): ParticleEmitter
	local a = Instance.new("Attachment")
	a.Name = "Spray"
	a.CFrame = anchor.CFrame:ToObjectSpace(cf)
	a.Parent = anchor
	local e = Instance.new("ParticleEmitter")
	e.Texture = WATER_TEXTURE
	e.Color = style.Color or ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(190, 225, 240))
	e.LightEmission = 0.2
	e.LightInfluence = 0.85
	e.Transparency = style.Transparency or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = style.Size
	e.Rate = style.Rate
	e.Lifetime = style.Lifetime
	e.Speed = style.Speed
	e.SpreadAngle = Vector2.new(style.Spread, style.Spread)
	e.Acceleration = Vector3.new(0, -style.Gravity, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Parent = a
	return e
end

return LobbyKit

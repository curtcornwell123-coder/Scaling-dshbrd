--!strict
-- Printed golf-ball markings, like a real tour ball. Everything is built from tiny plates
-- tangent to the ball (so text and lines hug the curve) welded to it:
--   * the brand stamp arched across the front, the model line under it,
--   * the play number (and an optional line under it) on the back,
--   * an alignment line / triple track / hazard tape on one side, an emblem on the other,
--   * thin latitude pinstripes or halo bands (opaque balls only),
--   * for glowing skins, a neon core seen through the translucent shell.
-- Every piece is massless, non-colliding and invisible to touches and queries, so physics
-- only ever sees the ball itself. Sizes are authored for a 1.5-stud ball and scale.

local BallPrints = {}

export type Design = {
	Pattern: string, -- "Classic" | "Pinstripe" | "Track" | "Halo" | "Stars" | "Target" | "Hazard"
	Brand: string,
	Model: string,
	Number: string,
	SubNumber: string?,
	NumberInk: Color3, -- the play number under the brand (red on white balls, as real ones)
	Club: string, -- the ribbon on the club crest on the back
	Ink: Color3,
	Accent: Color3,
	BrandFont: Enum.Font,
	TextFont: Enum.Font,
	Emblem: string?, -- a glyph, or "Target" for printed rings
	Core: Color3?,
	Metallic: boolean?, -- pinstripes and bands in foil instead of ink
}

BallPrints.FolderName = "SkinPrints"
BallPrints.CoreName = "SkinCore"

local REF = 1.5
local HAZARD_YELLOW = Color3.fromHex("#F2B705")
local HAZARD_BLACK = Color3.fromHex("#1D1E21")

-- Advance widths of capitals/digits as a share of the line height (bold geometric sans).
local ADVANCE: { [string]: number } = {
	I = 0.33, J = 0.55, L = 0.58, E = 0.6, F = 0.58, T = 0.6, S = 0.62, Z = 0.62, P = 0.64,
	M = 0.88, W = 0.98, O = 0.76, Q = 0.76, G = 0.74, C = 0.7,
	["1"] = 0.5, [" "] = 0.3, ["."] = 0.3, [","] = 0.3, ["-"] = 0.42, ["/"] = 0.45, ["#"] = 0.7,
	["'"] = 0.25, ["&"] = 0.74,
}

local function advance(ch: string): number
	if ADVANCE[ch] then
		return ADVANCE[ch]
	end
	if string.match(ch, "%d") then
		return 0.62
	end
	return if #ch > 1 then 0.95 else 0.7 -- multi-byte glyphs (★ ◆ ♠ ...) are wide
end

local function chars(s: string): { string }
	local out = {}
	for _, code in utf8.codes(s) do
		table.insert(out, utf8.char(code))
	end
	return out
end

type Ctx = { Ball: BasePart, Folder: Folder, R: number, S: number }

local function attach(ctx: Ctx, p: BasePart, offset: CFrame)
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = ctx.Ball.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = ctx.Ball
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = ctx.Folder
end

-- Frame on the ball's surface at (lat, lon) in radians: LookVector points out of the ball,
-- RightVector is "east" as the viewer sees it, UpVector is north. lon 0 = the ball's front.
local function tangent(r: number, lat: number, lon: number, roll: number?): CFrame
	local cl, sl = math.cos(lat), math.sin(lat)
	local co, so = math.cos(lon), math.sin(lon)
	local dir = Vector3.new(-so * cl, sl, -co * cl)
	local east = Vector3.new(-co, 0, so)
	local north = Vector3.new(so * sl, cl, co * sl)
	local cf = CFrame.fromMatrix(dir * r, -east, north)
	if roll then
		cf *= CFrame.Angles(0, 0, roll)
	end
	return cf
end

-- A print plate: an invisible part whose outward face carries a SurfaceGui.
local function plate(ctx: Ctx, lat: number, lon: number, w: number, h: number, pixels: number, roll: number?): Frame
	local t = 0.01 * ctx.S
	local p = Instance.new("Part")
	p.Name = "Print"
	p.Size = Vector3.new(w, h, t)
	p.Transparency = 1
	attach(ctx, p, tangent(ctx.R + 0.0035 * ctx.S - t / 2, lat, lon, roll))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ink"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels / h
	gui.LightInfluence = 1
	gui.MaxDistance = 80
	gui.ClipsDescendants = true
	gui.Parent = p
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	return root
end

local function label(root: Frame, text: string, font: Enum.Font, color: Color3, px: number)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = text
	l.Font = font
	l.TextSize = px
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = root
end

local function bar(root: Frame, y: number, thickness: number, color: Color3)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, y)
	f.Size = UDim2.new(1, 1, thickness, 0)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = root
end

-- Text arched along a line of latitude, centred on `lonDeg`, one plate per `chunk`
-- characters (1 = every letter hugs the curve and sits on its own advance).
local function arcText(ctx: Ctx, text: string, latDeg: number, lonDeg: number, height: number, font: Enum.Font, color: Color3, chunk: number, tracking: number)
	local h = height * ctx.S
	local lat = math.rad(latDeg)
	local rc = ctx.R * math.cos(lat)
	local pieces: { { Text: string, W: number } } = {}
	local cur, curW, n = "", 0, 0
	local function flush()
		if n > 0 then
			table.insert(pieces, { Text = cur, W = curW })
		end
		cur, curW, n = "", 0, 0
	end
	for _, ch in chars(text) do
		cur ..= ch
		curW += (advance(ch) + tracking) * h
		n += 1
		if n >= chunk or ch == " " then
			flush()
		end
	end
	flush()
	local total = 0
	for _, piece in pieces do
		total += piece.W
	end
	local lon = math.rad(lonDeg) - total / rc / 2
	local px = 64
	for _, piece in pieces do
		local mid = lon + piece.W / 2 / rc
		lon += piece.W / rc
		if string.match(piece.Text, "%S") then
			label(plate(ctx, lat, mid, piece.W, h, px), piece.Text, font, color, px)
		end
	end
end

-- A run of plates along the equator on one side: the alignment line, triple track or
-- hazard tape. `kind` picks what each plate shows.
local function sideRun(ctx: Ctx, lonDeg: number, kind: string, ink: Color3, accent: Color3)
	local segs, span = 4, 54
	local h = (if kind == "Line" then 0.06 elseif kind == "Hazard" then 0.13 else 0.16) * ctx.S
	local step = math.rad(span / segs)
	local w = 2 * ctx.R * math.sin(step / 2) * 1.02
	for i = 1, segs do
		local lon = math.rad(lonDeg - span / 2) + (i - 0.5) * step
		local root = plate(ctx, 0, lon, w, h, 48)
		if kind == "Line" then
			bar(root, 0.5, 0.36, ink)
		elseif kind == "Track" then
			bar(root, 0.5, 0.16, ink)
			bar(root, 0.17, 0.09, accent)
			bar(root, 0.83, 0.09, accent)
		else
			local tape = Instance.new("Frame")
			tape.Size = UDim2.fromScale(1, 1)
			tape.BackgroundColor3 = Color3.new(1, 1, 1)
			tape.BorderSizePixel = 0
			tape.Parent = root
			local keys = {}
			local bands = 6
			for b = 0, bands - 1 do
				local c = if b % 2 == 0 then HAZARD_YELLOW else HAZARD_BLACK
				local t0, t1 = b / bands, (b + 1) / bands
				table.insert(keys, ColorSequenceKeypoint.new(if b == 0 then 0 else t0 + 0.001, c))
				table.insert(keys, ColorSequenceKeypoint.new(t1, c))
			end
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(keys)
			g.Rotation = 35
			g.Parent = tape
		end
	end
end

local function emblem(ctx: Ctx, latDeg: number, lonDeg: number, size: number, glyph: string, ink: Color3, accent: Color3, font: Enum.Font)
	local s = size * ctx.S
	local root = plate(ctx, math.rad(latDeg), math.rad(lonDeg), s, s, 64)
	if glyph == "Target" then
		for i, k in { 0.96, 0.66, 0.36 } do
			local ring = Instance.new("Frame")
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(k, k)
			ring.BackgroundTransparency = 1
			ring.Parent = root
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = ring
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 4.5
			stroke.Color = if i == 2 then accent else ink
			stroke.Parent = ring
		end
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromScale(0.14, 0.14)
		dot.BackgroundColor3 = accent
		dot.BorderSizePixel = 0
		dot.Parent = root
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
	else
		label(root, glyph, font, ink, 60)
	end
end

-- Club crest, like a course logo ball: a green diamond with a thin border, a red pin flag in
-- it and a cream ribbon across the bottom carrying the club's name.
local CREST_GREEN = Color3.fromHex("#1F6B4E")
local CREST_RED = Color3.fromHex("#C8282E")
local CREST_CREAM = Color3.fromHex("#F3EDDD")

local function crest(ctx: Ctx, latDeg: number, lonDeg: number, size: number, ink: Color3, club: string)
	local s = size * ctx.S
	local root = plate(ctx, math.rad(latDeg), math.rad(lonDeg), s * 1.25, s, 96)
	local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, rot: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Rotation = rot or 0
		f.Parent = parent
		return f
	end
	-- The diamond is a square turned 45 degrees (sized on the plate's height).
	local d = box(root, 0.5, 0.44, 0.56 / 1.25, 0.56, CREST_GREEN, 45)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = ink
	stroke.Parent = d
	box(root, 0.47, 0.42, 0.025, 0.42, CREST_CREAM) -- pin
	box(root, 0.535, 0.29, 0.1, 0.12, CREST_RED) -- flag
	local ribbon = box(root, 0.5, 0.8, 0.98, 0.24, CREST_CREAM)
	local rs = Instance.new("UIStroke")
	rs.Thickness = 1.5
	rs.Color = ink
	rs.Parent = ribbon
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(0.92, 0.8)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Text = club
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromHex("#2B2620")
	t.Parent = ribbon
end

-- Thin ring round the ball at a latitude: a hair-thin cylinder just outside the surface.
local function ring(ctx: Ctx, latDeg: number, thickness: number, color: Color3, metallic: boolean?)
	local t = thickness * ctx.S
	local y0 = ctx.R * math.sin(math.rad(latDeg))
	local yNear = math.max(0, math.abs(y0) - t / 2)
	local rr = math.sqrt(ctx.R * ctx.R - yNear * yNear) + 0.003 * ctx.S
	local p = Instance.new("Part")
	p.Name = "Stripe"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(t, rr * 2, rr * 2)
	p.Color = color
	p.Material = if metallic then Enum.Material.Foil else Enum.Material.SmoothPlastic
	p.Reflectance = if metallic then 0.25 else 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	attach(ctx, p, CFrame.new(0, y0, 0) * CFrame.Angles(0, 0, math.pi / 2))
end

-- Builds the markings for `design` on `ball` (diameter d). Returns the folder.
function BallPrints.build(ball: BasePart, design: Design, d: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = BallPrints.FolderName
	local ctx: Ctx = { Ball = ball, Folder = folder, R = d / 2, S = d / REF }
	local ink, accent = design.Ink, design.Accent
	local pattern = design.Pattern
	local opaque = design.Core == nil

	if design.Core then
		local core = Instance.new("Part")
		core.Name = BallPrints.CoreName
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.one * d * 0.84
		core.Color = design.Core
		core.Material = Enum.Material.Neon
		core.TopSurface = Enum.SurfaceType.Smooth
		core.BottomSurface = Enum.SurfaceType.Smooth
		attach(ctx, core, CFrame.new())
	end

	-- Front, as on a real ball: the brand wordmark printed flat in ink, the play number
	-- under it (or a limited ball's copy number and edition line).
	local brandH = if (utf8.len(design.Brand) or 0) > 9 then 0.115 else 0.135
	arcText(ctx, design.Brand, 7, 0, brandH, design.BrandFont, ink, 1, 0.05)
	local numH = if #design.Number > 2 then 0.1 else 0.15
	arcText(ctx, design.Number, -12, 0, numH, Enum.Font.GothamBlack, design.NumberInk, 1, 0.04)
	if design.SubNumber then
		arcText(ctx, design.SubNumber, -21, 0, 0.055, design.TextFont, accent, 1, 0.16)
	end

	-- Back: the club crest and the model line under it.
	crest(ctx, 7, 180, 0.3, ink, design.Club)
	arcText(ctx, design.Model, -16, 180, 0.062, design.TextFont, if pattern == "Classic" then ink else accent, 1, 0.14)

	-- Sides: alignment aid on the left (-X), emblem on the right (+X).
	local sideKind = if pattern == "Track" then "Track" elseif pattern == "Hazard" then "Hazard" else "Line"
	sideRun(ctx, 90, sideKind, ink, accent)
	if design.Emblem then
		emblem(ctx, 0, 270, if design.Emblem == "Target" then 0.26 else 0.22, design.Emblem, ink, accent, design.BrandFont)
	elseif pattern == "Hazard" then
		sideRun(ctx, 270, "Hazard", ink, accent)
	end
	if pattern == "Target" then
		emblem(ctx, 90, 0, 0.3, "Target", ink, accent, design.BrandFont)
		emblem(ctx, -90, 0, 0.3, "Target", ink, accent, design.BrandFont)
	elseif pattern == "Stars" then
		for i = 0, 3 do
			emblem(ctx, 33, 45 + i * 90, 0.1, "★", accent, accent, design.BrandFont)
			emblem(ctx, -33, i * 90, 0.1, "★", accent, accent, design.BrandFont)
		end
	end

	-- Latitude rings (a cylinder would show through a translucent shell, so opaque only).
	if opaque then
		if pattern == "Pinstripe" then
			ring(ctx, 25, 0.016, accent, design.Metallic)
			ring(ctx, -25, 0.016, accent, design.Metallic)
		elseif pattern == "Halo" then
			for _, s in { -1, 1 } do
				ring(ctx, s * 27, 0.024, accent, design.Metallic)
				ring(ctx, s * 23, 0.009, accent, design.Metallic)
			end
		end
	end

	folder.Parent = ball
	return folder
end

return BallPrints

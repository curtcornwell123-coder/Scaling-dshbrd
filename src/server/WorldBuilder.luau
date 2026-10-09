--!strict
-- Builds the map: a conveyor down the middle and player bases on both sides.
-- Everything is made from parts so the place works from an empty Baseplate.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldBuilder = {}

export type PlotParts = {
	Index: number,
	Model: Model,
	CFrame: CFrame, -- center of the floor; LookVector points at the conveyor
	Pedestals: { BasePart },
	CollectPad: BasePart,
	LockPad: BasePart,
	Lasers: { BasePart },
	WallFolders: { [number]: Folder },
	Stories: { [number]: Folder }, -- floors 2+; parented only once bought
	Stairs: { { Carpet: Folder, Base: CFrame } }, -- Base: bottom-front-center of each staircase
	Floors: { BasePart }, -- ground floor + every upper slab
	LightSets: { [number]: { Ceiling: Folder, Posts: Folder } },
	Prestige: Folder, -- rebirth decorations (SetPrestige)
	Vault: Folder, -- the room under the base (walls restyled by SetWallLevel)
	VaultPodiums: { BasePart },
	VaultSpawn: CFrame, -- where you land inside the vault
	HatchCFrame: CFrame, -- where you come back up
	Roof: Model, -- parented once the base reaches Config.StandardWallLevels
	RoofPivot: CFrame, -- where the roof sits on top of the ground floor
	SignPost: BasePart,
	UpgradePost: BasePart,
	LockButton: BasePart, -- the owner's lock / unlock button by the door
	LockButtonLabel: TextLabel,
	UpgradeLabel: TextLabel,
	OwnerLabel: TextLabel,
	PendingLabel: TextLabel,
	LockLabel: TextLabel,
	SpawnCFrame: CFrame,
}

export type World = {
	Plots: { PlotParts },
	ConveyorStart: Vector3,
	ConveyorEnd: Vector3,
	CarriedFolder: Folder,
	ConveyorFolder: Folder,
	ShopPosition: Vector3, -- center of the shop tent
	StatuePosition: Vector3, -- where the event statue stands
	NextStatuePosition: Vector3, -- the next event's statue, right beside it
	SellPosition: Vector3, -- the Sell Stand's counter
}

local PLOT_SIZE = 60
local PLOT_DISTANCE = 100 -- from the conveyor to each plot's center
local PLOT_SPACING = 100
local SIGN_HEIGHT = 26 -- the name sign's height above the ground floor
local ENTRANCE_WIDTH = 16
local FLOOR_TOP = 1
local WALL_COLOR = Color3.fromRGB(140, 140, 145) -- every base's fence is the same grey
local CAVE_DEPTH = 30
local SIGN_STUDS_PER_UNIT = 0.035 -- billboard sizes below are in "units"; 400 units = 14 studs
local TUNNEL_TOP = 16.5 -- roughly where the carved tunnel's ceiling is
local BARRIER_RADIUS = 420 -- the fence around the map (with an invisible wall)
local PATH_COLOR = Color3.fromRGB(232, 214, 172)
local PATH_EDGE = Color3.fromRGB(190, 165, 125)

local PLOT_COLORS = {
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(120, 180, 255),
	Color3.fromRGB(140, 230, 140),
	Color3.fromRGB(255, 210, 110),
	Color3.fromRGB(200, 140, 255),
	Color3.fromRGB(110, 230, 220),
	Color3.fromRGB(255, 160, 210),
	Color3.fromRGB(230, 230, 230),
}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, size: Vector2, offset: Vector3, text: string, color: Color3): TextLabel
	local gui = Instance.new("BillboardGui")
	-- Sized in studs, so signs shrink with distance like real signs.
	gui.Size = UDim2.fromScale(size.X * SIGN_STUDS_PER_UNIT, size.Y * SIGN_STUDS_PER_UNIT)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 400
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee

	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.Parent = gui
	return l
end

local STORY_HEIGHT = 20
local DOOR_HEIGHT = 10
local STAIR_STEPS = 14
local STAIR_WIDTH = 8
local STAIR_RUN = 30 -- stairs climb from z = -26 (front) to z = 4
local WALL_THICKNESS = 2
local LASER_COUNT = 12
local GLASS_COLOR = Color3.fromRGB(80, 150, 255)

-- Ramps alternate sides: floor 1 -> 2 on the left, floor 2 -> 3 on the right...
local function rampSide(fromStory: number): number
	return if fromStory % 2 == 1 then -1 else 1
end

local function storyBase(story: number): number
	return FLOOR_TOP + (story - 1) * STORY_HEIGHT
end

-- Pedestal spots on upper floors, kept clear of the ramps on both sides.
local UPPER_PEDESTALS = {
	{ -15, 8 }, { -5, 8 }, { 5, 8 }, { 15, 8 },
	{ -15, 20 }, { -5, 20 }, { 5, 20 }, { 15, 20 },
	{ -5, -8 }, { 5, -8 },
}

-- One straight wall. `cf` is the bottom-center with local X running along the
-- wall. Walls 5+ studs tall get blue tinted windows set into real openings.
export type WallStyle = {
	Color: Color3,
	Material: Enum.Material,
	Glass: Color3,
	GlassNeon: boolean?,
	Corn: boolean?, -- Corny's own skin: corn cobs, gold trim, and his logo on the windows
	Trim: Color3?, -- glowing strips along the window sills and tops
	Moon: boolean?, -- Ace's own skin: a crescent moon over the base
	TopSign: string?, -- role skins: a glowing sign floating over the base
	Clover: boolean?, -- Ace's own skin: four-leaf clovers on the pillars
	Pattern: string?, -- "Checker", "Stripes", "Dots", "Argyle" or "Smileys" on floors and wall bands
	PatternColor: Color3?,
	PatternRainbow: boolean?, -- every stripe/tile its own color
}

local CORN_YELLOW = Color3.fromRGB(255, 205, 40)
local CORN_GOLD = Color3.fromRGB(250, 196, 60)
local CORN_LEAF = Color3.fromRGB(70, 185, 110)
local CORN_LEAF_DARK = Color3.fromRGB(40, 140, 85)
local CORN_NAVY = Color3.fromRGB(20, 28, 48)

local function decoration(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = block(parent, name, size, cframe, color, material)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- A standing corn cob with two leaves, its back against a wall at `cf`
-- (cf's -Z points out of the wall).
local function cornCob(folder: Instance, cf: CFrame, height: number)
	local width = height * 0.38
	local body = cf * CFrame.new(0, 0, -width / 2)
	decoration(folder, "CornCob", Vector3.new(height * 0.8, width, width), body * CFrame.Angles(0, 0, math.pi / 2), CORN_YELLOW, Enum.Material.Pebble).Shape = Enum.PartType.Cylinder
	decoration(folder, "CornTip", Vector3.one * width, body * CFrame.new(0, height * 0.4, 0), CORN_YELLOW, Enum.Material.Pebble).Shape = Enum.PartType.Ball
	for _, side in { -1, 1 } do
		-- Wedges slope up toward the cob, like husk leaves peeling away.
		decoration(folder, "CornLeaf", Vector3.new(0.2, height * 0.55, width * 0.7),
			body * CFrame.new(side * width * 0.3, -height * 0.25, -width * 0.15) * CFrame.Angles(0, 0, side * 0.35) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0),
			if side < 0 then CORN_LEAF_DARK else CORN_LEAF, Enum.Material.SmoothPlastic).Shape = Enum.PartType.Wedge
	end
end

-- The Corny Games logo (gold ring, corn cob, leaves) on one face of a window.
-- Small enough in the middle that you can still see in past it.
local function cornLogo(window: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CornLogo"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = window

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.62, 0.62)
	ring.BackgroundColor3 = CORN_NAVY
	ring.BackgroundTransparency = 0.15
	ring.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = ring
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = CORN_GOLD
	stroke.Thickness = 8
	stroke.Parent = ring

	local function shape(name: string, position: UDim2, size: UDim2, color: Color3, radius: UDim, rotation: number?, z: number?): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = position
		f.Size = size
		f.Rotation = rotation or 0
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z or 1
		f.Parent = ring
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = f
		return f
	end

	local cob = shape("Cob", UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.34, 0.58), CORN_YELLOW, UDim.new(0.5, 0), 0, 1)
	for row = 0, 4 do
		for column = 0, 2 do
			local kernel = Instance.new("Frame")
			kernel.AnchorPoint = Vector2.new(0.5, 0.5)
			kernel.Position = UDim2.fromScale(0.25 + column * 0.25, 0.16 + row * 0.15)
			kernel.Size = UDim2.fromScale(0.2, 0.11)
			kernel.BackgroundColor3 = Color3.fromRGB(255, 225, 90)
			kernel.BorderSizePixel = 0
			kernel.ZIndex = 2
			kernel.Parent = cob
		end
	end
	shape("LeafLeft", UDim2.fromScale(0.38, 0.72), UDim2.fromScale(0.2, 0.42), CORN_LEAF_DARK, UDim.new(1, 0), -30, 3)
	shape("LeafRight", UDim2.fromScale(0.62, 0.72), UDim2.fromScale(0.2, 0.42), CORN_LEAF_DARK, UDim.new(1, 0), 30, 3)
	shape("LeafMiddle", UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.16, 0.3), CORN_LEAF, UDim.new(1, 0), 0, 4)
end

-- A four-leaf clover with its back against a wall at `cf` (cf's -Z points
-- out of the wall), for Ace's skin.
local CLOVER_GREEN = Color3.fromRGB(70, 200, 110)
local function clover(folder: Instance, cf: CFrame, size: number)
	local leaf = size * 0.5
	local out = cf * CFrame.new(0, 0, -0.15)
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		-- Each leaf is two overlapping discs, so it reads as a heart.
		for _, turn in { -0.35, 0.35 } do
			local a = angle + turn
			local p = out * CFrame.new(math.cos(a) * leaf * 0.55, math.sin(a) * leaf * 0.55, 0)
			local disc = decoration(folder, "CloverLeaf", Vector3.new(0.2, leaf, leaf), p * CFrame.Angles(0, math.rad(90), 0), CLOVER_GREEN, Enum.Material.SmoothPlastic)
			disc.Shape = Enum.PartType.Cylinder
		end
	end
	local center = decoration(folder, "CloverCenter", Vector3.one * leaf * 0.4, out * CFrame.new(0, 0, -0.1), Color3.fromRGB(255, 130, 210), Enum.Material.Neon)
	center.Shape = Enum.PartType.Ball
	decoration(folder, "CloverStem", Vector3.new(0.18, size * 0.6, 0.18), out * CFrame.new(size * 0.12, -size * 0.55, 0) * CFrame.Angles(0, 0, math.rad(15)), Color3.fromRGB(45, 140, 75), Enum.Material.SmoothPlastic)
end

-- A pattern painted on one face of a part (floors and wall bands), as a
-- light SurfaceGui instead of many parts. `cell` is the tile size in studs.
local function addPattern(part: BasePart, face: Enum.NormalId, pattern: string, color: Color3, rainbow: boolean?, cell: number)
	local w, h = part.Size.X, part.Size.Y
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		w, h = part.Size.X, part.Size.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		w, h = part.Size.Z, part.Size.Y
	end
	local cols = math.clamp(math.floor(w / cell + 0.5), 1, 30)
	local rows = math.clamp(math.floor(h / cell + 0.5), 1, 30)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Pattern"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 1
	gui.Parent = part
	local function tint(i: number): Color3
		return if rainbow then Color3.fromHSV((i % 7) / 7, 0.65, 1) else color
	end
	local function tile(x: number, y: number, sw: number, sh: number, c: Color3, round: boolean?, rotation: number?)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(sw, sh)
		f.Rotation = rotation or 0
		f.BackgroundColor3 = c
		f.BackgroundTransparency = 0.1
		f.BorderSizePixel = 0
		f.Parent = gui
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = f
		end
	end
	-- A yellow smiley: face, two eyes and the bottom half of a ring for a grin.
	local function smiley(x: number, y: number, sw: number, sh: number)
		tile(x, y, sw, sh, Color3.fromRGB(255, 215, 50), true)
		local ink = Color3.fromRGB(60, 40, 20)
		for _, side in { -1, 1 } do
			tile(x + side * sw * 0.18, y - sh * 0.14, sw * 0.12, sh * 0.18, ink, true)
		end
		local clip = Instance.new("Frame")
		clip.AnchorPoint = Vector2.new(0.5, 0)
		clip.Position = UDim2.fromScale(x, y + sh * 0.05)
		clip.Size = UDim2.fromScale(sw * 0.6, sh * 0.3)
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Parent = gui
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 1)
		ring.Position = UDim2.fromScale(0.5, 1)
		ring.Size = UDim2.fromScale(1, 2)
		ring.BackgroundTransparency = 1
		ring.Parent = clip
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Color = ink
		stroke.Thickness = 3
		stroke.Parent = ring
	end
	if pattern == "Stripes" then
		for c = 0, cols - 1, 2 do
			tile((c + 0.5) / cols, 0.5, 1 / cols, 1, tint(c // 2))
		end
		return
	end
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x, y = (c + 0.5) / cols, (r + 0.5) / rows
			if pattern == "Checker" and (r + c) % 2 == 0 then
				tile(x, y, 1 / cols, 1 / rows, tint(r + c))
			elseif pattern == "Dots" then
				tile(x, y, 0.5 / cols, 0.5 / rows, tint(r * 3 + c), true)
			elseif pattern == "Argyle" and (r + c) % 2 == 0 then
				tile(x, y, 0.6 / cols, 0.6 / rows, tint(r + c), false, 45)
			elseif pattern == "Smileys" and (r + c) % 2 == 0 then
				smiley(x, y, 0.7 / cols, 0.7 / rows)
			end
		end
	end
end

-- A glowing crescent moon facing the front of the base (`cf` is its center).
-- `aura`: a halo, sparkles and light around it (for a fully upgraded base).
local MOON_COLOR = Color3.fromRGB(255, 228, 246)
local MOON_PINK = Color3.fromRGB(255, 110, 210)
local function crescentMoon(folder: Instance, cf: CFrame, radius: number, aura: boolean)
	local thickest = radius * 0.5
	local segments = 40
	local from, to = math.rad(70), math.rad(290) -- opens to the right
	for i = 0, segments - 1 do
		local t = (i + 0.5) / segments
		local angle = from + (to - from) * t
		local width = math.max(0.4, thickest * math.sin(math.pi * t))
		local length = radius * (to - from) / segments * 1.3
		decoration(folder, "Moon", Vector3.new(width, length, 1.6), cf * CFrame.Angles(0, 0, angle) * CFrame.new(radius - width / 2, 0, 0), MOON_COLOR, Enum.Material.Neon)
	end
	-- A couple of little stars beside it
	for _, star in { { 0.95, 0.55, 0.9 }, { 1.25, -0.2, 0.6 }, { 0.7, -0.75, 0.5 } } do
		local s = decoration(folder, "MoonStar", Vector3.one * star[3] * 1.4, cf * CFrame.new(radius * star[1], radius * star[2], 0), MOON_PINK, Enum.Material.Neon)
		s.Shape = Enum.PartType.Ball
	end
	local light = Instance.new("PointLight")
	light.Color = MOON_PINK
	light.Range = radius * 3
	light.Brightness = if aura then 3 else 1.2
	light.Parent = folder:FindFirstChild("Moon")
	if aura then
		-- Halo disc behind the moon, and pink sparkles drifting around it.
		local halo = decoration(folder, "MoonHalo", Vector3.new(0.3, radius * 3, radius * 3), cf * CFrame.new(0, 0, 1.2) * CFrame.Angles(0, math.pi / 2, 0), MOON_PINK, Enum.Material.Neon)
		halo.Shape = Enum.PartType.Cylinder
		halo.Transparency = 0.78
		local ring = decoration(folder, "MoonRing", Vector3.new(0.4, radius * 3.4, radius * 3.4), cf * CFrame.new(0, 0, 1.4) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(255, 30, 170), Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.55
		local field = decoration(folder, "MoonAura", Vector3.new(radius * 3.2, radius * 3.2, radius * 1.5), cf, MOON_PINK, Enum.Material.SmoothPlastic)
		field.Transparency = 1
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(MOON_PINK, Color3.fromRGB(255, 255, 255))
		sparkles.LightEmission = 1
		sparkles.Rate = 18
		sparkles.Lifetime = NumberRange.new(1.5, 3)
		sparkles.Speed = NumberRange.new(0.5, 2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Shape = Enum.ParticleEmitterShape.Box
		sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		sparkles.Parent = field
	end
end

local function wallSegment(folder: Instance, cf: CFrame, length: number, height: number, style: WallStyle)
	local function piece(name: string, x: number, y: number, width: number, h: number): Part
		local p = block(folder, name, Vector3.new(width, h, WALL_THICKNESS), cf * CFrame.new(x, y + h / 2, 0), style.Color, style.Material)
		return p
	end

	if height < 5 then
		piece("Wall", 0, 0, length, height)
		return
	end

	-- Big picture windows so everyone can see the brainrots inside: a low
	-- sill, a thin band at the top, and only slim pillars between panes.
	local sill = math.clamp(height * 0.12, 1, 2.5)
	local head = height - math.clamp(height * 0.08, 1, 2)
	local band = piece("WallBottom", 0, 0, length, sill)
	local pattern = style.Pattern
	if pattern then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			addPattern(band, face, pattern, style.PatternColor or Color3.new(1, 1, 1), style.PatternRainbow, math.max(1, sill))
		end
	end
	piece("WallTop", 0, head, length, height - head)
	local trim = style.Trim
	if trim then
		-- Trim along the window sills and tops, on both sides.
		for _, y in { sill, head } do
			decoration(folder, "Trim", Vector3.new(length, 0.35, WALL_THICKNESS + 0.3), cf * CFrame.new(0, y, 0), trim, if style.Corn then Enum.Material.Foil else Enum.Material.Neon)
		end
	end
	-- Corn cobs on the pillars between windows, on both sides of the wall.
	-- Pillar decorations, on both sides of the wall: corn (Corny), clovers (Ace).
	local function cobs(x: number)
		if not style.Corn and not style.Clover then
			return
		end
		local cobHeight = math.min(4, (head - sill) * 0.3)
		for _, side in { -1, 1 } do
			local facing = CFrame.Angles(0, if side < 0 then 0 else math.pi, 0)
			if style.Corn then
				cornCob(folder, cf * CFrame.new(x, sill + (head - sill) / 2, side * WALL_THICKNESS / 2) * facing, cobHeight)
			else
				for _, t in { 0.3, 0.72 } do
					clover(folder, cf * CFrame.new(x, sill + (head - sill) * t, side * WALL_THICKNESS / 2) * facing, math.min(2.2, cobHeight * 0.6))
				end
			end
		end
	end

	local count = math.max(1, math.floor(length / 12))
	local spacing = length / count
	local windowWidth = math.max(4, spacing - 1.6)
	local left = -length / 2
	for i = 1, count do
		local center = -length / 2 + spacing * (i - 0.5)
		local gapStart = center - windowWidth / 2
		if gapStart - left > 0.01 then
			piece("WallPillar", (left + gapStart) / 2, sill, gapStart - left, head - sill)
			cobs((left + gapStart) / 2)
		end
		local glass = block(folder, "Window", Vector3.new(windowWidth, head - sill, 0.4), cf * CFrame.new(center, sill + (head - sill) / 2, 0), style.Glass, if style.GlassNeon then Enum.Material.Neon else Enum.Material.Glass)
		-- Clear enough to see right through, with just a tint of the skin's color.
		glass.Transparency = if style.GlassNeon then 0.6 else 0.7
		glass.Reflectance = 0.1
		if style.Corn and i % 2 == 1 then
			cornLogo(glass, Enum.NormalId.Front)
			cornLogo(glass, Enum.NormalId.Back)
		end
		left = center + windowWidth / 2
	end
	if length / 2 - left > 0.01 then
		piece("WallPillar", (left + length / 2) / 2, sill, length / 2 - left, head - sill)
		cobs((left + length / 2) / 2)
	end
end

-- The vault room, deep under a base. Its walls, floor and ceiling follow the
-- base's wall skin (SetWallLevel restyles every part named Vault*Wall /
-- VaultFloor / VaultCeiling). Podiums sit in two curved rows facing the door.
local VAULT_FLOOR = -46 -- floor top, below the plot floor
local VAULT_SIZE = 44
local VAULT_HEIGHT = 16
local function buildVault(model: Instance, at: (number, number, number) -> CFrame): (Folder, { BasePart })
	local vault = Instance.new("Folder")
	vault.Name = "Vault"
	vault.Parent = model
	local half = VAULT_SIZE / 2
	block(vault, "VaultFloor", Vector3.new(VAULT_SIZE, 1, VAULT_SIZE), at(0, VAULT_FLOOR - 0.5, 0), Color3.fromRGB(60, 60, 70), Enum.Material.Marble)
	block(vault, "VaultCeiling", Vector3.new(VAULT_SIZE, 1, VAULT_SIZE), at(0, VAULT_FLOOR + VAULT_HEIGHT + 0.5, 0), Color3.fromRGB(60, 60, 70), Enum.Material.Marble)
	for _, side in { -1, 1 } do
		block(vault, "VaultWall", Vector3.new(2, VAULT_HEIGHT, VAULT_SIZE + 4), at(side * (half + 1), VAULT_FLOOR + VAULT_HEIGHT / 2, 0), Color3.fromRGB(80, 80, 90), Enum.Material.Marble)
		block(vault, "VaultWall", Vector3.new(VAULT_SIZE, VAULT_HEIGHT, 2), at(0, VAULT_FLOOR + VAULT_HEIGHT / 2, side * (half + 1)), Color3.fromRGB(80, 80, 90), Enum.Material.Marble)
	end
	-- A big round vault door on the back wall, for the look.
	local door = block(vault, "VaultDoor", Vector3.new(1, 11, 11), at(0, VAULT_FLOOR + 7, half - 0.2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
	door.Shape = Enum.PartType.Cylinder
	door.CanCollide = false
	for k = 0, 5 do
		local angle = k / 6 * math.pi * 2
		local spoke = block(vault, "VaultDoorSpoke", Vector3.new(0.5, 5, 0.5), at(0, VAULT_FLOOR + 7, half - 1) * CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.6, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
		spoke.CanCollide = false
	end
	local hub = block(vault, "VaultDoorHub", Vector3.new(1.4, 2.2, 2.2), at(0, VAULT_FLOOR + 7, half - 1.1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
	hub.Shape = Enum.PartType.Cylinder
	hub.CanCollide = false
	-- Lights
	for _, spot in { { -10, -10 }, { 10, -10 }, { -10, 10 }, { 10, 10 } } do
		local lamp = block(vault, "VaultLamp", Vector3.new(4, 0.3, 4), at(spot[1], VAULT_FLOOR + VAULT_HEIGHT - 0.2, spot[2]), Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
		lamp.CanCollide = false
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 1.1
		light.Color = Color3.fromRGB(255, 235, 200)
		light.Parent = lamp
	end
	-- Podiums: gold-rimmed, in two rows of six
	local podiums: { BasePart } = {}
	for row = 0, 1 do
		for column = 0, 5 do
			local i = #podiums + 1
			local x = (column - 2.5) * 6.5
			local z = 4 + row * 9
			local podium = block(vault, "VaultPodium" .. i, Vector3.new(5, 1.4, 5), at(x, VAULT_FLOOR + 0.7, z), Color3.fromRGB(50, 50, 60), Enum.Material.Marble)
			podium:SetAttribute("VaultSlot", i)
			local rim = block(podium, "PodiumRim", Vector3.new(5.4, 0.3, 5.4), at(x, VAULT_FLOOR + 1.3, z), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
			rim.CanCollide = false
			podiums[i] = podium
		end
	end
	-- The ladder back up, by the entrance spot
	local exit = block(vault, "VaultExit", Vector3.new(4, 0.3, 4), at(0, VAULT_FLOOR + 0.15, -half + 2.5), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
	exit.CanCollide = false
	for _, side in { -1, 1 } do
		local rail = block(vault, "VaultLadder", Vector3.new(0.3, VAULT_HEIGHT, 0.3), at(side * 1.2, VAULT_FLOOR + VAULT_HEIGHT / 2, -half + 0.4), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
		rail.CanCollide = false
	end
	for k = 1, 7 do
		local rung = block(vault, "VaultLadder", Vector3.new(2.4, 0.25, 0.25), at(0, VAULT_FLOOR + k * 2, -half + 0.4), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
		rung.CanCollide = false
	end
	billboard(exit, Vector2.new(200, 60), Vector3.new(0, 4, 0), "⬆ EXIT", Color3.fromRGB(255, 215, 90))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VaultExitPrompt"
	prompt.ActionText = "Climb up"
	prompt.ObjectText = "Leave Vault"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "ExitVault")
	prompt.Parent = exit
	return vault, podiums
end

-- Shows which vault podiums are unlocked (the rest are dimmed with a sign).
function WorldBuilder.SetVaultPodiums(parts: PlotParts, unlocked: number)
	for i, podium in parts.VaultPodiums do
		local open = i <= unlocked
		local rim = podium:FindFirstChild("PodiumRim") :: BasePart?
		if rim then
			rim.Color = if open then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(90, 90, 100)
			rim.Material = if open then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		local sign = podium:FindFirstChild("LockedSign")
		if open and sign then
			sign:Destroy()
		elseif not open and not sign then
			local label = billboard(podium, Vector2.new(170, 50), Vector3.new(0, 2.5, 0), "🔒 UPGRADE", Color3.fromRGB(200, 200, 210))
			local gui = label.Parent :: BillboardGui
			gui.Name = "LockedSign"
			gui.MaxDistance = 40
		end
	end
end

local function buildPlot(parent: Instance, index: number, center: Vector3): PlotParts
	local cf = CFrame.lookAt(center, Vector3.new(center.X, center.Y, 0))
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local half = PLOT_SIZE / 2

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("Locked", false)
	model.Parent = parent

	-- Local helper: x = right, y = up, z = toward the back of the base.
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- Floors are restyled by SetWallLevel to match the wall skin.
	local floors: { BasePart } = {
		block(model, "Floor", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), at(0, FLOOR_TOP - 0.5, 0), color, Enum.Material.Plastic),
	}

	local wallFolders: { [number]: Folder } = {}
	local groundWalls = Instance.new("Folder")
	groundWalls.Name = "Walls"
	groundWalls.Parent = model
	wallFolders[1] = groundWalls

	-- Entrance lasers: horizontal beams across the door. SetWallLevel marks
	-- which ones fit under the current wall height.
	local lasers: { BasePart } = {}
	for i = 1, LASER_COUNT do
		local beam = block(model, "Laser", Vector3.new(ENTRANCE_WIDTH, 0.3, 0.3), at(0, FLOOR_TOP + 0.8 + (i - 1) * 1.4, -half + 1), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
		beam.CanCollide = false
		beam.CastShadow = false
		beam.Transparency = 1
		beam:SetAttribute("Active", false)
		lasers[i] = beam
	end

	-- Ground floor pedestals: two rows of six at the back of the base.
	local pedestals: { BasePart } = {}
	local columns = { -25, -15, -5, 5, 15, 25 }
	local rows = { 8, 20 }
	for r, z in rows do
		for c, x in columns do
			local i = (r - 1) * #columns + c
			local pedestal = block(model, "Pedestal" .. i, Vector3.new(6, 1, 6), at(x, FLOOR_TOP + 0.5, z), Color3.fromRGB(60, 60, 70))
			pedestal:SetAttribute("Slot", i)
			pedestals[i] = pedestal
		end
	end

	-- Upper floors are built now and shown when bought (SetStories).
	local stories: { [number]: Folder } = {}
	local stairs: { { Carpet: Folder, Base: CFrame } } = {}
	for story = 2, #Config.Stories do
		local folder = Instance.new("Folder")
		folder.Name = "Story" .. story
		local y = storyBase(story)
		local side = rampSide(story - 1)

		-- Slab with a hole where the ramp from the floor below comes up.
		-- Edges stop inside the walls (x/z = +-29) so faces never overlap and flicker.
		local mainX = if side == -1 then 4.5 else -4.5
		table.insert(floors, block(folder, "Slab", Vector3.new(49, 1, 58), at(mainX, y - 0.5, 0), color, Enum.Material.Plastic))
		table.insert(floors, block(folder, "Slab", Vector3.new(9, 1, 25), at(side * 24.5, y - 0.5, 16.5), color, Enum.Material.Plastic))

		-- Open staircase up from the floor below: floating treads on two side
		-- beams, so brainrots behind and under it stay visible. Players walk on
		-- a thin invisible plank along the slope (smooth, and open underneath).
		local stairBase = at(side * 24, storyBase(story - 1), -26)
		local rise = STORY_HEIGHT / STAIR_STEPS
		local run = STAIR_RUN / STAIR_STEPS
		local slopeLength = math.sqrt(STAIR_RUN ^ 2 + STORY_HEIGHT ^ 2)
		local slopeAngle = math.atan2(STORY_HEIGHT, STAIR_RUN)
		-- Center of the slope line, tilted so local +Z climbs toward the back.
		local slope = stairBase * CFrame.new(0, STORY_HEIGHT / 2, STAIR_RUN / 2) * CFrame.Angles(-slopeAngle, 0, 0)

		local walkway = block(folder, "StairWalkway", Vector3.new(STAIR_WIDTH, 1, slopeLength), slope * CFrame.new(0, -0.5, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		walkway.Transparency = 1

		local wood = Color3.fromRGB(150, 105, 65)
		for _, beamSide in { -1, 1 } do
			local beam = block(folder, "StairBeam", Vector3.new(0.5, 1, slopeLength), slope * CFrame.new(beamSide * (STAIR_WIDTH / 2 - 0.25), -0.7, 0), wood:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.WoodPlanks)
			beam.CanCollide = false
		end
		for step = 1, STAIR_STEPS do
			local top = (step - 0.5) * rise
			local tread = block(folder, "Step", Vector3.new(STAIR_WIDTH - 1, 0.4, run * 0.9), stairBase * CFrame.new(0, top - 0.2, (step - 0.5) * run), wood, Enum.Material.WoodPlanks)
			tread.CanCollide = false
		end
		local carpet = Instance.new("Folder")
		carpet.Name = "Carpet"
		carpet.Parent = folder
		table.insert(stairs, { Carpet = carpet, Base = stairBase })

		for _, spot in UPPER_PEDESTALS do
			local i = #pedestals + 1
			local pedestal = block(folder, "Pedestal" .. i, Vector3.new(6, 1, 6), at(spot[1], y + 0.5, spot[2]), Color3.fromRGB(60, 60, 70))
			pedestal:SetAttribute("Slot", i)
			pedestals[i] = pedestal
		end

		local walls = Instance.new("Folder")
		walls.Name = "Walls"
		walls.Parent = folder
		wallFolders[story] = walls
		stories[story] = folder
	end

	-- Lights for every floor: ceiling panels when something is above, lamp
	-- posts on an open top floor. SetStories shows the right set.
	local lightSets: { [number]: { Ceiling: Folder, Posts: Folder } } = {}
	for story = 1, #Config.Stories do
		local y = storyBase(story)
		local holder: Instance = if story == 1 then model else stories[story]
		local ceiling = Instance.new("Folder")
		ceiling.Name = "CeilingLights"
		for _, spot in { { -12, -8 }, { 12, -8 }, { -12, 16 }, { 12, 16 } } do
			local panel = block(ceiling, "LightPanel", Vector3.new(6, 0.3, 2), at(spot[1], y + STORY_HEIGHT - 1.3, spot[2]), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
			panel.CanCollide = false
			panel.CastShadow = false
		end
		local ceilingLight = Instance.new("PointLight")
		ceilingLight.Range = 40
		ceilingLight.Brightness = 0.9
		ceilingLight.Color = Color3.fromRGB(255, 235, 200)
		ceilingLight.Parent = ceiling:FindFirstChild("LightPanel")

		local posts = Instance.new("Folder")
		posts.Name = "PostLights"
		for i, spot in { { -25, -20 }, { 25, -20 }, { -25, 25 }, { 25, 25 } } do
			local pole = block(posts, "LampPole", Vector3.new(0.4, 6, 0.4), at(spot[1], y + 3, spot[2]), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
			pole.CanCollide = false
			local lamp = block(posts, "Lamp", Vector3.new(1.2, 1.2, 1.2), at(spot[1], y + 6.4, spot[2]), Color3.fromRGB(255, 235, 180), Enum.Material.Neon)
			lamp.Shape = Enum.PartType.Ball
			lamp.CanCollide = false
			if i == 1 then
				local light = Instance.new("PointLight")
				light.Range = 45
				light.Brightness = 0.85
				light.Color = Color3.fromRGB(255, 230, 180)
				light.Parent = lamp
			end
		end
		ceiling.Parent = holder
		posts.Parent = holder
		lightSets[story] = { Ceiling = ceiling, Posts = posts }
	end

	-- Roof: once the base reaches Config.StandardWallLevels. It's built on top
	-- of the ground floor and moved up onto the top floor (SetStories).
	local roof = Instance.new("Model")
	roof.Name = "Roof"
	do
		local top = storyBase(1) + STORY_HEIGHT
		local roofColor = Color3.fromRGB(90, 60, 55)
		block(roof, "RoofSlab", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), at(0, top + 0.5, 0), WALL_COLOR, Enum.Material.Concrete)
		for _, side in { -1, 1 } do
			-- Two wedges meet at a ridge along the middle (wedges rise toward local +Z).
			local wedge = Instance.new("WedgePart")
			wedge.Name = "RoofSlope"
			wedge.Anchored = true
			wedge.Size = Vector3.new(PLOT_SIZE + 2, 10, PLOT_SIZE / 2 + 1)
			wedge.CFrame = at(0, top + 6, side * (PLOT_SIZE / 4 + 0.5)) * CFrame.Angles(0, if side == 1 then math.pi else 0, 0)
			wedge.Color = roofColor
			wedge.Material = Enum.Material.Slate
			wedge.Parent = roof
		end
		local ridge = block(roof, "RoofRidge", Vector3.new(PLOT_SIZE + 3, 1.2, 1.2), at(0, top + 11.2, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
		ridge.Shape = Enum.PartType.Cylinder
		local star = block(roof, "RoofStar", Vector3.new(3, 3, 3), at(0, top + 13.5, 0), Color3.fromRGB(255, 215, 80), Enum.Material.Neon)
		star.Shape = Enum.PartType.Ball
	end

	local collectPad = block(model, "CollectPad", Vector3.new(8, 0.4, 8), at(12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(60, 220, 90), Enum.Material.Neon)
	local pendingLabel = billboard(collectPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "COLLECT\n$0", Color3.fromRGB(140, 255, 140))

	local lockPad = block(model, "LockPad", Vector3.new(8, 0.4, 8), at(-12, FLOOR_TOP + 0.2, -12), Color3.fromRGB(230, 60, 60), Enum.Material.Neon)
	local lockLabel = billboard(lockPad, Vector2.new(220, 70), Vector3.new(0, 5, 0), "STEP TO LOCK", Color3.fromRGB(255, 140, 140))

	-- The upgrade post opens the upgrades panel (see HUD.client).
	-- Lock / unlock button just inside the door, on the right
	local lockPost = block(model, "LockButtonPost", Vector3.new(1.4, 3.4, 1.4), at(ENTRANCE_WIDTH / 2 + 3, FLOOR_TOP + 1.7, -half + 3.5), Color3.fromRGB(45, 45, 52), Enum.Material.Metal)
	lockPost.CanCollide = false
	local lockButton = block(model, "LockButton", Vector3.new(0.5, 1.6, 1.6), at(ENTRANCE_WIDTH / 2 + 3, FLOOR_TOP + 3.65, -half + 3.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(235, 60, 60), Enum.Material.Neon)
	lockButton.Shape = Enum.PartType.Cylinder
	lockButton.CanCollide = false
	local lockButtonLabel = billboard(lockButton, Vector2.new(200, 60), Vector3.new(0, 2.6, 0), "LOCK DOOR", Color3.fromRGB(255, 140, 140))
	local lockPrompt = Instance.new("ProximityPrompt")
	lockPrompt.Name = "LockPrompt"
	lockPrompt.ActionText = "Lock / Unlock"
	lockPrompt.ObjectText = "Base Door"
	lockPrompt.HoldDuration = 0
	lockPrompt.MaxActivationDistance = 10
	lockPrompt.RequiresLineOfSight = false
	lockPrompt:SetAttribute("Action", "LockToggle")
	lockPrompt.Parent = lockButton

	local upgradePost = block(model, "UpgradePost", Vector3.new(2, 4, 2), at(-14, FLOOR_TOP + 2, -24), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	local upgradeLabel = billboard(upgradePost, Vector2.new(260, 80), Vector3.new(0, 5, 0), "UPGRADES", Color3.fromRGB(255, 210, 120))
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "UpgradePrompt"
	upgradePrompt.ActionText = "Open Upgrades"
	upgradePrompt.ObjectText = "Base Upgrades"
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = 10
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt:SetAttribute("Action", "OpenUpgrades")
	upgradePrompt.Parent = upgradePost

	local prestige = Instance.new("Folder")
	prestige.Name = "Prestige"
	prestige.Parent = model

	-- The vault: a hatch in the ground floor and a room deep underneath it.
	local hatch = block(model, "VaultHatch", Vector3.new(5, 0.3, 5), at(0, FLOOR_TOP + 0.15, -10), Color3.fromRGB(70, 70, 80), Enum.Material.DiamondPlate)
	hatch.CanCollide = false
	local hatchRing = block(model, "VaultHatchRing", Vector3.new(0.4, 4.2, 4.2), at(0, FLOOR_TOP + 0.32, -10) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
	hatchRing.Shape = Enum.PartType.Cylinder
	hatchRing.CanCollide = false
	hatchRing.Transparency = 0.3
	billboard(hatch, Vector2.new(200, 60), Vector3.new(0, 3, 0), "🔒 VAULT", Color3.fromRGB(255, 215, 90))
	local hatchPrompt = Instance.new("ProximityPrompt")
	hatchPrompt.Name = "VaultPrompt"
	hatchPrompt.ActionText = "Enter Vault"
	hatchPrompt.ObjectText = "Your Vault"
	hatchPrompt.HoldDuration = 0.3
	hatchPrompt.MaxActivationDistance = 10
	hatchPrompt.RequiresLineOfSight = false
	hatchPrompt:SetAttribute("Action", "EnterVault")
	hatchPrompt.Parent = hatch
	local vault, vaultPodiums = buildVault(model, at)

	-- The owner's name floats just in front of the base, above the door (and
	-- above the King's balcony throne), so it reads from the conveyor side.
	local signPost = block(model, "Sign", Vector3.new(1, 1, 1), at(0, FLOOR_TOP + SIGN_HEIGHT, -half - 3), WALL_COLOR)
	signPost.Transparency = 1
	signPost.CanCollide = false
	local ownerLabel = billboard(signPost, Vector2.new(400, 80), Vector3.zero, "EMPTY BASE", Color3.new(1, 1, 1))
	local labelGui = ownerLabel.Parent :: BillboardGui
	labelGui.MaxDistance = 500

	return {
		Index = index,
		Model = model,
		CFrame = cf * CFrame.new(0, FLOOR_TOP, 0),
		Pedestals = pedestals,
		CollectPad = collectPad,
		LockPad = lockPad,
		Lasers = lasers,
		WallFolders = wallFolders,
		Stories = stories,
		Stairs = stairs,
		Floors = floors,
		LightSets = lightSets,
		Prestige = prestige,
		Vault = vault,
		VaultPodiums = vaultPodiums,
		VaultSpawn = at(0, VAULT_FLOOR + 3, -VAULT_SIZE / 2 + 5),
		HatchCFrame = at(0, FLOOR_TOP + 3, -14),
		Roof = roof,
		RoofPivot = roof:GetPivot(),
		SignPost = signPost,
		UpgradePost = upgradePost,
		LockButton = lockButton,
		LockButtonLabel = lockButtonLabel,
		UpgradeLabel = upgradeLabel,
		OwnerLabel = ownerLabel,
		PendingLabel = pendingLabel,
		LockLabel = lockLabel,
		SpawnCFrame = at(0, FLOOR_TOP + 4, -6) * CFrame.Angles(0, math.pi, 0),
	}
end

-- Rebuilds every floor's walls (with windows) for a wall level, and marks
-- which entrance laser beams cover the doorway. Floors with another floor
-- above get walls all the way up to it, so there are no gaps.
function WorldBuilder.SetWallLevel(parts: PlotParts, level: number, stories: number, skin: Config.WallSkin?)
	local info = Config.WallLevels[level] or Config.WallLevels[1]
	local style: WallStyle = {
		Color = if skin and skin.Color then skin.Color else WALL_COLOR,
		Material = if skin and skin.Material then skin.Material else info.Material,
		Glass = if skin and skin.Glass then skin.Glass else GLASS_COLOR,
		GlassNeon = if skin then skin.GlassNeon else nil,
		Corn = if skin then skin.Corn else nil,
		Trim = if skin then skin.Trim else nil,
		Moon = if skin then skin.Moon else nil,
		TopSign = if skin then skin.TopSign else nil,
		Clover = if skin then skin.Clover else nil,
		Pattern = if skin then skin.Pattern else nil,
		PatternColor = if skin then skin.PatternColor else nil,
		PatternRainbow = if skin then skin.PatternRainbow else nil,
	}
	-- Floors match the skin; Classic floors are grey in the walls' material.
	for _, floor in parts.Floors do
		floor.Color = if skin and skin.FloorColor then skin.FloorColor else style.Color
		floor.Material = if skin and skin.FloorMaterial then skin.FloorMaterial else style.Material
		for _, old in floor:GetChildren() do
			if old.Name == "Pattern" then
				old:Destroy()
			end
		end
		local pattern = style.Pattern
		if pattern then
			addPattern(floor, Enum.NormalId.Top, pattern, style.PatternColor or Color3.new(1, 1, 1), style.PatternRainbow, 6)
		end
	end
	-- The vault matches the base: walls in the skin, floor in its floor color.
	for _, part in parts.Vault:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "VaultWall" or part.Name == "VaultCeiling" then
				part.Color = style.Color
				part.Material = style.Material
			elseif part.Name == "VaultFloor" then
				part.Color = if skin and skin.FloorColor then skin.FloorColor else style.Color
				part.Material = if skin and skin.FloorMaterial then skin.FloorMaterial else style.Material
				for _, old in part:GetChildren() do
					if old.Name == "Pattern" then
						old:Destroy()
					end
				end
				local pattern = style.Pattern
				if pattern then
					addPattern(part, Enum.NormalId.Top, pattern, style.PatternColor or Color3.new(1, 1, 1), style.PatternRainbow, 6)
				end
			elseif part.Name == "VaultDoorSpoke" or part.Name == "VaultDoorHub" then
				part.Color = style.Trim or Color3.fromRGB(255, 200, 60)
			end
		end
	end

	local half = PLOT_SIZE / 2
	local inner = PLOT_SIZE - WALL_THICKNESS * 2 -- back/front walls fit between the side walls
	local frontWidth = (inner - ENTRANCE_WIDTH) / 2
	local turn = CFrame.Angles(0, math.pi / 2, 0)
	local roofed = stories >= Config.StandardWallLevels

	-- Floors with a floor (or the roof) above get walls all the way up to it.
	local function heightOf(story: number): number
		return if story < stories or roofed then STORY_HEIGHT else info.Height
	end
	local doorHeight = math.min(heightOf(1), DOOR_HEIGHT)
	for story, folder in parts.WallFolders do
		folder:ClearAllChildren()
		local y = storyBase(story)
		local height = heightOf(story)
		local function at(x: number, z: number): CFrame
			return parts.CFrame * CFrame.new(x, y - FLOOR_TOP, z)
		end
		wallSegment(folder, at(-half + 1, 0) * turn, PLOT_SIZE, height, style)
		wallSegment(folder, at(half - 1, 0) * turn, PLOT_SIZE, height, style)
		wallSegment(folder, at(0, half - 1), inner, height, style)
		if story == 1 then
			local frontX = ENTRANCE_WIDTH / 2 + frontWidth / 2
			wallSegment(folder, at(-frontX, -half + 1), frontWidth, height, style)
			wallSegment(folder, at(frontX, -half + 1), frontWidth, height, style)
			-- Solid lintel above the doorway when the walls are taller than it.
			if height > doorHeight + 0.1 then
				block(folder, "Lintel", Vector3.new(ENTRANCE_WIDTH, height - doorHeight, WALL_THICKNESS), at(0, -half + 1) * CFrame.new(0, doorHeight + (height - doorHeight) / 2, 0), style.Color, style.Material)
			end
			-- Laser emitter posts on both sides of the door.
			for _, side in { -1, 1 } do
				local x = side * (ENTRANCE_WIDTH / 2 + 0.5)
				block(folder, "LaserPost", Vector3.new(1, doorHeight, 2.4), at(x, -half + 1) * CFrame.new(0, doorHeight / 2, 0), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
				block(folder, "LaserStrip", Vector3.new(0.25, doorHeight - 0.4, 0.25), at(x - side * 0.55, -half + 1) * CFrame.new(0, doorHeight / 2, 0), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
			end
		else
			wallSegment(folder, at(0, -half + 1), inner, height, style)
		end
	end

	-- Role skins: a big glowing sign floating over the base.
	local topSign = style.TopSign
	if topSign then
		local topY = if roofed then storyBase(stories) + STORY_HEIGHT + 24 else storyBase(stories) + heightOf(stories) + 12
		local anchor = Instance.new("Part")
		anchor.Name = "TopSign"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = parts.CFrame * CFrame.new(0, topY - FLOOR_TOP, 0)
		anchor.Parent = parts.WallFolders[1]
		local sign = billboard(anchor, Vector2.new(520, 110), Vector3.zero, topSign, style.Trim or Color3.new(1, 1, 1))
		sign.Font = Enum.Font.FredokaOne
		local light = Instance.new("PointLight")
		light.Color = style.Trim or Color3.new(1, 1, 1)
		light.Range = 30
		light.Brightness = 1.5
		light.Parent = anchor
	end

	-- Ace's skin: a crescent moon floating over the base, high above the
	-- roof once it's built, with its aura once the base is fully upgraded.
	if style.Moon then
		local topY = if roofed then storyBase(stories) + STORY_HEIGHT + 30 else storyBase(stories) + heightOf(stories) + 16
		local moonFolder = parts.WallFolders[1]
		crescentMoon(moonFolder, parts.CFrame * CFrame.new(0, topY - FLOOR_TOP, 0), 9, level >= Config.StandardWallLevels)
	end

	for i, beam in parts.Lasers do
		beam:SetAttribute("Active", 0.8 + (i - 1) * 1.4 <= doorHeight - 0.4)
	end
end

-- Lays carpet on every staircase. Tier 0 = bare wood (see Config.CarpetTiers).
function WorldBuilder.SetCarpet(parts: PlotParts, tier: number)
	local info = Config.CarpetTiers[tier]
	local rise = STORY_HEIGHT / STAIR_STEPS
	local run = STAIR_RUN / STAIR_STEPS
	for _, stair in parts.Stairs do
		stair.Carpet:ClearAllChildren()
		if not info then
			continue
		end
		local width = STAIR_WIDTH - 1.6
		for step = 1, STAIR_STEPS do
			local top = (step - 0.5) * rise
			local z = (step - 0.5) * run
			local color = if info.Rainbow then Color3.fromHSV((step / STAIR_STEPS) % 1, 0.65, 1) else info.Color
			local function piece(name: string, size: Vector3, offset: CFrame, c: Color3, material: Enum.Material): Part
				local p = block(stair.Carpet, name, size, stair.Base * offset, c, material)
				p.CanCollide = false
				p.CastShadow = false
				return p
			end
			piece("CarpetTop", Vector3.new(width, 0.12, run * 0.9), CFrame.new(0, top + 0.06, z), color, info.Material)
			if info.Trim then
				for _, side in { -1, 1 } do
					piece("CarpetTrim", Vector3.new(0.3, 0.16, run * 0.9), CFrame.new(side * (width / 2 + 0.15), top + 0.08, z), info.Trim, Enum.Material.Foil)
				end
			end
			if info.Glow then
				piece("CarpetGlow", Vector3.new(width, 0.1, 0.18), CFrame.new(0, top + 0.14, z - run / 2 + 0.1), info.Glow, Enum.Material.Neon)
			end
		end
		if info.Sparkle then
			local emitterPart = block(stair.Carpet, "CarpetSparkles", Vector3.new(width, 0.2, STAIR_RUN), stair.Base * CFrame.new(0, STORY_HEIGHT / 2, STAIR_RUN / 2) * CFrame.Angles(math.atan2(STORY_HEIGHT, STAIR_RUN), 0, 0), info.Color, Enum.Material.SmoothPlastic)
			emitterPart.Transparency = 1
			emitterPart.CanCollide = false
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkles.Color = ColorSequence.new(info.Glow or info.Color)
			sparkles.LightEmission = 1
			sparkles.Rate = 15
			sparkles.Lifetime = NumberRange.new(0.6, 1.2)
			sparkles.Speed = NumberRange.new(0.5, 1.5)
			sparkles.Size = NumberSequence.new(0.3)
			sparkles.Parent = emitterPart
		end
	end
end

-- Shows the floors a base has bought and lifts the owner sign above them.
function WorldBuilder.SetStories(parts: PlotParts, count: number)
	local roofed = count >= Config.StandardWallLevels
	for story, folder in parts.Stories do
		folder.Parent = if story <= count then parts.Model else nil
	end
	for story, set in parts.LightSets do
		-- Ceiling lights under every floor or roof; lamp posts on an open top floor.
		local holder: Instance = if story == 1 then parts.Model else parts.Stories[story]
		local covered = story < count or roofed
		set.Ceiling.Parent = if covered then holder else nil
		set.Posts.Parent = if covered then nil else holder
	end
	if roofed then
		parts.Roof:PivotTo(parts.RoofPivot + Vector3.new(0, storyBase(count) - storyBase(1), 0))
	end
	parts.Roof.Parent = if roofed then parts.Model else nil
end

-- Prestige ---------------------------------------------------------------------
-- Rebirth decorations (Config.PrestigeLadder), in the stair carpet's colors.

local BRONZE = Color3.fromRGB(205, 127, 50)
local THRONE_GOLD = Color3.fromRGB(255, 200, 60)
local BLOOM_PINK = Color3.fromRGB(255, 110, 200)
local BLOOM_LIGHT = Color3.fromRGB(255, 190, 230)
local BALCONY_HEIGHT = 13 -- balcony floor, above the door

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
end

local function ball(parent: Instance, name: string, d: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = decoration(parent, name, Vector3.one * d, cframe, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function rod(parent: Instance, name: string, length: number, d: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	-- Cylinders run along X; `cframe` is the center, X along the rod.
	local p = decoration(parent, name, Vector3.new(length, d, d), cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- The throne, centered on `cf` (feet level, facing cf's -Z). Its look:
-- "Corn" (Corny), "Bloom" (Ace) or the carpet colors for everyone else.
local function throne(folder: Instance, cf: CFrame, look: string, main: Color3, trim: Color3, glow: Color3, rainbow: boolean?): Seat
	local frame = if look == "Corn" then CORN_YELLOW elseif look == "Bloom" then BLOOM_PINK else trim
	local cushion = if look == "Corn" then CORN_LEAF elseif look == "Bloom" then BLOOM_LIGHT else main
	-- Base and the seat you can sit on
	decoration(folder, "ThroneBase", Vector3.new(5.2, 1.6, 4.4), cf * CFrame.new(0, 0.8, 0.2), frame, Enum.Material.Foil)
	local seat = Instance.new("Seat")
	seat.Name = "ThroneSeat"
	seat.Anchored = true
	seat.Size = Vector3.new(4, 0.8, 3.4)
	seat.CFrame = cf * CFrame.new(0, 2, 0)
	seat.Color = cushion
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = folder
	-- Armrests
	for _, side in { -1, 1 } do
		decoration(folder, "ThroneArm", Vector3.new(0.7, 1.2, 3.6), cf * CFrame.new(side * 2.45, 2.6, 0.2), frame, Enum.Material.Foil)
		ball(folder, "ThroneArmKnob", 0.9, cf * CFrame.new(side * 2.45, 3.25, -1.6), glow, Enum.Material.Neon)
	end
	local back = cf * CFrame.new(0, 0, 1.9)
	if look == "Corn" then
		-- A fan of big corn cobs for the backrest, husk leaves at the sides.
		for i = -2, 2 do
			local height = 5.6 - math.abs(i) * 0.7
			cornCob(folder, back * CFrame.new(i * 0.95, 2.4 + height * 0.4, 0) * CFrame.Angles(0, 0, math.rad(-i * 11)), height)
		end
		decoration(folder, "ThroneBack", Vector3.new(4.6, 4.5, 0.5), back * CFrame.new(0, 4.4, 0.2), CORN_LEAF_DARK, Enum.Material.SmoothPlastic)
		ball(folder, "ThroneJewel", 1.1, back * CFrame.new(0, 8.6, -0.2), CORN_GOLD, Enum.Material.Neon)
	elseif look == "Bloom" then
		-- A giant pink flower behind the seat: two rings of petals and a gold heart.
		local center = back * CFrame.new(0, 5.6, 0.3)
		for ring, info in { { Count = 10, Radius = 2.9, Size = 2.6, Color = BLOOM_PINK }, { Count = 8, Radius = 1.7, Size = 2.1, Color = BLOOM_LIGHT } } do
			for k = 0, info.Count - 1 do
				local angle = (k + ring * 0.5) / info.Count * math.pi * 2
				local petal = decoration(folder, "BloomPetal", Vector3.new(info.Size * 1.3, info.Size * 0.75, 0.35), center * CFrame.Angles(0, 0, angle) * CFrame.new(info.Radius, 0, -ring * 0.15), info.Color, Enum.Material.SmoothPlastic)
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = petal
			end
		end
		rod(folder, "BloomHeart", 0.5, 1.8, center * CFrame.new(0, 0, -0.45) * CFrame.Angles(0, math.rad(90), 0), THRONE_GOLD, Enum.Material.Neon)
		decoration(folder, "ThroneBack", Vector3.new(4.2, 3.6, 0.5), back * CFrame.new(0, 3.6, 0.4), BLOOM_PINK, Enum.Material.Fabric)
	else
		-- A tall cushioned backrest in a gold frame, crowned with gems.
		decoration(folder, "ThroneBack", Vector3.new(4.8, 6.6, 0.8), back * CFrame.new(0, 5.3, 0.3), frame, Enum.Material.Foil)
		decoration(folder, "ThroneCushion", Vector3.new(3.8, 5.4, 0.3), back * CFrame.new(0, 5.1, -0.2), cushion, Enum.Material.Fabric)
		for k = -2, 2 do
			local gem = if rainbow then Color3.fromHSV((k + 2) / 5, 0.7, 1) else glow
			ball(folder, "ThroneGem", 0.8 - math.abs(k) * 0.1, back * CFrame.new(k * 1.05, 8.9 - math.abs(k) * 0.45, 0.2), gem, Enum.Material.Neon)
		end
	end
	light(seat, glow, 18, 1.2)
	return seat
end

-- Rebuilds a base's rebirth decorations. `look` picks the throne style
-- ("Corn", "Bloom" or nil for the carpet colors).
function WorldBuilder.SetPrestige(parts: PlotParts, rebirths: number, stories: number, look: string?)
	local folder = parts.Prestige
	folder:ClearAllChildren()
	for _, pedestal in parts.Pedestals do
		local rim = pedestal:FindFirstChild("PrestigeRim")
		if rim then
			rim:Destroy()
		end
	end
	local tier = Config.CarpetTierFor(rebirths)
	local info = Config.CarpetTiers[tier]
	local main = if info then info.Color else BRONZE
	local trim = if info and info.Trim then info.Trim else THRONE_GOLD
	local glow = if info and info.Glow then info.Glow elseif info then info.Color:Lerp(Color3.new(1, 1, 1), 0.3) else Color3.fromRGB(255, 170, 90)
	local rainbow = info ~= nil and info.Rainbow == true
	local cf = parts.CFrame -- floor level, -Z toward the conveyor
	local half = PLOT_SIZE / 2
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function has(key: string): boolean
		return Config.HasPrestige(rebirths, key)
	end

	-- Glowing rims around every pedestal
	if has("Rims") then
		for i, pedestal in parts.Pedestals do
			local rim = decoration(pedestal, "PrestigeRim", Vector3.new(6.4, 0.25, 6.4), pedestal.CFrame * CFrame.new(0, 0.42, 0), if rainbow then Color3.fromHSV((i % 7) / 7, 0.6, 1) else glow, Enum.Material.Neon)
			rim.Transparency = 0.35
		end
	end
	-- Torches on both sides of the door, outside
	if has("Torches") then
		for _, side in { -1, 1 } do
			local x = side * (ENTRANCE_WIDTH / 2 + 4.5)
			rod(folder, "TorchPole", 7, 0.6, at(x, 3.5, -half - 2.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 45, 35), Enum.Material.Wood)
			local bowl = rod(folder, "TorchBowl", 0.8, 1.8, at(x, 7.2, -half - 2.5) * CFrame.Angles(0, 0, math.rad(90)), trim, Enum.Material.Foil)
			local flame = ball(folder, "TorchFlame", 1.2, at(x, 8, -half - 2.5), Color3.fromRGB(255, 160, 60), Enum.Material.Neon)
			local fire = Instance.new("Fire")
			fire.Size = 3
			fire.Heat = 6
			fire.Color = if info then glow else Color3.fromRGB(255, 120, 30)
			fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
			fire.Parent = flame
			light(bowl, Color3.fromRGB(255, 180, 100), 22, 1.1)
		end
	end
	-- Banners with the rebirth count on tall poles in front of the wall
	if has("Banners") then
		for _, side in { -1, 1 } do
			local x = side * (ENTRANCE_WIDTH / 2 + 10)
			rod(folder, "BannerPole", 13, 0.4, at(x + side * 2.8, 6.5, -half - 2.2) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 45, 35), Enum.Material.Wood)
			ball(folder, "BannerFinial", 0.8, at(x + side * 2.8, 13.2, -half - 2.2), trim, Enum.Material.Foil)
			rod(folder, "BannerRod", 6.2, 0.3, at(x + side * 0.1, 12.2, -half - 2.2), trim, Enum.Material.Foil)
			local cloth = decoration(folder, "Banner", Vector3.new(5, 7, 0.2), at(x, 8.5, -half - 2.4), main, Enum.Material.Fabric)
			decoration(folder, "BannerTip", Vector3.new(3.5, 3.5, 0.2), at(x, 5, -half - 2.4) * CFrame.Angles(0, 0, math.rad(45)), main, Enum.Material.Fabric)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 25
			gui.LightInfluence = 0.3
			gui.Parent = cloth
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = trim
			label.TextStrokeTransparency = 0.2
			label.Text = string.format("★\nREBIRTH\n%d\n★", rebirths)
			label.Parent = gui
		end
	end
	-- Guardian pillars with glowing orbs at the two front corners
	if has("Pillars") then
		for _, side in { -1, 1 } do
			local x = side * (half + 2.5)
			decoration(folder, "PillarBase", Vector3.new(3.6, 1.2, 3.6), at(x, 0.6, -half - 2.5), trim, Enum.Material.Marble)
			rod(folder, "Pillar", 12, 2.2, at(x, 7.2, -half - 2.5) * CFrame.Angles(0, 0, math.rad(90)), main:Lerp(Color3.new(1, 1, 1), 0.5), Enum.Material.Marble)
			decoration(folder, "PillarCap", Vector3.new(3.2, 1, 3.2), at(x, 13.6, -half - 2.5), trim, Enum.Material.Foil)
			local orb = ball(folder, "PillarOrb", 2.4, at(x, 15.4, -half - 2.5), glow, Enum.Material.Neon)
			light(orb, glow, 30, 1.4)
		end
	end
	-- A carpet runway from the door out toward the conveyor, with little lamps
	if has("Runway") then
		local length = 26
		decoration(folder, "Runway", Vector3.new(ENTRANCE_WIDTH - 4, 0.15, length), at(0, 0.08, -half - length / 2 - 1), main, Enum.Material.Fabric)
		for _, side in { -1, 1 } do
			decoration(folder, "RunwayTrim", Vector3.new(0.5, 0.2, length), at(side * (ENTRANCE_WIDTH / 2 - 1.75), 0.1, -half - length / 2 - 1), trim, Enum.Material.Foil)
			for k = 0, 2 do
				local z = -half - 6 - k * 9
				rod(folder, "RunwayLampPost", 3, 0.3, at(side * (ENTRANCE_WIDTH / 2 + 0.5), 1.5, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
				ball(folder, "RunwayLamp", 0.9, at(side * (ENTRANCE_WIDTH / 2 + 0.5), 3.2, z), if rainbow then Color3.fromHSV(k / 3, 0.6, 1) else glow, Enum.Material.Neon)
			end
		end
	end
	-- A beam of light straight up from the top of the base
	if has("Beacon") then
		local roofed = stories >= Config.StandardWallLevels
		-- From above the roof (or above the top floor's walls)
		local top = storyBase(stories) - FLOOR_TOP + STORY_HEIGHT + (if roofed then 14 else 2)
		local beam = rod(folder, "SkyBeacon", 400, 3, at(0, top + 200, 0) * CFrame.Angles(0, 0, math.rad(90)), glow, Enum.Material.Neon)
		beam.Transparency = 0.55
		local base = ball(folder, "BeaconCore", 3.5, at(0, top + 1, 0), glow, Enum.Material.Neon)
		light(base, glow, 40, 2)
	end
	-- The King's balcony over the door, held up by two columns, with the throne
	if has("Balcony") then
		local depth, width = 9, ENTRANCE_WIDTH + 8
		local z = -half - 1 - depth / 2
		decoration(folder, "BalconyFloor", Vector3.new(width, 1, depth), at(0, BALCONY_HEIGHT - 0.5, z), trim, Enum.Material.Marble).CanCollide = true
		decoration(folder, "BalconyCarpet", Vector3.new(width - 3, 0.12, depth - 2), at(0, BALCONY_HEIGHT + 0.06, z + 0.3), main, Enum.Material.Fabric)
		for _, side in { -1, 1 } do
			rod(folder, "BalconyColumn", BALCONY_HEIGHT - 1, 1.6, at(side * (width / 2 - 1.5), (BALCONY_HEIGHT - 1) / 2, z - depth / 2 + 1.2) * CFrame.Angles(0, 0, math.rad(90)), main:Lerp(Color3.new(1, 1, 1), 0.6), Enum.Material.Marble)
		end
		-- Railing: posts and a gold rail along the front and both sides
		local railY = BALCONY_HEIGHT + 2.6
		decoration(folder, "Rail", Vector3.new(width, 0.4, 0.5), at(0, railY, z - depth / 2 + 0.3), trim, Enum.Material.Foil)
		for _, side in { -1, 1 } do
			decoration(folder, "Rail", Vector3.new(0.5, 0.4, depth), at(side * (width / 2 - 0.3), railY, z), trim, Enum.Material.Foil)
		end
		for k = 0, 10 do
			local x = -width / 2 + 0.5 + k * (width - 1) / 10
			rod(folder, "Baluster", 2.4, 0.4, at(x, BALCONY_HEIGHT + 1.3, z - depth / 2 + 0.3) * CFrame.Angles(0, 0, math.rad(90)), main:Lerp(Color3.new(1, 1, 1), 0.6), Enum.Material.Marble)
		end
		local seat = throne(folder, at(0, BALCONY_HEIGHT, z + 1.6), look or "Carpet", main, trim, glow, rainbow)
		-- Gold pad at the bottom: the owner taps it to take the throne.
		local pad = decoration(folder, "ThronePad", Vector3.new(4, 0.3, 4), at(-(width / 2 + 3.5), 0.15, -half - 8), THRONE_GOLD, Enum.Material.Neon)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ThronePrompt"
		prompt.ActionText = "Sit on the throne"
		prompt.ObjectText = "King's Balcony"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", "Throne")
		prompt.Parent = pad
		local sign = billboard(pad, Vector2.new(260, 60), Vector3.new(0, 4, 0), "👑 THRONE", THRONE_GOLD)
		sign.Font = Enum.Font.FredokaOne
		seat:SetAttribute("PlotIndex", parts.Index)
	end
end

-- A rocky cave around one end of the conveyor. `facing` is the direction
-- its mouth opens (+1 = toward +X, -1 = toward -X). It's built with the
-- mouth at the origin and then moved into place.
local function buildCave(parent: Instance, name: string, mouthPosition: Vector3, facing: number, seed: number)
	local cave = Instance.new("Model")
	cave.Name = name
	cave.Parent = parent
	local mouthX = 0

	local darkRock = Color3.fromRGB(45, 40, 40)
	local backX = mouthX - CAVE_DEPTH
	local centerX = (mouthX + backX) / 2
	local halfWidth = 9 -- tunnel half-width; the belt and rails fit inside
	local height = 15 -- tunnel height

	-- The rock and tunnel are built by buildCaveHill; these parts are the
	-- dressing inside the tunnel.
	block(cave, "CaveFloor", Vector3.new(CAVE_DEPTH, 0.6, halfWidth * 2), CFrame.new(centerX, 0.3, 0), darkRock, Enum.Material.Slate)
	local rng = Random.new(seed)

	-- Stalactites hanging in the entrance.
	for _, z in { -6, -2.5, 1.5, 5 } do
		local length = rng:NextNumber(1.5, 3)
		local spike = Instance.new("WedgePart")
		spike.Name = "Stalactite"
		spike.Anchored = true
		spike.Size = Vector3.new(1.2, length, 1.2)
		spike.CFrame = CFrame.new(mouthX - 3, TUNNEL_TOP - length / 2 + 0.5, z) * CFrame.Angles(math.pi, 0, 0)
		spike.Color = darkRock
		spike.Material = Enum.Material.Slate
		spike.Parent = cave
	end

	-- Glowing crystals inside so you can see brainrots coming.
	local crystalColors = { Color3.fromRGB(170, 80, 255), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 80, 200) }
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local crystal = Instance.new("Part")
		crystal.Name = "Crystal"
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.Size = Vector3.new(0.8, rng:NextNumber(1.5, 3), 0.8)
		crystal.CFrame = CFrame.new(backX + 3 + (i - 1) * 3.2, rng:NextNumber(2, height - 3), side * (halfWidth - 0.3))
			* CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5))
		crystal.Color = crystalColors[(i - 1) % #crystalColors + 1]
		crystal.Material = Enum.Material.Neon
		crystal.Parent = cave
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 120, 255)
	glow.Range = 24
	glow.Brightness = 1.5
	local lightPart = block(cave, "CaveLight", Vector3.new(1, 1, 1), CFrame.new(centerX, height - 3, 0), Color3.new(0, 0, 0))
	lightPart.Transparency = 1
	lightPart.CanCollide = false
	glow.Parent = lightPart

	cave.WorldPivot = CFrame.new()
	cave:PivotTo(CFrame.new(mouthPosition) * CFrame.Angles(0, if facing < 0 then math.pi else 0, 0))
end

-- Scenery -----------------------------------------------------------------------
-- Flat bright grass, stone paths, ponds, trees, rocky caves at the conveyor
-- ends and a wooden fence around the edge.


-- Flat, bright grass for the whole map.
local LAKES = { Vector3.new(-150, 0, 265), Vector3.new(170, 0, -255) }

local function buildGround(parent: Instance)
	-- Four tiles (parts max out at 2048 studs), reaching well past the fence
	-- so the giant founders have grass to stand on.
	for _, x in { -1024, 1024 } do
		for _, z in { -1024, 1024 } do
			block(parent, "Ground", Vector3.new(2048, 2, 2048), CFrame.new(x, -0.9, z), Color3.fromRGB(96, 175, 76), Enum.Material.Grass)
		end
	end
end

-- A flat stone path (with a darker border) between two points on the ground.
-- Paths are just paint: players walk on the grass underneath.
local function path(parent: Instance, from: Vector3, to: Vector3, width: number)
	local length = (to - from).Magnitude
	local center = (from + to) / 2
	local facing = CFrame.lookAt(Vector3.new(center.X, 0, center.Z), Vector3.new(to.X, 0, to.Z))
	local edge = block(parent, "PathEdge", Vector3.new(width + 2, 0.3, length + 2), facing + Vector3.new(0, 0.07, 0), PATH_EDGE, Enum.Material.SmoothPlastic)
	local top = block(parent, "Path", Vector3.new(width, 0.3, length), facing + Vector3.new(0, 0.1, 0), PATH_COLOR, Enum.Material.SmoothPlastic)
	for _, p in { edge, top } do
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
end

-- Cartoon ponds: glossy blue water in a sandy ring.
local function buildLakes(parent: Instance)
	for _, lake in LAKES do
		local sand = block(parent, "LakeSand", Vector3.new(0.3, 52, 52), CFrame.new(lake + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(235, 215, 160), Enum.Material.SmoothPlastic)
		sand.Shape = Enum.PartType.Cylinder
		local water = block(parent, "LakeWater", Vector3.new(0.35, 44, 44), CFrame.new(lake + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 170, 230), Enum.Material.SmoothPlastic)
		water.Shape = Enum.PartType.Cylinder
		water.Reflectance = 0.25
		water.Transparency = 0.1
		local shine = block(parent, "LakeShine", Vector3.new(0.36, 10, 22), CFrame.new(lake + Vector3.new(-8, 0.22, -6)) * CFrame.Angles(0, math.rad(30), math.pi / 2), Color3.fromRGB(160, 225, 255), Enum.Material.SmoothPlastic)
		shine.Shape = Enum.PartType.Cylinder
		shine.CanCollide = false
	end
end

-- Trees ------------------------------------------------------------------------

local function treeAt(parent: Instance, rng: Random, position: Vector3, pine: boolean)
	local tree = Instance.new("Model")
	tree.Name = if pine then "PineTree" else "Tree"
	tree.Parent = parent
	local scale = rng:NextNumber(0.85, 1.3)
	local trunkHeight = (if pine then 4 else 6) * scale
	local trunk = block(tree, "Trunk", Vector3.new(trunkHeight, 1.1 * scale, 1.1 * scale), CFrame.new(position + Vector3.new(0, trunkHeight / 2 - 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(105, 75, 50), Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	local top = position + Vector3.new(0, trunkHeight, 0)
	if pine then
		-- Fir: stacked, shrinking tiers of dark needles.
		local tiers = { { 7.5, 3.6, 0.6 }, { 6, 3.2, 2.9 }, { 4.4, 2.8, 5 }, { 2.6, 2.4, 6.8 } }
		for i, tier in tiers do
			local needles = block(tree, "Needles", Vector3.new(tier[1], tier[2], tier[1]) * scale, CFrame.new(top + Vector3.new(0, tier[3] * scale, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(45, 120 + i * 10, 70), Enum.Material.SmoothPlastic)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = needles
			needles.CanCollide = false
		end
	else
		-- Round leafy canopy made of a few overlapping blobs.
		for i = 1, 3 do
			local size = rng:NextNumber(5.5, 7.5) * scale
			local offset = Vector3.new(rng:NextNumber(-1.6, 1.6), 1.2 + i * 0.8, rng:NextNumber(-1.6, 1.6)) * scale
			local leaves = block(tree, "Leaves", Vector3.new(size, size, size), CFrame.new(top + offset), Color3.fromRGB(80 + i * 10, 175 + i * 12, 70), Enum.Material.SmoothPlastic)
			leaves.Shape = Enum.PartType.Ball
			leaves.CanCollide = false
		end
	end
end

-- A rugged rock outcrop at one end of the conveyor, with a dark tunnel the
-- conveyor runs into and a wooden mine-shaft frame with lanterns at the
-- mouth. `facing` is the direction the mouth opens (+1 = toward +X).
local ROCK_COLORS = {
	Color3.fromRGB(118, 112, 106),
	Color3.fromRGB(102, 98, 95),
	Color3.fromRGB(132, 125, 116),
}

local function buildCaveHill(parent: Instance, rng: Random, mouthX: number, facing: number)
	local inward = -facing -- direction from the mouth into the rock
	local hill = Instance.new("Model")
	hill.Name = "CaveRocks"
	hill.Parent = parent
	-- Position `depth` studs into the rock, `y` up, `z` across.
	local function at(depth: number, y: number, z: number): CFrame
		return CFrame.new(mouthX + inward * depth, y, z)
	end
	local function tilt(x: number, y: number, z: number): CFrame
		return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
	local function rock(cframe: CFrame, size: Vector3, mossy: boolean?)
		local color = ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)]
		block(hill, "Rock", size, cframe, color, Enum.Material.Rock)
		if mossy then
			block(hill, "Moss", Vector3.new(size.X * 0.8, 0.8, size.Z * 0.75), cframe * CFrame.new(0, size.Y / 2 + 0.2, 0), Color3.fromRGB(88, 140, 70), Enum.Material.Grass)
		end
	end

	-- Big masses either side of the tunnel, one over it and one behind.
	-- (No turning around Y near the tunnel, so nothing pokes into it.)
	rock(at(24, 12, -27.5) * tilt(4, 0, 2), Vector3.new(44, 24, 30), true)
	rock(at(26, 13, 28) * tilt(-4, 0, -3), Vector3.new(46, 26, 30), true)
	rock(at(22, 25, 0) * tilt(0, 0, 2), Vector3.new(40, 14, 34), true)
	rock(at(48, 14, 0) * tilt(0, 5, 0), Vector3.new(30, 30, 58), true)
	-- Craggy peaks on top
	rock(at(34, 33, -6) * tilt(5, 20, 8), Vector3.new(26, 14, 28))
	rock(at(30, 36, 10) * tilt(-6, -15, 5), Vector3.new(18, 10, 18), true)
	rock(at(44, 31, -20) * tilt(10, 30, -6), Vector3.new(16, 9, 16), true)
	-- Boulders around the front
	rock(at(6, 6, -20) * tilt(10, 25, 15), Vector3.new(12, 12, 12))
	rock(at(6, 6, 20) * tilt(-12, -20, 8), Vector3.new(12, 12, 12))
	rock(at(4, 3, -31) * tilt(0, 40, 10), Vector3.new(10, 7, 10))
	rock(at(5, 3, 32) * tilt(5, -30, 0), Vector3.new(9, 6, 9))
	rock(at(8, 20, -19) * tilt(0, 15, -10), Vector3.new(14, 10, 16), true)
	rock(at(9, 21, 19) * tilt(0, -20, 12), Vector3.new(14, 10, 14), true)
	-- Loose stones on the grass, clear of the walkways
	for _ = 1, 8 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local size = rng:NextNumber(2.5, 5)
		rock(at(rng:NextNumber(-6, 50), size * 0.3, side * rng:NextNumber(36, 48)) * tilt(rng:NextNumber(0, 40), rng:NextNumber(0, 360), rng:NextNumber(0, 40)), Vector3.new(size, size * 0.8, size * 1.1))
	end

	-- The tunnel: dark rock walls and ceiling, fading into blackness.
	local tunnelRock = Color3.fromRGB(52, 48, 47)
	for _, z in { -10.5, 10.5 } do
		block(hill, "TunnelWall", Vector3.new(24, 18, 1), at(12, 9, z), tunnelRock, Enum.Material.Slate)
	end
	block(hill, "TunnelCeiling", Vector3.new(24, 1, 22), at(12, 17.5, 0), tunnelRock, Enum.Material.Slate)
	local back = block(hill, "TunnelDark", Vector3.new(1, 18, 22), at(24, 9, 0), Color3.fromRGB(8, 6, 10), Enum.Material.SmoothPlastic)
	back.CanCollide = false

	-- Wooden mine-shaft frames at the mouth and a little way in.
	local wood = Color3.fromRGB(110, 75, 45)
	for _, depth in { -0.5, 9 } do
		for _, z in { -9.3, 9.3 } do
			block(hill, "MinePost", Vector3.new(1.6, 17, 1.6), at(depth, 8.5, z), wood, Enum.Material.WoodPlanks)
		end
		block(hill, "MineBeam", Vector3.new(1.8, 1.8, 22), at(depth, 17.6, 0), wood:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.WoodPlanks)
	end
	-- Corner braces on the front frame
	for _, z in { -1, 1 } do
		block(hill, "MineBrace", Vector3.new(1.2, 1.2, 5), at(-0.5, 15.4, z * 7.2) * tilt(z * 45, 0, 0), wood, Enum.Material.WoodPlanks)
	end
	-- Two warm lanterns hanging from the beam
	for _, z in { -6.5, 6.5 } do
		block(hill, "LanternChain", Vector3.new(0.2, 1.4, 0.2), at(-1.2, 16, z), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
		local lantern = block(hill, "Lantern", Vector3.new(0.9, 1.2, 0.9), at(-1.2, 14.8, z), Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
		lantern.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 180, 90)
		light.Range = 16
		light.Brightness = 1.5
		light.Parent = lantern
	end

	-- A few pines growing on top
	treeAt(hill, rng, at(42, 29, -16).Position, true)
	treeAt(hill, rng, at(46, 29, 14).Position, true)
	treeAt(hill, rng, at(28, 24, -34).Position, true)
	treeAt(hill, rng, at(30, 26, 36).Position, true)
end

-- Leafy trees and firs on the open grass around the bases.
local function buildTrees(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Trees"
	folder.Parent = parent
	local function clear(x: number, z: number): boolean
		if math.abs(x) < 370 and math.abs(z) < 160 then
			return false -- bases, conveyor, shop, caves
		end
		for _, lake in LAKES do
			if (Vector3.new(x, 0, z) - lake).Magnitude < 32 then
				return false
			end
		end
		return true
	end
	local planted = 0
	for _ = 1, 1000 do
		if planted >= 150 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(170, BARRIER_RADIUS - 15)
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if clear(x, z) then
			treeAt(folder, rng, Vector3.new(x, 0, z), rng:NextNumber() < 0.45)
			planted += 1
		end
	end
end

-- Gentle color grading so everything looks a bit richer.
local function buildLighting()
	if not Lighting:FindFirstChild("BrainrotGrade") then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "BrainrotGrade"
		grade.Saturation = 0.12
		grade.Contrast = 0.06
		grade.Brightness = -0.06 -- darker than default: the map was too bright
		grade.Parent = Lighting
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "BrainrotBloom"
		bloom.Intensity = 0.15
		bloom.Size = 16
		bloom.Threshold = 2.2
		bloom.Parent = Lighting
		local rays = Instance.new("SunRaysEffect")
		rays.Name = "BrainrotSunRays"
		rays.Intensity = 0.02
		rays.Spread = 0.6
		rays.Parent = Lighting
	end
end

-- A wooden fence around the edge of the map, with a tall invisible wall
-- right behind it so nobody can jump over.
local function buildBarrier(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "MapBarrier"
	folder.Parent = parent
	local wood = Color3.fromRGB(170, 120, 75)
	local fenceRadius = BARRIER_RADIUS - 2
	local fenceSegments = 120
	for i = 1, fenceSegments do
		local a0 = (i / fenceSegments) * math.pi * 2
		local a1 = ((i + 1) / fenceSegments) * math.pi * 2
		local p0 = Vector3.new(math.cos(a0), 0, math.sin(a0)) * fenceRadius
		local p1 = Vector3.new(math.cos(a1), 0, math.sin(a1)) * fenceRadius
		block(folder, "FencePost", Vector3.new(1.4, 6, 1.4), CFrame.new(p0 + Vector3.new(0, 3, 0)), wood:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.WoodPlanks)
		block(folder, "FencePostCap", Vector3.new(1.8, 0.6, 1.8), CFrame.new(p0 + Vector3.new(0, 6.3, 0)), wood:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.WoodPlanks)
		local railLength = (p1 - p0).Magnitude
		for _, y in { 2.2, 4.6 } do
			local mid = (p0 + p1) / 2 + Vector3.new(0, y, 0)
			block(folder, "FenceRail", Vector3.new(0.6, 0.9, railLength), CFrame.lookAt(mid, p1 + Vector3.new(0, y, 0)), wood, Enum.Material.WoodPlanks)
		end
	end
	local segments = 96
	local width = 2 * math.pi * BARRIER_RADIUS / segments + 2
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local position = Vector3.new(math.cos(angle) * BARRIER_RADIUS, 250, math.sin(angle) * BARRIER_RADIUS)
		local wall = Instance.new("Part")
		wall.Name = "Barrier"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Size = Vector3.new(width, 500, 2)
		wall.CFrame = CFrame.lookAt(position, Vector3.new(0, 250, 0))
		wall.Parent = folder
	end
end

-- The shop tent: a round, striped circus-style tent (like Bee Swarm's) by
-- the cave the brainrots come out of. Inside: a Shard counter (left) and
-- a Robux counter (right). The entrance faces the conveyor (-Z).
-- A little market stall where players sell brainrots from a menu.
local function buildSellStand(parent: Instance, center: Vector3)
	local stand = Instance.new("Model")
	stand.Name = "SellStand"
	stand.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(center + Vector3.new(x, y, z))
	end
	local wood = Color3.fromRGB(150, 105, 70)
	local green = Color3.fromRGB(60, 200, 100)
	local counter = block(stand, "Counter", Vector3.new(9, 3.5, 3), at(0, 1.75, 0), wood, Enum.Material.WoodPlanks)
	block(stand, "CounterTop", Vector3.new(9.4, 0.4, 3.4), at(0, 3.7, 0), green, Enum.Material.Neon)
	for _, x in { -4.2, 4.2 } do
		block(stand, "Post", Vector3.new(0.6, 9, 0.6), at(x, 4.5, 1.2), wood, Enum.Material.WoodPlanks)
	end
	-- Striped awning, sloping toward the front
	for i = 0, 5 do
		local stripe = block(stand, "Awning", Vector3.new(1.6, 0.3, 5), at(-4 + i * 1.6, 9, -0.6) * CFrame.Angles(math.rad(-18), 0, 0), if i % 2 == 0 then green else Color3.fromRGB(245, 245, 240), Enum.Material.SmoothPlastic)
		stripe.CanCollide = false
	end
	-- Coin pile and a cash bag on the counter
	for i = 1, 6 do
		local coin = block(stand, "Coin", Vector3.new(0.2, 1, 1), at(-2.5 + (i % 3) * 0.5, 4.05 + (i // 3) * 0.2, -0.3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 205, 60), Enum.Material.Foil)
		coin.Shape = Enum.PartType.Cylinder
		coin.CanCollide = false
	end
	local bag = block(stand, "CashBag", Vector3.new(1.6, 1.8, 1.6), at(2.6, 4.8, -0.2), Color3.fromRGB(70, 160, 80), Enum.Material.Fabric)
	bag.Shape = Enum.PartType.Ball
	bag.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellStandPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Sell Brainrots"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "SellStand")
	prompt.Parent = counter
	local label = billboard(counter, Vector2.new(260, 55), Vector3.new(0, 9.5, 0), "SELL STAND", green)
	;(label.Parent :: BillboardGui).MaxDistance = 250
end

local function buildShop(parent: Instance, center: Vector3)
	local shop = Instance.new("Model")
	shop.Name = "ShopTent"
	shop.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(center + Vector3.new(x, y, z))
	end

	local blue = Color3.fromRGB(45, 95, 200)
	local cream = Color3.fromRGB(246, 240, 225)
	local gold = Color3.fromRGB(255, 200, 60)
	local radius = 11.5
	local wallHeight = 8
	local apex = 19
	local panels = 18

	-- Round wooden floor with a gold rim
	local floor = block(shop, "TentFloor", Vector3.new(1, radius * 2 + 1, radius * 2 + 1), at(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(165, 120, 80), Enum.Material.WoodPlanks)
	floor.Shape = Enum.PartType.Cylinder
	local rim = block(shop, "TentRim", Vector3.new(0.6, radius * 2 + 2, radius * 2 + 2), at(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), gold, Enum.Material.Foil)
	rim.Shape = Enum.PartType.Cylinder

	-- Striped canvas walls, open at the front for the entrance
	local panelWidth = 2 * math.pi * radius / panels + 0.3
	for i = 0, panels - 1 do
		local angle = (i + 0.5) / panels * math.pi * 2
		local direction = Vector3.new(math.sin(angle), 0, -math.cos(angle)) -- angle 0 = front (-Z)
		if math.abs(math.deg(angle) - 360 * math.round(angle / (2 * math.pi))) > 32 then
			local position = center + direction * radius + Vector3.new(0, 1 + wallHeight / 2, 0)
			local panel = block(shop, "Canvas", Vector3.new(panelWidth, wallHeight, 0.4), CFrame.lookAt(position, center + Vector3.new(0, 1 + wallHeight / 2, 0)), if i % 2 == 0 then blue else cream, Enum.Material.Fabric)
			panel.CastShadow = true
		end
	end

	-- Peaked striped roof: canvas strips from the rim up to the top
	local slant = math.sqrt(radius ^ 2 + (apex - wallHeight - 1) ^ 2)
	for i = 0, panels - 1 do
		local angle = (i + 0.5) / panels * math.pi * 2
		local direction = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local rimPoint = center + direction * (radius + 0.6) + Vector3.new(0, wallHeight + 0.7, 0)
		local top = center + Vector3.new(0, apex, 0)
		local mid = (rimPoint + top) / 2
		local strip = block(shop, "RoofCanvas", Vector3.new(panelWidth + 0.4, 0.35, slant + 0.8), CFrame.lookAt(mid, top), if i % 2 == 0 then blue else cream, Enum.Material.Fabric)
		strip.CastShadow = true
		-- Scalloped gold trim hanging off the edge of the roof
		local scallop = block(shop, "Scallop", Vector3.new(1.6, 1.6, 1.6), CFrame.new(center + direction * (radius + 0.9) + Vector3.new(0, wallHeight + 0.2, 0)), if i % 2 == 0 then gold else cream, Enum.Material.SmoothPlastic)
		scallop.Shape = Enum.PartType.Ball
		scallop.CanCollide = false
	end

	-- Center pole, gold top and a flag
	local pole = block(shop, "TentPole", Vector3.new(0.6, apex + 4, 0.6), at(0, (apex + 4) / 2, 0), Color3.fromRGB(120, 85, 55), Enum.Material.WoodPlanks)
	pole.CanCollide = false
	local finial = block(shop, "Finial", Vector3.new(1.4, 1.4, 1.4), at(0, apex + 4.4, 0), gold, Enum.Material.Foil)
	finial.Shape = Enum.PartType.Ball
	local flag = block(shop, "Flag", Vector3.new(0.15, 2, 3.2), at(0, apex + 3, 1.7), blue, Enum.Material.Fabric)
	flag.CanCollide = false

	-- A big shard crystal spinning over the tent (spun by Effects.client)
	local cyan = Color3.fromRGB(80, 220, 255)
	local crystal = block(shop, "BigShard", Vector3.new(2, 4.5, 2), at(0, apex + 8, 0) * CFrame.Angles(0, math.rad(45), 0), cyan, Enum.Material.Neon)
	crystal.CanCollide = false
	crystal:SetAttribute("SpinCenter", crystal.CFrame)
	CollectionService:AddTag(crystal, "Spinner")
	local glow = Instance.new("PointLight")
	glow.Color = cyan
	glow.Range = 20
	glow.Brightness = 1
	glow.Parent = crystal

	-- Two counters inside, each with a prompt and a sign
	local counters = {
		{ X = -4.5, Color = cyan, Action = "ShardShop", Text = "Shard Shop", Sign = "SHARDS" },
		{ X = 4.5, Color = Color3.fromRGB(70, 220, 100), Action = "RobuxShop", Text = "Robux Shop", Sign = "ROBUX & EVENT" },
	}
	for _, info in counters do
		local counter = block(shop, "Counter", Vector3.new(7, 3.5, 2.5), at(info.X, 2.75, 4), Color3.fromRGB(150, 105, 70), Enum.Material.WoodPlanks)
		block(shop, "CounterTop", Vector3.new(7.4, 0.4, 2.9), at(info.X, 4.7, 4), info.Color, Enum.Material.Neon)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = info.Text
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", info.Action)
		prompt.Parent = counter
		local label = billboard(counter, Vector2.new(220, 45), Vector3.new(0, 4.5, 0), info.Sign, info.Color)
		;(label.Parent :: BillboardGui).MaxDistance = 250
	end
	-- Warm lantern light inside
	local lantern = block(shop, "Lantern", Vector3.new(1.2, 1.2, 1.2), at(0, wallHeight + 1, 0), Color3.fromRGB(255, 220, 150), Enum.Material.Neon)
	lantern.Shape = Enum.PartType.Ball
	lantern.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = lantern

	-- Sign over the entrance
	local signAnchor = block(shop, "ShopSignAnchor", Vector3.new(1, 1, 1), at(0, wallHeight + 4, -radius - 1), Color3.new(0, 0, 0))
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	local sign = billboard(signAnchor, Vector2.new(420, 80), Vector3.zero, "SHOP", gold)
	;(sign.Parent :: BillboardGui).MaxDistance = 500
end

function WorldBuilder.Build(): World
	local existing = workspace:FindFirstChild("BrainrotHeist")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "BrainrotHeist"
	root.Parent = workspace

	-- A Baseplate sitting too high would bury the map; put its top at y = 0.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		-- Tucked under our own grass ground, out of sight.
		baseplate.CFrame = CFrame.new(0, -12 - baseplate.Size.Y / 2, 0)
	end

	Lighting.ClockTime = 14
	Lighting.Brightness = 1.3
	Lighting.ExposureCompensation = -0.35
	-- Light haze so the far edge of the grass fades into the sky.
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(200, 215, 230)
		atmosphere.Decay = Color3.fromRGB(110, 125, 145)
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end

	-- Ground under everything, in case the Baseplate was removed. Its top sits
	-- slightly above the Baseplate's so the two surfaces don't flicker.
	buildGround(root)
	buildLighting()

	-- Conveyor
	local columnsPerSide = Config.PlotCount // 2
	-- Long enough to leave room past the bases for the caves, shop and statue.
	local length = columnsPerSide * PLOT_SPACING + 160
	local conveyorFolder = Instance.new("Folder")
	conveyorFolder.Name = "Conveyor"
	conveyorFolder.Parent = root

	block(conveyorFolder, "Belt", Vector3.new(length, 1, 12), CFrame.new(0, 0.5, 0), Color3.fromRGB(40, 40, 45), Enum.Material.DiamondPlate)
	for _, z in { -6.5, 6.5 } do
		block(conveyorFolder, "Rail", Vector3.new(length, 1.5, 1), CFrame.new(0, 1.25, z), Color3.fromRGB(240, 185, 40), Enum.Material.SmoothPlastic) -- (Neon glared)
	end

	-- Brainrots spawn inside one cave, ride out of its mouth, and disappear
	-- into a second cave at the far end.
	local mouthX = -length / 2 + 14
	local exitMouthX = length / 2 - 14
	local sceneryRng = Random.new(2026)
	buildLakes(root)
	buildCaveHill(root, sceneryRng, mouthX, 1)
	buildCaveHill(root, sceneryRng, exitMouthX, -1)
	buildTrees(root, sceneryRng)
	buildBarrier(root)
	buildCave(root, "BrainrotCave", Vector3.new(mouthX, 0, 0), 1, 7)
	buildCave(root, "ExitCave", Vector3.new(exitMouthX, 0, 0), -1, 11)
	local startX = mouthX - 10
	local endX = exitMouthX + 10
	local sign = block(conveyorFolder, "ShopSign", Vector3.new(1, 1, 1), CFrame.new(mouthX + 6, 28, 0), Color3.new(1, 1, 1))
	sign.Transparency = 1
	sign.CanCollide = false
	local signLabel = billboard(sign, Vector2.new(420, 90), Vector3.zero, "BRAINROT CONVEYOR\nBuy one before it's gone!", Color3.fromRGB(255, 230, 80))
	;(signLabel.Parent :: BillboardGui).MaxDistance = 500

	-- Plots: half on each side of the conveyor, entrances facing it.
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root

	local plots = {}
	local plotCenters = {}
	for i = 1, Config.PlotCount do
		local side = if i <= columnsPerSide then 1 else -1
		local column = (i - 1) % columnsPerSide
		local x = (column - (columnsPerSide - 1) / 2) * PLOT_SPACING
		plotCenters[i] = Vector3.new(x, 0, side * PLOT_DISTANCE)
		plots[i] = buildPlot(plotsFolder, i, plotCenters[i])
		WorldBuilder.SetWallLevel(plots[i], 1, 1)
		WorldBuilder.SetStories(plots[i], 1)
		WorldBuilder.SetCarpet(plots[i], 0)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	-- Beside the middle of the conveyor, right in front of the Shard Shop.
	-- The shop tent sits by the cave the brainrots come out of, with the event
	-- statue right beside it, keeping the middle clear.
	local shopPosition = Vector3.new(startX + 50, 0, 45)
	local statuePosition = shopPosition + Vector3.new(20, 0, -5)
	local nextStatuePosition = statuePosition + Vector3.new(17, 0, 0)
	buildShop(root, shopPosition)
	-- The Sell Stand: just past the two event statues, still by the shop.
	local sellPosition = shopPosition + Vector3.new(56, 0, 2)
	buildSellStand(root, sellPosition)

	-- Stone paths: a walkway along each side of the conveyor, with a branch
	-- to every base's door, the shop tent and the event statue.
	local pathsFolder = Instance.new("Folder")
	pathsFolder.Name = "Paths"
	pathsFolder.Parent = root
	local walkEnd = exitMouthX - 4
	for _, side in { 1, -1 } do
		path(pathsFolder, Vector3.new(mouthX + 4, 0, side * 15), Vector3.new(walkEnd, 0, side * 15), 10)
	end
	path(pathsFolder, Vector3.new(shopPosition.X, 0, 20), Vector3.new(shopPosition.X, 0, 33), 8)
	for _, position in { statuePosition, nextStatuePosition } do
		path(pathsFolder, Vector3.new(position.X, 0, 20), Vector3.new(position.X, 0, position.Z - 5), 6)
	end
	for _, center in plotCenters do
		local side = math.sign(center.Z)
		path(pathsFolder, Vector3.new(center.X, 0, side * 20), Vector3.new(center.X, 0, center.Z - side * (PLOT_SIZE / 2 + 1)), 12)
	end
	spawn.Size = Vector3.new(10, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 14)
	-- Invisible pad: players still spawn here, there's just no plate to see.
	spawn.Transparency = 1
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	-- Any template spawn would drop players onto the conveyor; ours replaces it.
	for _, other in workspace:GetChildren() do
		if other:IsA("SpawnLocation") then
			other.Enabled = false
		end
	end

	local carried = Instance.new("Folder")
	carried.Name = "Carried"
	carried.Parent = root

	return {
		Plots = plots,
		ConveyorStart = Vector3.new(startX, 1, 0),
		ConveyorEnd = Vector3.new(endX, 1, 0),
		CarriedFolder = carried,
		ConveyorFolder = conveyorFolder,
		ShopPosition = shopPosition,
		StatuePosition = statuePosition,
		NextStatuePosition = nextStatuePosition,
		SellPosition = sellPosition,
	}
end

return WorldBuilder

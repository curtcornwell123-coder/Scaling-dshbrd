--!strict
-- Physical showcase props for shops, kiosks and podiums: spinning display
-- balls, realistic crates and chests, floating info cards. Motion is done on
-- clients (tag "Spin" + SpinSpeed for parts, tag "Bob" for crate models).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Parts = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("Parts"))

local Displays = {}

local T = UIKit.Theme

function Displays.anchorPoint(pedestal: BasePart): Vector3
	local a = pedestal:FindFirstChild("Display")
	if a and a:IsA("Attachment") then
		return a.WorldPosition
	end
	return pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + 2.5, 0)
end

function Displays.spin(part: BasePart, speed: number?)
	part:SetAttribute("SpinSpeed", speed or 1.5)
	CollectionService:AddTag(part, "Spin")
end

-- A 3-stud showcase ball wearing `skinId`.
function Displays.ball(parent: Instance, position: Vector3, skinId: string, diameter: number?): Part
	local d = diameter or 3
	local p = Instance.new("Part")
	p.Name = "DisplayBall"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * d
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	Skins.apply(p, skinId)
	Displays.spin(p, 1.5)
	p.Parent = parent
	return p
end

-- Crates are built like real ones: a plank-built wooden crate (posts, rims, iron
-- corner brackets, painted band in the crate's colour, iron lock plate with a gem)
-- or, for style "chest", an arched treasure chest with gold fittings. No neon: the
-- crate's colour shows as paint, a glass gem and a soft light.
export type CrateStyle = "crate" | "chest"

local WOOD = Color3.fromRGB(156, 108, 64)
local WOOD_DARK = Color3.fromRGB(96, 64, 38)
local WOOD_CORE = Color3.fromRGB(52, 34, 20)
local IRON = Color3.fromRGB(58, 61, 68)
local GOLD = Color3.fromRGB(214, 168, 64)

local function jitter(c: Color3, seed: number): Color3
	local k = ((seed * 7919) % 13) / 13 - 0.5
	return c:Lerp(if k > 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(k) * 0.18)
end

local function buildCrate(m: Model, base: CFrame, color: Color3, s: number): BasePart
	local W, H, D = s, s * 0.82, s * 0.82
	local post = s * 0.1
	local plank = 0.13 * s / 3.2
	local gap = 0.035 * s / 3.2
	local function blk(cf: CFrame, size: Vector3, props: Parts.Props): Part
		return Parts.block(m, base * cf, size, props)
	end
	-- Dark core so the plank gaps read as depth.
	local core = blk(CFrame.new(), Vector3.new(W - plank * 1.6, H - plank * 1.6, D - plank * 1.6), { Color = WOOD_CORE, Material = Enum.Material.Wood, Name = "Body" })
	-- Side planks: 4 rows per face; the middle-upper row is painted in the crate colour.
	local rows = 4
	local inner = H - post * 2
	local rowH = inner / rows
	local seed = 0
	for face = 0, 3 do
		local yaw = face * math.pi / 2
		local span = if face % 2 == 0 then W - post * 2 else D - post * 2
		local dist = (if face % 2 == 0 then D else W) / 2 - plank / 2
		for r = 1, rows do
			seed += 1
			local y = -inner / 2 + (r - 0.5) * rowH
			local painted = r == 3
			blk(CFrame.Angles(0, yaw, 0) * CFrame.new(0, y, dist), Vector3.new(span, rowH - gap, plank), {
				Color = if painted then color:Lerp(WOOD_DARK, 0.25) else jitter(WOOD, seed),
				Material = Enum.Material.Wood,
				Name = "Plank",
			})
		end
		-- Top and bottom rims on this face.
		for _, y in { H / 2 - post / 2, -H / 2 + post / 2 } do
			blk(CFrame.Angles(0, yaw, 0) * CFrame.new(0, y, dist + plank * 0.25), Vector3.new(span + post * 2, post, plank * 1.5), {
				Color = WOOD_DARK,
				Material = Enum.Material.Wood,
				Name = "Rim",
			})
		end
	end
	-- Diagonal brace boards on the two ends (classic shipping-crate Z brace).
	for _, sx in { -1, 1 } do
		local len = math.sqrt((D - post * 2) ^ 2 + (inner * 0.92) ^ 2)
		local ang = math.atan2(inner * 0.92, D - post * 2)
		blk(CFrame.new(sx * (W / 2 + plank * 0.15), 0, 0) * CFrame.Angles(sx * ang, 0, 0), Vector3.new(plank, post * 0.85, len), {
			Color = WOOD_DARK,
			Material = Enum.Material.Wood,
			Name = "Brace",
		})
	end
	-- Corner posts with iron brackets top and bottom.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (W / 2 - post / 2 + plank * 0.3), sz * (D / 2 - post / 2 + plank * 0.3)
			blk(CFrame.new(x, 0, z), Vector3.new(post, H + plank * 0.4, post), { Color = WOOD_DARK, Material = Enum.Material.Wood, Name = "Post" })
			for _, sy in { -1, 1 } do
				local y = sy * (H / 2 - post * 0.6)
				blk(CFrame.new(x + sx * 0.012, y, z), Vector3.new(post + 0.06, post * 1.3, post + 0.06), { Color = IRON, Material = Enum.Material.Metal, Name = "Bracket" })
			end
		end
	end
	-- Lid: three planks across the top, slightly overhanging, with a hairline seam below.
	local lidY = H / 2 + plank * 0.5
	for i = -1, 1 do
		seed += 1
		blk(CFrame.new(0, lidY, i * (D + 0.08) / 3), Vector3.new(W + 0.08, plank * 1.4, (D + 0.08) / 3 - gap), {
			Color = jitter(WOOD, seed),
			Material = Enum.Material.Wood,
			Name = "Lid",
		})
	end
	blk(CFrame.new(0, H / 2 - post - gap, 0), Vector3.new(W + 0.02, gap * 1.5, D + 0.02), { Color = WOOD_CORE, Name = "Seam" })
	-- Iron lock plate, brass padlock and a glass gem in the crate colour.
	local front = -D / 2 - plank * 0.6
	blk(CFrame.new(0, H * 0.18, front), Vector3.new(W * 0.34, H * 0.36, 0.06), { Color = IRON, Material = Enum.Material.Metal, Name = "LockPlate" })
	blk(CFrame.new(0, H * 0.08, front - 0.08), Vector3.new(W * 0.13, H * 0.15, 0.12), { Color = GOLD, Material = Enum.Material.Metal, Name = "Padlock" })
	for _, sx in { -1, 1 } do
		Parts.rod(m, (base * CFrame.new(sx * W * 0.045, H * 0.15, front - 0.08)).Position, (base * CFrame.new(sx * W * 0.045, H * 0.24, front - 0.08)).Position, 0.06, { Color = GOLD, Material = Enum.Material.Metal, Name = "Shackle" })
	end
	Parts.rod(m, (base * CFrame.new(-W * 0.045, H * 0.24, front - 0.08)).Position, (base * CFrame.new(W * 0.045, H * 0.24, front - 0.08)).Position, 0.06, { Color = GOLD, Material = Enum.Material.Metal, Name = "Shackle" })
	local gem = Parts.ball(m, (base * CFrame.new(0, H * 0.31, front - 0.04)).Position, s * 0.11, { Color = color:Lerp(Color3.new(1, 1, 1), 0.25), Material = Enum.Material.Glass, Transparency = 0.05, Reflectance = 0.3, Name = "Gem" })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = gem
	-- A dimpled golf ball set into the lid: the Ultimate Golf mark.
	local mark = Parts.ball(m, (base * CFrame.new(0, lidY + plank * 0.5, 0)).Position, s * 0.2, { Color = Color3.new(1, 1, 1), Name = "Emblem" })
	Skins.apply(mark, "classic_white")
	return core
end

local function buildChest(m: Model, base: CFrame, color: Color3, s: number): BasePart
	local W, H, D = s * 1.15, s * 0.55, s * 0.72
	local lacquer = color:Lerp(Color3.fromRGB(40, 12, 18), 0.55)
	local function blk(cf: CFrame, size: Vector3, props: Parts.Props): Part
		return Parts.block(m, base * cf, size, props)
	end
	local body = blk(CFrame.new(0, -H / 2, 0), Vector3.new(W, H, D), { Color = lacquer, Material = Enum.Material.Wood, Name = "Body" })
	-- Arched lid: a cylinder along X sits half inside the body; its top half is the arch.
	local lid = Parts.block(m, base * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0), Vector3.new(W - 0.04, D, D), { Color = lacquer:Lerp(Color3.new(0, 0, 0), 0.1), Material = Enum.Material.Wood, Name = "Lid", Shape = Enum.PartType.Cylinder })
	lid.CanCollide = false
	-- Gold edging along the base, the lid line and the corners.
	for _, y in { -H + 0.06, -0.04 } do
		blk(CFrame.new(0, y, 0), Vector3.new(W + 0.06, 0.12, D + 0.06), { Color = GOLD, Material = Enum.Material.Metal, Name = "Trim" })
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(CFrame.new(sx * (W / 2 - 0.06), -H / 2, sz * (D / 2 - 0.06)), Vector3.new(0.16, H + 0.04, 0.16), { Color = GOLD, Material = Enum.Material.Metal, Name = "Corner" })
			Parts.ball(m, (base * CFrame.new(sx * (W / 2 - 0.1), -H - 0.08, sz * (D / 2 - 0.1))).Position, 0.26, { Color = GOLD, Material = Enum.Material.Metal, Name = "Foot" })
		end
	end
	-- Two gold straps running over the arch (8 short segments each) and down the body.
	local r = D / 2 + 0.03
	for _, x in { -W * 0.3, W * 0.3 } do
		blk(CFrame.new(x, -H / 2, -D / 2 - 0.02), Vector3.new(0.22, H, 0.05), { Color = GOLD, Material = Enum.Material.Metal, Name = "Strap" })
		blk(CFrame.new(x, -H / 2, D / 2 + 0.02), Vector3.new(0.22, H, 0.05), { Color = GOLD, Material = Enum.Material.Metal, Name = "Strap" })
		for k = 0, 7 do
			local a = math.pi * (k + 0.5) / 8
			local pos = CFrame.new(x, math.sin(a) * r, -math.cos(a) * r)
			blk(pos * CFrame.Angles(a - math.pi / 2, 0, 0), Vector3.new(0.22, 0.05, math.pi * r / 8 + 0.02), { Color = GOLD, Material = Enum.Material.Metal, Name = "Strap" })
		end
	end
	-- Big gold lock plate with a jewel in the crate colour and a keyhole.
	local front = -D / 2 - 0.05
	blk(CFrame.new(0, -0.12, front), Vector3.new(W * 0.24, H * 0.62, 0.08), { Color = GOLD, Material = Enum.Material.Metal, Name = "LockPlate" })
	blk(CFrame.new(0, -0.32, front - 0.05), Vector3.new(0.07, 0.16, 0.04), { Color = Color3.fromRGB(20, 14, 10), Name = "Keyhole" })
	local gem = Parts.ball(m, (base * CFrame.new(0, -0.02, front - 0.06)).Position, s * 0.1, { Color = color, Material = Enum.Material.Glass, Transparency = 0.1, Reflectance = 0.25, Name = "Gem" })
	local light = Instance.new("PointLight")
	light.Color = GOLD:Lerp(color, 0.4)
	light.Range = 12
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = gem
	return body
end

-- A display crate centred on `position`. `size` is the crate's width in studs.
function Displays.crate(parent: Instance, position: Vector3, color: Color3, size: number?, style: CrateStyle?): Model
	local s = size or 3.2
	local m = Instance.new("Model")
	m.Name = "Crate"
	local base = CFrame.new(position)
	local root = if style == "chest" then buildChest(m, base, color, s) else buildCrate(m, base, color, s)
	m.PrimaryPart = root
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Parent = parent
	return m
end

-- Gentle bob + turn for a crate, animated on each client (nothing replicates per frame).
function Displays.bob(model: Model)
	model:SetAttribute("BobAmp", 0.22)
	model:SetAttribute("BobTurn", 0.45)
	CollectionService:AddTag(model, "Bob")
end

export type Card = { Gui: BillboardGui, Title: TextLabel, Sub: TextLabel, Price: TextLabel, Dot: Frame }

-- Floating info card (name / rarity / price) above a display.
function Displays.card(adornee: BasePart, offsetY: number, title: string, sub: string, price: string, dotColor: Color3): Card
	local gui = Instance.new("BillboardGui")
	gui.Name = "InfoCard"
	gui.Size = UDim2.fromOffset(190, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 20 -- only the displays you walk up to show their card
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local panel = UIKit.panel({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.08, Parent = gui })
	UIKit.padding(panel, 8, 10)
	UIKit.list(panel, 2)
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 22)
	head.LayoutOrder = 1
	head.Parent = panel
	UIKit.list(head, 6, true)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = dotColor
	dot.BorderSizePixel = 0
	dot.LayoutOrder = 1
	UIKit.corner(dot, UDim.new(0, 2))
	dot.Parent = head
	local t = UIKit.text({ Text = title, TextSize = 17, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), LayoutOrder = 2, Parent = head })
	local sub2 = UIKit.text({ Text = sub, TextSize = 13, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, Parent = panel })
	local p = UIKit.text({ Text = price, TextSize = 15, TextColor3 = T.Gold, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, Parent = panel })
	gui.Parent = adornee
	return { Gui = gui, Title = t, Sub = sub2, Price = p, Dot = dot }
end

-- Reveal pop above a crate: the won ball (or a glowing orb for other
-- categories) rises out with a name card, visible to everyone nearby.
function Displays.reveal(parent: Instance, from: Vector3, skinId: string?, color: Color3, title: string, sub: string)
	local p: Part
	if skinId then
		p = Displays.ball(parent, from, skinId, 2.4)
	else
		p = Parts.ball(parent, from, 2, { Color = color, Material = Enum.Material.Neon, CanCollide = false })
		p.CanQuery = false
		Displays.spin(p, 3)
	end
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(color)
	burst.LightEmission = 1
	burst.Speed = NumberRange.new(8, 14)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Size = NumberSequence.new(0.6, 0)
	burst.Rate = 0
	burst.Parent = p
	burst:Emit(40)
	Displays.card(p, 2.6, title, sub, "", color)
	TweenService:Create(p, TweenInfo.new(1.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(from + Vector3.new(0, 3.5, 0)),
	}):Play()
	task.delay(4, function()
		p:Destroy()
	end)
end

Displays.Config = Config

return Displays

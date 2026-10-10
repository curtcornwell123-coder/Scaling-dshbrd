--!strict
-- Thumbnails for catalog cards, built from the same configs the game uses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Crates = require(Shared:WaitForChild("Crates"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Previews = {}

local T = UIKit.Theme

local function base(): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = T.SurfaceHi
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	UIKit.corner(f, T.RadiusSmall)
	return f
end

local function circle(parent: Instance, size: number, color: Color3, pos: UDim2, transparency: number?): Frame
	local c = Instance.new("Frame")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = pos
	c.Size = UDim2.fromOffset(size, size)
	c.BackgroundColor3 = color
	c.BackgroundTransparency = transparency or 0
	c.BorderSizePixel = 0
	UIKit.corner(c, UDim.new(1, 0))
	c.Parent = parent
	return c
end

function Previews.ball(skinId: string): Frame
	local f = base()
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 155, 170)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.4)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 3
	ball.CFrame = CFrame.new()
	ball.Anchored = true
	Skins.apply(ball, skinId)
	ball.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 7.2), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = f
	local skin = Skins.get(skinId)
	local order = Skins.Rarities[skin.Rarity].Order
	if order >= Skins.Rarities.Epic.Order then
		-- ViewportFrames don't render particles: hint at the built-in aura instead.
		local glow = circle(f, 86, (Skins.effects(skin)) or skin.Color, UDim2.fromScale(0.5, 0.5), 0.82)
		glow.ZIndex = 0
		vp.ZIndex = 1
	end
	return f
end

function Previews.trail(id: string): Frame
	local f = base()
	local def = Cosmetics.get("Trails", id)
	if not def or not def.Colors or id == "none" then
		UIKit.text({ Text = "No trail", TextSize = 14, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = f })
		return f
	end
	local ribbon = Instance.new("Frame")
	ribbon.AnchorPoint = Vector2.new(0, 0.5)
	ribbon.Position = UDim2.new(0.1, 0, 0.5, 0)
	ribbon.Size = UDim2.new(0.62, 0, 0, math.floor(10 + (def.Width or 0.5) * 18))
	ribbon.BorderSizePixel = 0
	ribbon.BackgroundColor3 = Color3.new(1, 1, 1)
	UIKit.corner(ribbon, UDim.new(1, 0))
	local grad = Instance.new("UIGradient")
	local keys = {}
	local colors = def.Colors :: { Color3 }
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else 1 - (i - 1) / (#colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	table.sort(keys, function(a, b)
		return a.Time < b.Time
	end)
	grad.Color = ColorSequence.new(keys)
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	grad.Parent = ribbon
	ribbon.Parent = f
	circle(f, 26, Color3.fromRGB(244, 246, 250), UDim2.new(0.76, 0, 0.5, 0))
	return f
end

function Previews.arrow(id: string): Frame
	local f = base()
	local def = Cosmetics.getOrDefault("Arrows", id)
	local tip = def.Tip or def.Color
	local style = def.Style or "Classic"
	if style == "Dotted" or style == "Comet" then
		for i = 1, 6 do
			local size = if style == "Comet" then 6 + i * 2 else 9
			circle(f, size, def.Color:Lerp(tip, i / 6), UDim2.new(0.12 + i * 0.1, 0, 0.5, 0))
		end
	elseif style == "Chevron" then
		for i = 1, 4 do
			local chev = UIKit.text({
				Text = "›",
				TextSize = 46,
				Font = T.FontHeavy,
				TextColor3 = def.Color:Lerp(tip, i / 4),
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.18 + i * 0.13, 0, 0.47, 0),
				Size = UDim2.fromOffset(30, 50),
				Parent = f,
			})
			chev.RichText = false
		end
	else
		local shaft = Instance.new("Frame")
		shaft.AnchorPoint = Vector2.new(0, 0.5)
		shaft.Position = UDim2.new(0.14, 0, 0.5, 0)
		shaft.Size = UDim2.new(0.58, 0, 0, if style == "Laser" then 4 else 8)
		shaft.BorderSizePixel = 0
		shaft.BackgroundColor3 = Color3.new(1, 1, 1)
		UIKit.corner(shaft, UDim.new(1, 0))
		local grad = Instance.new("UIGradient")
		grad.Color = if style == "Rainbow"
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.8, 1)),
				ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 0.8, 1)),
				ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.6, 0.8, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(0.8, 0.8, 1)),
			})
			else ColorSequence.new(def.Color, tip)
		grad.Parent = shaft
		shaft.Parent = f
	end
	local head = Instance.new("Frame")
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.new(0.78, 0, 0.5, 0)
	head.Size = UDim2.fromOffset(20, 20)
	head.Rotation = 45
	head.BorderSizePixel = 0
	head.BackgroundColor3 = tip
	UIKit.corner(head, UDim.new(0, 3))
	head.Parent = f
	return f
end

function Previews.knockout(id: string): Frame
	local f = base()
	local def = Cosmetics.getOrDefault("Knockouts", id)
	circle(f, 70, def.Color, UDim2.fromScale(0.5, 0.5), 0.8)
	circle(f, 34, def.Color, UDim2.fromScale(0.5, 0.5), 0.2)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		circle(f, 8, def.Color, UDim2.new(0.5, math.cos(a) * 44, 0.5, math.sin(a) * 36))
	end
	UIKit.text({
		Text = def.Style or "",
		TextSize = 12,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -6, 1, -4),
		Size = UDim2.fromOffset(90, 14),
		Parent = f,
	})
	return f
end

function Previews.crate(id: string): Frame
	local f = base()
	local crate = Crates.get(id)
	local color = if crate then crate.Color else T.Info
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.52)
	box.Size = UDim2.fromOffset(70, 60)
	box.BackgroundColor3 = color
	box.BorderSizePixel = 0
	UIKit.corner(box, UDim.new(0, 8))
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.2), color:Lerp(Color3.new(0, 0, 0), 0.25))
	grad.Parent = box
	box.Parent = f
	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 6)
	band.Position = UDim2.fromScale(0, 0.3)
	band.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.55)
	band.BorderSizePixel = 0
	band.Parent = box
	circle(box, 18, Color3.fromRGB(244, 246, 250), UDim2.fromScale(0.5, 0.64))
	return f
end

function Previews.pass(key: string): Frame
	local f = base()
	local glyph = ({ VIP = "VIP", DoubleCoins = "2X", Celebrations = "✦", Founder = "F" })[key] or "★"
	circle(f, 64, T.Gold, UDim2.fromScale(0.5, 0.5), 0.75)
	UIKit.text({ Text = glyph, TextSize = 28, Font = T.FontHeavy, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = f })
	return f
end

function Previews.coins(key: string): Frame
	local f = base()
	local product = Config.DevProducts[key]
	local count = if product and product.Coins then math.clamp(math.floor(math.log10(product.Coins) * 2) - 3, 2, 6) else 3
	for i = 1, count do
		circle(f, 30, T.Gold:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.12), UDim2.new(0.5, (i - (count + 1) / 2) * 16, 0.5, -(i % 2) * 6))
	end
	return f
end

function Previews.make(kind: string, ref: string): Frame
	if kind == "Ball" then
		return Previews.ball(ref)
	elseif kind == "Trail" then
		return Previews.trail(ref)
	elseif kind == "Arrow" then
		return Previews.arrow(ref)
	elseif kind == "Knockout" then
		return Previews.knockout(ref)
	elseif kind == "Crate" then
		return Previews.crate(ref)
	elseif kind == "Pass" then
		return Previews.pass(ref)
	elseif kind == "Coins" then
		return Previews.coins(ref)
	end
	return base()
end

return Previews

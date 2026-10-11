--!strict
-- One design system for every 2D surface in the game: the screen HUD and all
-- in-world kiosk / board SurfaceGuis. Modern and calm: slate base, off-white
-- text, subtle 8px corners, consistent 8/12px spacing, and only two accents
-- (Primary green for Buy/Equip CTAs, Info blue for secondary actions).
-- Rarity / quadrant colours appear only as small indicators, never as fills.

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Theme = {
	Base = Color3.fromRGB(24, 28, 36),
	Surface = Color3.fromRGB(32, 37, 48),
	SurfaceHi = Color3.fromRGB(42, 48, 62),
	Stroke = Color3.fromRGB(58, 66, 84),
	Text = Color3.fromRGB(240, 243, 248),
	Muted = Color3.fromRGB(148, 158, 178),
	Primary = Color3.fromRGB(46, 212, 122), -- Buy / Equip / Play
	PrimaryText = Color3.fromRGB(12, 28, 20),
	Info = Color3.fromRGB(61, 169, 255), -- secondary actions, selection
	Danger = Color3.fromRGB(235, 87, 87), -- errors only
	Gold = Color3.fromRGB(255, 200, 61), -- coin glyphs only
	Radius = UDim.new(0, 8),
	RadiusSmall = UDim.new(0, 6),
	Gap = 8,
	Pad = 12,
	Font = Enum.Font.GothamBold,
	FontMedium = Enum.Font.GothamMedium,
	FontHeavy = Enum.Font.GothamBlack,
}

local T = UIKit.Theme

export type Props = { [string]: any }

local function assign(inst: Instance, props: Props?)
	if props then
		for k, v in props do
			if k ~= "Parent" and k ~= "Children" then
				(inst :: any)[k] = v
			end
		end
	end
end

local function finish<T>(inst: T & Instance, props: Props?): T
	if props then
		if props.Children then
			for _, child in props.Children do
				(child :: Instance).Parent = inst
			end
		end
		if props.Parent then
			inst.Parent = props.Parent
		end
	end
	return inst
end

function UIKit.corner(parent: Instance, radius: UDim?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or T.Radius
	c.Parent = parent
	return c
end

function UIKit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or T.Stroke
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UIKit.padding(parent: Instance, all: number?, horizontal: number?): UIPadding
	local p = Instance.new("UIPadding")
	local v = all or T.Pad
	local h = horizontal or v
	p.PaddingTop = UDim.new(0, v)
	p.PaddingBottom = UDim.new(0, v)
	p.PaddingLeft = UDim.new(0, h)
	p.PaddingRight = UDim.new(0, h)
	p.Parent = parent
	return p
end

function UIKit.list(parent: Instance, gap: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or T.Gap)
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	if horizontal then
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	l.Parent = parent
	return l
end

function UIKit.grid(parent: Instance, cell: UDim2, gap: number?): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.CellSize = cell
	g.CellPadding = UDim2.fromOffset(gap or T.Gap, gap or T.Gap)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Left
	g.Parent = parent
	return g
end

-- Panel: rounded slate container with a hairline stroke.
function UIKit.panel(props: Props?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = T.Base
	f.BorderSizePixel = 0
	assign(f, props)
	UIKit.corner(f)
	UIKit.stroke(f)
	return finish(f, props)
end

-- Card: raised surface used for grid items and rows.
function UIKit.card(props: Props?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = T.Surface
	f.BorderSizePixel = 0
	assign(f, props)
	UIKit.corner(f)
	UIKit.stroke(f, T.Stroke, 1, 0.3)
	return finish(f, props)
end

function UIKit.text(props: Props?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = T.Font
	t.TextColor3 = T.Text
	t.TextSize = 18
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextWrapped = true
	t.RichText = true
	assign(t, props)
	return finish(t, props)
end

-- Small rounded tag (rarity, status). `color` is only used for the dot + text.
function UIKit.tag(text: string, color: Color3, props: Props?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = T.SurfaceHi
	f.BorderSizePixel = 0
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 22)
	assign(f, props)
	UIKit.corner(f, T.RadiusSmall)
	UIKit.padding(f, 0, 8)
	UIKit.list(f, 6, true)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	UIKit.corner(dot, UDim.new(0, 2))
	dot.LayoutOrder = 1
	dot.Parent = f
	UIKit.text({
		Text = text,
		TextSize = 13,
		Font = T.Font,
		TextColor3 = color,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = 2,
		Parent = f,
	})
	return finish(f, props)
end

export type ButtonVariant = "Primary" | "Secondary" | "Ghost" | "Disabled"

local function variantColors(variant: ButtonVariant): (Color3, Color3)
	if variant == "Primary" then
		return T.Primary, T.PrimaryText
	elseif variant == "Secondary" then
		return T.SurfaceHi, T.Text
	elseif variant == "Disabled" then
		return T.Surface, T.Muted
	end
	return T.Base, T.Muted
end

-- Button with hover / press feedback (UIScale + colour tweens). Hover works on
-- ScreenGuis and on SurfaceGuis that live in PlayerGui (Adornee set).
function UIKit.button(text: string, variant: ButtonVariant, props: Props?, onClick: (() -> ())?): TextButton
	local bg, fg = variantColors(variant)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = bg
	b.BorderSizePixel = 0
	b.Font = T.Font
	b.TextSize = 16
	b.TextColor3 = fg
	b.Text = text
	b.Size = UDim2.fromOffset(120, 36)
	assign(b, props)
	UIKit.corner(b)
	if variant == "Ghost" or variant == "Secondary" then
		UIKit.stroke(b, T.Stroke, 1, 0)
	end
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b:SetAttribute("Variant", variant)

	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local hoverBg = bg:Lerp(Color3.new(1, 1, 1), if variant == "Primary" then 0.12 else 0.06)
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Variant") == "Disabled" then
			return
		end
		TweenService:Create(scale, info, { Scale = 1.04 }):Play()
		TweenService:Create(b, info, { BackgroundColor3 = hoverBg }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
		TweenService:Create(b, info, { BackgroundColor3 = bg }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		if b:GetAttribute("Variant") ~= "Disabled" then
			TweenService:Create(scale, info, { Scale = 0.97 }):Play()
		end
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, info, { Scale = 1.04 }):Play()
	end)
	if onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("Variant") ~= "Disabled" then
				onClick()
			end
		end)
	end
	return finish(b, props)
end

-- Re-skin an existing kit button (e.g. "Buy" -> "Equipped").
function UIKit.setVariant(b: TextButton, variant: ButtonVariant, text: string?)
	local bg, fg = variantColors(variant)
	b:SetAttribute("Variant", variant)
	b.BackgroundColor3 = bg
	b.TextColor3 = fg
	if text then
		b.Text = text
	end
end

-- Subtle hover lift for any card (grid items).
function UIKit.hoverLift(target: GuiObject, stroke: UIStroke?)
	local scale = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = target
	local info = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	target.MouseEnter:Connect(function()
		TweenService:Create(scale, info, { Scale = 1.03 }):Play()
		if stroke then
			TweenService:Create(stroke, info, { Color = T.Info, Transparency = 0 }):Play()
		end
	end)
	target.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, info, { Color = T.Stroke, Transparency = 0.3 }):Play()
		end
	end)
end

-- SurfaceGui for an in-world screen. Pixel density keeps text crisp; a kiosk
-- 8 studs wide at 50 px/stud gives a 400 px wide canvas.
function UIKit.surface(part: BasePart, props: Props?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 50
	g.LightInfluence = 0
	g.MaxDistance = 140
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.ResetOnSpawn = false
	g.ClipsDescendants = true
	assign(g, props)
	if not props or props.Parent == nil then
		g.Parent = part
	end
	return finish(g, props)
end

-- Full-size slate background for a SurfaceGui screen.
function UIKit.screen(gui: SurfaceGui): Frame
	local f = Instance.new("Frame")
	f.Name = "Screen"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = T.Base
	f.BorderSizePixel = 0
	UIKit.padding(f, 16)
	f.Parent = gui
	return f
end

function UIKit.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function UIKit.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return UIKit

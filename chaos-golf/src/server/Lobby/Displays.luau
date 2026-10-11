--!strict
-- Physical showcase props for shops, kiosks and podiums: spinning display
-- balls, chunky crates, floating info cards. Spinning is done on clients
-- (CollectionService tag "Spin", attribute SpinSpeed in rad/s).

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

-- A chunky stylised crate (rounded body, bands, glowing seam, dimple emblem).
function Displays.crate(parent: Instance, position: Vector3, color: Color3, size: number?): Model
	local s = size or 3.2
	local m = Instance.new("Model")
	m.Name = "Crate"
	local base = CFrame.new(position)
	local body = Parts.roundedBox(m, base, Vector3.new(s, s * 0.85, s), s * 0.12, { Color = color, Name = "Body", CanCollide = false })
	m.PrimaryPart = body
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.45)
	for _, y in { -0.3, 0.3 } do
		Parts.block(m, base * CFrame.new(0, y * s * 0.85, 0), Vector3.new(s + 0.08, s * 0.1, s + 0.08), { Color = dark, CanCollide = false, Name = "Band" })
	end
	Parts.block(m, base * CFrame.new(0, s * 0.18, 0), Vector3.new(s + 0.1, 0.12, s + 0.1), {
		Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Name = "Seam",
	})
	local emblem = Parts.ball(m, position + Vector3.new(0, 0, -s / 2 - 0.05), s * 0.32, { Color = Color3.new(1, 1, 1), CanCollide = false, Name = "Emblem" })
	emblem.Material = Enum.Material.SmoothPlastic
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = body
	m.Parent = parent
	return m
end

-- Gentle bob for a crate model.
function Displays.bob(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local start = root.CFrame
	task.spawn(function()
		local t = 0
		while model.Parent do
			t += task.wait(1 / 20)
			model:PivotTo(start * CFrame.new(0, math.sin(t * 1.6) * 0.25, 0) * CFrame.Angles(0, t * 0.5, 0))
		end
	end)
end

export type Card = { Gui: BillboardGui, Title: TextLabel, Sub: TextLabel, Price: TextLabel, Dot: Frame }

-- Floating info card (name / rarity / price) above a display.
function Displays.card(adornee: BasePart, offsetY: number, title: string, sub: string, price: string, dotColor: Color3): Card
	local gui = Instance.new("BillboardGui")
	gui.Name = "InfoCard"
	gui.Size = UDim2.fromOffset(190, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 45
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

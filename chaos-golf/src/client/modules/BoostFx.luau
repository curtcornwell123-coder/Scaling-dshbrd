--!strict
-- Boost feel. When a ball touches a boost floor the server stamps its "Boost" attribute:
--   * your own ball: a speed rush on screen - camera FOV kick, radial speed lines, a light
--     motion blur, a glow round the screen edges, a "BOOST!" pop and a whoosh;
--   * every ball: a burst of streaks in the world and a whoosh you hear nearby.
-- Boost pad chevrons (tag "BoostChevron", attribute Order 1-5) light up in sequence like
-- runway lights, only near the camera.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local BoostFx = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local rng = Random.new()
local CYAN = Color3.fromRGB(64, 224, 255)
local GOLD = Color3.fromRGB(255, 210, 63)

local gui: ScreenGui
local rushUntil = 0
local baseFov = 70

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	t:Play()
	return t
end

local function whoosh(parent: Instance, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = Config.Sounds.Boost
	s.Volume = volume
	s.PlaybackSpeed = rng:NextNumber(0.9, 1.1)
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

-- On-screen rush for your own ball.
local function rush()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	if now > rushUntil then
		baseFov = camera.FieldOfView
	end
	rushUntil = now + 1.1

	-- Camera: a quick widen, then ease back.
	tween(camera, 0.14, { FieldOfView = math.min(baseFov + 16, 100) })
	tween(camera, 0.85, { FieldOfView = baseFov }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0.28)

	-- Light motion blur.
	local blur = Lighting:FindFirstChild("BoostBlur") :: BlurEffect?
	if not blur then
		local b = Instance.new("BlurEffect")
		b.Name = "BoostBlur"
		b.Size = 0
		b.Parent = Lighting
		blur = b
	end
	local bl = blur :: BlurEffect
	tween(bl, 0.1, { Size = 6 })
	tween(bl, 0.5, { Size = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.2)

	local layer = Instance.new("Frame")
	layer.Name = "Rush"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.Parent = gui
	Debris:AddItem(layer, 1.4)

	-- Radial speed lines streaming out from the centre.
	local v = camera.ViewportSize
	local cx, cy = v.X / 2, v.Y / 2
	local reach = math.max(v.X, v.Y) * 0.62
	for _ = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local dir = Vector2.new(math.cos(a), math.sin(a))
		local r0 = reach * rng:NextNumber(0.28, 0.5)
		local len = rng:NextNumber(90, 240)
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.BorderSizePixel = 0
		line.BackgroundColor3 = if rng:NextNumber() < 0.25 then CYAN else Color3.new(1, 1, 1)
		line.BackgroundTransparency = 1
		line.Size = UDim2.fromOffset(len, rng:NextInteger(2, 4))
		line.Rotation = math.deg(a)
		line.Position = UDim2.fromOffset(cx + dir.X * r0, cy + dir.Y * r0)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0.1),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		g.Parent = line
		line.Parent = layer
		local r1 = r0 + reach * rng:NextNumber(0.35, 0.55)
		local delay = rng:NextNumber(0, 0.18)
		tween(line, 0.12, { BackgroundTransparency = 0.25 }, nil, nil, delay)
		tween(line, 0.45, { Position = UDim2.fromOffset(cx + dir.X * r1, cy + dir.Y * r1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay)
		tween(line, 0.3, { BackgroundTransparency = 1 }, nil, nil, delay + 0.3)
	end

	-- Edge glow: four gradient bands fading in from the screen edges.
	for _, e in { { 0, 0, 1, 0.16, 90 }, { 0, 0.84, 1, 0.16, -90 }, { 0, 0, 0.1, 1, 0 }, { 0.9, 0, 0.1, 1, 180 } } do
		local band = Instance.new("Frame")
		band.BorderSizePixel = 0
		band.BackgroundColor3 = CYAN
		band.BackgroundTransparency = 1
		band.Position = UDim2.fromScale(e[1], e[2])
		band.Size = UDim2.fromScale(e[3], e[4])
		local g = Instance.new("UIGradient")
		g.Rotation = e[5]
		g.Transparency = NumberSequence.new(0.35, 1)
		g.Parent = band
		band.Parent = layer
		tween(band, 0.12, { BackgroundTransparency = 0.2 })
		tween(band, 0.6, { BackgroundTransparency = 1 }, nil, nil, 0.25)
	end

	-- "BOOST!" pop.
	local label = UIKit.text({
		Text = "BOOST!",
		TextSize = 64,
		Font = T.FontHeavy,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(420, 80),
		Rotation = -4,
		Parent = layer,
	})
	UIKit.stroke(label, Color3.fromRGB(20, 24, 32), 3, 0)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = label
	tween(scale, 0.18, { Scale = 1.15 }, Enum.EasingStyle.Back)
	tween(scale, 0.2, { Scale = 1 }, nil, nil, 0.18)
	tween(label, 0.35, { TextTransparency = 1 }, nil, nil, 0.75)

	whoosh(gui, 0.8)
end

-- World burst on any boosting ball.
local function burst(ball: BasePart)
	local a = Instance.new("Attachment")
	a.Parent = ball
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(CYAN, Color3.new(1, 1, 1))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new(0.6, 0)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Lifetime = NumberRange.new(0.25, 0.45)
	e.Drag = 4
	e.Rate = 0
	e.Parent = a
	e:Emit(22)
	Debris:AddItem(a, 1)
	if ball:GetAttribute("Owner") ~= player.UserId then
		whoosh(ball, 0.45)
	end
end

local function watch(ball: Instance)
	if not ball:IsA("BasePart") then
		return
	end
	ball:GetAttributeChangedSignal("Boost"):Connect(function()
		if not ball.Parent then
			return
		end
		burst(ball)
		if ball:GetAttribute("Owner") == player.UserId then
			rush()
		end
	end)
end

-- Runway lights on boost pads -----------------------------------------------------------

local chevrons: { [BasePart]: number } = {}

local function trackChevron(inst: Instance)
	if inst:IsA("BasePart") then
		chevrons[inst] = (inst:GetAttribute("Order") :: number?) or 1
	end
end

function BoostFx.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "BoostFx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	task.spawn(function()
		local balls = workspace:WaitForChild("GolfBalls")
		for _, b in balls:GetChildren() do
			watch(b)
		end
		balls.ChildAdded:Connect(watch)
	end)

	for _, c in CollectionService:GetTagged("BoostChevron") do
		trackChevron(c)
	end
	CollectionService:GetInstanceAddedSignal("BoostChevron"):Connect(trackChevron)
	CollectionService:GetInstanceRemovedSignal("BoostChevron"):Connect(function(c)
		if c:IsA("BasePart") then
			chevrons[c] = nil
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		acc = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		local phase = os.clock() * 7
		for part, order in chevrons do
			if not part.Parent then
				chevrons[part] = nil
			elseif (part.Position - camPos).Magnitude < 200 then
				-- One bright chevron chases down the pad, the others glow softly.
				local k = (phase - order) % 5
				part.Transparency = if k < 1 then 0 else 0.15 + math.min(k, 3) * 0.18
			end
		end
	end)
end

return BoostFx

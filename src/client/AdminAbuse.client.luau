--!strict
-- The big admin abuse show. The moment admin abuse starts (the weekly one or
-- one an admin starts by hand), every player gets a full-screen intro: a
-- flash, spinning light rays, a giant rainbow "ADMIN ABUSE!" title, falling
-- confetti, a camera shake and fireworks over the map. While it's live the
-- lighting gently cycles party colors and fireworks keep going off. Purely
-- visual and client-side.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Announce = Remotes:WaitForChild("Announce") :: RemoteEvent

local player = Players.LocalPlayer
local RED = Color3.fromRGB(255, 60, 60)
local GOLD = Color3.fromRGB(255, 205, 60)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local gui = Instance.new("ScreenGui")
gui.Name = "AdminAbuseShow"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function rainbow(offset: number): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6 + offset) % 1, 0.8, 1)))
	end
	return ColorSequence.new(keys)
end

-- The admin who started it (sent with the "abuse" announcement).
local startedBy: string? = nil
Announce.OnClientEvent:Connect(function(kind: string, who: string)
	if kind == "abuse" then
		startedBy = who
	end
end)

-- Fireworks ----------------------------------------------------------------

local fireworksFolder = Instance.new("Folder")
fireworksFolder.Name = "AbuseFireworks"
fireworksFolder.Parent = workspace

-- One firework: a glowing rocket shoots up and bursts into colored sparks.
local function firework(center: Vector3)
	local hue = math.random()
	local color = Color3.fromHSV(hue, 0.85, 1)
	local from = center + Vector3.new(math.random(-70, 70), 0, math.random(-70, 70))
	local to = from + Vector3.new(math.random(-8, 8), math.random(55, 85), math.random(-8, 8))

	local rocket = Instance.new("Part")
	rocket.Name = "Rocket"
	rocket.Shape = Enum.PartType.Ball
	rocket.Size = Vector3.new(1.2, 1.2, 1.2)
	rocket.Material = Enum.Material.Neon
	rocket.Color = color
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CanTouch = false
	rocket.CastShadow = false
	rocket.Position = from
	rocket.Parent = fireworksFolder

	local trail = Instance.new("ParticleEmitter")
	trail.Texture = SPARKLE
	trail.Color = ColorSequence.new(color, GOLD)
	trail.LightEmission = 1
	trail.Rate = 80
	trail.Lifetime = NumberRange.new(0.3, 0.6)
	trail.Speed = NumberRange.new(1, 3)
	trail.SpreadAngle = Vector2.new(25, 25)
	trail.EmissionDirection = Enum.NormalId.Bottom
	trail.Size = NumberSequence.new(0.6, 0)
	trail.Parent = rocket

	local rise = tween(rocket, 0.9, { Position = to }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	rise.Completed:Connect(function()
		trail.Enabled = false
		rocket.Transparency = 1
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = SPARKLE
		burst.Color = ColorSequence.new(color, Color3.fromHSV((hue + 0.15) % 1, 0.6, 1))
		burst.LightEmission = 1
		burst.Rate = 0
		burst.Lifetime = NumberRange.new(1.4, 2.2)
		burst.Speed = NumberRange.new(28, 42)
		burst.Drag = 2.5
		burst.Acceleration = Vector3.new(0, -12, 0)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) })
		burst.Parent = rocket
		burst:Emit(90)
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 60
		flash.Brightness = 6
		flash.Parent = rocket
		tween(flash, 1, { Brightness = 0 })
		task.delay(3, function()
			rocket:Destroy()
		end)
	end)
end

local function fireworksAroundMe(count: number, spread: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if root then Vector3.new(root.Position.X, 0, root.Position.Z) else Vector3.zero
	for _ = 1, count do
		task.spawn(firework, center)
		task.wait(spread)
	end
end

-- Camera shake --------------------------------------------------------------

local function shake(seconds: number, strength: number)
	local camera = workspace.CurrentCamera
	local ends = os.clock() + seconds
	RunService:BindToRenderStep("AdminAbuseShake", Enum.RenderPriority.Camera.Value + 1, function()
		local left = ends - os.clock()
		if left <= 0 then
			RunService:UnbindFromRenderStep("AdminAbuseShake")
			return
		end
		local power = strength * (left / seconds)
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * power), math.rad((math.random() - 0.5) * power), math.rad((math.random() - 0.5) * power * 0.5))
	end)
end

-- Confetti ------------------------------------------------------------------

local function confetti(count: number, seconds: number)
	local layer = Instance.new("Frame")
	layer.Name = "Confetti"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 5
	layer.Parent = gui
	type Piece = { Frame: Frame, X: number, Y: number, VX: number, VY: number, Spin: number, Sway: number }
	local pieces: { Piece } = {}
	for _ = 1, count do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.fromHSV(math.random(), 0.8, 1)
		frame.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.ZIndex = 5
		frame.Parent = layer
		table.insert(pieces, {
			Frame = frame,
			X = math.random(),
			Y = -math.random() * 0.6 - 0.05,
			VX = (math.random() - 0.5) * 0.08,
			VY = 0.25 + math.random() * 0.3,
			Spin = (math.random() - 0.5) * 720,
			Sway = math.random() * 6,
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		for _, p in pieces do
			p.X += (p.VX + math.sin(t * 3 + p.Sway) * 0.05) * dt
			p.Y += p.VY * dt
			p.Frame.Position = UDim2.fromScale(p.X, p.Y)
			p.Frame.Rotation += p.Spin * dt
		end
		if t > seconds - 1 then
			for _, p in pieces do
				p.Frame.BackgroundTransparency = math.clamp(t - (seconds - 1), 0, 1)
			end
		end
		if t > seconds then
			connection:Disconnect()
			layer:Destroy()
		end
	end)
end

-- Party lighting while it's live ---------------------------------------------

local party: ColorCorrectionEffect? = nil

local function startParty()
	if party then
		return
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "AdminAbuseParty"
	effect.Saturation = 0.25
	effect.Parent = Lighting
	party = effect
	task.spawn(function()
		while party == effect do
			-- A soft wash of color that slowly cycles, not a strobe.
			effect.TintColor = Color3.fromHSV((os.clock() * 0.08) % 1, 0.12, 1)
			task.wait(0.05)
		end
	end)
end

local function stopParty()
	local effect = party
	party = nil
	if effect then
		tween(effect, 1.5, { TintColor = Color3.new(1, 1, 1), Saturation = 0 })
		task.delay(1.6, function()
			effect:Destroy()
		end)
	end
end

-- The big intro --------------------------------------------------------------

local function playIntro()
	-- 1. White flash, and the world flashes red.
	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 10
	flash.Parent = gui
	tween(flash, 0.7, { BackgroundTransparency = 1 })
	task.delay(0.8, function()
		flash:Destroy()
	end)
	local redTint = Instance.new("ColorCorrectionEffect")
	redTint.Name = "AdminAbuseFlash"
	redTint.TintColor = Color3.fromRGB(255, 120, 120)
	redTint.Contrast = 0.2
	redTint.Parent = Lighting
	tween(redTint, 2.5, { TintColor = Color3.new(1, 1, 1), Contrast = 0 })
	task.delay(2.6, function()
		redTint:Destroy()
	end)
	shake(1.4, 6)

	-- 2. Dark backdrop with spinning red and gold light rays.
	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = gui

	local rays = Instance.new("Frame")
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.45)
	rays.Size = UDim2.fromOffset(10, 10)
	rays.ZIndex = 2
	rays.Parent = gui
	for k = 0, 7 do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = if k % 2 == 0 then RED else GOLD
		ray.BackgroundTransparency = 0.35
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(70, 2600)
		ray.Rotation = k * 22.5
		ray.ZIndex = 2
		ray.Parent = rays
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(0.6, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	local raysScale = Instance.new("UIScale")
	raysScale.Scale = 0.1
	raysScale.Parent = rays
	tween(raysScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)

	-- 3. Giant rainbow title that slams in, then a subtitle.
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.42)
	title.Size = UDim2.fromScale(0.9, 0.24)
	title.Font = Enum.Font.FredokaOne
	title.Text = "ADMIN ABUSE!"
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 6
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = Color3.fromRGB(40, 0, 0)
	stroke.Parent = title
	local colors = Instance.new("UIGradient")
	colors.Color = rainbow(0)
	colors.Parent = title
	local titleScale = Instance.new("UIScale")
	titleScale.Scale = 5
	titleScale.Parent = title
	tween(titleScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.6)
	subtitle.Size = UDim2.fromScale(0.7, 0.07)
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.TextScaled = true
	subtitle.TextColor3 = GOLD
	subtitle.TextTransparency = 1
	subtitle.ZIndex = 6
	subtitle.Parent = gui
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Transparency = 1
	subStroke.Parent = subtitle
	task.delay(0.5, function()
		-- Set now so the admin's name (sent alongside) has arrived.
		subtitle.Text = if startedBy then startedBy .. " is abusing! Drops & cash rain incoming!" else "Drops & cash rain incoming! Grab everything!"
		tween(subtitle, 0.4, { TextTransparency = 0 })
		tween(subStroke, 0.4, { Transparency = 0 })
	end)

	-- 4. Confetti, fireworks and party lighting.
	confetti(140, 6)
	task.spawn(fireworksAroundMe, 12, 0.35)
	startParty()

	-- Animate: rays spin, the title pulses, wobbles and cycles colors.
	local started = os.clock()
	local animate = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		rays.Rotation = t * 40
		colors.Color = rainbow(t * 0.5)
		if t > 0.6 then
			titleScale.Scale = 1 + math.sin(t * 6) * 0.05
			title.Rotation = math.sin(t * 3) * 4
		end
	end)

	-- 5. After a few seconds everything flies away.
	task.wait(4.5)
	tween(titleScale, 0.4, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(raysScale, 0.5, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(subtitle, 0.3, { TextTransparency = 1 })
	tween(subStroke, 0.3, { Transparency = 1 })
	tween(backdrop, 0.6, { BackgroundTransparency = 1 })
	task.wait(0.7)
	animate:Disconnect()
	for _, item: GuiObject in { title, subtitle, rays, backdrop } :: { GuiObject } do
		item:Destroy()
	end
end

-- A smaller "it's over" card when it ends.
local function playOutro()
	stopParty()
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.fromScale(0.6, 0.1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "ADMIN ABUSE IS OVER"
	label.TextScaled = true
	label.TextColor3 = RED
	label.TextTransparency = 1
	label.ZIndex = 6
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Transparency = 1
	stroke.Parent = label
	tween(label, 0.4, { TextTransparency = 0 })
	tween(stroke, 0.4, { Transparency = 0 })
	task.wait(2.5)
	tween(label, 0.6, { TextTransparency = 1 })
	tween(stroke, 0.6, { Transparency = 1 })
	task.wait(0.7)
	label:Destroy()
end

-- Watch for it starting and ending ------------------------------------------

local function isLive(): boolean
	local now = workspace:GetServerTimeNow()
	local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
	return (manualEnd ~= nil and manualEnd > now) or Config.AdminAbuseStatus(now) == "live"
end

local wasLive = false
local nextFirework = 0
while true do
	local live = isLive()
	if live and not wasLive then
		task.spawn(playIntro)
		nextFirework = os.clock() + 8
	elseif wasLive and not live then
		startedBy = nil
		task.spawn(playOutro)
	elseif live and os.clock() >= nextFirework then
		-- Every few seconds while it's live, a couple more fireworks.
		task.spawn(fireworksAroundMe, 2, 0.4)
		nextFirework = os.clock() + math.random(4, 7)
	end
	wasLive = live
	task.wait(0.25)
end

--!strict
-- The "GAME UPDATING!" screen: shown to everyone when the server closes for
-- an update (Main.server's BindToClose), while their progress saves. A dark
-- starry backdrop, a bouncing rainbow title, a spinning gear and a bar that
-- fills until they're sent off with a "rejoin" message.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Announce = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Announce") :: RemoteEvent

local player = Players.LocalPlayer

local function show()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UpdateNotice"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(14, 10, 30)
	backdrop.BackgroundTransparency = 1
	backdrop.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(40, 20, 80), Color3.fromRGB(10, 10, 25))
	gradient.Rotation = 90
	gradient.Parent = backdrop
	TweenService:Create(backdrop, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()

	-- Twinkling stars
	local stars: { Frame } = {}
	for _ = 1, 40 do
		local star = Instance.new("Frame")
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(math.random(), math.random())
		local size = math.random(2, 5)
		star.Size = UDim2.fromOffset(size, size)
		star.BackgroundColor3 = Color3.new(1, 1, 1)
		star.BorderSizePixel = 0
		star.Parent = backdrop
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = star
		table.insert(stars, star)
	end

	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromScale(0.8, 0.6)
	center.BackgroundTransparency = 1
	center.Parent = backdrop
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = center

	local gear = Instance.new("TextLabel")
	gear.AnchorPoint = Vector2.new(0.5, 0)
	gear.Position = UDim2.fromScale(0.5, 0)
	gear.Size = UDim2.fromScale(0.25, 0.32)
	gear.BackgroundTransparency = 1
	gear.Font = Enum.Font.FredokaOne
	gear.TextScaled = true
	gear.Text = "⚙️"
	gear.Parent = center
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = gear

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.34)
	title.Size = UDim2.fromScale(1, 0.26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "GAME UPDATING!"
	title.Parent = center
	local rainbow = Instance.new("UIGradient")
	rainbow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 120)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 70)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 230, 130)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 180, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
	})
	rainbow.Parent = title
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 4
	titleStroke.Color = Color3.fromRGB(20, 10, 40)
	titleStroke.Parent = title

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.fromScale(0.5, 0.62)
	subtitle.Size = UDim2.fromScale(0.9, 0.11)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(230, 225, 255)
	subtitle.Text = "New brainrots and fixes are landing. Your progress is being saved!"
	subtitle.Parent = center

	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0)
	barBack.Position = UDim2.fromScale(0.5, 0.8)
	barBack.Size = UDim2.fromScale(0.6, 0.06)
	barBack.BackgroundColor3 = Color3.fromRGB(40, 35, 70)
	barBack.Parent = center
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBack
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 200, 70)
	fill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local fillGradient = rainbow:Clone()
	fillGradient.Parent = fill

	local footer = Instance.new("TextLabel")
	footer.AnchorPoint = Vector2.new(0.5, 0)
	footer.Position = UDim2.fromScale(0.5, 0.9)
	footer.Size = UDim2.fromScale(0.7, 0.07)
	footer.BackgroundTransparency = 1
	footer.Font = Enum.Font.FredokaOne
	footer.TextScaled = true
	footer.TextColor3 = Color3.fromRGB(170, 160, 210)
	footer.Text = "Rejoin in a moment to play the new version"
	footer.Parent = center

	TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(fill, TweenInfo.new(Config.UpdateNoticeSeconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()

	local start = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		gear.Rotation = t * 120
		title.Rotation = math.sin(t * 3) * 2
		rainbow.Offset = Vector2.new(math.sin(t * 1.5) * 0.4, 0)
		for i, star in stars do
			star.BackgroundTransparency = 0.3 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 + i))
		end
	end)
end

Announce.OnClientEvent:Connect(function(kind: string)
	if kind == "updating" then
		show()
	end
end)

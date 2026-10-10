-- Merge A Egg: loading screen (runs from ReplicatedFirst, before anything else).
-- Shows a loading sign with an "Assets loaded" counter and progress bar while the
-- game and map stream in, flashes "Success!", then slides up off the screen.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local c = Color3.fromRGB
local WHITE = c(255, 255, 255)

local function new(className: string, props, parent: Instance?)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function label(parent: Instance, props)
	local text = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = WHITE,
	}, parent)
	for key, value in props do
		text[key] = value
	end
	new("UIStroke", { Thickness = 3, Color = c(15, 15, 20) }, text)
	return text
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "MergeAEggLoading", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100 }, playerGui)
local screen = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, gui)
new("UIGradient", { Color = ColorSequence.new(c(120, 210, 90), c(40, 120, 60)), Rotation = 90 }, screen)

-- Design at 1280x720 and scale to the device.
local content = new("Frame", { Size = UDim2.fromOffset(900, 560), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }, screen)
local scale = new("UIScale", {}, content)
local function rescale()
	local size = gui.AbsoluteSize
	if size.X > 0 then
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.45, 1.3)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
rescale()

local logo = label(content, { Text = "🥚 MERGE A EGG 🥚", Size = UDim2.new(1, 0, 0, 110), Position = UDim2.fromOffset(0, 10) })
new("UIGradient", { Color = ColorSequence.new(c(255, 245, 160), c(255, 160, 40)), Rotation = 90 }, logo)

-- The wooden loading sign.
local sign = new("Frame", { Size = UDim2.fromOffset(560, 230), Position = UDim2.new(0.5, 0, 0, 160), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = WHITE }, content)
new("UICorner", { CornerRadius = UDim.new(0, 18) }, sign)
new("UIStroke", { Thickness = 6, Color = c(70, 45, 25) }, sign)
new("UIGradient", { Color = ColorSequence.new(c(205, 150, 90), c(150, 100, 55)), Rotation = 90 }, sign)
for _, x in { 0.18, 0.82 } do
	local post = new("Frame", { Size = UDim2.fromOffset(26, 170), Position = UDim2.new(x, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = c(120, 80, 45), ZIndex = 0 }, sign)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, post)
	new("UIStroke", { Thickness = 4, Color = c(70, 45, 25) }, post)
end
local signTitle = label(sign, { Text = "LOADING", Size = UDim2.new(1, -40, 0, 80), Position = UDim2.fromOffset(20, 18) })
local counter = label(sign, { Text = "Assets loaded: 0 / 0", TextColor3 = c(255, 240, 200), Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 100) })

local barBack = new("Frame", { Size = UDim2.new(1, -60, 0, 34), Position = UDim2.new(0, 30, 1, -58), BackgroundColor3 = c(60, 38, 22) }, sign)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)
new("UIStroke", { Thickness = 3, Color = c(40, 25, 15) }, barBack)
local bar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE }, barBack)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
new("UIGradient", { Color = ColorSequence.new(c(150, 255, 110), c(60, 190, 60)), Rotation = 90 }, bar)

local tip = label(content, { Text = "Tip: animals sleep at night — that's the best time to steal!", TextColor3 = c(230, 255, 220), Size = UDim2.new(1, -40, 0, 34), Position = UDim2.new(0, 20, 1, -40) })

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------

local TIPS = {
	"Tip: animals sleep at night — that's the best time to steal!",
	"Tip: 3 matching eggs in the Fuse Machine make a rarer egg!",
	"Tip: heavier eggs hatch bigger, better pets!",
	"Tip: bonk thieves with your bat to make them drop your egg!",
	"Tip: battle pets follow you and fight the Golem King!",
}

local running = true
task.spawn(function()
	local dots = 0
	local tipIndex = 1
	local tick = 0
	while running do
		dots = dots % 3 + 1
		signTitle.Text = "LOADING" .. string.rep(".", dots)
		tick += 1
		if tick % 8 == 0 then
			tipIndex = tipIndex % #TIPS + 1
			tip.Text = TIPS[tipIndex]
		end
		task.wait(0.4)
	end
end)

local function setProgress(done: number, total: number)
	counter.Text = `Assets loaded: {done} / {total}`
	local ratio = if total > 0 then done / total else 0
	TweenService:Create(bar, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) }):Play()
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Wait (briefly) for the server-built map so it's included in the count.
local started = os.clock()
while not workspace:FindFirstChild("Map") and os.clock() - started < 15 do
	task.wait(0.2)
end

local assets = {}
for _, root in { game:GetService("ReplicatedStorage"), workspace:FindFirstChild("Map"), game:GetService("SoundService") } do
	if root then
		for _, descendant in root:GetDescendants() do
			table.insert(assets, descendant)
		end
	end
end

local total = #assets
local BATCH = 200
local done = 0
setProgress(0, total)
for i = 1, total, BATCH do
	local batch = table.move(assets, i, math.min(i + BATCH - 1, total), 1, {})
	pcall(function()
		ContentProvider:PreloadAsync(batch)
	end)
	done = math.min(done + #batch, total)
	setProgress(done, total)
	task.wait()
end

-- Success, then slide the whole screen up and away.
running = false
setProgress(total, total)
signTitle.Text = "✅ SUCCESS!"
signTitle.TextColor3 = c(150, 255, 120)
counter.Text = `All {total} assets loaded!`
task.wait(0.9)

local slide = TweenService:Create(screen, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.fromScale(0, -1.1) })
slide:Play()
slide.Completed:Wait()
player:SetAttribute("Loaded", true)
gui:Destroy()

--!strict
-- Corny studio loading screen. Drop this LocalScript into ReplicatedFirst of ANY
-- game: it shows the studio logo, "Corny presents...", then that game's own
-- icon and name (read from Roblox automatically) with a live loading bar.
-- Nothing to edit per game: the logo copy is picked by who owns the game.

local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

-- Settings -------------------------------------------------------------------------------

-- Corny Games logo, uploaded once per owner (Roblox only lets an image load in games
-- owned by the same account/group). Unknown owners fall back to a text wordmark.
local LOGO_USER = "rbxassetid://85146512996278" -- your account's games
local LOGO_GROUP = "rbxassetid://71441156027815" -- group 187537803's games
local STUDIO_NAME = "Corny"
local PRESENTS = STUDIO_NAME .. " presents..."
local MIN_SECONDS = 5.5 -- never shorter than this, so the intro always plays
local MAX_SECONDS = 15 -- never longer than this, even if assets are still streaming
local SKIP_AFTER = 3.5

local BG_TOP = Color3.fromRGB(16, 19, 30)
local BG_BOTTOM = Color3.fromRGB(6, 7, 12)
local TEXT = Color3.fromRGB(240, 243, 248)
local MUTED = Color3.fromRGB(148, 158, 178)
local ACCENT = Color3.fromRGB(255, 196, 61)

------------------------------------------------------------------------------------------

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local started = os.clock()
local finished = false

local gui = Instance.new("ScreenGui")
gui.Name = "StudioLoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.new(1, 1, 1)
root.BorderSizePixel = 0
root.Parent = gui
local bg = Instance.new("UIGradient")
bg.Rotation = 90
bg.Color = ColorSequence.new(BG_TOP, BG_BOTTOM)
bg.Parent = root

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function label(parent: Instance, text: string, size: number, font: Enum.Font, color: Color3, y: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, 0.5, y)
	l.Size = UDim2.fromOffset(900, size + 12)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.Parent = parent
	return l
end

-- Soft glow disc behind the hero element.
local function glow(parent: Instance, diameter: number, color: Color3, y: number): Frame
	local g = Instance.new("Frame")
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.new(0.5, 0, 0.5, y)
	g.Size = UDim2.fromOffset(diameter, diameter)
	g.BackgroundColor3 = color
	g.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = g
	-- UIGradient is linear; stacking a rotated copy gives a rounder falloff.
	local g2 = g:Clone()
	g2:ClearAllChildren()
	c:Clone().Parent = g2
	local grad2 = grad:Clone()
	grad2.Rotation = 90
	grad2.Parent = g2
	g2.Position = UDim2.fromScale(0.5, 0.5)
	g2.Size = UDim2.fromScale(1, 1)
	g2.BackgroundTransparency = 0.4
	g2.Parent = g
	g.Parent = parent
	return g
end

-- Stage 1: studio ----------------------------------------------------------------------------

local studio = Instance.new("CanvasGroup")
studio.Name = "Studio"
studio.BackgroundTransparency = 1
studio.Size = UDim2.fromScale(1, 1)
studio.GroupTransparency = 1
studio.Parent = root
local studioScale = Instance.new("UIScale")
studioScale.Scale = 0.92
studioScale.Parent = studio

glow(studio, 440, ACCENT, -70)

-- Wordmark fallback (shown only if the logo image can't load).
local wordmark = Instance.new("Frame")
wordmark.BackgroundTransparency = 1
wordmark.Size = UDim2.fromScale(1, 1)
wordmark.Visible = false
wordmark.Parent = studio
label(wordmark, string.upper(STUDIO_NAME), 96, Enum.Font.GothamBlack, TEXT, -80)
label(wordmark, "G A M E S", 24, Enum.Font.GothamBold, ACCENT, -14)

local logo = Instance.new("ImageLabel")
logo.BackgroundTransparency = 1
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.new(0.5, 0, 0.5, -70)
logo.Size = UDim2.fromOffset(320, 320)
logo.ScaleType = Enum.ScaleType.Fit
logo.Image = if game.CreatorType == Enum.CreatorType.Group then LOGO_GROUP else LOGO_USER
logo.Parent = studio
task.spawn(function()
	ContentProvider:PreloadAsync({ logo }, function(_, fetchStatus)
		if fetchStatus ~= Enum.AssetFetchStatus.Success then
			logo.Visible = false
			wordmark.Visible = true
		end
	end)
end)

local presents = label(studio, "", 30, Enum.Font.GothamMedium, MUTED, 130)

-- Stage 2: this game ----------------------------------------------------------------------------

local gameGroup = Instance.new("CanvasGroup")
gameGroup.Name = "Game"
gameGroup.BackgroundTransparency = 1
gameGroup.Size = UDim2.fromScale(1, 1)
gameGroup.GroupTransparency = 1
gameGroup.Parent = root
local gameScale = Instance.new("UIScale")
gameScale.Scale = 0.94
gameScale.Parent = gameGroup

glow(gameGroup, 460, Color3.fromRGB(120, 90, 255), -70)
local icon = Instance.new("ImageLabel")
icon.BackgroundColor3 = Color3.fromRGB(32, 37, 48)
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.new(0.5, 0, 0.5, -70)
icon.Size = UDim2.fromOffset(220, 220)
icon.ScaleType = Enum.ScaleType.Crop
icon.Image = if game.GameId ~= 0 then string.format("rbxthumb://type=GameIcon&id=%d&w=512&h=512", game.GameId) else ""
icon.Visible = game.GameId ~= 0
local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0, 28)
iconCorner.Parent = icon
local iconStroke = Instance.new("UIStroke")
iconStroke.Color = Color3.new(1, 1, 1)
iconStroke.Transparency = 0.85
iconStroke.Thickness = 2
iconStroke.Parent = icon
icon.Parent = gameGroup

local title = label(gameGroup, "", 40, Enum.Font.GothamBlack, TEXT, 80)
local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.new(0.5, 0, 0.5, 132)
barBack.Size = UDim2.fromOffset(360, 6)
barBack.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
barBack.BorderSizePixel = 0
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBack
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = ACCENT
barFill.BorderSizePixel = 0
barCorner:Clone().Parent = barFill
barFill.Parent = barBack
barBack.Parent = gameGroup
local status = label(gameGroup, "Loading...", 16, Enum.Font.GothamMedium, MUTED, 158)

local skip = Instance.new("TextButton")
skip.AnchorPoint = Vector2.new(1, 1)
skip.Position = UDim2.new(1, -28, 1, -28)
skip.Size = UDim2.fromOffset(96, 36)
skip.BackgroundColor3 = Color3.fromRGB(32, 37, 48)
skip.BackgroundTransparency = 0.2
skip.AutoButtonColor = true
skip.Font = Enum.Font.GothamBold
skip.TextSize = 15
skip.TextColor3 = TEXT
skip.Text = "Skip"
skip.Visible = false
local skipCorner = Instance.new("UICorner")
skipCorner.CornerRadius = UDim.new(0, 8)
skipCorner.Parent = skip
skip.Parent = root

gui.Parent = player:WaitForChild("PlayerGui")

-- Game name (async; falls back to nothing in unpublished places) --------------------------------

task.spawn(function()
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(game.PlaceId)
	end)
	if ok and type(info) == "table" and type(info.Name) == "string" then
		title.Text = info.Name
	end
end)

-- Progress: assets still downloading vs. the most we've seen queued ------------------------------

local peakQueue = 1
local function progress(): number
	local queue = ContentProvider.RequestQueueSize
	peakQueue = math.max(peakQueue, queue)
	local assets = 1 - queue / peakQueue
	local loaded = if game:IsLoaded() then 1 else 0.5
	local timeShare = math.clamp((os.clock() - started) / MIN_SECONDS, 0, 1)
	return math.min(assets, loaded, 1) * 0.7 + timeShare * 0.3
end

local function ready(): boolean
	local elapsed = os.clock() - started
	if elapsed >= MAX_SECONDS then
		return true
	end
	return elapsed >= MIN_SECONDS and game:IsLoaded() and ContentProvider.RequestQueueSize == 0
end

local function finish()
	if finished then
		return
	end
	finished = true
	skip.Visible = false
	tween(barFill, 0.25, { Size = UDim2.fromScale(1, 1) })
	task.wait(0.25)
	local fade = tween(root, 0.6, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
	fade.Completed:Wait()
	gui:Destroy()
end

skip.Activated:Connect(finish)

-- Sequence --------------------------------------------------------------------------------------

tween(studio, 0.9, { GroupTransparency = 0 })
tween(studioScale, 1.2, { Scale = 1 })
task.wait(0.8)
for i = 1, #PRESENTS do
	if finished then
		break
	end
	presents.Text = string.sub(PRESENTS, 1, i)
	task.wait(0.045)
end
task.wait(1.1)

if not finished then
	tween(studio, 0.45, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
	tween(studioScale, 0.45, { Scale = 1.04 }, Enum.EasingStyle.Quad)
	task.wait(0.3)
	tween(gameGroup, 0.7, { GroupTransparency = 0 })
	tween(gameScale, 0.9, { Scale = 1 })
end

while not finished do
	local p = progress()
	tween(barFill, 0.2, { Size = UDim2.fromScale(math.clamp(p, 0.04, 1), 1) }, Enum.EasingStyle.Quad)
	local queue = ContentProvider.RequestQueueSize
	status.Text = if queue > 0 then string.format("Loading assets · %d left", queue) elseif game:IsLoaded() then "Ready!" else "Loading world..."
	if os.clock() - started > SKIP_AFTER then
		skip.Visible = true
	end
	if ready() then
		finish()
		break
	end
	task.wait(0.15)
end

--!strict
-- The Corny Games loading screen. Runs before anything else loads: shows the
-- Corny Games emblem and a loading bar that fills as the game and the map
-- actually load, then fades away.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- To show the real emblem image instead of the one drawn below, upload it to
-- Roblox (as a Decal/Image) and put its id here, e.g. "rbxassetid://1234567890".
local LOGO_IMAGE = ""

local MIN_SECONDS = 2.5 -- always show it at least this long so it doesn't flash
local NAVY = Color3.fromRGB(16, 22, 38)
local GOLD = Color3.fromRGB(250, 196, 60)
local CORN = Color3.fromRGB(255, 205, 40)
local KERNEL = Color3.fromRGB(255, 220, 70)
local LEAF = Color3.fromRGB(70, 185, 110)
local LEAF_DARK = Color3.fromRGB(40, 140, 85)

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "CornyGamesLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className: string, parent: Instance, props: { [string]: any }): any
	local object = Instance.new(className)
	for key, value in props do
		(object :: any)[key] = value
	end
	object.Parent = parent
	return object
end

local function round(parent: Instance, radius: UDim)
	make("UICorner", parent, { CornerRadius = radius })
end

local background = make("Frame", gui, {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = NAVY,
	BorderSizePixel = 0,
})
make("UIGradient", background, {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(24, 32, 54), Color3.fromRGB(10, 14, 26)),
})

-- Everything in the middle, kept to a nice size on any screen
local center = make("Frame", background, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.47),
	Size = UDim2.fromOffset(340, 470),
	BackgroundTransparency = 1,
})
make("UIScale", center, { Name = "Fit" })

-- The emblem: a gold ring with a corn cob and leaves inside
local emblem = make("Frame", center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(230, 230),
	BackgroundTransparency = 1,
})
local emblemScale = make("UIScale", emblem, { Scale = 0.6 })

if LOGO_IMAGE ~= "" then
	make("ImageLabel", emblem, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = LOGO_IMAGE,
		ScaleType = Enum.ScaleType.Fit,
	})
else
	local ring = make("Frame", emblem, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 28, 48),
		ZIndex = 0,
	})
	round(ring, UDim.new(1, 0))
	make("UIStroke", ring, { Color = GOLD, Thickness = 6 })

	-- Corn cob: a rounded yellow body covered in kernels
	local cob = make("Frame", emblem, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.13),
		Size = UDim2.fromOffset(78, 132),
		BackgroundColor3 = CORN,
	})
	round(cob, UDim.new(0.5, 0))
	local columns, rows = 4, 7
	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			local kernel = make("Frame", cob, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				-- Kept inside the cob's rounded ends
				Position = UDim2.new(0.2 + column * 0.2, 0, 0.11 + row * 0.12, 0),
				Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = KERNEL,
			})
			round(kernel, UDim.new(0.35, 0))
			make("UIStroke", kernel, { Color = Color3.fromRGB(220, 160, 20), Thickness = 1.5 })
		end
	end

	-- Leaves wrapping the bottom of the cob
	local function leaf(x: number, y: number, w: number, h: number, rotation: number, color: Color3, z: number)
		local l = make("Frame", emblem, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = rotation,
			BackgroundColor3 = color,
			ZIndex = z,
		})
		round(l, UDim.new(1, 0))
	end
	leaf(82, 168, 46, 96, -32, LEAF_DARK, 2)
	leaf(148, 168, 46, 96, 32, LEAF_DARK, 2)
	leaf(92, 172, 40, 84, -22, LEAF, 3)
	leaf(138, 172, 40, 84, 22, LEAF, 3)
	leaf(115, 182, 34, 58, 0, LEAF, 4)
end

-- CORNY / — GAMES —
local title = make("TextLabel", center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 240),
	Size = UDim2.fromOffset(340, 70),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "CORNY",
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
})
local gamesRow = make("Frame", center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 312),
	Size = UDim2.fromOffset(260, 30),
	BackgroundTransparency = 1,
})
local games = make("TextLabel", gamesRow, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(120, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "G A M E S",
	TextScaled = true,
	TextColor3 = GOLD,
	TextTransparency = 1,
})
local lines = {}
for _, side in { -1, 1 } do
	table.insert(lines, make("Frame", gamesRow, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, side * 98, 0.5, 0),
		Size = UDim2.fromOffset(60, 3),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
	}))
end

-- The loading bar
local track = make("Frame", center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 380),
	Size = UDim2.fromOffset(300, 18),
	BackgroundColor3 = Color3.fromRGB(35, 45, 72),
})
round(track, UDim.new(1, 0))
make("UIStroke", track, { Color = Color3.fromRGB(70, 85, 120), Thickness = 1.5 })
local fill = make("Frame", track, {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = GOLD,
})
round(fill, UDim.new(1, 0))
make("UIGradient", fill, { Color = ColorSequence.new(Color3.fromRGB(255, 225, 110), GOLD) })
local status = make("TextLabel", center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 406),
	Size = UDim2.fromOffset(300, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Loading... 0%",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(200, 205, 220),
})

-- If something breaks while loading (on the server or here), show it in red
-- under the bar, so it can be screenshotted and fixed.
local problem = make("TextLabel", center, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 436),
	Size = UDim2.fromOffset(420, 90),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextSize = 14,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Color3.fromRGB(255, 90, 90),
	Visible = false,
})
local function showProblem(message: string?)
	if message and message ~= "" and not problem.Visible then
		problem.Text = "⚠ " .. message
		problem.Visible = true
	end
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function checkServer()
	showProblem(ReplicatedStorage:GetAttribute("ServerError") :: string?)
end
ReplicatedStorage:GetAttributeChangedSignal("ServerError"):Connect(checkServer)
checkServer()
game:GetService("ScriptContext").Error:Connect(function(message: string, trace: string)
	local where = string.match(trace or "", "^[^\n]+") or ""
	showProblem("Client: " .. message .. "  [" .. where .. "]")
end)

-- Shrink everything on small (phone) screens
local function fit()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	center.Fit.Scale = math.min(1, viewport.Y / 560, viewport.X / 400)
end
fit()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- Intro: the emblem pops in, then the words fade in
TweenService:Create(emblemScale, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Scale = 1 }):Play()
task.delay(0.3, function()
	TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	TweenService:Create(games, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	for _, line in lines do
		TweenService:Create(line, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	end
end)

-- How much has loaded: the game itself, then the map the server builds,
-- then the images and sounds still downloading.
local started = os.clock()
local biggestQueue = 1
local lastCount, lastGrowth = 0, os.clock()
local function progress(): number
	local gameLoaded = if game:IsLoaded() then 1 else 0
	local mapLoaded = 0
	local map = workspace:FindFirstChild("BrainrotHeist")
	if map then
		local count = #map:GetDescendants()
		if count > lastCount then
			lastCount, lastGrowth = count, os.clock()
		end
		local total = map:GetAttribute("PartCount")
		mapLoaded = if type(total) == "number" and total > 0 then math.min(1, count / total) else 0.5
		-- With streaming on, far-away parts only arrive when you get near
		-- them; once the map has stopped arriving for a moment, it's ready.
		if gameLoaded == 1 and os.clock() - lastGrowth > 1.5 then
			mapLoaded = 1
		end
	end
	local queue = ContentProvider.RequestQueueSize
	biggestQueue = math.max(biggestQueue, queue)
	local assetsLoaded = 1 - queue / biggestQueue
	return gameLoaded * 0.3 + mapLoaded * 0.5 + assetsLoaded * 0.2
end

local shown = 0
local pulse = 0
while true do
	local dt = RunService.RenderStepped:Wait()
	pulse += dt
	-- The bar eases toward the real amount, and never goes backwards.
	local target = progress()
	shown = math.max(shown, shown + (target - shown) * math.min(1, dt * 4))
	-- Don't finish before the minimum time, so the screen doesn't flash.
	local elapsed = os.clock() - started
	shown = math.min(shown, elapsed / MIN_SECONDS)
	fill.Size = UDim2.fromScale(math.clamp(shown, 0.02, 1), 1)
	status.Text = string.format("Loading... %d%%", math.floor(shown * 100 + 0.5))
	emblemScale.Scale = 1 + math.sin(pulse * 2.5) * 0.02
	if target >= 0.999 and shown >= 0.995 then
		break
	end
	-- Never get stuck: after 30 seconds, let them in anyway.
	if elapsed > 30 then
		break
	end
end

fill.Size = UDim2.fromScale(1, 1)
status.Text = "Loading... 100%"
task.wait(0.3)

-- Fade everything out
local fadeTime = 0.6
for _, object in gui:GetDescendants() do
	local goal: { [string]: any } = {}
	if object:IsA("TextLabel") then
		goal.TextTransparency = 1
	end
	if object:IsA("ImageLabel") then
		goal.ImageTransparency = 1
	end
	if object:IsA("GuiObject") and object.BackgroundTransparency < 1 then
		goal.BackgroundTransparency = 1
	end
	if object:IsA("UIStroke") then
		goal.Transparency = 1
	end
	if next(goal) then
		TweenService:Create(object, TweenInfo.new(fadeTime), goal):Play()
	end
end
task.wait(fadeTime + 0.1)
gui:Destroy()

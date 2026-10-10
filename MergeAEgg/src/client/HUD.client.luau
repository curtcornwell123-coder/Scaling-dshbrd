-- Merge A Egg: client entry point.
-- Builds the HUD (matching the reference layout), receives state from the server,
-- and runs every client-side effect: egg timers, prompt filtering, pet wandering,
-- treadmill belts, step popups, bat swings, knockback, hatch/fuse effects and sounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Panels = require(script.Parent:WaitForChild("Panels"))
local UI = Panels.UI

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Request = remotes:WaitForChild("Request") :: RemoteEvent

local c = Color3.fromRGB
local WHITE = c(255, 255, 255)

local state: { [string]: any } = {}
local serverOffset = 0
local displayedMoney = 0
local rng = Random.new()

local function serverNow(): number
	return os.time() + serverOffset
end

local function request(action: string, ...)
	Request:FireServer(action, ...)
end

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------

local sounds = {}
for name, id in Config.Sounds do
	local sound = Instance.new("Sound")
	sound.Name = "MAE_" .. name
	sound.SoundId = id
	sound.Volume = if name == "Click" then 0.3 else 0.6
	sound.Parent = SoundService
	sounds[name] = sound
end

local function sound(name: string)
	local s = sounds[name]
	if s then
		SoundService:PlayLocalSound(s)
	end
end

---------------------------------------------------------------------------
-- HUD layout
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MergeAEggHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = false
local playerGui = player:WaitForChild("PlayerGui")
gui.Parent = playerGui

local scaled = {}
local function container(name: string, anchor: Vector2, position: UDim2, size: Vector2): Frame
	local frame = UI.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
	}, gui)
	table.insert(scaled, UI.new("UIScale", {}, frame))
	return frame
end

local notify: (string, string?) -> ()

-- Left: Shop, Index and reward buttons.
local left = container("Left", Vector2.new(0, 0.5), UDim2.new(0, 12, 0.48, 0), Vector2.new(200, 400))
UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, left)
local shopButton = UI.button(left, { text = "🛒 Shop", color = c(80, 210, 60), size = UDim2.fromOffset(190, 70), order = 1, onClick = function()
	Panels.toggle("Shop")
end })
UI.button(left, { text = "📘 Index", color = c(40, 170, 240), size = UDim2.fromOffset(190, 70), order = 2, onClick = function()
	Panels.toggle("Index")
end })
local smallRow = UI.new("Frame", { Size = UDim2.fromOffset(190, 56), BackgroundTransparency = 1, LayoutOrder = 3 }, left)
UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, smallRow)
local dailyButton = UI.button(smallRow, { text = "📅", color = c(255, 170, 40), size = UDim2.fromOffset(58, 56), order = 1, onClick = function()
	Panels.toggle("Daily")
end })
UI.button(smallRow, { text = "🎁", color = c(40, 200, 230), size = UDim2.fromOffset(58, 56), order = 2, onClick = function()
	Panels.toggle("Gift")
end })
local playtimeButton, playtimeLabel = UI.button(smallRow, { text = "⏰", color = c(200, 80, 230), size = UDim2.fromOffset(58, 56), order = 3, onClick = function()
	Panels.toggle("Playtime")
end })

local function badge(parent: GuiObject): Frame
	local b = UI.new("Frame", { Name = "Badge", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -14, 0, -12), BackgroundColor3 = c(230, 30, 40), Visible = false, ZIndex = 3 }, parent)
	UI.corner(b, 99)
	UI.stroke(b, 2, WHITE)
	UI.text(b, { Text = "!", ZIndex = 4 })
	return b
end
local shopBadge = badge(shopButton)
shopBadge.Visible = true
local dailyBadge = badge(dailyButton)
local playtimeBadge = badge(playtimeButton)

-- Right: Eggs and Pets buttons plus shop shortcuts.
local right = container("Right", Vector2.new(1, 0.5), UDim2.new(1, -12, 0.45, 0), Vector2.new(90, 470))
UI.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
local eggsButton = UI.button(right, { text = "🥚", color = c(230, 40, 40), size = UDim2.fromOffset(84, 84), order = 1, onClick = function()
	Panels.toggle("Growing")
end })
UI.button(right, { text = "🐾", color = c(255, 130, 40), size = UDim2.fromOffset(84, 84), order = 2, onClick = function()
	Panels.toggle("Active")
end })
for i, info in { { "%", "Featured", c(255, 80, 60) }, { "👟", "Speed", c(60, 170, 255) }, { "💵", "Money", c(70, 190, 60) } } do
	UI.button(right, { text = info[1], color = info[3], size = UDim2.fromOffset(64, 60), order = 2 + i, onClick = function()
		Panels.open("Shop", info[2])
	end })
end
local readyBadge = badge(eggsButton)

-- Bottom-left: speed and money.
local stats = container("Stats", Vector2.new(0, 1), UDim2.new(0, 12, 1, -12), Vector2.new(440, 150))
UI.button(stats, { text = "👟+", color = c(60, 170, 255), size = UDim2.fromOffset(70, 60), position = UDim2.fromOffset(0, 0), onClick = function()
	Panels.open("Shop", "Speed")
end })
local speedLabel = UI.text(stats, { Text = "0", Size = UDim2.fromOffset(340, 60), Position = UDim2.fromOffset(80, 0), TextXAlignment = Enum.TextXAlignment.Left, strokeThickness = 4 })
UI.text(stats, { Text = "💵", Size = UDim2.fromOffset(70, 62), Position = UDim2.fromOffset(0, 66) })
local moneyLabel = UI.text(stats, { Text = "$0", TextColor3 = c(110, 255, 80), Size = UDim2.fromOffset(340, 62), Position = UDim2.fromOffset(80, 66), TextXAlignment = Enum.TextXAlignment.Left, strokeThickness = 4 })
local incomeLabel = UI.text(stats, { Text = "", TextColor3 = c(180, 255, 160), Size = UDim2.fromOffset(300, 24), Position = UDim2.fromOffset(84, 126), TextXAlignment = Enum.TextXAlignment.Left })

-- Bottom-right: day/night timer.
local cycle = container("Cycle", Vector2.new(1, 1), UDim2.new(1, -12, 1, -12), Vector2.new(320, 64))
local cycleBack = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = c(20, 20, 26), BackgroundTransparency = 0.5 }, cycle)
UI.corner(cycleBack, 10)
local cycleLabel = UI.text(cycleBack, { Text = "", Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5), TextXAlignment = Enum.TextXAlignment.Right, strokeThickness = 3 })

-- Top-centre: hint / announcement banner and toasts.
local top = container("Top", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8), Vector2.new(900, 260))
top.ZIndex = 10 -- toasts draw above open windows
local banner = UI.text(top, { Text = "Upgrade your Pen!", Size = UDim2.new(1, 0, 0, 70), strokeThickness = 4 })
local bossBanner = UI.text(top, { Text = "⚔️ The Golem King is awake in the Cave!", TextColor3 = c(255, 150, 70), Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 72), Visible = false })
local toasts = UI.new("Frame", { Size = UDim2.new(0.8, 0, 0, 150), Position = UDim2.new(0.1, 0, 0, 104), BackgroundTransparency = 1 }, top)
UI.new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toasts)

-- Bottom-centre: what you're carrying.
local carryFrame = container("Carry", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -96), Vector2.new(620, 52))
carryFrame.ZIndex = 10
local carryBack = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = c(255, 170, 40), Visible = false }, carryFrame)
UI.corner(carryBack, 10)
UI.stroke(carryBack, 3)
local carryLabel = UI.text(carryBack, { Text = "", Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5) })

---------------------------------------------------------------------------
-- Toasts and announcements
---------------------------------------------------------------------------

local toastOrder = 0
notify = function(text: string, kind: string?)
	toastOrder += 1
	local color = if kind == "success" then c(120, 255, 100) elseif kind == "error" then c(255, 90, 90) else WHITE
	local label = UI.text(toasts, { Text = text, TextColor3 = color, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = toastOrder, TextTransparency = 1 })
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	if kind == "error" then
		sound("Click")
	else
		sound("Notify")
	end
	local visible = 0
	for _, child in toasts:GetChildren() do
		if child:IsA("TextLabel") then
			visible += 1
		end
	end
	if visible > 4 then
		for _, child in toasts:GetChildren() do
			if child:IsA("TextLabel") and child ~= label then
				child:Destroy()
				break
			end
		end
	end
	task.delay(3.5, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
			task.wait(0.45)
			label:Destroy()
		end
	end)
end

local announceUntil = 0
local function announce(text: string, color: Color3)
	announceUntil = os.clock() + 5
	banner.Text = text
	banner.TextColor3 = color
	local scale = banner:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, banner)
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	sound("Notify")
end

local function hintText(): string
	local penLevel = state.penLevel or 1
	local nextLevel = Config.PenLevels[penLevel + 1]
	if player:GetAttribute("Carrying") then
		return "Bring the egg back to your pen!"
	end
	for _, egg in state.nests or {} do
		if (egg.growEnd or 0) <= serverNow() then
			return "An egg is ready to hatch!"
		end
	end
	if nextLevel and (state.money or 0) >= nextLevel.cost then
		return "Upgrade your Pen!"
	end
	if next(state.pets or {}) == nil and next(state.nests or {}) == nil then
		return "Steal an egg from the Forest!"
	end
	return "Upgrade your Pen!"
end

---------------------------------------------------------------------------
-- Scaling for phones and tablets
---------------------------------------------------------------------------

Panels.init({
	gui = gui,
	state = state,
	request = request,
	sound = sound,
	notify = function(text, kind)
		notify(text, kind)
	end,
	serverNow = serverNow,
})

local function rescale()
	local size = gui.AbsoluteSize
	if size.X <= 0 then
		return
	end
	local scale = math.clamp(math.min(size.X / 1280, size.Y / 720), 0.45, 1.25)
	for _, s in scaled do
		s.Scale = scale
	end
	Panels.setScale(scale)
end

---------------------------------------------------------------------------
-- State updates
---------------------------------------------------------------------------

local function refreshHud()
	speedLabel.Text = Config.formatWithCommas(math.floor(state.speed or 0))
	incomeLabel.Text = if (state.income or 0) > 0 then `+${Config.format(state.income)}/s` else ""
	local daily = state.daily
	dailyBadge.Visible = daily ~= nil and daily.canClaim
	local playtime = state.playtime
	local claimable = false
	local nextLeft = nil
	if playtime then
		for i, gift in Config.PlaytimeGifts do
			if not playtime.claimed[tostring(i)] then
				local left = gift.minutes * 60 - playtime.seconds
				if left <= 0 then
					claimable = true
				elseif not nextLeft or left < nextLeft then
					nextLeft = left
				end
			end
		end
	end
	playtimeBadge.Visible = claimable
	playtimeLabel.Text = if claimable then "⏰" elseif nextLeft then Config.formatTime(nextLeft) else "⏰"
	local ready = false
	for _, egg in state.nests or {} do
		if (egg.growEnd or 0) <= serverNow() then
			ready = true
			break
		end
	end
	readyBadge.Visible = ready
end

local firstSync = true
remotes:WaitForChild("Sync").OnClientEvent:Connect(function(patch)
	local changed = {}
	for key, value in patch do
		state[key] = value
		changed[key] = true
	end
	if patch.serverTime then
		serverOffset = patch.serverTime - os.time()
	end
	refreshHud()
	Panels.refresh(changed)
	if firstSync and state.daily then
		firstSync = false
		if state.daily.canClaim then
			task.delay(2.5, function()
				-- Let the "Welcome back" earnings screen finish first.
				while Panels.isOpen("Welcome") do
					task.wait(0.5)
				end
				Panels.open("Daily")
			end)
		end
	end
end)

remotes:WaitForChild("Notify").OnClientEvent:Connect(notify)
remotes:WaitForChild("Announce").OnClientEvent:Connect(announce)

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------

local function confetti(amount: number?)
	local colors = { c(255, 80, 80), c(255, 210, 60), c(90, 220, 90), c(80, 170, 255), c(200, 100, 255) }
	for _ = 1, amount or 40 do
		local piece = UI.new("Frame", {
			Size = UDim2.fromOffset(rng:NextInteger(8, 16), rng:NextInteger(10, 20)),
			Position = UDim2.fromScale(rng:NextNumber(0.05, 0.95), -0.05),
			BackgroundColor3 = colors[rng:NextInteger(1, #colors)],
			Rotation = rng:NextNumber(0, 360),
			ZIndex = 50,
		}, gui)
		local duration = rng:NextNumber(1.4, 2.4)
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(piece.Position.X.Scale + rng:NextNumber(-0.1, 0.1), 1.05),
			Rotation = piece.Rotation + rng:NextNumber(-360, 360),
		}):Play()
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

local function flash(color: Color3)
	local frame = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0.6, ZIndex = 45 }, gui)
	TweenService:Create(frame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	task.delay(0.6, function()
		frame:Destroy()
	end)
end

local function shake(intensity: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local started = os.clock()
	while os.clock() - started < duration do
		local fade = 1 - (os.clock() - started) / duration
		humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * intensity * fade
		task.wait()
	end
	humanoid.CameraOffset = Vector3.zero
end

local function burst(position: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.one * rng:NextNumber(0.3, 0.6)
		p.CFrame = CFrame.new(position)
		p.Parent = workspace
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.2, 1), rng:NextNumber(-1, 1)).Unit
		TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = CFrame.new(position + dir * rng:NextNumber(2, 4)), Transparency = 1, Size = Vector3.one * 0.1 }):Play()
		task.delay(0.5, function()
			p:Destroy()
		end)
	end
end

local function floatText(adornee: BasePart, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromScale(4, 1.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(rng:NextNumber(-1.5, 1.5), 2.5, rng:NextNumber(-1, 1))
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = playerGui
	local label = UI.text(billboard, { Text = text, TextColor3 = color })
	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
	task.delay(0.85, function()
		billboard:Destroy()
	end)
end

-- Bat swing: rotate the tool's grip (works for any player's bat).
local swinging: { [Tool]: boolean } = {}
local function swingAnimation(tool: Tool)
	if swinging[tool] then
		return
	end
	swinging[tool] = true
	local base = tool:GetAttribute("BaseGrip") or tool.Grip
	local handle = tool:FindFirstChild("Handle")
	local swoosh = handle and handle:FindFirstChild("Swoosh") :: Trail?
	if swoosh then
		swoosh.Enabled = true
	end
	local frames = {
		{ CFrame.Angles(math.rad(-70), 0, math.rad(20)), 0.07 },
		{ CFrame.Angles(math.rad(80), 0, math.rad(-25)), 0.09 },
		{ CFrame.Angles(math.rad(40), 0, 0), 0.08 },
		{ CFrame.new(), 0.12 },
	}
	for _, frame in frames do
		local value = Instance.new("CFrameValue")
		value.Value = tool.Grip
		value.Changed:Connect(function(cf)
			tool.Grip = cf
		end)
		local tween = TweenService:Create(value, TweenInfo.new(frame[2], Enum.EasingStyle.Quad), { Value = base * frame[1] })
		tween:Play()
		tween.Completed:Wait()
		value:Destroy()
	end
	tool.Grip = base
	if swoosh then
		swoosh.Enabled = false
	end
	swinging[tool] = nil
end

local lastSwing = 0
local function hookTool(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Bat" or tool:GetAttribute("Hooked") then
		return
	end
	tool:SetAttribute("Hooked", true)
	tool.Activated:Connect(function()
		if os.clock() - lastSwing < Config.BatCooldown then
			return
		end
		lastSwing = os.clock()
		sound("Swing")
		task.spawn(swingAnimation, tool)
		request("Swing")
	end)
end

local function onCharacter(character: Model)
	character.ChildAdded:Connect(hookTool)
	for _, child in character:GetChildren() do
		hookTool(child)
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

-- The six pen models, cached once they have all replicated.
local penModels: { Model } = {}
local function getPens(): { Model }
	if #penModels < 6 then
		table.clear(penModels)
		local map = workspace:FindFirstChild("Map")
		for i = 1, 6 do
			local slot = map and map:FindFirstChild("PenSlot" .. i)
			local pen = slot and slot:FindFirstChild("Pen" .. i)
			if pen and pen:IsA("Model") then
				table.insert(penModels, pen)
			end
		end
	end
	return penModels
end

local function myPen(): Model?
	for _, pen in getPens() do
		if pen:GetAttribute("OwnerUserId") == player.UserId then
			return pen
		end
	end
	return nil
end

local fxHandlers = {}

fxHandlers.Swing = function(who: Player)
	if who == player then
		return
	end
	local tool = who.Character and who.Character:FindFirstChild("Bat")
	if tool and tool:IsA("Tool") then
		task.spawn(swingAnimation, tool)
	end
end

fxHandlers.Knockback = function(velocity: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = velocity
		sound("Hit")
		task.spawn(shake, 0.6, 0.25)
	end
end

fxHandlers.BatHit = function(position: Vector3)
	burst(position + Vector3.new(0, 2, 0), c(255, 240, 120), 8)
end

fxHandlers.HitConfirm = function()
	sound("Hit")
end

fxHandlers.BossHit = function(position: Vector3)
	burst(position + Vector3.new(0, 3, 0), c(255, 140, 50), 10)
end

fxHandlers.BossSlam = function(position: Vector3, radius: number)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and (root.Position - position).Magnitude < radius * 3 then
		task.spawn(shake, 1.2, 0.5)
	end
	burst(position + Vector3.new(0, 1, 0), c(160, 140, 120), 18)
end

fxHandlers.GuardianRoar = function(position: Vector3)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and (root.Position - position).Magnitude < 40 then
		task.spawn(shake, 0.8, 0.35)
	end
end

fxHandlers.BossDefeated = function()
	confetti(70)
end

fxHandlers.Hatch = function(p, isNew: boolean, egg)
	task.spawn(Panels.hatchReveal, p, isNew, egg)
	if p.rarity >= 5 then
		task.delay(1, confetti, 60)
	end
end

fxHandlers.Celebrate = function()
	confetti(45)
end

fxHandlers.Secured = function(rarity: number)
	confetti(if rarity >= 4 then 50 else 20)
end

fxHandlers.Alarm = function()
	flash(c(255, 40, 40))
end

fxHandlers.Cash = function(amount: number)
	notify(`+${Config.format(amount)}`, "success")
end

fxHandlers.OpenPanel = function(name: string)
	Panels.open(name)
end

fxHandlers.Popup = function(text: string)
	Panels.popup(text)
end

fxHandlers.WelcomeBack = function(amount: number, seconds: number)
	task.delay(1, function()
		Panels.open("Welcome", { amount = amount, seconds = seconds })
	end)
end

fxHandlers.FuseInsert = function(count: number)
	sound("Notify")
	notify(`Fuse Machine {count}/3`, "info")
end

fxHandlers.FuseResult = function(egg)
	confetti(40)
	notify(`⚗️ Fused into a {Panels.eggName(egg)}!`, "success")
end

fxHandlers.Fuse = function(penIndex: number)
	local map = workspace:FindFirstChild("Map")
	local slot = map and map:FindFirstChild("PenSlot" .. penIndex)
	local pen = slot and slot:FindFirstChild("Pen" .. penIndex)
	local machine = pen and pen:FindFirstChild("FuseMachine")
	local core = machine and machine:FindFirstChild("Core") :: BasePart?
	if not core then
		return
	end
	local original = core.Color
	for i = 1, 10 do
		core.Color = if i % 2 == 0 then WHITE else c(255, 120, 230)
		burst(core.Position, core.Color, 3)
		task.wait(0.25)
	end
	core.Color = original
	burst(core.Position, WHITE, 20)
end

remotes:WaitForChild("Fx").OnClientEvent:Connect(function(name: string, ...)
	local handler = fxHandlers[name]
	if handler then
		task.spawn(handler, ...)
	end
end)

---------------------------------------------------------------------------
-- World: prompts, egg timers, home marker, rebirth chains
---------------------------------------------------------------------------

local homeMarker = Instance.new("BillboardGui")
homeMarker.Name = "HomeMarker"
homeMarker.Size = UDim2.fromOffset(70, 70)
homeMarker.StudsOffsetWorldSpace = Vector3.new(0, 24, 0)
homeMarker.AlwaysOnTop = true
homeMarker.LightInfluence = 0
homeMarker.Parent = playerGui
UI.text(homeMarker, { Text = "🏠" })

local function setPrompt(promptParent: Instance?, name: string, enabled: boolean)
	local prompt = promptParent and promptParent:FindFirstChild(name)
	if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

-- Owner sees Hatch/Pick Up/Fuse/Upgrade prompts; everyone else only sees Steal.
local function updatePen(pen: Model, now: number, carrying: boolean)
	local isMine = pen:GetAttribute("OwnerUserId") == player.UserId
	local occupied = (pen:GetAttribute("OwnerUserId") or 0) ~= 0
	if isMine then
		homeMarker.Adornee = pen:FindFirstChild("PenFloor") :: BasePart?
	end
	local eggs = pen:FindFirstChild("Eggs")
	if eggs then
		for _, egg in eggs:GetChildren() do
			local root = egg:IsA("Model") and egg.PrimaryPart
			if root then
				local growEnd = egg:GetAttribute("GrowEnd") or 0
				local ready = growEnd <= now
				setPrompt(root, "Hatch", isMine and ready)
				setPrompt(root, "PickUp", isMine and not carrying)
				setPrompt(root, "Steal", not isMine and occupied and not carrying)
				local tag = root:FindFirstChild("EggTag")
				local info = tag and tag:FindFirstChild("Info") :: TextLabel?
				if info then
					info.Text = if ready then "✅ READY!" else `⏳ {Config.formatTime(growEnd - now)}`
					info.TextColor3 = if ready then c(120, 255, 100) else WHITE
				end
			end
		end
	end
	local fuse = pen:FindFirstChild("FuseMachine")
	if fuse then
		setPrompt(fuse:FindFirstChild("Pod2"), "ProximityPrompt", isMine and carrying)
		setPrompt(fuse.PrimaryPart, "ProximityPrompt", isMine and #(state.fuse or {}) > 0)
	end
	setPrompt(pen:FindFirstChild("SignPost"), "ProximityPrompt", isMine and Config.PenLevels[(state.penLevel or 1) + 1] ~= nil)
end

local function worldTick()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	local now = serverNow()
	local carrying = player:GetAttribute("Carrying") ~= nil
	for _, pen in getPens() do
		updatePen(pen, now, carrying)
	end

	-- Rebirth machine chains fall away when you can afford it.
	local lobby = map:FindFirstChild("Lobby")
	local machine = lobby and lobby:FindFirstChild("RebirthMachine")
	if machine then
		local affordable = (state.money or 0) >= Config.rebirthCost(state.rebirths or 0)
		for _, part in machine:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Chain") then
				part.LocalTransparencyModifier = if affordable then 1 else 0
			end
		end
	end
end

---------------------------------------------------------------------------
-- World: pets wander, belts scroll, step popups
---------------------------------------------------------------------------

local petStates = {}
local belts = {}

local function setupBelt(belt: BasePart)
	if belts[belt] then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.PixelsPerStud = 20
	surface.LightInfluence = 1
	surface.Adornee = belt
	surface.Parent = playerGui
	local holder = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true }, surface)
	local stripes = {}
	for i = 0, 7 do
		local stripe = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromScale(0, i / 8), BackgroundColor3 = c(90, 90, 100), BackgroundTransparency = 0.4, BorderSizePixel = 0 }, holder)
		table.insert(stripes, stripe)
	end
	belts[belt] = { gui = surface, stripes = stripes, offset = 0 }
end

local function scanWorld()
	for belt, info in belts do
		if not belt.Parent then
			info.gui:Destroy()
			belts[belt] = nil
		end
	end
	for _, pen in getPens() do
		for _, child in pen:GetChildren() do
			if child.Name:match("^Treadmill") then
				local belt = child:FindFirstChild("Belt")
				if belt and belt:IsA("BasePart") then
					setupBelt(belt)
				end
			end
		end
	end
end

local function onOwnBelt(): boolean
	local pen = myPen()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not pen or not root or not humanoid or humanoid.MoveDirection.Magnitude < 0.1 then
		return false
	end
	for _, child in pen:GetChildren() do
		local belt = child.Name:match("^Treadmill") and child:FindFirstChild("Belt")
		if belt and belt:IsA("BasePart") then
			local rel = belt.CFrame:PointToObjectSpace(root.Position)
			if math.abs(rel.X) <= belt.Size.X / 2 + 0.5 and math.abs(rel.Z) <= belt.Size.Z / 2 and rel.Y > 0 and rel.Y < 7 then
				return true
			end
		end
	end
	return false
end

local PET_ANIMATE_DISTANCE = 200

local function animatePet(pet: Model, areaCf: CFrame, areaSize: Vector3, dt: number)
	local ps = petStates[pet]
	if not ps then
		ps = { pos = pet:GetPivot().Position, target = nil, wait = rng:NextNumber(0, 2), bob = rng:NextNumber(0, 6), yaw = 0 }
		petStates[pet] = ps
		pet.Destroying:Connect(function()
			petStates[pet] = nil
		end)
	end
	if ps.wait > 0 then
		ps.wait -= dt
	else
		if not ps.target then
			local half = areaSize / 2
			ps.target = (areaCf * CFrame.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))).Position
		end
		local delta = Vector3.new(ps.target.X - ps.pos.X, 0, ps.target.Z - ps.pos.Z)
		if delta.Magnitude < 0.5 then
			ps.target = nil
			ps.wait = rng:NextNumber(1, 3.5)
		else
			ps.pos += delta.Unit * math.min(delta.Magnitude, 5 * dt)
			ps.yaw = math.atan2(-delta.X, -delta.Z)
			ps.bob += dt * 10
		end
	end
	local hop = if ps.wait > 0 then 0 else math.abs(math.sin(ps.bob)) * 0.5
	local base = Vector3.new(ps.pos.X, areaCf.Position.Y, ps.pos.Z)
	local height = (pet.PrimaryPart :: BasePart).Size.Y / 2
	pet:PivotTo(CFrame.new(base + Vector3.new(0, height + hop, 0)) * CFrame.Angles(0, ps.yaw, 0))
end

local stepTimer = 0
RunService.RenderStepped:Connect(function(dt)
	-- Money counts up smoothly.
	local target = state.money or 0
	displayedMoney += (target - displayedMoney) * math.min(1, dt * 8)
	if math.abs(target - displayedMoney) < 1 then
		displayedMoney = target
	end
	moneyLabel.Text = "$" .. Config.formatWithCommas(math.floor(displayedMoney))

	-- Belts scroll.
	for _, info in belts do
		info.offset = (info.offset + dt * 0.6) % (1 / 8)
		for i, stripe in info.stripes do
			stripe.Position = UDim2.fromScale(0, (i - 1) / 8 + info.offset)
		end
	end

	-- Predicted treadmill steps (server is the authority; sync corrects it).
	stepTimer += dt
	if stepTimer >= Config.TreadmillStepInterval then
		stepTimer = 0
		if onOwnBelt() and state.perStep then
			state.speed = (state.speed or 0) + state.perStep
			speedLabel.Text = Config.formatWithCommas(math.floor(state.speed))
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				floatText(root, `+{Config.format(state.perStep)}`, c(120, 220, 255))
			end
		end
	end

	-- Pets wander inside their pen area (only near the camera).
	local cameraPos = workspace.CurrentCamera.CFrame.Position
	for _, pen in getPens() do
		local folder = pen:FindFirstChild("Pets")
		local areaCf = folder and folder:GetAttribute("AreaCF")
		local areaSize = folder and folder:GetAttribute("AreaSize")
		if areaCf and areaSize and (areaCf.Position - cameraPos).Magnitude < PET_ANIMATE_DISTANCE then
			for _, pet in folder:GetChildren() do
				if pet:IsA("Model") and pet.PrimaryPart then
					animatePet(pet, areaCf, areaSize, dt)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Slow loop: timers, banners, carry text
---------------------------------------------------------------------------

task.spawn(function()
	while true do
		worldTick()
		scanWorld()
		Panels.tick()
		refreshHud()

		local isNight = workspace:GetAttribute("IsNight")
		local ends = workspace:GetAttribute("CycleEnds")
		if ends then
			local left = ends - workspace:GetServerTimeNow()
			cycleLabel.Text = `{if isNight then "☀️" else "🌙"} in {Config.formatTime(left)}`
		end

		if os.clock() > announceUntil then
			banner.Text = hintText()
			banner.TextColor3 = WHITE
		end
		bossBanner.Visible = workspace:GetAttribute("BossActive") == true

		local carrying = player:GetAttribute("Carrying")
		carryBack.Visible = carrying ~= nil
		if carrying then
			carryLabel.Text = `🥚 {carrying} — get it home!`
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------------
-- Chat tags
---------------------------------------------------------------------------

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender then
		if sender.UserId == Config.OwnerUserId then
			properties.PrefixText = `<font color="#FFD232">[👑 OWNER]</font> {message.PrefixText}`
		elseif sender:GetAttribute("VIP") then
			properties.PrefixText = `<font color="#FFD232">[⭐ VIP]</font> {message.PrefixText}`
		end
	end
	return properties
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
rescale()

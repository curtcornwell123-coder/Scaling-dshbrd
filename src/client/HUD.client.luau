--!strict
-- Brainrot Heist client: cash HUD, shop, rebirth menu, announcements and
-- which prompts (Buy / Sell / Steal) each player sees.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetData = Remotes:WaitForChild("GetData") :: RemoteFunction
local DataUpdated = Remotes:WaitForChild("DataUpdated") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent
local Announce = Remotes:WaitForChild("Announce") :: RemoteEvent
local RequestRebirth = Remotes:WaitForChild("RequestRebirth") :: RemoteEvent
local AdminAction = Remotes:WaitForChild("AdminAction") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(25, 25, 35)
local GREEN = Color3.fromRGB(70, 210, 90)
local GOLD = Color3.fromRGB(255, 200, 50)
local RED = Color3.fromRGB(235, 60, 70)

local data: any = nil

-- UI helpers ---------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.new(0, 0, 0)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = WHITE
	l.TextScaled = true
	l.TextStrokeTransparency = 0.3
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, label: string, color: Color3, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.Font = FONT
	b.Text = label
	b.TextColor3 = WHITE
	b.TextScaled = true
	b.TextStrokeTransparency = 0.3
	b.AutoButtonColor = true
	corner(b, 10)
	stroke(b, 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = b
	b.Parent = parent
	return b
end

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotHeistUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Shrink everything on small (phone) screens.
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function rescale()
	local size = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(size.X / 1100, size.Y / 700), 0.55, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

-- Cash panel ---------------------------------------------------------------

local cashPanel = Instance.new("Frame")
cashPanel.AnchorPoint = Vector2.new(0.5, 0)
cashPanel.Position = UDim2.new(0.5, 0, 0, 8)
cashPanel.Size = UDim2.fromOffset(320, 92)
cashPanel.BackgroundColor3 = DARK
cashPanel.BackgroundTransparency = 0.2
corner(cashPanel, 14)
stroke(cashPanel, 2, GREEN)
cashPanel.Parent = gui

local cashLabel = text(cashPanel, {
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 0, 46),
	TextColor3 = Color3.fromRGB(120, 255, 120),
	Text = "$0",
})
local incomeLabel = text(cashPanel, {
	Position = UDim2.fromOffset(10, 50),
	Size = UDim2.new(1, -20, 0, 20),
	Text = "+$0/s",
})
local slotsLabel = text(cashPanel, {
	Position = UDim2.fromOffset(10, 70),
	Size = UDim2.new(1, -20, 0, 18),
	TextColor3 = Color3.fromRGB(200, 200, 210),
	Text = "Base 0/10",
})

local luckLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 106),
	Size = UDim2.fromOffset(320, 28),
	TextColor3 = Color3.fromRGB(120, 255, 160),
	Text = "",
	Visible = false,
})

-- Weekly admin abuse: countdown in the last hour, then a LIVE banner.
local abuseLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 136),
	Size = UDim2.fromOffset(420, 32),
	TextColor3 = GOLD,
	TextStrokeTransparency = 0,
	Text = "",
	Visible = false,
})

local carryLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(520, 44),
	TextColor3 = GOLD,
	Text = "",
	Visible = false,
})

-- Side buttons -------------------------------------------------------------

local side = Instance.new("Frame")
side.BackgroundTransparency = 1
side.AnchorPoint = Vector2.new(0, 0.5)
side.Position = UDim2.new(0, 10, 0.5, 0)
side.Size = UDim2.fromOffset(130, 200)
side.Parent = gui
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 10)
sideLayout.Parent = side

local shopButton = button(side, "SHOP", Color3.fromRGB(255, 150, 40), UDim2.fromOffset(130, 56))
local rebirthButton = button(side, "REBIRTH", Color3.fromRGB(170, 80, 255), UDim2.fromOffset(130, 56))

-- Toasts -------------------------------------------------------------------

local toasts = Instance.new("Frame")
toasts.BackgroundTransparency = 1
toasts.AnchorPoint = Vector2.new(0.5, 1)
toasts.Position = UDim2.new(0.5, 0, 1, -200)
toasts.Size = UDim2.fromOffset(520, 200)
toasts.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toasts

local function toast(message: string, color: Color3?)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(500, 36)
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.15
	corner(frame, 10)
	stroke(frame, 2, color or WHITE)
	text(frame, {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		TextColor3 = color or WHITE,
		Text = message,
	})
	frame.Parent = toasts
	task.delay(3.5, function()
		frame:Destroy()
	end)
	local children = toasts:GetChildren()
	if #children > 6 then
		for _, child in children do
			if child:IsA("Frame") then
				child:Destroy()
				break
			end
		end
	end
end

-- Announcement banner ------------------------------------------------------

local banner = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 174),
	Size = UDim2.fromOffset(760, 48),
	Text = "",
	Visible = false,
	TextStrokeTransparency = 0,
})
local bannerToken = 0

local function showBanner(message: string, color: Color3)
	bannerToken += 1
	local token = bannerToken
	banner.Text = message
	banner.TextColor3 = color
	banner.Visible = true
	banner.Size = UDim2.fromOffset(600, 38)
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(760, 48) }):Play()
	task.delay(5, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

local function rarityColor(brainrot: Config.Brainrot): Color3
	if brainrot.Rarity == "Secret" then
		return Color3.fromRGB(255, 120, 255)
	end
	return Config.Rarities[brainrot.Rarity].Color
end

Announce.OnClientEvent:Connect(function(kind: string, who: string, brainrotId: string, extra: string?, mutationId: string?)
	local brainrot = Config.GetBrainrot(brainrotId)
	local mutation = Config.GetMutation(mutationId)
	local label = if brainrot then string.upper(Config.Rarities[brainrot.Rarity].DisplayName) .. " " .. brainrot.DisplayName else ""
	if mutation then
		label = string.upper(mutation.DisplayName) .. " " .. label
	end
	local color = if mutation then mutation.Color elseif brainrot then rarityColor(brainrot) else WHITE
	if kind == "spawn" and brainrot then
		showBanner("A " .. label .. " is on the conveyor!", color)
	elseif kind == "buy" and brainrot then
		showBanner(who .. " bought a " .. label .. "!", color)
	elseif kind == "steal" and brainrot then
		showBanner(who .. " STOLE a " .. label .. " from " .. (extra or "someone") .. "!", RED)
	elseif kind == "drop" and brainrot then
		showBanner(who .. " is dropping a " .. label .. " from the sky! GRAB IT!", color)
	elseif kind == "grab" and brainrot then
		showBanner(who .. " grabbed the " .. label .. "!", color)
	elseif kind == "rain" then
		showBanner("BRAINROT RAIN! Grab them before anyone else!", Color3.fromRGB(200, 140, 255))
	elseif kind == "cashrain" then
		showBanner("CASH RAIN! " .. (extra or "") .. " drops are falling!", Color3.fromRGB(120, 255, 120))
	elseif kind == "abuse" then
		showBanner("ADMIN ABUSE HAS STARTED!", RED)
	elseif kind == "luck" then
		showBanner(who .. " bought SERVER LUCK for everyone!", Color3.fromRGB(120, 255, 160))
	elseif kind == "rebirth" then
		showBanner(who .. " reached Rebirth " .. (extra or "") .. "!", Color3.fromRGB(200, 140, 255))
	end
end)

Notify.OnClientEvent:Connect(function(message: string)
	toast(message)
end)

-- Modal windows ------------------------------------------------------------

local function modal(title: string, color: Color3, height: number): (Frame, Frame)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(560, height)
	frame.BackgroundColor3 = DARK
	frame.Visible = false
	corner(frame, 16)
	stroke(frame, 3, color)
	frame.Parent = gui

	text(frame, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = title,
	})
	local close = button(frame, "X", RED, UDim2.fromOffset(44, 44))
	close.Position = UDim2.new(1, -54, 0, 8)
	close.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 60)
	body.Size = UDim2.new(1, -32, 1, -76)
	body.Parent = frame
	return frame, body
end

-- Shop ---------------------------------------------------------------------

local shopFrame, shopBody = modal("SHOP", Color3.fromRGB(255, 150, 40), 470)
local shopList = Instance.new("ScrollingFrame")
shopList.BackgroundTransparency = 1
shopList.Size = UDim2.fromScale(1, 1)
shopList.CanvasSize = UDim2.new()
shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopList.ScrollBarThickness = 6
shopList.Parent = shopBody
local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopList

local passButtons: { [string]: TextButton } = {}

local function shopRow(order: number, name: string, description: string, id: number, infoType: Enum.InfoType, onBuy: () -> ()): TextButton
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 70)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	row.LayoutOrder = order
	corner(row, 10)
	row.Parent = shopList

	text(row, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -150, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
	})
	text(row, {
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(1, -150, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 190, 205),
		TextStrokeTransparency = 1,
		Text = description,
	})

	local buy = button(row, if id == 0 then "SOON" else "R$ ...", GREEN, UDim2.fromOffset(120, 50))
	buy.Position = UDim2.new(1, -130, 0, 10)
	if id == 0 then
		buy.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		buy.AutoButtonColor = false
		return buy
	end

	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		if ok and info and info.PriceInRobux and buy.Text == "R$ ..." then
			buy.Text = "R$ " .. tostring(info.PriceInRobux)
		end
	end)
	buy.MouseButton1Click:Connect(onBuy)
	return buy
end

local function sectionHeader(order: number, label: string)
	text(shopList, {
		Size = UDim2.new(1, -10, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
		Text = label,
		LayoutOrder = order,
	})
end

sectionHeader(0, "GAMEPASSES (forever)")
for i, pass in Config.GamePasses do
	passButtons[pass.Key] = shopRow(i, pass.Name, pass.Description, pass.Id, Enum.InfoType.GamePass, function()
		if data and data.Owns[pass.Key] then
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
end
sectionHeader(100, "BOOSTS")
for i, product in Config.Products do
	shopRow(100 + i, product.Name, product.Description, product.Id, Enum.InfoType.Product, function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
end

-- Rebirth ------------------------------------------------------------------

local rebirthFrame, rebirthBody = modal("REBIRTH", Color3.fromRGB(170, 80, 255), 330)
local rebirthInfo = text(rebirthBody, {
	Size = UDim2.new(1, 0, 0, 110),
	TextWrapped = true,
	Text = "",
})
local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(0, 120)
barBack.Size = UDim2.new(1, 0, 0, 26)
barBack.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
corner(barBack, 8)
barBack.Parent = rebirthBody
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(170, 80, 255)
corner(barFill, 8)
barFill.Parent = barBack
local confirmRebirth = button(rebirthBody, "REBIRTH NOW", Color3.fromRGB(170, 80, 255), UDim2.new(1, 0, 0, 60))
confirmRebirth.Position = UDim2.fromOffset(0, 170)
confirmRebirth.MouseButton1Click:Connect(function()
	RequestRebirth:FireServer()
	rebirthFrame.Visible = false
end)

shopButton.MouseButton1Click:Connect(function()
	rebirthFrame.Visible = false
	shopFrame.Visible = not shopFrame.Visible
end)
rebirthButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
	rebirthFrame.Visible = not rebirthFrame.Visible
end)

-- Admin panel (only shown to admins; the server checks every action too) ---

local adminFrame, adminFrameBody = modal("ADMIN", RED, 620)
local adminBody = Instance.new("ScrollingFrame")
adminBody.BackgroundTransparency = 1
adminBody.Size = UDim2.fromScale(1, 1)
adminBody.CanvasSize = UDim2.new()
adminBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
adminBody.ScrollBarThickness = 6
adminBody.Parent = adminFrameBody
local adminLayout = Instance.new("UIListLayout")
adminLayout.Padding = UDim.new(0, 8)
adminLayout.SortOrder = Enum.SortOrder.LayoutOrder
adminLayout.Parent = adminBody

local function adminRow(order: number, height: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -10, 0, height)
	row.LayoutOrder = order
	row.Parent = adminBody
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	return row
end

local function adminHeader(order: number, label: string)
	text(adminBody, {
		Size = UDim2.new(1, -10, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
		Text = label,
		LayoutOrder = order,
	})
end

local function inputBox(parent: Instance, default: string, hint: string, width: number): TextBox
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(width, 38)
	box.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
	box.TextColor3 = WHITE
	box.PlaceholderText = hint
	box.Text = default
	box.Font = FONT
	box.TextScaled = true
	box.ClearTextOnFocus = false
	corner(box, 8)
	box.Parent = parent
	return box
end

local function smallButton(parent: Instance, label: string, color: Color3, width: number, onClick: () -> ()): TextButton
	local b = button(parent, label, color, UDim2.fromOffset(width, 38))
	b.MouseButton1Click:Connect(onClick)
	return b
end

local ORANGE = Color3.fromRGB(255, 150, 40)
local PURPLE = Color3.fromRGB(170, 80, 255)
local GREY = Color3.fromRGB(90, 90, 100)

-- Player + amount
adminHeader(1, "PLAYERS")
local targetRow = adminRow(2, 40)
text(targetRow, { Size = UDim2.fromOffset(70, 30), Text = "Player" })
local targetBox = inputBox(targetRow, "me", "me / all / name", 180)
text(targetRow, {
	Size = UDim2.fromOffset(230, 22),
	TextColor3 = Color3.fromRGB(170, 170, 185),
	Text = "me, all, or start of a name",
})

local function send(action: string, value: any)
	AdminAction:FireServer(action, targetBox.Text, value)
end

local cashRow = adminRow(3, 40)
local amountBox = inputBox(cashRow, "1m", "e.g. 5000, 25k, 2m", 110)
smallButton(cashRow, "Give Cash", GREEN, 120, function()
	send("Cash", amountBox.Text)
end)
smallButton(cashRow, "Set Cash", Color3.fromRGB(60, 140, 255), 110, function()
	send("SetCash", amountBox.Text)
end)
smallButton(cashRow, "Rebirths", PURPLE, 110, function()
	send("Rebirths", amountBox.Text)
end)

local function levelButtons(row: Frame, label: string, count: number, action: string, color: Color3)
	text(row, { Size = UDim2.fromOffset(62, 30), Text = label })
	for level = 1, count do
		smallButton(row, tostring(level), color, 38, function()
			send(action, level)
		end)
	end
end
levelButtons(adminRow(4, 40), "Walls", #Config.WallLevels, "Walls", ORANGE)
local baseRow = adminRow(5, 40)
levelButtons(baseRow, "Floors", #Config.Stories, "Floors", Color3.fromRGB(60, 140, 255))
levelButtons(baseRow, "Lock", #Config.LockLevels, "LockLevel", RED)

local miscRow = adminRow(6, 40)
smallButton(miscRow, "Clear Base", RED, 130, function()
	send("ClearBase", nil)
end)
smallButton(miscRow, "Luck 15m", Color3.fromRGB(60, 180, 120), 130, function()
	send("Luck", 15)
end)
smallButton(miscRow, "Stop Luck", GREY, 120, function()
	send("Luck", 0)
end)

-- Admin abuse + drops
adminHeader(7, "ADMIN ABUSE & DROPS")
local abuseRow = adminRow(8, 40)
smallButton(abuseRow, "Start Admin Abuse", RED, 220, function()
	send("AbuseStart", Config.AdminAbuse.DurationMinutes)
end)
smallButton(abuseRow, "End It", GREY, 110, function()
	send("AbuseStop", nil)
end)
local dropRow = adminRow(9, 40)
smallButton(dropRow, "Brainrot Rain x" .. Config.BrainrotRainCount, PURPLE, 210, function()
	send("BrainrotRain", nil)
end)
smallButton(dropRow, "Cash Rain", GREEN, 140, function()
	send("CashRain", amountBox.Text)
end)
text(dropRow, {
	Size = UDim2.fromOffset(150, 34),
	TextColor3 = Color3.fromRGB(170, 170, 185),
	TextWrapped = true,
	Text = "Cash Rain: each drop = amount box",
})

-- Mutation picker for Give / Spawn / Drop below.
adminHeader(10, "BRAINROTS")
local mutationChoices = { "None" }
for _, mutation in Config.Mutations do
	table.insert(mutationChoices, mutation.Id)
end
local mutationIndex = 1
local mutationRow = adminRow(11, 40)
text(mutationRow, { Size = UDim2.fromOffset(100, 30), Text = "Mutation" })
local mutationButton = smallButton(mutationRow, "None", GREY, 160, function() end)
mutationButton.MouseButton1Click:Connect(function()
	mutationIndex = mutationIndex % #mutationChoices + 1
	local choice = mutationChoices[mutationIndex]
	local mutation = Config.GetMutation(choice)
	mutationButton.Text = choice
	mutationButton.BackgroundColor3 = if mutation then mutation.Color else GREY
end)

local function brainrotValue(id: string): string
	local choice = mutationChoices[mutationIndex]
	return if choice == "None" then id else Config.Encode(id, choice)
end

for i, brainrot in Config.Brainrots do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 36)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	row.LayoutOrder = 100 + i
	corner(row, 8)
	row.Parent = adminBody
	local color = if brainrot.Rarity == "Secret" then Color3.fromRGB(255, 120, 255) else Config.Rarities[brainrot.Rarity].Color
	text(row, {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -270, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = brainrot.DisplayName,
	})
	local buttons: { { Label: string, Color: Color3, Action: string } } = {
		{ Label = "Give", Color = GREEN, Action = "Brainrot" },
		{ Label = "Spawn", Color = ORANGE, Action = "Spawn" },
		{ Label = "Drop", Color = PURPLE, Action = "DropBrainrot" },
	}
	for j, info in buttons do
		local b = smallButton(row, info.Label, info.Color, 80, function()
			send(info.Action, brainrotValue(brainrot.Id))
		end)
		b.Size = UDim2.fromOffset(80, 30)
		b.Position = UDim2.new(1, -258 + (j - 1) * 86, 0, 3)
	end
end

local adminButton = button(side, "ADMIN", RED, UDim2.fromOffset(130, 56))
adminButton.Visible = false
adminButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
	rebirthFrame.Visible = false
	adminFrame.Visible = not adminFrame.Visible
end)

-- Data -> UI ---------------------------------------------------------------

local function render()
	if not data then
		return
	end
	cashLabel.Text = Config.FormatCash(data.Cash)
	adminButton.Visible = data.IsAdmin == true
	incomeLabel.Text = string.format("+%s/s   x%.1f income", Config.FormatCash(data.Income), data.Multiplier)
	slotsLabel.Text = string.format("Base %d/%d   Steals %d", data.Placed, data.MaxSlots, data.Steals)

	for key, b in passButtons do
		if data.Owns[key] then
			b.Text = "OWNED"
			b.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		end
	end

	rebirthInfo.Text = string.format(
		"Rebirth %d\nCost: %s\nIncome x%.1f  ->  x%.1f\nYou keep gamepasses. Cash and brainrots reset.",
		data.Rebirths,
		Config.FormatCash(data.RebirthCost),
		data.Multiplier,
		data.NextMultiplier
	)
	barFill.Size = UDim2.fromScale(math.clamp(data.Cash / data.RebirthCost, 0, 1), 1)
	local ready = data.Cash >= data.RebirthCost
	confirmRebirth.BackgroundColor3 = if ready then Color3.fromRGB(170, 80, 255) else Color3.fromRGB(90, 90, 100)
	confirmRebirth.Text = if ready then "REBIRTH NOW" else "NOT ENOUGH CASH"
end

DataUpdated.OnClientEvent:Connect(function(snapshot)
	data = snapshot
	render()
end)

task.spawn(function()
	local snapshot = GetData:InvokeServer()
	if snapshot and not data then
		data = snapshot
		render()
	end
end)

-- Carrying banner ----------------------------------------------------------

local function updateCarry()
	local carrying = player:GetAttribute("Carrying") :: string?
	carryLabel.Visible = carrying ~= nil
	carryLabel.Text = if carrying then "RUN! Bring " .. carrying .. " to your base!" else ""
end
player:GetAttributeChangedSignal("Carrying"):Connect(updateCarry)
updateCarry()

-- Prompt visibility: Sell on your own brainrots, Steal on everyone else's ---

local function updatePrompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("Action")
	if action == "Upgrade" then
		-- Prompt lives on the upgrade post, directly inside the plot model.
		local post = prompt.Parent
		local plot = post and post.Parent
		prompt.Enabled = plot ~= nil and plot:GetAttribute("OwnerUserId") == player.UserId
		return
	end
	if action ~= "Sell" and action ~= "Steal" then
		return
	end
	local root = prompt.Parent
	local model = root and root.Parent
	if not model then
		return
	end
	local owner = model:GetAttribute("OwnerUserId")
	local carried = model:GetAttribute("Carried") == true
	local plot = model.Parent
	local locked = plot ~= nil and plot:GetAttribute("Locked") == true
	if action == "Sell" then
		prompt.Enabled = not carried and owner == player.UserId
	else
		prompt.Enabled = not carried and not locked and owner ~= 0 and owner ~= player.UserId
	end
end

task.spawn(function()
	local folder = workspace:WaitForChild("BrainrotHeist")
	while true do
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				updatePrompt(descendant)
			end
		end
		task.wait(0.25)
	end
end)

-- Admin abuse timer ----------------------------------------------------------

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

task.spawn(function()
	while true do
		local now = workspace:GetServerTimeNow()
		local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
		local status, seconds = Config.AdminAbuseStatus(now)
		if manualEnd and manualEnd > now then
			status, seconds = "live", manualEnd - now
		end
		if status == "live" then
			abuseLabel.Visible = true
			abuseLabel.TextColor3 = RED
			abuseLabel.Text = "ADMIN ABUSE LIVE!  " .. clock(seconds) .. " left"
		elseif status == "soon" then
			abuseLabel.Visible = true
			abuseLabel.TextColor3 = GOLD
			abuseLabel.Text = "ADMIN ABUSE IN " .. clock(seconds)
		else
			abuseLabel.Visible = false
		end
		task.wait(0.5)
	end
end)

-- Server luck timer --------------------------------------------------------

task.spawn(function()
	while true do
		local endsAt = ReplicatedStorage:GetAttribute("LuckEndsAt") :: number?
		local left = if endsAt then endsAt - workspace:GetServerTimeNow() else 0
		luckLabel.Visible = left > 0
		if left > 0 then
			luckLabel.Text = string.format("SERVER LUCK  %d:%02d", left // 60, math.floor(left % 60))
		end
		task.wait(0.5)
	end
end)

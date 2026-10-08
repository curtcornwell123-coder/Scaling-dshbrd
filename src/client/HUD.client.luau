--!strict
-- Brainrot Heist client: cash HUD, shop, rebirth menu, announcements and
-- which prompts (Buy / Sell / Steal) each player sees.

local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
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
local BuyLimited = Remotes:WaitForChild("BuyLimited") :: RemoteFunction
local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade") :: RemoteEvent
local SetFollowers = Remotes:WaitForChild("SetFollowers") :: RemoteEvent
local SkinAction = Remotes:WaitForChild("SkinAction") :: RemoteEvent
local DiamondPurchase = Remotes:WaitForChild("DiamondPurchase") :: RemoteEvent

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
cashPanel.Size = UDim2.fromOffset(320, 112)
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

local currencyLabel = text(cashPanel, {
	Position = UDim2.fromOffset(10, 90),
	Size = UDim2.new(1, -20, 0, 18),
	TextColor3 = Color3.fromRGB(140, 220, 255),
	Text = "Shards 0   |   Diamonds 0",
})

local luckLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 126),
	Size = UDim2.fromOffset(320, 28),
	TextColor3 = Color3.fromRGB(120, 255, 160),
	Text = "",
	Visible = false,
})

-- Weekly admin abuse: countdown in the last hour, then a LIVE banner.
local abuseLabel = text(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 156),
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
side.Size = UDim2.fromOffset(130, 340)
side.Parent = gui
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 10)
sideLayout.Parent = side

local shopButton = button(side, "SHOP", Color3.fromRGB(255, 150, 40), UDim2.fromOffset(130, 56))
local rebirthButton = button(side, "REBIRTH", Color3.fromRGB(170, 80, 255), UDim2.fromOffset(130, 56))
local questsButton = button(side, "QUESTS", Color3.fromRGB(60, 170, 255), UDim2.fromOffset(130, 56))
local followButton = button(side, "FOLLOW", Color3.fromRGB(60, 200, 120), UDim2.fromOffset(130, 56))

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
	Position = UDim2.new(0.5, 0, 0, 194),
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
	elseif kind == "limited" and brainrot then
		local name = if mutation then string.upper(mutation.DisplayName) .. " " .. brainrot.DisplayName else brainrot.DisplayName
		showBanner(who .. " got " .. name .. " #" .. (extra or "?") .. "!", color)
	elseif kind == "magic" and brainrot then
		showBanner(who .. "'s " .. brainrot.DisplayName .. " turned MAGIC!", Color3.fromRGB(190, 130, 255))
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

-- Reserves a limited item and opens the Robux prompt (server does the rest).
local buyingLimited = false
local function buyLimitedItem(itemId: string)
	if buyingLimited then
		return
	end
	buyingLimited = true
	local ok, message = BuyLimited:InvokeServer(itemId)
	buyingLimited = false
	if not ok and message then
		toast(message)
	end
end

-- Limited event brainrots: live stock, one per player.
local limitedButtons: { [string]: TextButton } = {}
local limitedStock: { [string]: TextLabel } = {}
local limitedIds = {}
for itemId in Config.LimitedItems do
	table.insert(limitedIds, itemId)
end
table.sort(limitedIds)
if #limitedIds > 0 then
	sectionHeader(-100, "LIMITED EVENT")
end
for i, itemId in limitedIds do
	local item = Config.LimitedItems[itemId]
	local brainrot = Config.GetBrainrot(itemId)
	if brainrot then
		local rarity = Config.Rarities[brainrot.Rarity]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -10, 0, 104)
		row.BackgroundColor3 = Color3.fromRGB(70, 30, 65)
		row.LayoutOrder = -100 + i
		corner(row, 10)
		stroke(row, 2, rarity.Color)
		row.Parent = shopList

		text(row, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -150, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarity.Color,
			Text = brainrot.DisplayName,
		})
		limitedStock[itemId] = text(row, {
			Position = UDim2.fromOffset(12, 38),
			Size = UDim2.new(1, -150, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = GOLD,
			Text = string.format("LIMITED: %d of %d left", item.Stock, item.Stock),
		})
		text(row, {
			Position = UDim2.fromOffset(12, 62),
			Size = UDim2.new(1, -150, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(220, 200, 220),
			TextStrokeTransparency = 1,
			TextWrapped = true,
			Text = string.format("%s/s, doubles every rebirth. Can't be stolen. Kept on rebirth. 1 per player.", Config.FormatCash(brainrot.Income)),
		})

		local buy = button(row, if item.ProductId == 0 then "SOON" else "R$ " .. item.PriceRobux, GREEN, UDim2.fromOffset(120, 56))
		buy.Position = UDim2.new(1, -130, 0, 24)
		limitedButtons[itemId] = buy
		buy.MouseButton1Click:Connect(function()
			if item.ProductId == 0 or (data and data.Limited and data.Limited[itemId]) then
				return
			end
			buy.Text = "..."
			buyLimitedItem(itemId)
			buy.Text = "R$ " .. item.PriceRobux
		end)
	end
end

local function renderLimited()
	for itemId, label in limitedStock do
		local item = Config.LimitedItems[itemId]
		local published = ReplicatedStorage:GetAttribute("LimitedLeft_" .. itemId) :: number?
		local left: number = if published then published else item.Stock
		label.Text = string.format("LIMITED: %d of %d left", left, item.Stock)
		local b = limitedButtons[itemId]
		local serial = data and data.Limited and data.Limited[itemId]
		if serial then
			b.Text = "OWNED #" .. serial
			b.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		elseif item.ProductId == 0 then
			b.Text = "SOON"
			b.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		elseif left <= 0 then
			b.Text = "SOLD OUT"
			b.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		else
			b.BackgroundColor3 = GREEN
		end
	end
end
for itemId in Config.LimitedItems do
	ReplicatedStorage:GetAttributeChangedSignal("LimitedLeft_" .. itemId):Connect(renderLimited)
end
renderLimited()

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

-- Base upgrades panel: opened from the upgrade post in your base --------------

local upgradeFrame, upgradeBody = modal("BASE UPGRADES", Color3.fromRGB(255, 170, 40), 310)
local upgradeLayout = Instance.new("UIListLayout")
upgradeLayout.Padding = UDim.new(0, 10)
upgradeLayout.SortOrder = Enum.SortOrder.LayoutOrder
upgradeLayout.Parent = upgradeBody

type UpgradeCard = { Now: TextLabel, Next: TextLabel, Button: TextButton }
local upgradeCards: { [string]: UpgradeCard } = {}

local function upgradeCard(order: number, kind: string, title: string, color: Color3)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	card.LayoutOrder = order
	corner(card, 12)
	stroke(card, 2, color)
	card.Parent = upgradeBody

	text(card, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -190, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = title,
	})
	local now = text(card, {
		Position = UDim2.fromOffset(14, 42),
		Size = UDim2.new(1, -190, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local nextLabel = text(card, {
		Position = UDim2.fromOffset(14, 68),
		Size = UDim2.new(1, -190, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 190, 205),
		TextStrokeTransparency = 1,
		Text = "",
	})
	local buy = button(card, "UPGRADE", GREEN, UDim2.fromOffset(160, 72))
	buy.Position = UDim2.new(1, -172, 0, 14)
	buy.MouseButton1Click:Connect(function()
		RequestUpgrade:FireServer(kind)
	end)
	upgradeCards[kind] = { Now = now, Next = nextLabel, Button = buy }
end

upgradeCard(1, "Base", "BASE (floor + walls)", Color3.fromRGB(255, 170, 40))
upgradeCard(2, "Lock", "LOCK TIME", RED)

local function renderUpgrades()
	if not data or not data.WallLevel then
		return
	end
	local longer = data.Owns and data.Owns.LongerLock
	local function set(kind: string, now: string, nextText: string?, cost: number?, needRebirths: number?)
		local card = upgradeCards[kind]
		card.Now.Text = now
		if nextText and cost and needRebirths and (data.Rebirths or 0) < needRebirths then
			card.Next.Text = "Next: " .. nextText .. string.format(" (needs %d rebirth%s)", needRebirths, if needRebirths == 1 then "" else "s")
			card.Button.Text = "REBIRTH\n" .. needRebirths .. "x FIRST"
			card.Button.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		elseif nextText and cost then
			card.Next.Text = "Next: " .. nextText
			local affordable = data.Cash >= cost
			card.Button.Text = "UPGRADE\n" .. Config.FormatCash(cost)
			card.Button.BackgroundColor3 = if affordable then GREEN else Color3.fromRGB(90, 90, 100)
		else
			card.Next.Text = "Fully upgraded!"
			card.Button.Text = "MAX"
			card.Button.BackgroundColor3 = GOLD
		end
	end

	local level = data.WallLevel
	local wall = Config.WallLevels[level]
	local nextWall = Config.WallLevels[level + 1]
	local nextStory = Config.Stories[level + 1]
	set(
		"Base",
		string.format("Level %d: %s, %d floor%s", level, wall.Name, level, if level == 1 then "" else "s"),
		nextWall and nextStory and string.format("%s + %s (+%d slots)", nextStory.Name, nextWall.Name, Config.UpperFloorSlots),
		nextWall and nextWall.Cost
	)

	local nextLock = Config.LockLevels[data.LockLevel + 1]
	if data.InfiniteLock then
		set("Lock", "Lasers stay on FOREVER (Infinite Laser Door)", nil, nil)
	else
		set("Lock", string.format("Lasers stay on %ds", data.LockDuration or 0), nextLock and string.format("%ds", nextLock.Duration * (if longer then 2 else 1)), nextLock and nextLock.Cost, nextLock and nextLock.Rebirths)
	end
end

-- Opening the panel from the post; it closes again if you walk away.
local openPost: BasePart? = nil
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt:GetAttribute("Action") == "OpenUpgrades" then
		openPost = prompt.Parent :: BasePart
		shopFrame.Visible = false
		rebirthFrame.Visible = false
		renderUpgrades()
		upgradeFrame.Visible = true
	end
end)
task.spawn(function()
	while true do
		task.wait(0.5)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if upgradeFrame.Visible and openPost and root and (root.Position - openPost.Position).Magnitude > 30 then
			upgradeFrame.Visible = false
		end
	end
end)


-- Quests & wall skins --------------------------------------------------------

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return string.format("%dd %dh", seconds // 86400, (seconds % 86400) // 3600)
	elseif seconds >= 3600 then
		return string.format("%dh %dm", seconds // 3600, (seconds % 3600) // 60)
	end
	return string.format("%dm", math.max(1, seconds // 60))
end

local function scrollBody(parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	return scroll
end

local SHARD_COLOR = Color3.fromRGB(140, 220, 255)
local DIAMOND_COLOR = Color3.fromRGB(120, 180, 255)

local questsFrame, questsFrameBody = modal("QUESTS & SKINS", Color3.fromRGB(60, 170, 255), 600)
local questsBody = scrollBody(questsFrameBody)

local function header(parent: Instance, order: number, label: string, color: Color3): TextLabel
	return text(parent, {
		Size = UDim2.new(1, -10, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = label,
		LayoutOrder = order,
	})
end

type QuestRow = { Text: TextLabel, Fill: Frame, Count: TextLabel }
local function questRow(order: number): QuestRow
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	row.LayoutOrder = order
	corner(row, 10)
	row.Parent = questsBody
	local label = text(row, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -130, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(12, 36)
	bar.Size = UDim2.new(1, -130, 0, 12)
	bar.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
	corner(bar, 6)
	bar.Parent = row
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GREEN
	corner(fill, 6)
	fill.Parent = bar
	local count = text(row, {
		Position = UDim2.new(1, -110, 0, 14),
		Size = UDim2.fromOffset(100, 30),
		Text = "",
	})
	return { Text = label, Fill = fill, Count = count }
end

local dailyHeader = header(questsBody, 1, "DAILY QUESTS", GOLD)
text(questsBody, {
	Size = UDim2.new(1, -10, 0, 20),
	TextColor3 = SHARD_COLOR,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "+" .. Config.DailyShards .. " Shards each",
	LayoutOrder = 2,
})
local dailyRows: { QuestRow } = {}
for i = 1, Config.QuestsPerPeriod do
	dailyRows[i] = questRow(2 + i)
end
local weeklyHeader = header(questsBody, 10, "WEEKLY QUESTS", Color3.fromRGB(255, 120, 255))
text(questsBody, {
	Size = UDim2.new(1, -10, 0, 20),
	TextColor3 = DIAMOND_COLOR,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = string.format("+%d Diamond and +%d Shards each (much harder!)", Config.WeeklyDiamonds, Config.WeeklyShards),
	LayoutOrder = 11,
})
local weeklyRows: { QuestRow } = {}
for i = 1, Config.QuestsPerPeriod do
	weeklyRows[i] = questRow(11 + i)
end

header(questsBody, 20, "WALL SKINS", Color3.fromRGB(255, 170, 40))
local balanceLabel = text(questsBody, {
	Size = UDim2.new(1, -10, 0, 22),
	TextColor3 = SHARD_COLOR,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	LayoutOrder = 21,
})
local skinButtons: { [string]: TextButton } = {}
for i, skin in Config.WallSkins do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 50)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	row.LayoutOrder = 21 + i
	corner(row, 10)
	row.Parent = questsBody
	local swatch = Instance.new("Frame")
	swatch.Position = UDim2.fromOffset(10, 9)
	swatch.Size = UDim2.fromOffset(32, 32)
	swatch.BackgroundColor3 = skin.Color or Color3.fromRGB(140, 140, 145)
	corner(swatch, 6)
	stroke(swatch, 2, skin.Glass or Color3.fromRGB(80, 150, 255))
	swatch.Parent = row
	text(row, {
		Position = UDim2.fromOffset(52, 10),
		Size = UDim2.new(1, -220, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = skin.Name,
	})
	local b = button(row, "", GREEN, UDim2.fromOffset(150, 40))
	b.Position = UDim2.new(1, -160, 0, 5)
	b.MouseButton1Click:Connect(function()
		local owned = data and data.Skins and table.find(data.Skins, skin.Id)
		SkinAction:FireServer(if owned then "Equip" else "Buy", skin.Id)
	end)
	skinButtons[skin.Id] = b
end

local function renderQuests()
	if not data or not data.Quests then
		return
	end
	local q = data.Quests
	dailyHeader.Text = "DAILY QUESTS   (new in " .. duration(q.DayResetIn) .. ")"
	weeklyHeader.Text = "WEEKLY QUESTS   (new in " .. duration(q.WeekResetIn) .. ")"
	local function fill(rows: { QuestRow }, list: { any })
		for i, row in rows do
			local quest = list[i]
			if quest then
				row.Text.Text = quest.Text
				row.Fill.Size = UDim2.fromScale(math.clamp(quest.Progress / quest.Goal, 0, 1), 1)
				row.Fill.BackgroundColor3 = if quest.Done then GOLD else GREEN
				row.Count.Text = if quest.Done then "DONE!" else string.format("%d/%d", quest.Progress, quest.Goal)
			end
		end
	end
	fill(dailyRows, q.Daily)
	fill(weeklyRows, q.Weekly)

	balanceLabel.Text = string.format("You have %d Shards and %d Diamonds", data.Shards or 0, data.Diamonds or 0)
	for _, skin in Config.WallSkins do
		local b = skinButtons[skin.Id]
		local owned = data.Skins and table.find(data.Skins, skin.Id)
		if data.Skin == skin.Id then
			b.Text = "EQUIPPED"
			b.BackgroundColor3 = GOLD
		elseif owned then
			b.Text = "EQUIP"
			b.BackgroundColor3 = Color3.fromRGB(60, 140, 255)
		else
			local needed = Config.SkinRequirement(skin)
			local balance = if skin.Currency == "Diamonds" then data.Diamonds else data.Shards
			if needed and not (data.Skins and table.find(data.Skins, needed.Id)) then
				b.Text = "Unlock " .. needed.Name .. " first"
				b.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			else
				b.Text = string.format("%s %s", Config.FormatNumber(skin.Cost), skin.Currency)
				b.BackgroundColor3 = if (balance or 0) >= skin.Cost
					then (if skin.Currency == "Diamonds" then DIAMOND_COLOR else GREEN)
					else Color3.fromRGB(90, 90, 100)
			end
		end
	end
end

-- Followers ---------------------------------------------------------------------

local followFrame, followFrameBody = modal("FOLLOWERS", Color3.fromRGB(60, 200, 120), 560)
text(followFrameBody, {
	Size = UDim2.new(1, 0, 0, 40),
	TextWrapped = true,
	TextColor3 = Color3.fromRGB(200, 200, 215),
	TextStrokeTransparency = 1,
	Text = "Pick up to 3 brainrots to follow you as minis. If one gets stolen from your base, it stops following.",
})
local rarestButton = button(followFrameBody, "PICK MY 3 RAREST", GOLD, UDim2.new(1, 0, 0, 44))
rarestButton.Position = UDim2.fromOffset(0, 46)
local followListHolder = Instance.new("Frame")
followListHolder.BackgroundTransparency = 1
followListHolder.Position = UDim2.fromOffset(0, 98)
followListHolder.Size = UDim2.new(1, 0, 1, -98)
followListHolder.Parent = followFrameBody
local followList = scrollBody(followListHolder)

-- Rarest first, then highest income.
local function sortedBase(): { any }
	local list = table.clone(data and data.Base or {})
	local function score(entry: any): (number, number)
		local brainrot = Config.GetBrainrot(entry.Id)
		if not brainrot then
			return 0, 0
		end
		return Config.Rarities[brainrot.Rarity].Order, Config.IncomeOf(brainrot, entry.Mutation)
	end
	table.sort(list, function(a, b)
		local ra, ia = score(a)
		local rb, ib = score(b)
		if ra ~= rb then
			return ra > rb
		end
		return ia > ib
	end)
	return list
end

local function currentFollowing(): { number }
	local slots = {}
	for _, entry in data and data.Base or {} do
		if entry.Following then
			table.insert(slots, entry.Slot)
		end
	end
	return slots
end

rarestButton.MouseButton1Click:Connect(function()
	local slots = {}
	for _, entry in sortedBase() do
		if #slots < 3 then
			table.insert(slots, entry.Slot)
		end
	end
	SetFollowers:FireServer(slots)
end)

local function renderFollowers()
	if not followFrame.Visible or not data then
		return
	end
	for _, child in followList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, entry in sortedBase() do
		local brainrot = Config.GetBrainrot(entry.Id)
		if brainrot then
			local mutation = Config.GetMutation(entry.Mutation)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -10, 0, 44)
			row.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
			row.LayoutOrder = i
			corner(row, 8)
			row.Parent = followList
			text(row, {
				Position = UDim2.fromOffset(10, 7),
				Size = UDim2.new(1, -170, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if mutation then mutation.Color else Config.Rarities[brainrot.Rarity].Color,
				Text = (if mutation then mutation.DisplayName .. " " else "") .. brainrot.DisplayName,
			})
			local b = button(row, if entry.Following then "FOLLOWING" else "FOLLOW", if entry.Following then GOLD else GREEN, UDim2.fromOffset(140, 34))
			b.Position = UDim2.new(1, -150, 0, 5)
			b.MouseButton1Click:Connect(function()
				local slots = currentFollowing()
				local at = table.find(slots, entry.Slot)
				if at then
					table.remove(slots, at)
				elseif #slots >= 3 then
					toast("You can only have 3 followers. Remove one first.")
					return
				else
					table.insert(slots, entry.Slot)
				end
				SetFollowers:FireServer(slots)
			end)
		end
	end
end

-- Diamond Shop (the booth by the spawn) ---------------------------------------

local diamondFrame, diamondFrameBody = modal("DIAMOND SHOP", DIAMOND_COLOR, 560)
local diamondBody = scrollBody(diamondFrameBody)
local diamondBalance = text(diamondBody, {
	Size = UDim2.new(1, -10, 0, 28),
	TextColor3 = DIAMOND_COLOR,
	Text = "",
	LayoutOrder = 0,
})
text(diamondBody, {
	Size = UDim2.new(1, -10, 0, 20),
	TextColor3 = Color3.fromRGB(190, 190, 205),
	TextStrokeTransparency = 1,
	Text = "Diamonds come from weekly quests and admin abuse. Save up!",
	LayoutOrder = 1,
})

local diamondButtons: { { Button: TextButton, Cost: number, SkinId: string?, ItemId: string? } } = {}
local function diamondRow(order: number, name: string, description: string, cost: number, onBuy: () -> (), skinId: string?, itemId: string?)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 70)
	row.BackgroundColor3 = Color3.fromRGB(35, 45, 70)
	row.LayoutOrder = order
	corner(row, 10)
	stroke(row, 2, DIAMOND_COLOR)
	row.Parent = diamondBody
	text(row, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -170, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
	})
	text(row, {
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.new(1, -170, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 190, 205),
		TextStrokeTransparency = 1,
		Text = description,
	})
	local b = button(row, cost .. " Diamonds", DIAMOND_COLOR, UDim2.fromOffset(150, 50))
	b.Position = UDim2.new(1, -160, 0, 10)
	b.MouseButton1Click:Connect(onBuy)
	table.insert(diamondButtons, { Button = b, Cost = cost, SkinId = skinId, ItemId = itemId })
end

header(diamondBody, 2, "BOOSTS", GOLD)
for i, item in Config.DiamondShop do
	diamondRow(2 + i, item.Name, item.Description, item.Cost, function()
		DiamondPurchase:FireServer(item.Id)
	end, nil, item.Id)
end
header(diamondBody, 20, "DIAMOND WALL SKINS", Color3.fromRGB(255, 170, 40))
for i, skin in Config.WallSkins do
	if skin.Currency == "Diamonds" then
		local needed = Config.SkinRequirement(skin)
		local note = if needed then "Rare wall skin. Unlock " .. needed.Name .. " first." else "A rare wall skin for your base."
		diamondRow(20 + i, skin.Name, note, skin.Cost, function()
			local owned = data and data.Skins and table.find(data.Skins, skin.Id)
			SkinAction:FireServer(if owned then "Equip" else "Buy", skin.Id)
		end, skin.Id)
	end
end

local function renderDiamondShop()
	if not data then
		return
	end
	local diamonds = data.Diamonds or 0
	diamondBalance.Text = string.format("You have %d Diamonds", diamonds)
	for _, entry in diamondButtons do
		local owned = entry.SkinId and data.Skins and table.find(data.Skins, entry.SkinId)
		if entry.ItemId == "InfiniteLock" and data.InfiniteLock then
			entry.Button.Text = "OWNED"
			entry.Button.BackgroundColor3 = GOLD
		elseif entry.SkinId and data.Skin == entry.SkinId then
			entry.Button.Text = "EQUIPPED"
			entry.Button.BackgroundColor3 = GOLD
		elseif owned then
			entry.Button.Text = "EQUIP"
			entry.Button.BackgroundColor3 = Color3.fromRGB(60, 140, 255)
		else
			local skin = entry.SkinId and Config.GetWallSkin(entry.SkinId)
			local needed = skin and Config.SkinRequirement(skin)
			if needed and not (data.Skins and table.find(data.Skins, needed.Id)) then
				entry.Button.Text = "LOCKED"
				entry.Button.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			else
				entry.Button.Text = entry.Cost .. " Diamonds"
				entry.Button.BackgroundColor3 = if diamonds >= entry.Cost then DIAMOND_COLOR else Color3.fromRGB(90, 90, 100)
			end
		end
	end
end

-- Only one menu open at a time.
local menus = { shopFrame, rebirthFrame, upgradeFrame, questsFrame, followFrame, diamondFrame }
local function toggleMenu(frame: Frame)
	local open = not frame.Visible
	for _, menu in menus do
		menu.Visible = false
	end
	frame.Visible = open
end
shopButton.MouseButton1Click:Connect(function()
	toggleMenu(shopFrame)
end)
rebirthButton.MouseButton1Click:Connect(function()
	toggleMenu(rebirthFrame)
end)
questsButton.MouseButton1Click:Connect(function()
	toggleMenu(questsFrame)
	renderQuests()
end)
followButton.MouseButton1Click:Connect(function()
	toggleMenu(followFrame)
	renderFollowers()
end)

-- The two counters at the Diamond Shop booth.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local action = prompt:GetAttribute("Action")
	if action == "DiamondShop" then
		toggleMenu(diamondFrame)
		renderDiamondShop()
	elseif action == "RobuxShop" then
		toggleMenu(shopFrame)
	elseif action == "BuyEvent" then
		buyLimitedItem(prompt:GetAttribute("ItemId") :: string)
	end
end)

-- Tapping / clicking the event statue buys it too.
task.spawn(function()
	local statue = workspace:WaitForChild("BrainrotHeist"):WaitForChild("EventStatue", 30)
	local hitbox = statue and statue:WaitForChild("BuyHitbox", 10)
	local click = hitbox and hitbox:FindFirstChildOfClass("ClickDetector")
	if hitbox and click then
		click.MouseClick:Connect(function()
			buyLimitedItem(hitbox:GetAttribute("ItemId") :: string)
		end)
	end
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
local currencyRow = adminRow(3, 40)
text(currencyRow, { Size = UDim2.fromOffset(110, 30), Text = "Quest $" })
smallButton(currencyRow, "Give Shards", SHARD_COLOR, 150, function()
	send("Shards", amountBox.Text)
end)
smallButton(currencyRow, "Give Diamonds", DIAMOND_COLOR, 170, function()
	send("Diamonds", amountBox.Text)
end)

local function levelButtons(row: Frame, label: string, count: number, action: string, color: Color3)
	text(row, { Size = UDim2.fromOffset(62, 30), Text = label })
	for level = 1, count do
		smallButton(row, tostring(level), color, 38, function()
			send(action, level)
		end)
	end
end
levelButtons(adminRow(4, 40), "Base", #Config.WallLevels, "Base", ORANGE)
levelButtons(adminRow(5, 40), "Lock", #Config.LockLevels, "LockLevel", RED)
local doorRow = adminRow(5, 40)
text(doorRow, { Size = UDim2.fromOffset(150, 30), Text = "Infinite Door" })
smallButton(doorRow, "ON", Color3.fromRGB(255, 80, 80), 90, function()
	send("InfiniteLock", true)
end)
smallButton(doorRow, "OFF", GREY, 90, function()
	send("InfiniteLock", false)
end)

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
text(abuseRow, { Size = UDim2.fromOffset(70, 30), Text = "Minutes" })
local minutesBox = inputBox(abuseRow, tostring(Config.AdminAbuse.DurationMinutes), "how long", 70)
smallButton(abuseRow, "Start Admin Abuse", RED, 200, function()
	send("AbuseStart", minutesBox.Text)
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

-- Message to every server (same as typing /announce in chat).
local announceRow = adminRow(9, 40)
local announceBox = inputBox(announceRow, "", "Message to ALL servers", 330)
announceBox.ClearTextOnFocus = false
smallButton(announceRow, "Announce", Color3.fromRGB(255, 170, 40), 130, function()
	send("GlobalAnnounce", announceBox.Text)
	announceBox.Text = ""
end)

-- Founder events (only Corny and Ace see these): one button per event, plus
-- a stop button. They run for the Minutes box above.
local founderRow = adminRow(9, 40)
founderRow.Visible = false
local founderEventIds = {}
for eventId in Config.FounderEvents do
	table.insert(founderEventIds, eventId)
end
table.sort(founderEventIds)
for _, eventId in founderEventIds do
	smallButton(founderRow, eventId .. " Event", Color3.fromRGB(255, 120, 190), 170, function()
		send("FounderEvent", { Id = eventId, Minutes = minutesBox.Text })
	end)
end
smallButton(founderRow, "End Founder Event", GREY, 190, function()
	send("FounderEventStop", nil)
end)
smallButton(founderRow, "Save My Event Look", GOLD, 210, function()
	send("SaveEventLook", nil)
end)

-- Mutation picker for Give / Spawn / Drop below.
adminHeader(10, "BRAINROTS")
local mutationChoices = { "None" }
for _, mutation in Config.Mutations do
	if not mutation.Exclusive then
		table.insert(mutationChoices, mutation.Id)
	end
end
local mutationIndex = 1
local mutationRow = adminRow(11, 40)
text(mutationRow, { Size = UDim2.fromOffset(100, 30), Text = "Mutation" })
local mutationButton = smallButton(mutationRow, "None", GREY, 160, function() end)
smallButton(mutationRow, "Give MAGIC (event)", Color3.fromRGB(170, 110, 255), 220, function()
	send("GiveMagic", nil)
end)
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
	if brainrot.Limited then
		-- Limited brainrots can only be handed out from the reserved copies.
		buttons = { { Label = "Give #", Color = GREEN, Action = "Brainrot" } }
	end
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
	founderRow.Visible = data.IsFounder == true
	incomeLabel.Text = string.format("+%s/s   x%.1f income", Config.FormatCash(data.Income), data.Multiplier)
	if (data.CashBoostLeft or 0) > 0 then
		incomeLabel.Text ..= string.format("  (2x boost %dm)", math.ceil(data.CashBoostLeft / 60))
	end
	slotsLabel.Text = string.format("Base %d/%d   Steals %d", data.Placed, data.MaxSlots, data.Steals)

	renderLimited()
	renderUpgrades()
	renderQuests()
	renderFollowers()
	renderDiamondShop()
	currencyLabel.Text = string.format("Shards %d   |   Diamonds %d", data.Shards or 0, data.Diamonds or 0)
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
	if action == "OpenUpgrades" then
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
	-- Limited (Robux) brainrots can't be stolen or sold.
	local carried = model:GetAttribute("Carried") == true or model:GetAttribute("Protected") == true
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

-- Boost badges --------------------------------------------------------------
-- Bottom right: every boost that's on right now and how long it has left.

local badgeHolder = Instance.new("Frame")
badgeHolder.Name = "BoostBadges"
badgeHolder.AnchorPoint = Vector2.new(1, 1)
badgeHolder.Position = UDim2.new(1, -12, 1, -12)
badgeHolder.Size = UDim2.fromOffset(220, 330)
badgeHolder.BackgroundTransparency = 1
badgeHolder.Parent = gui
local badgeLayout = Instance.new("UIListLayout")
badgeLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
badgeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
badgeLayout.Padding = UDim.new(0, 6)
badgeLayout.SortOrder = Enum.SortOrder.LayoutOrder
badgeLayout.Parent = badgeHolder

type Badge = { Frame: Frame, Name: TextLabel, Time: TextLabel }
local badges: { [string]: Badge } = {}

local function badge(id: string, order: number): Badge
	local existing = badges[id]
	if existing then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(220, 34)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	frame.BackgroundTransparency = 0.15
	frame.Parent = badgeHolder
	corner(frame, 10)
	local name = text(frame, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -80, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local time = text(frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 64, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(220, 220, 235),
		Text = "",
	})
	local made = { Frame = frame, Name = name, Time = time }
	badges[id] = made
	return made
end

local function timeLeft(seconds: number?): string
	if not seconds then
		return "FOREVER"
	end
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

task.spawn(function()
	local lastSnapshot: any = nil
	local cashBoostEnds = 0
	while true do
		local now = workspace:GetServerTimeNow()
		if data ~= lastSnapshot then
			lastSnapshot = data
			cashBoostEnds = os.clock() + (if data then data.CashBoostLeft or 0 else 0)
		end
		type Active = { Id: string, Name: string, Color: Color3, Left: number? }
		local active: { Active } = {}

		-- Admin abuse (weekly, or started by an admin)
		local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
		local status, seconds = Config.AdminAbuseStatus(now)
		if manualEnd and manualEnd > now then
			status, seconds = "live", manualEnd - now
		end
		if status == "live" then
			local boosts = Config.AdminAbuseBoosts
			table.insert(active, { Id = "AbuseCash", Name = string.format("x%d CASH", boosts.Income), Color = Color3.fromRGB(120, 255, 140), Left = seconds })
			table.insert(active, { Id = "AbuseLuck", Name = string.format("x%d LUCK", boosts.Luck), Color = Color3.fromRGB(120, 255, 200), Left = seconds })
			table.insert(active, { Id = "AbuseSpeed", Name = "SPEED + JUMP", Color = Color3.fromRGB(120, 200, 255), Left = seconds })
		end
		-- Founder events with a luck boost (Ace's)
		local founderEvent = Config.FounderEvents[ReplicatedStorage:GetAttribute("FounderEvent") :: string? or ""]
		local founderEnds = ReplicatedStorage:GetAttribute("FounderEventEndsAt") :: number?
		if founderEvent and founderEvent.Luck and founderEnds and founderEnds > now then
			table.insert(active, { Id = "FounderLuck", Name = string.format("x%d LUCK (%s)", founderEvent.Luck, founderEvent.Founder), Color = Color3.fromRGB(255, 150, 210), Left = founderEnds - now })
		end
		-- Server Luck (bought by someone)
		local luckEnds = ReplicatedStorage:GetAttribute("LuckEndsAt") :: number?
		if luckEnds and luckEnds > now then
			table.insert(active, { Id = "ServerLuck", Name = string.format("x%d SERVER LUCK", Config.ServerLuckMultiplier), Color = Color3.fromRGB(120, 255, 160), Left = luckEnds - now })
		end
		-- Your own boosts
		if cashBoostEnds > os.clock() then
			table.insert(active, { Id = "CashBoost", Name = "x2 CASH BOOST", Color = Color3.fromRGB(255, 220, 90), Left = cashBoostEnds - os.clock() })
		end
		if data and data.Owns and data.Owns.DoubleCash then
			table.insert(active, { Id = "DoubleCash", Name = "x2 CASH PASS", Color = Color3.fromRGB(255, 200, 60), Left = nil })
		end

		local shown: { [string]: boolean } = {}
		for i, info in active do
			local b = badge(info.Id, i)
			b.Frame.LayoutOrder = i
			b.Name.Text = info.Name
			b.Name.TextColor3 = info.Color
			b.Time.Text = timeLeft(info.Left)
			shown[info.Id] = true
		end
		for id, b in badges do
			if not shown[id] then
				b.Frame:Destroy()
				badges[id] = nil
			end
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

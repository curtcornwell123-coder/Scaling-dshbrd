--!strict
-- Brainrot Heist client: cash HUD, shop, rebirth menu, announcements and
-- which prompts (Buy / Sell / Steal) each player sees.

local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrainrotModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotModel"))
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
local RedeemCode = Remotes:WaitForChild("RedeemCode") :: RemoteFunction

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(25, 25, 35)
local GREEN = Color3.fromRGB(70, 210, 90)
local GOLD = Color3.fromRGB(255, 200, 50)
local RED = Color3.fromRGB(235, 60, 70)
-- One dark look for every window (matches the shop).
local PANEL_BG = Color3.fromRGB(32, 32, 40)
local PANEL_DARK = Color3.fromRGB(22, 22, 28)
local TILE = Color3.fromRGB(44, 44, 54)
local EDGE = Color3.fromRGB(12, 12, 16)
local UI_GREY = Color3.fromRGB(90, 90, 100)

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
cashPanel.BackgroundColor3 = PANEL_BG
cashPanel.BackgroundTransparency = 0.1
corner(cashPanel, 10)
stroke(cashPanel, 3, EDGE)
cashPanel.Parent = gui
local cashAccent = Instance.new("Frame")
cashAccent.BorderSizePixel = 0
cashAccent.BackgroundColor3 = GREEN
cashAccent.AnchorPoint = Vector2.new(0.5, 1)
cashAccent.Position = UDim2.new(0.5, 0, 1, -4)
cashAccent.Size = UDim2.new(1, -24, 0, 3)
cashAccent.Parent = cashPanel

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
	Text = "🔷 0   💎 0",
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

-- Menu buttons styled like the shop's category tiles: a big icon and a label.
local function sideButton(label: string, emoji: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(130, 56)
	b.BackgroundColor3 = color
	b.Text = ""
	b.AutoButtonColor = true
	corner(b, 10)
	stroke(b, 2, color:Lerp(Color3.new(0, 0, 0), 0.45))
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color)
	gradient.Rotation = 90
	gradient.Parent = b
	text(b, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		TextStrokeTransparency = 1,
		Text = emoji,
	})
	text(b, {
		Position = UDim2.fromOffset(48, 10),
		Size = UDim2.new(1, -54, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = label,
	})
	b.Parent = side
	return b
end
local shopButton = sideButton("SHOP", "🛒", Color3.fromRGB(255, 150, 40))
local rebirthButton = sideButton("REBIRTH", "🔁", Color3.fromRGB(170, 80, 255))
local questsButton = sideButton("QUESTS", "📜", Color3.fromRGB(60, 170, 255))
local followButton = sideButton("FOLLOW", "🐾", Color3.fromRGB(60, 200, 120))

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
	elseif kind == "night" and mutation then
		local nightEvent = Config.FounderEvents[ReplicatedStorage:GetAttribute("FounderEvent") :: string? or ""]
		local nightFounder = if nightEvent then nightEvent.Founder else "the founder"
		showBanner(string.format("NIGHT FALLS! %s mutations are x%s more likely until %s leaves!", string.upper(mutation.DisplayName), extra or "?", nightFounder), mutation.Color)
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
	frame.BackgroundColor3 = PANEL_BG
	frame.Visible = false
	corner(frame, 10)
	stroke(frame, 4, EDGE)
	frame.Parent = gui

	-- Title in the window's color, with a matching line under the header.
	text(frame, {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -80, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = title,
	})
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = color
	line.Position = UDim2.fromOffset(16, 54)
	line.Size = UDim2.new(1, -32, 0, 3)
	line.Parent = frame
	local close = button(frame, "X", UI_GREY, UDim2.fromOffset(44, 44))
	close.Position = UDim2.new(1, -54, 0, 8)
	close.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 66)
	body.Size = UDim2.new(1, -32, 1, -80)
	body.Parent = frame
	return frame, body
end

-- Shop ---------------------------------------------------------------------
-- A dark shop window: SHOP title with your Cash and Diamonds, a row of
-- category tiles, a FEATURED limited brainrot, a game pass shopBanner you can
-- flip through, an ON SALE row of boosts, and a code box along the bottom.
-- (Kept in its own block: a script can only have 200 locals at the top.)
local shopFrame: Frame
local renderLimited: () -> ()
local buyLimitedItem: (string) -> ()
-- Opens another menu (Diamond Shop, Skins); set once those menus exist.
local openMenu: (string) -> () = function() end
do

	local SHOP_BG = Color3.fromRGB(32, 32, 40)
	local SHOP_PANEL = Color3.fromRGB(22, 22, 28)
	local SHOP_TILE = Color3.fromRGB(44, 44, 54)
	local SHOP_PINK = Color3.fromRGB(235, 80, 210)
	local SHOP_CYAN = Color3.fromRGB(70, 200, 255)
	local SHOP_PURPLE = Color3.fromRGB(150, 90, 255)
	local SHOP_GREY = Color3.fromRGB(90, 90, 100)

	local PASS_ICONS: { [string]: string } = { DoubleCash = "💰", VIP = "👑", LongerLock = "⏱️", InfiniteLock = "♾️" }
	local PASS_COLORS: { [string]: Color3 } = {
		DoubleCash = Color3.fromRGB(60, 190, 90),
		VIP = Color3.fromRGB(240, 180, 40),
		LongerLock = Color3.fromRGB(60, 150, 255),
		InfiniteLock = Color3.fromRGB(235, 60, 70),
	}
	local PRODUCT_ICONS: { [string]: string } = { SmallCash = "💵", BigCash = "🏦", ServerLuck = "🍀", InstantLock = "🔒" }


	shopFrame = Instance.new("Frame")
	shopFrame.Name = "Shop"
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.Position = UDim2.fromScale(0.5, 0.5)
	shopFrame.Size = UDim2.fromOffset(760, 560)
	shopFrame.BackgroundColor3 = SHOP_BG
	shopFrame.Visible = false
	corner(shopFrame, 10)
	stroke(shopFrame, 4, Color3.fromRGB(12, 12, 16))
	shopFrame.Parent = gui
	local function box(parent: Instance, position: UDim2, size: UDim2, color: Color3, radius: number?): Frame
		local f = Instance.new("Frame")
		f.Position = position
		f.Size = size
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		if radius then
			corner(f, radius)
		end
		f.Parent = parent
		return f
	end

	local function icon(parent: Instance, emoji: string, position: UDim2, size: UDim2): TextLabel
		return text(parent, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			Text = emoji,
			TextStrokeTransparency = 1,
		})
	end

	-- Fills in a Robux price once Roblox tells us (ids of 0 aren't set up yet).
	local function showPrice(target: any, id: number, infoType: Enum.InfoType)
		if id == 0 then
			target.Text = "SOON"
			return
		end
		target.Text = "R$ ..."
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			if ok and info and info.PriceInRobux and target.Text == "R$ ..." then
				target.Text = "R$ " .. tostring(info.PriceInRobux)
			end
		end)
	end

	-- Header: SHOP, your Cash and Diamonds, close
	text(shopFrame, {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(130, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SHOP",
	})
	local function currencyBar(x: number, color: Color3, symbol: string): TextLabel
		local bar = box(shopFrame, UDim2.fromOffset(x, 14), UDim2.fromOffset(200, 34), color, 8)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color)
		gradient.Rotation = 90
		gradient.Parent = bar
		local badge = box(bar, UDim2.fromOffset(-8, -4), UDim2.fromOffset(42, 42), color:Lerp(Color3.new(0, 0, 0), 0.15), 21)
		stroke(badge, 2, color:Lerp(WHITE, 0.4))
		icon(badge, symbol, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.8))
		return text(bar, {
			Position = UDim2.fromOffset(40, 3),
			Size = UDim2.new(1, -78, 1, -6),
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "0",
		})
	end
	local cashAmount = currencyBar(170, Color3.fromRGB(240, 170, 40), "💵")
	local diamondAmount = currencyBar(400, SHOP_PURPLE, "💎")
	local moreDiamonds = button(shopFrame, "+", SHOP_PURPLE:Lerp(WHITE, 0.2), UDim2.fromOffset(34, 34))
	moreDiamonds.Position = UDim2.fromOffset(570, 14)
	moreDiamonds.MouseButton1Click:Connect(function()
		openMenu("Diamonds")
	end)
	local closeShop = button(shopFrame, "X", SHOP_GREY, UDim2.fromOffset(44, 44))
	closeShop.Position = UDim2.new(1, -56, 0, 9)
	closeShop.MouseButton1Click:Connect(function()
		shopFrame.Visible = false
	end)

	-- Pages under the tiles
	local shopPages: { [string]: Frame } = {}
	local function shopPage(name: string): Frame
		local page = box(shopFrame, UDim2.fromOffset(12, 148), UDim2.new(1, -24, 1, -212), SHOP_BG)
		page.BackgroundTransparency = 1
		page.Visible = false
		shopPages[name] = page
		return page
	end
	local function showShopPage(name: string)
		for pageName, page in shopPages do
			page.Visible = pageName == name
		end
	end

	-- Category tiles
	local tiles = box(shopFrame, UDim2.fromOffset(12, 64), UDim2.new(1, -24, 0, 76), SHOP_BG)
	tiles.BackgroundTransparency = 1
	local tileLayout = Instance.new("UIListLayout")
	tileLayout.FillDirection = Enum.FillDirection.Horizontal
	tileLayout.Padding = UDim.new(0, 8)
	tileLayout.Parent = tiles
	local function tile(label: string, emoji: string, color: Color3, onClick: () -> ())
		local t = Instance.new("TextButton")
		t.Size = UDim2.fromOffset(140, 76)
		t.BackgroundColor3 = color
		t.Text = ""
		t.AutoButtonColor = true
		corner(t, 10)
		stroke(t, 2, color:Lerp(Color3.new(0, 0, 0), 0.4))
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color)
		gradient.Rotation = 90
		gradient.Parent = t
		t.Parent = tiles
		icon(t, emoji, UDim2.fromScale(0.5, 0.36), UDim2.fromOffset(46, 46))
		text(t, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -10, 0, 26),
			Text = label,
		})
		t.MouseButton1Click:Connect(onClick)
	end
	tile("Featured", "⭐", SHOP_PINK, function()
		showShopPage("Home")
	end)
	tile("Passes", "🎟️", Color3.fromRGB(255, 140, 50), function()
		showShopPage("Passes")
	end)
	tile("Boosts", "⚡", Color3.fromRGB(140, 220, 60), function()
		showShopPage("Boosts")
	end)
	tile("Diamonds", "💎", SHOP_PURPLE, function()
		openMenu("Diamonds")
	end)
	tile("Skins", "🧱", Color3.fromRGB(60, 170, 255), function()
		openMenu("Skins")
	end)

	-- Code box along the bottom
	local codeBar = box(shopFrame, UDim2.new(0, 12, 1, -56), UDim2.new(1, -24, 0, 44), SHOP_PANEL, 8)
	text(codeBar, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.fromOffset(330, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		Text = "Have a code? Enter it here!",
	})
	local codeBox = Instance.new("TextBox")
	codeBox.Position = UDim2.new(1, -330, 0, 5)
	codeBox.Size = UDim2.fromOffset(270, 34)
	codeBox.BackgroundColor3 = SHOP_TILE
	codeBox.Font = FONT
	codeBox.PlaceholderText = "Code"
	codeBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
	codeBox.Text = ""
	codeBox.TextColor3 = WHITE
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	corner(codeBox, 6)
	codeBox.Parent = codeBar
	local redeem = button(codeBar, "✔", GREEN, UDim2.fromOffset(44, 34))
	redeem.Position = UDim2.new(1, -50, 0, 5)
	local redeeming = false
	redeem.MouseButton1Click:Connect(function()
		if redeeming or codeBox.Text == "" then
			return
		end
		redeeming = true
		local ok, message = RedeemCode:InvokeServer(codeBox.Text)
		redeeming = false
		toast(message or (if ok then "Code redeemed!" else "That code doesn't work."), if ok then GREEN else RED)
		if ok then
			codeBox.Text = ""
		end
	end)

	-- Item card: icon, price and a name ribbon (used on every page).
	type Card = { Frame: TextButton, Price: TextLabel }
	local function itemCard(parent: Instance, size: UDim2, emoji: string, name: string, ribbon: Color3, onClick: () -> ()): Card
		local card = Instance.new("TextButton")
		card.Size = size
		card.BackgroundColor3 = SHOP_TILE
		card.Text = ""
		card.AutoButtonColor = true
		corner(card, 6)
		stroke(card, 2, Color3.fromRGB(15, 15, 20))
		card.Parent = parent
		icon(card, emoji, UDim2.new(0.5, 0, 0.4, 0), UDim2.fromScale(0.5, 0.45))
		local price = text(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0.62, 0),
			Size = UDim2.new(1, -12, 0.14, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(120, 255, 140),
			Text = "",
		})
		local band = box(card, UDim2.new(0, 3, 1, -27), UDim2.new(1, -6, 0, 24), ribbon, 4)
		text(band, {
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.new(1, -8, 1, -4),
			Text = name,
		})
		card.MouseButton1Click:Connect(onClick)
		return { Frame = card, Price = price }
	end

	local function buyPass(pass: Config.GamePass)
		if pass.Id == 0 or (data and data.Owns[pass.Key]) then
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end
	local function buyProduct(product: Config.Product)
		if product.Id ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product.Id)
		end
	end

	-- Reserves a limited item and opens the Robux prompt (server does the rest).
	local buyingLimited = false
	buyLimitedItem = function(itemId: string)
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

	-- HOME page ----------------------------------------------------------------
	local home = shopPage("Home")

	-- FEATURED: the limited event brainrot, spinning in a little window.
	local featuredId = Config.CurrentEvent
	local featured = Config.GetBrainrot(featuredId)
	local featuredItem = Config.LimitedItems[featuredId]
	local featuredColumn = box(home, UDim2.fromOffset(0, 0), UDim2.new(0, 190, 1, 0), SHOP_PANEL, 8)
	text(featuredColumn, {
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 34),
		TextColor3 = SHOP_PINK,
		Text = "FEATURED",
	})
	local window = Instance.new("ViewportFrame")
	window.AnchorPoint = Vector2.new(0.5, 0)
	window.Position = UDim2.new(0.5, 0, 0, 42)
	window.Size = UDim2.fromOffset(130, 118)
	window.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	window.Ambient = Color3.fromRGB(200, 200, 210)
	window.LightColor = WHITE
	corner(window, 6)
	stroke(window, 2, Color3.fromRGB(60, 60, 70))
	window.Parent = featuredColumn
	local featuredName = text(featuredColumn, {
		Position = UDim2.fromOffset(6, 164),
		Size = UDim2.new(1, -12, 0, 22),
		Text = if featured then featured.DisplayName else "",
	})
	local featuredStock = text(featuredColumn, {
		Position = UDim2.fromOffset(6, 188),
		Size = UDim2.new(1, -12, 0, 18),
		TextColor3 = GOLD,
		Text = "",
	})
	local getNow = button(featuredColumn, "GET NOW", Color3.fromRGB(190, 70, 230), UDim2.new(1, -30, 0, 44))
	getNow.Position = UDim2.fromOffset(15, 212)
	getNow.MouseButton1Click:Connect(function()
		if featuredItem and Config.LimitedOnSale(featuredItem) and not (data and data.Limited and data.Limited[featuredId]) then
			buyLimitedItem(featuredId)
		end
	end)
	local passesButton = button(featuredColumn, "GAME PASSES", SHOP_CYAN, UDim2.new(1, -16, 0, 44))
	passesButton.Position = UDim2.new(0, 8, 1, -52)
	passesButton.MouseButton1Click:Connect(function()
		showShopPage("Passes")
	end)

	local spinning: Model? = nil
	if featured then
		local model = BrainrotModel.Create(featured, nil, CFrame.new(), false, nil, false, 1)
		for _, child in model:GetDescendants() do
			if child:IsA("BillboardGui") or child:IsA("ParticleEmitter") or child:IsA("Script") or child:IsA("LocalScript") then
				child:Destroy()
			end
		end
		model.Parent = window
		local cf, size = model:GetBoundingBox()
		local viewCamera = Instance.new("Camera")
		local distance = math.max(size.X, size.Y, size.Z) * 1.5
		viewCamera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, size.Y * 0.1, distance), cf.Position)
		viewCamera.FieldOfView = 40
		viewCamera.Parent = window
		window.CurrentCamera = viewCamera
		model:PivotTo(CFrame.new(-cf.Position) * model:GetPivot())
		viewCamera.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.1, distance), Vector3.zero)
		spinning = model
	end

	-- Banner: the game passes, one at a time, with arrows (flips every 5s).
	local shopBanner = box(home, UDim2.fromOffset(200, 0), UDim2.new(1, -200, 0, 170), SHOP_PANEL, 8)
	shopBanner.ClipsDescendants = true
	local bannerGradient = Instance.new("UIGradient")
	bannerGradient.Rotation = 20
	bannerGradient.Parent = shopBanner
	local bannerIcon = icon(shopBanner, "", UDim2.new(0.8, 0, 0.5, 0), UDim2.fromOffset(120, 120))
	bannerIcon.Rotation = -8
	local bannerTitle = text(shopBanner, {
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(0.62, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBlack,
		Text = "",
	})
	text(shopBanner, {
		Position = UDim2.fromOffset(18, 58),
		Size = UDim2.new(0.62, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SHOP_PINK,
		Text = "GAME PASS  -  FOREVER",
	})
	local bannerText = text(shopBanner, {
		Position = UDim2.fromOffset(18, 84),
		Size = UDim2.new(0.6, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextScaled = false,
		TextSize = 17,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(225, 225, 235),
		Text = "",
	})
	local bannerBuy = button(shopBanner, "", GREEN, UDim2.fromOffset(130, 38))
	bannerBuy.Position = UDim2.new(0, 18, 1, -46)
	local bannerIndex = 1
	local bannerChanged = os.clock()
	local function showPassBanner(index: number)
		local passes = Config.GamePasses
		bannerIndex = (index - 1) % #passes + 1
		bannerChanged = os.clock()
		local pass = passes[bannerIndex]
		local color = PASS_COLORS[pass.Key] or SHOP_PURPLE
		bannerGradient.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.25), Color3.fromRGB(40, 20, 70))
		bannerIcon.Text = PASS_ICONS[pass.Key] or "🎟️"
		bannerTitle.Text = string.upper(pass.Name)
		bannerText.Text = pass.Description
		if data and data.Owns[pass.Key] then
			bannerBuy.Text = "OWNED"
			bannerBuy.BackgroundColor3 = SHOP_GREY
		else
			bannerBuy.BackgroundColor3 = if pass.Id == 0 then SHOP_GREY else GREEN
			showPrice(bannerBuy, pass.Id, Enum.InfoType.GamePass)
		end
	end
	bannerBuy.MouseButton1Click:Connect(function()
		buyPass(Config.GamePasses[bannerIndex])
	end)
	local function bannerArrow(label: string, step: number, x: number)
		local arrow = button(shopBanner, label, Color3.fromRGB(30, 30, 40), UDim2.fromOffset(32, 32))
		arrow.AnchorPoint = Vector2.new(x, 1)
		arrow.Position = UDim2.new(x, 0, 1, -8)
		arrow.MouseButton1Click:Connect(function()
			showPassBanner(bannerIndex + step)
		end)
	end
	bannerArrow("<", -1, 0.03)
	bannerArrow(">", 1, 0.97)
	showPassBanner(1)

	-- ON SALE: the boosts.
	local saleHeader = box(home, UDim2.fromOffset(200, 178), UDim2.new(1, -200, 0, 24), SHOP_BG)
	saleHeader.BackgroundTransparency = 1
	text(saleHeader, {
		Size = UDim2.fromOffset(120, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GREEN,
		Text = "ON SALE",
	})
	text(saleHeader, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(280, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic),
		TextStrokeTransparency = 1,
		Text = "Boosts for you (and your server)!",
	})
	local saleRow = box(home, UDim2.fromOffset(200, 206), UDim2.new(1, -200, 1, -206), SHOP_PANEL, 8)
	local salePadding = Instance.new("UIPadding")
	salePadding.PaddingLeft = UDim.new(0, 6)
	salePadding.PaddingTop = UDim.new(0, 6)
	salePadding.Parent = saleRow
	local saleLayout = Instance.new("UIListLayout")
	saleLayout.FillDirection = Enum.FillDirection.Horizontal
	saleLayout.Padding = UDim.new(0, 6)
	saleLayout.Parent = saleRow
	for _, product in Config.Products do
		local card = itemCard(saleRow, UDim2.fromOffset(122, 130), PRODUCT_ICONS[product.Key] or "⚡", product.Name, SHOP_PINK, function()
			buyProduct(product)
		end)
		showPrice(card.Price, product.Id, Enum.InfoType.Product)
	end

	-- PASSES page --------------------------------------------------------------
	local passesPage = shopPage("Passes")
	local passGrid = Instance.new("UIGridLayout")
	passGrid.CellSize = UDim2.fromOffset(176, 276)
	passGrid.CellPadding = UDim2.fromOffset(8, 8)
	passGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	passGrid.Parent = passesPage
	local passButtons: { [string]: TextButton } = {}
	for _, pass in Config.GamePasses do
		local color = PASS_COLORS[pass.Key] or SHOP_PURPLE
		local card = box(passesPage, UDim2.new(), UDim2.new(), SHOP_PANEL, 8)
		stroke(card, 2, color)
		local top = box(card, UDim2.fromOffset(6, 6), UDim2.new(1, -12, 0, 96), color, 6)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color:Lerp(Color3.new(0, 0, 0), 0.3))
		gradient.Rotation = 90
		gradient.Parent = top
		icon(top, PASS_ICONS[pass.Key] or "🎟️", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(70, 70))
		text(card, {
			Position = UDim2.fromOffset(8, 108),
			Size = UDim2.new(1, -16, 0, 30),
			Text = pass.Name,
		})
		text(card, {
			Position = UDim2.fromOffset(10, 140),
			Size = UDim2.new(1, -20, 0, 70),
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextStrokeTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(200, 200, 210),
			Text = pass.Description,
		})
		local buy = button(card, "", if pass.Id == 0 then SHOP_GREY else GREEN, UDim2.new(1, -20, 0, 44))
		buy.Position = UDim2.new(0, 10, 1, -54)
		showPrice(buy, pass.Id, Enum.InfoType.GamePass)
		buy.MouseButton1Click:Connect(function()
			buyPass(pass)
		end)
		passButtons[pass.Key] = buy
	end

	-- BOOSTS page --------------------------------------------------------------
	local boostsPage = shopPage("Boosts")
	local boostGrid = Instance.new("UIGridLayout")
	boostGrid.CellSize = UDim2.fromOffset(176, 276)
	boostGrid.CellPadding = UDim2.fromOffset(8, 8)
	boostGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	boostGrid.Parent = boostsPage
	for _, product in Config.Products do
		local card = itemCard(boostsPage, UDim2.new(), PRODUCT_ICONS[product.Key] or "⚡", product.Name, Color3.fromRGB(110, 190, 50), function()
			buyProduct(product)
		end)
		showPrice(card.Price, product.Id, Enum.InfoType.Product)
		text(card.Frame, {
			Position = UDim2.fromOffset(8, 212),
			Size = UDim2.new(1, -16, 0, 34),
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			TextStrokeTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(200, 200, 210),
			Text = product.Description,
		})
	end

	showShopPage("Home")

	-- Spin the featured brainrot and flip the shopBanner while the shop is open.
	local lastStockTick = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if not shopFrame.Visible then
			return
		end
		local model = spinning
		if model then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 0.8, 0))
		end
		if os.clock() - bannerChanged > 5 then
			showPassBanner(bannerIndex + 1)
		end
		-- The stock countdown ticks once a second.
		if os.clock() - lastStockTick >= 1 then
			lastStockTick = os.clock()
			renderLimited()
		end
	end)

	-- Prices, stock and "OWNED" from your latest data.
	renderLimited = function()
		if not data then
			return
		end
		cashAmount.Text = Config.FormatCash(data.Cash)
		diamondAmount.Text = tostring(data.Diamonds or 0)
		for key, b in passButtons do
			if data.Owns[key] then
				b.Text = "OWNED"
				b.BackgroundColor3 = SHOP_GREY
			end
		end
		if featured and featuredItem then
			local published = ReplicatedStorage:GetAttribute("LimitedLeft_" .. featuredId) :: number?
			local left: number = if published then published else featuredItem.Stock
			local nextAt = ReplicatedStorage:GetAttribute("LimitedNextUpdate") :: number?
		featuredStock.Text = string.format("%s  (%s)", if left <= 0 then "SOLD OUT" else string.format("%d / %d LEFT", left, featuredItem.Stock), Config.StockCountdown(nextAt, workspace:GetServerTimeNow()))
			local serial = data.Limited and data.Limited[featuredId]
			if serial then
				getNow.Text = "OWNED #" .. serial
				getNow.BackgroundColor3 = SHOP_GREY
			elseif not Config.LimitedOnSale(featuredItem) then
				getNow.Text = "SOON"
				getNow.BackgroundColor3 = SHOP_GREY
			elseif left <= 0 then
				getNow.Text = "SOLD OUT"
				getNow.BackgroundColor3 = SHOP_GREY
			else
				getNow.Text = "GET NOW  R$ " .. featuredItem.PriceRobux
				getNow.BackgroundColor3 = Color3.fromRGB(190, 70, 230)
			end
		else
			featuredName.Text = ""
		end
	end
	for itemId in Config.LimitedItems do
		ReplicatedStorage:GetAttributeChangedSignal("LimitedLeft_" .. itemId):Connect(renderLimited)
	end
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
	card.BackgroundColor3 = TILE
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
	row.BackgroundColor3 = TILE
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
local skinRows: { [string]: Frame } = {}
for i, skin in Config.WallSkins do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 50)
	row.BackgroundColor3 = if skin.FounderOnly then Color3.fromRGB(25, 32, 55) else TILE
	row.LayoutOrder = 21 + i
	-- Founder-only skins are hidden until we know you're that founder.
	row.Visible = skin.FounderOnly == nil
	corner(row, 10)
	if skin.FounderOnly then
		stroke(row, 2, GOLD)
	end
	row.Parent = questsBody
	skinRows[skin.Id] = row
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
		if skin.FounderOnly then
			skinRows[skin.Id].Visible = data.FounderId == skin.FounderOnly
		end
		if skin.FounderOnly and not owned then
			b.Text = "CLAIM (FREE)"
			b.BackgroundColor3 = GOLD
		elseif data.Skin == skin.Id then
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
			row.BackgroundColor3 = TILE
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
	if skin.Currency == "Diamonds" and not skin.FounderOnly then
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
-- The shop's Diamonds and Skins tiles open those menus.
openMenu = function(name: string)
	if name == "Diamonds" then
		toggleMenu(diamondFrame)
		renderDiamondShop()
	elseif name == "Skins" then
		toggleMenu(questsFrame)
		renderQuests()
	end
end
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
-- One tab per job (Players, Events, Brainrots, and Founder for Corny and
-- Ace), and inside each tab every job gets its own labelled box.
-- (Kept in its own block: a script can only have 200 locals at the top.)
type AdminTab = { Button: TextButton, Page: ScrollingFrame, Color: Color3 }
local adminFrame: Frame
local selectTab: (AdminTab) -> ()
local playersTab: AdminTab
local founderTab: AdminTab
-- Limited brainrots: only Corny sees these rows (the server checks too).
local limitedGiveRows: { Frame } = {}
do

	local ORANGE = Color3.fromRGB(255, 150, 40)
	local PURPLE = Color3.fromRGB(170, 80, 255)
	local GREY = Color3.fromRGB(90, 90, 100)
	local BLUE = Color3.fromRGB(60, 140, 255)
	local PINK = Color3.fromRGB(255, 120, 190)
	local HINT = Color3.fromRGB(170, 170, 185)

	local adminFrameBody
	adminFrame, adminFrameBody = modal("ADMIN PANEL", RED, 640)
	adminFrame.Size = UDim2.fromOffset(640, 640)
	local function inputBox(parent: Instance, default: string, hint: string, width: number): TextBox
		local box = Instance.new("TextBox")
		box.Size = UDim2.fromOffset(width, 38)
		box.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
		box.TextColor3 = WHITE
		box.PlaceholderText = hint
		box.PlaceholderColor3 = Color3.fromRGB(130, 130, 145)
		box.Text = default
		box.Font = FONT
		box.TextScaled = true
		box.ClearTextOnFocus = false
		corner(box, 8)
		stroke(box, 1.5, Color3.fromRGB(90, 90, 110))
		box.Parent = parent
		return box
	end

	local function smallButton(parent: Instance, label: string, color: Color3, width: number, onClick: () -> ()): TextButton
		local b = button(parent, label, color, UDim2.fromOffset(width, 38))
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	-- Who the Players and Brainrots buttons act on. Always at the top.
	local targetBar = Instance.new("Frame")
	targetBar.Size = UDim2.new(1, 0, 0, 44)
	targetBar.BackgroundColor3 = TILE
	corner(targetBar, 10)
	targetBar.Parent = adminFrameBody
	local targetLayout = Instance.new("UIListLayout")
	targetLayout.FillDirection = Enum.FillDirection.Horizontal
	targetLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	targetLayout.Padding = UDim.new(0, 8)
	targetLayout.Parent = targetBar
	local targetPadding = Instance.new("UIPadding")
	targetPadding.PaddingLeft = UDim.new(0, 10)
	targetPadding.Parent = targetBar
	text(targetBar, { Size = UDim2.fromOffset(90, 28), Text = "PLAYER", TextColor3 = GOLD })
	local targetBox = inputBox(targetBar, "me", "me / all / name", 200)
	text(targetBar, {
		Size = UDim2.fromOffset(270, 20),
		TextColor3 = HINT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "me, all, or the start of a name",
	})

	local function send(action: string, value: any)
		AdminAction:FireServer(action, targetBox.Text, value)
	end

	-- Tabs
	local tabBar = Instance.new("Frame")
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(0, 52)
	tabBar.Size = UDim2.new(1, 0, 0, 40)
	tabBar.Parent = adminFrameBody
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local adminTabs: { AdminTab } = {}
	selectTab = function(chosen: AdminTab)
		for _, tab in adminTabs do
			local on = tab == chosen
			tab.Page.Visible = on
			tab.Button.BackgroundColor3 = if on then tab.Color else Color3.fromRGB(55, 55, 70)
		end
	end

	local function adminTab(label: string, color: Color3): (ScrollingFrame, AdminTab)
		local tabButton = button(tabBar, label, color, UDim2.fromOffset(142, 40))
		tabButton.LayoutOrder = #adminTabs + 1
		local page = Instance.new("ScrollingFrame")
		page.BackgroundTransparency = 1
		page.Position = UDim2.fromOffset(0, 100)
		page.Size = UDim2.new(1, 0, 1, -100)
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollBarThickness = 6
		page.Visible = false
		page.Parent = adminFrameBody
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = page
		local tab: AdminTab = { Button = tabButton, Page = page, Color = color }
		table.insert(adminTabs, tab)
		tabButton.MouseButton1Click:Connect(function()
			selectTab(tab)
		end)
		return page, tab
	end

	-- A box with a title, a line saying what it does, and its controls.
	local function section(page: Instance, order: number, title: string, hint: string?, color: Color3): Frame
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -12, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = PANEL_DARK
		card.LayoutOrder = order
		corner(card, 12)
		stroke(card, 2, color)
		card.Parent = page
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = card
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = card
		text(card, {
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Text = title,
			LayoutOrder = 0,
		})
		if hint then
			text(card, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextScaled = false,
				TextSize = 15,
				TextWrapped = true,
				TextStrokeTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = HINT,
				Text = hint,
				LayoutOrder = 1,
			})
		end
		return card
	end

	-- A row of controls inside a box; wraps onto a new line if it runs out of room.
	local function controls(card: Frame, order: number): Frame
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = 10 + order
		row.Parent = card
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Wraps = true
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row
		return row
	end

	local function label(row: Frame, value: string, width: number)
		text(row, { Size = UDim2.fromOffset(width, 30), Text = value, TextXAlignment = Enum.TextXAlignment.Left })
	end

	-- PLAYERS tab ------------------------------------------------------------------
	local playersPage
	playersPage, playersTab = adminTab("PLAYERS", BLUE)

	local money = section(playersPage, 1, "MONEY & CURRENCY", "Type an amount (5000, 25k, 2m), then pick what to give the player.", GREEN)
	local amountRow = controls(money, 1)
	label(amountRow, "Amount", 90)
	local amountBox = inputBox(amountRow, "1m", "e.g. 5000, 25k, 2m", 150)
	local cashRow = controls(money, 2)
	smallButton(cashRow, "Give Cash", GREEN, 130, function()
		send("Cash", amountBox.Text)
	end)
	smallButton(cashRow, "Set Cash", BLUE, 120, function()
		send("SetCash", amountBox.Text)
	end)
	smallButton(cashRow, "Set Rebirths", PURPLE, 150, function()
		send("Rebirths", amountBox.Text)
	end)
	local currencyRow = controls(money, 3)
	smallButton(currencyRow, "Give Shards", SHARD_COLOR, 160, function()
		send("Shards", amountBox.Text)
	end)
	smallButton(currencyRow, "Give Diamonds", DIAMOND_COLOR, 180, function()
		send("Diamonds", amountBox.Text)
	end)

	local function levelButtons(row: Frame, count: number, action: string, color: Color3)
		for level = 1, count do
			smallButton(row, tostring(level), color, 42, function()
				send(action, level)
			end)
		end
	end
	local base = section(playersPage, 2, "BASE", "Set the player's base level and door lock level.", ORANGE)
	local baseRow = controls(base, 1)
	label(baseRow, "Base", 70)
	levelButtons(baseRow, #Config.WallLevels, "Base", ORANGE)
	local lockRow = controls(base, 2)
	label(lockRow, "Lock", 70)
	levelButtons(lockRow, #Config.LockLevels, "LockLevel", RED)
	local doorRow = controls(base, 3)
	label(doorRow, "Infinite Door", 160)
	smallButton(doorRow, "ON", Color3.fromRGB(255, 80, 80), 90, function()
		send("InfiniteLock", true)
	end)
	smallButton(doorRow, "OFF", GREY, 90, function()
		send("InfiniteLock", false)
	end)
	local clearRow = controls(base, 4)
	smallButton(clearRow, "Clear Base", RED, 150, function()
		send("ClearBase", nil)
	end)

	-- Everything in the Robux shop, free: gamepasses last until they leave.
	local shopItems = section(playersPage, 3, "SHOP ITEMS (FREE)", "Give the player anything from the shop. Gamepasses last until they leave the game.", Color3.fromRGB(255, 150, 40))
	local passRow = controls(shopItems, 1)
	label(passRow, "Passes", 90)
	for _, pass in Config.GamePasses do
		smallButton(passRow, pass.Name, PURPLE, 170, function()
			send("GivePass", pass.Key)
		end)
	end
	local productRow = controls(shopItems, 2)
	label(productRow, "Items", 90)
	for _, product in Config.Products do
		smallButton(productRow, product.Name, GREEN, 170, function()
			send("GiveProduct", product.Key)
		end)
	end

	-- EVENTS tab -------------------------------------------------------------------
	local eventsPage = adminTab("EVENTS", RED)

	local abuse = section(eventsPage, 1, "ADMIN ABUSE", "Boosts for everyone, plus the giants and gift drops. Set how many minutes it lasts.", RED)
	local abuseRow = controls(abuse, 1)
	label(abuseRow, "Minutes", 100)
	local minutesBox = inputBox(abuseRow, tostring(Config.AdminAbuse.DurationMinutes), "how long", 80)
	smallButton(abuseRow, "START", RED, 130, function()
		send("AbuseStart", minutesBox.Text)
	end)
	smallButton(abuseRow, "END", GREY, 100, function()
		send("AbuseStop", nil)
	end)

	local drops = section(eventsPage, 2, "DROPS", "Rain brainrots or cash bags all over the map.", PURPLE)
	local brainrotRainRow = controls(drops, 1)
	smallButton(brainrotRainRow, "Brainrot Rain x" .. Config.BrainrotRainCount, PURPLE, 240, function()
		send("BrainrotRain", nil)
	end)
	local cashRainRow = controls(drops, 2)
	label(cashRainRow, "Cash per bag", 150)
	local cashRainBox = inputBox(cashRainRow, "100k", "e.g. 50k", 120)
	smallButton(cashRainRow, "Cash Rain", GREEN, 140, function()
		send("CashRain", cashRainBox.Text)
	end)

	local luck = section(eventsPage, 3, "SERVER LUCK", "More rare brainrots spawn for everyone in this server.", Color3.fromRGB(60, 180, 120))
	local luckRow = controls(luck, 1)
	smallButton(luckRow, "Luck 15 min", Color3.fromRGB(60, 180, 120), 160, function()
		send("Luck", 15)
	end)
	smallButton(luckRow, "Stop Luck", GREY, 140, function()
		send("Luck", 0)
	end)

	-- Message to every server (same as typing /announce in chat).
	local announce = section(eventsPage, 4, "ANNOUNCE TO ALL SERVERS", "Shows on everyone's screen in every server. Same as typing /announce in chat.", ORANGE)
	local announceBox = inputBox(controls(announce, 1), "", "Type your message here...", 560)
	announceBox.Size = UDim2.new(1, 0, 0, 44)
	announceBox.TextScaled = false
	announceBox.TextSize = 20
	announceBox.TextXAlignment = Enum.TextXAlignment.Left
	local announceRow = controls(announce, 2)
	smallButton(announceRow, "SEND TO ALL", ORANGE, 180, function()
		send("GlobalAnnounce", announceBox.Text)
		announceBox.Text = ""
	end)

	-- BRAINROTS tab ----------------------------------------------------------------
	local brainrotsPage = adminTab("BRAINROTS", PURPLE)

	-- Mutation picker for Give / Spawn / Drop below.
	local mutationChoices = { "None" }
	for _, mutation in Config.Mutations do
		if not mutation.Exclusive then
			table.insert(mutationChoices, mutation.Id)
		end
	end
	local mutationIndex = 1
	local mutationCard = section(brainrotsPage, 1, "MUTATION", "Tap to cycle the mutation used by Give, Spawn and Drop below.", PURPLE)
	local mutationRow = controls(mutationCard, 1)
	local mutationButton = smallButton(mutationRow, "None", GREY, 180, function() end)
	smallButton(mutationRow, "Give MAGIC (event)", Color3.fromRGB(170, 110, 255), 230, function()
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

	local listCard = section(brainrotsPage, 2, "ALL BRAINROTS", "Give = into their base.  Spawn = on the conveyor.  Drop = falls near them.", GOLD)
	-- Limited brainrots: only Corny sees these rows (the server checks too).
	for i, brainrot in Config.Brainrots do
		-- Limited ones are gifted from the box in Corny's FOUNDER tab.
		if brainrot.Limited then
			continue
		end
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = TILE
		row.LayoutOrder = 100 + i
		corner(row, 8)
		row.Parent = listCard
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

	-- FOUNDER tab (only Corny and Ace see it) --------------------------------------
	local founderPage
	founderPage, founderTab = adminTab("FOUNDER", PINK)
	founderTab.Button.Visible = false

	local founderEvents = section(founderPage, 1, "MY FOUNDER EVENT", "Only Corny and Ace can start these. Runs for the minutes you type here.", PINK)
	local founderMinutesRow = controls(founderEvents, 1)
	label(founderMinutesRow, "Minutes", 100)
	local founderMinutesBox = inputBox(founderMinutesRow, "5", "how long", 80)
	local founderEventIds = {}
	for eventId in Config.FounderEvents do
		table.insert(founderEventIds, eventId)
	end
	table.sort(founderEventIds)
	local founderEventRow = controls(founderEvents, 2)
	for _, eventId in founderEventIds do
		smallButton(founderEventRow, "START " .. string.upper(eventId) .. " EVENT", PINK, 220, function()
			send("FounderEvent", { Id = eventId, Minutes = founderMinutesBox.Text })
		end)
	end
	local founderStopRow = controls(founderEvents, 3)
	smallButton(founderStopRow, "END FOUNDER EVENT", GREY, 230, function()
		send("FounderEventStop", nil)
	end)

	-- Gift box for the limited brainrot (Corny only; the server checks too).
	local giftItemId = Config.CurrentEvent
	local giftBrainrot = Config.GetBrainrot(giftItemId)
	local giftItem = Config.LimitedItems[giftItemId]
	if giftBrainrot and giftItem then
		local gift = section(founderPage, 0, "GIFT " .. string.upper(giftBrainrot.DisplayName), "Type anyone's Roblox username. It works even if they're not in this server: they get her as soon as they join. Each gift takes one from the stock.", Config.Rarities[giftBrainrot.Rarity].Color)
		gift.Visible = false
		table.insert(limitedGiveRows, gift)
		local stockLabel = text(gift, {
			Size = UDim2.new(1, 0, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = GOLD,
			Text = "",
			LayoutOrder = 5,
		})
		local function showLeft()
			local left = ReplicatedStorage:GetAttribute("LimitedLeft_" .. giftItemId) :: number?
			local nextAt = ReplicatedStorage:GetAttribute("LimitedNextUpdate") :: number?
			stockLabel.Text = string.format("%d / %d LEFT   (stock updates in %s)", left or giftItem.Stock, giftItem.Stock, Config.StockCountdown(nextAt, workspace:GetServerTimeNow()))
		end
		task.spawn(function()
			while true do
				if gift.Visible then
					showLeft()
				end
				task.wait(1)
			end
		end)
		showLeft()
		local giftRow = controls(gift, 1)
		local giftName = inputBox(giftRow, "", "Roblox username", 280)
		smallButton(giftRow, "GIFT", Color3.fromRGB(190, 70, 230), 140, function()
			AdminAction:FireServer("GiftLimited", "", { Name = giftName.Text, ItemId = giftItemId })
			giftName.Text = ""
		end)
	end

	local music = section(founderPage, 3, "MY EVENT MUSIC", "Upload a song on create.roblox.com (Audio), then paste its ID here. It plays in your event in every server. Leave it empty and press SET to go back to the default.", Color3.fromRGB(70, 255, 120))
	local musicRow = controls(music, 1)
	local musicBox = inputBox(musicRow, "", "Paste sound ID", 260)
	smallButton(musicRow, "SET", Color3.fromRGB(60, 180, 120), 120, function()
		send("SetEventMusic", musicBox.Text)
		musicBox.Text = ""
	end)

	local look = section(founderPage, 2, "MY EVENT GIANT'S LOOK", "Pick what your giant wears in your event. It saves for good, in every server.", GOLD)
	local saveLookRow = controls(look, 1)
	smallButton(saveLookRow, "USE WHAT I'M WEARING NOW", GOLD, 330, function()
		send("SaveEventLook", nil)
	end)
	local outfitHint = text(look, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = HINT,
		Text = "Or paste a costume (outfit) ID: the number in the link of a saved costume.",
		LayoutOrder = 15,
	})
	outfitHint.Name = "OutfitHint"
	local outfitRow = controls(look, 6)
	local outfitBox = inputBox(outfitRow, "", "Paste outfit ID", 260)
	smallButton(outfitRow, "USE OUTFIT", BLUE, 160, function()
		send("SaveEventOutfit", outfitBox.Text)
	end)
	local resetLookRow = controls(look, 7)
	smallButton(resetLookRow, "RESET TO MY NORMAL AVATAR", GREY, 330, function()
		send("ResetEventLook", nil)
	end)

	selectTab(playersTab)
end

local adminButton = sideButton("ADMIN", "🛠️", RED)
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
	founderTab.Button.Visible = data.IsFounder == true
	for _, row in limitedGiveRows do
		row.Visible = data.FounderId == Config.LimitedGiver
	end
	if founderTab.Page.Visible and not data.IsFounder then
		selectTab(playersTab)
	end
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
	currencyLabel.Text = string.format("🔷 %d Shards     💎 %d Diamonds", data.Shards or 0, data.Diamonds or 0)
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
badgeHolder.Position = UDim2.new(1, -12, 1, -58) -- above the music button
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
		-- Note: shown instead of a countdown (e.g. "UNTIL CORNY LEAVES").
		type Active = { Id: string, Name: string, Color: Color3, Left: number?, Note: string? }
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
		-- Tonight's night mutation (Corny's event)
		local nightMutation = Config.GetMutation(ReplicatedStorage:GetAttribute("NightMutation") :: string?)
		local nightBoost = ReplicatedStorage:GetAttribute("NightBoost") :: number?
		if nightMutation and nightBoost and nightBoost > 0 and founderEnds and founderEnds > now then
			table.insert(active, { Id = "NightMutation", Name = string.format("NIGHT: x%d %s", nightBoost, string.upper(nightMutation.DisplayName)), Color = nightMutation.Color, Note = if founderEvent then "UNTIL " .. string.upper(founderEvent.Founder) .. " LEAVES" else "TONIGHT" })
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
			b.Time.Text = if info.Note then info.Note else timeLeft(info.Left)
			b.Frame.Size = UDim2.fromOffset(if info.Note then 330 else 220, 34)
			b.Time.Size = UDim2.new(0, if info.Note then 150 else 64, 1, 0)
			b.Name.Size = UDim2.new(1, if info.Note then -170 else -80, 1, 0)
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

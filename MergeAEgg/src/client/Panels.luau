-- Merge A Egg: every menu, styled after the reference screenshots.
-- Shop, Index, Sell, Trail Shop, Treadmill Shop, Growing Eggs, Active Pets,
-- Free Gift, Daily, Playtime, Rebirth, popups, gift picker and the hatch reveal.
-- Everything is laid out in 1280x720 design pixels and scaled for phones/tablets.

local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Models = require(Shared:WaitForChild("Models"))

local player = Players.LocalPlayer

local Panels = {}

local env -- { gui, state, request, sound, notify, serverNow }
local windows: { [string]: any } = {}
local openCenter: string? = nil
local openSide: string? = nil

local c = Color3.fromRGB
local WHITE = c(255, 255, 255)
local DARK = c(38, 40, 50)
local DARKER = c(28, 30, 38)
local GREEN = c(90, 220, 60)
local RED = c(225, 45, 45)
local BLUE = c(40, 170, 240)
local YELLOW = c(255, 215, 60)
local PURPLE = c(170, 70, 230)
local ROBUX = utf8.char(0xE002)

---------------------------------------------------------------------------
-- UI kit
---------------------------------------------------------------------------

local UI = {}
Panels.UI = UI

function UI.new(className: string, props, parent: Instance?)
	local instance = Instance.new(className)
	for key, value in props or {} do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UI.corner(parent: Instance, radius: number?)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

function UI.stroke(parent: Instance, thickness: number?, color: Color3?, contextual: boolean?)
	return UI.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or c(15, 15, 20),
		ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UI.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	return UI.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 }, parent)
end

function UI.padding(parent: Instance, px: number)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	}, parent)
end

function UI.text(parent: Instance, props)
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = WHITE,
		TextScaled = true,
		RichText = true,
		Size = UDim2.fromScale(1, 1),
	}, parent)
	for key, value in props do
		if key ~= "strokeThickness" then
			label[key] = value
		end
	end
	UI.new("UIStroke", { Thickness = props.strokeThickness or 2.5, Color = c(15, 15, 20) }, label)
	return label
end

-- A chunky game button. props: text, color, size, position, anchor, textColor
function UI.button(parent: Instance, props)
	local color = props.color or GREEN
	local button = UI.new("TextButton", {
		Name = props.name or "Button",
		Size = props.size or UDim2.fromOffset(160, 50),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.order or 0,
	}, parent)
	UI.corner(button, props.radius or 8)
	UI.stroke(button, 3, color:Lerp(Color3.new(), 0.55))
	UI.gradient(button, color:Lerp(WHITE, 0.25), color:Lerp(Color3.new(), 0.1))
	local label = UI.text(button, {
		Name = "Label",
		Text = props.text or "",
		TextColor3 = props.textColor or WHITE,
		Size = UDim2.new(1, -12, 1, -10),
		Position = UDim2.fromOffset(6, 5),
	})
	local scale = UI.new("UIScale", {}, button)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	if props.onClick then
		button.Activated:Connect(function()
			env.sound("Click")
			props.onClick()
		end)
	end
	return button, label
end

function UI.setButton(button: TextButton, text: string, color: Color3)
	local label = button:FindFirstChild("Label") :: TextLabel
	label.Text = text
	button.BackgroundColor3 = color
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color:Lerp(Color3.new(), 0.55)
	end
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.25), color:Lerp(Color3.new(), 0.1))
	end
end

function UI.scroll(parent: Instance, props)
	local frame = UI.new("ScrollingFrame", {
		Name = props.name or "Scroll",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = c(120, 125, 140),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = props.horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
		ScrollingDirection = props.horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
	}, parent)
	if props.grid then
		UI.new("UIGridLayout", {
			CellSize = props.grid,
			CellPadding = props.gap or UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, frame)
	else
		UI.new("UIListLayout", {
			Padding = UDim.new(0, props.gapPx or 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = props.horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, frame)
	end
	UI.padding(frame, props.padding or 8)
	return frame
end

local modelCache = {}

-- Shows a model in a ViewportFrame, auto-framed.
function UI.viewport(parent: Instance, model: Model, props)
	props = props or {}
	local viewport = UI.new("ViewportFrame", {
		Name = "Viewport",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundTransparency = 1,
		Ambient = c(200, 200, 210),
		LightColor = c(255, 250, 240),
		LightDirection = Vector3.new(-1, -2, -1.5),
		ImageColor3 = props.silhouette and Color3.new() or WHITE,
	}, parent)
	local clone = model:Clone()
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport
	local cf, size = clone:GetBoundingBox()
	local radius = size.Magnitude / 2
	local camera = UI.new("Camera", { FieldOfView = 40 }, viewport)
	local angle = props.angle or math.rad(-30)
	local distance = radius / math.tan(math.rad(20)) * (props.zoom or 1.05)
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(math.sin(angle) * distance, radius * 0.35, -math.cos(angle) * distance), cf.Position)
	viewport.CurrentCamera = camera
	return viewport
end

function UI.petModel(name: string): Model
	local key = "pet:" .. name
	if not modelCache[key] then
		modelCache[key] = Models.pet(Config.PetsByName[name])
	end
	return modelCache[key]
end

function UI.eggModel(egg): Model
	local key = `egg:{egg.biome}:{egg.rarity}:{egg.variant or ""}:{egg.boss and 1 or 0}`
	if not modelCache[key] then
		modelCache[key] = Models.egg(egg.biome, egg.rarity, { variant = if egg.boss then "boss" else egg.variant })
	end
	return modelCache[key]
end

function UI.cachedModel(key: string, build: () -> Model): Model
	if not modelCache[key] then
		modelCache[key] = build()
	end
	return modelCache[key]
end

local function eggName(egg): string
	local rarity = Config.Rarities[egg.rarity]
	local biome = Config.Biomes[Config.BiomeIndex[egg.biome]]
	local name = if egg.boss then "Boss Egg" elseif egg.variant == "clown" then "Clown Egg" elseif egg.variant == "pumpkin" then "Pumpkin Egg" else biome.name .. " Egg"
	return `{if egg.big then "BIG " else ""}{rarity.name} {name}`
end
Panels.eggName = eggName

local function rarityHex(rarity: number): string
	return "#" .. Config.Rarities[rarity].color:ToHex()
end

-- Chance of each pet from an egg (base luck), for odds displays.
function Panels.oddsFor(biomeKey: string, eggRarity: number)
	local biome = Config.Biomes[Config.BiomeIndex[biomeKey]]
	local byRarity = {}
	for _, p in biome.pets do
		if not (biome.bossOnly and biome.bossOnly[p.name]) then
			byRarity[p.rarityIndex] = byRarity[p.rarityIndex] or {}
			table.insert(byRarity[p.rarityIndex], p)
		end
	end
	local chances = {}
	for offset, chance in Config.HatchTierChances do
		local rarity = math.min(eggRarity + offset - 1, #Config.Rarities)
		while rarity > 1 and not byRarity[rarity] do
			rarity -= 1
		end
		local list = byRarity[rarity]
		if list then
			for _, p in list do
				chances[p] = (chances[p] or 0) + chance / #list
			end
		end
	end
	local result = {}
	for p, chance in chances do
		table.insert(result, { pet = p, chance = chance })
	end
	table.sort(result, function(a, b)
		return a.chance > b.chance
	end)
	return result
end

local function formatPercent(chance: number): string
	local percent = chance * 100
	if percent >= 10 then
		return string.format("%d%%", math.floor(percent + 0.5))
	end
	return (string.format("%.1f", percent):gsub("%.0$", "")) .. "%"
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

-- A centred window with a coloured header bar, title and red X.
local function window(name: string, title: string, headerColor: Color3, size: Vector2)
	local frame = UI.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 5,
	}, env.gui)
	UI.corner(frame, 10)
	UI.stroke(frame, 4, c(20, 20, 26))
	UI.gradient(frame, c(48, 50, 62), DARKER)
	local header = UI.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = headerColor,
	}, frame)
	UI.corner(header, 10)
	UI.gradient(header, headerColor:Lerp(WHITE, 0.2), headerColor:Lerp(Color3.new(), 0.08), 20)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = headerColor:Lerp(Color3.new(), 0.08), BorderSizePixel = 0 }, header)
	UI.text(header, { Name = "Title", Text = title, Size = UDim2.new(1, -110, 0, 46), Position = UDim2.fromOffset(18, 9), TextXAlignment = Enum.TextXAlignment.Left, strokeThickness = 3 })
	UI.button(header, {
		name = "Close",
		text = "X",
		color = RED,
		size = UDim2.fromOffset(52, 52),
		position = UDim2.new(1, -8, 0, 6),
		anchor = Vector2.new(1, 0),
		onClick = function()
			Panels.close(name)
		end,
	})
	local body = UI.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -24, 1, -82),
		Position = UDim2.fromOffset(12, 72),
		BackgroundTransparency = 1,
	}, frame)
	local scale = UI.new("UIScale", {}, frame)
	windows[name] = { frame = frame, body = body, kind = "center", scale = scale }
	return windows[name]
end

-- A side panel that slides in from the right with a red ">" tab.
local function sidePanel(name: string, title: string, size: Vector2)
	local frame = UI.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.new(1, -100, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 4,
	}, env.gui)
	UI.corner(frame, 8)
	UI.stroke(frame, 4, c(20, 20, 26))
	UI.gradient(frame, c(48, 50, 62), DARKER)
	local header = UI.new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = c(210, 175, 120) }, frame)
	UI.corner(header, 8)
	UI.gradient(header, c(240, 210, 160), c(195, 155, 100))
	UI.text(header, { Name = "Title", Text = title, Size = UDim2.new(0.6, -10, 0, 40), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, strokeThickness = 3 })
	UI.button(frame, {
		name = "Tab",
		text = ">",
		color = RED,
		size = UDim2.fromOffset(48, 50),
		position = UDim2.new(0, -62, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		onClick = function()
			Panels.close(name)
		end,
	})
	local body = UI.new("Frame", { Name = "Body", Size = UDim2.new(1, -16, 1, -68), Position = UDim2.fromOffset(8, 62), BackgroundTransparency = 1 }, frame)
	local scale = UI.new("UIScale", {}, frame)
	windows[name] = { frame = frame, body = body, header = header, kind = "side", scale = scale }
	return windows[name]
end

local function section(parent: Instance, text: string, color: Color3, order: number)
	local label = UI.text(parent, { Text = `-- {text} --`, TextColor3 = color, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, strokeThickness = 3 })
	return label
end

function Panels.isOpen(name: string): boolean
	local w = windows[name]
	return w ~= nil and w.frame.Visible
end

function Panels.open(name: string, arg)
	local w = windows[name]
	if not w then
		return
	end
	if w.kind == "center" then
		if openCenter and openCenter ~= name then
			windows[openCenter].frame.Visible = false
		end
		openCenter = name
		w.frame.Visible = true
		w.frame.Position = UDim2.fromScale(0.5, 0.56)
		TweenService:Create(w.frame, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.52) }):Play()
	else
		if openSide and openSide ~= name then
			windows[openSide].frame.Visible = false
		end
		openSide = name
		w.frame.Visible = true
		w.frame.Position = UDim2.new(1, 300, 0.5, 0)
		TweenService:Create(w.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.new(1, -100, 0.5, 0) }):Play()
	end
	if w.onOpen then
		w.onOpen(arg)
	end
	if w.refresh then
		w.refresh()
	end
end

function Panels.close(name: string)
	local w = windows[name]
	if w then
		w.frame.Visible = false
		if openCenter == name then
			openCenter = nil
		end
		if openSide == name then
			openSide = nil
		end
	end
end

function Panels.toggle(name: string, arg)
	if Panels.isOpen(name) then
		Panels.close(name)
	else
		Panels.open(name, arg)
	end
end

function Panels.setScale(scale: number)
	for _, w in windows do
		w.scale.Scale = scale
	end
end

-- Re-renders any open window that cares about these state keys.
function Panels.refresh(keys: { [string]: boolean })
	for _, w in windows do
		if w.frame.Visible and w.refresh then
			local relevant = w.keys == nil
			if w.keys then
				for _, key in w.keys do
					if keys[key] then
						relevant = true
						break
					end
				end
			end
			if relevant then
				w.refresh()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Robux purchases (with gifting)
---------------------------------------------------------------------------

local giftPicker

local function promptProduct(productId: number, giftTo: number?)
	if productId == 0 then
		env.notify("This item isn't set up yet! (Add its ID in Config)", "error")
		return
	end
	env.request("SetGiftTarget", giftTo)
	MarketplaceService:PromptProductPurchase(player, productId)
end

local function buyProduct(key: string)
	promptProduct(Config.Products[key].id, nil)
end

local function giftProduct(key: string)
	giftPicker(function(userId)
		promptProduct(Config.Products[key].id, userId)
	end)
end

local function buyPass(key: string)
	local pass = Config.GamePasses[key]
	if pass.id == 0 then
		env.notify("This pass isn't set up yet! (Add its ID in Config)", "error")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.id)
end

local function giftPass(key: string)
	local pass = Config.GamePasses[key]
	giftPicker(function(userId)
		promptProduct(pass.giftProduct, userId)
	end)
end

local function giftButton(parent: Instance, onClick: () -> (), size: number?)
	local button = UI.button(parent, {
		name = "Gift",
		text = "🎁",
		color = c(200, 70, 230),
		size = UDim2.fromOffset(size or 56, size or 50),
		onClick = onClick,
	})
	return button
end

local function priceRow(parent: Instance, price: number, onBuy: () -> (), onGift: (() -> ())?, order: number?)
	local row = UI.new("Frame", { Name = "PriceRow", Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = order or 10 }, parent)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	if onGift then
		local g = giftButton(row, onGift)
		g.LayoutOrder = 1
	end
	local buy = UI.button(row, { text = `{ROBUX} {Config.formatWithCommas(price)}`, color = GREEN, size = UDim2.new(1, if onGift then -64 else 0, 1, 0), onClick = onBuy })
	buy.LayoutOrder = 2
	return row, buy
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------

local function buildShop()
	local w = window("Shop", "Shop", c(80, 210, 60), Vector2.new(780, 500))
	w.keys = { "passes" }
	local list = UI.scroll(w.body, { gapPx = 12 })
	w.sections = {}

	-- FEATURED
	w.sections.Featured = section(list, "FEATURED", YELLOW, 1)
	local featured = Config.FeaturedEgg
	local card = UI.new("Frame", { Name = "FeaturedCard", Size = UDim2.new(1, -10, 0, 330), BackgroundColor3 = c(200, 70, 20), LayoutOrder = 2 }, list)
	UI.corner(card, 10)
	UI.stroke(card, 4, c(255, 170, 40))
	UI.gradient(card, c(255, 120, 30), c(120, 20, 60), 30)
	local tag = UI.new("Frame", { Size = UDim2.fromOffset(120, 42), Position = UDim2.fromOffset(14, 12), BackgroundColor3 = RED }, card)
	UI.corner(tag, 6)
	UI.stroke(tag, 3)
	UI.text(tag, { Text = "New!" })
	UI.text(card, { Text = featured.name:upper(), TextColor3 = YELLOW, Size = UDim2.fromOffset(380, 50), Position = UDim2.fromOffset(145, 8), TextXAlignment = Enum.TextXAlignment.Left, strokeThickness = 3 })
	UI.text(card, { Text = "Limited Time!", Size = UDim2.fromOffset(200, 30), Position = UDim2.fromOffset(150, 56), TextXAlignment = Enum.TextXAlignment.Left })
	w.countdown = UI.text(card, { Text = "", Size = UDim2.fromOffset(230, 44), Position = UDim2.new(1, -14, 0, 10), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right })

	local oddsRow = UI.new("Frame", { Size = UDim2.new(1, -28, 0, 130), Position = UDim2.fromOffset(14, 96), BackgroundTransparency = 1 }, card)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }, oddsRow)
	for i, entry in Panels.oddsFor(featured.biome, featured.rarity) do
		local cell = UI.new("Frame", { Size = UDim2.fromOffset(110, 125), BackgroundColor3 = c(40, 20, 30), BackgroundTransparency = 0.3, LayoutOrder = i }, oddsRow)
		UI.corner(cell, 6)
		UI.stroke(cell, 3, Config.Rarities[entry.pet.rarityIndex].color)
		UI.viewport(cell, UI.petModel(entry.pet.name), { size = UDim2.new(1, -6, 1, -30), position = UDim2.fromOffset(3, 3) })
		UI.text(cell, { Text = formatPercent(entry.chance), Size = UDim2.new(1, -8, 0, 28), Position = UDim2.new(0, 4, 1, -30), TextXAlignment = Enum.TextXAlignment.Right })
	end

	local buyRow = UI.new("Frame", { Size = UDim2.new(1, -28, 0, 80), Position = UDim2.new(0, 14, 1, -94), BackgroundTransparency = 1 }, card)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }, buyRow)
	for i, key in { "FeaturedEgg50", "FeaturedEgg10", "FeaturedEgg3", "FeaturedEgg1" } do
		local product = Config.Products[key]
		local holder = UI.new("Frame", { Size = UDim2.fromOffset(170, 80), BackgroundTransparency = 1, LayoutOrder = i }, buyRow)
		local row = priceRow(holder, product.price, function()
			buyProduct(key)
		end, function()
			giftProduct(key)
		end)
		row.Size = UDim2.new(1, 0, 0, 50)
		UI.text(holder, { Text = `{product.amount} Egg{product.amount > 1 and "s" or ""}`, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 52) })
	end

	-- PASSES
	w.sections.Passes = section(list, "PASSES", YELLOW, 10)
	local passGrid = UI.new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 11 }, list)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(360, 180), CellPadding = UDim2.fromOffset(12, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, passGrid)
	local passStyles = {
		Growth = { icon = "⏱️", a = c(255, 140, 200), b = c(120, 200, 255) },
		Money = { icon = "💰", a = c(255, 230, 90), b = c(240, 170, 30) },
		Speed = { icon = "👟", a = c(120, 220, 255), b = c(40, 120, 230) },
		VIP = { icon = "⭐", a = c(255, 210, 60), b = c(200, 90, 255) },
		AutoHatch = { icon = "🥚", a = c(140, 255, 140), b = c(40, 170, 90) },
	}
	w.passButtons = {}
	for i, key in { "Growth", "Money", "Speed", "VIP", "AutoHatch" } do
		local pass = Config.GamePasses[key]
		local style = passStyles[key]
		local cardFrame = UI.new("Frame", { Name = key, BackgroundColor3 = style.a, LayoutOrder = i }, passGrid)
		UI.corner(cardFrame, 8)
		UI.stroke(cardFrame, 3)
		UI.gradient(cardFrame, style.a, style.b, 30)
		UI.text(cardFrame, { Text = style.icon, Size = UDim2.fromOffset(100, 100), Position = UDim2.fromOffset(10, 10) })
		UI.text(cardFrame, { Text = pass.name, Size = UDim2.new(1, -120, 0, 38), Position = UDim2.fromOffset(112, 8), TextXAlignment = Enum.TextXAlignment.Left })
		UI.text(cardFrame, { Text = pass.desc, Size = UDim2.new(1, -124, 0, 64), Position = UDim2.fromOffset(112, 48), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
		local holder = UI.new("Frame", { Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 1, -60), BackgroundTransparency = 1 }, cardFrame)
		local _, buy = priceRow(holder, pass.price, function()
			buyPass(key)
		end, function()
			giftPass(key)
		end)
		w.passButtons[key] = buy
	end

	-- SPEED
	w.sections.Speed = section(list, "SPEED", c(90, 210, 255), 20)
	local speedGrid = UI.new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 21 }, list)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(235, 170), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, speedGrid)
	local speedIcons = { "👟", "👟👟", "👟👟👟", "🥿👟👟", "🎒", "🧰" }
	for i, key in { "Speed150K", "Speed1M", "Speed10M", "Speed50M", "Speed500M", "Speed1B" } do
		local product = Config.Products[key]
		local cardFrame = UI.new("Frame", { BackgroundColor3 = c(60, 180, 245), LayoutOrder = i }, speedGrid)
		UI.corner(cardFrame, 8)
		UI.stroke(cardFrame, 3)
		UI.gradient(cardFrame, c(120, 220, 255), c(40, 140, 230))
		UI.text(cardFrame, { Text = speedIcons[i], Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 8) })
		UI.text(cardFrame, { Text = `<font color="#7dff6b">+{Config.format(product.amount)}</font> SPEED`, Size = UDim2.new(1, -10, 0, 34), Position = UDim2.fromOffset(5, 70) })
		local holder = UI.new("Frame", { Size = UDim2.new(1, -16, 0, 50), Position = UDim2.new(0, 8, 1, -58), BackgroundTransparency = 1 }, cardFrame)
		priceRow(holder, product.price, function()
			buyProduct(key)
		end, function()
			giftProduct(key)
		end)
	end

	-- MONEY
	w.sections.Money = section(list, "MONEY", c(120, 255, 90), 30)
	local moneyGrid = UI.new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 31 }, list)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(235, 170), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, moneyGrid)
	local moneyIcons = { "💵", "💵💵", "💰", "💰💰", "🏦" }
	for i, key in { "Money25K", "Money200K", "Money800K", "Money4M", "Money8M" } do
		local product = Config.Products[key]
		local cardFrame = UI.new("Frame", { BackgroundColor3 = c(70, 190, 60), LayoutOrder = i }, moneyGrid)
		UI.corner(cardFrame, 8)
		UI.stroke(cardFrame, 3)
		UI.gradient(cardFrame, c(120, 230, 90), c(40, 150, 40))
		UI.text(cardFrame, { Text = moneyIcons[i], Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 8) })
		UI.text(cardFrame, { Text = `${Config.format(product.amount)}`, Size = UDim2.new(1, -10, 0, 34), Position = UDim2.fromOffset(5, 70) })
		local holder = UI.new("Frame", { Size = UDim2.new(1, -16, 0, 50), Position = UDim2.new(0, 8, 1, -58), BackgroundTransparency = 1 }, cardFrame)
		priceRow(holder, product.price, function()
			buyProduct(key)
		end, function()
			giftProduct(key)
		end)
	end

	w.onOpen = function(sectionName)
		local target = sectionName and w.sections[sectionName]
		task.defer(function()
			if target then
				list.CanvasPosition = Vector2.new(0, math.max(0, target.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y - 8))
			else
				list.CanvasPosition = Vector2.zero
			end
		end)
	end
	w.refresh = function()
		local passes = env.state.passes or {}
		for key, button in w.passButtons do
			if passes[key] then
				UI.setButton(button, "OWNED", c(120, 120, 130))
			else
				UI.setButton(button, `{ROBUX} {Config.formatWithCommas(Config.GamePasses[key].price)}`, GREEN)
			end
		end
	end
	w.tick = function()
		local left = Config.FeaturedEgg.endsAt - env.serverNow()
		w.countdown.Text = if left > 0 then Config.formatTime(left) else "Ending soon!"
	end
end

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------

local function buildIndex()
	local w = window("Index", "Index", c(40, 170, 240), Vector2.new(780, 500))
	w.keys = { "index" }
	w.biome = 1
	local tabs = UI.scroll(w.body, { size = UDim2.new(0, 170, 1, 0), gapPx = 6, padding = 4 })
	local right = UI.new("Frame", { Size = UDim2.new(1, -180, 1, 0), Position = UDim2.fromOffset(180, 0), BackgroundTransparency = 1 }, w.body)
	w.headerText = UI.text(right, { Text = "", Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left })
	local grid = UI.scroll(right, { size = UDim2.new(1, 0, 1, -42), position = UDim2.fromOffset(0, 42), grid = UDim2.fromOffset(130, 150), gap = UDim2.fromOffset(8, 8) })

	w.tabButtons = {}
	for i, biome in Config.Biomes do
		if not biome.seasonal or Config.HalloweenEnabled then
			local button = UI.button(tabs, {
				text = `{biome.emoji} {biome.name}`,
				color = c(70, 75, 95),
				size = UDim2.new(1, -8, 0, 46),
				order = i,
				onClick = function()
					w.biome = i
					w.refresh()
				end,
			})
			w.tabButtons[i] = button
		end
	end

	w.refresh = function()
		local index = env.state.index or {}
		local biome = Config.Biomes[w.biome]
		for i, button in w.tabButtons do
			UI.setButton(button, `{Config.Biomes[i].emoji} {Config.Biomes[i].name}`, if i == w.biome then BLUE else c(70, 75, 95))
		end
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local found = 0
		for order, p in biome.pets do
			local discovered = index[p.name] == true
			if discovered then
				found += 1
			end
			local cell = UI.new("Frame", { BackgroundColor3 = c(55, 58, 72), LayoutOrder = order }, grid)
			UI.corner(cell, 8)
			UI.stroke(cell, 3, if discovered then Config.Rarities[p.rarityIndex].color else c(80, 80, 90))
			UI.viewport(cell, UI.petModel(p.name), { size = UDim2.new(1, -8, 1, -46), position = UDim2.fromOffset(4, 4), silhouette = not discovered })
			UI.text(cell, { Text = if discovered then p.name else "???", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.new(0, 4, 1, -44) })
			UI.text(cell, { Text = p.rarity, TextColor3 = Config.Rarities[p.rarityIndex].color, Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 1, -22) })
		end
		local complete = found == #biome.pets
		w.headerText.Text = `{biome.emoji} {biome.name}: {found}/{#biome.pets} found` .. (if complete then `  <font color="#7dff6b">✓ +{math.floor(Config.IndexSetBonus * 100)}% money!</font>` else `  <font color="#aaaaaa">(complete for +{math.floor(Config.IndexSetBonus * 100)}% money)</font>`)
	end
end

---------------------------------------------------------------------------
-- Sell
---------------------------------------------------------------------------

local function buildSell()
	local w = window("Sell", "🐾 Sell Pets", c(110, 210, 40), Vector2.new(820, 500))
	w.keys = { "pets", "eggs", "nests", "equipped" }
	w.tab = "Pets"
	w.sort = "Value"
	w.selected = {}

	local left = UI.new("Frame", { Size = UDim2.new(0, 170, 1, -86), BackgroundColor3 = DARKER, BackgroundTransparency = 0.3 }, w.body)
	UI.corner(left, 6)
	UI.text(left, { Text = "Sort By:", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6) })
	local weightButton = UI.button(left, { text = "⬇ Weight", color = c(80, 85, 100), size = UDim2.new(1, -16, 0, 44), position = UDim2.fromOffset(8, 42), onClick = function()
		w.sort = "Weight"
		w.refresh()
	end })
	local valueButton = UI.button(left, { text = "⬇ Value", color = GREEN, size = UDim2.new(1, -16, 0, 44), position = UDim2.fromOffset(8, 94), onClick = function()
		w.sort = "Value"
		w.refresh()
	end })
	UI.button(left, { text = "✅ Select All", color = GREEN, size = UDim2.new(1, -16, 0, 44), position = UDim2.fromOffset(8, 160), onClick = function()
		local allSelected = true
		for _, item in w.items do
			if not w.selected[item.id] then
				allSelected = false
			end
		end
		table.clear(w.selected)
		if not allSelected then
			for _, item in w.items do
				if not item.locked then
					w.selected[item.id] = true
				end
			end
		end
		w.refresh()
	end })

	local tabs = UI.new("Frame", { Size = UDim2.new(0, 110, 1, -86), Position = UDim2.new(1, -110, 0, 0), BackgroundTransparency = 1 }, w.body)
	local eggsTab = UI.button(tabs, { text = "Eggs\n🥚", color = c(60, 140, 50), size = UDim2.new(1, 0, 0, 100), onClick = function()
		w.tab = "Eggs"
		table.clear(w.selected)
		w.refresh()
	end })
	local petsTab = UI.button(tabs, { text = "Pets\n🐾", color = GREEN, size = UDim2.new(1, 0, 0, 100), position = UDim2.fromOffset(0, 110), onClick = function()
		w.tab = "Pets"
		table.clear(w.selected)
		w.refresh()
	end })

	local grid = UI.scroll(w.body, { size = UDim2.new(1, -300, 1, -86), position = UDim2.fromOffset(180, 0), grid = UDim2.fromOffset(120, 140), gap = UDim2.fromOffset(8, 8) })
	local bottom = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 76), Position = UDim2.new(0, 0, 1, -76), BackgroundColor3 = DARKER }, w.body)
	UI.corner(bottom, 6)
	UI.stroke(bottom, 3)
	UI.text(bottom, { Text = "Total Value:", Size = UDim2.fromOffset(200, 40), Position = UDim2.fromOffset(16, 18), TextXAlignment = Enum.TextXAlignment.Left })
	w.total = UI.text(bottom, { Text = "💵 $0", Size = UDim2.fromOffset(260, 46), Position = UDim2.fromOffset(230, 15), TextXAlignment = Enum.TextXAlignment.Left })
	UI.button(bottom, { text = "Sell", color = c(90, 95, 110), size = UDim2.fromOffset(200, 56), position = UDim2.new(1, -12, 0.5, 0), anchor = Vector2.new(1, 0.5), name = "SellButton", onClick = function()
		local ids = {}
		for id in w.selected do
			table.insert(ids, id)
		end
		if #ids == 0 then
			env.notify("Select something to sell first!", "error")
			return
		end
		if w.tab == "Pets" then
			env.request("Sell", { pets = ids })
		else
			env.request("Sell", { eggs = ids })
		end
		table.clear(w.selected)
	end })
	local sellButton = bottom:FindFirstChild("SellButton") :: TextButton

	w.items = {}
	w.refresh = function()
		local state = env.state
		UI.setButton(weightButton, "⬇ Weight", if w.sort == "Weight" then GREEN else c(80, 85, 100))
		UI.setButton(valueButton, "⬇ Value", if w.sort == "Value" then GREEN else c(80, 85, 100))
		UI.setButton(eggsTab, "Eggs\n🥚", if w.tab == "Eggs" then GREEN else c(60, 140, 50))
		UI.setButton(petsTab, "Pets\n🐾", if w.tab == "Pets" then GREEN else c(60, 140, 50))
		table.clear(w.items)
		if w.tab == "Pets" then
			for id, p in state.pets or {} do
				table.insert(w.items, { id = id, kind = "pet", data = p, value = Config.petValue(p), weight = p.weight, locked = table.find(state.equipped or {}, id) ~= nil })
			end
		else
			for id, egg in state.eggs or {} do
				table.insert(w.items, { id = id, kind = "egg", data = egg, value = Config.eggValue(egg), weight = egg.weight })
			end
			for _, egg in state.nests or {} do
				table.insert(w.items, { id = egg.id, kind = "egg", data = egg, value = Config.eggValue(egg), weight = egg.weight, inNest = true })
			end
		end
		table.sort(w.items, function(a, b)
			if w.sort == "Weight" then
				return a.weight > b.weight
			end
			return a.value > b.value
		end)
		for _, child in grid:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local total = 0
		for order, item in w.items do
			local selected = w.selected[item.id] == true
			if selected then
				total += item.value
			end
			local rarity = Config.Rarities[item.data.rarity]
			local cell = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if selected then c(60, 140, 60) else c(55, 58, 72), LayoutOrder = order }, grid)
			UI.corner(cell, 8)
			UI.stroke(cell, 3, if selected then GREEN else rarity.color)
			local model = if item.kind == "pet" then UI.petModel(item.data.name) else UI.eggModel(item.data)
			UI.viewport(cell, model, { size = UDim2.new(1, -8, 1, -54), position = UDim2.fromOffset(4, 4) })
			UI.text(cell, { Text = if item.kind == "pet" then item.data.name else eggName(item.data), Size = UDim2.new(1, -6, 0, 20), Position = UDim2.new(0, 3, 1, -50), TextColor3 = rarity.color })
			UI.text(cell, { Text = `{item.weight}kg • ${Config.format(item.value)}`, Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 1, -28) })
			if item.locked then
				UI.text(cell, { Text = "EQUIPPED", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 4), TextColor3 = YELLOW })
			end
			cell.Activated:Connect(function()
				if item.locked then
					env.notify("Unequip this pet first (Pets panel).", "error")
					return
				end
				w.selected[item.id] = if w.selected[item.id] then nil else true
				w.refresh()
			end)
		end
		w.total.Text = `💵 <font color="#7dff6b">${Config.format(total)}</font>`
		UI.setButton(sellButton, "Sell", if total > 0 then GREEN else c(90, 95, 110))
	end
end

---------------------------------------------------------------------------
-- Trail Shop and Treadmill Shop
---------------------------------------------------------------------------

local function runnerModel(trail): Model
	return UI.cachedModel("runner:" .. trail.key, function()
		local def = { name = trail.name, template = "biped", primary = trail.colors[1], secondary = trail.colors[2], features = {}, scale = 1 }
		local model = Models.pet(def, { rarityFx = false })
		local root = model.PrimaryPart :: BasePart
		for i = 0, 3 do
			Models.box(model, "Ribbon", Vector3.new(0.3, 1.6 - i * 0.25, 1.2), root.CFrame * CFrame.new(0, 0.3, 1.2 + i * 1.1), trail.colors[1]:Lerp(trail.colors[2], i / 3), { Material = Enum.Material.Neon, Transparency = i * 0.15 })
		end
		return model
	end)
end

local function shopCards(name: string, title: string, headerColor: Color3, items, kind: string)
	local w = window(name, title, headerColor, Vector2.new(820, 470))
	w.keys = { kind, "money" }
	local row = UI.scroll(w.body, { horizontal = true, gapPx = 12 })
	w.cards = {}
	for i, item in items do
		if not (kind == "treadmills" and item.ownerOnly) or player.UserId == Config.OwnerUserId then
			local rarityColor = if kind == "trails" then item.colors[1] else c(80, 160, 230)
			local card = UI.new("Frame", { Size = UDim2.fromOffset(240, 370), BackgroundColor3 = rarityColor, LayoutOrder = i }, row)
			UI.corner(card, 8)
			UI.stroke(card, 4)
			UI.gradient(card, rarityColor:Lerp(WHITE, 0.35), rarityColor:Lerp(Color3.new(), 0.15))
			UI.text(card, { Text = item.name, Size = UDim2.new(1, -10, 0, 36), Position = UDim2.fromOffset(5, 8) })
			local subtitle = if kind == "trails" then item.rarity elseif item.ownerOnly then "Corny Exclusive" elseif item.vip then "VIP" elseif item.event then "Halloween Event" else "Treadmill"
			UI.text(card, { Text = subtitle, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 42) })
			local model = if kind == "trails" then runnerModel(item) else UI.cachedModel("mill:" .. item.key, function()
				return Models.treadmill(item.theme, "Wood")
			end)
			UI.viewport(card, model, { size = UDim2.new(1, -10, 0, 170), position = UDim2.fromOffset(5, 68), angle = math.rad(-40) })
			local multBox = UI.new("Frame", { Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 246), BackgroundColor3 = c(30, 30, 40), BackgroundTransparency = 0.35 }, card)
			UI.corner(multBox, 6)
			UI.text(multBox, { Text = `<font color="#7dff6b">x{Config.format(item.mult)}</font> Speed`, Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4) })
			local button = UI.button(card, {
				text = "",
				color = GREEN,
				size = UDim2.new(1, -20, 0, 54),
				position = UDim2.new(0, 10, 1, -64),
				onClick = function()
					local state = env.state[kind] or { owned = {} }
					if state.owned[item.key] then
						env.request(if kind == "trails" then "EquipTrail" else "EquipTreadmill", item.key)
					elseif item.robux and Config.Products[item.robux] then
						buyProduct(item.robux)
					elseif item.vip then
						buyPass("VIP")
					elseif item.event then
						env.notify("Drops from Halloween eggs during the event!", "info")
					elseif not item.ownerOnly then
						env.request(if kind == "trails" then "BuyTrail" else "BuyTreadmill", item.key)
					end
				end,
			})
			w.cards[item.key] = { item = item, button = button }
		end
	end
	w.refresh = function()
		local state = env.state[kind] or { owned = {}, equipped = "" }
		for key, card in w.cards do
			local item = card.item
			if state.equipped == key then
				UI.setButton(card.button, "EQUIPPED", c(120, 120, 130))
			elseif state.owned[key] then
				UI.setButton(card.button, "EQUIP", BLUE)
			elseif item.robux then
				UI.setButton(card.button, `${Config.format(item.cost)} / {ROBUX}{Config.Products[item.robux].price}`, if (env.state.money or 0) >= item.cost then GREEN else c(200, 120, 40))
			elseif item.vip then
				UI.setButton(card.button, `{ROBUX} VIP Pass`, PURPLE)
			elseif item.event then
				UI.setButton(card.button, "🎃 Event Drop", c(255, 130, 20))
			elseif item.ownerOnly then
				UI.setButton(card.button, "🔒 Exclusive", c(90, 90, 100))
			else
				UI.setButton(card.button, `${Config.format(item.cost)}`, if (env.state.money or 0) >= item.cost then GREEN else c(200, 120, 40))
			end
		end
	end
	return w
end

---------------------------------------------------------------------------
-- Growing Eggs (side) and Active Pets (side)
---------------------------------------------------------------------------

local function buildGrowing()
	local w = sidePanel("Growing", "Growing Eggs", Vector2.new(400, 470))
	w.keys = { "nests", "eggs", "penLevel", "passes" }
	UI.button(w.header, { text = "Grow All", color = YELLOW, textColor = WHITE, size = UDim2.fromOffset(130, 44), position = UDim2.new(1, -8, 0, 6), anchor = Vector2.new(1, 0), onClick = function()
		buyProduct("SkipGrow")
	end })
	local list = UI.scroll(w.body, { gapPx = 8 })
	w.rows = {}
	w.refresh = function()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		table.clear(w.rows)
		local state = env.state
		local slots = {}
		for slot, egg in state.nests or {} do
			table.insert(slots, { slot = slot, egg = egg })
		end
		table.sort(slots, function(a, b)
			return tonumber(a.slot) < tonumber(b.slot)
		end)
		local nestCount = Config.PenLevels[state.penLevel or 1].nests
		UI.text(list, { Text = `Nests: {#slots}/{nestCount}`, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0 })
		for order, entry in slots do
			local egg = entry.egg
			local row = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 76), BackgroundColor3 = c(60, 62, 78), LayoutOrder = order }, list)
			UI.corner(row, 6)
			UI.stroke(row, 2, Config.Rarities[egg.rarity].color)
			UI.viewport(row, UI.eggModel(egg), { size = UDim2.fromOffset(64, 64), position = UDim2.fromOffset(6, 6) })
			UI.text(row, { Text = eggName(egg), TextColor3 = Config.Rarities[egg.rarity].color, Size = UDim2.new(1, -190, 0, 26), Position = UDim2.fromOffset(76, 8), TextXAlignment = Enum.TextXAlignment.Left })
			local barBack = UI.new("Frame", { Size = UDim2.new(1, -190, 0, 18), Position = UDim2.fromOffset(76, 44), BackgroundColor3 = c(30, 30, 38) }, row)
			UI.corner(barBack, 6)
			local bar = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN }, barBack)
			UI.corner(bar, 6)
			local timer = UI.text(barBack, { Text = "", Size = UDim2.fromScale(1, 1.2), Position = UDim2.fromScale(0, -0.1), ZIndex = 3 })
			local hatch = UI.button(row, { text = "Hatch", color = GREEN, size = UDim2.fromOffset(100, 50), position = UDim2.new(1, -8, 0.5, 0), anchor = Vector2.new(1, 0.5), onClick = function()
				env.request("Hatch", entry.slot)
			end })
			local total = Config.growSeconds(egg.biome, egg.rarity) / (if state.passes and state.passes.Growth then 2 else 1)
			table.insert(w.rows, { egg = egg, bar = bar, timer = timer, hatch = hatch, total = total })
		end
		local bagCount = 0
		for _ in state.eggs or {} do
			bagCount += 1
		end
		if bagCount > 0 then
			UI.text(list, { Text = `Eggs Bag ({bagCount})`, TextColor3 = YELLOW, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 100 })
			local order = 101
			for id, egg in state.eggs do
				local row = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 70), BackgroundColor3 = c(55, 58, 72), LayoutOrder = order }, list)
				order += 1
				UI.corner(row, 6)
				UI.viewport(row, UI.eggModel(egg), { size = UDim2.fromOffset(58, 58), position = UDim2.fromOffset(6, 6) })
				UI.text(row, { Text = `{eggName(egg)}\n<font size="14">{egg.weight}kg</font>`, TextColor3 = Config.Rarities[egg.rarity].color, Size = UDim2.new(1, -230, 1, -12), Position = UDim2.fromOffset(70, 6), TextXAlignment = Enum.TextXAlignment.Left })
				UI.button(row, { text = "Place", color = GREEN, size = UDim2.fromOffset(74, 46), position = UDim2.new(1, -86, 0.5, 0), anchor = Vector2.new(1, 0.5), onClick = function()
					env.request("PlaceEgg", id)
				end })
				UI.button(row, { text = "Hold", color = BLUE, size = UDim2.fromOffset(74, 46), position = UDim2.new(1, -6, 0.5, 0), anchor = Vector2.new(1, 0.5), onClick = function()
					env.request("HoldEgg", id)
					Panels.close("Growing")
				end })
			end
		end
		if #slots == 0 and bagCount == 0 then
			UI.text(list, { Text = "No eggs yet!\nSteal eggs from the biomes and bring them home.", Size = UDim2.new(1, -20, 0, 80), LayoutOrder = 1, TextColor3 = c(200, 200, 210) })
		end
		w.tick()
	end
	w.tick = function()
		local now = env.serverNow()
		for _, row in w.rows do
			local left = (row.egg.growEnd or 0) - now
			local ratio = if row.total > 0 then 1 - math.clamp(left / row.total, 0, 1) else 1
			row.bar.Size = UDim2.fromScale(ratio, 1)
			if left > 0 then
				row.timer.Text = Config.formatTime(left)
				row.hatch.Visible = false
			else
				row.timer.Text = "READY!"
				row.hatch.Visible = true
			end
		end
	end
end

local function buildActive()
	local w = sidePanel("Active", "1/1 Active", Vector2.new(420, 470))
	w.keys = { "pets", "equipped", "slots", "money" }
	local slotButton = UI.button(w.header, { text = "+1 EQUIP", color = GREEN, size = UDim2.fromOffset(190, 44), position = UDim2.new(1, -8, 0, 6), anchor = Vector2.new(1, 0), onClick = function()
		env.request("BuySlot")
	end })
	local list = UI.scroll(w.body, { size = UDim2.new(1, 0, 1, -62), gapPx = 8 })
	UI.button(w.frame, { text = "Equip Best", color = GREEN, size = UDim2.fromOffset(190, 50), position = UDim2.new(1, -8, 1, 8), anchor = Vector2.new(1, 0), onClick = function()
		env.request("EquipBest")
	end })
	w.refresh = function()
		local state = env.state
		local slots = state.slots or { used = 0, max = 1, bought = 1 }
		local title = w.header:FindFirstChild("Title") :: TextLabel
		title.Text = `{slots.used}/{slots.max} Active`
		local cost = Config.EquipSlotCosts[slots.bought]
		slotButton.Visible = cost ~= nil
		if cost then
			UI.setButton(slotButton, `+1 EQUIP [${Config.format(cost)}]`, if (state.money or 0) >= cost then GREEN else c(200, 120, 40))
		end
		for _, child in list:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local pets = {}
		for _, p in state.pets or {} do
			table.insert(pets, p)
		end
		local equipped = state.equipped or {}
		table.sort(pets, function(a, b)
			local ea, eb = table.find(equipped, a.id) ~= nil, table.find(equipped, b.id) ~= nil
			if ea ~= eb then
				return ea
			end
			return Config.petIncome(a) > Config.petIncome(b)
		end)
		for order, p in pets do
			local isEquipped = table.find(equipped, p.id) ~= nil
			local rarity = Config.Rarities[p.rarity]
			local row = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 70), BackgroundColor3 = if isEquipped then c(70, 74, 92) else c(52, 54, 66), LayoutOrder = order }, list)
			UI.corner(row, 6)
			UI.stroke(row, 2, rarity.color)
			UI.viewport(row, UI.petModel(p.name), { size = UDim2.fromOffset(60, 60), position = UDim2.fromOffset(5, 5) })
			UI.text(row, { Text = `{p.name} <font color="#7dff6b">(${Config.format(Config.petIncome(p))}/s)</font>\n<font size="14" color="{rarityHex(p.rarity)}">{rarity.name} • {p.weight}kg</font>`, Size = UDim2.new(1, -200, 1, -12), Position = UDim2.fromOffset(70, 6), TextXAlignment = Enum.TextXAlignment.Left })
			UI.button(row, { text = if isEquipped then "Unequip" else "Equip", color = if isEquipped then RED else GREEN, size = UDim2.fromOffset(116, 48), position = UDim2.new(1, -6, 0.5, 0), anchor = Vector2.new(1, 0.5), onClick = function()
				env.request(if isEquipped then "Unequip" else "Equip", p.id)
			end })
		end
		if #pets == 0 then
			UI.text(list, { Text = "No pets yet!\nHatch eggs in your pen to get pets.", Size = UDim2.new(1, -20, 0, 80), LayoutOrder = 1, TextColor3 = c(200, 200, 210) })
		end
	end
end

---------------------------------------------------------------------------
-- Free Gift, Daily, Playtime, Rebirth
---------------------------------------------------------------------------

local function buildGift()
	local w = window("Gift", "Free Gift!", c(40, 200, 230), Vector2.new(760, 470))
	w.keys = { "groupClaimed" }
	UI.text(w.body, { Text = "🎒👟", Size = UDim2.fromOffset(260, 170), Position = UDim2.fromOffset(10, 0) })
	UI.text(w.body, { Text = `<font color="#ff5f5f">~ LIMITED TIME! ~</font>\n<font color="#3fe0ff">{Config.formatWithCommas(Config.GroupRewardSpeed)} SPEED!</font>`, Size = UDim2.new(1, -300, 0, 150), Position = UDim2.fromOffset(290, 10), strokeThickness = 3 })
	local steps = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 150), Position = UDim2.fromOffset(0, 180), BackgroundTransparency = 1 }, w.body)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }, steps)
	local stepInfo = { { "1. Like the game!", "👍" }, { "2. Favorite the game!", "⭐" }, { "3. Join the community!", "👥" } }
	for i, info in stepInfo do
		local cardFrame = UI.new("Frame", { Size = UDim2.fromOffset(230, 140), BackgroundColor3 = c(30, 32, 42), LayoutOrder = i }, steps)
		UI.corner(cardFrame, 8)
		UI.stroke(cardFrame, 3)
		UI.text(cardFrame, { Text = info[1], Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 6) })
		UI.text(cardFrame, { Text = info[2], Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 44) })
	end
	local joinButton = UI.button(w.body, { text = "Join Group", color = BLUE, size = UDim2.fromOffset(220, 64), position = UDim2.new(0.5, -120, 1, -4), anchor = Vector2.new(1, 1), onClick = function()
		pcall(function()
			GroupService:PromptJoinAsync(Config.GroupId)
		end)
	end })
	local claim = UI.button(w.body, { text = "Claim!", color = GREEN, size = UDim2.fromOffset(300, 64), position = UDim2.new(0.5, -100, 1, -4), anchor = Vector2.new(0, 1), onClick = function()
		env.request("ClaimGroup")
	end })
	w.refresh = function()
		if env.state.groupClaimed then
			UI.setButton(claim, "Claimed ✓", c(120, 120, 130))
		else
			UI.setButton(claim, "Claim!", GREEN)
		end
		joinButton.Visible = not env.state.groupClaimed
	end
end

local function buildDaily()
	local w = window("Daily", "Daily Rewards", c(255, 170, 40), Vector2.new(760, 380))
	w.keys = { "daily" }
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 170), Position = UDim2.fromOffset(0, 10), BackgroundTransparency = 1 }, w.body)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }, row)
	w.tiles = {}
	for day, reward in Config.DailyRewards do
		local tile = UI.new("Frame", { Size = UDim2.fromOffset(96, 160), BackgroundColor3 = c(60, 62, 78), LayoutOrder = day }, row)
		UI.corner(tile, 8)
		local stroke = UI.stroke(tile, 3)
		UI.text(tile, { Text = `Day {day}`, Size = UDim2.new(1, -8, 0, 28), Position = UDim2.fromOffset(4, 6) })
		UI.text(tile, { Text = if reward.egg then "🥚" else "💵", Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 40) })
		UI.text(tile, { Text = if reward.egg then "Rare Egg!" else "Cash", Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -34) })
		w.tiles[day] = { frame = tile, stroke = stroke }
	end
	local claim = UI.button(w.body, { text = "Claim!", color = GREEN, size = UDim2.fromOffset(300, 64), position = UDim2.new(0.5, 0, 1, -6), anchor = Vector2.new(0.5, 1), onClick = function()
		env.request("ClaimDaily")
	end })
	w.refresh = function()
		local daily = env.state.daily or { streak = 0, canClaim = false, nextStreak = 1 }
		local current = if daily.canClaim then daily.nextStreak else ((daily.streak - 1) % 7) + 1
		for day, tile in w.tiles do
			local isCurrent = day == current
			tile.frame.BackgroundColor3 = if isCurrent then c(80, 170, 60) elseif day < current then c(45, 47, 58) else c(60, 62, 78)
			tile.stroke.Color = if isCurrent then YELLOW else c(15, 15, 20)
		end
		if daily.canClaim then
			UI.setButton(claim, `Claim Day {daily.nextStreak}!`, GREEN)
		else
			UI.setButton(claim, "Come back tomorrow!", c(120, 120, 130))
		end
	end
end

local function buildPlaytime()
	local w = window("Playtime", "Playtime Gifts", c(200, 80, 230), Vector2.new(700, 330))
	w.keys = { "playtime" }
	local row = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, w.body)
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	w.tiles = {}
	for i, gift in Config.PlaytimeGifts do
		local tile = UI.new("Frame", { Size = UDim2.fromOffset(150, 220), BackgroundColor3 = c(60, 62, 78), LayoutOrder = i }, row)
		UI.corner(tile, 8)
		UI.stroke(tile, 3)
		UI.text(tile, { Text = `{gift.minutes} min`, Size = UDim2.new(1, -8, 0, 30), Position = UDim2.fromOffset(4, 6) })
		UI.text(tile, { Text = if gift.egg then "🥚" elseif gift.speed then "👟" else "💵", Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 40) })
		local button = UI.button(tile, { text = "", color = GREEN, size = UDim2.new(1, -16, 0, 50), position = UDim2.new(0, 8, 1, -58), onClick = function()
			env.request("ClaimPlaytime", i)
		end })
		w.tiles[i] = button
	end
	w.refresh = function()
		local playtime = env.state.playtime or { seconds = 0, claimed = {} }
		for i, button in w.tiles do
			local gift = Config.PlaytimeGifts[i]
			local left = gift.minutes * 60 - playtime.seconds
			if playtime.claimed[tostring(i)] then
				UI.setButton(button, "Claimed", c(120, 120, 130))
			elseif left <= 0 then
				UI.setButton(button, "Claim!", GREEN)
			else
				UI.setButton(button, Config.formatTime(left), c(90, 95, 110))
			end
		end
	end
	w.tick = w.refresh
end

local function buildRebirth()
	local w = window("Rebirth", "♻️ Rebirth", c(110, 220, 70), Vector2.new(640, 420))
	w.keys = { "rebirths", "money" }
	local info = UI.text(w.body, { Text = "", Size = UDim2.new(1, -20, 0, 250), Position = UDim2.fromOffset(10, 0), TextYAlignment = Enum.TextYAlignment.Top })
	local button = UI.button(w.body, { text = "Rebirth!", color = GREEN, size = UDim2.fromOffset(320, 64), position = UDim2.new(0.5, 0, 1, -6), anchor = Vector2.new(0.5, 1), onClick = function()
		env.request("Rebirth")
		Panels.close("Rebirth")
	end })
	w.refresh = function()
		local rebirths = env.state.rebirths or 0
		local cost = Config.rebirthCost(rebirths)
		local now = 1 + rebirths * Config.RebirthBoost
		local nextBoost = now + Config.RebirthBoost
		info.Text = `Rebirth {rebirths} ➜ <font color="#7dff6b">{rebirths + 1}</font>\n`
			.. `Money & Speed boost: x{now} ➜ <font color="#7dff6b">x{nextBoost}</font>\n\n`
			.. `<font color="#ff7070">Resets:</font> Money, Speed, Pen level\n`
			.. `<font color="#7dff6b">Keeps:</font> Pets, Eggs, Trails, Treadmills\n\n`
			.. `Cost: <font color="#ffd23c">${Config.format(cost)}</font>`
		UI.setButton(button, if (env.state.money or 0) >= cost then "Rebirth!" else `Need ${Config.format(cost)}`, if (env.state.money or 0) >= cost then GREEN else c(120, 120, 130))
	end
end

---------------------------------------------------------------------------
-- Popups, gift picker, welcome back, hatch reveal
---------------------------------------------------------------------------

local function buildPopup()
	local frame = UI.new("Frame", { Name = "Popup", Size = UDim2.fromOffset(620, 300), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = c(30, 30, 34), BackgroundTransparency = 0.08, Visible = false, ZIndex = 20 }, env.gui)
	UI.corner(frame, 10)
	UI.stroke(frame, 4, c(70, 70, 80))
	local message = UI.text(frame, { Text = "", Size = UDim2.new(1, -60, 0, 160), Position = UDim2.fromOffset(30, 30), ZIndex = 21 })
	UI.button(frame, { text = "Ok!", color = GREEN, size = UDim2.fromOffset(240, 66), position = UDim2.new(0.5, 0, 1, -24), anchor = Vector2.new(0.5, 1), onClick = function()
		frame.Visible = false
	end })
	UI.button(frame, { text = "X", color = RED, size = UDim2.fromOffset(52, 52), position = UDim2.new(1, 14, 0, -14), anchor = Vector2.new(1, 0), onClick = function()
		frame.Visible = false
	end })
	local scale = UI.new("UIScale", {}, frame)
	windows.Popup = { frame = frame, body = frame, kind = "popup", scale = scale }
	Panels.popup = function(text: string)
		message.Text = text
		frame.Visible = true
	end
end

local function buildGiftPicker()
	local w = window("GiftPicker", "🎁 Gift to...", c(200, 70, 230), Vector2.new(520, 460))
	local list = UI.scroll(w.body, { gapPx = 8 })
	local callback = nil
	giftPicker = function(onPick)
		callback = onPick
		Panels.open("GiftPicker")
	end
	w.refresh = function()
		for _, child in list:GetChildren() do
			if child:IsA("TextButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local count = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				count += 1
				UI.button(list, { text = `{other.DisplayName} (@{other.Name})`, color = PURPLE, size = UDim2.new(1, -10, 0, 54), order = count, onClick = function()
					Panels.close("GiftPicker")
					if callback then
						callback(other.UserId)
					end
				end })
			end
		end
		if count == 0 then
			UI.text(list, { Text = "Nobody else is in this server yet!", Size = UDim2.new(1, -20, 0, 60), TextColor3 = c(200, 200, 210) })
		end
	end
end

local function buildWelcome()
	local w = window("Welcome", "Welcome back!", c(80, 210, 60), Vector2.new(600, 330))
	local text = UI.text(w.body, { Text = "", Size = UDim2.new(1, -20, 0, 160), Position = UDim2.fromOffset(10, 10) })
	UI.button(w.body, { text = "Collect!", color = GREEN, size = UDim2.fromOffset(260, 64), position = UDim2.new(0.5, 0, 1, -6), anchor = Vector2.new(0.5, 1), onClick = function()
		Panels.close("Welcome")
	end })
	w.onOpen = function(arg)
		if arg then
			text.Text = `Your pets earned\n<font color="#7dff6b">${Config.format(arg.amount)}</font>\nwhile you were away ({Config.formatTime(arg.seconds)})!`
		end
	end
end

-- Full-screen hatch reveal: egg shakes, cracks with a flash, the pet spins in.
function Panels.hatchReveal(p, isNew: boolean, egg)
	local overlay = UI.new("Frame", { Name = "Hatch", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.45, ZIndex = 30 }, env.gui)
	local holder = UI.new("Frame", { Size = UDim2.fromOffset(360, 360), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 31 }, overlay)
	UI.new("UIScale", { Scale = windows.Shop and windows.Shop.scale.Scale or 1 }, holder)
	local eggView = UI.viewport(holder, UI.eggModel(egg), { size = UDim2.fromScale(0.8, 0.8), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5) })
	eggView.ZIndex = 32
	env.sound("Swing")
	for i = 1, 8 do
		eggView.Rotation = if i % 2 == 0 then 12 else -12
		task.wait(0.07 + i * 0.012)
	end
	eggView:Destroy()
	local flash = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 40 }, overlay)
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	env.sound("Notify")
	local rarity = Config.Rarities[p.rarity]
	local glow = UI.new("Frame", { Size = UDim2.fromScale(1.1, 1.1), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = rarity.color, BackgroundTransparency = 0.55, ZIndex = 31 }, holder)
	UI.corner(glow, 999)
	local petView = UI.viewport(holder, UI.petModel(p.name), { size = UDim2.fromScale(0.1, 0.1), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5) })
	petView.ZIndex = 33
	TweenService:Create(petView, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.95, 0.95) }):Play()
	UI.text(overlay, { Text = `<font color="{rarityHex(p.rarity)}">{rarity.name:upper()}</font>\n{p.name}`, Size = UDim2.fromOffset(600, 110), Position = UDim2.new(0.5, 0, 0.45, 190), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 34, strokeThickness = 4 })
	if isNew then
		UI.text(overlay, { Text = "NEW!", TextColor3 = YELLOW, Size = UDim2.fromOffset(200, 60), Position = UDim2.new(0.5, 0, 0.45, -230), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 34, strokeThickness = 4 })
	end
	local spin = 0
	local running = true
	task.spawn(function()
		while running do
			spin += 2
			glow.Rotation = spin
			task.wait()
		end
	end)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		running = false
		TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.wait(0.25)
		overlay:Destroy()
	end
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			close()
		end
	end)
	task.delay(3.2, close)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function Panels.init(environment)
	env = environment
	buildShop()
	buildIndex()
	buildSell()
	shopCards("Trails", "Trail Shop", c(190, 80, 230), Config.Trails, "trails")
	shopCards("Treadmills", "Treadmill Shop", c(40, 150, 240), Config.Treadmills, "treadmills")
	buildGrowing()
	buildActive()
	buildGift()
	buildDaily()
	buildPlaytime()
	buildRebirth()
	buildPopup()
	buildGiftPicker()
	buildWelcome()

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
		if userId == player.UserId and not purchased then
			env.request("SetGiftTarget", nil)
		end
	end)
end

-- Called every half second for live timers.
function Panels.tick()
	for _, w in windows do
		if w.frame.Visible and w.tick then
			w.tick()
		end
	end
end

return Panels

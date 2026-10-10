--!strict
-- East room Mega Shop: Coin Shop rotation pedestals, the four category crates,
-- the isolated Mythic Featured shrine (global stock), stat upgrades, gamepass
-- and coin-pack kiosks, plus every ShopAction coming from the catalog UIs.
-- All purchases are validated here; the client never decides prices or drops.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Crates = require(Shared:WaitForChild("Crates"))
local Minigames = require(Shared:WaitForChild("Minigames"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Parts = require(Server:WaitForChild("World"):WaitForChild("Parts"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local CreatorCodes = require(Server:WaitForChild("Services"):WaitForChild("CreatorCodes"))
local MythicStock = require(Server:WaitForChild("Services"):WaitForChild("MythicStock"))
local Displays = require(script.Parent:WaitForChild("Displays"))

local Shop = {}

local T = UIKit.Theme
local rng = Random.new()
local lobby: LobbyTypes.Lobby
local propsFolder: Folder
local lastAction: { [Player]: number } = {}
local cratePedestals: { [string]: BasePart } = {}

local function result(player: Player, ok: boolean, text: string)
	Net.event("Fx"):FireClient(player, "shopResult", { Ok = ok, Text = text })
end

local function today(): number
	return math.floor(os.time() / 86400)
end

-- Skins -------------------------------------------------------------------

local rotation: { Skins.Skin } = {}
local rotationDay = -1

function Shop.rotation(): { Skins.Skin }
	return rotation
end

local function inRotation(id: string): boolean
	for _, s in rotation do
		if s.Id == id then
			return true
		end
	end
	return false
end

function Shop.buySkin(player: Player, id: string)
	local skin = Skins.ById[id]
	if not skin then
		return
	end
	if Data.owns(player, "Skins", id) then
		Data.equip(player, "Skins", id)
		result(player, true, "Equipped " .. skin.Name)
		return
	end
	if skin.Source ~= "Shop" or skin.Rarity == "Mythic" or not inRotation(id) then
		result(player, false, skin.Name .. " isn't in today's shop")
		return
	end
	local price = Skins.price(id)
	if not Data.spend(player, price) then
		result(player, false, "Not enough coins")
		return
	end
	Data.grant(player, "Skins", id)
	Data.equip(player, "Skins", id)
	CreatorCodes.record(player, price, 0)
	result(player, true, "Bought & equipped " .. skin.Name)
end

function Shop.equip(player: Player, category: string, id: string)
	if not Cosmetics.isCategory(category) or type(id) ~= "string" then
		return
	end
	local item = Cosmetics.get(category, id)
	if item and Data.equip(player, category, id) then
		result(player, true, "Equipped " .. item.Name)
	else
		result(player, false, "You don't own that yet")
	end
end

-- Crates --------------------------------------------------------------------

local function revealAt(crateId: string): Vector3?
	local part = cratePedestals[crateId]
	if crateId == "Featured" then
		part = lobby.East.Mythic.Pedestal
	elseif Crates.get(crateId) and (Crates.get(crateId) :: Crates.Crate).Currency ~= "Coins" then
		part = lobby.South.TokenKiosk.CratePedestal
	end
	return if part then Displays.anchorPoint(part) else nil
end

-- Opens a crate. `free` = already paid (Robux receipt, stock already reserved).
-- Returns true on success.
function Shop.openCrate(player: Player, crateId: string, free: boolean?): boolean
	local crate = Crates.get(crateId)
	local session = Data.get(player)
	if not crate or not session then
		return false
	end
	local profile = session.Profile
	local paidCoins = 0
	local usedKey = false

	if not free then
		local tokenId = string.match(crate.Currency, "^Tokens:(.+)$")
		if tokenId then
			local active = Minigames.active(os.time())
			if active.Id ~= tokenId then
				result(player, false, crate.Name .. " is only sold while " .. (Minigames.ById[tokenId] :: Minigames.Minigame).Name .. " is active")
				return false
			end
			if (profile.Tokens[tokenId] or 0) < crate.Price then
				result(player, false, "Not enough " .. (Minigames.ById[tokenId] :: Minigames.Minigame).Token)
				return false
			end
			Data.addTokens(player, tokenId, -crate.Price)
		elseif crate.Keyed and (profile.Keys[crateId] or 0) > 0 then
			profile.Keys[crateId] -= 1
			usedKey = true
			Data.markDirty(player)
		else
			if crateId == "Featured" and not MythicStock.reserve() then
				result(player, false, "The Mythic Featured Crate is sold out")
				return false
			end
			if not Data.spend(player, crate.Price) then
				if crateId == "Featured" then
					MythicStock.release()
				end
				result(player, false, "Not enough coins")
				return false
			end
			paidCoins = crate.Price
		end
	end

	local pity = profile.Pity[crateId] or 0
	local item, newPity = Crates.roll(crate, rng, pity)
	profile.Pity[crateId] = newPity
	local isNew = Data.grant(player, crate.Category, item.Id)
	local refund = 0
	if not isNew then
		refund = Crates.refund(crate, item.Rarity)
		local tokenId = string.match(crate.Currency, "^Tokens:(.+)$")
		if tokenId then
			Data.addTokens(player, tokenId, refund)
		else
			Data.addCoins(player, refund, "refund")
		end
	end
	Data.markDirty(player)
	Data.push(player)
	if paidCoins > 0 then
		CreatorCodes.record(player, paidCoins, 0)
	end

	local rarityColor = Skins.Rarities[item.Rarity].Color
	local at = revealAt(crateId)
	if at then
		Displays.reveal(propsFolder, at, if crate.Category == "Skins" then item.Id else nil, rarityColor, item.Name, player.DisplayName .. " · " .. item.Rarity)
	end
	Net.event("CrateReveal"):FireClient(player, crateId, crate.Category, item.Id, isNew, refund, usedKey)
	if Skins.Rarities[item.Rarity].Order >= Skins.Rarities.Legendary.Order then
		Net.event("Fx"):FireAllClients("announce", {
			Text = string.format("%s unboxed %s %s (%s)!", player.DisplayName, item.Rarity, item.Name, Cosmetics.CategoryInfo[crate.Category].Singular),
			Color = rarityColor,
		})
	end
	return true
end

-- Upgrades --------------------------------------------------------------------

function Shop.upgrade(player: Player, stat: string)
	local profile = Data.profile(player)
	if not profile or profile.Upgrades[stat] == nil then
		return
	end
	local level = profile.Upgrades[stat]
	if level >= Config.Upgrades.MaxLevel then
		result(player, false, stat .. " is maxed")
		return
	end
	local cost = Config.Upgrades.Costs[level + 1]
	if not Data.spend(player, cost) then
		result(player, false, "Not enough coins")
		return
	end
	profile.Upgrades[stat] = level + 1
	Data.markDirty(player)
	Data.push(player)
	CreatorCodes.record(player, cost, 0)
	result(player, true, string.format("%s upgraded to level %d", stat, level + 1))
end

-- Celebrations ----------------------------------------------------------------

function Shop.celebration(player: Player, id: string)
	local session = Data.get(player)
	if not session or not table.find(Config.Celebrations, id) then
		return
	end
	if id ~= "Default" and not session.Passes.Celebrations then
		result(player, false, "Needs the Celebration Pack pass")
		return
	end
	session.Profile.Celebration = id
	Data.markDirty(player)
	Data.push(player)
	result(player, true, "Celebration set: " .. id)
end

-- Robux prompts -----------------------------------------------------------------

function Shop.promptPass(player: Player, key: string)
	local pass = Config.GamePasses[key]
	if not pass then
		return
	end
	if pass.Id == 0 then
		result(player, false, pass.Name .. " is coming soon")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end

function Shop.promptProduct(player: Player, key: string)
	local product = Config.DevProducts[key]
	if not product then
		return
	end
	if product.Id == 0 then
		result(player, false, product.Name .. " is coming soon")
		return
	end
	if key == "MythicCrate" and MythicStock.remaining() <= 0 then
		result(player, false, "Sold out")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

-- Remote router -------------------------------------------------------------------

local handlers: { [string]: (Player, any, any) -> () } = {
	buySkin = function(p, a)
		if type(a) == "string" then
			Shop.buySkin(p, a)
		end
	end,
	equip = function(p, a, b)
		if type(a) == "string" and type(b) == "string" then
			Shop.equip(p, a, b)
		end
	end,
	openCrate = function(p, a)
		if type(a) == "string" then
			Shop.openCrate(p, a)
		end
	end,
	upgrade = function(p, a)
		if type(a) == "string" then
			Shop.upgrade(p, a)
		end
	end,
	celebration = function(p, a)
		if type(a) == "string" then
			Shop.celebration(p, a)
		end
	end,
	buyPass = function(p, a)
		if type(a) == "string" then
			Shop.promptPass(p, a)
		end
	end,
	buyProduct = function(p, a)
		if type(a) == "string" then
			Shop.promptProduct(p, a)
		end
	end,
}

function Shop.handle(action: string, handler: (Player, any, any) -> ())
	handlers[action] = handler
end

local function onAction(player: Player, action: any, a: any, b: any)
	if type(action) ~= "string" then
		return
	end
	local t = os.clock()
	if t - (lastAction[player] or 0) < 0.3 then
		return
	end
	lastAction[player] = t
	local h = handlers[action]
	if h then
		h(player, a, b)
	end
end

-- World props ---------------------------------------------------------------------

local function rarityColor(r: string): Color3
	return Skins.Rarities[r].Color
end

local function buildRotation()
	rotationDay = today()
	rotation = Skins.shopRotation(rotationDay, #lobby.East.SkinPedestals)
	local folder = propsFolder:FindFirstChild("Rotation")
	if folder then
		folder:Destroy()
	end
	local f = Parts.folder(propsFolder, "Rotation")
	for i, pedestal in lobby.East.SkinPedestals do
		local skin = rotation[i]
		if skin then
			local ball = Displays.ball(f, Displays.anchorPoint(pedestal), skin.Id, 3)
			ball:SetAttribute("SkinId", skin.Id)
			Displays.card(ball, 3.2, skin.Name, skin.Rarity .. " ball skin", UIKit.formatNumber(Skins.price(skin.Id)) .. " coins", rarityColor(skin.Rarity))
			local prompt = Parts.prompt(pedestal, "Buy · " .. UIKit.formatNumber(Skins.price(skin.Id)), skin.Name, { Name = "BuyPrompt", Distance = 9 })
			prompt:SetAttribute("SkinId", skin.Id)
			prompt.Parent = ball
			prompt.Triggered:Connect(function(player)
				Shop.buySkin(player, skin.Id)
			end)
		end
	end
end

local function oddsBoard(screen: BasePart, crate: Crates.Crate, title: string)
	local gui = UIKit.surface(screen, { PixelsPerStud = 50, Name = "OddsUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 6)
	UIKit.text({ Text = string.upper(title), TextSize = 30, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 0, Parent = root })
	local priceText = if crate.Currency == "Coins"
		then UIKit.formatNumber(crate.Price) .. " coins" .. (if crate.Keyed then "  ·  or 1 crate key" else "")
		else crate.Price .. " " .. (string.match(crate.Currency, "Tokens:(.+)") or "") .. " tokens"
	UIKit.text({ Text = priceText, TextSize = 18, Font = T.FontMedium, TextColor3 = T.Gold, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = root })
	for i, line in Crates.oddsLines(crate) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 24)
		row.LayoutOrder = 10 + i
		row.Parent = root
		UIKit.tag(line.Rarity, rarityColor(line.Rarity), { Parent = row })
		UIKit.text({
			Text = string.format("%g%%", line.Percent),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromScale(1, 1),
			Parent = row,
		})
	end
	UIKit.text({
		Text = string.format("Guaranteed %s+ within %d opens. Duplicates refund part of the price.", crate.PityRarity, crate.PityAt),
		TextSize = 14,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 99,
		Parent = root,
	})
end

local function buildCrates()
	local f = Parts.folder(propsFolder, "Crates")
	for _, id in Crates.ShopOrder do
		local crate = Crates.get(id) :: Crates.Crate
		local pedestal = lobby.East.CratePedestals[id]
		if pedestal then
			cratePedestals[id] = pedestal
			local model = Displays.crate(f, Displays.anchorPoint(pedestal), crate.Color)
			Displays.bob(model)
			local prompt = Parts.prompt(pedestal, "Open · " .. UIKit.formatNumber(crate.Price), crate.Name, { Name = "OpenPrompt", Hold = 0.3, Distance = 9 })
			prompt:SetAttribute("CrateId", id)
			prompt.Triggered:Connect(function(player)
				Shop.openCrate(player, id)
			end)
			local screen = lobby.East.CrateScreens[id]
			if screen then
				oddsBoard(screen, crate, crate.Name)
			end
		end
	end
end

local function buildMythic()
	local shrine = lobby.East.Mythic
	local crate = Crates.get("Featured") :: Crates.Crate
	local model = Displays.crate(propsFolder, Displays.anchorPoint(shrine.Pedestal), crate.Color, 4)
	Displays.bob(model)
	local coinPrompt = Parts.prompt(shrine.Pedestal, "Open · " .. UIKit.formatNumber(crate.Price) .. " coins", crate.Name, { Name = "OpenPrompt", Hold = 0.6, Distance = 10 })
	coinPrompt.Triggered:Connect(function(player)
		Shop.openCrate(player, "Featured")
	end)
	local product = Config.DevProducts.MythicCrate
	local robuxPrompt = Parts.prompt(shrine.Pedestal, "Buy · " .. product.Robux .. " Robux", crate.Name, { Name = "RobuxPrompt", Distance = 10, Key = Enum.KeyCode.R })
	robuxPrompt.UIOffset = Vector2.new(0, 70)
	robuxPrompt.Enabled = product.Id ~= 0
	robuxPrompt.Triggered:Connect(function(player)
		Shop.promptProduct(player, "MythicCrate")
	end)

	-- Global stock counter (same for everyone, server-rendered).
	local gui = UIKit.surface(shrine.Counter, { PixelsPerStud = 50, Name = "StockUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 6, false, Enum.HorizontalAlignment.Center)
	UIKit.text({ Text = "MYTHIC FEATURED CRATE", TextSize = 28, Font = T.FontHeavy, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Parent = root })
	local count = UIKit.text({ Text = "", TextSize = 64, Font = T.FontHeavy, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 72), Parent = root })
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 12)
	bar.BackgroundColor3 = T.SurfaceHi
	bar.BorderSizePixel = 0
	UIKit.corner(bar, UDim.new(0, 4))
	bar.Parent = root
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = crate.Color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	UIKit.corner(fill, UDim.new(0, 4))
	fill.Parent = bar
	local sub = UIKit.text({ Text = "", TextSize = 18, Font = T.FontMedium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Parent = root })
	local function render(remaining: number)
		count.Text = UIKit.formatNumber(remaining)
		fill.Size = UDim2.fromScale(remaining / Config.Mythic.GlobalCap, 1)
		if remaining <= 0 then
			sub.Text = "SOLD OUT — thanks for playing Season " .. Config.Mythic.Season
			coinPrompt.Enabled = false
			robuxPrompt.Enabled = false
		else
			sub.Text = "left worldwide of " .. UIKit.formatNumber(Config.Mythic.GlobalCap) .. "  ·  every skin also drops from play"
		end
	end
	render(MythicStock.remaining())
	MythicStock.Changed:Connect(render)

	oddsBoard(shrine.OddsBoard, crate, "Featured odds")
end

local function buildPasses()
	local f = Parts.folder(propsFolder, "Passes")
	local showcase = { VIP = "vip_aurum", Founder = "founder" }
	for _, key in Config.GamePassOrder do
		local pedestal = lobby.East.PassPedestals[key]
		local pass = Config.GamePasses[key]
		if pedestal and pass then
			local at = Displays.anchorPoint(pedestal)
			local adornee: BasePart
			if showcase[key] then
				adornee = Displays.ball(f, at, showcase[key], 2.6)
			else
				local m = Displays.crate(f, at, if key == "DoubleCoins" then Config.Colors.Gold else Color3.fromHex("#FF4FA3"), 2.2)
				Displays.bob(m)
				adornee = m.PrimaryPart :: BasePart
			end
			local price = if pass.Id == 0 then "Coming soon" else pass.Robux .. " Robux"
			Displays.card(adornee, 3, pass.Name, pass.Desc, price, T.Info)
			local prompt = Parts.prompt(pedestal, "Get pass", pass.Name, { Distance = 9 })
			prompt.Enabled = pass.Id ~= 0
			prompt.Triggered:Connect(function(player)
				Shop.promptPass(player, key)
			end)
		end
	end
	for key, pad in lobby.East.CoinPackPads do
		local product = Config.DevProducts[key]
		if product then
			local prompt = Parts.prompt(pad, string.format("%s coins · %d Robux", UIKit.formatNumber(product.Coins or 0), product.Robux), product.Name, { Distance = 9 })
			prompt.Enabled = product.Id ~= 0
			prompt.Triggered:Connect(function(player)
				Shop.promptProduct(player, key)
			end)
		end
	end
end

local function buildUpgrades()
	for stat, button in lobby.East.Upgrades.Buttons do
		local def
		for _, s in Config.Upgrades.Stats do
			if s.Id == stat then
				def = s
			end
		end
		if def then
			local prompt = Parts.prompt(button, "Upgrade " .. def.Name, def.Desc, { Distance = 8 })
			prompt:SetAttribute("Upgrade", stat)
			prompt.Triggered:Connect(function(player)
				Shop.upgrade(player, stat)
			end)
		end
	end
end

function Shop.start(l: LobbyTypes.Lobby)
	lobby = l
	propsFolder = Parts.folder(lobby.Model, "ShopProps")
	buildRotation()
	buildCrates()
	buildMythic()
	buildPasses()
	buildUpgrades()

	Net.event("ShopAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)

	-- Midnight UTC: new Coin Shop rotation.
	task.spawn(function()
		while true do
			task.wait(30)
			if today() ~= rotationDay then
				buildRotation()
				Net.event("Fx"):FireAllClients("shopRotated", {})
			end
		end
	end)
end

return Shop

--!strict
-- Robux: gamepass ownership (checked on join + live purchases) and developer
-- product receipts. Receipts are idempotent (purchase ids stored on the
-- profile) and only acknowledged after the grant is saved.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Data = require(script.Parent:WaitForChild("Data"))
local CreatorCodes = require(script.Parent:WaitForChild("CreatorCodes"))
local MythicStock = require(script.Parent:WaitForChild("MythicStock"))
local LimitedStock = require(script.Parent:WaitForChild("LimitedStock"))
local Social = require(script.Parent:WaitForChild("Social"))

local Monetization = {}

-- Set by Main once the Shop exists (avoids a require cycle).
local openFeaturedCrate: ((Player) -> boolean)? = nil

function Monetization.setCrateOpener(fn: (Player) -> boolean)
	openFeaturedCrate = fn
end

-- What each pass unlocks (category -> item ids). Everything here is cosmetic.
local passGrants: { [string]: { [string]: { string } } } = {
	VIP = { Skins = { "vip_aurum" } },
	Founder = { Skins = { "founder" } },
	TourCollection = { Skins = { "tour_black", "tour_pearl", "tour_graphite" } },
	Heritage = { Skins = { "heritage_cream", "heritage_forest", "heritage_oxblood" } },
	MembersClub = { Trails = { "members_contrail" }, Arrows = { "members_line" } },
	BallStudio = { Skins = { "studio" } },
}
Monetization.PassGrants = passGrants

local function applyPass(player: Player, key: string)
	local session = Data.get(player)
	if not session then
		return
	end
	session.Passes[key] = true
	player:SetAttribute("Pass_" .. key, true)
	local grants: { [string]: { string } } = passGrants[key] or {}
	for category, ids in grants do
		for _, id in ids do
			if category == "Skins" then
				Data.grantSkin(player, id)
			else
				Data.grant(player, category, id)
			end
		end
	end
	Data.push(player)
	Social.updateNametag(player)
end

local function checkPasses(player: Player)
	for key, pass in Config.GamePasses do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns then
				applyPass(player, key)
			end
		end
	end
end

local function productByAsset(id: number): (string?, any)
	for key, product in Config.DevProducts do
		if product.Id == id and id ~= 0 then
			return key, product
		end
	end
	return nil, nil
end

-- The limited ball: reserve the next copy worldwide (its number is the buyer's serial). A
-- second copy, or one bought as the last sold elsewhere, pays coins so nothing is lost.
local function grantLimited(player: Player)
	local id = Config.Limited.Skin
	local session = Data.get(player)
	local ok, serial = false, 0
	if session and not Data.owns(player, "Skins", id) then
		ok, serial = LimitedStock.reserve()
	end
	if not session or not ok then
		Data.addCoins(player, Config.Limited.RefundCoins, "refund")
		local reason = if session and Data.owns(player, "Skins", id) then "You already own this ball"
			elseif LimitedStock.remaining() <= 0 then "The last copy just sold"
			else "Couldn't reserve a copy right now"
		Net.event("Toast"):FireClient(player, reason .. ". You received " .. Config.Limited.RefundCoins .. " coins instead.", Config.Colors.Gold)
		return
	end
	local name = Config.DevProducts[Config.Limited.Product].Name
	session.Profile.Serials[id] = serial
	Data.grant(player, "Skins", id)
	Data.equip(player, "Skins", id)
	Data.markDirty(player)
	Data.push(player)
	Net.event("Toast"):FireClient(player, string.format("%s No. %d of %d is yours", name, serial, LimitedStock.Cap), Config.Colors.Gold)
	Net.event("Fx"):FireAllClients("announce", {
		Text = string.format("%s just got %s No. %d of %d!", player.DisplayName, name, serial, LimitedStock.Cap),
		Color = Config.Colors.Gold,
	})
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local session = Data.get(player)
	if not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if Data.hasReceipt(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key, product = productByAsset(info.ProductId)
	if not key then
		warn("[UltimateGolf] unknown product", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if key == "MythicCrate" then
		local opener = openFeaturedCrate
		if MythicStock.reserve() and opener then
			opener(player)
		else
			-- Couldn't reserve a crate (sold out, or the stock service is unreachable):
			-- pay the coin price instead so the purchase is never lost.
			Data.addCoins(player, Config.Mythic.CoinPrice, "refund")
			local reason = if MythicStock.remaining() <= 0 then "The Mythic crate just sold out" else "Couldn't reserve a Mythic crate right now"
			Net.event("Toast"):FireClient(player, reason .. ". You received " .. Config.Mythic.CoinPrice .. " coins instead.", Config.Colors.Gold)
		end
	elseif key == Config.Limited.Product then
		grantLimited(player)
	elseif product.Coins then
		Data.addCoins(player, product.Coins, "purchase")
		Net.event("Fx"):FireClient(player, "coins", { Amount = product.Coins })
	end
	CreatorCodes.record(player, 0, info.CurrencySpent or product.Robux or 0)
	Data.addReceipt(player, purchaseId)
	if not Data.saveNow(player) then
		-- Roblox retries later; the stored receipt id prevents a double grant.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in Config.GamePasses do
			if pass.Id == passId then
				applyPass(player, key)
				CreatorCodes.record(player, 0, pass.Robux)
				Net.event("Toast"):FireClient(player, "Thanks for supporting Ultimate Golf! " .. pass.Name .. " unlocked.", Config.Colors.Gold)
			end
		end
	end)
	Data.Loaded:Connect(function(player: Player)
		checkPasses(player)
	end)
end

return Monetization

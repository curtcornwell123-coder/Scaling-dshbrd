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
local Social = require(script.Parent:WaitForChild("Social"))

local Monetization = {}

-- Set by Main once the Shop exists (avoids a require cycle).
local openFeaturedCrate: ((Player) -> boolean)? = nil

function Monetization.setCrateOpener(fn: (Player) -> boolean)
	openFeaturedCrate = fn
end

local passSkins = { VIP = "vip_aurum", Founder = "founder" }

local function applyPass(player: Player, key: string)
	local session = Data.get(player)
	if not session then
		return
	end
	session.Passes[key] = true
	player:SetAttribute("Pass_" .. key, true)
	local skin = passSkins[key]
	if skin then
		Data.grantSkin(player, skin)
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
		warn("[ChaosGolf] unknown product", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if key == "MythicCrate" then
		local opener = openFeaturedCrate
		if MythicStock.reserve() and opener then
			opener(player)
		else
			-- Sold out between prompt and payment: pay the coin price instead.
			Data.addCoins(player, Config.Mythic.CoinPrice, "refund")
			Net.event("Toast"):FireClient(player, "Sold out! You received " .. Config.Mythic.CoinPrice .. " coins instead.", Config.Colors.Gold)
		end
	elseif product.Coins then
		Data.addCoins(player, product.Coins, "purchase")
		Net.event("Fx"):FireClient(player, "coins", { Amount = product.Coins })
	end
	CreatorCodes.record(player, 0, info.CurrencySpent or product.Robux or 0)
	Data.addReceipt(player, purchaseId)
	Data.saveNow(player)
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
				Net.event("Toast"):FireClient(player, "Thanks for supporting Chaos Golf! " .. pass.Name .. " unlocked.", Config.Colors.Gold)
			end
		end
	end)
	Data.Loaded:Connect(function(player: Player)
		checkPasses(player)
	end)
end

return Monetization

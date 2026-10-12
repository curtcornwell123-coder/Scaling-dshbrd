--!strict
-- Cyber Swarm: game pass / developer product ids (created off sale; put them on sale in
-- Creator Hub once your scripts use them). ModuleScript for ServerScriptService.
--
--   local Monetization = require(path.to.Monetization)
--   if Monetization.owns(player, Monetization.Passes.VIP) then ... end
--   Monetization.onProduct(Monetization.Products.CoinPackSmall, function(player, receipt)
--       -- grant it AND save it (receipt.PurchaseId lets you skip repeats), then:
--       return true
--   end)
--
-- This module sets MarketplaceService.ProcessReceipt: a game may only have one, so route every
-- product through onProduct instead of assigning ProcessReceipt anywhere else.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Monetization = {}

Monetization.Passes = {
	VIP = 2026994730, -- VIP
	DoubleCoins = 2026574737, -- 2x Coins
	ExtraRobotSlot = 2025806717, -- Extra Robot Slot
	DoubleGameSpeed = 2025716691, -- 2x Game Speed
}

Monetization.Products = {
	CoinPackSmall = 3717826967, -- Coin Pack (Small)
	CoinPackMedium = 3717826972, -- Coin Pack (Medium)
	CoinPackLarge = 3717826980, -- Coin Pack (Large)
}

local owned: { [Player]: { [number]: boolean } } = {}

function Monetization.owns(player: Player, passId: number): boolean
	local cache = owned[player]
	if not cache then
		cache = {}
		owned[player] = cache
	end
	local known = cache[passId]
	if known ~= nil then
		return known
	end
	local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	if not ok then
		return false -- not cached, so the next check retries
	end
	cache[passId] = has
	return has
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	local cache = owned[player]
	if purchased and cache then
		cache[passId] = true
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	owned[player] = nil
end)

type Handler = (player: Player, receipt: { [string]: any }) -> boolean
local handlers: { [number]: Handler } = {}

function Monetization.onProduct(productId: number, handler: Handler)
	handlers[productId] = handler
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local handler = handlers[receipt.ProductId]
	if not player or not handler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player, receipt)
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

return Monetization

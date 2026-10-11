--!strict
-- Merge A Egg: game pass / developer product ids (created off sale; put them on sale in
-- Creator Hub once your scripts use them). ModuleScript for ServerScriptService.
--
--   local Monetization = require(path.to.Monetization)
--   if Monetization.owns(player, Monetization.Passes.VIP) then ... end
--   Monetization.onProduct(Monetization.Products.DoubleServerLuck15, function(player, receipt)
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
	VIP = 2026244703, -- VIP
	DoubleSpeed = 2026454703, -- 2x Speed
	DoubleEggLuck = 2025512707, -- 2x Egg Luck
	AutoMerge = 2025572676, -- Auto Merge
	ExtraMerger = 2026904674, -- Extra Merger
}

Monetization.Products = {
	DoubleServerLuck15 = 3717826924, -- 2x Server Luck (15 min)
	SpeedBoost15 = 3717826929, -- Speed Boost (15 min)
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

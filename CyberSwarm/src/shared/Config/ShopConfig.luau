--!strict
--[[
	ShopConfig
	Robux developer products sold in Market Bay 01, plus the Season Pass premium product.
	productId values come from Creator Hub (Monetization > Developer Products). A productId of 0
	means "not set up yet": the shop shows the item as unavailable and ConfigValidator warns.
	Prices are never stored here; the UI reads the live price from MarketplaceService.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local ShopConfig = {}

local products: { [string]: Types.ShopProduct } = {
	CoinsSmall = {
		id = "CoinsSmall",
		productId = 0,
		name = "Coin Crate",
		kind = "Coins",
		reward = { coins = 500 },
		description = "500 coins",
	},
	CoinsMedium = {
		id = "CoinsMedium",
		productId = 0,
		name = "Coin Pallet",
		kind = "Coins",
		reward = { coins = 1500 },
		description = "1,500 coins",
	},
	CoinsLarge = {
		id = "CoinsLarge",
		productId = 0,
		name = "Coin Container",
		kind = "Coins",
		reward = { coins = 5000 },
		description = "5,000 coins",
	},
	GemsSmall = {
		id = "GemsSmall",
		productId = 0,
		name = "Gem Pouch",
		kind = "Gems",
		reward = { gems = 25 },
		description = "25 gems",
	},
	GemsLarge = {
		id = "GemsLarge",
		productId = 0,
		name = "Gem Vault",
		kind = "Gems",
		reward = { gems = 120 },
		description = "120 gems",
	},
	StarterBundle = {
		id = "StarterBundle",
		productId = 0,
		name = "Starter Bundle",
		kind = "Bundle",
		reward = { coins = 1000, gems = 40, troopId = "Medic" },
		description = "1,000 coins, 40 gems and the Medic troop",
	},
	SeasonPremium = {
		id = "SeasonPremium",
		productId = 0,
		name = "Season Pass Premium",
		kind = "SeasonPremium",
		reward = {},
		description = "Unlocks the premium track for this season",
	},
}
ShopConfig.Products = products

-- Display order in the Robux shop (SeasonPremium is sold from the Season Pass bay).
ShopConfig.Order = { "StarterBundle", "CoinsSmall", "CoinsMedium", "CoinsLarge", "GemsSmall", "GemsLarge" }

-- Optional: a game pass that also unlocks premium (0 = not used).
ShopConfig.PremiumGamePassId = 0

function ShopConfig.byProductId(productId: number): Types.ShopProduct?
	if productId == 0 then
		return nil
	end
	for _, product in products do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

return TableUtil.deepFreeze(ShopConfig)

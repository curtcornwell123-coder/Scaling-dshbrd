--!strict
-- Crates. The East-room shop sells four category crates (Ball Skins, Trails,
-- Knockout Effects, Arrow Skins), each openable with Coins or a crate key from
-- the 14-day login calendar. The isolated Mythic Featured Crate (global stock)
-- and the practice-room token crates are separate.
-- Odds are shown in-world on every crate. Pity: after PityAt opens without a
-- PityRarity-or-better drop, the next open is guaranteed one.

local Cosmetics = require(script.Parent:WaitForChild("Cosmetics"))
local Skins = require(script.Parent:WaitForChild("Skins"))

local Crates = {}

export type Crate = {
	Id: string,
	Name: string,
	Category: string, -- Cosmetics category it drops
	Pool: string, -- item Source it draws from
	Currency: string, -- "Coins" | "Tokens:<Minigame>"
	Price: number,
	Keyed: boolean, -- can be opened with a crate key
	Odds: { [string]: number }, -- rarity -> percent (sums to 100)
	PityAt: number,
	PityRarity: string,
	Color: Color3,
}

local standardOdds = { Common = 52, Rare = 30, Epic = 13, Legendary = 4.2, Mythic = 0.8 }

local crates: { [string]: Crate } = {
	Skins = {
		Id = "Skins",
		Name = "Ball Skin Crate",
		Category = "Skins",
		Pool = "Shop",
		Currency = "Coins",
		Price = 600,
		Keyed = true,
		Odds = { Common = 55, Rare = 28, Epic = 12, Legendary = 4.4, Mythic = 0.6 },
		PityAt = 35,
		PityRarity = "Legendary",
		Color = Cosmetics.CategoryInfo.Skins.Color,
	},
	Trails = {
		Id = "Trails",
		Name = "Trail Crate",
		Category = "Trails",
		Pool = "Crate",
		Currency = "Coins",
		Price = 500,
		Keyed = true,
		Odds = standardOdds,
		PityAt = 30,
		PityRarity = "Legendary",
		Color = Cosmetics.CategoryInfo.Trails.Color,
	},
	Knockouts = {
		Id = "Knockouts",
		Name = "Knockout Crate",
		Category = "Knockouts",
		Pool = "Crate",
		Currency = "Coins",
		Price = 500,
		Keyed = true,
		Odds = standardOdds,
		PityAt = 30,
		PityRarity = "Legendary",
		Color = Cosmetics.CategoryInfo.Knockouts.Color,
	},
	Arrows = {
		Id = "Arrows",
		Name = "Arrow Crate",
		Category = "Arrows",
		Pool = "Crate",
		Currency = "Coins",
		Price = 400,
		Keyed = true,
		Odds = standardOdds,
		PityAt = 30,
		PityRarity = "Legendary",
		Color = Cosmetics.CategoryInfo.Arrows.Color,
	},
	Featured = {
		Id = "Featured",
		Name = "Mythic Featured Crate",
		Category = "Skins",
		Pool = "Featured",
		Currency = "Coins",
		Price = 6000, -- also sold for Robux (Config.DevProducts.MythicCrate)
		Keyed = false,
		Odds = { Epic = 55, Legendary = 35, Mythic = 10 },
		PityAt = 12,
		PityRarity = "Mythic",
		Color = Color3.fromHex("#FF2D55"),
	},
	Target = {
		Id = "Target",
		Name = "Bullseye Crate",
		Category = "Skins",
		Pool = "Token:Target",
		Currency = "Tokens:Target",
		Price = 12,
		Keyed = false,
		Odds = { Common = 50, Rare = 32, Epic = 14, Legendary = 4 },
		PityAt = 25,
		PityRarity = "Legendary",
		Color = Color3.fromHex("#E63946"),
	},
	Drive = {
		Id = "Drive",
		Name = "Long-Drive Crate",
		Category = "Skins",
		Pool = "Token:Drive",
		Currency = "Tokens:Drive",
		Price = 12,
		Keyed = false,
		Odds = { Common = 50, Rare = 32, Epic = 14, Legendary = 4 },
		PityAt = 25,
		PityRarity = "Legendary",
		Color = Color3.fromHex("#00B4FF"),
	},
	Hazard = {
		Id = "Hazard",
		Name = "Hazard Crate",
		Category = "Skins",
		Pool = "Token:Hazard",
		Currency = "Tokens:Hazard",
		Price = 12,
		Keyed = false,
		Odds = { Common = 50, Rare = 32, Epic = 14, Legendary = 4 },
		PityAt = 25,
		PityRarity = "Legendary",
		Color = Color3.fromHex("#FFB703"),
	},
}

Crates.ById = crates
Crates.ShopOrder = { "Skins", "Trails", "Knockouts", "Arrows" }

-- Duplicate drops refund this multiple of the crate's price, in its currency.
Crates.DuplicateRefund = { Common = 0.15, Rare = 0.35, Epic = 0.75, Legendary = 1.5, Mythic = 3 } :: { [string]: number }

-- Token skins can also be bought outright at the practice kiosk.
Crates.TokenDirectPrice = { Common = 8, Rare = 20, Epic = 45, Legendary = 90 } :: { [string]: number }

function Crates.get(id: string): Crate?
	return crates[id]
end

function Crates.poolByRarity(crate: Crate): { [string]: { Cosmetics.Item } }
	local out: { [string]: { Cosmetics.Item } } = {}
	for _, item in Cosmetics.withSource(crate.Category, crate.Pool) do
		out[item.Rarity] = out[item.Rarity] or {}
		table.insert(out[item.Rarity], item)
	end
	return out
end

function Crates.refund(crate: Crate, rarity: string): number
	return math.max(1, math.floor(crate.Price * (Crates.DuplicateRefund[rarity] or 0.15)))
end

-- Rolls an item. `pity` = opens since the last PityRarity-or-better drop;
-- returns the item and the new pity counter.
function Crates.roll(crate: Crate, rng: Random, pity: number): (Cosmetics.Item, number)
	local pools = Crates.poolByRarity(crate)
	local pityOrder = Skins.Rarities[crate.PityRarity].Order
	local forced = pity + 1 >= crate.PityAt

	local function pick(eligible: (string) -> boolean): string?
		local total = 0
		for _, r in Skins.RarityOrder do
			local pct = crate.Odds[r] or 0
			if pct > 0 and pools[r] and eligible(r) then
				total += pct
			end
		end
		if total <= 0 then
			return nil
		end
		local roll = rng:NextNumber() * total
		local last: string? = nil
		for _, r in Skins.RarityOrder do
			local pct = crate.Odds[r] or 0
			if pct > 0 and pools[r] and eligible(r) then
				last = r
				roll -= pct
				if roll <= 0 then
					return r
				end
			end
		end
		return last
	end

	local rarity: string? = nil
	if forced then
		rarity = pick(function(r)
			return Skins.Rarities[r].Order >= pityOrder
		end)
	end
	if not rarity then
		rarity = pick(function()
			return true
		end)
	end
	local pool = pools[rarity :: string]
	local item = pool[rng:NextInteger(1, #pool)]
	local newPity = if Skins.Rarities[item.Rarity].Order >= pityOrder then 0 else pity + 1
	return item, newPity
end

function Crates.oddsLines(crate: Crate): { { Rarity: string, Percent: number } }
	local out = {}
	for _, r in Skins.RarityOrder do
		local pct = crate.Odds[r] or 0
		if pct > 0 then
			table.insert(out, { Rarity = r, Percent = pct })
		end
	end
	return out
end

return Crates

--!strict
-- Central catalog config. The catalog UI (client/modules/Catalog) is fully
-- data-driven: it renders whatever tabs and items this module returns, so new
-- skins, crates or passes appear automatically once added to their registries.
-- Prices and ownership are always re-validated by the server (Lobby/Shop).

local Config = require(script.Parent:WaitForChild("Config"))
local Cosmetics = require(script.Parent:WaitForChild("Cosmetics"))
local Crates = require(script.Parent:WaitForChild("Crates"))
local Skins = require(script.Parent:WaitForChild("Skins"))

local ShopCatalog = {}

export type Price = { Amount: number, Currency: string } -- "Coins" | "Robux" | "Key"
export type Preview = { Kind: string, Ref: string } -- "Ball" (skin id) | "Trail" | "Arrow" | "Knockout" | "Crate" (crate id) | "Pass" | "Coins"

export type Item = {
	Key: string, -- unique within a tab
	Title: string,
	Subtitle: string,
	Rarity: string?,
	Accent: Color3?, -- small indicator colour only
	Price: Price?,
	Preview: Preview,
	Action: string, -- ShopAction name
	A: any,
	B: any,
	Category: string?, -- for ownership / equip state of cosmetics
	ItemId: string?,
}

export type Tab = { Id: string, Name: string, Items: (profile: any) -> { Item }, Hint: string }

local function rarityColor(r: string): Color3
	return Skins.Rarities[r].Color
end

local function skinItem(skin: Skins.Skin): Item
	return {
		Key = skin.Id,
		Title = skin.Name,
		Subtitle = skin.Rarity .. " ball skin",
		Rarity = skin.Rarity,
		Accent = rarityColor(skin.Rarity),
		Price = { Amount = Skins.price(skin.Id), Currency = "Coins" },
		Preview = { Kind = "Ball", Ref = skin.Id },
		Action = "buySkin",
		A = skin.Id,
		Category = "Skins",
		ItemId = skin.Id,
	}
end

local function cosmeticItem(category: string, item: Cosmetics.Item): Item
	local info = Cosmetics.CategoryInfo[category]
	local kind = if category == "Skins" then "Ball" elseif category == "Trails" then "Trail" elseif category == "Arrows" then "Arrow" else "Knockout"
	return {
		Key = category .. ":" .. item.Id,
		Title = item.Name,
		Subtitle = item.Rarity .. " " .. string.lower(info.Singular),
		Rarity = item.Rarity,
		Accent = rarityColor(item.Rarity),
		Price = nil,
		Preview = { Kind = kind, Ref = item.Id },
		Action = "equip",
		A = category,
		B = item.Id,
		Category = category,
		ItemId = item.Id,
	}
end

ShopCatalog.Tabs = {
	{
		Id = "Featured",
		Name = "Today",
		Hint = "Today's Coin Shop rotation · refreshes at 00:00 UTC",
		Items = function(_profile)
			local out = {}
			for _, skin in Skins.shopRotation(math.floor(os.time() / 86400), 12) do
				table.insert(out, skinItem(skin))
			end
			return out
		end,
	},
	{
		Id = "Crates",
		Name = "Crates",
		Hint = "Open with Coins or a crate key from the Daily Rewards calendar",
		Items = function(profile)
			local out = {}
			for _, id in Crates.ShopOrder do
				local crate = Crates.get(id) :: Crates.Crate
				local keys = if profile and profile.Keys then profile.Keys[id] or 0 else 0
				table.insert(out, {
					Key = id,
					Title = crate.Name,
					Subtitle = Cosmetics.CategoryInfo[crate.Category].Name .. (if keys > 0 then string.format(" · %d key%s", keys, if keys == 1 then "" else "s") else ""),
					Accent = crate.Color,
					Price = if keys > 0 then { Amount = 1, Currency = "Key" } else { Amount = crate.Price, Currency = "Coins" },
					Preview = { Kind = "Crate", Ref = id },
					Action = "openCrate",
					A = id,
				})
			end
			return out
		end,
	},
	{
		Id = "Locker",
		Name = "Locker",
		Hint = "Everything you own · select to equip",
		Items = function(profile)
			local out = {}
			for _, category in Cosmetics.Categories do
				local owned = if profile and profile.Owned then profile.Owned[category] or {} else {}
				local list = table.clone(Cosmetics.list(category))
				table.sort(list, function(a, b)
					local ra, rb = Skins.Rarities[a.Rarity].Order, Skins.Rarities[b.Rarity].Order
					if ra ~= rb then
						return ra > rb
					end
					return a.Order < b.Order
				end)
				for _, item in list do
					if owned[item.Id] then
						table.insert(out, cosmeticItem(category, item))
					end
				end
			end
			return out
		end,
	},
	{
		Id = "Store",
		Name = "Passes",
		Hint = "Optional support. Nothing here wins matches: upgrades are off in Ranked",
		Items = function(_profile)
			local out = {}
			for _, key in Config.GamePassOrder do
				local pass = Config.GamePasses[key]
				table.insert(out, {
					Key = "pass:" .. key,
					Title = pass.Name,
					Subtitle = pass.Desc,
					Accent = Config.Colors.Gold,
					Price = { Amount = pass.Robux, Currency = "Robux" },
					Preview = { Kind = "Pass", Ref = key },
					Action = "buyPass",
					A = key,
				})
			end
			for _, key in { "Coins1", "Coins2", "Coins3", "Coins4" } do
				local product = Config.DevProducts[key]
				table.insert(out, {
					Key = "product:" .. key,
					Title = product.Name,
					Subtitle = string.format("%s coins", tostring(product.Coins or 0)),
					Accent = Config.Colors.Gold,
					Price = { Amount = product.Robux, Currency = "Robux" },
					Preview = { Kind = "Coins", Ref = key },
					Action = "buyProduct",
					A = key,
				})
			end
			return out
		end,
	},
} :: { Tab }

-- Locker sub-filters shown as chips above the grid.
ShopCatalog.LockerFilters = { "All", "Skins", "Trails", "Knockouts", "Arrows" }

return ShopCatalog

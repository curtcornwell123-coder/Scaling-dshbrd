--!strict
-- Shared game configuration: rarities, crates, pets and drop odds.
-- Edit this file to rebalance the game; server and client both read it.

local Config = {}

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type Rarity = {
	Id: RarityId,
	DisplayName: string,
	Color: Color3,
	Order: number,
	SellMultiplier: number,
}

export type Pet = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	Power: number, -- coins per second while equipped
}

export type Crate = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Price: number,
	-- Percent chance per rarity. Must add up to 100.
	Odds: { [RarityId]: number },
}

Config.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" } :: { RarityId }

Config.Rarities = {
	Common = {
		Id = "Common",
		DisplayName = "Common",
		Color = Color3.fromRGB(70, 200, 90), -- green
		Order = 1,
		SellMultiplier = 5,
	},
	Rare = {
		Id = "Rare",
		DisplayName = "Rare",
		Color = Color3.fromRGB(60, 140, 255), -- blue
		Order = 2,
		SellMultiplier = 8,
	},
	Epic = {
		Id = "Epic",
		DisplayName = "Epic",
		Color = Color3.fromRGB(170, 80, 255), -- purple
		Order = 3,
		SellMultiplier = 12,
	},
	Legendary = {
		Id = "Legendary",
		DisplayName = "Legendary",
		Color = Color3.fromRGB(255, 195, 40), -- gold
		Order = 4,
		SellMultiplier = 20,
	},
	Mythic = {
		Id = "Mythic",
		DisplayName = "Mythic",
		Color = Color3.fromRGB(255, 45, 60), -- red
		Order = 5,
		SellMultiplier = 30,
	},
} :: { [RarityId]: Rarity }

Config.Pets = {
	-- Common (green)
	{ Id = "Puppy", DisplayName = "Puppy", Rarity = "Common", Power = 1 },
	{ Id = "Kitty", DisplayName = "Kitty", Rarity = "Common", Power = 1 },
	{ Id = "Bunny", DisplayName = "Bunny", Rarity = "Common", Power = 2 },
	{ Id = "Duckling", DisplayName = "Duckling", Rarity = "Common", Power = 2 },
	-- Rare (blue)
	{ Id = "Fox", DisplayName = "Fox", Rarity = "Rare", Power = 5 },
	{ Id = "Owl", DisplayName = "Owl", Rarity = "Rare", Power = 6 },
	{ Id = "Penguin", DisplayName = "Penguin", Rarity = "Rare", Power = 7 },
	-- Epic (purple)
	{ Id = "Dragonling", DisplayName = "Dragonling", Rarity = "Epic", Power = 20 },
	{ Id = "Unicorn", DisplayName = "Unicorn", Rarity = "Epic", Power = 25 },
	{ Id = "PhoenixChick", DisplayName = "Phoenix Chick", Rarity = "Epic", Power = 30 },
	-- Legendary (gold)
	{ Id = "GoldenGriffin", DisplayName = "Golden Griffin", Rarity = "Legendary", Power = 100 },
	{ Id = "CrystalWolf", DisplayName = "Crystal Wolf", Rarity = "Legendary", Power = 125 },
	-- Mythic (red)
	{ Id = "InfernoDragon", DisplayName = "Inferno Dragon", Rarity = "Mythic", Power = 500 },
	{ Id = "VoidKraken", DisplayName = "Void Kraken", Rarity = "Mythic", Power = 750 },
} :: { Pet }

Config.Crates = {
	{
		Id = "Green",
		DisplayName = "Green Crate",
		Color = Color3.fromRGB(70, 200, 90),
		Price = 100,
		Odds = { Common = 70, Rare = 22, Epic = 6, Legendary = 1.8, Mythic = 0.2 },
	},
	{
		Id = "Blue",
		DisplayName = "Blue Crate",
		Color = Color3.fromRGB(60, 140, 255),
		Price = 750,
		Odds = { Common = 40, Rare = 40, Epic = 15, Legendary = 4.5, Mythic = 0.5 },
	},
	{
		Id = "Purple",
		DisplayName = "Purple Crate",
		Color = Color3.fromRGB(170, 80, 255),
		Price = 4000,
		Odds = { Common = 10, Rare = 35, Epic = 42, Legendary = 11.5, Mythic = 1.5 },
	},
	{
		Id = "Gold",
		DisplayName = "Gold Crate",
		Color = Color3.fromRGB(255, 195, 40),
		Price = 20000,
		Odds = { Common = 0, Rare = 15, Epic = 40, Legendary = 40, Mythic = 5 },
	},
} :: { Crate }

-- Gameplay tuning
Config.StartingCoins = 150
Config.BaseCoinsPerSecond = 2
Config.MaxEquipped = 4
Config.MaxInventory = 200
Config.OpenCooldown = 1 -- seconds between crate opens (server enforced)

-- Lookup helpers ----------------------------------------------------------

local petsById: { [string]: Pet } = {}
local petsByRarity: { [RarityId]: { Pet } } = {}
for _, pet in Config.Pets do
	petsById[pet.Id] = pet
	local list = petsByRarity[pet.Rarity]
	if not list then
		list = {}
		petsByRarity[pet.Rarity] = list
	end
	table.insert(list, pet)
end

local cratesById: { [string]: Crate } = {}
for _, crate in Config.Crates do
	cratesById[crate.Id] = crate
end

function Config.GetPet(id: string): Pet?
	return petsById[id]
end

function Config.GetPetsOfRarity(rarity: RarityId): { Pet }
	return petsByRarity[rarity] or {}
end

function Config.GetCrate(id: string): Crate?
	return cratesById[id]
end

function Config.SellValue(pet: Pet): number
	return pet.Power * Config.Rarities[pet.Rarity].SellMultiplier
end

-- Rolls a pet from a crate using the given Random object.
function Config.Roll(crate: Crate, rng: Random): Pet
	local roll = rng:NextNumber(0, 100)
	local cumulative = 0
	local chosen: RarityId = "Common"
	for _, rarity in Config.RarityOrder do
		local chance = crate.Odds[rarity] or 0
		if chance > 0 then
			chosen = rarity
			cumulative += chance
			if roll < cumulative then
				break
			end
		end
	end
	local pool = Config.GetPetsOfRarity(chosen)
	return pool[rng:NextInteger(1, #pool)]
end

function Config.FormatNumber(n: number): string
	n = math.floor(n)
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local i = 1
	local value = n
	while math.abs(value) >= 1000 and i < #suffixes do
		value /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(n)
	end
	return string.format("%.1f%s", value, suffixes[i])
end

return Config

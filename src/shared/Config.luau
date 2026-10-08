--!strict
-- Shared game configuration: rarities, brainrots, conveyor odds, bases,
-- rebirths and monetization. Server and client both read this file.

local Config = {}

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

export type Rarity = {
	Id: RarityId,
	Color: Color3,
	Order: number,
	Scale: number, -- model size multiplier
	SpawnWeight: number, -- relative chance to appear on the conveyor
	Announce: boolean, -- tell the whole server when one spawns
}

export type Brainrot = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	Price: number,
	Income: number, -- cash per second while sitting in your base
	Color: Color3,
	Accent: Color3,
}

export type GamePass = {
	Key: string,
	Id: number, -- paste your gamepass ID here (0 = not set up yet)
	Name: string,
	Description: string,
}

export type Product = {
	Key: string,
	Id: number, -- paste your developer product ID here (0 = not set up yet)
	Name: string,
	Description: string,
}

Config.GameName = "Brainrot Heist"

local rarityOrder: { RarityId } = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Config.RarityOrder = rarityOrder

Config.Rarities = {
	Common = { Id = "Common", Color = Color3.fromRGB(70, 200, 90), Order = 1, Scale = 1, SpawnWeight = 60, Announce = false },
	Rare = { Id = "Rare", Color = Color3.fromRGB(60, 140, 255), Order = 2, Scale = 1.15, SpawnWeight = 25, Announce = false },
	Epic = { Id = "Epic", Color = Color3.fromRGB(170, 80, 255), Order = 3, Scale = 1.3, SpawnWeight = 10, Announce = false },
	Legendary = { Id = "Legendary", Color = Color3.fromRGB(255, 195, 40), Order = 4, Scale = 1.5, SpawnWeight = 4, Announce = true },
	Mythic = { Id = "Mythic", Color = Color3.fromRGB(255, 45, 60), Order = 5, Scale = 1.75, SpawnWeight = 0.9, Announce = true },
	Secret = { Id = "Secret", Color = Color3.fromRGB(20, 20, 20), Order = 6, Scale = 2, SpawnWeight = 0.1, Announce = true },
} :: { [RarityId]: Rarity }

-- Original characters. Add new ones here every update to keep players coming back.
Config.Brainrots = {
	-- Common
	{ Id = "NoodloDoodlo", DisplayName = "Noodlo Doodlo", Rarity = "Common", Price = 25, Income = 1, Color = Color3.fromRGB(245, 215, 120), Accent = Color3.fromRGB(200, 60, 40) },
	{ Id = "PizzarinoPizzaroni", DisplayName = "Pizzarino Pizzaroni", Rarity = "Common", Price = 50, Income = 2, Color = Color3.fromRGB(240, 170, 60), Accent = Color3.fromRGB(190, 30, 30) },
	{ Id = "SockGobblino", DisplayName = "Sock Gobblino", Rarity = "Common", Price = 80, Income = 3, Color = Color3.fromRGB(230, 230, 230), Accent = Color3.fromRGB(60, 160, 220) },
	{ Id = "FrigoBurrito", DisplayName = "Frigo Burrito", Rarity = "Common", Price = 120, Income = 4, Color = Color3.fromRGB(200, 160, 110), Accent = Color3.fromRGB(120, 200, 255) },
	-- Rare
	{ Id = "BananitoBandito", DisplayName = "Bananito Bandito", Rarity = "Rare", Price = 500, Income = 10, Color = Color3.fromRGB(255, 225, 50), Accent = Color3.fromRGB(30, 30, 30) },
	{ Id = "CroissantoFurioso", DisplayName = "Croissanto Furioso", Rarity = "Rare", Price = 900, Income = 16, Color = Color3.fromRGB(215, 150, 70), Accent = Color3.fromRGB(255, 80, 40) },
	{ Id = "TostinoTurbino", DisplayName = "Tostino Turbino", Rarity = "Rare", Price = 1500, Income = 25, Color = Color3.fromRGB(190, 120, 60), Accent = Color3.fromRGB(80, 80, 90) },
	-- Epic
	{ Id = "CactussoBossino", DisplayName = "Cactusso Bossino", Rarity = "Epic", Price = 5000, Income = 60, Color = Color3.fromRGB(60, 170, 70), Accent = Color3.fromRGB(255, 120, 200) },
	{ Id = "WaffelinoWizardo", DisplayName = "Waffelino Wizardo", Rarity = "Epic", Price = 9000, Income = 100, Color = Color3.fromRGB(230, 180, 90), Accent = Color3.fromRGB(90, 50, 200) },
	{ Id = "GnocchiNinjaro", DisplayName = "Gnocchi Ninjaro", Rarity = "Epic", Price = 15000, Income = 150, Color = Color3.fromRGB(250, 240, 200), Accent = Color3.fromRGB(20, 20, 30) },
	-- Legendary
	{ Id = "PinguinoHackerino", DisplayName = "Pinguino Hackerino", Rarity = "Legendary", Price = 75000, Income = 500, Color = Color3.fromRGB(40, 40, 50), Accent = Color3.fromRGB(0, 255, 120) },
	{ Id = "LasagnaLightningo", DisplayName = "Lasagna Lightningo", Rarity = "Legendary", Price = 200000, Income = 1200, Color = Color3.fromRGB(220, 90, 40), Accent = Color3.fromRGB(255, 240, 80) },
	-- Mythic
	{ Id = "DragoniSpaghettoni", DisplayName = "Dragoni Spaghettoni", Rarity = "Mythic", Price = 1500000, Income = 6000, Color = Color3.fromRGB(200, 30, 30), Accent = Color3.fromRGB(255, 210, 120) },
	{ Id = "MeatballoSupremo", DisplayName = "Meatballo Supremo", Rarity = "Mythic", Price = 4000000, Income = 15000, Color = Color3.fromRGB(120, 60, 40), Accent = Color3.fromRGB(255, 255, 255) },
	-- Secret
	{ Id = "IlCosmicoCannolo", DisplayName = "Il Cosmico Cannolo", Rarity = "Secret", Price = 50000000, Income = 250000, Color = Color3.fromRGB(30, 10, 60), Accent = Color3.fromRGB(255, 120, 255) },
} :: { Brainrot }

-- Mutations ----------------------------------------------------------------
-- Any brainrot on the conveyor can roll a mutation. Mutations multiply both
-- the price and the income, and change how it looks. Server Luck boosts them.

export type Mutation = {
	Id: string,
	DisplayName: string,
	Chance: number, -- percent per conveyor spawn
	Multiplier: number,
	Color: Color3,
}

Config.Mutations = {
	{ Id = "Gold", DisplayName = "Gold", Chance = 5, Multiplier = 2, Color = Color3.fromRGB(255, 200, 50) },
	{ Id = "Diamond", DisplayName = "Diamond", Chance = 2, Multiplier = 3, Color = Color3.fromRGB(140, 230, 255) },
	{ Id = "Lava", DisplayName = "Lava", Chance = 0.8, Multiplier = 5, Color = Color3.fromRGB(255, 100, 20) },
	{ Id = "Rainbow", DisplayName = "Rainbow", Chance = 0.3, Multiplier = 10, Color = Color3.fromRGB(255, 120, 255) },
} :: { Mutation }

-- Economy ------------------------------------------------------------------

Config.StartingCash = 100
Config.SellRatio = 0.5 -- selling returns this share of the buy price

-- Conveyor -----------------------------------------------------------------

Config.ConveyorSpawnInterval = 3 -- seconds between new brainrots
Config.ConveyorTravelTime = 45 -- seconds to ride from one end to the other
Config.ServerLuckMultiplier = 2 -- doubles the spawn weight of Rare and better (Mythic 0.9% -> ~1.3%)
Config.ServerLuckDuration = 15 * 60

-- Bases --------------------------------------------------------------------

Config.PlotCount = 8 -- also set Max Players to 8 in Game Settings
Config.BaseSlots = 10
Config.VipSlots = 2 -- extra slots for VIP owners
Config.LockDuration = 60
Config.LongerLockDuration = 120 -- with the Longer Lock gamepass
Config.LockCooldown = 30 -- vulnerable window after a lock ends

-- Walls --------------------------------------------------------------------
-- Everyone starts with a low fence that thieves can hop over. Players jump
-- about 7 studs high, so level 3 is the first wall nobody can jump over,
-- and from then on the entrance (and its lock laser) is the only way in.

export type WallLevel = {
	Name: string,
	Height: number,
	Cost: number,
	Material: Enum.Material,
}

Config.WallLevels = {
	{ Name = "Wood Fence", Height = 3, Cost = 0, Material = Enum.Material.WoodPlanks },
	{ Name = "Brick Wall", Height = 5.5, Cost = 1000, Material = Enum.Material.Brick },
	{ Name = "Concrete Wall", Height = 9, Cost = 25000, Material = Enum.Material.Concrete },
	{ Name = "Steel Wall", Height = 13, Cost = 500000, Material = Enum.Material.DiamondPlate },
	{ Name = "Diamond Wall", Height = 18, Cost = 10000000, Material = Enum.Material.Glass },
} :: { WallLevel }

-- Stealing -----------------------------------------------------------------

Config.CarryWalkSpeed = 13 -- thieves move slower while carrying
Config.NormalWalkSpeed = 16
Config.StealRange = 14
Config.SlapCooldown = 0.8
Config.SlapRange = 8
Config.SlapForce = 70

-- Rebirth ------------------------------------------------------------------

Config.RebirthBaseCost = 1000000
Config.RebirthCostGrowth = 5
Config.RebirthBonus = 0.5 -- +50% income per rebirth

-- Admins -------------------------------------------------------------------
-- The game's owner (or a group owner, for group games) is always an admin,
-- and everyone is an admin when testing in Studio. Add other people's
-- Roblox user IDs here (the number in their profile URL).

Config.AdminUserIds = {} :: { number }
Config.AdminGroupRank = 255 -- for group games: this rank and above are admins

-- Monetization -------------------------------------------------------------
-- Create these on the Creator Dashboard (your experience > Monetization),
-- then paste the IDs below. Items with Id = 0 show as "coming soon".

Config.GamePasses = {
	{ Key = "DoubleCash", Id = 0, Name = "2x Cash", Description = "Your brainrots make double cash forever." },
	{ Key = "VIP", Id = 0, Name = "VIP", Description = "+2 base slots and a gold VIP tag." },
	{ Key = "LongerLock", Id = 0, Name = "Longer Lock", Description = "Your base lock lasts 120s instead of 60s." },
} :: { GamePass }

Config.Products = {
	{ Key = "SmallCash", Id = 0, Name = "Cash Bag", Description = "10 minutes of your income (at least $1K)." },
	{ Key = "BigCash", Id = 0, Name = "Cash Vault", Description = "1 hour of your income (at least $25K)." },
	{ Key = "ServerLuck", Id = 0, Name = "Server Luck", Description = "More Rare+ spawns for EVERYONE for 15 minutes." },
	{ Key = "InstantLock", Id = 0, Name = "Instant Lock", Description = "Skip the lock cooldown and lock your base now." },
} :: { Product }

Config.SmallCashMinutes = 10
Config.SmallCashMinimum = 1000
Config.BigCashMinutes = 60
Config.BigCashMinimum = 25000

-- Lookup helpers -----------------------------------------------------------

local byId: { [string]: Brainrot } = {}
local byRarity: { [RarityId]: { Brainrot } } = {}
for _, brainrot in Config.Brainrots do
	byId[brainrot.Id] = brainrot
	local list = byRarity[brainrot.Rarity]
	if not list then
		list = {}
		byRarity[brainrot.Rarity] = list
	end
	table.insert(list, brainrot)
end

function Config.GetBrainrot(id: string): Brainrot?
	return byId[id]
end

function Config.GetGamePass(key: string): GamePass?
	for _, pass in Config.GamePasses do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

local mutationsById: { [string]: Mutation } = {}
for _, mutation in Config.Mutations do
	mutationsById[mutation.Id] = mutation
end

function Config.GetMutation(id: string?): Mutation?
	return if id then mutationsById[id] else nil
end

local function mutationMultiplier(mutationId: string?): number
	local mutation = Config.GetMutation(mutationId)
	return if mutation then mutation.Multiplier else 1
end

function Config.PriceOf(brainrot: Brainrot, mutationId: string?): number
	return brainrot.Price * mutationMultiplier(mutationId)
end

function Config.IncomeOf(brainrot: Brainrot, mutationId: string?): number
	return brainrot.Income * mutationMultiplier(mutationId)
end

function Config.SellValue(brainrot: Brainrot, mutationId: string?): number
	return math.floor(Config.PriceOf(brainrot, mutationId) * Config.SellRatio)
end

-- Saved brainrots are stored as "Id" or "Id:Mutation".
function Config.Encode(id: string, mutationId: string?): string
	return if mutationId then id .. ":" .. mutationId else id
end

function Config.Decode(entry: string): (Brainrot?, string?)
	local id, mutationId = string.match(entry, "^([^:]+):?(.*)$")
	local brainrot = id and byId[id]
	local mutation = Config.GetMutation(mutationId)
	return brainrot, if mutation then mutation.Id else nil
end

-- Rolls a mutation (or nil) for a conveyor spawn.
function Config.RollMutation(rng: Random, luck: number): string?
	local roll = rng:NextNumber(0, 100)
	-- Rarest first, so luck can't push a common mutation past a rare one.
	for i = #Config.Mutations, 1, -1 do
		local mutation = Config.Mutations[i]
		roll -= mutation.Chance * luck
		if roll < 0 then
			return mutation.Id
		end
	end
	return nil
end

function Config.RebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.RebirthBonus
end

-- Picks a random brainrot for the conveyor. Luck boosts every rarity above Common.
function Config.RollConveyor(rng: Random, luck: number): Brainrot
	local total = 0
	local weights: { [RarityId]: number } = {}
	for _, rarityId: RarityId in rarityOrder do
		local rarity = Config.Rarities[rarityId]
		local weight = rarity.SpawnWeight
		if rarity.Order > 1 then
			weight *= luck
		end
		if byRarity[rarityId] then
			weights[rarityId] = weight
			total += weight
		end
	end

	local roll = rng:NextNumber(0, total)
	local chosen: RarityId = "Common"
	for _, rarityId: RarityId in rarityOrder do
		local weight = weights[rarityId]
		if weight then
			chosen = rarityId
			roll -= weight
			if roll < 0 then
				break
			end
		end
	end

	local pool = byRarity[chosen]
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

function Config.FormatCash(n: number): string
	return "$" .. Config.FormatNumber(n)
end

return Config

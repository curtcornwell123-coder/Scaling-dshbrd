--!strict
-- Shared game configuration: rarities, brainrots, conveyor odds, bases,
-- rebirths and monetization. Server and client both read this file.

local Config = {}

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret" | "EventSpecial"

export type Rarity = {
	Id: RarityId,
	DisplayName: string,
	Color: Color3,
	Order: number,
	Scale: number, -- model size multiplier
	SpawnWeight: number, -- relative chance to appear on the conveyor
	Announce: boolean, -- tell the whole server when one spawns
	EventOnly: boolean?, -- only on the conveyor during admin abuse
}

export type Brainrot = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	Price: number,
	Income: number, -- cash per second while sitting in your base
	Color: Color3,
	Accent: Color3,
	IncomeGrowth: number?, -- income multiplies by this for every rebirth the owner has
	Scale: number?, -- model size override (otherwise the rarity's size)
	Limited: boolean?, -- sold for Robux in limited numbers: can't be stolen or sold, kept on rebirth
}

-- Limited Robux brainrots. Stock is shared by every server (saved in a
-- DataStore), one per player, and each copy gets a serial number.
export type LimitedItem = {
	ProductId: number, -- developer product (0 = none)
	GamePassId: number?, -- or a gamepass (one per player); either puts her on sale
	PriceRobux: number, -- shown in the shop; the real price is set on the product
	Stock: number, -- copies for sale
	Reserved: number, -- extra copies Corny can still give once the shop stock is gone
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

local rarityOrder: { RarityId } = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "EventSpecial" }
Config.RarityOrder = rarityOrder

Config.Rarities = {
	Common = { Id = "Common", DisplayName = "Common", Color = Color3.fromRGB(70, 200, 90), Order = 1, Scale = 1, SpawnWeight = 60, Announce = false },
	Rare = { Id = "Rare", DisplayName = "Rare", Color = Color3.fromRGB(60, 140, 255), Order = 2, Scale = 1.15, SpawnWeight = 25, Announce = false },
	Epic = { Id = "Epic", DisplayName = "Epic", Color = Color3.fromRGB(170, 80, 255), Order = 3, Scale = 1.3, SpawnWeight = 10, Announce = false },
	Legendary = { Id = "Legendary", DisplayName = "Legendary", Color = Color3.fromRGB(255, 195, 40), Order = 4, Scale = 1.5, SpawnWeight = 4, Announce = true },
	Mythic = { Id = "Mythic", DisplayName = "Mythic", Color = Color3.fromRGB(255, 45, 60), Order = 5, Scale = 1.75, SpawnWeight = 0.9, Announce = true },
	Secret = { Id = "Secret", DisplayName = "Secret", Color = Color3.fromRGB(20, 20, 20), Order = 6, Scale = 2, SpawnWeight = 0.1, Announce = true },
	-- Event Special: never on the conveyor. Set SpawnWeight above 0 to let
	-- non-limited Event Specials roll on the conveyor during admin abuse.
	EventSpecial = { Id = "EventSpecial", DisplayName = "Event Special", Color = Color3.fromRGB(255, 70, 190), Order = 7, Scale = 1.5, SpawnWeight = 0, Announce = true, EventOnly = true },
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
	{ Id = "TireinaFrogiva", DisplayName = "Tireina Frogiva", Rarity = "Rare", Price = 1200, Income = 20, Color = Color3.fromRGB(80, 170, 60), Accent = Color3.fromRGB(235, 200, 60) },
	{ Id = "TostinoTurbino", DisplayName = "Tostino Turbino", Rarity = "Rare", Price = 1500, Income = 25, Color = Color3.fromRGB(190, 120, 60), Accent = Color3.fromRGB(80, 80, 90) },
	-- Epic
	{ Id = "CactussoBossino", DisplayName = "Cactusso Bossino", Rarity = "Epic", Price = 5000, Income = 60, Color = Color3.fromRGB(60, 170, 70), Accent = Color3.fromRGB(255, 120, 200) },
	{ Id = "WaffelinoWizardo", DisplayName = "Waffelino Wizardo", Rarity = "Epic", Price = 9000, Income = 100, Color = Color3.fromRGB(230, 180, 90), Accent = Color3.fromRGB(90, 50, 200) },
	{ Id = "SixSeven", DisplayName = "67", Rarity = "Epic", Price = 6700, Income = 67, Color = Color3.fromRGB(40, 110, 230), Accent = Color3.fromRGB(245, 245, 250) },
	{ Id = "GnocchiNinjaro", DisplayName = "Gnocchi Ninjaro", Rarity = "Epic", Price = 15000, Income = 150, Color = Color3.fromRGB(250, 240, 200), Accent = Color3.fromRGB(20, 20, 30) },
	-- Legendary
	{ Id = "PinguinoHackerino", DisplayName = "Pinguino Hackerino", Rarity = "Legendary", Price = 75000, Income = 500, Color = Color3.fromRGB(40, 40, 50), Accent = Color3.fromRGB(0, 255, 120) },
	{ Id = "LasagnaLightningo", DisplayName = "Lasagna Lightningo", Rarity = "Legendary", Price = 200000, Income = 1200, Color = Color3.fromRGB(220, 90, 40), Accent = Color3.fromRGB(255, 240, 80) },
	-- Mythic
	{ Id = "DragoniSpaghettoni", DisplayName = "Dragoni Spaghettoni", Rarity = "Mythic", Price = 1500000, Income = 6000, Color = Color3.fromRGB(200, 30, 30), Accent = Color3.fromRGB(255, 210, 120) },
	{ Id = "BallerinaCapuchina", DisplayName = "Ballerina Capuchina", Rarity = "Mythic", Price = 2500000, Income = 10000, Color = Color3.fromRGB(245, 190, 170), Accent = Color3.fromRGB(180, 110, 60) },
	{ Id = "MeatballoSupremo", DisplayName = "Meatballo Supremo", Rarity = "Mythic", Price = 4000000, Income = 15000, Color = Color3.fromRGB(120, 60, 40), Accent = Color3.fromRGB(255, 255, 255) },
	-- Event Special
	-- Launch event: 500 for sale at 50 Robux + 2 reserved. Earns $2.5K/s and
	-- doubles with every rebirth, so she stays useful without breaking the economy.
	{ Id = "CignaGlamourina", DisplayName = "Cigna Glamourina", Rarity = "EventSpecial", Price = 0, Income = 2500, IncomeGrowth = 2, Limited = true, Color = Color3.fromRGB(240, 110, 200), Accent = Color3.fromRGB(255, 30, 170) },
	-- Secret
	-- A little sneaker creature: kept short on purpose (Scale), but very rare.
	-- (The Id keeps its old name so saved copies still load.)
	{ Id = "ScarpinoStellino", DisplayName = "Sneakerino Shoelacini", Rarity = "Secret", Price = 25000000, Income = 120000, Scale = 1.15, Color = Color3.fromRGB(110, 130, 205), Accent = Color3.fromRGB(240, 235, 222) },
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
	Exclusive: { string }?, -- only these brainrots can have it (never on the conveyor)
}

Config.Mutations = {
	-- Keep this list ordered from most to least common (the roll relies on it).
	{ Id = "Gold", DisplayName = "Gold", Chance = 4, Multiplier = 2, Color = Color3.fromRGB(255, 200, 50) },
	{ Id = "Candy", DisplayName = "Candy", Chance = 2.5, Multiplier = 2.5, Color = Color3.fromRGB(255, 160, 210) },
	{ Id = "Diamond", DisplayName = "Diamond", Chance = 2, Multiplier = 3, Color = Color3.fromRGB(140, 230, 255) },
	{ Id = "Frozen", DisplayName = "Frozen", Chance = 2, Multiplier = 3, Color = Color3.fromRGB(170, 225, 255) },
	{ Id = "Sparkle", DisplayName = "Sparkle", Chance = 1.5, Multiplier = 4, Color = Color3.fromRGB(255, 250, 170) },
	{ Id = "Electric", DisplayName = "Electric", Chance = 1.2, Multiplier = 4.5, Color = Color3.fromRGB(255, 230, 70) },
	{ Id = "Smiley", DisplayName = "Smiley", Chance = 1, Multiplier = 5, Color = Color3.fromRGB(255, 220, 60) },
	{ Id = "Radioactive", DisplayName = "Radioactive", Chance = 0.9, Multiplier = 5.5, Color = Color3.fromRGB(120, 255, 90) },
	{ Id = "Lava", DisplayName = "Lava", Chance = 0.8, Multiplier = 5, Color = Color3.fromRGB(255, 100, 20) },
	{ Id = "Galaxy", DisplayName = "Galaxy", Chance = 0.6, Multiplier = 7, Color = Color3.fromRGB(150, 100, 255) },
	{ Id = "Cursed", DisplayName = "Cursed", Chance = 0.5, Multiplier = 8, Color = Color3.fromRGB(210, 40, 60) },
	{ Id = "Rainbow", DisplayName = "Rainbow", Chance = 0.3, Multiplier = 10, Color = Color3.fromRGB(255, 120, 255) },
	{ Id = "Void", DisplayName = "Void", Chance = 0.2, Multiplier = 12, Color = Color3.fromRGB(130, 80, 210) },
	{ Id = "Divine", DisplayName = "Divine", Chance = 0.1, Multiplier = 15, Color = Color3.fromRGB(255, 235, 160) },
	-- Event-only: 1% when you get Cigna Glamourina, or given by an admin.
	{ Id = "Magic", DisplayName = "Magic", Chance = 0, Multiplier = 8, Color = Color3.fromRGB(190, 130, 255), Exclusive = { "CignaGlamourina" } },
} :: { Mutation }

Config.MagicChance = 1 -- percent, rolled when a limited event brainrot is granted
Config.CurrentEvent = "CignaGlamourina" -- the brainrot shown on the event statue

-- Economy ------------------------------------------------------------------

Config.StartingCash = 100
Config.SellRatio = 0.5 -- selling returns this share of the buy price

-- Conveyor -----------------------------------------------------------------

Config.ConveyorSpawnInterval = 3 -- seconds between new brainrots
Config.ConveyorTravelTime = 75 -- seconds to ride from one end to the other
Config.ServerLuckMultiplier = 2 -- doubles the spawn weight of Rare and better (Mythic 0.9% -> ~1.3%)
Config.ServerLuckDuration = 15 * 60

-- Bases --------------------------------------------------------------------

Config.PlotCount = 8 -- also set Max Players to 8 in Game Settings
Config.BaseSlots = 10
Config.VipSlots = 2 -- extra slots for VIP owners
Config.LockCooldown = 30 -- vulnerable window after a lock ends

-- Base levels ----------------------------------------------------------------
-- Walls and floors are upgraded together: each base level adds a floor
-- (reached by stairs inside the base) and better walls. Players jump about
-- 7 studs high, so level 3 is the first wall nobody can jump over; from then
-- on the entrance (and its lock lasers) is the only way in.

export type WallLevel = {
	Name: string,
	Height: number,
	Cost: number, -- price of reaching this base level
	Material: Enum.Material,
}

Config.WallLevels = {
	{ Name = "Wood Fence", Height = 3, Cost = 0, Material = Enum.Material.WoodPlanks },
	{ Name = "Brick Wall", Height = 5.5, Cost = 25000, Material = Enum.Material.Brick },
	{ Name = "Concrete Wall", Height = 9, Cost = 1000000, Material = Enum.Material.Concrete },
	{ Name = "Steel Wall", Height = 13, Cost = 40000000, Material = Enum.Material.DiamondPlate },
	{ Name = "Diamond Wall", Height = 18, Cost = 1500000000, Material = Enum.Material.Foil },
} :: { WallLevel }

-- One floor per base level, so this list must be as long as WallLevels.
export type Story = { Name: string }

Config.Stories = {
	{ Name = "Ground Floor" },
	{ Name = "2nd Floor" },
	{ Name = "3rd Floor" },
	{ Name = "4th Floor" },
	{ Name = "5th Floor" },
} :: { Story }
assert(#Config.Stories == #Config.WallLevels, "Config: need one floor per wall level")
Config.UpperFloorSlots = 10

-- Wall skins -----------------------------------------------------------------
-- Cosmetic looks for your base walls, bought with quest currencies:
--   Shards   - 10 per daily quest, 100 per weekly quest (up to 510 a week)
--   Diamonds - 1 per weekly quest (plus 100 Shards), max 3 a week; for the best skins
-- They can't be bought with Robux, so everyone earns skins the same way.
-- A skin keeps your base level's wall height; it just changes the look.

export type Currency = "Shards" | "Diamonds"

export type WallSkin = {
	Id: string,
	Name: string,
	Cost: number,
	Currency: Currency,
	Color: Color3?,
	Material: Enum.Material?, -- nil = the base level's own material
	Glass: Color3?, -- window tint
	GlassNeon: boolean?, -- glowing windows
	-- Every floor of the base. Unset = same grey and material as the walls
	-- (so Classic floors follow the base level: wood, brick, concrete...).
	FloorColor: Color3?,
	FloorMaterial: Enum.Material?,
	-- Only this founder (Config.Founders Id) can have it; it's free for them
	-- and hidden from everyone else.
	FounderOnly: string?,
	Corn: boolean?, -- corn cobs on the walls and the Corny Games logo on the windows
	Trim: Color3?, -- glowing strips along the window sills and tops
	Moon: boolean?, -- a crescent moon over the base, with an aura once it's fully upgraded
}

Config.WallSkins = {
	{ Id = "Classic", Name = "Classic Grey", Cost = 0, Currency = "Shards" },
	{ Id = "RedBrick", Name = "Red Brick", Cost = 250, Currency = "Shards", Color = Color3.fromRGB(165, 65, 50), Material = Enum.Material.Brick, FloorColor = Color3.fromRGB(150, 105, 75), FloorMaterial = Enum.Material.WoodPlanks },
	{ Id = "Candy", Name = "Candy Pink", Cost = 600, Currency = "Shards", Color = Color3.fromRGB(255, 160, 205), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 225, 245), FloorColor = Color3.fromRGB(255, 225, 238), FloorMaterial = Enum.Material.SmoothPlastic },
	{ Id = "Ice", Name = "Frozen Ice", Cost = 1200, Currency = "Shards", Color = Color3.fromRGB(175, 220, 255), Material = Enum.Material.Ice, Glass = Color3.fromRGB(225, 245, 255), FloorColor = Color3.fromRGB(215, 238, 255), FloorMaterial = Enum.Material.Ice },
	{ Id = "Jungle", Name = "Jungle Stone", Cost = 2000, Currency = "Shards", Color = Color3.fromRGB(85, 120, 70), Material = Enum.Material.Slate, Glass = Color3.fromRGB(150, 220, 120), FloorColor = Color3.fromRGB(100, 85, 60), FloorMaterial = Enum.Material.Ground },
	{ Id = "Cyber", Name = "Cyber Neon", Cost = 3500, Currency = "Shards", Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Metal, Glass = Color3.fromRGB(0, 255, 200), GlassNeon = true, FloorColor = Color3.fromRGB(35, 35, 45), FloorMaterial = Enum.Material.DiamondPlate },
	{ Id = "Gold", Name = "Royal Gold", Cost = 12, Currency = "Diamonds", Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil, Glass = Color3.fromRGB(255, 240, 180) },
	{ Id = "Galaxy", Name = "Galaxy", Cost = 25, Currency = "Diamonds", Color = Color3.fromRGB(45, 25, 85), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(200, 120, 255), GlassNeon = true, FloorColor = Color3.fromRGB(25, 15, 50), FloorMaterial = Enum.Material.Glass },
	{ Id = "Crystal", Name = "Crystal Palace", Cost = 45, Currency = "Diamonds", Color = Color3.fromRGB(150, 225, 255), Material = Enum.Material.Glass, Glass = Color3.fromRGB(220, 250, 255), GlassNeon = true, FloorColor = Color3.fromRGB(200, 240, 255), FloorMaterial = Enum.Material.Glass },
	{ Id = "Lava", Name = "Lava Core", Cost = 75, Currency = "Diamonds", Color = Color3.fromRGB(55, 25, 20), Material = Enum.Material.CrackedLava, Glass = Color3.fromRGB(255, 120, 30), GlassNeon = true, FloorColor = Color3.fromRGB(45, 22, 18), FloorMaterial = Enum.Material.Slate },
	{ Id = "Celestial", Name = "Celestial", Cost = 120, Currency = "Diamonds", Color = Color3.fromRGB(245, 240, 228), Material = Enum.Material.Marble, Glass = Color3.fromRGB(255, 210, 90), GlassNeon = true, FloorColor = Color3.fromRGB(250, 246, 236), FloorMaterial = Enum.Material.Marble },
	-- Corny's own skin, like his logo: navy walls, gold trim, corn everywhere.
	-- Ace's own skin, in Cigna Glamourina's pinks, with a crescent moon on top.
	{ Id = "Ace", Name = "Glamourina Moon (Ace only)", Cost = 0, Currency = "Diamonds", FounderOnly = "Ace", Moon = true, Trim = Color3.fromRGB(255, 30, 170), Color = Color3.fromRGB(240, 110, 200), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 190, 235), GlassNeon = true, FloorColor = Color3.fromRGB(255, 225, 245), FloorMaterial = Enum.Material.SmoothPlastic },
	{ Id = "Corny", Name = "Corny Gold (Corny only)", Cost = 0, Currency = "Diamonds", FounderOnly = "Corny", Corn = true, Trim = Color3.fromRGB(250, 196, 60), Color = Color3.fromRGB(25, 32, 55), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 205, 60), FloorColor = Color3.fromRGB(255, 215, 90), FloorMaterial = Enum.Material.SmoothPlastic },
} :: { WallSkin }

-- Skins are a ladder: to buy one you must own the one before it that costs
-- the same currency (Red Brick -> Candy Pink -> ... and Royal Gold ->
-- Galaxy -> ...). Returns the skin you need first, if any.
function Config.SkinRequirement(skin: WallSkin): WallSkin?
	if skin.FounderOnly then
		return nil
	end
	local previous: WallSkin? = nil
	for _, other in Config.WallSkins do
		if other.Id == skin.Id then
			return previous
		end
		if other.Currency == skin.Currency and other.Cost > 0 and not other.FounderOnly then
			previous = other
		end
	end
	return nil
end

-- Diamond Shop: the counter in the shop tent (like a ticket shop). Diamonds
-- only come from weekly quests (up to 3 a week) and the admin abuse gift
-- (3 a week), so everything here is priced to be saved up for. Shards are
-- easy to earn (~650 a week), so a Shard Pouch is a poor trade on purpose.
export type DiamondItem = { Id: string, Name: string, Description: string, Cost: number }

Config.DiamondShop = {
	{ Id = "ShardPack", Name = "Shard Pouch", Description = "Get 400 Shards for skins.", Cost = 2 },
	{ Id = "CashBoost", Name = "2x Cash (30 min)", Description = "Double your income for 30 minutes. Stacks.", Cost = 3 },
	{ Id = "ServerLuck", Name = "Server Luck (15 min)", Description = "More Rare+ spawns for EVERYONE. Be a hero.", Cost = 5 },
	{ Id = "CashBoostBig", Name = "2x Cash (3 hours)", Description = "Double your income for 3 hours. Stacks.", Cost = 12 },
	-- The same as the Infinite Laser Door gamepass. The most expensive thing
	-- in the game on purpose: months of weekly quests and admin abuse.
	{ Id = "InfiniteLock", Name = "Infinite Laser Door", Description = "Your base lasers stay on forever. One-time, permanent.", Cost = 250 },
} :: { DiamondItem }
Config.ShardPackAmount = 400
Config.CashBoostSeconds = 30 * 60
Config.BigCashBoostSeconds = 3 * 60 * 60

function Config.GetWallSkin(id: string?): WallSkin?
	for _, skin in Config.WallSkins do
		if skin.Id == id then
			return skin
		end
	end
	return nil
end

-- Quests -----------------------------------------------------------------------
-- Everyone gets the same 3 daily and 3 weekly quests (picked from the pools
-- below). Days reset at midnight in the admin abuse time zone (Oklahoma);
-- weeks reset Monday at midnight. Daily quests pay Shards; weekly quests are
-- much harder and are the only way to earn Diamonds.

export type QuestDef = {
	Id: string, -- the stat it counts (see Main.server: addQuestProgress)
	Text: string, -- "%d" is replaced with the goal
	Goal: number,
}

Config.DailyQuests = {
	{ Id = "Buy", Text = "Buy %d brainrots", Goal = 15 },
	{ Id = "BuyEpic", Text = "Buy %d Epic or better brainrots", Goal = 3 },
	{ Id = "Steal", Text = "Steal %d brainrots", Goal = 2 },
	{ Id = "Collect", Text = "Collect cash %d times", Goal = 20 },
	{ Id = "Slap", Text = "Slap %d thieves", Goal = 3 },
	{ Id = "Lock", Text = "Lock your base %d times", Goal = 5 },
	{ Id = "Minutes", Text = "Play for %d minutes", Goal = 20 },
	{ Id = "Grab", Text = "Grab %d admin drops", Goal = 1 },
} :: { QuestDef }

Config.WeeklyQuests = {
	{ Id = "Buy", Text = "Buy %d brainrots", Goal = 400 },
	{ Id = "BuyLegendary", Text = "Buy %d Legendary or better brainrots", Goal = 15 },
	{ Id = "BuyMutated", Text = "Buy %d mutated brainrots", Goal = 20 },
	{ Id = "Steal", Text = "Steal %d brainrots", Goal = 40 },
	{ Id = "Slap", Text = "Slap %d thieves", Goal = 50 },
	{ Id = "Minutes", Text = "Play for %d minutes", Goal = 360 },
	{ Id = "Rebirth", Text = "Rebirth %d times", Goal = 2 },
	{ Id = "Upgrade", Text = "Buy %d base or lock upgrades", Goal = 3 },
} :: { QuestDef }

Config.QuestsPerPeriod = 3
Config.DailyShards = 10 -- per daily quest
Config.WeeklyDiamonds = 1 -- per weekly quest
Config.WeeklyShards = 100 -- per weekly quest, on top of the Diamond

-- The day and week numbers quests are keyed on (local to the admin abuse
-- time zone, so "midnight" is Oklahoma midnight).
function Config.QuestPeriods(now: number): (number, number, number, number)
	local localNow = now + Config.AdminAbuseUtcOffset(now)
	local day = localNow // 86400
	-- Unix day 0 was a Thursday; +3 makes weeks start on Monday.
	local week = (day + 3) // 7
	local secondsToDay = 86400 - localNow % 86400
	local secondsToWeek = (7 - (day + 3) % 7) * 86400 - localNow % 86400
	return day, week, secondsToDay, secondsToWeek
end

-- The quests everyone gets for a given day/week. Same seed -> same quests.
function Config.PickQuests(pool: { QuestDef }, seed: number): { QuestDef }
	local rng = Random.new(seed)
	local indexes = {}
	for i = 1, #pool do
		indexes[i] = i
	end
	local picked = {}
	for i = 1, math.min(Config.QuestsPerPeriod, #pool) do
		local j = rng:NextInteger(i, #indexes)
		indexes[i], indexes[j] = indexes[j], indexes[i]
		table.insert(picked, pool[indexes[i]])
	end
	return picked
end

-- Stair carpets -------------------------------------------------------------
-- Stairs start as plain wood. Every 5 rebirths they get a fancier carpet.

export type CarpetTier = {
	Name: string,
	Color: Color3,
	Material: Enum.Material,
	Trim: Color3?, -- edge strips along both sides
	Glow: Color3?, -- neon light on the lip of every step
	Sparkle: boolean?,
	Rainbow: boolean?,
}

Config.CarpetRebirthStep = 5
Config.CarpetTiers = {
	{ Name = "Red Carpet", Color = Color3.fromRGB(170, 20, 35), Material = Enum.Material.Fabric },
	{ Name = "Royal Carpet", Color = Color3.fromRGB(95, 30, 150), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 200, 60) },
	{ Name = "Golden Carpet", Color = Color3.fromRGB(235, 185, 50), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 255, 255), Glow = Color3.fromRGB(255, 220, 120) },
	{ Name = "Diamond Carpet", Color = Color3.fromRGB(150, 225, 255), Material = Enum.Material.Glass, Trim = Color3.fromRGB(220, 250, 255), Glow = Color3.fromRGB(90, 220, 255), Sparkle = true },
	{ Name = "Rainbow Carpet", Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 200, 60), Glow = Color3.fromRGB(255, 120, 255), Sparkle = true, Rainbow = true },
} :: { CarpetTier }

-- 0 = plain wood stairs, 1 = first carpet at 5 rebirths, and so on.
function Config.CarpetTierFor(rebirths: number): number
	return math.min(#Config.CarpetTiers, rebirths // Config.CarpetRebirthStep)
end

-- Lock upgrades --------------------------------------------------------------
-- How long the entrance lasers stay on. The Longer Lock gamepass doubles it.

-- Rebirths: how many times you must have rebirthed before you can buy it.
export type LockLevel = { Duration: number, Cost: number, Rebirths: number? }

Config.LockLevels = {
	{ Duration = 30, Cost = 0 },
	{ Duration = 45, Cost = 5000 },
	{ Duration = 60, Cost = 50000 },
	{ Duration = 90, Cost = 500000 },
	{ Duration = 120, Cost = 5000000 },
	-- Rebirth-only levels (kept through rebirths, like every lock upgrade)
	{ Duration = 150, Cost = 25000000, Rebirths = 1 },
	{ Duration = 180, Cost = 250000000, Rebirths = 2 },
	{ Duration = 210, Cost = 2000000000, Rebirths = 4 },
	{ Duration = 240, Cost = 40000000000, Rebirths = 6 },
} :: { LockLevel }

-- Stealing -----------------------------------------------------------------

Config.CarryWalkSpeed = 13 -- thieves move slower while carrying (and can't sprint)
Config.SprintMultiplier = 1.45 -- Shift / SPRINT button / click the left stick
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

-- Admin abuse --------------------------------------------------------------
-- A weekly event. Everyone sees a countdown during the hour before it, and a
-- LIVE banner while it runs. The time is local to the time zone below, and
-- US daylight saving time is handled automatically.
-- Admins can also start or stop it any time from the admin panel.

Config.AdminAbuse = {
	WeekDay = 7, -- 1 = Sunday, 2 = Monday ... 7 = Saturday
	Hour = 14, -- 24-hour clock: 14 = 2 PM
	Minute = 0,
	UtcOffset = -6, -- US Central standard time (Oklahoma)
	UsDaylightSaving = true, -- adds an hour from March to November
	DurationMinutes = 60,
	CountdownMinutes = 60,
}

-- What everyone gets during admin abuse. It's rare (once a week), so it's big.
Config.AdminAbuseBoosts = {
	Income = 3, -- x3 cash for everyone while it's live (stacks with other boosts)
	Luck = 3, -- x3 luck for rare spawns and mutations (bought Server Luck is x2)
	WalkSpeed = 24, -- normal walking speed while it's live (16 normally; carrying is unchanged)
	JumpHeight = 13, -- normal jump is 7.2
}

-- Game music ------------------------------------------------------------------
-- Background music for normal play (audio ids, "rbxassetid://123..."). Plays
-- on a loop (shuffled if there's more than one), fades out while a founder
-- event plays its own song, and players can turn it off. Empty = no music.
-- More of our own songs are in assets/music/: upload one and add its id here.
Config.GameMusic = {
	"rbxassetid://119583552951911", -- "Chill Plaza" (assets/music/lobby_3_chill_plaza.mp3)
} :: { string }
Config.GameMusicVolume = 0.35

-- Founders --------------------------------------------------------------------
-- The game's founders show up as giants during admin abuse, and each has an
-- event of their own. Put each founder's Roblox UserId (the number in their
-- profile link: roblox.com/users/<UserId>/profile) or their Username here so
-- the giants wear their real avatars.
export type Founder = { Id: string, Name: string, UserId: number, Username: string }
Config.Founders = {
	{ Id = "Corny", Name = "Corny", UserId = 469657246, Username = "Cornywell10" },
	{ Id = "Ace", Name = "Ace", UserId = 8504983999, Username = "Meishappy2341" },
} :: { Founder }
-- During admin abuse they tower just outside the fence (like the devs in
-- Grow a Garden), doing one Roblox emote after another.
Config.FounderGiantScale = 24 -- about 125 studs tall
Config.FounderGiantSpots = {
	Corny = Vector3.new(-170, 0, 470),
	Ace = Vector3.new(170, 0, -470),
} :: { [string]: Vector3 }
Config.FounderCashDrop = 25000 -- cash in each bag a founder throws or drops

-- Founder events: each stars only that founder, wearing their special event
-- outfit (not their normal avatar). Admins start them from the admin panel.
export type FounderEvent = {
	Founder: string,
	OutfitId: number, -- their special event outfit (0 = Corny's built-in look-alike)
	Title: string,
	Subtitle: string,
	DurationMinutes: number,
	Scale: number,
	Spots: { Vector3 }, -- where they appear (one per side of the map)
	-- "Ufo": they float in a UFO's beam throwing things (Corny's).
	-- "Ballet": they stand in the water while Cigna Glamourina dances around them (Ace's).
	Style: string,
	UfoSize: number?, -- the UFO's width
	UfoHeight: number?, -- how high the UFO hovers
	FloatHeight: number?, -- how high their feet float in the beam
	PoseAnimationId: string?, -- the pose they hold ("" = the built-in pose)
	DropEvery: number?, -- seconds between throws (nil = no throwing)
	BrainrotChance: number?, -- chance each throw is a brainrot (else a cash bag)
	BrainrotLuck: number?,
	Mutations: { { Id: string, Chance: number } }?, -- extra mutation chances on their brainrots (percent)
	Luck: number?, -- server luck while it runs (like bought Server Luck)
	Guaranteed: string?, -- a brainrot that's sure to come down the conveyor, with a rare mutation
	Dancer: string?, -- a brainrot that flies around them dancing ballet
	Colors: { Color3 }, -- intro colors
	Chips: { string }, -- the little boxes under the intro title
	Sky: string?, -- "Green", "Pink" or "Rainbow": the sky changes while it runs
	Water: boolean?, -- knee-deep water floods the map, with lily pads falling into it
	MusicId: string?, -- theme song (an audio id, "rbxassetid://123..."), "" = none
	Night: boolean?, -- it turns night while it runs
	-- Each night one of these mutations is picked at random (Chance is its
	-- percent chance of being tonight's pick) and is Boost times more likely
	-- on everything that spawns or drops until morning.
	NightMutations: { { Id: string, Chance: number, Boost: number } }?,
	Alien: boolean?, -- alien-style intro (green, sci-fi, glitchy) instead of rainbow
	Chaos: boolean?, -- sweeping green searchlights, pulsing lights, mini UFOs and abduction beams
}
Config.FounderEvents = {
	Corny = {
		Founder = "Corny",
		Style = "Ufo",
		-- To use the real outfit: save it as a Costume on Roblox and put its
		-- outfit id here. Until then a look-alike of it is built from parts.
		OutfitId = 0,
		Title = "CORNY EVENT!",
		Subtitle = "Giant Corny has landed! Grab everything he throws!",
		DurationMinutes = 5,
		Scale = 19, -- about 120 studs tall
		-- One UFO on each side, over the open grass just behind the bases.
		Spots = { Vector3.new(0, 0, 240), Vector3.new(0, 0, -240) },
		UfoSize = 260,
		UfoHeight = 230,
		FloatHeight = 35,
		-- Floats in the UFO's beam in a wise sage pose (legs folded back,
		-- hands together). To use an animation instead, paste its id here
		-- ("rbxassetid://123...").
		PoseAnimationId = "",
		DropEvery = 1.6,
		BrainrotChance = 0.3,
		BrainrotLuck = 4,
		-- Sprinkles like his hat, rainbow like his pants.
		Mutations = { { Id = "Candy", Chance = 45 }, { Id = "Rainbow", Chance = 8 } },
		-- Alien colors: neon green, toxic lime, teal, and an alien purple.
		Colors = { Color3.fromRGB(70, 255, 120), Color3.fromRGB(190, 255, 70), Color3.fromRGB(0, 210, 180), Color3.fromRGB(170, 90, 255) },
		Chips = { "NIGHT FALLS", "NIGHT MUTATION", "SPRINKLE DROPS", "CASH BAGS" },
		Sky = "Green",
		Night = true,
		NightMutations = {
			{ Id = "Galaxy", Chance = 30, Boost = 5 },
			{ Id = "Radioactive", Chance = 25, Boost = 5 },
			{ Id = "Electric", Chance = 20, Boost = 5 },
			{ Id = "Void", Chance = 12, Boost = 6 },
			{ Id = "Cursed", Chance = 10, Boost = 6 },
			{ Id = "Divine", Chance = 3, Boost = 8 },
		},
		Alien = true,
		Chaos = true,
		-- Theme song: "Tractor Beam" (assets/music/alien_abduction_1_tractor_beam.mp3)
		MusicId = "rbxassetid://81256073930643",
	},
	Ace = {
		Founder = "Ace",
		Style = "Ballet",
		OutfitId = 0, -- his event look: Save My Event Look in the admin panel (or an outfit id)
		Title = "ACE'S ADMIN EVENT!",
		Subtitle = "Ace brought the ballet! x2 Luck and a guaranteed Ballerina Capuchina!",
		DurationMinutes = 5,
		Scale = 19, -- about 120 studs tall
		Spots = { Vector3.new(0, 0, 240), Vector3.new(0, 0, -240) },
		Luck = 2,
		Guaranteed = "BallerinaCapuchina",
		Dancer = "CignaGlamourina",
		Colors = { Color3.fromRGB(255, 130, 200), Color3.fromRGB(255, 190, 230), Color3.fromRGB(230, 120, 255), Color3.fromRGB(255, 220, 240) },
		Chips = { "x2 LUCK", "BALLERINA GUARANTEED", "RARE MUTATION", "BALLET TIME" },
		Sky = "Pink",
		Water = true,
		-- Theme song (from Roblox's licensed music library). To use the
		-- original ballet track instead, upload assets/music/ballet_action.mp3
		-- and put its id here.
		MusicId = "rbxassetid://1836281845",
	},
} :: { [string]: FounderEvent }

function Config.GetFounder(id: string): Founder?
	for _, founder in Config.Founders do
		if founder.Id == id then
			return founder
		end
	end
	return nil
end
-- A gift for every player who's online during admin abuse, at most once a
-- week (so starting it again the same week doesn't give a second one).
-- Diamonds normally come only from weekly quests (1 a week), so 3 is a big
-- treat that still keeps Diamond Shop items worth working for.
Config.AdminAbuseGift = {
	Diamonds = 3,
	Shards = 150,
	BrainrotLuck = 5, -- one free brainrot, rolled with the same luck as Brainrot Rain
}

local WEEK = 7 * 24 * 3600

-- US rule: daylight time runs from the 2nd Sunday of March to the 1st Sunday
-- of November, switching at 2 AM local time.
local function isUsDaylightTime(t: { [string]: any }): boolean
	local month, day, weekday, hour = t.month, t.day, t.wday, t.hour
	if month > 3 and month < 11 then
		return true
	elseif month < 3 or month > 11 then
		return false
	end
	local lastSunday = day - (weekday - 1) -- date of the most recent Sunday
	if month == 3 then
		return lastSunday >= 8 and not (weekday == 1 and day <= 14 and hour < 2)
	end
	-- November: still daylight time until the first Sunday at 2 AM (1 AM standard).
	return lastSunday <= 0 or (weekday == 1 and day <= 7 and hour < 1)
end

-- Seconds to add to UTC to get the event's local time right now.
function Config.AdminAbuseUtcOffset(now: number): number
	local schedule = Config.AdminAbuse
	local offset = schedule.UtcOffset * 3600
	if schedule.UsDaylightSaving and isUsDaylightTime(os.date("!*t", math.floor(now + offset)) :: any) then
		offset += 3600
	end
	return offset
end

-- Returns "live" + seconds left, "soon" + seconds until it starts, or nil.
-- An admin can END this week's one early (the ReplicatedStorage attribute
-- "AdminAbuseSkipUntil" holds when the skipped one would have finished).
function Config.AdminAbuseStatus(now: number): (string?, number)
	local skipUntil = game:GetService("ReplicatedStorage"):GetAttribute("AdminAbuseSkipUntil")
	if type(skipUntil) == "number" and now < skipUntil then
		return nil, 0
	end
	local schedule = Config.AdminAbuse
	local t = os.date("!*t", math.floor(now + Config.AdminAbuseUtcOffset(now)))
	local intoWeek = (t.wday - 1) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
	local start = (schedule.WeekDay - 1) * 86400 + schedule.Hour * 3600 + schedule.Minute * 60
	local duration = schedule.DurationMinutes * 60
	local untilStart = (start - intoWeek) % WEEK
	local sinceStart = (intoWeek - start) % WEEK
	if sinceStart < duration then
		return "live", duration - sinceStart
	elseif untilStart <= schedule.CountdownMinutes * 60 then
		return "soon", untilStart
	end
	return nil, 0
end

-- The only one who can give limited brainrots from the admin panel (a
-- founder Id). Each gift comes out of the shop stock.
Config.LimitedGiver = "Corny"

-- How often every server re-checks the shared stock (the signs count down
-- to it). Sales and gifts in your own server show up right away.
Config.LimitedRefreshSeconds = 300

-- "4:12" until the next stock update (`nextAt` is a unix time).
function Config.StockCountdown(nextAt: number?, now: number): string
	local left = math.max(0, math.floor((nextAt or now) - now))
	return string.format("%d:%02d", left // 60, left % 60)
end

Config.LimitedItems = {
	CignaGlamourina = { ProductId = 0, GamePassId = 2021528297, PriceRobux = 50, Stock = 500, Reserved = 2 },
} :: { [string]: LimitedItem }

-- Whether a limited item can be bought yet (it has a product or a gamepass).
function Config.LimitedOnSale(item: LimitedItem): boolean
	return item.ProductId ~= 0 or (item.GamePassId or 0) ~= 0
end

-- Admin drops: what the "Brainrot Rain" and "Cash Rain" buttons drop.
Config.BrainrotRainCount = 10
Config.BrainrotRainLuck = 5 -- rain is luckier than the conveyor
Config.CashRainCount = 30
Config.DropLifetime = 90 -- seconds before an unclaimed drop disappears

-- Monetization -------------------------------------------------------------
-- Create these on the Creator Dashboard (your experience > Monetization),
-- then paste the IDs below. Items with Id = 0 show as "coming soon".

Config.GamePasses = {
	{ Key = "DoubleCash", Id = 0, Name = "2x Cash", Description = "Your brainrots make double cash forever." },
	{ Key = "VIP", Id = 0, Name = "VIP", Description = "+2 base slots and a gold VIP tag." },
	{ Key = "LongerLock", Id = 0, Name = "Longer Lock", Description = "Your base lock lasts twice as long." },
	{ Key = "InfiniteLock", Id = 0, Name = "Infinite Laser Door", Description = "Your base lasers stay on forever. Nobody can steal from you." },
} :: { GamePass }

Config.Products = {
	{ Key = "SmallCash", Id = 0, Name = "Cash Bag", Description = "10 minutes of your income (at least $1K)." },
	{ Key = "BigCash", Id = 0, Name = "Cash Vault", Description = "1 hour of your income (at least $25K)." },
	{ Key = "ServerLuck", Id = 0, Name = "Server Luck", Description = "More Rare+ spawns for EVERYONE for 15 minutes." },
	{ Key = "InstantLock", Id = 0, Name = "Instant Lock", Description = "Skip the lock cooldown and lock your base now." },
} :: { Product }

-- Codes typed into the box at the bottom of the shop. Each works once per
-- player. Add new ones here (letters are matched without caring about caps);
-- Expires is optional (unix time, e.g. from https://www.epochconverter.com).
export type Code = { Code: string, Shards: number?, Diamonds: number?, Cash: number?, Expires: number? }
-- Corny can also make codes in-game (admin panel > FOUNDER > CODES); those
-- are saved for every server. Only this founder can make or delete them.
Config.CodeMaker = "Corny"
-- Most a code made in-game can give (keeps Diamonds rare).
Config.CodeLimits = { Cash = 1e15, Shards = 5000, Diamonds = 50 }

Config.Codes = {
	{ Code = "RELEASE", Shards = 100, Diamonds = 1 },
	{ Code = "CORNY", Cash = 5000 },
} :: { Code }

Config.SmallCashMinutes = 10
Config.SmallCashMinimum = 1000
Config.BigCashMinutes = 60
Config.BigCashMinimum = 25000

-- Lookup helpers -----------------------------------------------------------

local byId: { [string]: Brainrot } = {}
local byRarity: { [RarityId]: { Brainrot } } = {}
-- The conveyor's pools leave out limited (Robux) brainrots: those only come
-- from the shop or a gift, with a serial number.
local conveyorByRarity: { [RarityId]: { Brainrot } } = {}
for _, brainrot in Config.Brainrots do
	byId[brainrot.Id] = brainrot
	local list = byRarity[brainrot.Rarity]
	if not list then
		list = {}
		byRarity[brainrot.Rarity] = list
	end
	table.insert(list, brainrot)
	if not brainrot.Limited then
		conveyorByRarity[brainrot.Rarity] = conveyorByRarity[brainrot.Rarity] or {}
		table.insert(conveyorByRarity[brainrot.Rarity], brainrot)
	end
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

-- Exclusive mutations (like Magic) only go on the brainrots they name.
function Config.MutationAllowed(brainrot: Brainrot, mutationId: string?): boolean
	local mutation = Config.GetMutation(mutationId)
	if not mutation then
		return mutationId == nil
	end
	return mutation.Exclusive == nil or table.find(mutation.Exclusive, brainrot.Id) ~= nil
end

function Config.PriceOf(brainrot: Brainrot, mutationId: string?): number
	return brainrot.Price * mutationMultiplier(mutationId)
end

-- `rebirths` only matters for brainrots with IncomeGrowth.
function Config.IncomeOf(brainrot: Brainrot, mutationId: string?, rebirths: number?): number
	local growth = if brainrot.IncomeGrowth then brainrot.IncomeGrowth ^ (rebirths or 0) else 1
	return brainrot.Income * mutationMultiplier(mutationId) * growth
end

function Config.SellValue(brainrot: Brainrot, mutationId: string?): number
	return math.floor(Config.PriceOf(brainrot, mutationId) * Config.SellRatio)
end

-- Saved brainrots are stored as "Id", "Id:Mutation" or "Id:Mutation:Serial"
-- (limited ones carry a serial number, e.g. "CignaGlamourina::17").
function Config.Encode(id: string, mutationId: string?, serial: number?): string
	if serial then
		return id .. ":" .. (mutationId or "") .. ":" .. serial
	end
	return if mutationId then id .. ":" .. mutationId else id
end

function Config.Decode(entry: string): (Brainrot?, string?, number?)
	local id, rest = string.match(entry, "^([^:]+):?(.*)$")
	local mutationId, serialText = string.match(rest or "", "^([^:]*):?(.*)$")
	local brainrot = id and byId[id]
	local mutation = Config.GetMutation(mutationId)
	-- Exclusive mutations (Magic) are dropped from brainrots that can't have them.
	if mutation and mutation.Exclusive and not (brainrot and table.find(mutation.Exclusive, brainrot.Id)) then
		mutation = nil
	end
	local serial = tonumber(serialText)
	return brainrot, if mutation then mutation.Id else nil, if serial then math.floor(serial) else nil
end

-- Rolls a mutation (or nil) for a conveyor spawn.
-- `boost`: one mutation made more likely (tonight's night mutation).
function Config.RollMutation(rng: Random, luck: number, boost: { Id: string, Multiplier: number }?): string?
	local roll = rng:NextNumber(0, 100)
	-- Rarest first, so luck can't push a common mutation past a rare one.
	for i = #Config.Mutations, 1, -1 do
		local mutation = Config.Mutations[i]
		if not mutation.Exclusive then
			local extra = if boost and boost.Id == mutation.Id then boost.Multiplier else 1
			roll -= mutation.Chance * luck * extra
			if roll < 0 then
				return mutation.Id
			end
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

-- Picks a random brainrot for the conveyor. Luck boosts every rarity above
-- Common. Event-only rarities can only roll while `eventLive` is true.
function Config.RollConveyor(rng: Random, luck: number, eventLive: boolean?): Brainrot
	local total = 0
	local weights: { [RarityId]: number } = {}
	for _, rarityId: RarityId in rarityOrder do
		local rarity = Config.Rarities[rarityId]
		local weight = rarity.SpawnWeight
		if rarity.Order > 1 then
			weight *= luck
		end
		if rarity.EventOnly and not eventLive then
			weight = 0
		end
		if conveyorByRarity[rarityId] and weight > 0 then
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

	local pool = conveyorByRarity[chosen]
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

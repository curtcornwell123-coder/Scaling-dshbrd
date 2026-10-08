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
	-- Event Special: never on the conveyor normally. Admins give/drop them,
	-- and they can show up on the conveyor while admin abuse is live.
	EventSpecial = { Id = "EventSpecial", DisplayName = "Event Special", Color = Color3.fromRGB(255, 70, 190), Order = 7, Scale = 1.5, SpawnWeight = 0.5, Announce = true, EventOnly = true },
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
	-- Event Special
	{ Id = "CignaGlamourina", DisplayName = "Cigna Glamourina", Rarity = "EventSpecial", Price = 20000000, Income = 100000, Color = Color3.fromRGB(240, 110, 200), Accent = Color3.fromRGB(255, 30, 170) },
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
	{ Id = "Sparkle", DisplayName = "Sparkle", Chance = 1.5, Multiplier = 4, Color = Color3.fromRGB(255, 250, 170) },
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
	{ Name = "Diamond Wall", Height = 18, Cost = 10000000, Material = Enum.Material.Foil },
} :: { WallLevel }

-- Floors -------------------------------------------------------------------
-- Extra stories stack on top of the base, reached by ramps inside it. The
-- ground floor has 10 slots (+2 VIP); every extra floor adds more.

export type Story = { Name: string, Cost: number }

Config.Stories = {
	{ Name = "Ground Floor", Cost = 0 },
	{ Name = "2nd Floor", Cost = 50000 },
	{ Name = "3rd Floor", Cost = 2000000 },
} :: { Story }
Config.UpperFloorSlots = 10

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

export type LockLevel = { Duration: number, Cost: number }

Config.LockLevels = {
	{ Duration = 30, Cost = 0 },
	{ Duration = 45, Cost = 5000 },
	{ Duration = 60, Cost = 50000 },
	{ Duration = 90, Cost = 500000 },
	{ Duration = 120, Cost = 5000000 },
} :: { LockLevel }

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
function Config.AdminAbuseStatus(now: number): (string?, number)
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
		if byRarity[rarityId] and weight > 0 then
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

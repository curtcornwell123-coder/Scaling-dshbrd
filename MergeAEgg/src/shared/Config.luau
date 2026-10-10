-- Merge A Egg: every tunable number in the game lives here.
-- Server and client both read this module. Change values, not code.

local Config = {}

Config.GameName = "Merge A Egg"
Config.GroupId = 187537803
Config.OwnerUserId = 469657246
Config.AdminUserIds = { 469657246 }
Config.AdminGroupRank = 255 -- group owner rank also gets admin
Config.HideOwnerFromLeaderboards = false
Config.HalloweenEnabled = true
Config.DataStoreName = "MergeAEgg_v1"

---------------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------------

-- income: pet income multiplier. treadmill: treadmill boost per equipped pet.
-- grow: grow time multiplier for an egg of this rarity.
Config.Rarities = {
	{ name = "Common", color = Color3.fromRGB(200, 200, 205), income = 1, treadmill = 0.02, grow = 1 },
	{ name = "Uncommon", color = Color3.fromRGB(85, 220, 95), income = 2, treadmill = 0.04, grow = 1.5 },
	{ name = "Rare", color = Color3.fromRGB(60, 150, 255), income = 4, treadmill = 0.08, grow = 2.5 },
	{ name = "Epic", color = Color3.fromRGB(175, 80, 255), income = 10, treadmill = 0.15, grow = 4 },
	{ name = "Legendary", color = Color3.fromRGB(255, 200, 40), income = 25, treadmill = 0.30, grow = 6 },
	{ name = "Mythic", color = Color3.fromRGB(255, 60, 70), income = 75, treadmill = 0.60, grow = 9 },
	{ name = "Secret", color = Color3.fromRGB(255, 255, 255), income = 250, treadmill = 1.20, grow = 14 },
}

Config.RarityIndex = {}
for i, rarity in Config.Rarities do
	Config.RarityIndex[rarity.name] = i
end

-- Chance (weights) of each egg rarity spawning in a biome nest.
Config.NestRarityWeights = { 60, 25, 10, 4, 0.9, 0.1, 0 }
Config.EggsPerNest = 3 -- each biome has one nest holding this many eggs
-- Luck events only roll these rarities: Legendary, Mythic, Secret.
Config.LuckEventWeights = { [5] = 70, [6] = 25, [7] = 5 }

-- Hatching: chance the pet lands on the egg's rarity, +1 or +2 tiers.
Config.HatchTierChances = { 0.72, 0.22, 0.06 }

---------------------------------------------------------------------------
-- Eggs, weight and speed
---------------------------------------------------------------------------

Config.EggWeightMin = 1.0
Config.EggWeightMax = 5.0
Config.BigEggWeightMultiplier = 1.6
Config.BigEggLuck = 1.5
Config.WeightLuckPerKg = 0.15 -- each kg above 1 adds 15% upgrade luck
Config.WeightIncomePerKg = 0.25 -- each kg above 1 adds 25% pet income
Config.CarrySlowPerKg = 0.08 -- each kg above 1 slows carrying by ~8%
Config.EggSellSeconds = 20 -- an egg sells for this many seconds of its pet income
Config.PetSellSeconds = 30

Config.BaseWalkSpeed = 16
Config.MaxWalkSpeed = 200

-- Converts the Speed stat (can reach trillions) into a real WalkSpeed.
function Config.walkSpeedFor(speed: number): number
	local decades = math.log10(math.max(speed, 0) + 1)
	return math.min(Config.MaxWalkSpeed, Config.BaseWalkSpeed + 1.2 * decades ^ 2.2)
end

function Config.carryMultiplier(weight: number): number
	return 1 / (1 + math.max(weight - 1, 0) * Config.CarrySlowPerKg)
end

---------------------------------------------------------------------------
-- Timings
---------------------------------------------------------------------------

Config.DaySeconds = 300
Config.NightSeconds = 120
Config.NightBigEggChance = 0.35
Config.NightGuardianSpeedBonus = 0.10
Config.NestRespawnSeconds = 25
Config.DroppedEggReturnSeconds = 60
Config.StealHoldSeconds = 1.2
Config.StealShieldSeconds = 45
Config.LuckEventInterval = 240
Config.TreadmillStepInterval = 0.25
Config.AutosaveInterval = 120
Config.OfflineIncomeCapSeconds = 7200
Config.LeaderboardRefreshSeconds = 120

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------

Config.BatCooldown = 0.6
Config.BatRange = 9
Config.BatKnockback = 70
Config.BatBossDamage = 3
Config.BatGuardianStun = 1.0
Config.GuardianStunCooldown = 8
Config.GuardianCatchDistance = 5
Config.GuardianKnockback = 60

---------------------------------------------------------------------------
-- Boss (Cave)
---------------------------------------------------------------------------

Config.Boss = {
	name = "Golem King",
	interval = 900, -- seconds between spawns
	duration = 300, -- how long it stays if nobody beats it
	baseHealth = 400, -- bat hits deal 3, battle pets add damage every attack
	healthPerPlayer = 200,
	attackInterval = 3.5,
	slamRadius = 26,
	telegraphTime = 1.2,
	eggLifetime = 300,
	-- Boss Egg rarity (Cave pets only come from here; the Cave King only from Secret rolls).
	eggRarityWeights = { 30, 25, 20, 13, 8, 3.5, 0.5 },
	taunts = {
		spawn = "Who dares enter MY cave? Come and face me!",
		half = "Grr... you hit harder than you look!",
		win = "Nobody showed up? Cowards! My cave remains mine!",
		defeated = "Impossible... take your egg, and leave me be...",
	},
}

---------------------------------------------------------------------------
-- Biomes and pets
---------------------------------------------------------------------------

-- Pet entry: { name, rarity, template, primary, secondary, features, scale? }
-- Templates: quad, bird, biped, slime, serpent, bug, fish.
local c = Color3.fromRGB

local function pet(name, rarity, template, primary, secondary, features, scale)
	return {
		name = name,
		rarity = rarity,
		template = template,
		primary = primary,
		secondary = secondary,
		features = features or {},
		scale = scale or 1,
	}
end

Config.Biomes = {
	{
		key = "Forest",
		name = "Forest",
		emoji = "🙂",
		recommended = 0,
		guardianSpeed = 12, -- gentle starter chicken so brand-new players can escape
		baseIncome = 3,
		growSeconds = 20,
		floor = c(95, 200, 60),
		floorAlt = c(85, 185, 55),
		wall = c(190, 130, 80),
		wallAlt = c(170, 115, 70),
		egg = c(250, 245, 230),
		eggSpots = c(190, 150, 100),
		guardian = "Chicken",
		pets = {
			pet("Chicken", "Common", "bird", c(245, 245, 245), c(220, 40, 40), { "beak", "crest", "wings" }),
			pet("Bunny", "Common", "quad", c(235, 225, 210), c(255, 170, 185), { "ears_long", "tail_fluffy" }, 0.8),
			pet("Squirrel", "Common", "quad", c(175, 100, 50), c(235, 195, 150), { "ears_pointy", "tail_fluffy" }, 0.75),
			pet("Hedgehog", "Uncommon", "quad", c(120, 85, 60), c(230, 205, 170), { "spikes" }, 0.75),
			pet("Duck", "Uncommon", "bird", c(250, 230, 90), c(255, 150, 40), { "beak", "wings" }),
			pet("Raccoon", "Uncommon", "quad", c(135, 135, 140), c(40, 40, 45), { "ears_round", "tail_fluffy", "mask" }),
			pet("Fox", "Rare", "quad", c(235, 120, 40), c(255, 255, 255), { "ears_pointy", "tail_fluffy" }),
			pet("Beaver", "Rare", "quad", c(120, 75, 40), c(250, 225, 120), { "ears_round", "tail_flat", "teeth" }),
			pet("Deer", "Epic", "quad", c(175, 115, 60), c(240, 220, 190), { "antlers", "ears_pointy", "long_neck" }),
			pet("Owl", "Epic", "bird", c(140, 100, 60), c(240, 200, 120), { "beak", "wings", "ears_pointy" }),
			pet("Wolf", "Legendary", "quad", c(110, 115, 125), c(225, 225, 230), { "ears_pointy", "tail_fluffy" }, 1.15),
			pet("Bear", "Legendary", "quad", c(100, 65, 40), c(70, 45, 30), { "ears_round" }, 1.3),
			pet("Moose King", "Mythic", "quad", c(95, 62, 36), c(255, 210, 60), { "antlers", "crown", "long_neck" }, 1.3),
			pet("Golden Stag", "Secret", "quad", c(255, 200, 40), c(255, 240, 170), { "antlers", "long_neck" }, 1.25),
		},
	},
	{
		key = "Cave",
		name = "Cave",
		emoji = "🦇",
		recommended = 0,
		dungeon = true, -- not in the corridor: eggs come from the Golem King's dungeon
		baseIncome = 20000,
		growSeconds = 60,
		floor = c(95, 90, 100),
		floorAlt = c(80, 76, 86),
		wall = c(70, 66, 76),
		wallAlt = c(58, 55, 64),
		egg = c(120, 110, 140),
		eggSpots = c(120, 220, 255),
		guardian = "Cave Spider",
		pets = {
			pet("Bat", "Common", "bird", c(70, 60, 80), c(150, 110, 160), { "wings", "ears_pointy", "fangs" }, 0.8),
			pet("Mole", "Common", "quad", c(80, 65, 60), c(255, 160, 175), { "claws", "snout" }, 0.8),
			pet("Cave Snail", "Common", "slime", c(150, 140, 130), c(110, 90, 170), { "shell", "antenna" }, 0.8),
			pet("Cave Spider", "Uncommon", "bug", c(60, 50, 70), c(200, 60, 60), { "eyes_many" }),
			pet("Glow Worm", "Uncommon", "serpent", c(120, 255, 160), c(40, 120, 80), { "glow" }, 0.8),
			pet("Blind Fish", "Uncommon", "fish", c(230, 220, 235), c(180, 170, 205), {}),
			pet("Crystal Beetle", "Rare", "bug", c(90, 200, 255), c(40, 80, 160), { "horn", "crystal" }),
			pet("Armadillo", "Rare", "quad", c(150, 130, 110), c(110, 95, 80), { "shell", "ears_round" }, 0.9),
			pet("Rock Golem", "Epic", "biped", c(120, 115, 110), c(255, 150, 50), { "glow" }, 1.1),
			pet("Crystal Bat", "Epic", "bird", c(140, 220, 255), c(80, 120, 220), { "wings", "ears_pointy", "crystal" }),
			pet("Lava Salamander", "Legendary", "quad", c(255, 90, 30), c(255, 200, 60), { "tail", "spikes", "glow" }),
			pet("Gem Turtle", "Legendary", "quad", c(60, 160, 90), c(200, 60, 255), { "shell", "crystal" }),
			pet("Diamond Golem", "Mythic", "biped", c(180, 240, 255), c(255, 255, 255), { "crystal" }, 1.25),
			pet("Cave King", "Secret", "biped", c(90, 70, 120), c(255, 210, 60), { "crown", "crystal" }, 1.3),
		},
		bossOnly = { ["Cave King"] = true },
	},
	{
		key = "Desert",
		name = "Desert",
		emoji = "🏜️",
		recommended = 1e3,
		baseIncome = 25,
		growSeconds = 30,
		floor = c(240, 215, 140),
		floorAlt = c(230, 200, 125),
		wall = c(215, 160, 95),
		wallAlt = c(200, 145, 85),
		egg = c(240, 200, 120),
		eggSpots = c(190, 110, 60),
		guardian = "Scorpion",
		pets = {
			pet("Lizard", "Common", "quad", c(190, 170, 90), c(120, 110, 60), { "tail" }, 0.75),
			pet("Desert Mouse", "Common", "quad", c(220, 190, 150), c(255, 170, 185), { "ears_round", "tail" }, 0.65),
			pet("Tortoise", "Common", "quad", c(170, 140, 90), c(110, 130, 60), { "shell" }, 0.85),
			pet("Fennec Fox", "Uncommon", "quad", c(240, 200, 140), c(255, 255, 255), { "ears_big", "tail_fluffy" }, 0.85),
			pet("Meerkat", "Uncommon", "biped", c(200, 160, 110), c(90, 70, 50), { "ears_round" }, 0.7),
			pet("Roadrunner", "Uncommon", "bird", c(120, 110, 100), c(60, 120, 200), { "beak", "crest", "wings" }),
			pet("Camel", "Rare", "quad", c(210, 170, 110), c(170, 130, 80), { "hump", "long_neck" }, 1.2),
			pet("Scorpion", "Rare", "bug", c(45, 38, 32), c(200, 60, 40), { "claws", "stinger" }),
			pet("Rattlesnake", "Epic", "serpent", c(190, 150, 90), c(110, 80, 50), { "fangs", "stripes" }),
			pet("Vulture", "Epic", "bird", c(60, 50, 45), c(240, 200, 190), { "beak", "wings" }, 1.1),
			pet("Desert Lion", "Legendary", "quad", c(230, 180, 90), c(170, 100, 40), { "mane", "tail" }, 1.2),
			pet("Mummy Cat", "Legendary", "quad", c(240, 235, 215), c(80, 200, 120), { "ears_pointy", "stripes", "glow" }),
			pet("Sand Worm", "Mythic", "serpent", c(200, 160, 100), c(150, 60, 60), { "teeth", "spikes" }, 1.4),
			pet("Sphinx Cat", "Secret", "quad", c(255, 205, 60), c(40, 90, 200), { "ears_pointy", "pharaoh" }, 1.15),
		},
	},
	{
		key = "Toxic",
		name = "Toxic Wastelands",
		emoji = "☢️",
		recommended = 1e4,
		baseIncome = 200,
		growSeconds = 45,
		floor = c(85, 95, 70),
		floorAlt = c(75, 85, 62),
		wall = c(70, 75, 60),
		wallAlt = c(60, 65, 52),
		egg = c(140, 255, 80),
		eggSpots = c(50, 70, 40),
		guardian = "Two-Headed Dog",
		pets = {
			pet("Mutant Rat", "Common", "quad", c(130, 140, 110), c(130, 255, 80), { "ears_round", "tail", "toxic_spots" }, 0.7),
			pet("Radroach", "Common", "bug", c(110, 70, 40), c(130, 255, 80), { "antenna" }, 0.8),
			pet("Toxic Fly", "Common", "bug", c(60, 70, 60), c(130, 255, 80), { "wings", "eyes_big" }, 0.7),
			pet("Sludge Slime", "Uncommon", "slime", c(110, 230, 60), c(60, 120, 30), { "drip" }),
			pet("Toxic Toad", "Uncommon", "quad", c(120, 200, 60), c(255, 230, 60), { "toxic_spots" }, 0.75),
			pet("Glow Pigeon", "Uncommon", "bird", c(140, 150, 160), c(130, 255, 80), { "beak", "wings", "glow" }),
			pet("Two-Headed Dog", "Rare", "quad", c(120, 100, 80), c(130, 255, 80), { "two_heads", "ears_pointy", "tail" }),
			pet("Acid Snail", "Rare", "slime", c(150, 255, 90), c(80, 90, 60), { "shell", "antenna", "drip" }, 0.85),
			pet("Hazmat Hound", "Epic", "quad", c(250, 210, 40), c(40, 40, 40), { "ears_pointy", "gasmask", "tail" }),
			pet("Mutant Croc", "Epic", "quad", c(70, 110, 60), c(130, 255, 80), { "tail", "spikes", "teeth" }, 1.15),
			pet("Mutant Gorilla", "Legendary", "biped", c(70, 80, 70), c(130, 255, 80), { "toxic_spots" }, 1.3),
			pet("Radioactive Wolf", "Legendary", "quad", c(60, 80, 60), c(150, 255, 90), { "ears_pointy", "tail_fluffy", "glow" }, 1.15),
			pet("Toxic Behemoth", "Mythic", "biped", c(90, 110, 70), c(170, 255, 60), { "horns", "spikes" }, 1.45),
			pet("Nuclear Hydra", "Secret", "serpent", c(60, 180, 70), c(220, 255, 90), { "three_heads" }, 1.3),
		},
	},
	{
		key = "Farmlands",
		name = "Farmlands",
		emoji = "🌾",
		recommended = 5e4,
		baseIncome = 1500,
		growSeconds = 60,
		floor = c(120, 190, 70),
		floorAlt = c(150, 120, 70),
		wall = c(200, 70, 60),
		wallAlt = c(180, 60, 52),
		egg = c(255, 240, 200),
		eggSpots = c(220, 170, 70),
		guardian = "Bull",
		pets = {
			pet("Pig", "Common", "quad", c(255, 180, 190), c(240, 140, 160), { "ears_pointy", "snout", "tail_curl" }, 0.85),
			pet("Sheep", "Common", "quad", c(250, 250, 245), c(60, 55, 55), { "wool" }, 0.9),
			pet("Chick", "Common", "bird", c(255, 230, 80), c(255, 150, 40), { "beak" }, 0.6),
			pet("Goat", "Uncommon", "quad", c(235, 230, 220), c(140, 120, 100), { "horns", "beard" }, 0.9),
			pet("Turkey", "Uncommon", "bird", c(130, 85, 50), c(220, 60, 50), { "beak", "fan_tail", "wings" }),
			pet("Donkey", "Uncommon", "quad", c(150, 140, 135), c(60, 55, 55), { "ears_long", "tail" }),
			pet("Cow", "Rare", "quad", c(250, 250, 250), c(40, 40, 40), { "horns", "spots", "ears_round" }, 1.15),
			pet("Llama", "Rare", "quad", c(240, 230, 210), c(200, 160, 120), { "ears_pointy", "wool", "long_neck" }),
			pet("Horse", "Epic", "quad", c(140, 90, 50), c(60, 40, 25), { "mane", "tail", "long_neck" }, 1.2),
			pet("Bull", "Epic", "quad", c(110, 60, 40), c(240, 230, 210), { "horns", "nose_ring" }, 1.2),
			pet("Golden Rooster", "Legendary", "bird", c(255, 200, 40), c(220, 40, 40), { "beak", "crest", "wings", "glow" }),
			pet("Scarecrow Crow", "Legendary", "bird", c(40, 40, 50), c(200, 160, 80), { "beak", "wings", "straw_hat" }),
			pet("Tractor Pig", "Mythic", "quad", c(255, 180, 190), c(230, 50, 40), { "snout", "wheels" }),
			pet("Golden Cow", "Secret", "quad", c(255, 205, 50), c(255, 245, 190), { "horns", "spots" }, 1.2),
		},
	},
	{
		key = "Enchanted",
		name = "Enchanted Forest",
		emoji = "✨",
		recommended = 2.5e5,
		baseIncome = 12000,
		growSeconds = 80,
		floor = c(110, 80, 170),
		floorAlt = c(95, 70, 150),
		wall = c(70, 50, 120),
		wallAlt = c(60, 42, 105),
		egg = c(200, 160, 255),
		eggSpots = c(140, 255, 230),
		guardian = "Griffin",
		pets = {
			pet("Pixie Moth", "Common", "bug", c(220, 180, 255), c(140, 255, 230), { "wings", "antenna", "glow" }, 0.8),
			pet("Mushroom Frog", "Common", "quad", c(120, 200, 120), c(230, 50, 50), { "mushroom_cap" }, 0.75),
			pet("Glow Snail", "Common", "slime", c(150, 240, 255), c(200, 130, 255), { "shell", "antenna", "glow" }, 0.8),
			pet("Glow Deer", "Uncommon", "quad", c(170, 230, 255), c(255, 255, 255), { "antlers", "long_neck", "glow" }),
			pet("Fairy Fox", "Uncommon", "quad", c(255, 170, 220), c(255, 255, 255), { "ears_pointy", "tail_fluffy", "wings" }),
			pet("Leaf Sprite", "Uncommon", "biped", c(120, 220, 90), c(60, 140, 50), { "leaf_hair" }, 0.7),
			pet("Crystal Owl", "Rare", "bird", c(170, 220, 255), c(255, 255, 255), { "beak", "wings", "crystal" }),
			pet("Moon Rabbit", "Rare", "quad", c(230, 230, 255), c(255, 240, 150), { "ears_long", "tail_fluffy", "glow" }, 0.85),
			pet("Unicorn", "Epic", "quad", c(255, 255, 255), c(255, 150, 230), { "horn", "mane", "tail", "long_neck" }, 1.15),
			pet("Griffin", "Epic", "quad", c(240, 200, 120), c(255, 255, 255), { "beak", "wings", "tail" }, 1.2),
			pet("Phoenix", "Legendary", "bird", c(255, 110, 30), c(255, 220, 60), { "beak", "wings", "crest", "fire" }, 1.15),
			pet("Forest Spirit", "Legendary", "slime", c(190, 255, 220), c(120, 255, 180), { "ghost", "halo" }),
			pet("Ancient Treant", "Mythic", "biped", c(110, 80, 50), c(90, 200, 80), { "leaf_hair" }, 1.5),
			pet("Fairy Dragon", "Secret", "quad", c(255, 170, 240), c(150, 255, 240), { "wings", "horns", "tail", "long_neck" }, 1.25),
		},
	},
	{
		key = "Candylands",
		name = "Candylands",
		emoji = "🍭",
		recommended = 1e6,
		baseIncome = 100000,
		growSeconds = 100,
		floor = c(255, 190, 225),
		floorAlt = c(255, 170, 210),
		wall = c(255, 120, 180),
		wallAlt = c(255, 255, 255),
		egg = c(255, 200, 230),
		eggSpots = c(120, 220, 255),
		guardian = "Giant Gummy Bear",
		pets = {
			pet("Gummy Bear", "Common", "biped", c(255, 80, 80), c(255, 140, 140), { "ears_round", "translucent" }, 0.7),
			pet("Candy Corn Chick", "Common", "bird", c(255, 200, 40), c(255, 120, 30), { "beak", "candy_corn" }, 0.7),
			pet("Jelly Bean Bug", "Common", "bug", c(200, 80, 255), c(255, 120, 200), { "antenna", "shiny" }, 0.75),
			pet("Cupcake Cat", "Uncommon", "quad", c(255, 190, 210), c(140, 90, 60), { "ears_pointy", "cherry" }),
			pet("Marshmallow Sheep", "Uncommon", "quad", c(255, 250, 250), c(255, 200, 220), { "wool" }, 0.9),
			pet("Donut Dog", "Uncommon", "quad", c(220, 160, 100), c(255, 130, 190), { "ears_round", "donut" }),
			pet("Lollipop Llama", "Rare", "quad", c(255, 120, 200), c(120, 220, 255), { "long_neck", "ears_pointy", "lollipop" }),
			pet("Cotton Candy Cloud", "Rare", "slime", c(255, 180, 230), c(160, 210, 255), { "cloud" }),
			pet("Giant Gummy Bear", "Epic", "biped", c(80, 200, 90), c(150, 255, 160), { "ears_round", "translucent" }, 1.2),
			pet("Ice Cream Penguin", "Epic", "bird", c(40, 40, 60), c(255, 230, 240), { "beak", "ice_cream" }),
			pet("Chocolate Bunny", "Legendary", "quad", c(110, 65, 35), c(80, 45, 25), { "ears_long", "tail_fluffy", "shiny" }),
			pet("Gingerbread Golem", "Legendary", "biped", c(190, 120, 60), c(255, 255, 255), { "icing" }, 1.25),
			pet("Candy Cane Serpent", "Mythic", "serpent", c(255, 255, 255), c(230, 30, 40), { "stripes", "glow" }, 1.3),
			pet("Candy Dragon", "Secret", "quad", c(255, 120, 200), c(120, 230, 255), { "wings", "horns", "stripes", "tail", "long_neck" }, 1.25),
		},
	},
	{
		key = "Halloween",
		name = "Halloween",
		emoji = "🎃",
		recommended = 5e6,
		baseIncome = 800000,
		growSeconds = 120,
		seasonal = true,
		floor = c(55, 40, 70),
		floorAlt = c(45, 32, 58),
		wall = c(40, 30, 50),
		wallAlt = c(255, 120, 20),
		egg = c(255, 130, 20),
		eggSpots = c(40, 30, 50),
		altEgg = c(250, 250, 250), -- clown eggs
		altEggSpots = c(230, 30, 40),
		guardian = "Clown",
		pets = {
			pet("Pumpkin Cat", "Common", "quad", c(40, 35, 45), c(255, 140, 20), { "ears_pointy", "pumpkin_head" }),
			pet("Spooky Bat", "Uncommon", "bird", c(50, 40, 60), c(255, 140, 20), { "wings", "ears_pointy", "fangs" }),
			pet("Skeleton Dog", "Rare", "quad", c(240, 240, 230), c(30, 30, 30), { "ears_pointy", "skeleton" }),
			pet("Ghost Owl", "Epic", "bird", c(240, 240, 255), c(160, 180, 255), { "beak", "wings", "ghost" }),
			pet("Black Cat Witch", "Legendary", "quad", c(30, 25, 35), c(140, 60, 200), { "ears_pointy", "witch_hat", "tail" }),
			pet("Headless Horse", "Mythic", "quad", c(40, 35, 40), c(255, 120, 20), { "headless", "mane", "fire", "long_neck" }, 1.25),
			pet("Clown", "Secret", "biped", c(255, 255, 255), c(230, 30, 40), { "clown" }, 1.1),
			pet("Evil Clown King", "Secret", "biped", c(240, 240, 240), c(150, 0, 30), { "clown", "crown" }, 1.3),
		},
	},
}

Config.BiomeIndex = {}
Config.PetsByName = {}
for i, biome in Config.Biomes do
	Config.BiomeIndex[biome.key] = i
	biome.index = i
	for _, p in biome.pets do
		p.biome = biome.key
		p.rarityIndex = Config.RarityIndex[p.rarity]
		Config.PetsByName[p.name] = p
	end
end

-- Walk speed of a biome's guardians: a hair slower than a player who has the
-- recommended Speed, so carrying a heavy egg there is a real chase.
function Config.guardianSpeed(biomeIndex: number): number
	local biome = Config.Biomes[biomeIndex]
	if biome.guardianSpeed then
		return biome.guardianSpeed
	end
	return math.max(14, Config.walkSpeedFor(biome.recommended) * 0.95)
end

function Config.guardianAggroRange(biomeIndex: number): number
	return 30 + biomeIndex * 5
end

function Config.activeBiomeCount(): number
	local count = 0
	for _, biome in Config.Biomes do
		if not biome.dungeon and (not biome.seasonal or Config.HalloweenEnabled) then
			count += 1
		end
	end
	return count
end

function Config.growSeconds(biomeKey: string, rarity: number): number
	local biome = Config.Biomes[Config.BiomeIndex[biomeKey]]
	return math.floor(biome.growSeconds * Config.Rarities[rarity].grow)
end

function Config.petIncome(p): number
	local biome = Config.Biomes[Config.BiomeIndex[p.biome]]
	local weightBonus = 1 + math.max(p.weight - 1, 0) * Config.WeightIncomePerKg
	return biome.baseIncome * Config.Rarities[p.rarity].income * weightBonus
end

function Config.eggValue(egg): number
	local biome = Config.Biomes[Config.BiomeIndex[egg.biome]]
	local weightBonus = 1 + math.max(egg.weight - 1, 0) * Config.WeightIncomePerKg
	return math.floor(biome.baseIncome * Config.Rarities[egg.rarity].income * weightBonus * Config.EggSellSeconds)
end

function Config.petValue(p): number
	return math.floor(Config.petIncome(p) * Config.PetSellSeconds)
end

---------------------------------------------------------------------------
-- Pen upgrades, equip slots, rebirth
---------------------------------------------------------------------------

-- style: fence and treadmill frame look for that level.
Config.PenLevels = {
	{ cost = 0, nests = 3, perStep = 1, style = "Wood" },
	{ cost = 1e3, nests = 4, perStep = 2, style = "Wood" },
	{ cost = 25e3, nests = 5, perStep = 5, style = "Stone" },
	{ cost = 5e5, nests = 6, perStep = 15, style = "Stone" },
	{ cost = 1e7, nests = 7, perStep = 50, style = "Gold" },
	{ cost = 2.5e8, nests = 8, perStep = 200, style = "Gold" },
	{ cost = 1e10, nests = 9, perStep = 1e3, style = "Neon" },
	{ cost = 5e11, nests = 10, perStep = 5e3, style = "Neon" },
}
Config.MaxNests = 10

Config.EquipSlotCosts = { 1e3, 1e4, 1e5, 1e6, 2.5e7, 5e8 } -- slot 2..7

-- Battle pets: pets that follow you and fight bosses (never biome guardians).
Config.FollowSlotCosts = { 5e4, 2e6, 1e8, 5e9 } -- slot 2..5
Config.PetAttackInterval = 1.5
Config.PetAttackRange = 70 -- studs from the boss arena centre
Config.PetBossDamage = { 2, 4, 7, 12, 20, 35, 60 } -- per attack, by rarity
Config.BaseEquipSlots = 1

Config.RebirthCosts = { 1e6, 25e6, 5e8, 1e10 }
Config.RebirthCostGrowth = 20
Config.RebirthBoost = 0.25

function Config.rebirthCost(rebirths: number): number
	local nextIndex = rebirths + 1
	if Config.RebirthCosts[nextIndex] then
		return Config.RebirthCosts[nextIndex]
	end
	local last = Config.RebirthCosts[#Config.RebirthCosts]
	return last * Config.RebirthCostGrowth ^ (nextIndex - #Config.RebirthCosts)
end

---------------------------------------------------------------------------
-- Trails and treadmills
---------------------------------------------------------------------------

Config.Trails = {
	{ key = "Grey", name = "Grey Trail", rarity = "Common", mult = 1.5, cost = 100, colors = { c(200, 200, 205), c(140, 140, 150) } },
	{ key = "Green", name = "Green Trail", rarity = "Uncommon", mult = 2, cost = 5e3, colors = { c(90, 255, 110), c(30, 170, 60) } },
	{ key = "Blue", name = "Blue Trail", rarity = "Rare", mult = 2.5, cost = 75e3, colors = { c(80, 190, 255), c(30, 90, 230) } },
	{ key = "Purple", name = "Purple Trail", rarity = "Epic", mult = 3, cost = 1.5e6, colors = { c(200, 110, 255), c(120, 40, 220) } },
	{ key = "Golden", name = "Golden Trail", rarity = "Legendary", mult = 3.5, cost = 3e7, colors = { c(255, 230, 120), c(230, 170, 30) } },
	{ key = "Red", name = "Red Trail", rarity = "Mythic", mult = 4, cost = 7.5e8, colors = { c(255, 90, 80), c(180, 20, 30) } },
	{ key = "Galaxy", name = "Galaxy Trail", rarity = "Cosmic", mult = 5, cost = 2e10, colors = { c(120, 70, 255), c(255, 120, 230) } },
	{ key = "Secret", name = "Secret Trail", rarity = "Secret", mult = 7, cost = 5e11, colors = { c(255, 255, 255), c(20, 20, 20) } },
	{ key = "Eternal", name = "Eternal Trail", rarity = "Eternal", mult = 10, cost = 1.25e13, colors = { c(255, 120, 255), c(120, 255, 255) } },
	{ key = "Divine", name = "Divine Trail", rarity = "Divine", mult = 14, cost = 3e14, colors = { c(255, 220, 60), c(60, 200, 255) } },
	{ key = "Moonbloom", name = "Moonbloom Trail", rarity = "Divine", mult = 20, cost = 5e15, robux = "MoonbloomTrail", colors = { c(140, 255, 230), c(60, 140, 255) } },
	{ key = "Pumpkin", name = "Pumpkin Trail", rarity = "Event", mult = 8, cost = 0, event = true, colors = { c(255, 140, 20), c(60, 20, 80) } },
}

Config.Treadmills = {
	{ key = "Wooden", name = "Wooden Mill", theme = "Wood", mult = 1, cost = 0 },
	{ key = "Stone", name = "Stone Grinder", theme = "Stone", mult = 1.5, cost = 5e4 },
	{ key = "Sandstorm", name = "Sandstorm Runner", theme = "Sand", mult = 2, cost = 2e6 },
	{ key = "Toxic", name = "Toxic Pump", theme = "Toxic", mult = 3, cost = 1e8 },
	{ key = "Hay", name = "Hay Harvester", theme = "Hay", mult = 4, cost = 5e9 },
	{ key = "Fairy", name = "Fairy Wheel", theme = "Fairy", mult = 6, cost = 2.5e11 },
	{ key = "Candy", name = "Candy Conveyor", theme = "Candy", mult = 8, cost = 1e13 },
	{ key = "Pumpkin", name = "Pumpkin Stomper", theme = "Pumpkin", mult = 6, cost = 0, event = true },
	{ key = "VIPNeon", name = "VIP Neon Mill", theme = "Neon", mult = 5, cost = 0, vip = true },
	{ key = "CornyTopHat", name = "Corny's Top Hat", theme = "TopHat", mult = 25000, cost = 0, ownerOnly = true },
}

Config.TrailsByKey = {}
for i, trail in Config.Trails do
	trail.order = i
	Config.TrailsByKey[trail.key] = trail
end
Config.TreadmillsByKey = {}
for i, mill in Config.Treadmills do
	mill.order = i
	Config.TreadmillsByKey[mill.key] = mill
end

-- Halloween hatch drops (per Halloween egg hatched, if not owned yet).
Config.PumpkinTrailDropChance = 0.02
Config.PumpkinStomperDropChance = 0.02

---------------------------------------------------------------------------
-- Robux: paste your IDs from the Creator Dashboard. 0 = not set up yet.
---------------------------------------------------------------------------

Config.GamePasses = {
	Growth = { id = 0, name = "x2 Growth", price = 399, desc = "Eggs Grow x2 faster!", giftProduct = 0 },
	Money = { id = 0, name = "x2 Money", price = 349, desc = "Get x2 Money!", giftProduct = 0 },
	Speed = { id = 0, name = "x2 Speed", price = 299, desc = "DOUBLE your treadmill speed!", giftProduct = 0 },
	VIP = { id = 0, name = "VIP", price = 449, desc = "Neon Mill, +1 slot, x1.25 money & luck, daily VIP egg!", giftProduct = 0 },
	AutoHatch = { id = 0, name = "Auto Hatch", price = 149, desc = "Ready eggs hatch by themselves!", giftProduct = 0 },
}

-- kind: what the product grants. amount: how much.
Config.Products = {
	FeaturedEgg1 = { id = 0, kind = "FeaturedEgg", amount = 1, price = 89 },
	FeaturedEgg3 = { id = 0, kind = "FeaturedEgg", amount = 3, price = 219 },
	FeaturedEgg10 = { id = 0, kind = "FeaturedEgg", amount = 10, price = 699 },
	FeaturedEgg50 = { id = 0, kind = "FeaturedEgg", amount = 50, price = 2999 },
	Speed150K = { id = 0, kind = "Speed", amount = 150e3, price = 69 },
	Speed1M = { id = 0, kind = "Speed", amount = 1e6, price = 219 },
	Speed10M = { id = 0, kind = "Speed", amount = 10e6, price = 599 },
	Speed50M = { id = 0, kind = "Speed", amount = 50e6, price = 1299 },
	Speed500M = { id = 0, kind = "Speed", amount = 500e6, price = 1749 },
	Speed1B = { id = 0, kind = "Speed", amount = 1e9, price = 2599 },
	Money25K = { id = 0, kind = "Money", amount = 25e3, price = 45 },
	Money200K = { id = 0, kind = "Money", amount = 200e3, price = 89 },
	Money800K = { id = 0, kind = "Money", amount = 800e3, price = 219 },
	Money4M = { id = 0, kind = "Money", amount = 4e6, price = 449 },
	Money8M = { id = 0, kind = "Money", amount = 8e6, price = 699 },
	SkipGrow = { id = 0, kind = "SkipGrow", amount = 1, price = 25 },
	MoonbloomTrail = { id = 0, kind = "Trail", trail = "Moonbloom", amount = 1, price = 999 },
}

-- What the featured egg is: biome and egg rarity granted per purchase.
Config.FeaturedEgg = { name = "Pumpkin Egg", biome = "Halloween", rarity = 4, endsAt = 1793577600 } -- Nov 2 2026 UTC, update per event

---------------------------------------------------------------------------
-- Free rewards
---------------------------------------------------------------------------

Config.GroupRewardSpeed = 10000

-- Money rewards scale with income so they stay useful: max(base, income * seconds).
Config.DailyRewards = {
	{ money = 500, incomeSeconds = 60 },
	{ money = 1000, incomeSeconds = 120 },
	{ money = 2500, incomeSeconds = 180 },
	{ money = 5000, incomeSeconds = 300 },
	{ money = 10000, incomeSeconds = 450 },
	{ money = 20000, incomeSeconds = 600 },
	{ egg = 3, money = 0 }, -- day 7: Rare egg from the best biome you've reached
}

-- Playtime gifts reset every day. egg = rarity of a free egg from your best biome.
Config.PlaytimeGifts = {
	{ minutes = 2, money = 500, incomeSeconds = 60 },
	{ minutes = 5, speed = 1000, speedSteps = 300 },
	{ minutes = 10, egg = 2 },
	{ minutes = 15, money = 2500, incomeSeconds = 240 },
	{ minutes = 20, egg = 3 },
	{ minutes = 30, speed = 5000, speedSteps = 900 },
	{ minutes = 45, egg = 4 },
	{ minutes = 60, money = 10000, incomeSeconds = 900 },
	{ minutes = 90, egg = 5 },
	{ minutes = 120, egg = 6 },
}

-- Background music. Each area cross-fades to its own track.
-- When an id is "", the server picks a licensed track from Roblox's music library by
-- searching the keywords below. Paste an id (e.g. "rbxassetid://1234567890") to lock one in.
Config.MusicVolume = 0.35
Config.Music = {
	Lobby = { id = "", search = { "happy upbeat", "cheerful", "fun game" } },
	Dungeon = { id = "", search = { "boss battle", "epic battle", "intense" } },
	Forest = { id = "", search = { "forest", "peaceful nature", "adventure" } },
	Desert = { id = "", search = { "desert", "arabian", "egypt" } },
	Toxic = { id = "", search = { "industrial", "dark synth", "toxic" } },
	Farmlands = { id = "", search = { "country", "banjo", "farm" } },
	Enchanted = { id = "", search = { "magical", "fantasy", "enchanted" } },
	Candylands = { id = "", search = { "candy", "bubbly", "sweet" } },
	Halloween = { id = "", search = { "halloween", "spooky", "haunted" } },
}

-- Shown when a player opens the Roblox menu (usually about to leave). Once per day.
Config.LeaveReward = { egg = 3, money = 2000, incomeSeconds = 300 }

Config.FriendBoost = 2 -- money multiplier while a Roblox friend is in your server

Config.IndexSetBonus = 0.02 -- +2% money per completed biome set

---------------------------------------------------------------------------
-- Sounds (built-in engine sounds; swap for Creator Store IDs any time)
---------------------------------------------------------------------------

Config.Sounds = {
	Swing = "rbxasset://sounds/swordlunge.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
	Notify = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Alert = "rbxasset://sounds/electronicpingshort.wav",
}

---------------------------------------------------------------------------
-- Formatting helpers
---------------------------------------------------------------------------

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Config.format(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local text = if n == math.floor(n) then tostring(n) else string.format("%.1f", n)
		return (negative and "-" or "") .. text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text = if scaled >= 100 then string.format("%d", math.floor(scaled)) else string.format("%.1f", math.floor(scaled * 10) / 10)
	text = text:gsub("%.0$", "")
	return (negative and "-" or "") .. text .. SUFFIXES[tier + 1]
end

function Config.formatWithCommas(n: number): string
	if n >= 1e6 then
		return Config.format(n)
	end
	local text = tostring(math.floor(n))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

function Config.formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

function Config.rarityColor(rarity: number): Color3
	return Config.Rarities[rarity].color
end

return Config

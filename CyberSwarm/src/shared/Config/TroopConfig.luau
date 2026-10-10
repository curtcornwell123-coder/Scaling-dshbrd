--!strict
--[[
	TroopConfig
	The Troop Depot catalog. Shop fields (role, price, currency, unlock requirement, model builder,
	description) are declared here; combat fields (name, HP, SPD, COST, rarity) are read from
	RobotConfig so the shop can never disagree with the robot that actually spawns.

	Stock: the Permanent troops are always on their tables. RotatingCount more are drawn each UTC
	day from RotatingPool with a seed derived from the day number, so every server shows the same
	rotation without talking to each other.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local RobotConfig = require(script.Parent.RobotConfig)

type ShopEntry = {
	role: string,
	price: number,
	currency: Types.Currency,
	unlock: Types.UnlockRequirement,
	builderId: string,
}

local NONE: Types.UnlockRequirement = { kind = "None", value = 0 }

local shopEntries: { [string]: ShopEntry } = {
	Scout = { role = "Rusher", price = 0, currency = "Coins", unlock = NONE, builderId = "Orb" },
	Brute = { role = "Tank", price = 0, currency = "Coins", unlock = NONE, builderId = "Heavy" },
	Medic = { role = "Support", price = 400, currency = "Coins", unlock = NONE, builderId = "Orb" },
	Glitch = { role = "Disruptor", price = 600, currency = "Coins", unlock = NONE, builderId = "Walker" },
	Drone = { role = "Flyer", price = 500, currency = "Coins", unlock = NONE, builderId = "Hover" },
	Bomber = { role = "Demolition", price = 800, currency = "Coins", unlock = NONE, builderId = "Orb" },
	Sentinel = {
		role = "Defensive Tank",
		price = 900,
		currency = "Coins",
		unlock = { kind = "OwnsTroop", value = 0, troopId = "Brute" },
		builderId = "Heavy",
	},
	Sapper = { role = "Saboteur", price = 450, currency = "Coins", unlock = NONE, builderId = "Walker" },
	Striker = { role = "Melee", price = 400, currency = "Coins", unlock = NONE, builderId = "Lancer" },
	Relay = { role = "Booster", price = 60, currency = "Gems", unlock = NONE, builderId = "Lancer" },
	Mortar = {
		role = "Artillery",
		price = 120,
		currency = "Gems",
		unlock = { kind = "HighestWave", value = 8 },
		builderId = "Heavy",
	},
	Phantom = {
		role = "Infiltrator",
		price = 100,
		currency = "Gems",
		unlock = { kind = "Wins", value = 5 },
		builderId = "Orb",
	},
	MegaMech = {
		role = "Boss",
		price = 250,
		currency = "Gems",
		unlock = { kind = "Wins", value = 3 },
		builderId = "Heavy",
	},
	Crawler = { role = "Swarmer", price = 300, currency = "Coins", unlock = NONE, builderId = "Walker" },
	Juggernaut = { role = "Siege", price = 1200, currency = "Coins", unlock = NONE, builderId = "Heavy" },
	Hornet = { role = "Gunship", price = 80, currency = "Gems", unlock = NONE, builderId = "Hover" },
}

local TroopConfig = {}

local troops: { [string]: Types.TroopDef } = {}
for robotId, entry in shopEntries do
	local robot = RobotConfig.Robots[robotId]
	if robot == nil then
		continue
	end
	troops[robotId] = {
		id = robotId,
		name = robot.displayName,
		role = entry.role,
		hp = robot.health,
		spd = robot.speed,
		cost = robot.cost,
		rarity = robot.rarity,
		price = entry.price,
		currency = entry.currency,
		unlock = entry.unlock,
		builderId = entry.builderId,
		description = robot.description,
		comingSoon = robot.locked,
	}
end
TroopConfig.Troops = troops

-- Every catalog troop, in RobotConfig display order.
TroopConfig.Order = RobotConfig.Order

-- Always on the first three tables.
TroopConfig.Permanent = { "Medic", "Drone", "MegaMech" }

-- Drawn per UTC day for the other three tables.
TroopConfig.RotatingPool = {
	"Glitch",
	"Bomber",
	"Sentinel",
	"Sapper",
	"Striker",
	"Relay",
	"Mortar",
	"Phantom",
	"Crawler",
	"Juggernaut",
	"Hornet",
}
TroopConfig.RotatingCount = 3
TroopConfig.RotationSeed = 7919

-- Model builders the shared RobotModels module knows how to make.
TroopConfig.Builders = { "Orb", "Heavy", "Walker", "Hover", "Lancer" }

return TableUtil.deepFreeze(TroopConfig)

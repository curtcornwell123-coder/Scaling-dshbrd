--!strict
--[[
	RobotConfig
	Every robot the player can send. To add a robot: add an entry to Robots, add its id to Order,
	and (optionally) drop a Model at ServerStorage/Assets/<modelPath>. Abilities reuse the kinds
	implemented in RobotService (Heal, Disable, Explode); ConfigValidator checks their fields.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local CYAN = Color3.fromRGB(0, 238, 255)
local MAGENTA = Color3.fromRGB(255, 46, 196)

local RobotConfig = {}

-- Typed up front so the literal union survives (the old type solver widens inline literals).
local SAPPER_IMMUNITIES: { Types.Immunity } = { "Stun", "Slow" }
local SLOW_IMMUNE: { Types.Immunity } = { "Slow" }

RobotConfig.Rarities = { "Common", "Uncommon", "Rare", "Epic" }

local Robots: { [string]: Types.RobotDef } = {
	Scout = {
		id = "Scout",
		displayName = "Scout",
		description = "Cheap and fast. Floods the lane before towers can react.",
		rarity = "Common",
		cost = 10,
		health = 32,
		speed = 15,
		damage = 5,
		flying = false,
		abilities = {},
		modelPath = "Robots/Scout",
		visual = { size = Vector3.new(2, 2, 2), color = CYAN, accent = MAGENTA, shape = "Ball" },
		locked = false,
		upgradeCosts = { 30, 60, 120 },
	},
	Brute = {
		id = "Brute",
		displayName = "Brute",
		description = "Slow, armored, and hard to stop. Soaks tower fire for the swarm.",
		rarity = "Common",
		cost = 25,
		health = 170,
		speed = 7,
		damage = 14,
		flying = false,
		abilities = {},
		modelPath = "Robots/Brute",
		visual = { size = Vector3.new(4, 4, 4), color = MAGENTA, accent = CYAN, shape = "Block" },
		locked = false,
		upgradeCosts = { 40, 80, 160 },
	},
	Medic = {
		id = "Medic",
		displayName = "Medic",
		description = "Repairs nearby robots every second.",
		rarity = "Uncommon",
		cost = 30,
		health = 70,
		speed = 10,
		damage = 4,
		flying = false,
		abilities = {
			{ kind = "Heal", radius = 12, amount = 7, interval = 1 },
		},
		modelPath = "Robots/Medic",
		visual = {
			size = Vector3.new(2.6, 2.6, 2.6),
			color = CYAN,
			accent = Color3.fromRGB(64, 255, 156),
			shape = "Ball",
		},
		locked = false,
		upgradeCosts = { 45, 90, 180 },
	},
	Glitch = {
		id = "Glitch",
		displayName = "Glitch",
		description = "Hacks the nearest tower and shuts it down for a few seconds.",
		rarity = "Rare",
		cost = 35,
		health = 55,
		speed = 12,
		damage = 5,
		flying = false,
		abilities = {
			{ kind = "Disable", radius = 16, duration = 2.5, cooldown = 7 },
		},
		modelPath = "Robots/Glitch",
		visual = { size = Vector3.new(2.4, 2.4, 2.4), color = MAGENTA, accent = CYAN, shape = "Block" },
		locked = false,
		upgradeCosts = { 50, 100, 200 },
	},
	Drone = {
		id = "Drone",
		displayName = "Drone",
		description = "Flies over the lane. Ground-only towers cannot hit it.",
		rarity = "Uncommon",
		cost = 30,
		health = 45,
		speed = 13,
		damage = 6,
		flying = true,
		abilities = {},
		modelPath = "Robots/Drone",
		visual = { size = Vector3.new(2.4, 1.2, 2.4), color = CYAN, accent = MAGENTA, shape = "Block" },
		locked = false,
		upgradeCosts = { 45, 90, 180 },
	},
	Bomber = {
		id = "Bomber",
		displayName = "Bomber",
		description = "Rolls up to a tower and detonates, damaging every tower nearby.",
		rarity = "Rare",
		cost = 40,
		health = 80,
		speed = 9,
		damage = 10,
		flying = false,
		abilities = {
			{ kind = "Explode", triggerRadius = 9, radius = 13, damage = 110 },
		},
		modelPath = "Robots/Bomber",
		visual = { size = Vector3.new(3, 3, 3), color = MAGENTA, accent = Color3.fromRGB(255, 202, 64), shape = "Ball" },
		locked = false,
		upgradeCosts = { 60, 120, 240 },
	},
	Sentinel = {
		id = "Sentinel",
		displayName = "Sentinel",
		description = "Heavy shield unit. Robots near it take a third less damage.",
		rarity = "Rare",
		cost = 45,
		health = 260,
		speed = 6,
		damage = 12,
		flying = false,
		abilities = {
			{ kind = "Guard", radius = 10, reduction = 0.33 },
		},
		modelPath = "Robots/Sentinel",
		visual = {
			size = Vector3.new(4.4, 4.2, 3.4),
			color = CYAN,
			accent = Color3.fromRGB(242, 193, 0),
			shape = "Block",
		},
		locked = false,
		upgradeCosts = { 60, 120, 240 },
	},
	Sapper = {
		id = "Sapper",
		displayName = "Sapper",
		description = "Shrugs off EMP stuns and cryo slows, and cuts power to nearby towers.",
		rarity = "Uncommon",
		cost = 30,
		health = 60,
		speed = 11,
		damage = 5,
		flying = false,
		abilities = {
			{ kind = "Disable", radius = 12, duration = 1.5, cooldown = 5 },
		},
		modelPath = "Robots/Sapper",
		visual = {
			size = Vector3.new(2.4, 2, 2.4),
			color = MAGENTA,
			accent = Color3.fromRGB(242, 193, 0),
			shape = "Block",
		},
		locked = false,
		upgradeCosts = { 45, 90, 180 },
		immunities = SAPPER_IMMUNITIES,
	},
	Striker = {
		id = "Striker",
		displayName = "Striker",
		description = "Fast melee unit that slashes towers as it runs past.",
		rarity = "Uncommon",
		cost = 25,
		health = 50,
		speed = 17,
		damage = 6,
		flying = false,
		abilities = {
			{ kind = "Strike", radius = 8, damage = 18, cooldown = 1.5 },
		},
		modelPath = "Robots/Striker",
		visual = { size = Vector3.new(1.8, 2.6, 1.8), color = CYAN, accent = MAGENTA, shape = "Block" },
		locked = false,
		upgradeCosts = { 40, 80, 160 },
	},
	Relay = {
		id = "Relay",
		displayName = "Relay",
		description = "Signal booster. Nearby robots move 25% faster.",
		rarity = "Rare",
		cost = 35,
		health = 65,
		speed = 10,
		damage = 4,
		flying = false,
		abilities = {
			{ kind = "Boost", radius = 12, amount = 0.25, duration = 1.5, interval = 1 },
		},
		modelPath = "Robots/Relay",
		visual = {
			size = Vector3.new(2.2, 3, 2.2),
			color = CYAN,
			accent = Color3.fromRGB(86, 214, 146),
			shape = "Ball",
		},
		locked = false,
		upgradeCosts = { 50, 100, 200 },
	},
	Mortar = {
		id = "Mortar",
		displayName = "Mortar",
		description = "Slow artillery robot that shells towers from long range.",
		rarity = "Epic",
		cost = 50,
		health = 90,
		speed = 5,
		damage = 10,
		flying = false,
		abilities = {
			{ kind = "Bombard", radius = 34, damage = 30, cooldown = 4 },
		},
		modelPath = "Robots/Mortar",
		visual = { size = Vector3.new(3.4, 2.6, 3.4), color = MAGENTA, accent = CYAN, shape = "Block" },
		locked = false,
		upgradeCosts = { 70, 140, 280 },
	},
	Phantom = {
		id = "Phantom",
		displayName = "Phantom",
		description = "Cloaks every few seconds; towers cannot target it while cloaked.",
		rarity = "Epic",
		cost = 40,
		health = 55,
		speed = 13,
		damage = 7,
		flying = false,
		abilities = {
			{ kind = "Stealth", duration = 2.5, cooldown = 6 },
		},
		modelPath = "Robots/Phantom",
		visual = { size = Vector3.new(2.2, 2.2, 2.2), color = MAGENTA, accent = CYAN, shape = "Ball" },
		locked = false,
		upgradeCosts = { 60, 120, 240 },
	},
	MegaMech = {
		id = "MegaMech",
		displayName = "Mega Mech",
		description = "A walking fortress that soaks up a whole defense line.",
		rarity = "Epic",
		cost = 250,
		health = 1500,
		speed = 5,
		damage = 120,
		flying = false,
		abilities = {},
		modelPath = "Robots/MegaMech",
		visual = { size = Vector3.new(7, 8, 7), color = MAGENTA, accent = CYAN, shape = "Block" },
		locked = false,
		upgradeCosts = { 300, 600 },
	},
	Crawler = {
		id = "Crawler",
		displayName = "Crawler",
		description = "Low spider bot. Cheap, quick, and shrugs off slows.",
		rarity = "Common",
		cost = 12,
		health = 40,
		speed = 14,
		damage = 6,
		flying = false,
		abilities = {},
		immunities = SLOW_IMMUNE,
		modelPath = "Robots/Crawler",
		visual = { size = Vector3.new(2.6, 1.4, 2.6), color = CYAN, accent = MAGENTA, shape = "Block" },
		locked = false,
		upgradeCosts = { 30, 60, 120 },
	},
	Juggernaut = {
		id = "Juggernaut",
		displayName = "Juggernaut",
		description = "Armoured siege tank that pounds towers as it rolls in.",
		rarity = "Rare",
		cost = 70,
		health = 420,
		speed = 5,
		damage = 30,
		flying = false,
		abilities = {
			{ kind = "Strike", radius = 10, damage = 25, cooldown = 2.5 },
		},
		modelPath = "Robots/Juggernaut",
		visual = {
			size = Vector3.new(4.6, 3.4, 5),
			color = MAGENTA,
			accent = Color3.fromRGB(242, 193, 0),
			shape = "Block",
		},
		locked = false,
		upgradeCosts = { 90, 180, 360 },
	},
	Hornet = {
		id = "Hornet",
		displayName = "Hornet",
		description = "Fast gunship that strafes towers from the air.",
		rarity = "Rare",
		cost = 35,
		health = 70,
		speed = 15,
		damage = 9,
		flying = true,
		abilities = {
			{ kind = "Strike", radius = 14, damage = 8, cooldown = 1.2 },
		},
		modelPath = "Robots/Hornet",
		visual = {
			size = Vector3.new(2.4, 1.2, 2.8),
			color = CYAN,
			accent = Color3.fromRGB(242, 193, 0),
			shape = "Block",
		},
		locked = false,
		upgradeCosts = { 50, 100, 200 },
	},
}
RobotConfig.Robots = Robots

-- Display order in the shop, loadout editor, and validator.
RobotConfig.Order = {
	"Scout",
	"Brute",
	"Medic",
	"Glitch",
	"Drone",
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
	"MegaMech",
}

-- Robots every new profile owns and equips.
RobotConfig.DefaultUnlocked = { "Scout", "Brute" }

-- Each upgrade level adds this fraction of the base value (level 2 Brute = +40% health).
local upgradeRules: Types.RobotUpgradeRules = {
	healthPerLevel = 0.2,
	damagePerLevel = 0.15,
}
RobotConfig.Upgrade = upgradeRules

-- Studs above the lane that flying robots cruise at.
RobotConfig.FlyingAltitude = 9

return TableUtil.deepFreeze(RobotConfig)

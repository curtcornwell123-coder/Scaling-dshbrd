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

RobotConfig.Rarities = { "Common", "Rare", "Epic", "Legendary" }

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
		unlockCost = 0,
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
		unlockCost = 0,
		locked = false,
		upgradeCosts = { 40, 80, 160 },
	},
	Medic = {
		id = "Medic",
		displayName = "Medic",
		description = "Repairs nearby robots every second.",
		rarity = "Rare",
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
		unlockCost = 400,
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
		unlockCost = 600,
		locked = false,
		upgradeCosts = { 50, 100, 200 },
	},
	Drone = {
		id = "Drone",
		displayName = "Drone",
		description = "Flies over the lane. Ground-only towers cannot hit it.",
		rarity = "Rare",
		cost = 30,
		health = 45,
		speed = 13,
		damage = 6,
		flying = true,
		abilities = {},
		modelPath = "Robots/Drone",
		visual = { size = Vector3.new(2.4, 1.2, 2.4), color = CYAN, accent = MAGENTA, shape = "Block" },
		unlockCost = 500,
		locked = false,
		upgradeCosts = { 45, 90, 180 },
	},
	Bomber = {
		id = "Bomber",
		displayName = "Bomber",
		description = "Rolls up to a tower and detonates, damaging every tower nearby.",
		rarity = "Epic",
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
		unlockCost = 800,
		locked = false,
		upgradeCosts = { 60, 120, 240 },
	},
	MegaMech = {
		id = "MegaMech",
		displayName = "Mega Mech",
		description = "A walking fortress. Coming soon.",
		rarity = "Legendary",
		cost = 250,
		health = 1500,
		speed = 5,
		damage = 120,
		flying = false,
		abilities = {},
		modelPath = "Robots/MegaMech",
		visual = { size = Vector3.new(7, 8, 7), color = MAGENTA, accent = CYAN, shape = "Block" },
		unlockCost = 5000,
		locked = true,
		upgradeCosts = { 300, 600 },
	},
}
RobotConfig.Robots = Robots

-- Display order in the shop, loadout editor, and validator.
RobotConfig.Order = { "Scout", "Brute", "Medic", "Glitch", "Drone", "Bomber", "MegaMech" }

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

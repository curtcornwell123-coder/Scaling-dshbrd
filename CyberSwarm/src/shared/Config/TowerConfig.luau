--!strict
--[[
	TowerConfig
	Base stats for the AI military defense. Mutations never edit these values; they are layered on
	top by StatResolver, so these numbers always describe an un-mutated tower. To add a tower: add
	an entry here, add its id to Order, and reference it from WaveConfig.DefensePlan.
	Ids match the design spec (BasicTurret, RapidTurret, ...); displayName carries the military name.
	visual.color is the tower body, visual.accent is its targeting light.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local OLIVE = Color3.fromRGB(78, 90, 50)
local KHAKI = Color3.fromRGB(150, 136, 96)
local GUNMETAL = Color3.fromRGB(46, 50, 54)
local ALERT_RED = Color3.fromRGB(255, 52, 40)
local AMBER = Color3.fromRGB(255, 170, 30)
local ICE_BLUE = Color3.fromRGB(120, 200, 255)

local TowerConfig = {}

local Towers: { [string]: Types.TowerDef } = {
	BasicTurret = {
		id = "BasicTurret",
		displayName = "Rifle Turret",
		description = "Standard-issue automatic rifle. Single target, hits ground and air.",
		damage = 9,
		fireRate = 1.25,
		range = 22,
		maxHealth = 160,
		splashRadius = 0,
		targetsGround = true,
		targetsAir = true,
		slowMultiplier = 1,
		slowDuration = 0,
		modelPath = "Towers/BasicTurret",
		visual = { size = Vector3.new(3, 1.6, 3), color = OLIVE, accent = ALERT_RED, shape = "Block" },
	},
	RapidTurret = {
		id = "RapidTurret",
		displayName = "Gatling Nest",
		description = "Rotary gun that shreds light robots with a stream of weak rounds.",
		damage = 3,
		fireRate = 5,
		range = 18,
		maxHealth = 120,
		splashRadius = 0,
		targetsGround = true,
		targetsAir = true,
		slowMultiplier = 1,
		slowDuration = 0,
		modelPath = "Towers/RapidTurret",
		visual = { size = Vector3.new(2.6, 1.4, 2.6), color = KHAKI, accent = AMBER, shape = "Block" },
	},
	Cannon = {
		id = "Cannon",
		displayName = "Howitzer",
		description = "Heavy artillery shells that splash ground robots. Cannot hit aircraft.",
		damage = 20,
		fireRate = 0.6,
		range = 24,
		maxHealth = 220,
		splashRadius = 8,
		targetsGround = true,
		targetsAir = false,
		slowMultiplier = 1,
		slowDuration = 0,
		modelPath = "Towers/Cannon",
		visual = { size = Vector3.new(3.6, 2, 3.6), color = GUNMETAL, accent = ALERT_RED, shape = "Block" },
	},
	AntiAir = {
		id = "AntiAir",
		displayName = "Flak Cannon",
		description = "Radar-guided flak that locks onto flying robots only.",
		damage = 15,
		fireRate = 2,
		range = 30,
		maxHealth = 140,
		splashRadius = 0,
		targetsGround = false,
		targetsAir = true,
		slowMultiplier = 1,
		slowDuration = 0,
		modelPath = "Towers/AntiAir",
		visual = { size = Vector3.new(3, 3, 3), color = OLIVE, accent = AMBER, shape = "Ball" },
	},
	FreezeTower = {
		id = "FreezeTower",
		displayName = "Cryo Mortar",
		description = "Freezing mortar rounds that halve a robot's speed for a short time.",
		damage = 2,
		fireRate = 1,
		range = 18,
		maxHealth = 150,
		splashRadius = 0,
		targetsGround = true,
		targetsAir = true,
		slowMultiplier = 0.5,
		slowDuration = 2,
		modelPath = "Towers/FreezeTower",
		visual = { size = Vector3.new(2.8, 2.8, 2.8), color = KHAKI, accent = ICE_BLUE, shape = "Ball" },
	},
}
TowerConfig.Towers = Towers

TowerConfig.Order = { "BasicTurret", "RapidTurret", "Cannon", "AntiAir", "FreezeTower" }

return TableUtil.deepFreeze(TowerConfig)

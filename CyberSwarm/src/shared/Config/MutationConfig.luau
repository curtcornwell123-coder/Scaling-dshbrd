--!strict
--[[
	MutationConfig
	The stacking upgrades the AI military defense gains after every wave. Mutations are pure data: each one
	is a list of modifiers on tower stats. StatResolver applies them from the base stats each time,
	so stacking is linear and predictable:

		final = (base + sum(add * stacks)) * (1 + sum((multiplier - 1) * stacks)), then capped.

	Two stacks of a 1.25x mutation give 1.5x, not 1.5625x. To add a mutation: add an entry to
	Mutations and its id to Order. Stats must be names from Constants.TOWER_STATS.

	Military names map to the design spec's mechanics:
		Rapid Reload = Overclock, Reactive Armor = Armor Plating, EMP Strike = EMP Pulse,
		Shrapnel Rounds = Chain Lightning, Field Engineers = Regen Core, Sniper Scopes = Long Range,
		Flak Barrage = Scrap Magnet, Fortifications = Reinforced Frame.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local MutationConfig = {}

local rarities: { [string]: Types.MutationRarityDef } = {
	Common = { weight = 60 },
	Rare = { weight = 30 },
	Mythic = { weight = 10 },
}
MutationConfig.Rarities = rarities

MutationConfig.RarityOrder = { "Common", "Rare", "Mythic" }

local mutations: { [string]: Types.MutationDef } = {
	RapidReload = {
		id = "RapidReload",
		displayName = "Rapid Reload",
		rarity = "Common",
		description = "Gun crews drill faster reloads. Towers fire 25% faster.",
		modifiers = { { stat = "fireRate", multiplier = 1.25 } },
		maxStacks = 6,
	},
	ReactiveArmor = {
		id = "ReactiveArmor",
		displayName = "Reactive Armor",
		rarity = "Rare",
		description = "Explosive plating. Each tower ignores the first hit it takes from every robot.",
		modifiers = { { stat = "armorHits", add = 1 } },
		maxStacks = 3,
	},
	EmpStrike = {
		id = "EmpStrike",
		displayName = "EMP Strike",
		rarity = "Rare",
		description = "Towers fire an EMP burst every few seconds, stunning robots in range.",
		modifiers = { { stat = "empStun", add = 0.6 } },
		maxStacks = 4,
	},
	ShrapnelRounds = {
		id = "ShrapnelRounds",
		displayName = "Shrapnel Rounds",
		rarity = "Mythic",
		description = "Every shot fragments into one more nearby robot.",
		modifiers = { { stat = "chainCount", add = 1 } },
		maxStacks = 4,
	},
	FieldEngineers = {
		id = "FieldEngineers",
		displayName = "Field Engineers",
		rarity = "Common",
		description = "Combat engineers repair every tower for 4 health per second.",
		modifiers = { { stat = "regenPerSecond", add = 4 } },
		maxStacks = 5,
	},
	SniperScopes = {
		id = "SniperScopes",
		displayName = "Sniper Scopes",
		rarity = "Common",
		description = "Long-range optics. Tower range +15%.",
		modifiers = { { stat = "range", multiplier = 1.15 } },
		maxStacks = 5,
	},
	FlakBarrage = {
		id = "FlakBarrage",
		displayName = "Flak Barrage",
		rarity = "Rare",
		description = "Flak forces flying robots down low enough for ground guns to hit.",
		modifiers = { { stat = "magnet", add = 1 } },
		maxStacks = 1,
	},
	Fortifications = {
		id = "Fortifications",
		displayName = "Fortifications",
		rarity = "Common",
		description = "Sandbags and steel. Tower health +30%.",
		modifiers = { { stat = "maxHealth", multiplier = 1.3 } },
		maxStacks = 5,
	},
}
MutationConfig.Mutations = mutations

MutationConfig.Order = {
	"RapidReload",
	"ReactiveArmor",
	"EmpStrike",
	"ShrapnelRounds",
	"FieldEngineers",
	"SniperScopes",
	"FlakBarrage",
	"Fortifications",
}

-- Numbers used by the mutation behaviours themselves (not by stacking).
local tuning: Types.MutationTuning = {
	empPulseInterval = 6,
	chainRange = 14,
	chainDamageFactor = 0.6,
	magnetAltitudeScale = 0.3,
}
MutationConfig.Tuning = tuning

-- Hard ceilings so long matches stay readable and never produce absurd values.
local statCaps: { [string]: number } = {
	fireRate = 12,
	range = 60,
	armorHits = 3,
	empStun = 2.5,
	chainCount = 4,
	regenPerSecond = 25,
	magnet = 1,
}
MutationConfig.StatCaps = statCaps

return TableUtil.deepFreeze(MutationConfig)

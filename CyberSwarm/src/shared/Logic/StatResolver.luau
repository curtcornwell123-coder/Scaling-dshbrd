--!strict
--[[
	StatResolver
	The one place tower and robot stats are computed. Tower stats are always rebuilt from the
	untouched TowerConfig base plus the full mutation stack, which is what keeps stacking correct:
	nothing is ever multiplied onto an already-mutated value.
]]

local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Constants)

local StatResolver = {}

-- Mutation id -> number of stacks applied.
export type StackCounts = { [string]: number }

function StatResolver.baseTowerStats(tower: Types.TowerDef): Types.StatBlock
	local stats: Types.StatBlock = {}
	for _, statName in Constants.TOWER_STATS do
		stats[statName] = 0
	end
	stats.damage = tower.damage
	stats.fireRate = tower.fireRate
	stats.range = tower.range
	stats.maxHealth = tower.maxHealth
	stats.splashRadius = tower.splashRadius
	stats.slowDuration = tower.slowDuration
	return stats
end

-- Applies every stacked mutation to `base`. Additive bonuses and multiplier bonuses are summed
-- separately, then combined once: (base + adds) * (1 + multiplierBonuses), then capped.
function StatResolver.resolve(
	base: Types.StatBlock,
	counts: StackCounts,
	mutations: { [string]: Types.MutationDef },
	caps: { [string]: number }
): Types.StatBlock
	local adds: { [string]: number } = {}
	local multiplierBonuses: { [string]: number } = {}

	for mutationId, stacks in counts do
		local mutation = mutations[mutationId]
		if mutation ~= nil and stacks > 0 then
			for _, modifier in mutation.modifiers do
				local add = modifier.add
				if add ~= nil then
					adds[modifier.stat] = (adds[modifier.stat] or 0) + add * stacks
				end
				local multiplier = modifier.multiplier
				if multiplier ~= nil then
					multiplierBonuses[modifier.stat] = (multiplierBonuses[modifier.stat] or 0) + (multiplier - 1) * stacks
				end
			end
		end
	end

	local resolved: Types.StatBlock = {}
	for statName, baseValue in base do
		local scale = math.max(0, 1 + (multiplierBonuses[statName] or 0))
		local value = (baseValue + (adds[statName] or 0)) * scale
		local cap = caps[statName]
		if cap ~= nil then
			value = math.min(value, cap)
		end
		resolved[statName] = value
	end
	return resolved
end

-- Robot upgrades scale linearly from the base config value per level.
function StatResolver.robotStats(
	robot: Types.RobotDef,
	level: number,
	rules: Types.RobotUpgradeRules
): (number, number)
	local health = robot.health * (1 + rules.healthPerLevel * level)
	local damage = robot.damage * (1 + rules.damagePerLevel * level)
	return health, damage
end

return StatResolver

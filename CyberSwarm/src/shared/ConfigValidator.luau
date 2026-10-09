--!strict
--[[
	ConfigValidator
	Checks every Config module for missing fields, wrong types, and references to unknown ids.
	The server runs it at startup and warns about each problem; the test suite runs it against
	both the real config and deliberately broken fixtures. It never throws, so a config mistake
	shows up as a clear warning instead of a crash deep inside gameplay code.
]]

local Constants = require(script.Parent.Constants)
local RobotConfig = require(script.Parent.Config.RobotConfig)
local TowerConfig = require(script.Parent.Config.TowerConfig)
local MutationConfig = require(script.Parent.Config.MutationConfig)
local MapConfig = require(script.Parent.Config.MapConfig)
local WaveConfig = require(script.Parent.Config.WaveConfig)
local ModeConfig = require(script.Parent.Config.ModeConfig)
local TableUtil = require(script.Parent.Util.TableUtil)

-- Configs are typed loosely here on purpose: the validator must cope with malformed input.
export type ConfigSet = {
	robots: { [string]: any },
	robotOrder: { string },
	robotRarities: { string },
	defaultUnlocked: { string },
	towers: { [string]: any },
	towerOrder: { string },
	mutations: { [string]: any },
	mutationOrder: { string },
	mutationRarities: { [string]: any },
	mutationRarityOrder: { string },
	maps: { [string]: any },
	mapOrder: { string },
	modes: { [string]: any },
	modeOrder: { string },
	defensePlan: { [any]: any },
}

local ConfigValidator = {}

local isTable = TableUtil.isTable

type Issues = { string }

local function expect(issues: Issues, path: string, value: any, typeName: string)
	if typeof(value) ~= typeName then
		table.insert(issues, `{path} should be a {typeName} (got {typeof(value)})`)
	end
end

local function expectPositive(issues: Issues, path: string, value: any)
	if typeof(value) ~= "number" then
		table.insert(issues, `{path} should be a number (got {typeof(value)})`)
	elseif value < 0 then
		table.insert(issues, `{path} should not be negative (got {value})`)
	end
end

local function checkVisual(issues: Issues, path: string, visual: any)
	if not isTable(visual) then
		table.insert(issues, `{path}.visual is missing`)
		return
	end
	expect(issues, path .. ".visual.size", visual.size, "Vector3")
	expect(issues, path .. ".visual.color", visual.color, "Color3")
	expect(issues, path .. ".visual.accent", visual.accent, "Color3")
	if visual.shape ~= "Block" and visual.shape ~= "Ball" then
		table.insert(issues, `{path}.visual.shape must be "Block" or "Ball"`)
	end
end

-- Every id in `order` must exist, and every entry must appear in `order` exactly once.
local function checkOrder(issues: Issues, label: string, entries: { [string]: any }, order: { string })
	local seen: { [string]: boolean } = {}
	for _, id in order do
		if entries[id] == nil then
			table.insert(issues, `{label}.Order references unknown id "{id}"`)
		end
		if seen[id] then
			table.insert(issues, `{label}.Order lists "{id}" more than once`)
		end
		seen[id] = true
	end
	for id in entries do
		if not seen[id] then
			table.insert(issues, `{label}.Order is missing "{id}"`)
		end
	end
end

local function checkIdMatchesKey(issues: Issues, path: string, key: string, entry: any)
	if entry.id ~= key then
		table.insert(issues, `{path}.id should equal its key "{key}"`)
	end
end

local function validateRobots(issues: Issues, set: ConfigSet)
	for key, robot in set.robots do
		local path = `RobotConfig.Robots.{key}`
		if not isTable(robot) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, robot)
		expect(issues, path .. ".displayName", robot.displayName, "string")
		expect(issues, path .. ".description", robot.description, "string")
		expect(issues, path .. ".modelPath", robot.modelPath, "string")
		expect(issues, path .. ".flying", robot.flying, "boolean")
		expect(issues, path .. ".locked", robot.locked, "boolean")
		for _, field in { "cost", "health", "speed", "damage", "unlockCost" } do
			expectPositive(issues, `{path}.{field}`, robot[field])
		end
		if typeof(robot.health) == "number" and robot.health <= 0 then
			table.insert(issues, `{path}.health must be greater than 0`)
		end
		if typeof(robot.speed) == "number" and robot.speed <= 0 then
			table.insert(issues, `{path}.speed must be greater than 0`)
		end
		if not table.find(set.robotRarities, robot.rarity) then
			table.insert(issues, `{path}.rarity "{tostring(robot.rarity)}" is not a known robot rarity`)
		end
		checkVisual(issues, path, robot.visual)

		if not isTable(robot.upgradeCosts) then
			table.insert(issues, `{path}.upgradeCosts should be a table`)
		else
			for index, cost in robot.upgradeCosts do
				expectPositive(issues, `{path}.upgradeCosts[{index}]`, cost)
			end
		end

		if not isTable(robot.abilities) then
			table.insert(issues, `{path}.abilities should be a table`)
		else
			for index, ability in robot.abilities do
				local abilityPath = `{path}.abilities[{index}]`
				local fields = if isTable(ability) then Constants.ABILITY_FIELDS[ability.kind] else nil
				if fields == nil then
					table.insert(issues, `{abilityPath}.kind is not a known ability kind`)
				else
					for _, field in fields do
						expectPositive(issues, `{abilityPath}.{field}`, ability[field])
					end
				end
			end
		end
	end

	checkOrder(issues, "RobotConfig", set.robots, set.robotOrder)
	if #set.defaultUnlocked == 0 then
		table.insert(issues, "RobotConfig.DefaultUnlocked must contain at least one robot")
	end
	if #set.defaultUnlocked > Constants.MAX_LOADOUT then
		table.insert(issues, "RobotConfig.DefaultUnlocked has more robots than fit in a loadout")
	end
	for _, robotId in set.defaultUnlocked do
		local robot = set.robots[robotId]
		if robot == nil then
			table.insert(issues, `RobotConfig.DefaultUnlocked references unknown robot "{robotId}"`)
		elseif isTable(robot) and robot.locked then
			table.insert(issues, `RobotConfig.DefaultUnlocked includes locked robot "{robotId}"`)
		end
	end
end

local function validateTowers(issues: Issues, set: ConfigSet)
	for key, tower in set.towers do
		local path = `TowerConfig.Towers.{key}`
		if not isTable(tower) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, tower)
		expect(issues, path .. ".displayName", tower.displayName, "string")
		expect(issues, path .. ".description", tower.description, "string")
		expect(issues, path .. ".modelPath", tower.modelPath, "string")
		expect(issues, path .. ".targetsGround", tower.targetsGround, "boolean")
		expect(issues, path .. ".targetsAir", tower.targetsAir, "boolean")
		for _, field in { "damage", "fireRate", "range", "maxHealth", "splashRadius", "slowMultiplier", "slowDuration" } do
			expectPositive(issues, `{path}.{field}`, tower[field])
		end
		if typeof(tower.fireRate) == "number" and tower.fireRate <= 0 then
			table.insert(issues, `{path}.fireRate must be greater than 0`)
		end
		if tower.targetsGround == false and tower.targetsAir == false then
			table.insert(issues, `{path} cannot target anything`)
		end
		checkVisual(issues, path, tower.visual)
	end
	checkOrder(issues, "TowerConfig", set.towers, set.towerOrder)
end

local function validateMutations(issues: Issues, set: ConfigSet)
	for key, mutation in set.mutations do
		local path = `MutationConfig.Mutations.{key}`
		if not isTable(mutation) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, mutation)
		expect(issues, path .. ".displayName", mutation.displayName, "string")
		expect(issues, path .. ".description", mutation.description, "string")
		if set.mutationRarities[mutation.rarity] == nil then
			table.insert(issues, `{path}.rarity "{tostring(mutation.rarity)}" is not in MutationConfig.Rarities`)
		end
		if typeof(mutation.maxStacks) ~= "number" or mutation.maxStacks < 1 then
			table.insert(issues, `{path}.maxStacks must be a number of at least 1`)
		end
		if not isTable(mutation.modifiers) or #mutation.modifiers == 0 then
			table.insert(issues, `{path}.modifiers must list at least one modifier`)
		else
			for index, modifier in mutation.modifiers do
				local modifierPath = `{path}.modifiers[{index}]`
				if not isTable(modifier) then
					table.insert(issues, `{modifierPath} is not a table`)
					continue
				end
				if not table.find(Constants.TOWER_STATS, modifier.stat) then
					table.insert(issues, `{modifierPath}.stat "{tostring(modifier.stat)}" is not a tower stat`)
				end
				if modifier.add == nil and modifier.multiplier == nil then
					table.insert(issues, `{modifierPath} needs an add or a multiplier`)
				end
				if modifier.add ~= nil then
					expect(issues, modifierPath .. ".add", modifier.add, "number")
				end
				if modifier.multiplier ~= nil then
					expectPositive(issues, modifierPath .. ".multiplier", modifier.multiplier)
				end
			end
		end
	end
	checkOrder(issues, "MutationConfig", set.mutations, set.mutationOrder)
	for rarityName, rarity in set.mutationRarities do
		if not isTable(rarity) then
			table.insert(issues, `MutationConfig.Rarities.{rarityName} is not a table`)
		else
			expectPositive(issues, `MutationConfig.Rarities.{rarityName}.weight`, rarity.weight)
		end
		if not table.find(set.mutationRarityOrder, rarityName) then
			table.insert(issues, `MutationConfig.RarityOrder is missing "{rarityName}"`)
		end
	end
end

local function validateMaps(issues: Issues, set: ConfigSet)
	for key, map in set.maps do
		local path = `MapConfig.Maps.{key}`
		if not isTable(map) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, map)
		expect(issues, path .. ".displayName", map.displayName, "string")
		expect(issues, path .. ".description", map.description, "string")
		expect(issues, path .. ".templateName", map.templateName, "string")
		expect(issues, path .. ".builtIn", map.builtIn, "boolean")
		if typeof(map.laneCount) ~= "number" or map.laneCount < 1 then
			table.insert(issues, `{path}.laneCount must be at least 1`)
		end
		if typeof(map.baseHealth) ~= "number" or map.baseHealth <= 0 then
			table.insert(issues, `{path}.baseHealth must be greater than 0`)
		end
	end
	checkOrder(issues, "MapConfig", set.maps, set.mapOrder)
end

local function validateModes(issues: Issues, set: ConfigSet)
	for key, mode in set.modes do
		local path = `ModeConfig.Modes.{key}`
		if not isTable(mode) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, mode)
		expect(issues, path .. ".displayName", mode.displayName, "string")
		expect(issues, path .. ".padColor", mode.padColor, "Color3")
		if mode.sideLayout ~= "Shared" and mode.sideLayout ~= "PerPlayer" then
			table.insert(issues, `{path}.sideLayout must be "Shared" or "PerPlayer"`)
		end
		if typeof(mode.minPlayers) ~= "number" or typeof(mode.maxPlayers) ~= "number" then
			table.insert(issues, `{path} needs numeric minPlayers and maxPlayers`)
		elseif mode.minPlayers < 1 or mode.maxPlayers < mode.minPlayers then
			table.insert(issues, `{path} needs 1 <= minPlayers <= maxPlayers`)
		end
		if typeof(mode.maxWaves) ~= "number" or mode.maxWaves < 1 then
			table.insert(issues, `{path}.maxWaves must be at least 1`)
		end
		expectPositive(issues, path .. ".queueCountdown", mode.queueCountdown)
		expectPositive(issues, path .. ".baseHealthPerExtraPlayer", mode.baseHealthPerExtraPlayer)
		if not isTable(mode.rewards) then
			table.insert(issues, `{path}.rewards is missing`)
		else
			for _, field in { "winCoins", "lossCoins", "perWaveCoins" } do
				expectPositive(issues, `{path}.rewards.{field}`, mode.rewards[field])
			end
		end
		if not isTable(mode.mapPool) or #mode.mapPool == 0 then
			table.insert(issues, `{path}.mapPool must list at least one map`)
		else
			for _, mapId in mode.mapPool do
				if set.maps[mapId] == nil then
					table.insert(issues, `{path}.mapPool references unknown map "{tostring(mapId)}"`)
				end
			end
		end
	end
	checkOrder(issues, "ModeConfig", set.modes, set.modeOrder)
end

local function validateDefensePlan(issues: Issues, set: ConfigSet)
	for wave, towerIds in set.defensePlan do
		if typeof(wave) ~= "number" or wave < 1 or wave % 1 ~= 0 then
			table.insert(issues, `WaveConfig.DefensePlan key {tostring(wave)} must be a positive whole wave number`)
		end
		if not isTable(towerIds) then
			table.insert(issues, `WaveConfig.DefensePlan[{tostring(wave)}] must be a list of tower ids`)
			continue
		end
		for _, towerId in towerIds do
			if set.towers[towerId] == nil then
				table.insert(
					issues,
					`WaveConfig.DefensePlan[{tostring(wave)}] references unknown tower "{tostring(towerId)}"`
				)
			end
		end
	end
end

function ConfigValidator.validate(set: ConfigSet): { string }
	local issues: Issues = {}
	validateRobots(issues, set)
	validateTowers(issues, set)
	validateMutations(issues, set)
	validateMaps(issues, set)
	validateModes(issues, set)
	validateDefensePlan(issues, set)
	return issues
end

-- Builds a ConfigSet from the live Config modules. Tests copy and break this to prove detection works.
function ConfigValidator.gameConfigSet(): ConfigSet
	return {
		robots = RobotConfig.Robots,
		robotOrder = RobotConfig.Order,
		robotRarities = RobotConfig.Rarities,
		defaultUnlocked = RobotConfig.DefaultUnlocked,
		towers = TowerConfig.Towers,
		towerOrder = TowerConfig.Order,
		mutations = MutationConfig.Mutations,
		mutationOrder = MutationConfig.Order,
		mutationRarities = MutationConfig.Rarities,
		mutationRarityOrder = MutationConfig.RarityOrder,
		maps = MapConfig.Maps,
		mapOrder = MapConfig.Order,
		modes = ModeConfig.Modes,
		modeOrder = ModeConfig.Order,
		defensePlan = WaveConfig.DefensePlan,
	}
end

function ConfigValidator.validateGame(): { string }
	return ConfigValidator.validate(ConfigValidator.gameConfigSet())
end

return ConfigValidator

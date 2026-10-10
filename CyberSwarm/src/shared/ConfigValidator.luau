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
local TroopConfig = require(script.Parent.Config.TroopConfig)
local QuestConfig = require(script.Parent.Config.QuestConfig)
local SeasonConfig = require(script.Parent.Config.SeasonConfig)
local ShopConfig = require(script.Parent.Config.ShopConfig)
local RankConfig = require(script.Parent.Config.RankConfig)
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
	troops: { [string]: any },
	troopPermanent: { string },
	troopRotatingPool: { string },
	troopBuilders: { string },
	quests: { [string]: any },
	questPools: { { string } },
	seasonTiers: { any },
	seasonTierCount: number,
	products: { [string]: any },
	rankTiers: { any },
	ratingKeys: { [string]: string },
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

local UNLOCK_KINDS = { "None", "Wins", "HighestWave", "OwnsTroop", "LoadoutSize", "MatchesPlayed" }

local function checkRequirement(issues: Issues, path: string, requirement: any, set: ConfigSet)
	if not isTable(requirement) or not table.find(UNLOCK_KINDS, requirement.kind) then
		table.insert(issues, `{path}.kind is not a known unlock kind`)
		return
	end
	expectPositive(issues, path .. ".value", requirement.value)
	local troopId: any = requirement.troopId
	if requirement.kind == "OwnsTroop" and (typeof(troopId) ~= "string" or set.robots[troopId] == nil) then
		table.insert(issues, `{path}.troopId "{tostring(troopId)}" is not a known troop`)
	end
end

local function checkReward(issues: Issues, path: string, reward: any, set: ConfigSet)
	if not isTable(reward) then
		table.insert(issues, `{path} should be a reward table`)
		return
	end
	for _, field in { "coins", "gems", "xp" } do
		if reward[field] ~= nil then
			expectPositive(issues, `{path}.{field}`, reward[field])
		end
	end
	if reward.troopId ~= nil and set.robots[reward.troopId] == nil then
		table.insert(issues, `{path}.troopId "{tostring(reward.troopId)}" is not a known troop`)
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
		for _, field in { "cost", "health", "speed", "damage" } do
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
		expect(issues, path .. ".description", mode.description, "string")
		expect(issues, path .. ".signColor", mode.signColor, "Color3")
		expect(issues, path .. ".ranked", mode.ranked, "boolean")
		expect(issues, path .. ".requiresParty", mode.requiresParty, "boolean")
		expect(issues, path .. ".rewardsEnabled", mode.rewardsEnabled, "boolean")
		expect(issues, path .. ".sandbox", mode.sandbox, "boolean")
		if not table.find({ "Casual", "Ranked", "Coop", "Limited" }, mode.category) then
			table.insert(issues, `{path}.category must be Casual, Ranked, Coop, or Limited`)
		end
		if typeof(mode.minPlayers) ~= "number" or typeof(mode.maxPlayers) ~= "number" then
			table.insert(issues, `{path} needs numeric minPlayers and maxPlayers`)
		elseif mode.minPlayers < 1 or mode.maxPlayers < mode.minPlayers then
			table.insert(issues, `{path} needs 1 <= minPlayers <= maxPlayers`)
		end
		if
			typeof(mode.teams) ~= "number"
			or typeof(mode.teamSize) ~= "number"
			or mode.teams < 1
			or mode.teamSize < 1
		then
			table.insert(issues, `{path} needs teams and teamSize of at least 1`)
		elseif mode.teams > 1 and mode.minPlayers ~= mode.teams * mode.teamSize then
			table.insert(issues, `{path}: team modes need minPlayers = teams * teamSize`)
		elseif mode.teams == 1 and typeof(mode.maxPlayers) == "number" and mode.maxPlayers > mode.teamSize then
			table.insert(issues, `{path}: one-team modes need maxPlayers <= teamSize`)
		end
		if
			typeof(mode.queueCap) ~= "number"
			or typeof(mode.maxPlayers) ~= "number"
			or mode.queueCap < mode.maxPlayers
		then
			table.insert(issues, `{path}.queueCap must be at least maxPlayers`)
		end
		expectPositive(issues, path .. ".bayOrder", mode.bayOrder)
		expectPositive(issues, path .. ".estimatedWait", mode.estimatedWait)
		if mode.ranked == true and set.ratingKeys[key] == nil then
			table.insert(issues, `{path} is ranked but RankConfig.RatingKeys has no entry for it`)
		end
		if not isTable(mode.unlock) then
			table.insert(issues, `{path}.unlock should be a list of requirements`)
		else
			for index, requirement in mode.unlock do
				checkRequirement(issues, `{path}.unlock[{index}]`, requirement, set)
			end
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

local function validateTroops(issues: Issues, set: ConfigSet)
	for robotId in set.robots do
		local troop = set.troops[robotId]
		local path = `TroopConfig.Troops.{robotId}`
		if not isTable(troop) then
			table.insert(issues, `{path} is missing (every robot needs a Troop Depot entry)`)
			continue
		end
		expect(issues, path .. ".role", troop.role, "string")
		expectPositive(issues, path .. ".price", troop.price)
		if troop.currency ~= "Coins" and troop.currency ~= "Gems" then
			table.insert(issues, `{path}.currency must be "Coins" or "Gems"`)
		end
		if not table.find(set.troopBuilders, troop.builderId) then
			table.insert(issues, `{path}.builderId "{tostring(troop.builderId)}" is not a known model builder`)
		end
		checkRequirement(issues, path .. ".unlock", troop.unlock, set)
	end
	local seen: { [string]: boolean } = {}
	for _, list in { set.troopPermanent, set.troopRotatingPool } do
		for _, troopId in list do
			if set.troops[troopId] == nil then
				table.insert(issues, `TroopConfig stock references unknown troop "{troopId}"`)
			end
			if seen[troopId] then
				table.insert(issues, `TroopConfig lists "{troopId}" in stock more than once`)
			end
			seen[troopId] = true
		end
	end
end

local function validateQuests(issues: Issues, set: ConfigSet)
	local kinds = { "PlayMatches", "WinMatches", "CompleteWaves", "DeployRobots", "TryTroops", "TestRealmWaves" }
	for key, quest in set.quests do
		local path = `QuestConfig.Quests.{key}`
		if not isTable(quest) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, quest)
		expect(issues, path .. ".description", quest.description, "string")
		expect(issues, path .. ".testRealm", quest.testRealm, "boolean")
		if not table.find(kinds, quest.kind) then
			table.insert(issues, `{path}.kind is not a known quest kind`)
		end
		if typeof(quest.target) ~= "number" or quest.target < 1 then
			table.insert(issues, `{path}.target must be at least 1`)
		end
		checkReward(issues, path .. ".reward", quest.reward, set)
	end
	for _, pool in set.questPools do
		for _, questId in pool do
			if set.quests[questId] == nil then
				table.insert(issues, `QuestConfig pool references unknown quest "{questId}"`)
			end
		end
	end
end

local function validateSeason(issues: Issues, set: ConfigSet)
	if #set.seasonTiers ~= set.seasonTierCount then
		table.insert(issues, `SeasonConfig.Tiers has {#set.seasonTiers} tiers but TierCount is {set.seasonTierCount}`)
	end
	for index, tier in set.seasonTiers do
		local path = `SeasonConfig.Tiers[{index}]`
		if not isTable(tier) or tier.tier ~= index then
			table.insert(issues, `{path}.tier should equal {index}`)
			continue
		end
		if tier.free ~= nil then
			checkReward(issues, path .. ".free", tier.free, set)
		end
		if tier.premium ~= nil then
			checkReward(issues, path .. ".premium", tier.premium, set)
		end
	end
end

local function validateProducts(issues: Issues, set: ConfigSet)
	for key, product in set.products do
		local path = `ShopConfig.Products.{key}`
		if not isTable(product) then
			table.insert(issues, `{path} is not a table`)
			continue
		end
		checkIdMatchesKey(issues, path, key, product)
		expectPositive(issues, path .. ".productId", product.productId)
		checkReward(issues, path .. ".reward", product.reward, set)
	end
end

local function validateRank(issues: Issues, set: ConfigSet)
	local previous = -math.huge
	for index, tier in set.rankTiers do
		local path = `RankConfig.Tiers[{index}]`
		if not isTable(tier) or typeof(tier.floor) ~= "number" or tier.floor <= previous then
			table.insert(issues, `{path}.floor must be a number above the previous tier's floor`)
			continue
		end
		previous = tier.floor
		if typeof(tier.divisions) ~= "number" or tier.divisions < 1 then
			table.insert(issues, `{path}.divisions must be at least 1`)
		end
		checkReward(issues, path .. ".seasonReward", tier.seasonReward, set)
	end
	for modeId in set.ratingKeys do
		local mode = set.modes[modeId]
		if mode == nil or not isTable(mode) or mode.ranked ~= true then
			table.insert(issues, `RankConfig.RatingKeys.{modeId} must name a ranked mode`)
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
	validateTroops(issues, set)
	validateQuests(issues, set)
	validateSeason(issues, set)
	validateProducts(issues, set)
	validateRank(issues, set)
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
		troops = TroopConfig.Troops,
		troopPermanent = TroopConfig.Permanent,
		troopRotatingPool = TroopConfig.RotatingPool,
		troopBuilders = TroopConfig.Builders,
		quests = QuestConfig.Quests,
		questPools = { QuestConfig.RegularPool, QuestConfig.TestRealmPool },
		seasonTiers = SeasonConfig.Tiers,
		seasonTierCount = SeasonConfig.TierCount,
		products = ShopConfig.Products,
		rankTiers = RankConfig.Tiers,
		ratingKeys = RankConfig.RatingKeys,
	}
end

function ConfigValidator.validateGame(): { string }
	return ConfigValidator.validate(ConfigValidator.gameConfigSet())
end

-- Setup reminders that are not errors (e.g. Robux products not created yet).
function ConfigValidator.setupWarnings(): { string }
	local warnings: { string } = {}
	for productKey, product in ShopConfig.Products do
		if product.productId == 0 then
			table.insert(
				warnings,
				`ShopConfig.Products.{productKey}.productId is 0; create the developer product and paste its id`
			)
		end
	end
	if ShopConfig.PremiumGamePassId == 0 then
		table.insert(warnings, "ShopConfig.PremiumGamePassId is 0; Season Premium is sold only as a developer product")
	end
	return warnings
end

return ConfigValidator

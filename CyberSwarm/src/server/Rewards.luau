--!strict
--[[
	Rewards
	Server wrapper around RewardRules with the live config filled in. Call it only inside a
	DataService.update mutator so the grant is saved together with whatever triggered it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local RewardRules = require(ReplicatedStorage.Shared.Logic.RewardRules)

local Rewards = {}

local seasonWindow: RewardRules.SeasonWindow = {
	seasonId = SeasonConfig.SeasonId,
	startsAt = SeasonConfig.StartsAt,
	endsAt = SeasonConfig.EndsAt,
}

function Rewards.apply(data: Types.PlayerData, reward: Types.Reward): Types.Reward
	return RewardRules.apply(data, reward, os.time(), seasonWindow, TroopConfig.Troops, Constants.MAX_LOADOUT)
end

local troopNames: { [string]: string } = {}
for troopId, troop in TroopConfig.Troops do
	troopNames[troopId] = troop.name
end

function Rewards.describe(reward: Types.Reward): string
	return RewardRules.describe(reward, troopNames)
end

return Rewards

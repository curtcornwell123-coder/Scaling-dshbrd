--!strict
--[[
	EconomyService
	The only code that changes coins. In-match coins live on the server-side MatchPlayer record;
	persistent coins and stats go through DataService at match end. All amounts come from
	WaveConfig / ModeConfig via WaveMath, never from the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local WaveConfig = require(ReplicatedStorage.Shared.Config.WaveConfig)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local WaveMath = require(ReplicatedStorage.Shared.Logic.WaveMath)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

function EconomyService.trySpend(matchPlayer: ServerTypes.MatchPlayer, amount: number): boolean
	if amount < 0 or matchPlayer.coins < amount then
		return false
	end
	matchPlayer.coins -= amount
	return true
end

function EconomyService.grant(matchPlayer: ServerTypes.MatchPlayer, amount: number)
	if amount > 0 then
		matchPlayer.coins += amount
	end
end

-- Coins for one robot that reached the HQ. Returns the amount granted.
function EconomyService.rewardArrival(matchPlayer: ServerTypes.MatchPlayer, damageDealt: number): number
	local amount = WaveMath.arrivalReward(damageDealt, WaveConfig.Rewards)
	EconomyService.grant(matchPlayer, amount)
	return amount
end

function EconomyService.rewardWaveCompletion(matchPlayer: ServerTypes.MatchPlayer, waveNumber: number): number
	local amount = WaveMath.completionBonus(waveNumber, matchPlayer.sentThisWave, WaveConfig.Rewards)
	EconomyService.grant(matchPlayer, amount)
	return amount
end

-- False when the player cannot afford even the cheapest robot in their loadout.
function EconomyService.canAffordAnyRobot(matchPlayer: ServerTypes.MatchPlayer): boolean
	local cheapest = WaveMath.cheapestCost(matchPlayer.loadout, RobotConfig.Robots)
	return cheapest ~= nil and matchPlayer.coins >= cheapest
end

-- Grants persistent coins and records stats. Returns the coins awarded.
function EconomyService.payoutMatch(player: Player, mode: Types.ModeDef, won: boolean, wavesCompleted: number): number
	local payout = WaveMath.matchPayout(won, wavesCompleted, mode.rewards)
	local saved = DataService.update(player, function(data)
		data.coins += payout
		if won then
			data.stats.wins += 1
		else
			data.stats.losses += 1
		end
		data.stats.wavesSurvived += wavesCompleted
		data.stats.highestWave = math.max(data.stats.highestWave, wavesCompleted)
	end)
	return if saved then payout else 0
end

return EconomyService

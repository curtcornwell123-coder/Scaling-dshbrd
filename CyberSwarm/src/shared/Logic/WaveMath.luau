--!strict
--[[
	WaveMath
	Pure formulas for in-match coins, swarm size limits, and end-of-match payouts. Services call
	these with values from WaveConfig / ModeConfig so the numbers stay in config and the math stays
	testable.
]]

local Types = require(script.Parent.Parent.Types)

local WaveMath = {}

-- Coins for one robot that reached the base and dealt `damageDealt`.
function WaveMath.arrivalReward(damageDealt: number, rewards: Types.WaveRewards): number
	return math.floor(rewards.perSurvivor + math.max(0, damageDealt) * rewards.perBaseDamage)
end

-- Bonus for finishing a wave. Players who sent nothing get nothing, so idling is never rewarded.
function WaveMath.completionBonus(waveNumber: number, robotsSent: number, rewards: Types.WaveRewards): number
	if robotsSent <= 0 then
		return 0
	end
	return math.floor(rewards.completionBonus + rewards.completionBonusPerWave * math.max(0, waveNumber - 1))
end

-- Total coins for a whole wave: each arrival plus the completion bonus.
function WaveMath.waveTotal(
	arrivalDamages: { number },
	waveNumber: number,
	robotsSent: number,
	rewards: Types.WaveRewards
): number
	local total = 0
	for _, damage in arrivalDamages do
		total += WaveMath.arrivalReward(damage, rewards)
	end
	return total + WaveMath.completionBonus(waveNumber, robotsSent, rewards)
end

-- Maximum robots one player may queue in a given wave.
function WaveMath.robotCap(waveNumber: number, rules: Types.RobotCapRules): number
	return math.min(rules.max, rules.base + rules.perWave * math.max(0, waveNumber - 1))
end

-- Persistent coins granted when a match ends.
function WaveMath.matchPayout(won: boolean, wavesCompleted: number, rewards: Types.MatchRewards): number
	local base = if won then rewards.winCoins else rewards.lossCoins
	return math.floor(base + rewards.perWaveCoins * math.max(0, wavesCompleted))
end

-- Cheapest robot a player could still buy; nil when the loadout is empty.
function WaveMath.cheapestCost(loadout: { string }, robots: { [string]: Types.RobotDef }): number?
	local cheapest: number? = nil
	for _, robotId in loadout do
		local robot = robots[robotId]
		if robot ~= nil and (cheapest == nil or robot.cost < cheapest) then
			cheapest = robot.cost
		end
	end
	return cheapest
end

return WaveMath

--!strict
--[[
	WaveConfig
	Pacing, in-match economy, swarm size limits, and the AI defense build order.
	DefensePlan[n] lists the towers the AI adds at the start of wave n; towers fill a map's
	TowerSlots in slot order, so map authors control placement priority by numbering slots.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local WaveConfig = {}

-- Phase durations in seconds.
WaveConfig.countdownDuration = 5
WaveConfig.preparingDuration = 15
WaveConfig.waveResultDuration = 4
WaveConfig.matchEndDuration = 8
-- Safety net: a wave that runs this long ends and any robots still walking are scrapped.
WaveConfig.maxWaveDuration = 150

-- Seconds between robots leaving the same lane, so the swarm reads as a stream not a blob.
WaveConfig.spawnSpacing = 0.6

-- Coins each player starts a match with.
WaveConfig.startingCoins = 120

local rewards: Types.WaveRewards = {
	perSurvivor = 5,
	perBaseDamage = 0.5,
	completionBonus = 30,
	completionBonusPerWave = 6,
}
WaveConfig.Rewards = rewards

-- Wave size: how many robots one player may queue per wave.
local robotCap: Types.RobotCapRules = {
	base = 12,
	perWave = 2,
	max = 40,
}
WaveConfig.RobotCap = robotCap

local defensePlan: { [number]: { string } } = {
	[1] = { "BasicTurret", "BasicTurret" },
	[2] = { "RapidTurret" },
	[3] = { "FreezeTower" },
	[4] = { "Cannon" },
	[5] = { "AntiAir" },
	[7] = { "BasicTurret" },
	[9] = { "RapidTurret" },
	[6] = { "Flamethrower" },
	[8] = { "Railgun" },
	[10] = { "MissilePod" },
	[11] = { "Cannon" },
	[13] = { "Flamethrower" },
	[15] = { "MissilePod" },
}
WaveConfig.DefensePlan = defensePlan

return TableUtil.deepFreeze(WaveConfig)

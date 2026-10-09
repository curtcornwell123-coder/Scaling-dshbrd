--!strict
--[[
	ModeConfig
	Match modes and meta-progression payouts. MatchService builds every match from these entries,
	so Solo, 1v1, and Co-op share one code path:
		sideLayout "Shared"    -> one arena, all players attack it together (Solo, Co-op)
		sideLayout "PerPlayer" -> one arena per player, first core destroyed wins (1v1)
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local ModeConfig = {}

local modes: { [string]: Types.ModeDef } = {
	Solo = {
		id = "Solo",
		displayName = "Solo",
		description = "You versus the mutating defense.",
		minPlayers = 1,
		maxPlayers = 1,
		sideLayout = "Shared",
		maxWaves = 20,
		queueCountdown = 3,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 150, lossCoins = 25, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0,
		padColor = Color3.fromRGB(0, 238, 255),
	},
	Versus = {
		id = "Versus",
		displayName = "1v1",
		description = "Race a rival. First to break their core wins.",
		minPlayers = 2,
		maxPlayers = 2,
		sideLayout = "PerPlayer",
		maxWaves = 20,
		queueCountdown = 5,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 250, lossCoins = 40, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0,
		padColor = Color3.fromRGB(255, 46, 196),
	},
	Coop = {
		id = "Coop",
		displayName = "Co-op",
		description = "Up to four players swarm one defense together.",
		minPlayers = 2,
		maxPlayers = 4,
		sideLayout = "Shared",
		maxWaves = 25,
		queueCountdown = 10,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 200, lossCoins = 30, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0.75,
		padColor = Color3.fromRGB(176, 92, 255),
	},
}
ModeConfig.Modes = modes

ModeConfig.Order = { "Solo", "Versus", "Coop" }

-- Starting values for brand-new profiles.
ModeConfig.ProfileDefaults = {
	coins = 100,
	gems = 0,
	musicVolume = 0.5,
	sfxVolume = 0.7,
}

return TableUtil.deepFreeze(ModeConfig)

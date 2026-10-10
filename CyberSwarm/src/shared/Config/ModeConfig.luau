--!strict
--[[
	ModeConfig
	Every match mode, fully data-driven. The Duels Hall builds one bay per mode with bayOrder > 0,
	the queue matchmakes from these fields, and MatchService builds arenas from them, so a new mode
	is a new entry here (plus a map) with no queue or match code changes.

		teams = 1      everyone attacks one defense together (Solo, Co-op)
		teams = 2+     each team races on its own arena; first to break its target core wins
		ranked         rating on the line (RankConfig.RatingKeys maps the mode to a rating)
		unlock         requirements checked on the server before a player may queue
		category       sign colour family: Casual (white), Ranked (gold), Coop (green), Limited

	LimitedBayOrder reserves a bay for a rotating limited-time mode. It stays an empty
	"coming soon" bay until a mode with category "Limited" and that bayOrder is added.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local CASUAL_WHITE = Color3.fromRGB(236, 240, 246)
local RANKED_GOLD = Color3.fromRGB(242, 193, 0)
local COOP_GREEN = Color3.fromRGB(86, 214, 146)
local SANDBOX_CYAN = Color3.fromRGB(64, 196, 226)

-- Ranked modes keep fresh and throwaway accounts out: a full loadout and some casual experience.
local RANKED_UNLOCK: { Types.UnlockRequirement } = {
	{ kind = "LoadoutSize", value = 5 },
	{ kind = "MatchesPlayed", value = 10 },
}

local ModeConfig = {}

local modes: { [string]: Types.ModeDef } = {
	Solo = {
		id = "Solo",
		displayName = "Solo",
		description = "You versus the mutating defense.",
		teams = 1,
		teamSize = 1,
		minPlayers = 1,
		maxPlayers = 1,
		ranked = false,
		requiresParty = false,
		unlock = {},
		rewardsEnabled = true,
		category = "Casual",
		signColor = CASUAL_WHITE,
		bayOrder = 1,
		queueCap = 40,
		queueCountdown = 3,
		estimatedWait = 3,
		maxWaves = 20,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 150, lossCoins = 25, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0,
		sandbox = false,
	},
	Duel = {
		id = "Duel",
		displayName = "1v1 Casual",
		description = "Race a rival. First to break the other's core wins. No rating.",
		teams = 2,
		teamSize = 1,
		minPlayers = 2,
		maxPlayers = 2,
		ranked = false,
		requiresParty = false,
		unlock = {},
		rewardsEnabled = true,
		category = "Casual",
		signColor = CASUAL_WHITE,
		bayOrder = 2,
		queueCap = 40,
		queueCountdown = 5,
		estimatedWait = 30,
		maxWaves = 20,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 250, lossCoins = 40, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0,
		sandbox = false,
	},
	DuelRanked = {
		id = "DuelRanked",
		displayName = "1v1 Ranked",
		description = "Same race, rating on the line.",
		teams = 2,
		teamSize = 1,
		minPlayers = 2,
		maxPlayers = 2,
		ranked = true,
		requiresParty = false,
		unlock = RANKED_UNLOCK,
		rewardsEnabled = true,
		category = "Ranked",
		signColor = RANKED_GOLD,
		bayOrder = 3,
		queueCap = 40,
		queueCountdown = 5,
		estimatedWait = 45,
		maxWaves = 20,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 300, lossCoins = 40, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0,
		sandbox = false,
	},
	Squad = {
		id = "Squad",
		displayName = "3v3 Casual",
		description = "Two teams of three, each racing to break the other team's core.",
		teams = 2,
		teamSize = 3,
		minPlayers = 6,
		maxPlayers = 6,
		ranked = false,
		requiresParty = false,
		unlock = {},
		rewardsEnabled = true,
		category = "Casual",
		signColor = CASUAL_WHITE,
		bayOrder = 4,
		queueCap = 48,
		queueCountdown = 6,
		estimatedWait = 60,
		maxWaves = 20,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 250, lossCoins = 40, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0.6,
		sandbox = false,
	},
	SquadRanked = {
		id = "SquadRanked",
		displayName = "3v3 Ranked",
		description = "Team race with team rating on the line.",
		teams = 2,
		teamSize = 3,
		minPlayers = 6,
		maxPlayers = 6,
		ranked = true,
		requiresParty = false,
		unlock = RANKED_UNLOCK,
		rewardsEnabled = true,
		category = "Ranked",
		signColor = RANKED_GOLD,
		bayOrder = 5,
		queueCap = 48,
		queueCountdown = 6,
		estimatedWait = 90,
		maxWaves = 20,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 300, lossCoins = 40, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0.6,
		sandbox = false,
	},
	Coop = {
		id = "Coop",
		displayName = "Co-op",
		description = "Two to four players versus one defense together.",
		teams = 1,
		teamSize = 4,
		minPlayers = 2,
		maxPlayers = 4,
		ranked = false,
		requiresParty = false,
		unlock = {},
		rewardsEnabled = true,
		category = "Coop",
		signColor = COOP_GREEN,
		bayOrder = 6,
		queueCap = 40,
		queueCountdown = 10,
		estimatedWait = 30,
		maxWaves = 25,
		mapPool = { "Junkyard" },
		rewards = { winCoins = 200, lossCoins = 30, perWaveCoins = 8 },
		baseHealthPerExtraPlayer = 0.75,
		sandbox = false,
	},
	-- Not a Duels Hall bay: entered through the Test Realm portal in the Troop Depot.
	TestRealm = {
		id = "TestRealm",
		displayName = "Test Realm",
		description = "Try any troop against any defense. Nothing is earned or lost.",
		teams = 1,
		teamSize = 4,
		minPlayers = 1,
		maxPlayers = 4,
		ranked = false,
		requiresParty = false,
		unlock = {},
		rewardsEnabled = false,
		category = "Casual",
		signColor = SANDBOX_CYAN,
		bayOrder = 0,
		queueCap = 4,
		queueCountdown = 0,
		estimatedWait = 0,
		maxWaves = 999,
		mapPool = { "TestYard" },
		rewards = { winCoins = 0, lossCoins = 0, perWaveCoins = 0 },
		baseHealthPerExtraPlayer = 0,
		sandbox = true,
	},
}
ModeConfig.Modes = modes

ModeConfig.Order = { "Solo", "Duel", "DuelRanked", "Squad", "SquadRanked", "Coop", "TestRealm" }

-- Bay reserved for a rotating limited-time mode (empty until such a mode is configured).
ModeConfig.LimitedBayOrder = 7

ModeConfig.CategoryColors = {
	Casual = CASUAL_WHITE,
	Ranked = RANKED_GOLD,
	Coop = COOP_GREEN,
	Limited = Color3.fromRGB(176, 120, 255),
} :: { [string]: Color3 }

-- Starting values for brand-new profiles.
ModeConfig.ProfileDefaults = {
	coins = 100,
	gems = 0,
	musicVolume = 0.5,
	sfxVolume = 0.7,
}

-- Duels Hall bays in bay order (modes with bayOrder > 0).
function ModeConfig.bayModes(): { Types.ModeDef }
	local list: { Types.ModeDef } = {}
	for _, modeId in ModeConfig.Order do
		local mode = modes[modeId]
		if mode.bayOrder > 0 then
			table.insert(list, mode)
		end
	end
	table.sort(list, function(a: Types.ModeDef, b: Types.ModeDef)
		return a.bayOrder < b.bayOrder
	end)
	return list
end

return TableUtil.deepFreeze(ModeConfig)

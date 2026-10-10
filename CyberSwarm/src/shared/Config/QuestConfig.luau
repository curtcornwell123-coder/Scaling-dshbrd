--!strict
--[[
	QuestConfig
	Daily tasks. Each UTC day QuestRules picks RegularPerDay quests from the regular pool and
	TestRealmPerDay from the Test Realm pool, seeded by the day number so every server agrees.
	Test Realm quests (testRealm = true) only progress inside the sandbox and are paid out back in
	the main game; regular quests never progress in the sandbox.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local QuestConfig = {}

local quests: { [string]: Types.QuestDef } = {
	PlayThree = {
		id = "PlayThree",
		description = "Play 3 matches",
		kind = "PlayMatches",
		target = 3,
		reward = { coins = 150, xp = 100 },
		testRealm = false,
	},
	WinTwo = {
		id = "WinTwo",
		description = "Win 2 matches",
		kind = "WinMatches",
		target = 2,
		reward = { coins = 200, xp = 150 },
		testRealm = false,
	},
	ClearWaves = {
		id = "ClearWaves",
		description = "Clear 15 waves",
		kind = "CompleteWaves",
		target = 15,
		reward = { coins = 150, xp = 100 },
		testRealm = false,
	},
	DeployMany = {
		id = "DeployMany",
		description = "Deploy 60 robots",
		kind = "DeployRobots",
		target = 60,
		reward = { coins = 120, xp = 80 },
		testRealm = false,
	},
	WinOne = {
		id = "WinOne",
		description = "Win a match",
		kind = "WinMatches",
		target = 1,
		reward = { gems = 5, xp = 80 },
		testRealm = false,
	},
	TryTroops = {
		id = "TryTroops",
		description = "Try 3 different troops in the Test Realm",
		kind = "TryTroops",
		target = 3,
		reward = { coins = 100, xp = 60 },
		testRealm = true,
	},
	TestWaves = {
		id = "TestWaves",
		description = "Clear 5 waves in the Test Realm",
		kind = "TestRealmWaves",
		target = 5,
		reward = { coins = 100, xp = 60 },
		testRealm = true,
	},
}
QuestConfig.Quests = quests

QuestConfig.RegularPool = { "PlayThree", "WinTwo", "ClearWaves", "DeployMany", "WinOne" }
QuestConfig.TestRealmPool = { "TryTroops", "TestWaves" }
QuestConfig.RegularPerDay = 2
QuestConfig.TestRealmPerDay = 1
QuestConfig.Seed = 4241

return TableUtil.deepFreeze(QuestConfig)

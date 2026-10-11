--!strict
--[[
	QuestConfig
	Daily and weekly tasks.
	- Daily: each UTC day QuestRules picks DailyPerDay tasks from DailyPool plus TestRealmPerDay
	  from TestRealmPool, seeded by the day number so every server agrees.
	- Weekly: each week (Monday 00:00 UTC) WeeklyPerWeek bigger tasks from WeeklyPool.
	Test Realm tasks (testRealm = true) only progress inside the sandbox and are claimed back in the
	main game; every other task never progresses in the sandbox.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local QuestConfig = {}

local function quest(
	id: string,
	description: string,
	kind: Types.QuestKind,
	target: number,
	reward: Types.Reward,
	testRealm: boolean?
): Types.QuestDef
	return {
		id = id,
		description = description,
		kind = kind,
		target = target,
		reward = reward,
		testRealm = testRealm == true,
	}
end

local quests: { [string]: Types.QuestDef } = {}
local function add(definition: Types.QuestDef)
	quests[definition.id] = definition
end

-- Daily.
add(quest("PlayThree", "Play 3 matches", "PlayMatches", 3, { coins = 150 }))
add(quest("PlayFive", "Play 5 matches", "PlayMatches", 5, { coins = 250 }))
add(quest("WinOne", "Win a match", "WinMatches", 1, { coins = 120, gems = 3 }))
add(quest("WinTwo", "Win 2 matches", "WinMatches", 2, { coins = 220, gems = 4 }))
add(quest("ClearWaves", "Clear 15 waves", "CompleteWaves", 15, { coins = 180 }))
add(quest("ClearWavesBig", "Clear 30 waves", "CompleteWaves", 30, { coins = 300 }))
add(quest("DeployMany", "Deploy 60 robots", "DeployRobots", 60, { coins = 160 }))
add(quest("DeployLots", "Deploy 120 robots", "DeployRobots", 120, { coins = 260 }))
-- Weekly.
add(quest("WeekPlay", "Play 25 matches this week", "PlayMatches", 25, { coins = 1200, gems = 15 }))
add(quest("WeekWin", "Win 10 matches this week", "WinMatches", 10, { coins = 1500, gems = 25 }))
add(quest("WeekWaves", "Clear 150 waves this week", "CompleteWaves", 150, { coins = 1300, gems = 15 }))
add(quest("WeekDeploy", "Deploy 700 robots this week", "DeployRobots", 700, { coins = 1200, gems = 15 }))
add(quest("WeekWinBig", "Win 20 matches this week", "WinMatches", 20, { coins = 2500, gems = 40 }))
-- Test Realm (daily).
add(quest("TryTroops", "Try 3 different troops in the Test Realm", "TryTroops", 3, { coins = 100 }, true))
add(quest("TestWaves", "Clear 5 waves in the Test Realm", "TestRealmWaves", 5, { coins = 100 }, true))

QuestConfig.Quests = quests

QuestConfig.RegularPool =
	{ "PlayThree", "PlayFive", "WinOne", "WinTwo", "ClearWaves", "ClearWavesBig", "DeployMany", "DeployLots" }
QuestConfig.TestRealmPool = { "TryTroops", "TestWaves" }
QuestConfig.WeeklyPool = { "WeekPlay", "WeekWin", "WeekWaves", "WeekDeploy", "WeekWinBig" }
QuestConfig.RegularPerDay = 4
QuestConfig.TestRealmPerDay = 1
QuestConfig.WeeklyPerWeek = 3
QuestConfig.Seed = 4241

return TableUtil.deepFreeze(QuestConfig)

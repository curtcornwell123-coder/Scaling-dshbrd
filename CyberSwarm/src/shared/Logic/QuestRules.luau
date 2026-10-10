--!strict
--[[
	QuestRules
	Daily task selection and progress. The day's tasks are the same for everyone (seeded by the UTC
	day) and progress is per player. Pure; QuestService feeds it server events.
]]

local Types = require(script.Parent.Parent.Types)
local Calendar = require(script.Parent.Calendar)

export type QuestSettings = {
	regularPool: { string },
	testRealmPool: { string },
	regularPerDay: number,
	testRealmPerDay: number,
	seed: number,
}

local QuestRules = {}

function QuestRules.dailyQuests(day: number, settings: QuestSettings): { string }
	local list = Calendar.pickDaily(settings.regularPool, settings.regularPerDay, settings.seed, day)
	for _, questId in Calendar.pickDaily(settings.testRealmPool, settings.testRealmPerDay, settings.seed + 1, day) do
		table.insert(list, questId)
	end
	return list
end

-- Starts a fresh day's progress when the stored data is from an earlier day.
function QuestRules.normalize(data: Types.QuestData, day: number)
	if data.day ~= day then
		data.day = day
		data.progress = {}
		data.claimed = {}
		data.tried = {}
	end
end

-- Adds progress, capped at the target. Returns true when the value changed.
function QuestRules.addProgress(data: Types.QuestData, quest: Types.QuestDef, amount: number): boolean
	local current = data.progress[quest.id] or 0
	local nextValue = math.min(quest.target, current + math.max(0, amount))
	if nextValue == current then
		return false
	end
	data.progress[quest.id] = nextValue
	return true
end

-- Records a distinct troop tried in the Test Realm. Returns true when it was new.
function QuestRules.recordTried(data: Types.QuestData, troopId: string): boolean
	if table.find(data.tried, troopId) ~= nil then
		return false
	end
	table.insert(data.tried, troopId)
	return true
end

-- Returns an ErrorCode value ("OK" when the quest's reward may be claimed).
function QuestRules.checkClaim(data: Types.QuestData, quest: Types.QuestDef?, todays: { string }): string
	if quest == nil or table.find(todays, quest.id) == nil then
		return "QUEST_UNKNOWN"
	end
	if table.find(data.claimed, quest.id) ~= nil then
		return "ALREADY_CLAIMED"
	end
	if (data.progress[quest.id] or 0) < quest.target then
		return "QUEST_INCOMPLETE"
	end
	return "OK"
end

return QuestRules

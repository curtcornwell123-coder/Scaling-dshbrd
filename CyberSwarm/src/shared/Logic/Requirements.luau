--!strict
--[[
	Requirements
	Checks unlock requirements (troop purchases, mode access) against a player's progress and
	explains the first one that is not met. The server enforces with this; the client uses the
	same function only to show the reason (red pad ring, wall plate, shop text).
]]

local Types = require(script.Parent.Parent.Types)

export type Progress = {
	wins: number,
	highestWave: number,
	matchesPlayed: number,
	loadoutSize: number,
	owned: { string },
}

local Requirements = {}

function Requirements.progressOf(data: Types.PlayerData): Progress
	return {
		wins = data.stats.wins,
		highestWave = data.stats.highestWave,
		matchesPlayed = data.stats.wins + data.stats.losses,
		loadoutSize = #data.equippedLoadout,
		owned = data.unlockedRobots,
	}
end

local function describe(requirement: Types.UnlockRequirement, progress: Progress, purpose: string): string
	local kind = requirement.kind
	local value = requirement.value
	if kind == "Wins" then
		return `Win {value} matches {purpose} ({progress.wins}/{value})`
	elseif kind == "HighestWave" then
		return `Reach wave {value} {purpose}`
	elseif kind == "MatchesPlayed" then
		return `Play {value} matches {purpose} ({progress.matchesPlayed}/{value})`
	elseif kind == "LoadoutSize" then
		return `Equip {value} troops {purpose}`
	elseif kind == "OwnsTroop" then
		return `Own the {requirement.troopId or "required"} troop {purpose}`
	end
	return ""
end

function Requirements.isMet(requirement: Types.UnlockRequirement, progress: Progress): boolean
	local kind = requirement.kind
	if kind == "None" then
		return true
	elseif kind == "Wins" then
		return progress.wins >= requirement.value
	elseif kind == "HighestWave" then
		return progress.highestWave >= requirement.value
	elseif kind == "MatchesPlayed" then
		return progress.matchesPlayed >= requirement.value
	elseif kind == "LoadoutSize" then
		return progress.loadoutSize >= requirement.value
	elseif kind == "OwnsTroop" then
		local troopId = requirement.troopId
		return troopId ~= nil and table.find(progress.owned, troopId) ~= nil
	end
	return false
end

-- Returns (true, "") or (false, reason) for the first unmet requirement.
-- `purpose` finishes the sentence, e.g. "to play ranked" -> "Equip 5 troops to play ranked".
function Requirements.check(requirements: { Types.UnlockRequirement }, progress: Progress, purpose: string): (boolean, string)
	for _, requirement in requirements do
		if not Requirements.isMet(requirement, progress) then
			return false, describe(requirement, progress, purpose)
		end
	end
	return true, ""
end

return Requirements

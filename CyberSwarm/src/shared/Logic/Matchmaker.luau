--!strict
--[[
	Matchmaker
	Forms one match from a mode's queue. Pure, so every queue race and balancing rule is testable
	without Roblox.

	An Entry is one queue unit: a solo player or a whole party (a party never splits). Entries are
	passed in queue order (oldest first), and the oldest compatible entry anchors each attempt.

	Rules:
	- One-team modes (Solo, Co-op) take entries in order up to maxPlayers; a match forms once
	  minPlayers fit.
	- Team modes need exactly teams * teamSize players. Ranked entries must sit inside the
	  anchor's rating window, which widens with the anchor's wait (base + step per interval, up to
	  cap) and never beyond maxGap between any two entries in the match.
	- `blocked(a, b)` vetoes two entries meeting (win-trading guard). It is checked for every
	  pair in the match.
	- Teams are balanced greedily: biggest units first, each into the team with the lowest total
	  value (rating when ranked, loadout power when casual) that still has room.
]]

export type Entry = {
	key: any,
	members: { any },
	-- Per-player average: rating when ranked, loadout power when casual.
	value: number,
	joinedAt: number,
}

export type ModeShape = {
	teams: number,
	teamSize: number,
	minPlayers: number,
	maxPlayers: number,
	ranked: boolean,
}

export type Window = {
	base: number,
	step: number,
	interval: number,
	cap: number,
	maxGap: number,
}

export type Selection = {
	entries: { Entry },
	-- Player keys per team, in team order.
	teams: { { any } },
}

local Matchmaker = {}

function Matchmaker.windowFor(waited: number, window: Window): number
	local widened = window.base + window.step * math.floor(math.max(0, waited) / window.interval)
	return math.min(widened, window.cap, window.maxGap)
end

-- Largest entry that may queue for this mode (parties never split across teams).
function Matchmaker.maxEntrySize(mode: ModeShape): number
	return if mode.teams > 1 then mode.teamSize else mode.maxPlayers
end

local function partition(entries: { Entry }, teams: number, teamSize: number): { { any } }?
	local order = table.clone(entries)
	table.sort(order, function(a: Entry, b: Entry)
		if #a.members ~= #b.members then
			return #a.members > #b.members
		end
		return a.value > b.value
	end)
	local totals: { number } = {}
	local counts: { number } = {}
	local result: { { any } } = {}
	for team = 1, teams do
		totals[team] = 0
		counts[team] = 0
		result[team] = {}
	end
	for _, entry in order do
		local size = #entry.members
		local best: number? = nil
		for team = 1, teams do
			if counts[team] + size <= teamSize then
				-- Compare per-player value so a party of two is not treated as one strong player.
				if best == nil or totals[team] < totals[best] then
					best = team
				end
			end
		end
		if best == nil then
			return nil
		end
		counts[best] += size
		totals[best] += entry.value * size
		for _, member in entry.members do
			table.insert(result[best], member)
		end
	end
	return result
end

local function fitsWindow(entry: Entry, chosen: { Entry }, limit: number, maxGap: number): boolean
	for _, other in chosen do
		local gap = math.abs(entry.value - other.value)
		if gap > maxGap then
			return false
		end
	end
	return math.abs(entry.value - chosen[1].value) <= limit
end

local function notBlocked(entry: Entry, chosen: { Entry }, blocked: ((Entry, Entry) -> boolean)?): boolean
	if blocked == nil then
		return true
	end
	for _, other in chosen do
		if blocked(entry, other) then
			return false
		end
	end
	return true
end

local function selectOneTeam(entries: { Entry }, mode: ModeShape): Selection?
	local chosen: { Entry } = {}
	local players: { any } = {}
	for _, entry in entries do
		if #players + #entry.members <= mode.maxPlayers then
			table.insert(chosen, entry)
			for _, member in entry.members do
				table.insert(players, member)
			end
		end
	end
	if #players < mode.minPlayers or #players == 0 then
		return nil
	end
	return { entries = chosen, teams = { players } }
end

local function selectTeams(
	entries: { Entry },
	mode: ModeShape,
	now: number,
	window: Window?,
	blocked: ((Entry, Entry) -> boolean)?
): Selection?
	local needed = mode.teams * mode.teamSize
	for anchorIndex, anchor in entries do
		if #anchor.members > mode.teamSize then
			continue
		end
		local limit = math.huge
		local maxGap = math.huge
		if mode.ranked and window ~= nil then
			limit = Matchmaker.windowFor(now - anchor.joinedAt, window)
			maxGap = window.maxGap
		end
		local chosen: { Entry } = { anchor }
		local count = #anchor.members
		for index = anchorIndex + 1, #entries do
			if count == needed then
				break
			end
			local candidate = entries[index]
			local size = #candidate.members
			if size > mode.teamSize or count + size > needed then
				continue
			end
			if not fitsWindow(candidate, chosen, limit, maxGap) or not notBlocked(candidate, chosen, blocked) then
				continue
			end
			table.insert(chosen, candidate)
			-- Only keep the candidate if the group can still be split into whole teams.
			if partition(chosen, mode.teams, mode.teamSize) == nil then
				table.remove(chosen)
			else
				count += size
			end
		end
		if count == needed then
			local teams = partition(chosen, mode.teams, mode.teamSize)
			if teams ~= nil then
				return { entries = chosen, teams = teams }
			end
		end
	end
	return nil
end

-- Returns one match's worth of entries split into teams, or nil if none can form yet.
function Matchmaker.select(
	entries: { Entry },
	mode: ModeShape,
	now: number,
	window: Window?,
	blocked: ((Entry, Entry) -> boolean)?
): Selection?
	if mode.teams <= 1 then
		return selectOneTeam(entries, mode)
	end
	return selectTeams(entries, mode, now, window, blocked)
end

-- Every disjoint match that can form right now, oldest anchors first.
function Matchmaker.selectAll(
	entries: { Entry },
	mode: ModeShape,
	now: number,
	window: Window?,
	blocked: ((Entry, Entry) -> boolean)?
): { Selection }
	local remaining = table.clone(entries)
	local selections: { Selection } = {}
	while true do
		local selection = Matchmaker.select(remaining, mode, now, window, blocked)
		if selection == nil then
			break
		end
		table.insert(selections, selection)
		for _, used in selection.entries do
			local index = table.find(remaining, used)
			if index ~= nil then
				table.remove(remaining, index)
			end
		end
	end
	return selections
end

return Matchmaker

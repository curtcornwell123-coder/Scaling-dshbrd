--!strict
--[[
	QueueRules
	Pure membership rules for the lobby queue pads. The server observes every player a few times a
	second ("is this character alive, and which pad is it standing on?") and feeds that here; this
	module decides who is in which queue. Keeping it free of Roblox APIs makes every edge case
	unit-testable: jitter, push-offs, deaths, fast pad switching, and simultaneous joins.

	Rules:
	- A player is in at most one queue. Standing on a different pad moves them immediately.
	- Leaving the pad zone only counts after `grace` seconds off it, so physics jitter and small
	  hops do not drop anyone. Coming back within the grace keeps their place.
	- Death, a missing character, or becoming ineligible (data not loaded, already in a match)
	  removes the player at once, with no grace.
	- A full queue rejects newcomers; they join automatically once a slot frees up while they
	  still stand on the pad.
]]

export type Observation = {
	-- Pad the character is inside right now, or nil.
	padId: string?,
	-- Character exists and its humanoid is alive.
	alive: boolean,
	-- Allowed to queue at all (data loaded, not in a match).
	eligible: boolean,
}

export type Tracker = {
	capacities: { [string]: number },
	members: { [string]: { any } },
	current: { [any]: string },
	offPadSince: { [any]: number },
}

local QueueRules = {}

function QueueRules.newTracker(capacities: { [string]: number }): Tracker
	local members: { [string]: { any } } = {}
	for padId in capacities do
		members[padId] = {}
	end
	return {
		capacities = capacities,
		members = members,
		current = {},
		offPadSince = {},
	}
end

-- Removes the player from their queue immediately. Returns the queue they left, if any.
function QueueRules.remove(tracker: Tracker, key: any): string?
	tracker.offPadSince[key] = nil
	local padId = tracker.current[key]
	if padId == nil then
		return nil
	end
	tracker.current[key] = nil
	local list = tracker.members[padId]
	local index = table.find(list, key)
	if index ~= nil then
		-- table.remove keeps join order, which decides who launches first from a crowded pad.
		table.remove(list, index)
	end
	return padId
end

local function add(tracker: Tracker, key: any, padId: string): boolean
	local list = tracker.members[padId]
	local capacity = tracker.capacities[padId]
	if list == nil or capacity == nil or #list >= capacity then
		return false
	end
	table.insert(list, key)
	tracker.current[key] = padId
	return true
end

-- Applies one observation. Returns (queue left, queue joined); either may be nil.
function QueueRules.observe(
	tracker: Tracker,
	key: any,
	observation: Observation,
	now: number,
	grace: number
): (string?, string?)
	if not observation.alive or not observation.eligible then
		return QueueRules.remove(tracker, key), nil
	end

	local padId = observation.padId
	local current = tracker.current[key]
	if padId ~= nil then
		tracker.offPadSince[key] = nil
		if padId == current then
			return nil, nil
		end
		local left = QueueRules.remove(tracker, key)
		local joined = if add(tracker, key, padId) then padId else nil
		return left, joined
	end

	if current == nil then
		return nil, nil
	end
	local since = tracker.offPadSince[key]
	if since == nil then
		tracker.offPadSince[key] = now
		return nil, nil
	end
	if now - since >= grace then
		return QueueRules.remove(tracker, key), nil
	end
	return nil, nil
end

function QueueRules.queueOf(tracker: Tracker, key: any): string?
	return tracker.current[key]
end

function QueueRules.members(tracker: Tracker, padId: string): { any }
	return tracker.members[padId] or {}
end

return QueueRules

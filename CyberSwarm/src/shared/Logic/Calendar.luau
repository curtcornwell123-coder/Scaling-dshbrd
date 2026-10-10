--!strict
--[[
	Calendar
	UTC day maths and a small seeded generator. Daily rotations (troops, quests) are picked with
	the day number as the seed, so every server computes the same result with no coordination.
	Pure: callers pass the unix time in.
]]

local SECONDS_PER_DAY = 86400
-- Park-Miller "minimal standard" generator constants.
local MODULUS = 2147483647
local MULTIPLIER = 48271

local Calendar = {}

function Calendar.dayNumber(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

function Calendar.nextResetAt(unixTime: number): number
	return (Calendar.dayNumber(unixTime) + 1) * SECONDS_PER_DAY
end

-- Deterministic sequence of numbers in [0, 1) for a seed.
function Calendar.sequence(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	return function(): number
		state = (state * MULTIPLIER) % MODULUS
		return state / MODULUS
	end
end

-- Picks `count` distinct entries from `pool` for a given day, in a stable order.
function Calendar.pickDaily<T>(pool: { T }, count: number, seed: number, day: number): { T }
	local remaining = table.clone(pool)
	local nextRoll = Calendar.sequence(seed * 100003 + day)
	local picked: { T } = {}
	for _ = 1, math.min(count, #remaining) do
		local index = math.floor(nextRoll() * #remaining) + 1
		table.insert(picked, remaining[index])
		table.remove(remaining, index)
	end
	return picked
end

-- "7d 4h 14s" style text; days are dropped under a day, hours under an hour.
function Calendar.formatDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local days = total // SECONDS_PER_DAY
	local hours = (total % SECONDS_PER_DAY) // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if days > 0 then
		return `{days}d {hours}h {minutes}m`
	elseif hours > 0 then
		return `{hours}h {minutes}m {secs}s`
	end
	return `{minutes}m {secs}s`
end

return Calendar

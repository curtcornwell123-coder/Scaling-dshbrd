--!strict
--[[
	Math
	Small numeric helpers shared by gameplay logic and UI. Everything here is pure so it can be
	unit tested outside of a running game.
]]

local MathUtil = {}

function MathUtil.lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

function MathUtil.clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

function MathUtil.round(value: number): number
	return math.floor(value + 0.5)
end

-- Squared distance avoids a square root in hot targeting loops.
function MathUtil.distanceSquared(a: Vector3, b: Vector3): number
	local delta = a - b
	return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
end

-- Picks an index from a list of non-negative weights using a roll in [0, 1).
-- Returns nil when every weight is zero so callers can handle "nothing eligible" explicitly.
function MathUtil.weightedIndex(weights: { number }, roll: number): number?
	local total = 0
	for _, weight in weights do
		if weight > 0 then
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end

	local target = math.clamp(roll, 0, 1) * total
	local lastPositive: number? = nil
	for index, weight in weights do
		if weight > 0 then
			lastPositive = index
			if target < weight then
				return index
			end
			target -= weight
		end
	end
	-- Floating point drift on roll == 1 lands here; the last eligible entry is the correct answer.
	return lastPositive
end

-- Formats 12500 as "12,500" for UI readability.
function MathUtil.formatCount(value: number): string
	local whole = math.floor(math.abs(value))
	local text = tostring(whole)
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	if value < 0 then
		return "-" .. formatted
	end
	return formatted
end

return MathUtil

--!strict
--[[
	RateLimiter
	Token bucket keyed by any value (players on the server). Each remote gets its own limiter so a
	spammy client can be throttled per action without affecting anyone else. Time is passed in,
	which keeps the module pure and testable.
]]

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type RateLimiterData = {
	_capacity: number,
	_refillPerSecond: number,
	_buckets: { [any]: Bucket },
}

export type RateLimiter = typeof(setmetatable({} :: RateLimiterData, RateLimiter))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	return setmetatable({
		_capacity = capacity,
		_refillPerSecond = refillPerSecond,
		_buckets = {},
	}, RateLimiter)
end

-- Returns true and spends a token when the key is within its budget.
function RateLimiter.consume(self: RateLimiter, key: any, now: number): boolean
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { tokens = self._capacity, updatedAt = now }
		self._buckets[key] = bucket
	else
		local elapsed = math.max(0, now - bucket.updatedAt)
		bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refillPerSecond)
		bucket.updatedAt = now
	end

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.forget(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter

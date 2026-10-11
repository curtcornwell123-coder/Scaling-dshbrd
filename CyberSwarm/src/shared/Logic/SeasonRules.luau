--!strict
--[[
	SeasonRules
	Season Pass maths: tiers from XP and the rules for claiming a tier's reward. Pure.
]]

local Types = require(script.Parent.Parent.Types)

local SeasonRules = {}

function SeasonRules.tierForXp(xp: number, xpPerTier: number, tierCount: number): number
	return math.clamp(math.floor(xp / xpPerTier), 0, tierCount)
end

-- Returns an ErrorCode value ("OK" when the tier's reward may be claimed now).
function SeasonRules.check(
	season: Types.SeasonData,
	tier: number,
	track: Types.PassTrack,
	reward: Types.Reward?,
	now: number,
	endsAt: number,
	_xpPerTier: number,
	tierCount: number
): string
	if now >= endsAt then
		return "SEASON_ENDED"
	end
	if reward == nil then
		return "INVALID_REQUEST"
	end
	if tier > math.min(season.tier, tierCount) then
		return "TIER_LOCKED"
	end
	if track == "Premium" then
		if not season.premium then
			return "PREMIUM_REQUIRED"
		end
		if table.find(season.claimedPremium, tier) ~= nil then
			return "ALREADY_CLAIMED"
		end
	elseif table.find(season.claimedFree, tier) ~= nil then
		return "ALREADY_CLAIMED"
	end
	return "OK"
end

-- Starts fresh pass progress when the saved data belongs to an older season. Rewards from the old
-- season were visible but unclaimable after it ended; they do not carry over.
function SeasonRules.normalize(season: Types.SeasonData, seasonId: string): boolean
	if season.seasonId == seasonId then
		return false
	end
	season.seasonId = seasonId
	season.xp = 0
	season.premium = false
	table.clear(season.claimedFree)
	table.clear(season.claimedPremium)
	season.tier = 0
	season.tierProgress = 0
	return true
end

-- Adds progress to the current tier's quest when `kind` matches it, rolling over into the next
-- tiers. Returns the number of tiers gained.
function SeasonRules.addTierProgress(
	season: Types.SeasonData,
	kind: Types.QuestKind,
	amount: number,
	tiers: { Types.SeasonTier },
	tierCount: number
): number
	local gained = 0
	local remaining = math.max(0, math.floor(amount))
	while remaining > 0 and season.tier < tierCount do
		local nextTier = tiers[season.tier + 1]
		if nextTier == nil or nextTier.quest.kind ~= kind then
			break
		end
		local needed = nextTier.quest.target - season.tierProgress
		if remaining >= needed then
			remaining -= needed
			season.tier += 1
			season.tierProgress = 0
			gained += 1
		else
			season.tierProgress += remaining
			remaining = 0
		end
	end
	return gained
end

-- XP is only added while the season is running.
function SeasonRules.addXp(
	season: Types.SeasonData,
	amount: number,
	now: number,
	startsAt: number,
	endsAt: number
): number
	if amount <= 0 or now < startsAt or now >= endsAt then
		return 0
	end
	local gained = math.floor(amount)
	season.xp += gained
	return gained
end

return SeasonRules

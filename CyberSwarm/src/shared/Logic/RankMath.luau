--!strict
--[[
	RankMath
	Elo-style rating maths and tier lookup. Pure: RankService decides WHEN a rating changes (only
	from a verified match result, once per match id); this module only decides BY HOW MUCH.

	Team modes use each player's own rating against the opposing team's average, so a strong
	player carried by a weak team gains less than the rest of that team.
]]

local Types = require(script.Parent.Parent.Types)

export type Settings = {
	startRating: number,
	minRating: number,
	eloScale: number,
	kFactor: number,
	placementMatches: number,
	placementKFactor: number,
}

export type TierInfo = {
	id: string,
	displayName: string,
	floor: number,
	divisions: number,
	color: Color3,
	seasonReward: Types.Reward,
}

export type TierResult = {
	tier: TierInfo,
	tierIndex: number,
	-- 1 is the highest division in the tier; tiers with one division always report 1.
	division: number,
	label: string,
}

local ROMAN = { "I", "II", "III", "IV", "V" }

local RankMath = {}

function RankMath.newRating(settings: Settings): Types.RatingData
	return { rating = settings.startRating, played = 0, wins = 0, losses = 0, peak = settings.startRating }
end

function RankMath.expected(rating: number, opponentRating: number, scale: number): number
	return 1 / (1 + 10 ^ ((opponentRating - rating) / scale))
end

function RankMath.kFor(played: number, settings: Settings): number
	return if played < settings.placementMatches then settings.placementKFactor else settings.kFactor
end

-- Whole-number rating change for one result (score 1 = win, 0 = loss).
function RankMath.delta(rating: number, opponentRating: number, score: number, played: number, settings: Settings): number
	local k = RankMath.kFor(played, settings)
	local change = k * (score - RankMath.expected(rating, opponentRating, settings.eloScale))
	-- Round half away from zero so a win never rounds to a loss and vice versa.
	if change >= 0 then
		return math.floor(change + 0.5)
	end
	return -math.floor(-change + 0.5)
end

function RankMath.average(ratings: { number }): number
	if #ratings == 0 then
		return 0
	end
	local total = 0
	for _, value in ratings do
		total += value
	end
	return total / #ratings
end

-- Applies a change in place and returns the applied amount (after the rating floor).
function RankMath.apply(data: Types.RatingData, change: number, won: boolean?, settings: Settings): number
	local before = data.rating
	data.rating = math.max(settings.minRating, before + change)
	data.peak = math.max(data.peak, data.rating)
	if won ~= nil then
		data.played += 1
		if won then
			data.wins += 1
		else
			data.losses += 1
		end
	end
	return data.rating - before
end

-- Moves a rating `factor` of the way back toward the start rating (end of a ranked season).
function RankMath.softReset(rating: number, factor: number, settings: Settings): number
	return math.floor(settings.startRating + (rating - settings.startRating) * (1 - factor) + 0.5)
end

function RankMath.tierFor(rating: number, tiers: { TierInfo }): TierResult
	local index = 1
	for candidate, tier in tiers do
		if rating >= tier.floor then
			index = candidate
		end
	end
	local tier = tiers[index]
	local nextTier = tiers[index + 1]
	local division = 1
	if nextTier ~= nil and tier.divisions > 1 then
		local band = (nextTier.floor - tier.floor) / tier.divisions
		local step = math.clamp(math.floor((rating - tier.floor) / band), 0, tier.divisions - 1)
		division = tier.divisions - step
	end
	local label = if tier.divisions > 1 then `{tier.displayName} {ROMAN[division] or tostring(division)}` else tier.displayName
	return { tier = tier, tierIndex = index, division = division, label = label }
end

return RankMath

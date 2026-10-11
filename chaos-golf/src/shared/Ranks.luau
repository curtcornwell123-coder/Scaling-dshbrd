--!strict
-- Ranked 1v1: hidden Elo-style MMR shown as tiers with three divisions
-- (Bronze III -> Bronze I -> Silver III ... -> Chaos Legend).

local Config = require(script.Parent:WaitForChild("Config"))

local Ranks = {}

export type Tier = { Name: string, Min: number, Color: Color3, Reward: string? }

Ranks.Tiers = {
	{ Name = "Bronze", Min = 0, Color = Color3.fromHex("#C9814B") },
	{ Name = "Silver", Min = 900, Color = Color3.fromHex("#C4CCD8") },
	{ Name = "Gold", Min = 1100, Color = Color3.fromHex("#FFC83D"), Reward = "rank_gold" },
	{ Name = "Platinum", Min = 1300, Color = Color3.fromHex("#4FE3C1") },
	{ Name = "Diamond", Min = 1500, Color = Color3.fromHex("#7FD8FF"), Reward = "rank_diamond" },
	{ Name = "Onyx", Min = 1700, Color = Color3.fromHex("#7A6CFF"), Reward = "rank_onyx" },
	{ Name = "Chaos Legend", Min = 1900, Color = Color3.fromHex("#FF2D55"), Reward = "rank_legend" },
} :: { Tier }

local NUMERALS = { "III", "II", "I" }

export type RankInfo = { Tier: Tier, TierIndex: number, Division: string, Label: string }

function Ranks.fromMMR(mmr: number): RankInfo
	local index = 1
	for i, tier in Ranks.Tiers do
		if mmr >= tier.Min then
			index = i
		end
	end
	local tier = Ranks.Tiers[index]
	local nextTier = Ranks.Tiers[index + 1]
	if not nextTier then
		return { Tier = tier, TierIndex = index, Division = "", Label = string.upper(tier.Name) }
	end
	local span = nextTier.Min - tier.Min
	local floorMin = if index == 1 then 600 else tier.Min -- Bronze divisions start at 600 MMR
	span = nextTier.Min - floorMin
	local progress = math.clamp((mmr - floorMin) / span, 0, 0.999)
	local division = NUMERALS[math.floor(progress * 3) + 1]
	return {
		Tier = tier,
		TierIndex = index,
		Division = division,
		Label = string.upper(tier.Name) .. " " .. division,
	}
end

-- score: 1 win, 0.5 draw, 0 loss. Returns the MMR change for player A.
function Ranks.delta(mmrA: number, mmrB: number, score: number, placement: boolean): number
	local expected = 1 / (1 + 10 ^ ((mmrB - mmrA) / 400))
	local k = if placement then Config.Ranked.PlacementK else Config.Ranked.K
	return math.floor(k * (score - expected) + 0.5)
end

return Ranks

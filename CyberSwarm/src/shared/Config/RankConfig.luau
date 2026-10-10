--!strict
--[[
	RankConfig
	Ranked rules, all data. Ratings are Elo-style (one number per player per ranked format).
	Tiers are original military ranks; each tier has a rating floor and divisions that split the
	band up to the next tier. Every number the ranked system uses lives here.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type TierDef = {
	id: string,
	displayName: string,
	floor: number,
	divisions: number,
	color: Color3,
	-- Paid once per ranked season based on the tier you finish in.
	seasonReward: Types.Reward,
}

local RankConfig = {}

-- Ranked mode -> rating key. 1v1 and 3v3 keep separate ratings.
RankConfig.RatingKeys = {
	DuelRanked = "Duel",
	SquadRanked = "Squad",
} :: { [string]: string }

RankConfig.RatingKeyNames = {
	Duel = "1v1",
	Squad = "3v3",
} :: { [string]: string }

RankConfig.StartRating = 1000
RankConfig.MinRating = 0
-- Elo scale: a 400-point gap means the favourite is expected to win about 10 to 1.
RankConfig.EloScale = 400
RankConfig.KFactor = 32
-- Placement matches move rating faster so new players settle quickly.
RankConfig.PlacementMatches = 10
RankConfig.PlacementKFactor = 64

local tiers: { TierDef } = {
	{ id = "Recruit", displayName = "Recruit", floor = 0, divisions = 3, color = Color3.fromRGB(150, 146, 136), seasonReward = { coins = 200 } },
	{ id = "Private", displayName = "Private", floor = 900, divisions = 3, color = Color3.fromRGB(176, 140, 96), seasonReward = { coins = 400 } },
	{ id = "Corporal", displayName = "Corporal", floor = 1050, divisions = 3, color = Color3.fromRGB(150, 168, 176), seasonReward = { coins = 600, gems = 5 } },
	{ id = "Sergeant", displayName = "Sergeant", floor = 1200, divisions = 3, color = Color3.fromRGB(96, 170, 120), seasonReward = { coins = 800, gems = 10 } },
	{ id = "Lieutenant", displayName = "Lieutenant", floor = 1350, divisions = 3, color = Color3.fromRGB(64, 160, 226), seasonReward = { coins = 1000, gems = 20 } },
	{ id = "Captain", displayName = "Captain", floor = 1500, divisions = 3, color = Color3.fromRGB(150, 96, 226), seasonReward = { coins = 1250, gems = 35 } },
	{ id = "Major", displayName = "Major", floor = 1650, divisions = 3, color = Color3.fromRGB(226, 96, 96), seasonReward = { coins = 1500, gems = 50 } },
	{ id = "Commander", displayName = "Commander", floor = 1800, divisions = 1, color = Color3.fromRGB(242, 193, 0), seasonReward = { coins = 2000, gems = 80 } },
}
RankConfig.Tiers = tiers

-- Matchmaking: start tight and widen while waiting, but never past MaxGap.
RankConfig.Window = {
	base = 100,
	step = 50,
	interval = 10,
	cap = 400,
	maxGap = 500,
}

-- Leaving a ranked countdown or match early.
RankConfig.Dodge = {
	ratingPenalty = 15,
	cooldownSeconds = 300,
}

-- Win-trading guard: at most this many ranked matches against the same player per window.
RankConfig.WinTrade = {
	windowSeconds = 1800,
	maxRepeats = 3,
	-- Opponent history kept per player.
	historySize = 20,
}

-- End of ranked season: rating moves this fraction of the way back to StartRating.
RankConfig.SoftResetFactor = 0.5

-- Recent match ids remembered per player so a result is never applied twice.
RankConfig.AppliedMatchHistory = 50

return TableUtil.deepFreeze(RankConfig)

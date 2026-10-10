--!strict
--[[
	SeasonConfig
	Season Pass and ranked season timing. All times are unix seconds (UTC).

	Pass: XP comes only from server-verified events (XpSources). Tier n needs n * XpPerTier XP.
	Claiming closes at EndsAt; unclaimed rewards stay visible. A new SeasonId resets pass progress.
	Ranked: its own id and end date; at the end ratings soft-reset and the finishing tier's reward
	becomes claimable through the same claim flow.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local SeasonConfig = {}

SeasonConfig.SeasonId = "S1"
SeasonConfig.DisplayName = "SEASON 1"
SeasonConfig.StartsAt = 1790812800 -- 2026-10-01 00:00 UTC
SeasonConfig.EndsAt = 1798761600 -- 2027-01-01 00:00 UTC
SeasonConfig.TierCount = 30
SeasonConfig.XpPerTier = 300

SeasonConfig.XpSources = {
	win = 150,
	loss = 50,
	perWave = 10,
	quest = 100,
}

-- Free track: coins every tier, gems every fifth. Premium: more of both plus troops at milestones.
local tiers: { Types.SeasonTier } = {}
for tier = 1, SeasonConfig.TierCount do
	local free: Types.Reward = if tier % 5 == 0 then { gems = 5 } else { coins = 50 + tier * 5 }
	local premium: Types.Reward = if tier == 10
		then { troopId = "Relay" }
		elseif tier == 30 then { troopId = "Phantom" }
		elseif tier % 5 == 0 then { gems = 15 }
		else { coins = 100 + tier * 10 }
	tiers[tier] = { tier = tier, free = free, premium = premium }
end
SeasonConfig.Tiers = tiers

SeasonConfig.Ranked = {
	seasonId = "R1",
	displayName = "RANKED SEASON 1",
	endsAt = 1798761600, -- 2027-01-01 00:00 UTC
}

return TableUtil.deepFreeze(SeasonConfig)

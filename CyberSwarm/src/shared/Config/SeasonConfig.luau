--!strict
--[[
	SeasonConfig
	Season Pass and ranked season timing. All times are unix seconds (UTC).

	Pass: every tier has its own quest (play, win, clear waves, deploy robots) and the targets grow
	tier by tier. Tiers are earned in order from server-verified match events only; the 2x XP game
	pass doubles that progress. Claiming closes at EndsAt; unclaimed rewards stay visible. A new
	SeasonId resets pass progress.
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

-- Tier quests rotate through four kinds; each lap of four raises every target.
local function tierQuest(tier: number): Types.TierQuest
	local lap = (tier - 1) // 4
	local slot = (tier - 1) % 4
	if slot == 0 then
		local target = 2 + lap
		return { kind = "PlayMatches", target = target, description = `Play {target} matches` }
	elseif slot == 1 then
		local target = 10 + lap * 6
		return { kind = "CompleteWaves", target = target, description = `Clear {target} waves` }
	elseif slot == 2 then
		local target = 40 + lap * 25
		return { kind = "DeployRobots", target = target, description = `Deploy {target} robots` }
	end
	local target = 1 + lap // 2
	return {
		kind = "WinMatches",
		target = target,
		description = if target == 1 then "Win a match" else `Win {target} matches`,
	}
end
SeasonConfig.tierQuest = tierQuest

-- Free track: coins every tier, gems every fifth. Premium: more of both plus troops at milestones.
local tiers: { Types.SeasonTier } = {}
for tier = 1, SeasonConfig.TierCount do
	local free: Types.Reward = if tier % 5 == 0 then { gems = 5 } else { coins = 50 + tier * 5 }
	local premium: Types.Reward = if tier == 10
		then { troopId = "Relay" }
		elseif tier == 30 then { troopId = "Phantom" }
		elseif tier % 5 == 0 then { gems = 15 }
		else { coins = 100 + tier * 10 }
	tiers[tier] = { tier = tier, quest = tierQuest(tier), free = free, premium = premium }
end
SeasonConfig.Tiers = tiers

SeasonConfig.Ranked = {
	seasonId = "R1",
	displayName = "RANKED SEASON 1",
	endsAt = 1798761600, -- 2027-01-01 00:00 UTC
}

return TableUtil.deepFreeze(SeasonConfig)

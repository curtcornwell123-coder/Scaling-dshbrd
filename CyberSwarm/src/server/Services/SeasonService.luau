--!strict
--[[
	SeasonService
	The Season Pass. XP comes only from server-verified events: match results (win, loss, waves
	cleared) and completed Daily Tasks. The Test Realm never grants XP, and neither do modes with
	rewards disabled.

	Claims send a tier number and a track. The server validates the tier as an integer in range,
	the track, the season window, the player's tier, premium ownership, and that the reward was not
	already claimed, then grants and marks it claimed in one DataService.update.

	Track "Ranked" claims the end-of-ranked-season reward stored by RankService (tier is ignored).
	When SeasonConfig.SeasonId changes, profiles start fresh pass progress on load.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local Actions = require(script.Parent.Parent.Actions)
local Rewards = require(script.Parent.Parent.Rewards)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local ErrorCode = Constants.ErrorCode
local XP = SeasonConfig.XpSources

local SeasonService = {}

local function addXp(player: Player, amount: number)
	DataService.update(player, function(data)
		SeasonRules.normalize(data.season, SeasonConfig.SeasonId)
		SeasonRules.addXp(data.season, amount, os.time(), SeasonConfig.StartsAt, SeasonConfig.EndsAt)
	end)
end

local function claimRanked(player: Player): string
	local code = ErrorCode.DataNotLoaded
	local granted: Types.Reward? = nil
	DataService.update(player, function(data)
		local pending = data.rank.pendingReward
		if pending == nil then
			code = ErrorCode.AlreadyClaimed
			return
		end
		data.rank.pendingReward = nil
		granted = Rewards.apply(data, pending.reward)
		code = ErrorCode.Ok
	end)
	local final = granted
	if final ~= nil then
		Notifier.banner({ player }, "Success", "RANKED SEASON REWARD", Rewards.describe(final))
	end
	return code
end

local function claimTier(player: Player, tier: number, track: Types.PassTrack): string
	local tierDef = SeasonConfig.Tiers[tier]
	local reward: Types.Reward? = nil
	if tierDef ~= nil then
		reward = if track == "Premium" then tierDef.premium else tierDef.free
	end
	local code = ErrorCode.DataNotLoaded
	local granted: Types.Reward? = nil
	DataService.update(player, function(data)
		SeasonRules.normalize(data.season, SeasonConfig.SeasonId)
		code = SeasonRules.check(
			data.season,
			tier,
			track,
			reward,
			os.time(),
			SeasonConfig.EndsAt,
			SeasonConfig.XpPerTier,
			SeasonConfig.TierCount
		)
		if code ~= ErrorCode.Ok or reward == nil then
			return
		end
		table.insert(if track == "Premium" then data.season.claimedPremium else data.season.claimedFree, tier)
		-- Pass rewards never grant pass XP (no loops).
		local clean = table.clone(reward)
		clean.xp = nil
		granted = Rewards.apply(data, clean)
	end)
	local final = granted
	if final ~= nil then
		Notifier.toast({ player }, "Success", `Tier {tier}: {Rewards.describe(final)}`)
	end
	return code
end

function SeasonService.start()
	MatchService.matchEnded:connect(function(match: ServerTypes.Match, outcome: ServerTypes.Outcome)
		if match.sandbox ~= nil or not match.mode.rewardsEnabled then
			return
		end
		for player, matchPlayer in match.players do
			if matchPlayer.connected and not DataService.isSandboxed(player) then
				local won = outcome.winner ~= nil and matchPlayer.arena == outcome.winner
				addXp(player, (if won then XP.win else XP.loss) + XP.perWave * match.wavesCompleted)
			end
		end
	end)

	Remotes.RequestClaimPassReward:connect(function(player: Player, rawTier: unknown, rawTrack: unknown)
		local track: Types.PassTrack? = if rawTrack == "Free"
			then "Free"
			elseif rawTrack == "Premium" then "Premium"
			elseif rawTrack == "Ranked" then "Ranked"
			else nil
		local tier = Actions.readInteger(rawTier, 0, SeasonConfig.TierCount)
		local id = if tier ~= nil and track ~= nil then `{track}:{tier}` else nil
		Actions.run(player, "ClaimPass", id, function(): string
			if DataService.isSandboxed(player) then
				return ErrorCode.Sandbox
			end
			if track == nil or tier == nil then
				return ErrorCode.InvalidRequest
			end
			local chosenTrack = track :: Types.PassTrack
			local chosenTier = tier :: number
			if chosenTrack == "Ranked" then
				return claimRanked(player)
			end
			if chosenTier < 1 then
				return ErrorCode.InvalidRequest
			end
			return claimTier(player, chosenTier, chosenTrack)
		end)
	end)

	DataService.profileLoaded:connect(function(player: Player)
		local data = DataService.getData(player)
		if data ~= nil and data.season.seasonId ~= SeasonConfig.SeasonId then
			DataService.update(player, function(profile)
				SeasonRules.normalize(profile.season, SeasonConfig.SeasonId)
			end)
		end
	end)
end

return SeasonService

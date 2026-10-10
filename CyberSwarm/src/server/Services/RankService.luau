--!strict
--[[
	RankService
	Ranked ratings, one per player per ranked format (1v1 and 3v3 separately).

	Ratings change ONLY here, ONLY from MatchService results, and at most once per match:
	- matchStarted (ranked): every player's rating and team are snapshotted under match.key.
	- matchEnded: each player still in the match is rated against the opposing teams' average
	  snapshot rating (score 1 win, 0 loss, 0.5 no winner). data.rank.appliedMatches makes the
	  update idempotent, so a repeated signal can never count a match twice.
	- playerAbandoned (disconnect or leaving mid-match): counts as a loss plus the dodge
	  cooldown. A server crash or shutdown never reaches this code, so it costs nothing.
	- A match that fails to start or is cancelled has no result and changes no rating.

	Protections: placement matches use a higher K; leaving a ranked countdown costs
	RankConfig.Dodge.ratingPenalty and a queue cooldown; repeat opponents inside the win-trading
	window are blocked by matchmaking and, if they ever meet anyway, rated at zero change.

	Ranked seasons: when SeasonConfig.Ranked.seasonId changes, the first load soft-resets each
	rating and stores the finishing tier's reward as rank.pendingReward, claimed through the Season
	Pass claim flow (track "Ranked").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RankConfig = require(ReplicatedStorage.Shared.Config.RankConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local RankMath = require(ReplicatedStorage.Shared.Logic.RankMath)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local LeaderboardService = require(script.Parent.LeaderboardService)

type SnapshotEntry = {
	rating: number,
	played: number,
	team: number,
}

type Snapshot = {
	ratingKey: string,
	players: { [number]: SnapshotEntry },
}

local RankService = {}

local settings: RankMath.Settings = {
	startRating = RankConfig.StartRating,
	minRating = RankConfig.MinRating,
	eloScale = RankConfig.EloScale,
	kFactor = RankConfig.KFactor,
	placementMatches = RankConfig.PlacementMatches,
	placementKFactor = RankConfig.PlacementKFactor,
}
RankService.settings = settings

local snapshots: { [string]: Snapshot } = {}

function RankService.ratingKeyFor(modeId: string): string?
	return RankConfig.RatingKeys[modeId]
end

function RankService.boardId(ratingKey: string): string
	return "Rank_" .. ratingKey
end

local function ratingData(data: Types.PlayerData, ratingKey: string): Types.RatingData
	local existing = data.rank.ratings[ratingKey]
	if existing ~= nil then
		return existing
	end
	local fresh = RankMath.newRating(settings)
	data.rank.ratings[ratingKey] = fresh
	return fresh
end

function RankService.ratingFor(player: Player, ratingKey: string): number
	local data = DataService.getData(player)
	if data == nil then
		return settings.startRating
	end
	local existing = data.rank.ratings[ratingKey]
	return if existing ~= nil then existing.rating else settings.startRating
end

function RankService.seasonOpen(): boolean
	return os.time() < SeasonConfig.Ranked.endsAt
end

function RankService.cooldownRemaining(player: Player): number
	local data = DataService.getData(player)
	if data == nil then
		return 0
	end
	return math.max(0, data.rank.cooldownUntil - os.time())
end

-- Why this player may not queue a ranked mode right now, or nil. Unlock requirements are
-- checked separately (Requirements); this covers season state and dodge cooldowns.
function RankService.lockReason(player: Player): string?
	if not RankService.seasonOpen() then
		return "Ranked season has ended"
	end
	if DataService.isSandboxed(player) then
		return "Not available in the Test Realm"
	end
	local remaining = RankService.cooldownRemaining(player)
	if remaining > 0 then
		return `Ranked cooldown {Calendar.formatDuration(remaining)}`
	end
	return nil
end

local function recentMeetings(data: Types.PlayerData, opponentId: number, now: number): number
	local count = 0
	for _, entry in data.rank.recentOpponents do
		if entry.userId == opponentId and now - entry.at < RankConfig.WinTrade.windowSeconds then
			count += 1
		end
	end
	return count
end

-- Win-trading guard used by matchmaking: true when these two have met too often recently.
function RankService.isRepeatPair(a: Player, b: Player): boolean
	local data = DataService.getData(a)
	if data == nil then
		return false
	end
	return recentMeetings(data, b.UserId, os.time()) >= RankConfig.WinTrade.maxRepeats
end

local function submitBoard(player: Player, ratingKey: string, rating: number)
	LeaderboardService.submit(RankService.boardId(ratingKey), player.UserId, rating)
end

-- Leaving a ranked countdown: rating penalty plus a queue cooldown.
function RankService.penalizeDodge(player: Player, modeId: string)
	local ratingKey = RankService.ratingKeyFor(modeId)
	if ratingKey == nil then
		return
	end
	local key = ratingKey :: string
	local after = 0
	local applied = DataService.update(player, function(data)
		local rating = ratingData(data, key)
		RankMath.apply(rating, -RankConfig.Dodge.ratingPenalty, nil, settings)
		after = rating.rating
		data.rank.cooldownUntil = os.time() + RankConfig.Dodge.cooldownSeconds
	end)
	if applied and player.Parent ~= nil then
		submitBoard(player, key, after)
		Notifier.banner(
			{ player },
			"Error",
			"RANKED DODGE",
			`Left a ranked countdown: -{RankConfig.Dodge.ratingPenalty} rating and a {Calendar.formatDuration(
				RankConfig.Dodge.cooldownSeconds
			)} cooldown.`
		)
	end
end

local function opponentsOf(snapshot: Snapshot, team: number): ({ number }, number)
	local ids: { number } = {}
	local ratings: { number } = {}
	for userId, entry in snapshot.players do
		if entry.team ~= team then
			table.insert(ids, userId)
			table.insert(ratings, entry.rating)
		end
	end
	return ids, RankMath.average(ratings)
end

-- score: 1 win, 0 loss, 0.5 no winner. Returns nothing; the player is told through RankResult.
local function applyResult(player: Player, match: ServerTypes.Match, score: number, abandoned: boolean)
	local snapshot = snapshots[match.key]
	if snapshot == nil then
		return
	end
	local entry = snapshot.players[player.UserId]
	if entry == nil then
		return
	end
	local opponentIds, opponentRating = opponentsOf(snapshot, entry.team)
	local now = os.time()
	local result: Types.RankResult? = nil

	DataService.update(player, function(data)
		local rank = data.rank
		if table.find(rank.appliedMatches, match.key) ~= nil then
			return
		end
		table.insert(rank.appliedMatches, match.key)
		while #rank.appliedMatches > RankConfig.AppliedMatchHistory do
			table.remove(rank.appliedMatches, 1)
		end

		local rating = ratingData(data, snapshot.ratingKey)
		local before = rating.rating
		local repeated = false
		for _, opponentId in opponentIds do
			if recentMeetings(data, opponentId, now) >= RankConfig.WinTrade.maxRepeats then
				repeated = true
			end
		end

		local won: boolean? = if score >= 1 then true elseif score <= 0 then false else nil
		local note: string? = nil
		if repeated then
			note = "Repeat opponent: no rating change"
			RankMath.apply(rating, 0, won, settings)
		else
			local change = RankMath.delta(entry.rating, opponentRating, score, entry.played, settings)
			RankMath.apply(rating, change, won, settings)
		end
		if won == nil then
			rating.played += 1
		end
		if abandoned then
			note = "Left the match: counted as a loss"
			rank.cooldownUntil = now + RankConfig.Dodge.cooldownSeconds
		end

		for _, opponentId in opponentIds do
			table.insert(rank.recentOpponents, { userId = opponentId, at = now })
		end
		while #rank.recentOpponents > RankConfig.WinTrade.historySize do
			table.remove(rank.recentOpponents, 1)
		end

		result = {
			ratingKey = snapshot.ratingKey,
			before = before,
			after = rating.rating,
			won = won == true,
			note = note,
		}
	end)

	local final = result
	if final ~= nil then
		submitBoard(player, final.ratingKey, final.after)
		if player.Parent ~= nil then
			Remotes.RankResult:fireClient(player, final)
			RankService.refreshNameplate(player)
		end
	end
end

local function onMatchStarted(match: ServerTypes.Match)
	if not match.mode.ranked or match.sandbox ~= nil then
		return
	end
	local ratingKey = RankService.ratingKeyFor(match.mode.id)
	if ratingKey == nil then
		return
	end
	local snapshot: Snapshot = { ratingKey = ratingKey, players = {} }
	for player, matchPlayer in match.players do
		local data = DataService.getData(player)
		local existing = if data ~= nil then data.rank.ratings[ratingKey] else nil
		snapshot.players[player.UserId] = {
			rating = if existing ~= nil then existing.rating else settings.startRating,
			played = if existing ~= nil then existing.played else 0,
			team = matchPlayer.team,
		}
	end
	snapshots[match.key] = snapshot
end

local function onMatchEnded(match: ServerTypes.Match, outcome: ServerTypes.Outcome)
	if snapshots[match.key] == nil then
		return
	end
	for player, matchPlayer in match.players do
		if matchPlayer.connected then
			local score = if outcome.winner == nil then 0.5 elseif matchPlayer.arena == outcome.winner then 1 else 0
			applyResult(player, match, score, false)
		end
	end
end

local function onAbandon(match: ServerTypes.Match, matchPlayer: ServerTypes.MatchPlayer)
	if snapshots[match.key] == nil then
		return
	end
	applyResult(matchPlayer.player, match, 0, true)
end

-- New ranked season: store the finishing tier's reward, then soft-reset every rating.
local function normalizeSeason(player: Player)
	local data = DataService.getData(player)
	local current = SeasonConfig.Ranked.seasonId
	if data == nil or data.rank.seasonId == current then
		return
	end
	DataService.update(player, function(profile)
		local rank = profile.rank
		local best: number? = nil
		for _, rating in rank.ratings do
			if rating.played > 0 and (best == nil or rating.rating > best) then
				best = rating.rating
			end
		end
		if best ~= nil and rank.pendingReward == nil then
			local tier = RankMath.tierFor(best, RankConfig.Tiers).tier
			rank.pendingReward = { seasonId = rank.seasonId, tier = tier.displayName, reward = tier.seasonReward }
		end
		for _, rating in rank.ratings do
			rating.rating = RankMath.softReset(rating.rating, RankConfig.SoftResetFactor, settings)
		end
		rank.seasonId = current
	end)
end

-- Highest tier across this player's ranked formats, for the overhead badge.
function RankService.badgeFor(player: Player): (string, Color3)
	local data = DataService.getData(player)
	if data == nil then
		return "", Color3.new(1, 1, 1)
	end
	local best: number? = nil
	for _, rating in data.rank.ratings do
		if rating.played > 0 and (best == nil or rating.rating > best) then
			best = rating.rating
		end
	end
	if best == nil then
		return "UNRANKED", Color3.fromRGB(150, 150, 150)
	end
	local tier = RankMath.tierFor(best, RankConfig.Tiers)
	return string.upper(tier.label), tier.tier.color
end

function RankService.refreshNameplate(player: Player)
	local character = player.Character
	local head = if character ~= nil then character:FindFirstChild("Head") else nil
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local gui = head:FindFirstChild(Constants.Nameplate.NAME)
	if gui == nil then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = Constants.Nameplate.NAME
		billboard.Size = UDim2.fromOffset(200, 44)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		billboard.MaxDistance = Constants.Nameplate.MAX_DISTANCE
		billboard.AlwaysOnTop = false
		billboard.LightInfluence = 0
		billboard.Adornee = head

		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.BackgroundTransparency = 1
		name.Size = UDim2.fromScale(1, 0.55)
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.5
		name.Text = player.DisplayName
		name.Parent = billboard

		local badge = Instance.new("TextLabel")
		badge.Name = "Rank"
		badge.BackgroundTransparency = 1
		badge.Position = UDim2.fromScale(0, 0.55)
		badge.Size = UDim2.fromScale(1, 0.45)
		badge.Font = Enum.Font.GothamBold
		badge.TextScaled = true
		badge.TextStrokeTransparency = 0.6
		badge.Parent = billboard

		billboard.Parent = head
		gui = billboard
	end
	local label = (gui :: Instance):FindFirstChild("Rank")
	if label ~= nil and label:IsA("TextLabel") then
		local text, color = RankService.badgeFor(player)
		label.Text = text
		label.TextColor3 = color
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		-- Hide the default name so the custom plate is the only one.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		RankService.refreshNameplate(player)
	end)
end

function RankService.init()
	for _, ratingKey in RankConfig.RatingKeys do
		LeaderboardService.register(
			RankService.boardId(ratingKey),
			`{Constants.Leaderboard.RANKED_STORE_PREFIX}{SeasonConfig.Ranked.seasonId}_{ratingKey}`
		)
	end
end

function RankService.start()
	MatchService.matchStarted:connect(onMatchStarted)
	MatchService.matchEnded:connect(onMatchEnded)
	MatchService.playerAbandoned:connect(onAbandon)
	MatchService.matchClosed:connect(function(match: ServerTypes.Match)
		snapshots[match.key] = nil
	end)
	DataService.profileLoaded:connect(function(player: Player)
		normalizeSeason(player)
		local data = DataService.getData(player)
		if data ~= nil then
			for ratingKey, rating in data.rank.ratings do
				if rating.played > 0 then
					submitBoard(player, ratingKey, rating.rating)
				end
			end
		end
		RankService.refreshNameplate(player)
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return RankService

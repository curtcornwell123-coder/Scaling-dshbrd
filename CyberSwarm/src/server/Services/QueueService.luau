--!strict
--[[
	QueueService
	Matchmaking for the Duels Hall bays. Queueing is decided ONLY here, on the server: there is no
	remote a client can fire to join or leave a queue or to start a match. Every Constants.Queue.TICK
	the server looks at each player's character and asks "alive, and inside which bay pad?", then
	QueueRules turns those observations into queue membership (one queue per player, a 0.3 s grace
	for jitter, instant removal on death, reset, or disconnect).

	Each tick, per mode:
	1. Build queue entries: a solo player, or a party led by the player on the pad (the leader
	   carries every eligible member). Parties larger than the mode allows, parties with a member
	   who fails the mode's requirements, and players a mode is locked for never form an entry;
	   the player gets a QueueNotice with the reason for the bay plate.
	2. Matchmaker.selectAll forms matches (rating windows for ranked, team balancing, win-trade
	   guard). If any can form, a countdown starts; if they stop being possible, it cancels.
	3. When the countdown ends, matches are re-selected from the state at that exact moment and
	   started. Anyone who left in the meantime is simply not in them (refill, never a crash).

	Leaving a ranked queue during its countdown is a dodge (RankService.penalizeDodge).
	If MatchService cannot start a match, its players go back to the Duels Hall with a message and
	no penalty; ratings are only touched by real results.

	Pads are BaseParts tagged Constants.Tags.QueuePad with a ModeId and QueueRadius attribute.
	Rings, bay screens, and lock colours are drawn by each client from the QueueBoard broadcast
	and the player's own profile (WorldScreensController).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local RankConfig = require(ReplicatedStorage.Shared.Config.RankConfig)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local QueueRules = require(ReplicatedStorage.Shared.Logic.QueueRules)
local Matchmaker = require(ReplicatedStorage.Shared.Logic.Matchmaker)
local Requirements = require(ReplicatedStorage.Shared.Logic.Requirements)
local DataService = require(script.Parent.DataService)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local PartyService = require(script.Parent.PartyService)
local RankService = require(script.Parent.RankService)
local Notifier = require(script.Parent.Parent.Notifier)

local ErrorCode = Constants.ErrorCode
local QUEUE = Constants.Queue
-- Weight of the newest measured wait in the running estimate shown on bay screens.
local WAIT_SMOOTHING = 0.3

type PadQueue = {
	mode: Types.ModeDef,
	pad: BasePart,
	radius: number,
	-- Server time the countdown ends, or nil.
	countdownEndsAt: number?,
	-- Players inside the matches the running countdown would start (dodge tracking).
	countdownPlayers: { [Player]: boolean },
	estimatedWait: number,
	count: number,
}

local QueueService = {}

local queues: { [string]: PadQueue } = {}
local queueOrder: { PadQueue } = {}
local tracker: QueueRules.Tracker = QueueRules.newTracker({})
local joinedAt: { [Player]: number } = {}
-- Last notice per player, so the same reason is not re-sent every tick.
local lastNotice: { [Player]: string } = {}
-- Carried party members per mode this tick (for personal snapshots).
local carried: { [Player]: string } = {}
local lastSnapshot: { [Player]: string } = {}
local boardDirty = true

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function matchSize(mode: Types.ModeDef): number
	return if mode.teams > 1 then mode.teams * mode.teamSize else mode.minPlayers
end

local function notice(player: Player, modeId: string, reason: string)
	local key = modeId .. "|" .. reason
	if lastNotice[player] == key then
		return
	end
	lastNotice[player] = key
	Remotes.QueueNotice:fireClient(player, { modeId = modeId, reason = reason })
end

local function clearNotice(player: Player)
	if lastNotice[player] ~= nil then
		lastNotice[player] = nil
		Remotes.QueueNotice:fireClient(player, { modeId = "", reason = "" })
	end
end

-- Why `player` may not queue `mode` right now, or nil. Checked again for every carried member.
function QueueService.lockReason(player: Player, mode: Types.ModeDef): string?
	local data = DataService.getData(player)
	if data == nil then
		return "Loading your data"
	end
	if mode.sandbox or mode.bayOrder <= 0 then
		return "Not available"
	end
	local ok, reason = Requirements.check(mode.unlock, Requirements.progressOf(data), `to play {mode.displayName}`)
	if not ok then
		return reason
	end
	if mode.ranked then
		return RankService.lockReason(player)
	end
	return nil
end

-- Lobby players who can be put in a match at all.
local function isFree(player: Player): boolean
	return player.Parent ~= nil
		and DataService.isLoaded(player)
		and not DataService.isSandboxed(player)
		and not MatchService.isInMatch(player)
end

-- The character's root part, but only while the character is alive.
local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil or character.Parent == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- The bay whose standing zone contains `position`: inside its radius horizontally, and between
-- its surface and PAD_VERTICAL_TOLERANCE above it.
local function padAt(position: Vector3): PadQueue?
	for _, queue in queueOrder do
		local offset = position - queue.pad.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if horizontal <= queue.radius and offset.Y >= 0 and offset.Y <= QUEUE.PAD_VERTICAL_TOLERANCE then
			return queue
		end
	end
	return nil
end

local function onLeft(player: Player, modeId: string, dodgeCounts: boolean)
	local queue = queues[modeId]
	joinedAt[player] = nil
	boardDirty = true
	if queue ~= nil and dodgeCounts and queue.mode.ranked and queue.countdownEndsAt ~= nil and queue.countdownPlayers[player] then
		queue.countdownPlayers[player] = nil
		RankService.penalizeDodge(player, modeId)
	end
end

local function removeNow(player: Player)
	local left = QueueRules.remove(tracker, player)
	if left ~= nil then
		onLeft(player, left, true)
	end
end

local function observe(player: Player, now: number)
	local root = aliveRoot(player)
	local pad = if root ~= nil then padAt(root.Position) else nil
	local padId: string? = nil
	if pad ~= nil then
		local reason = QueueService.lockReason(player, pad.mode)
		if reason ~= nil then
			-- Locked pads never queue the player; the plate shows why.
			notice(player, pad.mode.id, reason)
		else
			padId = pad.mode.id
		end
	end
	local left, joined = QueueRules.observe(tracker, player, {
		padId = padId,
		alive = root ~= nil,
		eligible = isFree(player),
	}, now, QUEUE.LEAVE_GRACE)
	if left ~= nil then
		onLeft(player, left, true)
	end
	if joined ~= nil then
		joinedAt[player] = now
		boardDirty = true
		clearNotice(player)
	end
	if pad == nil and padId == nil and lastNotice[player] ~= nil and QueueRules.queueOf(tracker, player) == nil then
		clearNotice(player)
	end
end

local function powerOf(player: Player): number
	local data = DataService.getData(player)
	if data == nil then
		return 0
	end
	local total = 0
	for _, robotId in data.equippedLoadout do
		local robot = RobotConfig.Robots[robotId]
		if robot ~= nil then
			total += robot.health + robot.damage * 4
		end
	end
	return total
end

-- Queue entries for one mode in arrival order. Party leaders carry their free members.
local function buildEntries(queue: PadQueue): { Matchmaker.Entry }
	local mode = queue.mode
	local entries: { Matchmaker.Entry } = {}
	local ratingKey = RankConfig.RatingKeys[mode.id]
	local maxSize = Matchmaker.maxEntrySize(mode)

	for _, key in QueueRules.members(tracker, mode.id) do
		local player = key :: Player
		local party = PartyService.partyOf(player)
		local members: { Player } = { player }
		if party ~= nil then
			if party.leader ~= player then
				-- A member stands on a pad: they queue on their own unless their leader is queued,
				-- in which case the leader's queue carries them instead.
				if QueueRules.queueOf(tracker, party.leader) ~= nil then
					continue
				end
			else
				members = {}
				for _, member in party.members do
					if member == player or isFree(member) then
						table.insert(members, member)
					end
				end
			end
		end

		if #members > maxSize then
			notice(player, mode.id, `Party of {#members} is too large for {mode.displayName} (max {maxSize})`)
			continue
		end
		if mode.requiresParty and #members < 2 then
			notice(player, mode.id, `{mode.displayName} needs a party`)
			continue
		end
		local blocked: string? = nil
		for _, member in members do
			if member ~= player then
				local reason = QueueService.lockReason(member, mode)
				if reason ~= nil then
					blocked = `{member.DisplayName}: {reason}`
					break
				end
			end
		end
		if blocked ~= nil then
			notice(player, mode.id, blocked)
			continue
		end

		local values: { number } = {}
		for _, member in members do
			table.insert(
				values,
				if ratingKey ~= nil then RankService.ratingFor(member, ratingKey) else powerOf(member)
			)
		end
		local total = 0
		for _, value in values do
			total += value
		end
		table.insert(entries, {
			key = player,
			members = members,
			value = total / #values,
			joinedAt = joinedAt[player] or os.clock(),
		})
		for _, member in members do
			if member ~= player then
				carried[member] = mode.id
			end
		end
	end
	return entries
end

local function shape(mode: Types.ModeDef): Matchmaker.ModeShape
	return {
		teams = mode.teams,
		teamSize = mode.teamSize,
		minPlayers = mode.minPlayers,
		maxPlayers = mode.maxPlayers,
		ranked = mode.ranked,
	}
end

local function blockedPair(a: Matchmaker.Entry, b: Matchmaker.Entry): boolean
	for _, first in a.members do
		for _, second in b.members do
			if RankService.isRepeatPair(first :: Player, second :: Player) then
				return true
			end
		end
	end
	return false
end

local function selectMatches(queue: PadQueue, entries: { Matchmaker.Entry }, now: number): { Matchmaker.Selection }
	local mode = queue.mode
	return Matchmaker.selectAll(
		entries,
		shape(mode),
		now,
		if mode.ranked then RankConfig.Window else nil,
		if mode.ranked then blockedPair else nil
	)
end

local function launch(queue: PadQueue, selection: Matchmaker.Selection, now: number)
	local mode = queue.mode
	local teams: { { Player } } = {}
	local everyone: { Player } = {}
	for _, team in selection.teams do
		local list: { Player } = {}
		for _, member in team do
			table.insert(list, member :: Player)
			table.insert(everyone, member :: Player)
		end
		table.insert(teams, list)
	end
	for _, entry in selection.entries do
		local waited = now - entry.joinedAt
		queue.estimatedWait = queue.estimatedWait * (1 - WAIT_SMOOTHING) + waited * WAIT_SMOOTHING
	end
	-- Leaving the queue because your match is starting is never a dodge.
	for _, player in everyone do
		local left = QueueRules.remove(tracker, player)
		if left ~= nil then
			onLeft(player, left, false)
		end
		queue.countdownPlayers[player] = nil
	end

	local ok, errorCode = MatchService.startMatch(mode.id, everyone, { teams = teams })
	if ok then
		LobbyService.openBlastDoor(mode.id)
		return
	end
	warn(`[QueueService] {mode.id} match failed to start: {errorCode}`)
	for _, player in everyone do
		if player.Parent ~= nil then
			Notifier.error(player, ErrorCode.MatchStartFailed)
			-- Off the pad and back in the hall, so a failing start cannot loop.
			LobbyService.returnToDuelsHall(player)
		end
	end
end

local function processQueue(queue: PadQueue, entries: { Matchmaker.Entry }, now: number)
	local selections = selectMatches(queue, entries, now)
	local count = 0
	for _, entry in entries do
		count += #entry.members
	end
	if count ~= queue.count then
		queue.count = count
		boardDirty = true
	end

	if #selections == 0 then
		if queue.countdownEndsAt ~= nil then
			queue.countdownEndsAt = nil
			table.clear(queue.countdownPlayers)
			boardDirty = true
		end
		return
	end

	if queue.countdownEndsAt == nil then
		queue.countdownEndsAt = serverNow() + queue.mode.queueCountdown
		boardDirty = true
	end
	-- Track who the running countdown would start, for dodge detection.
	table.clear(queue.countdownPlayers)
	for _, selection in selections do
		for _, team in selection.teams do
			for _, member in team do
				queue.countdownPlayers[member :: Player] = true
			end
		end
	end

	local endsAt = queue.countdownEndsAt :: number
	if serverNow() >= endsAt then
		queue.countdownEndsAt = nil
		boardDirty = true
		for _, selection in selections do
			launch(queue, selection, now)
		end
		table.clear(queue.countdownPlayers)
	end
end

local function personalSnapshot(player: Player): Types.QueueSnapshot
	local modeId = QueueRules.queueOf(tracker, player)
	local viaParty = false
	if carried[player] ~= nil then
		modeId = carried[player]
		viaParty = true
	end
	local queue = if modeId ~= nil then queues[modeId] else nil
	if queue == nil then
		return { modeId = nil, count = 0, matchSize = 0, countdownEndsAt = nil, viaParty = false }
	end
	return {
		modeId = queue.mode.id,
		count = queue.count,
		matchSize = matchSize(queue.mode),
		countdownEndsAt = queue.countdownEndsAt,
		viaParty = viaParty,
	}
end

local function boardEntries(): { Types.QueueBoardEntry }
	local entries: { Types.QueueBoardEntry } = {}
	for _, queue in queueOrder do
		table.insert(entries, {
			modeId = queue.mode.id,
			count = queue.count,
			matchSize = matchSize(queue.mode),
			countdownEndsAt = queue.countdownEndsAt,
			estimatedWait = math.floor(queue.estimatedWait + 0.5),
		})
	end
	return entries
end

local function sendPersonal(player: Player)
	local snapshot = personalSnapshot(player)
	local signature = `{snapshot.modeId or ""}|{snapshot.count}|{snapshot.countdownEndsAt or 0}|{snapshot.viaParty}`
	if lastSnapshot[player] ~= signature then
		lastSnapshot[player] = signature
		Remotes.QueueUpdated:fireClient(player, snapshot)
	end
end

local function tickQueues()
	local now = os.clock()
	local players = Players:GetPlayers()
	for _, player in players do
		observe(player, now)
	end
	table.clear(carried)
	for _, queue in queueOrder do
		processQueue(queue, buildEntries(queue), now)
	end
	for _, player in players do
		sendPersonal(player)
	end
	if boardDirty then
		boardDirty = false
		Remotes.QueueBoard:fireAll(boardEntries())
	end
end

-- Death and resets remove the player at once instead of waiting for the next check.
local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			removeNow(player)
		end)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		removeNow(player)
	end)
	local character = player.Character
	if character ~= nil then
		task.spawn(watchCharacter, player, character)
	end
end

local function forget(player: Player)
	removeNow(player)
	joinedAt[player] = nil
	lastNotice[player] = nil
	lastSnapshot[player] = nil
	carried[player] = nil
end

function QueueService.init()
	local capacities: { [string]: number } = {}
	for _, instance in CollectionService:GetTagged(Constants.Tags.QueuePad) do
		local modeId = instance:GetAttribute(Constants.Attributes.ModeId)
		local mode = if type(modeId) == "string" then ModeConfig.Modes[modeId] else nil
		if mode == nil or not instance:IsA("BasePart") then
			warn(
				`[QueueService] Queue pad {instance:GetFullName()} needs a valid {Constants.Attributes.ModeId} attribute.`
			)
			continue
		end
		local radiusAttribute = instance:GetAttribute(Constants.Attributes.QueueRadius)
		local radius = if type(radiusAttribute) == "number"
			then radiusAttribute
			else math.min(instance.Size.X, instance.Size.Z) * 0.5
		queues[mode.id] = {
			mode = mode,
			pad = instance,
			radius = radius,
			countdownEndsAt = nil,
			countdownPlayers = {},
			estimatedWait = mode.estimatedWait,
			count = 0,
		}
		capacities[mode.id] = mode.queueCap
	end
	for _, mode in ModeConfig.bayModes() do
		local queue = queues[mode.id]
		if queue ~= nil then
			table.insert(queueOrder, queue)
		end
	end
	tracker = QueueRules.newTracker(capacities)
end

function QueueService.start()
	Remotes.RequestSync:connect(function(player: Player)
		lastSnapshot[player] = nil
		sendPersonal(player)
		Remotes.QueueBoard:fireClient(player, boardEntries())
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- Before the final save, so a ranked dodge by disconnecting is saved too.
	DataService.beforeRelease:connect(forget)
	Players.PlayerRemoving:Connect(forget)

	task.spawn(function()
		while true do
			tickQueues()
			task.wait(QUEUE.TICK)
		end
	end)
end

return QueueService

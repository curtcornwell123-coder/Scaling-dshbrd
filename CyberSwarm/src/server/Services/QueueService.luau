--!strict
--[[
	QueueService
	Matchmaking queues for the lobby pads. Standing on a pad (or pressing Play, which walks you onto
	it) puts you in that mode's queue; stepping off leaves it. Membership is decided by a fixed-rate
	position check instead of Touched/TouchEnded, which are unreliable for players standing still.
	When a queue reaches the mode's minPlayers a countdown starts; when it ends, up to maxPlayers
	are handed to MatchService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local DataService = require(script.Parent.DataService)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local Notifier = require(script.Parent.Parent.Notifier)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)

local ErrorCode = Constants.ErrorCode

type Queue = {
	mode: Types.ModeDef,
	padInfo: LobbyBuilder.PadInfo,
	players: { Player },
	countdownEndsAt: number?,
	countdownEndsAtServer: number?,
	changed: boolean,
}

local QueueService = {}

local queues: { [string]: Queue } = {}
local playerQueues: { [Player]: Queue } = {}

local function snapshot(queue: Queue?): Types.QueueSnapshot
	if queue == nil then
		return { modeId = nil, count = 0, required = 0, capacity = 0, countdownEndsAt = nil }
	end
	return {
		modeId = queue.mode.id,
		count = #queue.players,
		required = queue.mode.minPlayers,
		capacity = queue.mode.maxPlayers,
		countdownEndsAt = queue.countdownEndsAtServer,
	}
end

local function leave(player: Player)
	local queue = playerQueues[player]
	if queue == nil then
		return
	end
	playerQueues[player] = nil
	local index = table.find(queue.players, player)
	if index ~= nil then
		table.remove(queue.players, index)
	end
	queue.changed = true
	if player.Parent ~= nil then
		Remotes.QueueUpdated:fireClient(player, snapshot(nil))
	end
end

local function join(player: Player, queue: Queue): boolean
	if playerQueues[player] == queue then
		return true
	end
	if not DataService.isLoaded(player) or MatchService.isInMatch(player) then
		return false
	end
	leave(player)
	if #queue.players >= queue.mode.maxPlayers then
		return false
	end
	table.insert(queue.players, player)
	playerQueues[player] = queue
	queue.changed = true
	return true
end

-- True when the player's root part is over the pad's footprint and roughly at its height.
local function isOnPad(rootPosition: Vector3, pad: BasePart): boolean
	local localPosition = pad.CFrame:PointToObjectSpace(rootPosition)
	local halfX = pad.Size.X * 0.5
	local halfZ = pad.Size.Z * 0.5
	return math.abs(localPosition.X) <= halfX
		and math.abs(localPosition.Z) <= halfZ
		and localPosition.Y >= 0
		and localPosition.Y <= Constants.Queue.PAD_VERTICAL_TOLERANCE
end

local function padUnder(player: Player): Queue?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	for _, queue in queues do
		if isOnPad(root.Position, queue.padInfo.pad) then
			return queue
		end
	end
	return nil
end

local function updatePadLabel(queue: Queue, now: number)
	local mode = queue.mode
	local text: string
	if queue.countdownEndsAt ~= nil then
		text = `STARTING IN {math.max(0, math.ceil(queue.countdownEndsAt - now))}`
	elseif #queue.players > 0 then
		text = `{#queue.players}/{mode.maxPlayers}  NEED {mode.minPlayers}`
	else
		text = "STEP ON TO QUEUE"
	end
	if queue.padInfo.statusLabel.Text ~= text then
		queue.padInfo.statusLabel.Text = text
	end
end

local function launch(queue: Queue)
	local group: { Player } = {}
	for index = 1, math.min(#queue.players, queue.mode.maxPlayers) do
		table.insert(group, queue.players[index])
	end
	for _, player in group do
		leave(player)
	end
	queue.countdownEndsAt = nil
	queue.countdownEndsAtServer = nil

	local ok, errorCode = MatchService.startMatch(queue.mode.id, group)
	if not ok then
		for _, player in group do
			Notifier.error(player, errorCode or ErrorCode.MatchFailed)
			-- Step them off the pad so a failing match cannot re-queue them in a loop.
			LobbyService.returnToLobby(player)
		end
	end
end

local function processQueue(queue: Queue, now: number)
	local count = #queue.players
	if count >= queue.mode.minPlayers then
		if queue.countdownEndsAt == nil then
			queue.countdownEndsAt = now + queue.mode.queueCountdown
			queue.countdownEndsAtServer = workspace:GetServerTimeNow() + queue.mode.queueCountdown
			queue.changed = true
		elseif now >= queue.countdownEndsAt then
			launch(queue)
		end
	elseif queue.countdownEndsAt ~= nil then
		queue.countdownEndsAt = nil
		queue.countdownEndsAtServer = nil
		queue.changed = true
	end

	if queue.changed then
		queue.changed = false
		local payload = snapshot(queue)
		Remotes.QueueUpdated:fireClients(queue.players, payload)
	end
	updatePadLabel(queue, now)
end

local function tickQueues()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if MatchService.isInMatch(player) then
			leave(player)
		else
			local standingOn = padUnder(player)
			local current = playerQueues[player]
			if standingOn ~= current then
				leave(player)
				if standingOn ~= nil then
					join(player, standingOn)
				end
			end
		end
	end
	for _, queue in queues do
		processQueue(queue, now)
	end
end

local function onJoinRequest(player: Player, modeIdRaw: unknown)
	if type(modeIdRaw) ~= "string" then
		Notifier.error(player, ErrorCode.InvalidMode)
		return
	end
	local queue = queues[modeIdRaw :: string]
	if queue == nil then
		Notifier.error(player, ErrorCode.InvalidMode)
		return
	end
	if MatchService.isInMatch(player) then
		Notifier.error(player, ErrorCode.AlreadyInMatch)
		return
	end
	if not DataService.isLoaded(player) then
		Notifier.error(player, ErrorCode.DataNotLoaded)
		return
	end
	-- Walking the character onto the pad keeps the pad as the single source of queue membership.
	if not LobbyService.teleportToPad(player, queue.mode.id) then
		Notifier.error(player, ErrorCode.NoCharacter)
		return
	end
	join(player, queue)
end

local function onLeaveRequest(player: Player)
	if playerQueues[player] == nil then
		return
	end
	leave(player)
	LobbyService.returnToLobby(player)
end

function QueueService.init()
	for _, padInfo in LobbyService.getPads() do
		local mode = ModeConfig.Modes[padInfo.modeId]
		if mode ~= nil then
			queues[mode.id] = {
				mode = mode,
				padInfo = padInfo,
				players = {},
				countdownEndsAt = nil,
				countdownEndsAtServer = nil,
				changed = false,
			}
		end
	end
end

function QueueService.start()
	Remotes.RequestJoinQueue:connect(onJoinRequest)
	Remotes.RequestLeaveQueue:connect(onLeaveRequest)
	Remotes.RequestSync:connect(function(player: Player)
		Remotes.QueueUpdated:fireClient(player, snapshot(playerQueues[player]))
	end)
	Players.PlayerRemoving:Connect(leave)

	task.spawn(function()
		while true do
			tickQueues()
			task.wait(Constants.Queue.TICK)
		end
	end)
end

return QueueService

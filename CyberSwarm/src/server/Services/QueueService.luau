--!strict
--[[
	QueueService
	Matchmaking for the lobby queue pads. Queueing is decided ONLY here, on the server: there is no
	remote a client can fire to join or leave a queue. Every Constants.Queue.TICK the server looks
	at each player's character and asks "alive, and inside which pad's zone?", then QueueRules turns
	those observations into queue membership (one queue per player, a short grace period for
	jitter, instant removal on death, reset, or disconnect).

	Feedback is in-world: each pad's floor ring fills as players join, and the lobby's queue board
	screen shows every mode's count and countdown. The same counts are broadcast to clients for the
	info-only Deploy panel.

	A pad is any BasePart tagged Constants.Tags.QueuePad with a ModeId attribute. Optional: a
	QueueRadius attribute, a "Ring" folder of "Segment_N" parts, and a matching "Mode_<ModeId>"
	label on a screen tagged Constants.Tags.QueueBoard.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local QueueRules = require(ReplicatedStorage.Shared.Logic.QueueRules)
local DataService = require(script.Parent.DataService)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local Notifier = require(script.Parent.Parent.Notifier)

local ErrorCode = Constants.ErrorCode
local QUEUE = Constants.Queue

type PadQueue = {
	mode: Types.ModeDef,
	pad: BasePart,
	radius: number,
	ring: { BasePart },
	ringLit: number,
	boardLabel: TextLabel?,
	countdownEndsAt: number?,
	countdownEndsAtServer: number?,
	changed: boolean,
}

local QueueService = {}

local queues: { [string]: PadQueue } = {}
local queueOrder: { PadQueue } = {}
local tracker: QueueRules.Tracker = QueueRules.newTracker({})
local boardDirty = true

local function members(queue: PadQueue): { Player }
	return QueueRules.members(tracker, queue.mode.id) :: { Player }
end

local function personalSnapshot(queue: PadQueue?): Types.QueueSnapshot
	if queue == nil then
		return { modeId = nil, count = 0, required = 0, capacity = 0, countdownEndsAt = nil }
	end
	return {
		modeId = queue.mode.id,
		count = #members(queue),
		required = queue.mode.minPlayers,
		capacity = queue.mode.maxPlayers,
		countdownEndsAt = queue.countdownEndsAtServer,
	}
end

local function boardEntries(): { Types.QueueBoardEntry }
	local entries: { Types.QueueBoardEntry } = {}
	for _, queue in queueOrder do
		table.insert(entries, {
			modeId = queue.mode.id,
			count = #members(queue),
			required = queue.mode.minPlayers,
			capacity = queue.mode.maxPlayers,
			countdownEndsAt = queue.countdownEndsAtServer,
		})
	end
	return entries
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

-- The pad whose standing zone contains `position`: inside its radius horizontally, and between
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

local function markChanged(player: Player, left: string?, joined: string?)
	if left ~= nil then
		queues[left].changed = true
	end
	if joined ~= nil then
		queues[joined].changed = true
	end
	-- Someone who left without joining elsewhere gets an explicit "not queued" status.
	if left ~= nil and joined == nil and player.Parent ~= nil then
		Remotes.QueueUpdated:fireClient(player, personalSnapshot(nil))
	end
end

local function removeNow(player: Player)
	markChanged(player, QueueRules.remove(tracker, player), nil)
end

local function observe(player: Player, now: number)
	local root = aliveRoot(player)
	local pad = if root ~= nil then padAt(root.Position) else nil
	local left, joined = QueueRules.observe(tracker, player, {
		padId = if pad ~= nil then pad.mode.id else nil,
		alive = root ~= nil,
		eligible = DataService.isLoaded(player) and not MatchService.isInMatch(player),
	}, now, QUEUE.LEAVE_GRACE)
	markChanged(player, left, joined)
end

local function launch(queue: PadQueue)
	local waiting = members(queue)
	local group: { Player } = {}
	for index = 1, math.min(#waiting, queue.mode.maxPlayers) do
		table.insert(group, waiting[index])
	end
	for _, player in group do
		removeNow(player)
	end
	queue.countdownEndsAt = nil
	queue.countdownEndsAtServer = nil
	queue.changed = true

	local ok, errorCode = MatchService.startMatch(queue.mode.id, group)
	if not ok then
		for _, player in group do
			Notifier.error(player, errorCode or ErrorCode.MatchFailed)
			-- Move them off the pad so a failing match cannot re-queue them in a loop.
			LobbyService.returnToLobby(player)
		end
	end
end

local function updateRing(queue: PadQueue, count: number)
	local segments = #queue.ring
	if segments == 0 then
		return
	end
	local lit = if count <= 0 then 0 else math.max(1, math.floor(count / queue.mode.maxPlayers * segments + 0.5))
	if lit == queue.ringLit then
		return
	end
	queue.ringLit = lit
	for index, segment in queue.ring do
		local on = index <= lit
		segment.Color = if on then queue.mode.padColor else Theme.World.RingUnlit
		segment.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function updateBoard(queue: PadQueue, count: number, now: number)
	local label = queue.boardLabel
	if label == nil then
		return
	end
	local mode = queue.mode
	local status: string
	local endsAt = queue.countdownEndsAt
	if endsAt ~= nil then
		status = `STARTING IN {math.max(0, math.ceil(endsAt - now))}`
	elseif count > 0 then
		status = `NEED {mode.minPlayers}`
	else
		status = "STEP ON THE PAD TO QUEUE"
	end
	local text = `{string.upper(mode.displayName)}   {count}/{mode.maxPlayers}   {status}`
	if label.Text ~= text then
		label.Text = text
	end
end

local function processQueue(queue: PadQueue, now: number)
	local count = #members(queue)
	if count >= queue.mode.minPlayers then
		if queue.countdownEndsAt == nil then
			queue.countdownEndsAt = now + queue.mode.queueCountdown
			queue.countdownEndsAtServer = workspace:GetServerTimeNow() + queue.mode.queueCountdown
			queue.changed = true
		elseif now >= queue.countdownEndsAt then
			launch(queue)
			count = #members(queue)
		end
	elseif queue.countdownEndsAt ~= nil then
		queue.countdownEndsAt = nil
		queue.countdownEndsAtServer = nil
		queue.changed = true
	end

	if queue.changed then
		queue.changed = false
		boardDirty = true
		local current = members(queue)
		Remotes.QueueUpdated:fireClients(current, personalSnapshot(queue))
	end
	updateRing(queue, count)
	updateBoard(queue, count, now)
end

local function tickQueues()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		observe(player, now)
	end
	for _, queue in queueOrder do
		processQueue(queue, now)
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

local function sortedRing(pad: BasePart): { BasePart }
	local ring: { BasePart } = {}
	local folder = pad:FindFirstChild("Ring")
	if folder == nil then
		return ring
	end
	local entries: { { index: number, part: BasePart } } = {}
	for _, child in folder:GetChildren() do
		local index = tonumber(string.match(child.Name, "^Segment_(%d+)$"))
		if index ~= nil and child:IsA("BasePart") then
			table.insert(entries, { index = index, part = child })
		end
	end
	table.sort(entries, function(a: { index: number }, b: { index: number })
		return a.index < b.index
	end)
	for _, entry in entries do
		table.insert(ring, entry.part)
	end
	return ring
end

local function findBoardLabel(modeId: string): TextLabel?
	for _, screen in CollectionService:GetTagged(Constants.Tags.QueueBoard) do
		local label = screen:FindFirstChild("Mode_" .. modeId, true)
		if label ~= nil and label:IsA("TextLabel") then
			return label
		end
	end
	return nil
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
		local queue: PadQueue = {
			mode = mode,
			pad = instance,
			radius = radius,
			ring = sortedRing(instance),
			ringLit = -1,
			boardLabel = findBoardLabel(mode.id),
			countdownEndsAt = nil,
			countdownEndsAtServer = nil,
			changed = false,
		}
		queues[mode.id] = queue
		capacities[mode.id] = mode.maxPlayers
	end
	for _, modeId in ModeConfig.Order do
		local queue = queues[modeId]
		if queue ~= nil then
			table.insert(queueOrder, queue)
		end
	end
	tracker = QueueRules.newTracker(capacities)
end

function QueueService.start()
	Remotes.RequestSync:connect(function(player: Player)
		local modeId = QueueRules.queueOf(tracker, player)
		Remotes.QueueUpdated:fireClient(player, personalSnapshot(if modeId ~= nil then queues[modeId] else nil))
		Remotes.QueueBoard:fireClient(player, boardEntries())
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(removeNow)

	task.spawn(function()
		while true do
			tickQueues()
			task.wait(QUEUE.TICK)
		end
	end)
end

return QueueService

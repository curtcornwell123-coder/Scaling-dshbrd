--!strict
--[[
	LeaderboardService
	The hub Win Streaks wall and the Duels Hall ranked walls, backed by OrderedDataStores.

	- Values are only ever written by the server from saved data (best win streak, ranked rating).
	- Writes are batched: a player's value is marked dirty and flushed on the refresh loop, so a
	  busy server stays well inside the data store budget.
	- Each board's top entries are cached and broadcast. If a store call fails the cached copy is
	  kept and sent with live = false; clients show an empty state until the first data arrives.
	- In Studio without API access the boards are built from the players in this server only.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local BOARD = Constants.Leaderboard

type Board = {
	id: string,
	storeName: string,
	store: OrderedDataStore?,
	-- userId -> value waiting to be written.
	pending: { [number]: number },
	-- userId -> value, used when the store is unreachable (Studio, outages).
	localValues: { [number]: number },
	snapshot: Types.LeaderboardSnapshot,
}

local LeaderboardService = {}

local boards: { [string]: Board } = {}
local boardOrder: { Board } = {}
local nameCache: { [number]: string } = {}
local useStores = true

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached ~= nil then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok then name else `Player {userId}`
	nameCache[userId] = resolved
	return resolved
end

-- Adds a board. Ranked boards are registered by RankService (one per rating key).
function LeaderboardService.register(boardId: string, storeName: string)
	if boards[boardId] ~= nil then
		return
	end
	local board: Board = {
		id = boardId,
		storeName = storeName,
		store = nil,
		pending = {},
		localValues = {},
		snapshot = { board = boardId, entries = {}, updatedAt = 0, live = false },
	}
	if useStores then
		local ok, store = pcall(function(): OrderedDataStore
			return DataStoreService:GetOrderedDataStore(storeName)
		end)
		if ok then
			board.store = store
		end
	end
	boards[boardId] = board
	table.insert(boardOrder, board)
end

-- Records a player's value; written on the next refresh. Values are whole numbers.
function LeaderboardService.submit(boardId: string, userId: number, value: number)
	local board = boards[boardId]
	if board == nil then
		return
	end
	local whole = math.max(0, math.floor(value))
	board.pending[userId] = whole
	board.localValues[userId] = whole
end

local function localSnapshot(board: Board): { Types.LeaderboardEntry }
	local list: { { userId: number, value: number } } = {}
	for userId, value in board.localValues do
		table.insert(list, { userId = userId, value = value })
	end
	table.sort(list, function(a: { value: number }, b: { value: number })
		return a.value > b.value
	end)
	local entries: { Types.LeaderboardEntry } = {}
	for index = 1, math.min(#list, BOARD.SIZE) do
		local item = list[index]
		table.insert(entries, { rank = index, userId = item.userId, name = nameFor(item.userId), value = item.value })
	end
	return entries
end

local function refreshBoard(board: Board)
	local store = board.store
	if store == nil then
		board.snapshot = { board = board.id, entries = localSnapshot(board), updatedAt = os.time(), live = false }
		return
	end
	local activeStore = store :: OrderedDataStore
	local writes = board.pending
	board.pending = {}
	for userId, value in writes do
		local ok, err = pcall(function()
			activeStore:SetAsync(tostring(userId), value)
		end)
		if not ok then
			warn(`[LeaderboardService] Write to {board.storeName} failed: {err}`)
			board.pending[userId] = value
		end
	end

	local ok, result = pcall(function(): any
		local pages = activeStore:GetSortedAsync(false, BOARD.SIZE)
		return pages:GetCurrentPage()
	end)
	if not ok then
		warn(`[LeaderboardService] Read of {board.storeName} failed: {result}`)
		board.snapshot = {
			board = board.id,
			entries = board.snapshot.entries,
			updatedAt = board.snapshot.updatedAt,
			live = false,
		}
		return
	end
	local entries: { Types.LeaderboardEntry } = {}
	for index, item in result do
		local userId = tonumber(item.key)
		if userId ~= nil and type(item.value) == "number" then
			table.insert(entries, { rank = index, userId = userId, name = nameFor(userId), value = item.value })
		end
	end
	board.snapshot = { board = board.id, entries = entries, updatedAt = os.time(), live = true }
end

local function sendAll(player: Player?)
	for _, board in boardOrder do
		if player ~= nil then
			Remotes.Leaderboard:fireClient(player, board.snapshot)
		else
			Remotes.Leaderboard:fireAll(board.snapshot)
		end
	end
end

function LeaderboardService.init()
	-- Studio without API access: skip the stores entirely rather than erroring every refresh.
	if RunService:IsStudio() then
		useStores = pcall(function()
			DataStoreService:GetDataStore("__studio_probe"):GetAsync("probe")
		end)
	end
	LeaderboardService.register(BOARD.WIN_STREAK, BOARD.WIN_STREAK_STORE)
end

local function submitStreak(player: Player)
	local data = DataService.getData(player)
	if data ~= nil and data.stats.bestWinStreak > 0 then
		LeaderboardService.submit(BOARD.WIN_STREAK, player.UserId, data.stats.bestWinStreak)
	end
end

function LeaderboardService.start()
	Players.PlayerAdded:Connect(function(player: Player)
		sendAll(player)
	end)
	DataService.profileLoaded:connect(submitStreak)
	MatchService.matchEnded:connect(function(match)
		for player in match.players do
			submitStreak(player)
		end
	end)
	Remotes.RequestSync:connect(function(player: Player)
		sendAll(player)
	end)
	task.spawn(function()
		-- Short first wait so the walls fill soon after the server starts.
		task.wait(5)
		while true do
			for _, board in boardOrder do
				refreshBoard(board)
			end
			sendAll(nil)
			task.wait(BOARD.REFRESH_INTERVAL)
		end
	end)
end

return LeaderboardService

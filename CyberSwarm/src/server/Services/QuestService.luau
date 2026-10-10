--!strict
--[[
	QuestService
	Daily Tasks. The day's tasks are the same for everyone (QuestRules, seeded by UTC day) and
	progress comes only from server-verified MatchService events: matches finished and won, waves
	cleared, robots queued.

	Test Realm tasks (testRealm = true) progress only inside a sandbox match, and regular tasks
	never do. Saved data cannot be written in the Test Realm, so sandbox progress is kept apart:
	- On a Test Realm server it is flushed to Constants.TestRealm.PROGRESS_STORE.
	- In Studio's local Test Realm it is kept in memory.
	When the player is back in the main game it is merged into their saved tasks (same UTC day
	only), and the reward is claimed from the Tasks panel like any other task.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local QuestRules = require(ReplicatedStorage.Shared.Logic.QuestRules)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local Actions = require(script.Parent.Parent.Actions)
local Rewards = require(script.Parent.Parent.Rewards)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local ErrorCode = Constants.ErrorCode

local settings: QuestRules.QuestSettings = {
	regularPool = QuestConfig.RegularPool,
	testRealmPool = QuestConfig.TestRealmPool,
	regularPerDay = QuestConfig.RegularPerDay,
	testRealmPerDay = QuestConfig.TestRealmPerDay,
	seed = QuestConfig.Seed,
}

type SandboxProgress = Types.QuestData

local QuestService = {}

local sandboxProgress: { [Player]: SandboxProgress } = {}
local dirtySandbox: { [Player]: boolean } = {}
local progressStore: DataStore? = nil

local function today(): number
	return Calendar.dayNumber(os.time())
end

function QuestService.todaysQuests(): { string }
	return QuestRules.dailyQuests(today(), settings)
end

local function questsOfKind(kind: Types.QuestKind, testRealm: boolean): { Types.QuestDef }
	local list: { Types.QuestDef } = {}
	for _, questId in QuestService.todaysQuests() do
		local quest = QuestConfig.Quests[questId]
		if quest ~= nil and quest.kind == kind and quest.testRealm == testRealm then
			table.insert(list, quest)
		end
	end
	return list
end

local function emptyProgress(): SandboxProgress
	return { day = today(), progress = {}, claimed = {}, tried = {} }
end

-- Regular progress: straight into saved data.
local function addRegular(player: Player, kind: Types.QuestKind, amount: number)
	local quests = questsOfKind(kind, false)
	local data = DataService.getData(player)
	if #quests == 0 or data == nil then
		return
	end
	-- Skip the save-and-push when every matching task is already complete (or claimed).
	local open = data.quests.day ~= today()
	for _, quest in quests do
		if (data.quests.progress[quest.id] or 0) < quest.target then
			open = true
		end
	end
	if not open then
		return
	end
	DataService.update(player, function(data)
		QuestRules.normalize(data.quests, today())
		for _, quest in quests do
			QuestRules.addProgress(data.quests, quest, amount)
		end
	end)
end

-- Test Realm progress: kept apart from saved data until the player is back.
local function addSandbox(player: Player, kind: Types.QuestKind, amount: number, troopId: string?)
	local quests = questsOfKind(kind, true)
	if #quests == 0 then
		return
	end
	local progress = sandboxProgress[player]
	if progress == nil then
		progress = emptyProgress()
		sandboxProgress[player] = progress
	end
	local entry = progress :: SandboxProgress
	QuestRules.normalize(entry, today())
	for _, quest in quests do
		if kind == "TryTroops" then
			if troopId ~= nil and QuestRules.recordTried(entry, troopId) then
				QuestRules.addProgress(entry, quest, 1)
			end
		else
			QuestRules.addProgress(entry, quest, amount)
		end
	end
	dirtySandbox[player] = true
end

local function flushSandbox(player: Player)
	local store = progressStore
	local progress = sandboxProgress[player]
	if store == nil or progress == nil or not dirtySandbox[player] then
		return
	end
	dirtySandbox[player] = nil
	local payload = TableUtil.deepCopy(progress)
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), payload)
	end)
	if not ok then
		dirtySandbox[player] = true
		warn(`[QuestService] Could not save Test Realm progress for {player.Name}: {err}`)
	end
end

local function mergeInto(player: Player, progress: any)
	if not TableUtil.isTable(progress) or progress.day ~= today() or not TableUtil.isTable(progress.progress) then
		return
	end
	DataService.update(player, function(data)
		QuestRules.normalize(data.quests, today())
		for questId, value in progress.progress do
			local quest = if type(questId) == "string" then QuestConfig.Quests[questId] else nil
			if quest ~= nil and quest.testRealm and type(value) == "number" then
				-- Never lower progress; take the higher of saved and sandbox values.
				local current = data.quests.progress[quest.id] or 0
				QuestRules.addProgress(data.quests, quest, math.max(0, value - current))
			end
		end
	end)
end

-- Main game: fold in what the player earned in the Test Realm.
local function pullSandboxProgress(player: Player)
	local store = progressStore
	if store == nil or DataService.isSandboxServer() then
		return
	end
	local key = tostring(player.UserId)
	local ok, stored = pcall(function(): any
		return store:GetAsync(key)
	end)
	if ok and stored ~= nil then
		mergeInto(player, stored)
		pcall(function()
			store:RemoveAsync(key)
		end)
	end
end

-- Studio local Test Realm: called by TestRealmService when the player leaves the sandbox.
function QuestService.mergeLocalSandbox(player: Player)
	local progress = sandboxProgress[player]
	sandboxProgress[player] = nil
	dirtySandbox[player] = nil
	if progress ~= nil then
		mergeInto(player, progress)
	end
end

function QuestService.sandboxProgressFor(player: Player): Types.QuestData?
	return sandboxProgress[player]
end

local function claim(player: Player, questId: string): string
	if DataService.isSandboxed(player) then
		return ErrorCode.Sandbox
	end
	local quest = QuestConfig.Quests[questId]
	local todays = QuestService.todaysQuests()
	local code = ErrorCode.DataNotLoaded
	local granted: Types.Reward? = nil
	DataService.update(player, function(data)
		QuestRules.normalize(data.quests, today())
		code = QuestRules.checkClaim(data.quests, quest, todays)
		if code ~= ErrorCode.Ok or quest == nil then
			return
		end
		table.insert(data.quests.claimed, quest.id)
		local reward = table.clone(quest.reward)
		reward.xp = (reward.xp or 0) + SeasonConfig.XpSources.quest
		granted = Rewards.apply(data, reward)
	end)
	local final = granted
	if final ~= nil then
		Notifier.toast({ player }, "Success", `Task complete: {Rewards.describe(final)}`)
	end
	return code
end

local function forEachMatchPlayer(match: ServerTypes.Match, callback: (Player) -> ())
	for player, matchPlayer in match.players do
		if matchPlayer.connected then
			callback(player)
		end
	end
end

function QuestService.init()
	local ok, store = pcall(function(): DataStore
		return DataStoreService:GetDataStore(Constants.TestRealm.PROGRESS_STORE)
	end)
	if ok then
		progressStore = store
	end
end

function QuestService.start()
	MatchService.matchEnded:connect(function(match: ServerTypes.Match, outcome: ServerTypes.Outcome)
		if match.sandbox ~= nil or not match.mode.rewardsEnabled then
			return
		end
		forEachMatchPlayer(match, function(player)
			addRegular(player, "PlayMatches", 1)
			local matchPlayer = match.players[player]
			if outcome.winner ~= nil and matchPlayer ~= nil and matchPlayer.arena == outcome.winner then
				addRegular(player, "WinMatches", 1)
			end
		end)
	end)
	MatchService.waveCleared:connect(function(match: ServerTypes.Match)
		forEachMatchPlayer(match, function(player)
			if match.sandbox ~= nil then
				addSandbox(player, "TestRealmWaves", 1, nil)
			elseif match.mode.rewardsEnabled then
				addRegular(player, "CompleteWaves", 1)
			end
		end)
	end)
	MatchService.robotQueued:connect(function(match: ServerTypes.Match, matchPlayer: ServerTypes.MatchPlayer)
		local player = matchPlayer.player
		if match.sandbox ~= nil then
			-- The last queued robot tells us which troop was just tried.
			local lane = matchPlayer.arena.spawnQueues
			local newest: string? = nil
			for _, queue in lane do
				local last = queue[#queue]
				if last ~= nil and last.owner == matchPlayer then
					newest = last.robotId
				end
			end
			addSandbox(player, "TryTroops", 1, newest)
		elseif match.mode.rewardsEnabled then
			addRegular(player, "DeployRobots", 1)
		end
	end)

	Remotes.RequestClaimQuest:connect(function(player: Player, raw: unknown)
		local questId = Actions.readId(raw)
		Actions.run(player, "ClaimQuest", questId, function(): string
			if questId == nil then
				return ErrorCode.QuestUnknown
			end
			return claim(player, questId)
		end)
	end)

	DataService.profileLoaded:connect(function(player: Player)
		DataService.update(player, function(data)
			QuestRules.normalize(data.quests, today())
		end)
		task.spawn(pullSandboxProgress, player)
	end)

	if DataService.isSandboxServer() then
		task.spawn(function()
			while true do
				task.wait(Constants.TestRealm.FLUSH_INTERVAL)
				for player in sandboxProgress do
					flushSandbox(player)
				end
			end
		end)
		DataService.beforeRelease:connect(function(player: Player)
			task.spawn(flushSandbox, player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		if DataService.isSandboxServer() then
			flushSandbox(player)
		end
		sandboxProgress[player] = nil
		dirtySandbox[player] = nil
		Actions.forget(player)
	end)
end

return QuestService

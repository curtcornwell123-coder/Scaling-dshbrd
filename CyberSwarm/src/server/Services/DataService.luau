--!strict
--[[
	DataService
	Loads, caches, and saves persistent player data.

	- Session locking: each record stores the JobId of the server that owns it. Another server
	  refuses to load (and retries) until the lock is released or goes stale, so two servers can
	  never both write the same player's data.
	- Retries with exponential backoff on every DataStore call.
	- Autosave every Constants.Data.AUTOSAVE_INTERVAL seconds (which also refreshes the lock),
	  plus a releasing save on PlayerRemoving and BindToClose.
	- Schema versioning: records carry schemaVersion and pass through MIGRATIONS on load.
	- A load that still fails after retries kicks the player instead of handing out defaults,
	  because defaults saved later would overwrite their real progress.
	- In Studio without API access it falls back to in-memory data with a warning.
	- Sandbox (Test Realm): on a Test Realm server data is loaded read-only (no session lock) and
	  never saved, and update() rejects every write, so nothing can be earned or lost there.
	  setSandbox(player) applies the same write block to one player (Studio's local Test Realm).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)

local DATA = Constants.Data

type SessionLock = {
	jobId: string,
	time: number,
}

type StoredRecord = {
	schemaVersion: number,
	data: Types.PlayerData,
	lock: SessionLock?,
}

type Profile = {
	data: Types.PlayerData,
	saving: boolean,
	released: boolean,
}

type LoadFailure = "locked" | "newer" | "error" | "unavailable"

local KICK_MESSAGES: { [string]: string } = {
	locked = "Your Cyber Swarm data is still open on another server. Please rejoin in a minute.",
	newer = "This server is running an older version of Cyber Swarm. Please rejoin to reach a newer server.",
	error = "We couldn't load your Cyber Swarm data right now. Your progress is safe - please rejoin shortly.",
	unavailable = "Cyber Swarm data storage is unavailable right now. Your progress is safe - please rejoin shortly.",
}

local DataService = {}

-- Fires once a player's data is loaded and safe to read.
DataService.profileLoaded = Signal.new() :: Signal.Signal<Player>
-- Fires (synchronously) just before a leaving player's final save. Handlers must not yield;
-- this is where a match abandon is turned into a loss so it is part of the saved data.
DataService.beforeRelease = Signal.new() :: Signal.Signal<Player>

local store: DataStore? = nil
local memoryMode = false
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local activeSaves = 0
-- Test Realm server: read-only loads, no saves, every update rejected.
local sandboxServer = false
local sandboxPlayers: { [Player]: boolean } = {}

local function defaultData(): Types.PlayerData
	local defaults = ModeConfig.ProfileDefaults
	return {
		coins = defaults.coins,
		gems = defaults.gems,
		unlockedRobots = table.clone(RobotConfig.DefaultUnlocked),
		equippedLoadout = table.clone(RobotConfig.DefaultUnlocked),
		stats = {
			wins = 0,
			losses = 0,
			wavesSurvived = 0,
			highestWave = 0,
			winStreak = 0,
			bestWinStreak = 0,
		},
		settings = {
			musicVolume = defaults.musicVolume,
			sfxVolume = defaults.sfxVolume,
		},
		purchases = {},
		season = {
			seasonId = SeasonConfig.SeasonId,
			xp = 0,
			premium = false,
			claimedFree = {},
			claimedPremium = {},
		},
		quests = { day = 0, progress = {}, claimed = {}, tried = {} },
		supply = { day = 0, claims = 0, lastClaimAt = 0 },
		codes = {},
		rank = {
			seasonId = SeasonConfig.Ranked.seasonId,
			ratings = {},
			appliedMatches = {},
			recentOpponents = {},
			cooldownUntil = 0,
			pendingReward = nil,
		},
	}
end

local function stringList(value: any, limit: number): { string }
	local list: { string } = {}
	if TableUtil.isTable(value) then
		for _, item in value do
			if type(item) == "string" and #list < limit and not table.find(list, item) then
				table.insert(list, item)
			end
		end
	end
	return list
end

local function numberList(value: any, limit: number): { number }
	local list: { number } = {}
	if TableUtil.isTable(value) then
		for _, item in value do
			if type(item) == "number" and item == item and #list < limit and not table.find(list, item) then
				table.insert(list, item)
			end
		end
	end
	return list
end

local function numberOr(value: any, fallback: number): number
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function sanitizeReward(raw: any): Types.Reward?
	if not TableUtil.isTable(raw) then
		return nil
	end
	local troopId = raw.troopId
	return {
		coins = if type(raw.coins) == "number" then math.max(0, math.floor(raw.coins)) else nil,
		gems = if type(raw.gems) == "number" then math.max(0, math.floor(raw.gems)) else nil,
		xp = if type(raw.xp) == "number" then math.max(0, math.floor(raw.xp)) else nil,
		troopId = if type(troopId) == "string" and RobotConfig.Robots[troopId] ~= nil then troopId else nil,
	}
end

local function sanitizeRank(raw: any, defaults: Types.RankData): Types.RankData
	if not TableUtil.isTable(raw) then
		return defaults
	end
	local ratings: { [string]: Types.RatingData } = {}
	if TableUtil.isTable(raw.ratings) then
		for key, entry in raw.ratings do
			if type(key) == "string" and TableUtil.isTable(entry) and type(entry.rating) == "number" then
				ratings[key] = {
					rating = math.max(0, numberOr(entry.rating, 0)),
					played = math.max(0, math.floor(numberOr(entry.played, 0))),
					wins = math.max(0, math.floor(numberOr(entry.wins, 0))),
					losses = math.max(0, math.floor(numberOr(entry.losses, 0))),
					peak = numberOr(entry.peak, entry.rating),
				}
			end
		end
	end
	local opponents: { { userId: number, at: number } } = {}
	if TableUtil.isTable(raw.recentOpponents) then
		for _, entry in raw.recentOpponents do
			if TableUtil.isTable(entry) and type(entry.userId) == "number" and type(entry.at) == "number" then
				table.insert(opponents, { userId = entry.userId, at = entry.at })
			end
		end
	end
	local pending: Types.RankedReward? = nil
	local rawPending: any = raw.pendingReward
	if
		TableUtil.isTable(rawPending)
		and type(rawPending.seasonId) == "string"
		and type(rawPending.tier) == "string"
	then
		local reward = sanitizeReward(rawPending.reward)
		if reward ~= nil then
			pending = { seasonId = rawPending.seasonId, tier = rawPending.tier, reward = reward }
		end
	end
	return {
		seasonId = if type(raw.seasonId) == "string" then raw.seasonId else defaults.seasonId,
		ratings = ratings,
		appliedMatches = stringList(raw.appliedMatches, 200),
		recentOpponents = opponents,
		cooldownUntil = numberOr(raw.cooldownUntil, 0),
		pendingReward = pending,
	}
end

-- Rebuilds a well-formed PlayerData from anything stored, dropping ids that no longer exist so a
-- removed robot in config can never break a player's loadout.
local function sanitize(raw: any): Types.PlayerData
	local defaults = defaultData()
	if not TableUtil.isTable(raw) then
		return defaults
	end
	local stored = TableUtil.reconcile(raw, defaults :: any)

	local unlocked: { string } = {}
	local owned: { [string]: boolean } = {}
	local function unlock(robotId: any)
		if type(robotId) ~= "string" or owned[robotId] then
			return
		end
		local robot = RobotConfig.Robots[robotId]
		if robot ~= nil and not robot.locked then
			owned[robotId] = true
			table.insert(unlocked, robotId)
		end
	end
	for _, robotId in RobotConfig.DefaultUnlocked do
		unlock(robotId)
	end
	if TableUtil.isTable(stored.unlockedRobots) then
		for _, robotId in stored.unlockedRobots do
			unlock(robotId)
		end
	end

	local loadout: { string } = {}
	local equipped: { [string]: boolean } = {}
	if TableUtil.isTable(stored.equippedLoadout) then
		for _, robotId in stored.equippedLoadout do
			if
				type(robotId) == "string"
				and owned[robotId]
				and not equipped[robotId]
				and #loadout < Constants.MAX_LOADOUT
			then
				equipped[robotId] = true
				table.insert(loadout, robotId)
			end
		end
	end
	if #loadout == 0 then
		loadout = table.clone(defaults.equippedLoadout)
	end

	local stats: any = if TableUtil.isTable(stored.stats) then stored.stats else {}
	local settings: any = if TableUtil.isTable(stored.settings) then stored.settings else {}
	local season: any = if TableUtil.isTable(stored.season) then stored.season else {}
	local quests: any = if TableUtil.isTable(stored.quests) then stored.quests else {}
	local supply: any = if TableUtil.isTable(stored.supply) then stored.supply else {}

	local questProgress: { [string]: number } = {}
	if TableUtil.isTable(quests.progress) then
		for questId, value in quests.progress do
			if type(questId) == "string" and type(value) == "number" then
				questProgress[questId] = math.max(0, math.floor(value))
			end
		end
	end

	return {
		coins = math.max(0, math.floor(numberOr(stored.coins, defaults.coins))),
		gems = math.max(0, math.floor(numberOr(stored.gems, defaults.gems))),
		unlockedRobots = unlocked,
		equippedLoadout = loadout,
		stats = {
			wins = numberOr(stats.wins, 0),
			losses = numberOr(stats.losses, 0),
			wavesSurvived = numberOr(stats.wavesSurvived, 0),
			highestWave = numberOr(stats.highestWave, 0),
			winStreak = math.max(0, numberOr(stats.winStreak, 0)),
			bestWinStreak = math.max(0, numberOr(stats.bestWinStreak, 0)),
		},
		settings = {
			musicVolume = math.clamp(numberOr(settings.musicVolume, defaults.settings.musicVolume), 0, 1),
			sfxVolume = math.clamp(numberOr(settings.sfxVolume, defaults.settings.sfxVolume), 0, 1),
		},
		purchases = stringList(stored.purchases, DATA.PURCHASE_HISTORY),
		season = {
			seasonId = if type(season.seasonId) == "string" then season.seasonId else defaults.season.seasonId,
			xp = math.max(0, math.floor(numberOr(season.xp, 0))),
			premium = season.premium == true,
			claimedFree = numberList(season.claimedFree, 200),
			claimedPremium = numberList(season.claimedPremium, 200),
		},
		quests = {
			day = numberOr(quests.day, 0),
			progress = questProgress,
			claimed = stringList(quests.claimed, 50),
			tried = stringList(quests.tried, 50),
		},
		supply = {
			day = numberOr(supply.day, 0),
			claims = math.max(0, math.floor(numberOr(supply.claims, 0))),
			lastClaimAt = numberOr(supply.lastClaimAt, 0),
		},
		codes = stringList(stored.codes, 200),
		rank = sanitizeRank(stored.rank, defaults.rank),
	}
end

-- Migration n upgrades a record from schema version n to n + 1.
-- Version 0 is a record from before versioning existed: bare PlayerData at the top level.
local MIGRATIONS: { [number]: (any) -> any } = {
	[0] = function(old: any): any
		return { schemaVersion = 1, data = old, lock = nil }
	end,
	-- v2 (Lobby v2): adds purchases, season, quests, supply, codes, rank, and win streak stats.
	-- New fields start from defaults (sanitize fills them); existing progress is kept as is.
	[1] = function(old: any): any
		return { schemaVersion = 2, data = old.data, lock = old.lock }
	end,
}

-- Returns the upgraded record, and true when the record is from a newer schema than this server.
-- Runs inside UpdateAsync transforms, so it must never yield.
local function migrate(raw: any): (StoredRecord, boolean)
	if not TableUtil.isTable(raw) then
		return { schemaVersion = DATA.SCHEMA_VERSION, data = defaultData(), lock = nil }, false
	end

	local record = raw
	local version = if type(record.schemaVersion) == "number" then record.schemaVersion else 0
	if version > DATA.SCHEMA_VERSION then
		return record, true
	end
	while version < DATA.SCHEMA_VERSION do
		local step = MIGRATIONS[version]
		if step == nil then
			warn(`[DataService] No migration from schema {version}; filling missing fields from defaults.`)
			record = { schemaVersion = DATA.SCHEMA_VERSION, data = record.data, lock = record.lock }
			break
		end
		record = step(record)
		version = record.schemaVersion
	end

	local lock: SessionLock? = nil
	local storedLock: any = record.lock
	if TableUtil.isTable(storedLock) and type(storedLock.jobId) == "string" and type(storedLock.time) == "number" then
		lock = { jobId = storedLock.jobId :: string, time = storedLock.time :: number }
	end
	return {
		schemaVersion = DATA.SCHEMA_VERSION,
		data = sanitize(record.data),
		lock = lock,
	}, false
end

local function keyFor(player: Player): string
	return DATA.KEY_PREFIX .. tostring(player.UserId)
end

local function backoff(attempt: number)
	task.wait(DATA.RETRY_BASE_DELAY * 2 ^ (attempt - 1))
end

local function loadData(player: Player): (Types.PlayerData?, LoadFailure?)
	if memoryMode then
		return defaultData(), nil
	end
	local activeStore = store
	if activeStore == nil then
		return nil, "unavailable"
	end

	local key = keyFor(player)
	if sandboxServer then
		-- Read-only: the Test Realm never takes the session lock, so returning to the main game is
		-- never blocked by this server, and nothing here can be saved anyway.
		for attempt = 1, DATA.MAX_ATTEMPTS do
			local ok, result = pcall(function(): any
				return activeStore:GetAsync(key)
			end)
			if ok then
				local record, newer = migrate(result)
				if newer then
					return nil, "newer"
				end
				return record.data, nil
			end
			warn(`[DataService] Sandbox read {attempt} for {player.Name} failed: {result}`)
			if attempt < DATA.MAX_ATTEMPTS then
				backoff(attempt)
			end
		end
		return nil, "error"
	end
	local lastFailure: LoadFailure = "error"
	for attempt = 1, DATA.MAX_ATTEMPTS do
		local outcome: LoadFailure | "ok" = "error"
		local loaded: Types.PlayerData? = nil
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any): any
				local record, newer = migrate(old)
				if newer then
					outcome = "newer"
					return nil
				end
				local lock = record.lock
				if lock ~= nil and lock.jobId ~= game.JobId and os.time() - lock.time < DATA.SESSION_LOCK_TIMEOUT then
					outcome = "locked"
					return nil
				end
				record.lock = { jobId = game.JobId, time = os.time() }
				loaded = record.data
				outcome = "ok"
				return record
			end)
		end)

		if ok and outcome == "ok" and loaded ~= nil then
			return loaded, nil
		end
		if not ok then
			warn(`[DataService] Load attempt {attempt} for {player.Name} failed: {err}`)
			lastFailure = "error"
		elseif outcome ~= "ok" then
			lastFailure = outcome
		end
		if lastFailure == "newer" or player.Parent == nil then
			break
		end
		if attempt < DATA.MAX_ATTEMPTS then
			backoff(attempt)
		end
	end
	return nil, lastFailure
end

-- Returns true when the data was written. Never overwrites a record another server now owns.
local function writeProfile(player: Player, profile: Profile, release: boolean): boolean
	if memoryMode then
		return true
	end
	if sandboxServer then
		return false
	end
	local activeStore = store
	if activeStore == nil then
		return false
	end

	local key = keyFor(player)
	local snapshot = TableUtil.deepCopy(profile.data)
	for attempt = 1, DATA.MAX_ATTEMPTS do
		local refused = false
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: any): any
				local record, newer = migrate(old)
				local lock = record.lock
				if newer or (lock ~= nil and lock.jobId ~= game.JobId) then
					refused = true
					return nil
				end
				record.data = snapshot
				record.lock = if release then nil else { jobId = game.JobId, time = os.time() }
				return record
			end)
		end)
		if ok then
			if refused then
				warn(`[DataService] {player.Name}'s data is owned by another server; this server will stop saving it.`)
				profile.released = true
				return false
			end
			return true
		end
		warn(`[DataService] Save attempt {attempt} for {player.Name} failed: {err}`)
		if attempt < DATA.MAX_ATTEMPTS then
			backoff(attempt)
		end
	end
	return false
end

local function saveProfile(player: Player, profile: Profile, release: boolean): boolean
	-- Saves for one profile run one at a time so a releasing save can never land before an
	-- in-flight autosave (which would re-acquire the lock with older data).
	local waited = 0
	while profile.saving and waited < DATA.SAVE_WAIT_TIMEOUT do
		waited += task.wait()
	end
	if profile.released then
		return false
	end

	activeSaves += 1
	profile.saving = true
	local written = writeProfile(player, profile, release)
	profile.saving = false
	if release then
		profile.released = true
	end
	activeSaves -= 1
	return written
end

function DataService.pushProfile(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		Remotes.ProfileUpdated:fireClient(player, TableUtil.deepCopy(profile.data))
	end
end

-- Live data table for reads. Mutate only through DataService.update so the client stays in sync.
function DataService.getData(player: Player): Types.PlayerData?
	local profile = profiles[player]
	return if profile ~= nil then profile.data else nil
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.isSandboxed(player: Player): boolean
	return sandboxServer or sandboxPlayers[player] == true
end

function DataService.isSandboxServer(): boolean
	return sandboxServer
end

-- Called by Bootstrap before start() on a Test Realm server.
function DataService.setSandboxServer(enabled: boolean)
	sandboxServer = enabled
end

-- Blocks (or unblocks) every write for one player while they are in a local Test Realm.
function DataService.setSandbox(player: Player, enabled: boolean)
	if enabled then
		sandboxPlayers[player] = true
	else
		sandboxPlayers[player] = nil
	end
end

-- Writes the profile now (keeping the lock). Used where a grant must be durable before the
-- caller answers, e.g. ProcessReceipt. Returns true once the data store accepted it.
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if profile == nil or profile.released or DataService.isSandboxed(player) then
		return false
	end
	return saveProfile(player, profile, false)
end

-- Applies a change to a loaded profile and pushes the result to the client.
-- Always rejected while the player is sandboxed (Test Realm).
function DataService.update(player: Player, mutator: (data: Types.PlayerData) -> ()): boolean
	local profile = profiles[player]
	if profile == nil or profile.released or DataService.isSandboxed(player) then
		return false
	end
	mutator(profile.data)
	DataService.pushProfile(player)
	return true
end

local function onPlayerAdded(player: Player)
	if profiles[player] ~= nil or loading[player] then
		return
	end
	loading[player] = true
	local data, failure = loadData(player)
	loading[player] = nil

	if data == nil then
		if player.Parent ~= nil then
			player:Kick(KICK_MESSAGES[failure or "error"])
		end
		return
	end

	local profile: Profile = { data = data, saving = false, released = false }
	if player.Parent == nil then
		-- The player left while we were loading: hand the lock straight back.
		saveProfile(player, profile, true)
		return
	end
	profiles[player] = profile
	DataService.pushProfile(player)
	DataService.profileLoaded:fire(player)
end

local function onPlayerRemoving(player: Player)
	sandboxPlayers[player] = nil
	local profile = profiles[player]
	if profile == nil then
		return
	end
	-- Last chance for other services to record what leaving means (e.g. a ranked abandon).
	DataService.beforeRelease:fire(player)
	profiles[player] = nil
	saveProfile(player, profile, true)
end

local function autosaveLoop()
	while true do
		task.wait(DATA.AUTOSAVE_INTERVAL)
		-- Snapshot the list first: saves yield, and players may join or leave meanwhile.
		local batch: { { player: Player, profile: Profile } } = {}
		for player, profile in profiles do
			table.insert(batch, { player = player, profile = profile })
		end
		for _, entry in batch do
			if profiles[entry.player] == entry.profile then
				saveProfile(entry.player, entry.profile, false)
			end
		end
	end
end

local function onClose()
	if memoryMode then
		return
	end
	for player, profile in profiles do
		-- A shutdown is not the player's fault: services must not treat this as an abandon,
		-- so beforeRelease is not fired here.
		profiles[player] = nil
		task.spawn(saveProfile, player, profile, true)
	end
	local started = os.clock()
	while activeSaves > 0 and os.clock() - started < DATA.BIND_TO_CLOSE_TIMEOUT do
		task.wait()
	end
end

function DataService.init()
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(DATA.STORE_NAME)
	end)
	if ok then
		store = result
	end

	if RunService:IsStudio() then
		local activeStore = store
		local probeOk = false
		if activeStore ~= nil then
			probeOk = pcall(function()
				activeStore:GetAsync("__studio_probe")
			end)
		end
		if not probeOk then
			memoryMode = true
			warn(
				"[DataService] DataStores are unavailable in Studio (publish the place and enable "
					.. "'Studio Access to API Services' to test saving). Using in-memory data; progress will not persist."
			)
		end
	elseif not ok then
		warn(`[DataService] DataStoreService is unavailable: {result}. Players will be asked to rejoin.`)
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Remotes.RequestSync:connect(function(player: Player)
		DataService.pushProfile(player)
	end)

	task.spawn(autosaveLoop)
	game:BindToClose(onClose)
end

return DataService

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

local KICK_MESSAGES: { [LoadFailure]: string } = {
	locked = "Your Cyber Swarm data is still open on another server. Please rejoin in a minute.",
	newer = "This server is running an older version of Cyber Swarm. Please rejoin to reach a newer server.",
	error = "We couldn't load your Cyber Swarm data right now. Your progress is safe - please rejoin shortly.",
	unavailable = "Cyber Swarm data storage is unavailable right now. Your progress is safe - please rejoin shortly.",
}

local DataService = {}

-- Fires once a player's data is loaded and safe to read.
DataService.profileLoaded = Signal.new() :: Signal.Signal<Player>

local store: DataStore? = nil
local memoryMode = false
local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local activeSaves = 0

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
		},
		settings = {
			musicVolume = defaults.musicVolume,
			sfxVolume = defaults.sfxVolume,
		},
	}
end

local function numberOr(value: any, fallback: number): number
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

-- Rebuilds a well-formed PlayerData from anything stored, dropping ids that no longer exist so a
-- removed robot in config can never break a player's loadout.
local function sanitize(raw: any): Types.PlayerData
	local defaults = defaultData()
	if type(raw) ~= "table" then
		return defaults
	end
	local stored = TableUtil.reconcile(raw, defaults)

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
	if type(stored.unlockedRobots) == "table" then
		for _, robotId in stored.unlockedRobots do
			unlock(robotId)
		end
	end

	local loadout: { string } = {}
	local equipped: { [string]: boolean } = {}
	if type(stored.equippedLoadout) == "table" then
		for _, robotId in stored.equippedLoadout do
			if type(robotId) == "string" and owned[robotId] and not equipped[robotId] and #loadout < Constants.MAX_LOADOUT then
				equipped[robotId] = true
				table.insert(loadout, robotId)
			end
		end
	end
	if #loadout == 0 then
		loadout = table.clone(defaults.equippedLoadout)
	end

	local stats = if type(stored.stats) == "table" then stored.stats else {}
	local settings = if type(stored.settings) == "table" then stored.settings else {}

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
		},
		settings = {
			musicVolume = math.clamp(numberOr(settings.musicVolume, defaults.settings.musicVolume), 0, 1),
			sfxVolume = math.clamp(numberOr(settings.sfxVolume, defaults.settings.sfxVolume), 0, 1),
		},
	}
end

-- Migration n upgrades a record from schema version n to n + 1.
-- Version 0 is a record from before versioning existed: bare PlayerData at the top level.
local MIGRATIONS: { [number]: (any) -> any } = {
	[0] = function(old: any): any
		return { schemaVersion = 1, data = old, lock = nil }
	end,
}

-- Returns the upgraded record, and true when the record is from a newer schema than this server.
-- Runs inside UpdateAsync transforms, so it must never yield.
local function migrate(raw: any): (StoredRecord, boolean)
	if type(raw) ~= "table" then
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
	if type(record.lock) == "table" and type(record.lock.jobId) == "string" and type(record.lock.time) == "number" then
		lock = { jobId = record.lock.jobId, time = record.lock.time }
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

local function saveProfile(player: Player, profile: Profile, release: boolean)
	-- Saves for one profile run one at a time so a releasing save can never land before an
	-- in-flight autosave (which would re-acquire the lock with older data).
	local waited = 0
	while profile.saving and waited < DATA.SAVE_WAIT_TIMEOUT do
		waited += task.wait()
	end
	if profile.released then
		return
	end

	activeSaves += 1
	profile.saving = true
	writeProfile(player, profile, release)
	profile.saving = false
	if release then
		profile.released = true
	end
	activeSaves -= 1
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

-- Applies a change to a loaded profile and pushes the result to the client.
function DataService.update(player: Player, mutator: (data: Types.PlayerData) -> ()): boolean
	local profile = profiles[player]
	if profile == nil or profile.released then
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
	local profile = profiles[player]
	if profile == nil then
		return
	end
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

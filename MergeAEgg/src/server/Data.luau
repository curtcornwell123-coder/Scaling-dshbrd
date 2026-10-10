-- Merge A Egg: player saving. Session-locked DataStore profiles with retries,
-- autosave, safe shutdown, and global leaderboards (OrderedDataStores).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Data = {}

local ctx
local Config

local LOCK_TIMEOUT = 30 * 60 -- a lock older than this is treated as abandoned
local LOAD_ATTEMPTS = 6
local RETRY_DELAY = 4

Data.TEMPLATE = {
	version = 1,
	money = 0,
	speed = 0,
	steals = 0,
	rebirths = 0,
	penLevel = 1,
	equipSlots = Config and Config.BaseEquipSlots or 1,
	maxBiomeKey = "Forest", -- furthest biome reached (a key, so new biomes never shift it)
	nextId = 1,
	eggs = {}, -- [id] = { id, biome, rarity, weight, big, boss, variant }
	nests = {}, -- [slot string] = egg + growEnd
	fuse = {}, -- array of eggs waiting in the Fuse Machine
	pets = {}, -- [id] = { id, name, biome, rarity, weight }
	equipped = {}, -- array of pet ids
	followers = {}, -- array of pet ids that follow you and fight bosses
	followSlots = 1,
	index = {}, -- [pet name] = true
	trails = {}, -- [trail key] = true
	equippedTrail = "",
	treadmills = { Wooden = true },
	equippedTreadmill = "Wooden",
	lastOnline = 0,
	daily = { day = 0, streak = 0 },
	playtime = { day = 0, seconds = 0, claimed = {} },
	vipEggDay = 0,
	bossEggDay = 0,
	leaveRewardDay = 0,
	groupRewardClaimed = false,
	giftedPasses = {}, -- passes received as gifts
	purchases = {}, -- recent receipt ids, newest last
	stats = { hatched = 0, fused = 0, timePlayed = 0 },
}

local store: DataStore? = nil
local boards: { [string]: OrderedDataStore } = {}
local profiles: { [Player]: any } = {}
local saving: { [Player]: boolean } = {}
local releasing: { [Player]: boolean } = {}
local enabled = false
local jobId = if RunService:IsStudio() then "studio-" .. HttpService:GenerateGUID(false) else game.JobId

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Fills any keys missing from saved data with template defaults.
local function reconcile(target, template)
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil and #value == 0 then
			reconcile(target[key], value)
		end
	end
end

local function retry(label: string, fn: () -> any): (boolean, any)
	local ok, result
	for attempt = 1, 3 do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[Data] {label} failed (attempt {attempt}): {result}`)
		task.wait(attempt * 2)
	end
	return false, result
end

function Data.init(context)
	ctx = context
	Config = ctx.Config
	Data.TEMPLATE.equipSlots = Config.BaseEquipSlots
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	-- Probe once so an unpublished place or Studio without API access runs without saving
	-- instead of retrying every load.
	if ok then
		local probeOk, probeErr = pcall(function()
			return result:GetAsync("__probe")
		end)
		if not probeOk then
			ok = false
			result = probeErr
		end
	end
	if ok then
		store = result
		enabled = true
		for _, name in { "MoneyPerSec", "Steals", "Speed" } do
			local boardOk, board = pcall(function()
				return DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_" .. name)
			end)
			if boardOk then
				boards[name] = board
			end
		end
	else
		warn("[Data] DataStores unavailable (enable Studio API access to test saving):", result)
	end
end

function Data.isEnabled(): boolean
	return enabled
end

function Data.get(player: Player)
	return profiles[player]
end

function Data.today(): number
	return math.floor(os.time() / 86400)
end

function Data.newId(data): string
	local id = tostring(data.nextId)
	data.nextId += 1
	return id
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

-- Loads and locks a profile. Returns nil (and kicks) if it could not be loaded safely.
function Data.load(player: Player)
	if not enabled or not store then
		local data = deepCopy(Data.TEMPLATE)
		data.lastOnline = os.time()
		profiles[player] = data
		return data
	end

	local loaded = nil
	for attempt = 1, LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(keyFor(player), function(saved)
				saved = saved or deepCopy(Data.TEMPLATE)
				local lock = saved.lock
				local locked = lock and lock.job ~= jobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT
				-- After a few tries we take over a stale session from a crashed server.
				if locked and attempt < LOAD_ATTEMPTS - 1 then
					return nil
				end
				saved.lock = { job = jobId, time = os.time() }
				return saved
			end)
		end)
		if ok and result and result.lock and result.lock.job == jobId then
			loaded = result
			break
		end
		if not ok then
			warn(`[Data] Load failed for {player.Name}: {result}`)
		end
		if not player.Parent then
			return nil
		end
		task.wait(RETRY_DELAY)
	end

	if not loaded then
		player:Kick("Your data couldn't load safely. Please rejoin in a moment!")
		return nil
	end
	if not player.Parent then
		-- Left while loading: release the lock we just took.
		task.spawn(function()
			pcall(function()
				(store :: DataStore):UpdateAsync(keyFor(player), function(saved)
					if saved and saved.lock and saved.lock.job == jobId then
						saved.lock = nil
					end
					return saved
				end)
			end)
		end)
		return nil
	end

	reconcile(loaded, Data.TEMPLATE)
	profiles[player] = loaded
	return loaded
end

-- Writes one profile. Waits for any write already in flight so saves never land out of order.
local function write(player: Player, data, release: boolean): boolean
	while saving[player] do
		task.wait()
	end
	saving[player] = true
	data.lastOnline = os.time()
	local snapshot = deepCopy(data)
	local ok = retry("Save " .. player.Name, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(saved)
			if saved and saved.lock and saved.lock.job ~= jobId then
				-- Another server owns this profile now; never overwrite it.
				return nil
			end
			snapshot.lock = if release then nil else { job = jobId, time = os.time() }
			return snapshot
		end)
	end)
	if not ok then
		warn(`[Data] Could not save {player.Name}`)
	end
	saving[player] = nil
	return ok
end

-- Returns true once the profile is safely stored (or saving is off).
function Data.save(player: Player): boolean
	local data = profiles[player]
	if not enabled or not store or not data or releasing[player] then
		return true
	end
	return write(player, data, false)
end

-- Final save that also unlocks the profile for the next server.
function Data.release(player: Player)
	local data = profiles[player]
	if not data or releasing[player] then
		return
	end
	releasing[player] = true
	if enabled and store then
		write(player, data, true)
	end
	profiles[player] = nil
	releasing[player] = nil
end

function Data.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				if profiles[player] then
					task.spawn(Data.save, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				task.spawn(Data.release, player)
			end
		end
		-- Also waits for releases that started when the last players left.
		local started = os.clock()
		while next(profiles) ~= nil and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

---------------------------------------------------------------------------
-- Global leaderboards
---------------------------------------------------------------------------

-- Huge values (speed can pass 1e15) are stored log-encoded so they fit an integer.
local function encode(value: number): number
	if value <= 0 then
		return 0
	end
	return math.floor(math.log10(value + 1) * 1e6)
end

local function decode(stored: number): number
	return 10 ^ (stored / 1e6) - 1
end

function Data.submitLeaderboards(player: Player, values: { [string]: number })
	for name, value in values do
		local board = boards[name]
		if board then
			pcall(function()
				board:SetAsync(tostring(player.UserId), encode(value))
			end)
		end
	end
end

-- Returns the top entries: { { userId = number, value = number } }.
function Data.fetchTop(name: string, count: number)
	local board = boards[name]
	if not board then
		return {}
	end
	local ok, pages = pcall(function()
		return board:GetSortedAsync(false, count)
	end)
	if not ok then
		return {}
	end
	local entries = {}
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		table.insert(entries, { userId = tonumber(entry.key), value = decode(entry.value) })
	end
	return entries
end

return Data

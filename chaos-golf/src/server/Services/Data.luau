--!strict
-- Player profiles: load/save with a soft session lock, autosave, receipts,
-- leaderboard deltas, and the client-facing profile snapshot.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Net = require(Shared:WaitForChild("Net"))
local Ranks = require(Shared:WaitForChild("Ranks"))

local Data = {}

export type Profile = {
	Version: number,
	Coins: number,
	Tokens: { [string]: number },
	Owned: { [string]: { [string]: boolean } }, -- category -> item id -> true
	Equipped: { [string]: string }, -- category -> item id (Skins / Trails / Knockouts / Arrows)
	Keys: { [string]: number }, -- crate id -> unopened crate keys
	Login: { Day: number, LastClaim: number }, -- 14-day calendar (next day to claim)
	Celebration: string,
	Upgrades: { [string]: number },
	Stats: { [string]: number },
	Ranked: { MMR: number, Wins: number, Losses: number, Draws: number, Played: number, Peak: number },
	Creator: string?,
	TutorialDone: boolean,
	DirectoryDone: boolean,
	Pity: { [string]: number },
	Receipts: { string },
	Lock: { Job: string, Time: number }?,
}

export type Session = {
	Player: Player,
	Profile: Profile,
	Loaded: boolean,
	Dirty: boolean,
	PublicDirty: boolean,
	LBDelta: { [string]: number }, -- Wins / Coins / Sabotages since the last leaderboard flush
	Passes: { [string]: boolean },
	Leaderstats: Folder?,
	Offline: boolean, -- Studio without API access: play on a temporary profile, never save
}

local LOCK_TIMEOUT = 150
local AUTOSAVE = 120

local store: DataStore? = nil
local publicStore: DataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DataStoreName)
		publicStore = DataStoreService:GetDataStore(Config.DataStoreName .. "_Public")
	end)
	if not ok then
		warn("[ChaosGolf] DataStores unavailable; progress will not save:", err)
	end
end

local sessions: { [Player]: Session } = {}
local loadedEvent = Instance.new("BindableEvent")
local releaseHooks: { (Session) -> () } = {}

Data.Loaded = loadedEvent.Event -- (player, session)

local function defaultProfile(): Profile
	return {
		Version = 1,
		Coins = Config.StartingCoins,
		Tokens = { Target = 0, Drive = 0, Hazard = 0 },
		Owned = {
			Skins = { [Cosmetics.Defaults.Skins] = true },
			Trails = { [Cosmetics.Defaults.Trails] = true },
			Knockouts = { [Cosmetics.Defaults.Knockouts] = true },
			Arrows = { [Cosmetics.Defaults.Arrows] = true },
		},
		Equipped = table.clone(Cosmetics.Defaults),
		Keys = { Skins = 0, Trails = 0, Knockouts = 0, Arrows = 0 },
		Login = { Day = 1, LastClaim = 0 },
		Celebration = "Default",
		Upgrades = { Power = 0, Control = 0, Bounce = 0 },
		Stats = { Wins = 0, Matches = 0, Sabotages = 0, Knockouts = 0, CoinsEarned = 0, HoleInOnes = 0, Holes = 0 },
		Ranked = { MMR = Config.Ranked.StartMMR, Wins = 0, Losses = 0, Draws = 0, Played = 0, Peak = Config.Ranked.StartMMR },
		Creator = nil,
		TutorialDone = false,
		DirectoryDone = false,
		Pity = {},
		Receipts = {},
		Lock = nil,
	}
end

-- Fill in fields added after a profile was first saved.
local function reconcile(saved: any): Profile
	local base = defaultProfile() :: any
	if type(saved) ~= "table" then
		return base
	end
	for k, v in base do
		if saved[k] == nil then
			saved[k] = v
		elseif type(v) == "table" and type(saved[k]) == "table" and k ~= "Receipts" then
			for k2, v2 in v do
				if saved[k][k2] == nil then
					saved[k][k2] = v2
				end
			end
		end
	end
	for _, category in Cosmetics.Categories do
		saved.Owned[category] = saved.Owned[category] or {}
		saved.Owned[category][Cosmetics.Defaults[category]] = true
		local id = saved.Equipped[category]
		if not Cosmetics.get(category, id) or not saved.Owned[category][id] then
			saved.Equipped[category] = Cosmetics.Defaults[category]
		end
	end
	return saved :: Profile
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

-- Snapshot sent to the owning client (no receipts / lock).
function Data.snapshot(session: Session): { [string]: any }
	local p = session.Profile
	return {
		Coins = p.Coins,
		Tokens = p.Tokens,
		Owned = p.Owned,
		Equipped = p.Equipped,
		Keys = p.Keys,
		Login = p.Login,
		Celebration = p.Celebration,
		Upgrades = p.Upgrades,
		Stats = p.Stats,
		Ranked = p.Ranked,
		Creator = p.Creator,
		TutorialDone = p.TutorialDone,
		DirectoryDone = p.DirectoryDone,
		Pity = p.Pity,
		Passes = session.Passes,
	}
end

function Data.push(player: Player)
	local session = sessions[player]
	if session and session.Loaded then
		player:SetAttribute("Celebration", session.Profile.Celebration)
		Net.event("Profile"):FireClient(player, Data.snapshot(session))
	end
end

function Data.get(player: Player): Session?
	local s = sessions[player]
	if s and s.Loaded then
		return s
	end
	return nil
end

function Data.profile(player: Player): Profile?
	local s = Data.get(player)
	return s and s.Profile
end

-- Yields until the player's profile is loaded (or they leave).
function Data.wait(player: Player): Session?
	while player.Parent == Players do
		local s = Data.get(player)
		if s then
			return s
		end
		task.wait(0.1)
	end
	return nil
end

function Data.onRelease(hook: (Session) -> ())
	table.insert(releaseHooks, hook)
end

function Data.markDirty(player: Player)
	local s = sessions[player]
	if s then
		s.Dirty = true
	end
end

local function updateLeaderstats(session: Session)
	local ls = session.Leaderstats
	if not ls then
		return
	end
	local rank = ls:FindFirstChild("Rank") :: StringValue?
	local wins = ls:FindFirstChild("Wins") :: IntValue?
	if rank then
		rank.Value = Ranks.fromMMR(session.Profile.Ranked.MMR).Label
	end
	if wins then
		wins.Value = session.Profile.Stats.Wins
	end
end

function Data.refreshLeaderstats(player: Player)
	local s = sessions[player]
	if s then
		updateLeaderstats(s)
	end
end

-- Coins ------------------------------------------------------------------

-- Adds raw coins (no multipliers; see Economy for boosted rewards).
function Data.addCoins(player: Player, amount: number, reason: string?)
	local s = Data.get(player)
	if not s or amount == 0 then
		return
	end
	amount = math.floor(amount)
	s.Profile.Coins += amount
	if amount > 0 then
		s.Profile.Stats.CoinsEarned += amount
		s.LBDelta.Coins = (s.LBDelta.Coins or 0) + amount
	end
	s.Dirty = true
	Net.event("Coins"):FireClient(player, s.Profile.Coins, amount, reason)
	Data.push(player)
end

-- Spends coins if affordable; returns success.
function Data.spend(player: Player, amount: number): boolean
	local s = Data.get(player)
	if not s or amount < 0 or s.Profile.Coins < amount then
		return false
	end
	s.Profile.Coins -= amount
	s.Dirty = true
	Net.event("Coins"):FireClient(player, s.Profile.Coins, -amount, nil)
	return true
end

function Data.addTokens(player: Player, minigame: string, amount: number)
	local s = Data.get(player)
	if not s then
		return
	end
	s.Profile.Tokens[minigame] = math.max(0, (s.Profile.Tokens[minigame] or 0) + amount)
	s.Dirty = true
	Data.push(player)
end

function Data.addStat(player: Player, stat: string, amount: number)
	local s = Data.get(player)
	if not s then
		return
	end
	s.Profile.Stats[stat] = (s.Profile.Stats[stat] or 0) + amount
	if stat == "Wins" or stat == "Sabotages" then
		s.LBDelta[stat] = (s.LBDelta[stat] or 0) + amount
	end
	s.Dirty = true
	updateLeaderstats(s)
end

-- Cosmetics --------------------------------------------------------------

function Data.owns(player: Player, category: string, id: string): boolean
	local s = Data.get(player)
	return s ~= nil and s.Profile.Owned[category] ~= nil and s.Profile.Owned[category][id] == true
end

-- Grants a cosmetic; returns true if it was new.
function Data.grant(player: Player, category: string, id: string): boolean
	local s = Data.get(player)
	if not s or not Cosmetics.get(category, id) then
		return false
	end
	local owned = s.Profile.Owned[category]
	if owned[id] then
		return false
	end
	owned[id] = true
	s.Dirty = true
	Data.push(player)
	return true
end

function Data.grantSkin(player: Player, skinId: string): boolean
	return Data.grant(player, "Skins", skinId)
end

function Data.equip(player: Player, category: string, id: string): boolean
	local s = Data.get(player)
	if not s or not Data.owns(player, category, id) then
		return false
	end
	s.Profile.Equipped[category] = id
	s.Dirty = true
	if category == "Skins" or category == "Trails" then
		s.PublicDirty = true
	end
	Data.push(player)
	return true
end

-- Equipped cosmetics as a flat table for ball spawning.
function Data.loadout(player: Player): { Skin: string, Trail: string, Knockout: string, Arrow: string }
	local p = Data.profile(player)
	local e = if p then p.Equipped else Cosmetics.Defaults
	return {
		Skin = e.Skins or Cosmetics.Defaults.Skins,
		Trail = e.Trails or Cosmetics.Defaults.Trails,
		Knockout = e.Knockouts or Cosmetics.Defaults.Knockouts,
		Arrow = e.Arrows or Cosmetics.Defaults.Arrows,
	}
end

function Data.addKeys(player: Player, crateId: string, amount: number)
	local s = Data.get(player)
	if not s then
		return
	end
	s.Profile.Keys[crateId] = math.max(0, (s.Profile.Keys[crateId] or 0) + amount)
	s.Dirty = true
	Data.push(player)
end

-- Receipts (ProcessReceipt idempotency) ----------------------------------------

function Data.hasReceipt(player: Player, purchaseId: string): boolean
	local s = Data.get(player)
	return s ~= nil and table.find(s.Profile.Receipts, purchaseId) ~= nil
end

function Data.addReceipt(player: Player, purchaseId: string)
	local s = Data.get(player)
	if not s then
		return
	end
	table.insert(s.Profile.Receipts, purchaseId)
	while #s.Profile.Receipts > 60 do
		table.remove(s.Profile.Receipts, 1)
	end
	s.Dirty = true
end

-- Persistence ------------------------------------------------------------

local function retry<T>(attempts: number, fn: () -> T): (boolean, T | string)
	local lastErr: any = nil
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(math.min(2 ^ i, 8))
	end
	return false, tostring(lastErr)
end

local function save(session: Session, release: boolean): boolean
	local ds = store
	if not ds or not session.Loaded or session.Offline then
		return false
	end
	local profile = session.Profile
	profile.Lock = if release then nil else { Job = game.JobId, Time = os.time() }
	local ok, err = retry(3, function()
		return ds:UpdateAsync(key(session.Player), function(old: any)
			-- Never overwrite a profile another server has locked since we loaded.
			if old and old.Lock and old.Lock.Job ~= game.JobId and os.time() - old.Lock.Time < LOCK_TIMEOUT then
				return nil
			end
			return profile
		end)
	end)
	if not ok then
		warn("[ChaosGolf] save failed for", session.Player.Name, err)
		return false
	end
	session.Dirty = false

	if session.PublicDirty and publicStore then
		session.PublicDirty = false
		local pub = { Skin = profile.Equipped.Skins, Trail = profile.Equipped.Trails, MMR = profile.Ranked.MMR }
		local ps = publicStore :: DataStore
		task.spawn(pcall, function()
			ps:SetAsync(tostring(session.Player.UserId), pub)
		end)
	end
	return true
end

-- Saves immediately. Returns true when the profile is safely stored (or the
-- session is an offline Studio profile that never saves).
function Data.saveNow(player: Player): boolean
	local s = sessions[player]
	if not s then
		return false
	end
	if s.Offline or not store then
		return true
	end
	return save(s, false)
end

-- Public profile of any user (for leaderboard podiums).
function Data.getPublic(userId: number): { Skin: string?, Trail: string?, MMR: number? }?
	for _, s in sessions do
		if s.Player.UserId == userId and s.Loaded then
			return { Skin = s.Profile.Equipped.Skins, Trail = s.Profile.Equipped.Trails, MMR = s.Profile.Ranked.MMR }
		end
	end
	local ps = publicStore
	if not ps then
		return nil
	end
	local ok, result = pcall(function()
		return ps:GetAsync(tostring(userId))
	end)
	if ok and type(result) == "table" then
		return result :: any
	end
	return nil
end

local function load(player: Player)
	local session: Session = {
		Player = player,
		Profile = defaultProfile(),
		Loaded = false,
		Dirty = false,
		PublicDirty = true,
		LBDelta = {},
		Passes = {},
		Leaderstats = nil,
		Offline = false,
	}
	sessions[player] = session

	local ds = store
	if ds then
		local profile: Profile? = nil
		for attempt = 1, 6 do
			local locked = false
			local ok, result = pcall(function()
				return ds:UpdateAsync(key(player), function(old: any)
					if old and old.Lock and old.Lock.Job ~= game.JobId and os.time() - old.Lock.Time < LOCK_TIMEOUT and attempt < 6 then
						locked = true
						return nil
					end
					local p = reconcile(old)
					p.Lock = { Job = game.JobId, Time = os.time() }
					return p
				end)
			end)
			if ok and not locked and result then
				profile = reconcile(result)
				break
			end
			if not ok then
				warn("[ChaosGolf] load attempt", attempt, "failed for", player.Name, result)
				if RunService:IsStudio() then
					warn("[ChaosGolf] Studio: enable Game Settings > Security > Studio Access to API Services to test saving. Using a temporary profile.")
					session.Offline = true
					break
				end
			end
			if player.Parent ~= Players then
				return
			end
			task.wait(if locked then 5 else 2)
		end
		if session.Offline then
			profile = defaultProfile()
		end
		if not profile then
			-- Never play on a blank profile that could overwrite real progress.
			player:Kick("Couldn't load your Chaos Golf data. Please rejoin in a minute.")
			sessions[player] = nil
			return
		end
		session.Profile = profile
	end
	if player.Parent ~= Players then
		sessions[player] = nil
		return
	end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = ls
	ls.Parent = player
	session.Leaderstats = ls

	session.Loaded = true
	updateLeaderstats(session)
	Data.push(player)
	Net.event("Coins"):FireClient(player, session.Profile.Coins, 0, nil)
	loadedEvent:Fire(player, session)
end

local function release(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	for _, hook in releaseHooks do
		local ok, err = pcall(function()
			hook(s)
		end)
		if not ok then
			warn("[ChaosGolf] release hook error:", err)
		end
	end
	save(s, true)
	sessions[player] = nil
end

function Data.sessions(): { [Player]: Session }
	return sessions
end

function Data.start()
	Net.func("GetProfile").OnServerInvoke = function(player: Player)
		local s = Data.get(player)
		return s and Data.snapshot(s)
	end

	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(release)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for _, s in sessions do
				if s.Loaded then
					task.spawn(save, s, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Unique id for logs.
function Data.newId(): string
	return HttpService:GenerateGUID(false)
end

return Data

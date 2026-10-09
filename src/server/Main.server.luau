--!strict
-- Brainrot Heist server: saving, bases, conveyor, buying, stealing, locks,
-- slapping, rebirths and Robux purchases. The server decides everything, so
-- exploiters can't give themselves cash or brainrots.

local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local BrainrotModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BrainrotModel"))
local LimitedStock = require(script.Parent:WaitForChild("LimitedStock"))
local Founders = require(script.Parent:WaitForChild("Founders"))

-- Remotes ------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"

local function makeRemote(className: string, name: string): any
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local GetData: RemoteFunction = makeRemote("RemoteFunction", "GetData")
local DataUpdated: RemoteEvent = makeRemote("RemoteEvent", "DataUpdated")
local Notify: RemoteEvent = makeRemote("RemoteEvent", "Notify")
local Announce: RemoteEvent = makeRemote("RemoteEvent", "Announce")
local RequestRebirth: RemoteEvent = makeRemote("RemoteEvent", "RequestRebirth")
local AdminAction: RemoteEvent = makeRemote("RemoteEvent", "AdminAction")
local BuyLimited: RemoteFunction = makeRemote("RemoteFunction", "BuyLimited")
local RequestUpgrade: RemoteEvent = makeRemote("RemoteEvent", "RequestUpgrade")
local SetFollowers: RemoteEvent = makeRemote("RemoteEvent", "SetFollowers")
local SkinAction: RemoteEvent = makeRemote("RemoteEvent", "SkinAction")
local ShardPurchase: RemoteEvent = makeRemote("RemoteEvent", "ShardPurchase")
local SellBrainrot: RemoteEvent = makeRemote("RemoteEvent", "SellBrainrot")
local RedeemCode: RemoteFunction = makeRemote("RemoteFunction", "RedeemCode")
local ChangeSetting: RemoteEvent = makeRemote("RemoteEvent", "ChangeSetting")
local HammerPower: RemoteEvent = makeRemote("RemoteEvent", "HammerPower")

remotes.Parent = ReplicatedStorage
ReplicatedStorage:SetAttribute("LuckEndsAt", 0)

-- Types --------------------------------------------------------------------

type SaveData = {
	Cash: number,
	Rebirths: number,
	Brainrots: { string }, -- brainrot ids placed in the base, in slot order
	Vault: { string }, -- brainrots on the vault podiums (kept through rebirths)
	VaultLevel: number, -- Config.VaultLevels index (kept through rebirths)
	Steals: number,
	WallLevel: number,
	Stories: number,
	LockLevel: number,
	Receipts: { string }, -- recent purchase ids, so a purchase is never granted twice
	Unclaimed: { string }, -- paid brainrots waiting for a free slot
	Followers: { string }, -- up to 3 brainrots (encoded) that follow you as minis
	Shards: number,
	Skins: { string }, -- owned wall skin ids
	Skin: string, -- equipped wall skin
	Quests: QuestState,
	CashBoostUntil: number, -- unix time the Shard Shop 2x Cash boost ends
	AbuseGiftWeek: number, -- the week this player last got the admin abuse gift
	InfiniteLock: boolean, -- bought the Infinite Laser Door with Shards
	Codes: { string }, -- codes already redeemed (upper case)
	Discovered: { string }, -- every brainrot id this player has ever had (the Index)
	Settings: PlayerSettings,
}

-- The settings panel (gear button); saved with the player's data.
type PlayerSettings = {
	HideVip: boolean, -- a VIP can hide their crown and VIP tag
	MusicVolume: number, -- 0..1, share of Config.GameMusicVolume
}

type QuestState = {
	Day: number,
	Week: number,
	Daily: { [string]: number }, -- quest id -> progress
	Weekly: { [string]: number },
	DailyDone: { [string]: boolean },
	WeeklyDone: { [string]: boolean },
}

type Slot = {
	Id: string,
	Mutation: string?,
	Serial: number?, -- limited brainrots only
	Model: Model,
	StolenBy: Player?,
}

type Plot = {
	Parts: WorldBuilder.PlotParts,
	Owner: Player?,
	Slots: { [number]: Slot },
	Vault: { [number]: Slot }, -- the vault podiums under the base
	Pending: number, -- cash waiting on the collect pad
	LockedUntil: number,
	CooldownUntil: number,
	DoorOpen: boolean, -- Infinite Laser Door owner opened it with the door button
}

type Session = {
	Data: SaveData,
	Loaded: boolean,
	Plot: Plot?,
	Owns: { [string]: boolean },
	Leaderstats: Folder?,
	LastSlap: number,
	LastHint: number,
	LastCollect: number,
	IsAdmin: boolean, -- full admin panel or mod panel
	FullAdmin: boolean, -- false for mods (Config.AdminUserIds): MOD PANEL only
	IsFounder: boolean,
	FounderId: string, -- "Corny", "Ace", or "" for everyone else
	Roles: { [string]: boolean }, -- Tester / Mod, for the role-only skins
	NoSave: boolean, -- Studio test where loading failed: play, but never save
	LastLimitedTry: number,
	FollowerModels: { Model },
}

type Carry = {
	Thief: Player,
	Plot: Plot,
	SlotIndex: number,
	Started: number,
	MinTime: number,
	Weld: WeldConstraint,
}

local world = WorldBuilder.Build()
do
	-- Tells the loading screen how much map there is to load.
	local root = workspace:FindFirstChild("BrainrotHeist")
	if root then
		root:SetAttribute("PartCount", #root:GetDescendants())
	end
end
local plots: { Plot } = {}
for i, parts in world.Plots do
	plots[i] = {
		Parts = parts,
		Owner = nil,
		Slots = {},
		Vault = {},
		Pending = 0,
		LockedUntil = 0,
		CooldownUntil = 0,
		DoorOpen = false,
	}
end

local sessions: { [Player]: Session } = {}
local carries: { [Player]: Carry } = {}
local rng = Random.new()

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotHeist_v1")
	end)
	if ok then
		store = result
	else
		warn("[BrainrotHeist] DataStore unavailable, progress will not save:", result)
	end
end

local function notify(player: Player, message: string)
	Notify:FireClient(player, message)
end

-- Helpers ------------------------------------------------------------------

local function getRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function maxSlots(session: Session): number
	return Config.BaseSlots
		+ (if session.Owns.VIP then Config.VipSlots else 0)
		+ (session.Data.Stories - 1) * Config.UpperFloorSlots
end

-- Ground floor: 10 slots + 2 VIP. Each bought floor above adds its own slots.
local GROUND_SLOTS = Config.BaseSlots + Config.VipSlots
local function isSlotUnlocked(session: Session, index: number): boolean
	if index <= Config.BaseSlots then
		return true
	elseif index <= GROUND_SLOTS then
		return session.Owns.VIP == true
	end
	local story = 2 + (index - GROUND_SLOTS - 1) // Config.UpperFloorSlots
	return session.Data.Stories >= story
end

-- True while the weekly admin abuse runs, or one an admin started by hand.
local function adminAbuseLive(): boolean
	local now = workspace:GetServerTimeNow()
	local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
	return (manualEnd ~= nil and manualEnd > now) or Config.AdminAbuseStatus(now) == "live"
end

-- Which founder (Corny, Ace) this player is, if any. Only founders can start
-- the founder events.
local function founderOf(player: Player): Config.Founder?
	for _, founder in Config.Founders do
		-- With a UserId set, only that exact account counts (usernames can
		-- change hands); the username is just a fallback until it's filled in.
		local matches = if founder.UserId > 0
			then founder.UserId == player.UserId
			else founder.Username ~= "" and string.lower(founder.Username) == string.lower(player.Name)
		if matches then
			return founder
		end
	end
	return nil
end

-- Whether this player can use the admin panel right now. Corny can lock it
-- for everyone but himself (adminsLocked, set from his panel).
local adminsLockedNow = function(): boolean
	return false
end
local function hasAdminPowers(session: Session): boolean
	return session.IsAdmin and (not adminsLockedNow() or session.FounderId == Config.HeadFounder)
end

local function incomeMultiplier(session: Session): number
	local multiplier = Config.RebirthMultiplier(session.Data.Rebirths)
	if adminAbuseLive() then
		multiplier *= Config.AdminAbuseBoosts.Income
	end
	if session.Owns.DoubleCash then
		multiplier *= 2
	end
	if os.time() < session.Data.CashBoostUntil then
		multiplier *= 2
	end
	return multiplier
end

local function plotIncome(plot: Plot, session: Session): number
	local total = 0
	for _, slots in { plot.Slots, plot.Vault } do
		for _, slot in slots do
			if not slot.StolenBy then
				local brainrot = Config.GetBrainrot(slot.Id)
				if brainrot then
					total += Config.IncomeOf(brainrot, slot.Mutation, session.Data.Rebirths)
				end
			end
		end
	end
	-- Never infinity / NaN, however many rebirths (the pad and cash stay real).
	local income = total * incomeMultiplier(session)
	return if income ~= income then 0 else math.min(income, Config.MaxCash)
end

local function placedCount(plot: Plot): number
	local count = 0
	for _ in plot.Slots do
		count += 1
	end
	return count
end

local function vaultCount(plot: Plot): number
	local count = 0
	for _ in plot.Vault do
		count += 1
	end
	return count
end

local function freeSlot(plot: Plot, session: Session): number?
	for i = 1, #plot.Parts.Pedestals do
		if not plot.Slots[i] and isSlotUnlocked(session, i) then
			return i
		end
	end
	return nil
end

local function isInside(plot: Plot, position: Vector3): boolean
	local p = plot.Parts.CFrame:PointToObjectSpace(position)
	return math.abs(p.X) <= 30 and math.abs(p.Z) <= 30 and p.Y > -5 and p.Y < 150
end

local function fullName(brainrot: Config.Brainrot, mutationId: string?): string
	local label = Config.MutationLabel(mutationId)
	return if label ~= "" then label .. " " .. brainrot.DisplayName else brainrot.DisplayName
end

local function hasMagic(mutationId: string?): boolean
	for _, mutation in Config.SplitMutations(mutationId) do
		if mutation.Id == "Magic" then
			return true
		end
	end
	return false
end

-- Worth telling the whole server about: Legendary+ or a rare mutation.
local function isNotable(brainrot: Config.Brainrot, mutationId: string?): boolean
	local mutation = Config.GetMutation(mutationId)
	return Config.Rarities[brainrot.Rarity].Order >= 4 or (mutation ~= nil and mutation.Chance <= 0.6)
end

-- Tonight's night mutation (Corny's event), if it's night.
local function nightBoost(): { Id: string, Multiplier: number }?
	local id = ReplicatedStorage:GetAttribute("NightMutation") :: string?
	local multiplier = ReplicatedStorage:GetAttribute("NightBoost") :: number?
	if id and id ~= "" and multiplier then
		return { Id = id, Multiplier = multiplier }
	end
	return nil
end

local function luckMultiplier(): number
	local luck = 1
	local endsAt = ReplicatedStorage:GetAttribute("LuckEndsAt") :: number?
	if endsAt and workspace:GetServerTimeNow() < endsAt then
		luck = Config.ServerLuckMultiplier
	end
	if adminAbuseLive() then
		luck = math.max(luck, Config.AdminAbuseBoosts.Luck)
	end
	-- Founder events with a luck boost (Ace's)
	local founderEvent = Config.FounderEvents[ReplicatedStorage:GetAttribute("FounderEvent") :: string? or ""]
	local founderEndsAt = ReplicatedStorage:GetAttribute("FounderEventEndsAt") :: number?
	if founderEvent and founderEvent.Luck and founderEndsAt and workspace:GetServerTimeNow() < founderEndsAt then
		luck = math.max(luck, founderEvent.Luck)
	end
	-- 99 Nights: every night survived makes the whole server luckier.
	if founderEvent and founderEvent.Forest and founderEndsAt and workspace:GetServerTimeNow() < founderEndsAt then
		local nights = (ReplicatedStorage:GetAttribute("NightsSurvived") :: number?) or 0
		luck = math.max(luck, math.min(Config.Nights99.MaxLuck, 1 + Config.Nights99.LuckPerNight * nights))
	end
	return luck
end

-- Player data --------------------------------------------------------------

local function defaultData(): SaveData
	return {
		Cash = Config.StartingCash,
		Rebirths = 0,
		Brainrots = {},
		Vault = {},
		VaultLevel = 1,
		Steals = 0,
		WallLevel = 1,
		Stories = 1,
		LockLevel = 1,
		Receipts = {},
		Unclaimed = {},
		Followers = {},
		Shards = 0,
		Skins = { "Classic" },
		Skin = "Classic",
		CashBoostUntil = 0,
		AbuseGiftWeek = -1,
		InfiniteLock = false,
		Codes = {},
		Discovered = {},
		Settings = { HideVip = false, MusicVolume = 1 },
		Quests = { Day = -1, Week = -1, Daily = {}, Weekly = {}, DailyDone = {}, WeeklyDone = {} },
	}
end

local function sanitize(raw: any): SaveData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.Cash) == "number" then
		data.Cash = raw.Cash
	end
	if type(raw.Rebirths) == "number" then
		data.Rebirths = raw.Rebirths
	end
	if type(raw.Steals) == "number" then
		data.Steals = raw.Steals
	end
	-- Walls and floors are one base level now; older saves upgraded them
	-- separately, so take whichever was higher.
	local wallLevel = if type(raw.WallLevel) == "number" then raw.WallLevel else 1
	local stories = if type(raw.Stories) == "number" then raw.Stories else 1
	local baseLevel = math.clamp(math.floor(math.max(wallLevel, stories)), 1, #Config.WallLevels)
	data.WallLevel = baseLevel
	data.Stories = baseLevel
	if type(raw.LockLevel) == "number" then
		data.LockLevel = math.clamp(math.floor(raw.LockLevel), 1, #Config.LockLevels)
	end
	if type(raw.Brainrots) == "table" then
		for _, entry in raw.Brainrots do
			if type(entry) == "string" then
				local brainrot, mutation, serial = Config.Decode(entry)
				if brainrot then
					table.insert(data.Brainrots, Config.Encode(brainrot.Id, mutation, serial))
				end
			end
		end
	end
	if type(raw.Vault) == "table" then
		for _, entry in raw.Vault do
			if type(entry) == "string" and #data.Vault < Config.VaultMaxPodiums then
				local brainrot, mutation, serial = Config.Decode(entry)
				if brainrot then
					table.insert(data.Vault, Config.Encode(brainrot.Id, mutation, serial))
				end
			end
		end
	end
	if type(raw.VaultLevel) == "number" then
		data.VaultLevel = math.clamp(math.floor(raw.VaultLevel), 1, #Config.VaultLevels)
	end
	if type(raw.Followers) == "table" then
		for _, entry in raw.Followers do
			if type(entry) == "string" and #data.Followers < 3 then
				table.insert(data.Followers, entry)
			end
		end
	end
	if type(raw.Shards) == "number" then
		data.Shards = math.max(0, math.floor(raw.Shards))
	end
	-- Diamonds were removed: any left in an old save become Shards (once,
	-- since Diamonds are no longer saved).
	if type(raw.Diamonds) == "number" and raw.Diamonds > 0 then
		data.Shards += math.floor(raw.Diamonds) * Config.ShardsPerOldDiamond
	end
	if type(raw.Skins) == "table" then
		for _, id in raw.Skins do
			if type(id) == "string" and Config.GetWallSkin(id) and not table.find(data.Skins, id) then
				table.insert(data.Skins, id)
			end
		end
	end
	if type(raw.CashBoostUntil) == "number" then
		data.CashBoostUntil = raw.CashBoostUntil
	end
	if type(raw.AbuseGiftWeek) == "number" then
		data.AbuseGiftWeek = raw.AbuseGiftWeek
	end
	data.InfiniteLock = raw.InfiniteLock == true
	if type(raw.Discovered) == "table" then
		for _, id in raw.Discovered do
			if type(id) == "string" and Config.GetBrainrot(id) and not table.find(data.Discovered, id) then
				table.insert(data.Discovered, id)
			end
		end
	end
	if type(raw.Codes) == "table" then
		for _, code in raw.Codes do
			if type(code) == "string" and not table.find(data.Codes, code) then
				table.insert(data.Codes, code)
			end
		end
	end
	if type(raw.Settings) == "table" then
		data.Settings.HideVip = raw.Settings.HideVip == true
		if type(raw.Settings.MusicVolume) == "number" and raw.Settings.MusicVolume == raw.Settings.MusicVolume then
			data.Settings.MusicVolume = math.clamp(raw.Settings.MusicVolume, 0, 1)
		end
	end
	if type(raw.Skin) == "string" and table.find(data.Skins, raw.Skin) then
		data.Skin = raw.Skin
	end
	if type(raw.Quests) == "table" then
		local q = raw.Quests
		local function numbers(t: any): { [string]: number }
			local out = {}
			if type(t) == "table" then
				for k, v in t do
					if type(k) == "string" and type(v) == "number" then
						out[k] = v
					end
				end
			end
			return out
		end
		local function flags(t: any): { [string]: boolean }
			local out = {}
			if type(t) == "table" then
				for k, v in t do
					if type(k) == "string" and v == true then
						out[k] = true
					end
				end
			end
			return out
		end
		data.Quests = {
			Day = if type(q.Day) == "number" then q.Day else -1,
			Week = if type(q.Week) == "number" then q.Week else -1,
			Daily = numbers(q.Daily),
			Weekly = numbers(q.Weekly),
			DailyDone = flags(q.DailyDone),
			WeeklyDone = flags(q.WeeklyDone),
		}
	end
	if type(raw.Unclaimed) == "table" then
		for _, entry in raw.Unclaimed do
			if type(entry) == "string" and Config.Decode(entry) then
				table.insert(data.Unclaimed, entry)
			end
		end
	end
	if type(raw.Receipts) == "table" then
		for _, id in raw.Receipts do
			if type(id) == "string" then
				table.insert(data.Receipts, id)
			end
		end
	end
	return data
end

-- Copies the brainrots currently in the base into the save data.
local function syncBrainrots(session: Session)
	local plot = session.Plot
	if not plot then
		return
	end
	local list = {}
	for i = 1, #plot.Parts.Pedestals do
		local slot = plot.Slots[i]
		if slot then
			table.insert(list, Config.Encode(slot.Id, slot.Mutation, slot.Serial))
		end
	end
	session.Data.Brainrots = list
	local vault = {}
	for i = 1, Config.VaultMaxPodiums do
		local slot = plot.Vault[i]
		if slot then
			table.insert(vault, Config.Encode(slot.Id, slot.Mutation, slot.Serial))
		end
	end
	session.Data.Vault = vault
end

-- itemId -> serial for every limited brainrot this player owns.
local function limitedOwned(session: Session): { [string]: number }
	local owned = {}
	local plot = session.Plot
	if plot then
		for _, slot in plot.Slots do
			if slot.Serial then
				owned[slot.Id] = slot.Serial
			end
		end
	end
	for _, entry in session.Data.Unclaimed do
		local brainrot, _, serial = Config.Decode(entry)
		if brainrot and serial then
			owned[brainrot.Id] = serial
		end
	end
	return owned
end

-- Quests ---------------------------------------------------------------------

local function currentQuests(): ({ Config.QuestDef }, { Config.QuestDef }, number, number, number, number)
	local day, week, toDay, toWeek = Config.QuestPeriods(workspace:GetServerTimeNow())
	return Config.PickQuests(Config.DailyQuests, day * 31 + 7), Config.PickQuests(Config.WeeklyQuests, week * 53 + 11), day, week, toDay, toWeek
end

-- Clears progress when a new day or week starts.
local function refreshQuestPeriod(data: SaveData)
	local _, _, day, week = currentQuests()
	local q = data.Quests
	if q.Day ~= day then
		q.Day, q.Daily, q.DailyDone = day, {}, {}
	end
	if q.Week ~= week then
		q.Week, q.Weekly, q.WeeklyDone = week, {}, {}
	end
end

local function questSnapshot(data: SaveData)
	refreshQuestPeriod(data)
	local daily, weekly, _, _, toDay, toWeek = currentQuests()
	local function list(defs: { Config.QuestDef }, counts: { [string]: number }, done: { [string]: boolean })
		local out = {}
		for _, quest in defs do
			table.insert(out, {
				Text = string.format(quest.Text, quest.Goal),
				Goal = quest.Goal,
				Progress = counts[quest.Id] or 0,
				Done = done[quest.Id] == true,
			})
		end
		return out
	end
	return {
		Daily = list(daily, data.Quests.Daily, data.Quests.DailyDone),
		Weekly = list(weekly, data.Quests.Weekly, data.Quests.WeeklyDone),
		DayResetIn = toDay,
		WeekResetIn = toWeek,
	}
end

-- Your base's brainrots, for the followers panel.
local function baseList(session: Session)
	local list = {}
	local plot = session.Plot
	if plot then
		for index, slot in plot.Slots do
			table.insert(list, {
				Slot = index,
				Id = slot.Id,
				Mutation = slot.Mutation,
				Following = table.find(session.FollowerModels, slot.Model) ~= nil,
			})
		end
	end
	return list
end

local function snapshot(session: Session)
	local data = session.Data
	local plot = session.Plot
	return {
		Cash = data.Cash,
		Income = if plot then plotIncome(plot, session) else 0,
		Rebirths = data.Rebirths,
		Multiplier = incomeMultiplier(session),
		RebirthCost = Config.RebirthCost(data.Rebirths),
		NextMultiplier = Config.RebirthMultiplier(data.Rebirths + 1) * (if session.Owns.DoubleCash then 2 else 1),
		Placed = if plot then placedCount(plot) else 0,
		MaxSlots = maxSlots(session),
		Steals = data.Steals,
		WallLevel = data.WallLevel,
		Stories = data.Stories,
		LockLevel = data.LockLevel,
		LockDuration = Config.LockLevels[data.LockLevel].Duration * (if session.Owns.LongerLock then 2 else 1),
		InfiniteLock = session.Owns.InfiniteLock == true or data.InfiniteLock,
		Owns = session.Owns,
		PlotIndex = if plot then plot.Parts.Index else 0,
		IsAdmin = hasAdminPowers(session) and session.FullAdmin,
		IsMod = hasAdminPowers(session) and not session.FullAdmin,
		AdminsLocked = adminsLockedNow(),
		IsFounder = session.IsFounder,
		FounderId = session.FounderId,
		Roles = session.Roles,
		Limited = limitedOwned(session),
		Shards = data.Shards,
		CashBoostLeft = math.max(0, data.CashBoostUntil - os.time()),
		Skins = data.Skins,
		Skin = data.Skin,
		Settings = data.Settings,
		Discovered = data.Discovered,
		VaultLevel = data.VaultLevel,
		VaultUsed = if plot then vaultCount(plot) else #data.Vault,
		Quests = questSnapshot(data),
		Base = baseList(session),
	}
end

local function updateLeaderstats(session: Session)
	local stats = session.Leaderstats
	if not stats then
		return
	end
	-- Cash shows as text ("$1.5Qi"): a whole-number value can't hold more
	-- than ~9.2 Qi and would wrap around to a huge negative number.
	local cash = stats:FindFirstChild("Cash") :: StringValue?
	local steals = stats:FindFirstChild("Steals") :: IntValue?
	local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
	if cash then
		cash.Value = Config.FormatCash(session.Data.Cash)
	end
	if steals then
		steals.Value = session.Data.Steals
	end
	if rebirths then
		rebirths.Value = session.Data.Rebirths
	end
end

-- Keeps cash a real, saveable number: never NaN, negative or past MaxCash.
local function clampCash(data: SaveData)
	local cash = data.Cash
	data.Cash = if cash ~= cash then 0 else math.clamp(cash, 0, Config.MaxCash)
end

local function push(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	clampCash(session.Data)
	updateLeaderstats(session)
	DataUpdated:FireClient(player, snapshot(session))
end

local function save(player: Player): boolean
	local session = sessions[player]
	if not session or not session.Loaded or not store or session.NoSave then
		return false
	end
	syncBrainrots(session)
	clampCash(session.Data)
	local key = "Player_" .. player.UserId
	local data = session.Data
	local ok, err = pcall(function()
		store:SetAsync(key, data, { player.UserId })
	end)
	if not ok then
		warn("[BrainrotHeist] Failed to save", player.Name, err)
	end
	return ok
end

-- Counts towards every active quest that tracks `stat` and pays out when done.
local function addQuestProgress(player: Player, stat: string, amount: number)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	local data = session.Data
	refreshQuestPeriod(data)
	local daily, weekly = currentQuests()
	local changed = false
	local function progress(list: { Config.QuestDef }, counts: { [string]: number }, done: { [string]: boolean }, isWeekly: boolean)
		for _, quest in list do
			if quest.Id == stat and not done[quest.Id] then
				counts[quest.Id] = math.min(quest.Goal, (counts[quest.Id] or 0) + amount)
				changed = true
				if counts[quest.Id] >= quest.Goal then
					done[quest.Id] = true
					local text = string.format(quest.Text, quest.Goal)
					if isWeekly then
						data.Shards += Config.WeeklyShards
						notify(player, string.format("WEEKLY QUEST DONE: %s  +%d Shards!", text, Config.WeeklyShards))
					else
						data.Shards += Config.DailyShards
						notify(player, "Daily quest done: " .. text .. "  +" .. Config.DailyShards .. " Shards!")
					end
				end
			end
		end
	end
	progress(daily, data.Quests.Daily, data.Quests.DailyDone, false)
	progress(weekly, data.Quests.Weekly, data.Quests.WeeklyDone, true)
	if changed then
		push(player)
	end
end

-- Followers ------------------------------------------------------------------
-- Up to 3 of your brainrots follow you around as minis. They're drawn by
-- every client from the "Followers" attribute. If one leaves your base
-- (stolen, sold, rebirth) its mini disappears too.

local function updateFollowers(player: Player)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session then
		return
	end
	local kept: { Model } = {}
	local entries: { string } = {}
	for _, model in session.FollowerModels do
		local ownedSlot = nil
		if plot then
			for _, slot in plot.Slots do
				if slot.Model == model then
					ownedSlot = slot
					break
				end
			end
		end
		if ownedSlot then
			table.insert(kept, model)
			table.insert(entries, Config.Encode(ownedSlot.Id, ownedSlot.Mutation))
		end
	end
	session.FollowerModels = kept
	session.Data.Followers = entries
	local text = table.concat(entries, ",")
	if player:GetAttribute("Followers") ~= text then
		player:SetAttribute("Followers", text)
	end
end

-- Brainrots in bases -------------------------------------------------------

local onSell: (Player, Model) -> ()
local moveToVault: (Player, Model) -> ()
local moveToBase: (Player, Model) -> ()
local onSteal: (Player, Model) -> ()
local deliverUnclaimed: (Player, Session) -> ()

local function addBasePrompts(model: Model, brainrot: Config.Brainrot, mutation: string?)
	local root = model.PrimaryPart :: BasePart
	if root:FindFirstChild("SellPrompt") then
		return
	end

	local sell = Instance.new("ProximityPrompt")
	sell.Name = "SellPrompt"
	sell.ActionText = "Sell " .. Config.FormatCash(Config.SellValue(brainrot, mutation))
	sell.ObjectText = fullName(brainrot, mutation)
	sell.HoldDuration = 0.6
	sell.MaxActivationDistance = 10
	sell.RequiresLineOfSight = false
	sell.KeyboardKeyCode = Enum.KeyCode.F
	sell:SetAttribute("Action", "Sell")
	sell.Parent = root
	sell.Triggered:Connect(function(player)
		onSell(player, model)
	end)

	local steal = Instance.new("ProximityPrompt")
	steal.Name = "StealPrompt"
	steal.ActionText = "STEAL!"
	steal.ObjectText = fullName(brainrot, mutation)
	steal.HoldDuration = 1.2
	steal.MaxActivationDistance = 10
	steal.RequiresLineOfSight = false
	steal:SetAttribute("Action", "Steal")
	steal.Parent = root
	steal.Triggered:Connect(function(player)
		onSteal(player, model)
	end)

	-- Limited brainrots stay through rebirths anyway, so they don't need the vault.
	if not brainrot.Limited then
		local toVault = Instance.new("ProximityPrompt")
		toVault.Name = "ToVaultPrompt"
		toVault.ActionText = "Move to Vault"
		toVault.ObjectText = fullName(brainrot, mutation)
		toVault.HoldDuration = 0.4
		toVault.MaxActivationDistance = 10
		toVault.RequiresLineOfSight = false
		toVault.KeyboardKeyCode = Enum.KeyCode.V
		toVault.UIOffset = Vector2.new(0, 70)
		toVault:SetAttribute("Action", "ToVault")
		toVault.Parent = root
		toVault.Triggered:Connect(function(player)
			moveToVault(player, model)
		end)
	end
end

local function pedestalCFrame(plot: Plot, index: number): CFrame
	-- Root sits half a stud above the pedestal top (see BrainrotModel).
	return plot.Parts.Pedestals[index].CFrame * CFrame.new(0, 1, 0)
end

-- Bought and grabbed brainrots walk home: across the grass to the door, in,
-- up the stairs floor by floor, then onto their pedestal.
local WALK_SPEED = 18

local function walkPath(plot: Plot, target: CFrame): { Vector3 }
	local parts = plot.Parts
	local half = parts.Floors[1].Size.Z / 2
	local points = {
		(parts.CFrame * CFrame.new(0, -0.5, -half - 8)).Position, -- outside the door
		(parts.CFrame * CFrame.new(0, 0.5, -half + 6)).Position, -- just inside
	}
	for k, stair in parts.Stairs do
		local bottomY = stair.Base.Position.Y
		if target.Position.Y < bottomY + 4 then
			break -- already on the pedestal's floor
		end
		local nextStair = parts.Stairs[k + 1]
		local height = if nextStair then nextStair.Base.Position.Y - bottomY else 20
		table.insert(points, (stair.Base * CFrame.new(0, 0.5, -2)).Position)
		table.insert(points, (stair.Base * CFrame.new(0, height + 0.5, 32)).Position)
	end
	table.insert(points, target.Position)
	return points
end

local function walkHome(model: Model, root: BasePart, points: { Vector3 }, target: CFrame)
	-- No stealing or selling it on the way (see onSteal / the HUD prompts).
	model:SetAttribute("Walking", true)
	task.spawn(function()
		local position = root.Position
		for _, point in points do
			if not model.Parent or model:GetAttribute("Carried") then
				return
			end
			local distance = (point - position).Magnitude
			if distance > 0.05 then
				-- Face where it's going (designs face -Z, like CFrame.lookAt).
				local level = Vector3.new(point.X, position.Y, point.Z)
				local facing = if (level - position).Magnitude > 0.05 then CFrame.lookAt(position, level).Rotation else root.CFrame.Rotation
				local tween = TweenService:Create(root, TweenInfo.new(distance / WALK_SPEED, Enum.EasingStyle.Linear), { CFrame = CFrame.new(point) * facing })
				tween:Play()
				tween.Completed:Wait()
			end
			position = point
		end
		if model.Parent then
			root.CFrame = target
			model:SetAttribute("Walking", false)
		end
	end)
end

-- Puts a brainrot in a base slot, reusing `model` if given (bought or stolen).
-- `animate`: a reused model walks home from where it is.
local function placeBrainrot(plot: Plot, index: number, id: string, mutation: string?, model: Model?, animate: boolean, serial: number?)
	local brainrot = Config.GetBrainrot(id)
	if not brainrot then
		return
	end
	local target = pedestalCFrame(plot, index)

	local m = model or BrainrotModel.Create(brainrot, mutation, target * CFrame.new(0, -0.5, 0), false, serial)
	local root = m.PrimaryPart :: BasePart

	local buy = root:FindFirstChild("BuyPrompt")
	if buy then
		buy:Destroy()
	end
	BrainrotModel.RemovePrice(m)

	local owner = plot.Owner
	m:SetAttribute("PlotIndex", plot.Parts.Index)
	m:SetAttribute("Slot", index)
	m:SetAttribute("Vault", nil)
	m:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	m:SetAttribute("Carried", false)
	m.Parent = plot.Parts.Model
	addBasePrompts(m, brainrot, mutation)

	root.Anchored = true
	if animate and model and (root.Position - target.Position).Magnitude > 6 then
		walkHome(m, root, walkPath(plot, target), target)
	else
		m:SetAttribute("Walking", false)
		root.CFrame = target
	end

	plot.Slots[index] = { Id = id, Mutation = mutation, Serial = serial, Model = m }

	-- Income that grows with rebirths shows the owner's current amount.
	local session = owner and sessions[owner]
	if owner and session and not table.find(session.Data.Discovered, id) then
		table.insert(session.Data.Discovered, id)
		notify(owner, string.format("📖 NEW in your Index: %s! (%d/%d)", brainrot.DisplayName, #session.Data.Discovered, #Config.Brainrots))
	end
	if session and brainrot.IncomeGrowth then
		BrainrotModel.SetIncomeText(m, Config.IncomeOf(brainrot, mutation, session.Data.Rebirths))
	end
end

-- Vault ------------------------------------------------------------------------
-- Brainrots on the vault podiums under a base keep earning, can't be stolen
-- or sold, and stay through rebirths. Moved with prompts: "Move to Vault" on
-- a base brainrot, "Move to Base" in the vault (the owner only sees them).

local function removePrompts(model: Model)
	local root = model.PrimaryPart
	if root then
		for _, child in root:GetChildren() do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
	end
end

local function placeInVault(plot: Plot, index: number, id: string, mutation: string?, serial: number?, model: Model?)
	local brainrot = Config.GetBrainrot(id)
	local podium = plot.Parts.VaultPodiums[index]
	if not brainrot or not podium then
		return
	end
	local target = podium.CFrame * CFrame.new(0, 1.2, 0)
	local m = model or BrainrotModel.Create(brainrot, mutation, target * CFrame.new(0, -0.5, 0), false, serial)
	BrainrotModel.RemovePrice(m)
	removePrompts(m)
	local root = m.PrimaryPart :: BasePart
	root.Anchored = true
	root.CFrame = target
	local owner = plot.Owner
	m:SetAttribute("PlotIndex", plot.Parts.Index)
	m:SetAttribute("Slot", nil)
	m:SetAttribute("Vault", index)
	m:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	m:SetAttribute("Carried", false)
	m:SetAttribute("Walking", false)
	m.Parent = plot.Parts.Vault
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FromVaultPrompt"
	prompt.ActionText = "Move to Base"
	prompt.ObjectText = fullName(brainrot, mutation)
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "FromVault")
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		moveToBase(player, m)
	end)
	plot.Vault[index] = { Id = id, Mutation = mutation, Serial = serial, Model = m }
	local session = owner and sessions[owner]
	if session and brainrot.IncomeGrowth then
		BrainrotModel.SetIncomeText(m, Config.IncomeOf(brainrot, mutation, session.Data.Rebirths))
	end
end

local function updateVipPedestals(plot: Plot)
	local owner = plot.Owner
	local session = owner and sessions[owner]
	for i = 1, GROUND_SLOTS do
		local pedestal = plot.Parts.Pedestals[i]
		local locked = i > Config.BaseSlots and not (session and session.Owns.VIP)
		pedestal.Color = if locked then Color3.fromRGB(255, 195, 40) else Color3.fromRGB(60, 60, 70)
		pedestal.Material = if locked then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local tag = pedestal:FindFirstChild("VipTag") :: BillboardGui?
		if locked and not tag then
			local gui = Instance.new("BillboardGui")
			gui.Name = "VipTag"
			gui.Size = UDim2.fromScale(4, 1.3)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
			gui.MaxDistance = 150
			gui.Parent = pedestal
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.TextColor3 = Color3.fromRGB(255, 220, 80)
			l.TextStrokeTransparency = 0
			l.Text = "VIP SLOT"
			l.Parent = gui
		elseif not locked and tag then
			tag:Destroy()
		end
	end
end

local function setLaser(plot: Plot, on: boolean)
	for _, beam in plot.Parts.Lasers do
		beam.Transparency = if on and beam:GetAttribute("Active") then 0.1 else 1
	end
	plot.Parts.Model:SetAttribute("Locked", on)
end

-- Whether the base wears the VIP Royale skin (velvet stairs, VIP throne).
local function wearsVipSkin(session: Session): boolean
	local skin = Config.GetWallSkin(session.Data.Skin)
	return skin ~= nil and skin.Vip == true
end

-- The throne style on a max-prestige balcony: Corny's is made of corn, Ace's
-- is a pink bloom, VIP Royale's is velvet and gold, everyone else's is in
-- their carpet colors.
local function throneLook(session: Session): string?
	return if session.FounderId == "Corny" then "Corn"
		elseif session.FounderId == "Ace" then "Bloom"
		elseif wearsVipSkin(session) then "VIP"
		else nil
end

-- The stairs' carpet: the VIP velvet for VIP Royale, else the rebirth one.
local function carpetOverride(session: Session): Config.CarpetTier?
	return if wearsVipSkin(session) then Config.VipCarpet else nil
end

local function lockDuration(session: Session): number
	local duration = Config.LockLevels[session.Data.LockLevel].Duration
	return if session.Owns.LongerLock then duration * 2 else duration
end

-- Infinite Laser Door (gamepass or Shards): the lasers never turn off.
local function hasInfiniteLock(session: Session): boolean
	return session.Owns.InfiniteLock == true or session.Data.InfiniteLock
end

local function applyInfiniteLock(plot: Plot, session: Session)
	if hasInfiniteLock(session) and plot.LockedUntil ~= math.huge and not plot.DoorOpen then
		plot.LockedUntil = math.huge
		plot.CooldownUntil = math.huge
		setLaser(plot, true)
	end
end

local function lockBase(plot: Plot)
	local owner = plot.Owner
	local session = owner and sessions[owner]
	if not session then
		return
	end
	local duration = lockDuration(session)
	local now = os.clock()
	plot.LockedUntil = now + duration
	plot.CooldownUntil = plot.LockedUntil + Config.LockCooldown
	setLaser(plot, true)
end

-- Stealing -----------------------------------------------------------------

-- Walking speed and jump: slow while carrying, boosted during admin abuse.
local function applyMovement(player: Player)
	local _, humanoid = getRoot(player)
	if not humanoid then
		return
	end
	local carrying = player:GetAttribute("Carrying") ~= nil
	local boosted = adminAbuseLive() and not carrying
	humanoid.WalkSpeed = if carrying then Config.CarryWalkSpeed elseif boosted then Config.AdminAbuseBoosts.WalkSpeed else Config.NormalWalkSpeed
	if humanoid.UseJumpPower then
		humanoid.JumpPower = if boosted then 50 * math.sqrt(Config.AdminAbuseBoosts.JumpHeight / 7.2) else 50
	else
		humanoid.JumpHeight = if boosted then Config.AdminAbuseBoosts.JumpHeight else 7.2
	end
end

local function setCarrying(player: Player, text: string?)
	player:SetAttribute("Carrying", text)
	applyMovement(player)
end

-- Puts a stolen brainrot back on its owner's pedestal.
local function returnCarry(carry: Carry, message: string?)
	carries[carry.Thief] = nil
	setCarrying(carry.Thief, nil)
	carry.Weld:Destroy()

	local plot = carry.Plot
	local slot = plot.Slots[carry.SlotIndex]
	if slot and slot.StolenBy == carry.Thief then
		slot.StolenBy = nil
		local root = slot.Model.PrimaryPart :: BasePart
		root.Anchored = true
		root.CFrame = pedestalCFrame(plot, carry.SlotIndex)
		slot.Model.Parent = plot.Parts.Model
		slot.Model:SetAttribute("Carried", false)
		if plot.Owner then
			push(plot.Owner)
		end
	end
	if message then
		notify(carry.Thief, message)
	end
end

local function completeCarry(carry: Carry)
	local thief = carry.Thief
	local thiefSession = sessions[thief]
	local thiefPlot = thiefSession and thiefSession.Plot
	local victimPlot = carry.Plot
	local slot = victimPlot.Slots[carry.SlotIndex]
	if not thiefSession or not thiefPlot or not slot or slot.StolenBy ~= thief then
		returnCarry(carry, nil)
		return
	end
	local index = freeSlot(thiefPlot, thiefSession)
	if not index then
		returnCarry(carry, "Your base is full! The brainrot ran home.")
		return
	end

	carries[thief] = nil
	setCarrying(thief, nil)
	carry.Weld:Destroy()
	victimPlot.Slots[carry.SlotIndex] = nil
	placeBrainrot(thiefPlot, index, slot.Id, slot.Mutation, slot.Model, false)
	thiefSession.Data.Steals += 1
	addQuestProgress(thief, "Steal", 1)

	local brainrot = Config.GetBrainrot(slot.Id) :: Config.Brainrot
	local name = fullName(brainrot, slot.Mutation)
	local victim = victimPlot.Owner
	notify(thief, "You stole " .. name .. "!")
	if victim then
		notify(victim, thief.DisplayName .. " stole your " .. name .. "!")
		push(victim)
		-- Save both sides right away so a server crash can't duplicate it.
		task.spawn(save, victim)
	end
	if isNotable(brainrot, slot.Mutation) then
		Announce:FireAllClients("steal", thief.DisplayName, brainrot.Id, if victim then victim.DisplayName else "", slot.Mutation)
	end
	push(thief)
	task.spawn(save, thief)
end

onSteal = function(thief: Player, model: Model)
	local session = sessions[thief]
	if not session or not session.Loaded or not session.Plot or carries[thief] then
		return
	end
	local plot = plots[model:GetAttribute("PlotIndex") :: number]
	local index = model:GetAttribute("Slot") :: number
	local owner = plot and plot.Owner
	if not plot or not owner or owner == thief or model:GetAttribute("Carried") or model:GetAttribute("Walking") then
		return
	end
	local slot = plot.Slots[index]
	if not slot or slot.Model ~= model or slot.StolenBy then
		return
	end
	if model:GetAttribute("Protected") then
		notify(thief, "Limited brainrots can't be stolen!")
		return
	end
	if os.clock() < plot.LockedUntil then
		notify(thief, "This base is locked!")
		return
	end
	if not freeSlot(session.Plot, session) then
		notify(thief, "Your base is full! Sell something first.")
		return
	end
	local hrp = getRoot(thief)
	local root = model.PrimaryPart :: BasePart
	if not hrp or (hrp.Position - root.Position).Magnitude > Config.StealRange then
		return
	end

	local brainrot = Config.GetBrainrot(slot.Id) :: Config.Brainrot
	slot.StolenBy = thief
	model:SetAttribute("Carried", true)
	model.Parent = world.CarriedFolder
	root.CFrame = hrp.CFrame * CFrame.new(0, 3.5, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = root
	weld.Parent = root
	root.Anchored = false

	local home = session.Plot.Parts.CFrame.Position
	carries[thief] = {
		Thief = thief,
		Plot = plot,
		SlotIndex = index,
		Started = os.clock(),
		-- Server-side speed check: nobody can carry it home faster than this.
		MinTime = (hrp.Position - home).Magnitude / (Config.CarryWalkSpeed * 1.6),
		Weld = weld,
	}
	setCarrying(thief, fullName(brainrot, slot.Mutation))
	notify(thief, "Run it back to your base! Don't get slapped!")
	notify(owner, thief.DisplayName .. " is stealing your " .. fullName(brainrot, slot.Mutation) .. "! Slap them!")
	push(owner)
end

-- Sells the brainrot on one of your pedestals. Returns what it sold for (nil
-- if it can't be sold: empty, being stolen, or limited).
local function sellSlot(session: Session, plot: Plot, index: number): number?
	local slot = plot.Slots[index]
	if not slot or slot.StolenBy then
		return nil
	end
	local brainrot = Config.GetBrainrot(slot.Id)
	if not brainrot or brainrot.Limited then
		return nil
	end
	plot.Slots[index] = nil
	slot.Model:Destroy()
	local value = Config.SellValue(brainrot, slot.Mutation)
	session.Data.Cash += value
	return value
end

onSell = function(player: Player, model: Model)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session or not plot or model:GetAttribute("PlotIndex") ~= plot.Parts.Index then
		return
	end
	local index = model:GetAttribute("Slot") :: number
	local slot = plot.Slots[index]
	if not slot or slot.Model ~= model then
		return
	end
	local name = fullName(Config.GetBrainrot(slot.Id) :: Config.Brainrot, slot.Mutation)
	local value = sellSlot(session, plot, index)
	if value then
		notify(player, "Sold " .. name .. " for " .. Config.FormatCash(value))
		deliverUnclaimed(player, session)
		push(player)
	end
end

moveToVault = function(player: Player, model: Model)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session or not plot or plot.Owner ~= player or model:GetAttribute("Walking") then
		return
	end
	local index = model:GetAttribute("Slot") :: number?
	local slot = index and plot.Slots[index]
	if not index or not slot or slot.Model ~= model or slot.StolenBy then
		return
	end
	local podiums = Config.VaultLevels[session.Data.VaultLevel].Podiums
	local free: number? = nil
	for i = 1, podiums do
		if not plot.Vault[i] then
			free = i
			break
		end
	end
	if not free then
		notify(player, "Your vault is full! Upgrade it at the upgrade post for more podiums.")
		return
	end
	plot.Slots[index] = nil
	placeInVault(plot, free, slot.Id, slot.Mutation, slot.Serial, model)
	updateFollowers(player)
	notify(player, fullName(Config.GetBrainrot(slot.Id) :: Config.Brainrot, slot.Mutation) .. " is safe in your vault!")
	deliverUnclaimed(player, session)
	push(player)
end

moveToBase = function(player: Player, model: Model)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session or not plot or plot.Owner ~= player then
		return
	end
	local index = model:GetAttribute("Vault") :: number?
	local slot = index and plot.Vault[index]
	if not index or not slot or slot.Model ~= model then
		return
	end
	local free = freeSlot(plot, session)
	if not free then
		notify(player, "No free pedestal in your base!")
		return
	end
	plot.Vault[index] = nil
	removePrompts(model)
	placeBrainrot(plot, free, slot.Id, slot.Mutation, model, false, slot.Serial)
	notify(player, "Moved " .. fullName(Config.GetBrainrot(slot.Id) :: Config.Brainrot, slot.Mutation) .. " back to your base.")
	push(player)
end

-- The Sell Stand by the shop: sell one brainrot (by pedestal) or all of them.
SellBrainrot.OnServerEvent:Connect(function(player: Player, which: unknown)
	local session = sessions[player]
	local plot = session and session.Plot
	local hrp = getRoot(player)
	if not session or not session.Loaded or not plot or not hrp then
		return
	end
	if ((hrp.Position - world.SellPosition) * Vector3.new(1, 0, 1)).Magnitude > 25 then
		notify(player, "Go to the Sell Stand by the shop to sell!")
		return
	end
	if which == "all" then
		local total, count = 0, 0
		for index in table.clone(plot.Slots) do
			local value = sellSlot(session, plot, index)
			if value then
				total += value
				count += 1
			end
		end
		if count == 0 then
			notify(player, "Nothing to sell!")
			return
		end
		notify(player, string.format("Sold %d brainrot%s for %s!", count, if count == 1 then "" else "s", Config.FormatCash(total)))
	elseif type(which) == "number" then
		local slot = plot.Slots[which]
		if not slot then
			return
		end
		local name = fullName(Config.GetBrainrot(slot.Id) :: Config.Brainrot, slot.Mutation)
		local value = sellSlot(session, plot, which)
		if not value then
			notify(player, "That one can't be sold right now.")
			return
		end
		notify(player, "Sold " .. name .. " for " .. Config.FormatCash(value))
	else
		return
	end
	deliverUnclaimed(player, session)
	push(player)
end)

task.spawn(function()
	while true do
		-- One bad tick is logged and skipped; the loop never stops.
		local ok, err = pcall(function()
			task.wait(0.1)
			for thief, carry in carries do
				local hrp = getRoot(thief)
				local session = sessions[thief]
				if not hrp or not session or not session.Plot then
					returnCarry(carry, "You dropped it! It ran back home.")
				elseif isInside(session.Plot, hrp.Position) and os.clock() - carry.Started >= carry.MinTime then
					completeCarry(carry)
				end
			end
		end)
		if not ok then
			warn("[BrainrotHeist] carry loop error:", err)
			task.wait(1)
		end
	end
end)

-- Plots --------------------------------------------------------------------

-- Limited (Robux) brainrots ------------------------------------------------

local function ownsLimited(session: Session, itemId: string): boolean
	local plot = session.Plot
	if plot then
		for _, slot in plot.Slots do
			if slot.Id == itemId then
				return true
			end
		end
	end
	for _, entry in session.Data.Unclaimed do
		local brainrot = Config.Decode(entry)
		if brainrot and brainrot.Id == itemId then
			return true
		end
	end
	return false
end

-- Puts a paid brainrot in the base. If every pedestal is taken it waits in
-- Unclaimed and appears as soon as a slot frees up.
local function grantLimited(player: Player, session: Session, brainrot: Config.Brainrot, serial: number): string?
	-- Every copy rolls for a mutation: normal odds, plus 1% Magic (event-only),
	-- which stacks on top of whatever it rolled.
	local mutation: string? = Config.RollMutation(rng, 1)
	if Config.MutationAllowed(brainrot, "Magic") and rng:NextNumber(0, 100) < Config.MagicChance then
		mutation = Config.JoinMutations({ mutation or "", "Magic" })
	end
	local plot = session.Plot
	local index = plot and freeSlot(plot, session)
	if plot and not index then
		for i = 1, #plot.Parts.Pedestals do
			if not plot.Slots[i] and (i <= GROUND_SLOTS or isSlotUnlocked(session, i)) then
				index = i
				break
			end
		end
	end
	local name = fullName(brainrot, mutation)
	if plot and index then
		placeBrainrot(plot, index, brainrot.Id, mutation, nil, true, serial)
		notify(player, string.format("%s #%d is in your base!", name, serial))
	else
		table.insert(session.Data.Unclaimed, Config.Encode(brainrot.Id, mutation, serial))
		notify(player, name .. " will appear as soon as you have a free slot!")
	end
	if hasMagic(mutation) then
		notify(player, "INCREDIBLE! You rolled the 1% MAGIC mutation!")
	end
	push(player)
	return mutation
end

-- Limited brainrots this player owns in the shared stock but doesn't have
-- yet: gifts Corny gave while they were offline or in another server (and
-- any purchase whose save didn't go through).
local function deliverOwnedLimited(player: Player)
	for itemId in Config.LimitedItems do
		local session = sessions[player]
		local brainrot = Config.GetBrainrot(itemId)
		if not session or not session.Loaded or not brainrot or ownsLimited(session, itemId) then
			continue
		end
		local serial = LimitedStock.OwnedSerial(player.UserId, itemId)
		local item = Config.LimitedItems[itemId]
		if not serial and item.GamePassId and item.GamePassId ~= 0 then
			-- Bought the gamepass (maybe on the website) but no copy yet.
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.GamePassId :: number)
			end)
			if ok and owns then
				serial = LimitedStock.Claim(player, itemId)
			end
		end
		-- Checked again after the wait: they may have left, or got it meanwhile.
		session = sessions[player]
		if serial and session and session.Loaded and not ownsLimited(session, itemId) then
			local rolled = grantLimited(player, session, brainrot, serial)
			Announce:FireAllClients("limited", player.DisplayName, itemId, tostring(serial), rolled)
		end
	end
end

deliverUnclaimed = function(player: Player, session: Session)
	local plot = session.Plot
	if not plot then
		return
	end
	local list = session.Data.Unclaimed
	for i = #list, 1, -1 do
		local brainrot, mutation, serial = Config.Decode(list[i])
		local index = freeSlot(plot, session)
		if not index then
			break
		end
		table.remove(list, i)
		if brainrot then
			placeBrainrot(plot, index, brainrot.Id, mutation, nil, true, serial)
			notify(player, brainrot.DisplayName .. " arrived in your base!")
		end
	end
end

-- Admin abuse rewards --------------------------------------------------------
-- While admin abuse is live everyone earns more, gets Server Luck and walks
-- faster (see incomeMultiplier, luckMultiplier and setCarrying). Everyone
-- online also gets a gift, once per week.

local function giveAbuseGift(player: Player, session: Session)
	local _, week = Config.QuestPeriods(workspace:GetServerTimeNow())
	local data = session.Data
	if data.AbuseGiftWeek == week then
		return
	end
	data.AbuseGiftWeek = week
	local gift = Config.AdminAbuseGift
	data.Shards += gift.Shards
	local brainrot = Config.RollConveyor(rng, gift.BrainrotLuck, false)
	local mutation = Config.RollMutation(rng, gift.BrainrotLuck, nightBoost())
	local plot = session.Plot
	local index = plot and freeSlot(plot, session)
	if plot and index then
		placeBrainrot(plot, index, brainrot.Id, mutation, nil, true)
	else
		table.insert(data.Unclaimed, Config.Encode(brainrot.Id, mutation))
		notify(player, "Your gift brainrot will appear as soon as you have a free slot!")
	end
	Announce:FireClient(player, "abusegift", "", brainrot.Id, tostring(gift.Shards), mutation)
	push(player)
	task.spawn(save, player)
end

task.spawn(function()
	local wasLive = false
	while true do
		-- One bad tick is logged and skipped; the loop never stops.
		local ok, err = pcall(function()
			local live = adminAbuseLive()
			if live ~= wasLive then
				-- Boosts switched on or off: refresh walk speeds and income displays.
				for player, session in sessions do
					if session.Loaded then
						applyMovement(player)
						push(player)
					end
				end
			end
			if live then
				for player, session in sessions do
					if session.Loaded then
						giveAbuseGift(player, session)
					end
				end
			end
			wasLive = live
			task.wait(1)
		end)
		if not ok then
			warn("[BrainrotHeist] boosts loop error:", err)
			task.wait(1)
		end
	end
end)

-- Removes brainrots from a base. `keepLimited` keeps Robux brainrots (used
-- for rebirths and admin clears; they were paid for).
local function clearPlotBrainrots(plot: Plot, keepLimited: boolean?)
	for thief, carry in carries do
		if carry.Plot == plot then
			carries[thief] = nil
			setCarrying(thief, nil)
			notify(thief, "The brainrot vanished!")
		end
	end
	for index, slot in plot.Slots do
		local brainrot = Config.GetBrainrot(slot.Id)
		if not (keepLimited and brainrot and brainrot.Limited) then
			slot.Model:Destroy()
			plot.Slots[index] = nil
		end
	end
end

local function updateUpgradeLabel(plot: Plot)
	local owner = plot.Owner
	local session = owner and sessions[owner]
	if not session then
		plot.Parts.UpgradeLabel.Text = "UPGRADES"
		return
	end
	local data = session.Data
	plot.Parts.UpgradeLabel.Text = if hasInfiniteLock(session)
		then string.format("UPGRADES\nBase Lv %d/%d | Lock FOREVER", data.WallLevel, math.max(data.WallLevel, Config.MaxWallLevel(session.Owns.VIP)))
		else string.format("UPGRADES\nBase Lv %d/%d | Lock %ds", data.WallLevel, math.max(data.WallLevel, Config.MaxWallLevel(session.Owns.VIP)), lockDuration(session))
end

local function assignPlot(player: Player, session: Session)
	for _, plot in plots do
		if not plot.Owner then
			plot.Owner = player
			plot.Pending = 0
			plot.LockedUntil = 0
			plot.CooldownUntil = 0
			plot.DoorOpen = false
			plot.Parts.Model:SetAttribute("OwnerUserId", player.UserId)
			plot.Parts.OwnerLabel.Text = player.DisplayName .. "'s Base"
			session.Plot = plot
			updateVipPedestals(plot)
			WorldBuilder.SetWallLevel(plot.Parts, session.Data.WallLevel, session.Data.Stories, Config.GetWallSkin(session.Data.Skin))
			WorldBuilder.SetStories(plot.Parts, session.Data.Stories)
			WorldBuilder.SetCarpet(plot.Parts, Config.CarpetTierFor(session.Data.Rebirths), carpetOverride(session))
			WorldBuilder.SetPrestige(plot.Parts, session.Data.Rebirths, session.Data.Stories, throneLook(session), carpetOverride(session))
			setLaser(plot, false)
			applyInfiniteLock(plot, session)
			-- Everything they already own counts as discovered (older saves).
			for _, list in { session.Data.Brainrots, session.Data.Vault, session.Data.Unclaimed } do
				for _, entry in list do
					local owned = Config.Decode(entry)
					if owned and not table.find(session.Data.Discovered, owned.Id) then
						table.insert(session.Data.Discovered, owned.Id)
					end
				end
			end
			for _, entry in session.Data.Brainrots do
				local brainrot, mutation, serial = Config.Decode(entry)
				-- Fill unlocked slots first; if there are more brainrots than
				-- unlocked slots (e.g. VIP ended), keep them on any free pedestal.
				local index = freeSlot(plot, session)
				if not index then
					for i = 1, #plot.Parts.Pedestals do
						if not plot.Slots[i] then
							index = i
							break
						end
					end
				end
				if brainrot and index then
					placeBrainrot(plot, index, brainrot.Id, mutation, nil, false, serial)
				end
			end
			WorldBuilder.SetVaultPodiums(plot.Parts, Config.VaultLevels[session.Data.VaultLevel].Podiums)
			for i, entry in session.Data.Vault do
				local brainrot, mutation, serial = Config.Decode(entry)
				if brainrot then
					placeInVault(plot, i, brainrot.Id, mutation, serial, nil)
				end
			end
			updateUpgradeLabel(plot)
			deliverUnclaimed(player, session)
			-- Re-pick saved followers from the placed brainrots.
			for _, entry in session.Data.Followers do
				for _, slot in plot.Slots do
					if Config.Encode(slot.Id, slot.Mutation) == entry and not table.find(session.FollowerModels, slot.Model) then
						table.insert(session.FollowerModels, slot.Model)
						break
					end
				end
			end
			updateFollowers(player)
			return
		end
	end
	notify(player, "All bases are taken! Try another server.")
end

local function releasePlot(plot: Plot)
	clearPlotBrainrots(plot)
	for index, slot in plot.Vault do
		slot.Model:Destroy()
		plot.Vault[index] = nil
	end
	plot.Owner = nil
	plot.Pending = 0
	plot.LockedUntil = 0
	plot.CooldownUntil = 0
	plot.DoorOpen = false
	setLaser(plot, false)
	plot.Parts.Model:SetAttribute("OwnerUserId", 0)
	plot.Parts.OwnerLabel.Text = "EMPTY BASE"
	plot.Parts.PendingLabel.Text = "COLLECT\n$0"
	plot.Parts.LockLabel.Text = "STEP TO LOCK"
	plot.Parts.LockButtonLabel.Text = "LOCK DOOR"
	updateVipPedestals(plot)
	WorldBuilder.SetWallLevel(plot.Parts, 1, 1)
	WorldBuilder.SetStories(plot.Parts, 1)
	WorldBuilder.SetCarpet(plot.Parts, 0)
	WorldBuilder.SetPrestige(plot.Parts, 0, 1)
	plot.Parts.UpgradeLabel.Text = "UPGRADES"
end

-- Applies a base's saved wall, floor and lock levels to the world.
local function applyBaseLevels(plot: Plot, session: Session)
	WorldBuilder.SetWallLevel(plot.Parts, session.Data.WallLevel, session.Data.Stories, Config.GetWallSkin(session.Data.Skin))
	WorldBuilder.SetStories(plot.Parts, session.Data.Stories)
	WorldBuilder.SetCarpet(plot.Parts, Config.CarpetTierFor(session.Data.Rebirths), carpetOverride(session))
	WorldBuilder.SetPrestige(plot.Parts, session.Data.Rebirths, session.Data.Stories, throneLook(session), carpetOverride(session))
	WorldBuilder.SetVaultPodiums(plot.Parts, Config.VaultLevels[session.Data.VaultLevel].Podiums)
	applyInfiniteLock(plot, session)
	setLaser(plot, os.clock() < plot.LockedUntil)
	updateVipPedestals(plot)
	updateUpgradeLabel(plot)
	for _, slot in plot.Slots do
		local brainrot = Config.GetBrainrot(slot.Id)
		if brainrot and brainrot.IncomeGrowth then
			BrainrotModel.SetIncomeText(slot.Model, Config.IncomeOf(brainrot, slot.Mutation, session.Data.Rebirths))
		end
	end
end

local function onUpgrade(player: Player, plot: Plot, kind: string)
	local session = sessions[player]
	if not session or not session.Loaded or plot.Owner ~= player then
		return
	end
	local data = session.Data
	local cost: number, name: string
	if kind == "Base" then
		local nextLevel = Config.WallLevels[data.WallLevel + 1]
		if not nextLevel then
			notify(player, "Your base is fully upgraded!")
			return
		end
		if nextLevel.Vip and not session.Owns.VIP then
			notify(player, "The next floors are VIP only! Get VIP in the shop to build higher.")
			return
		end
		cost, name = nextLevel.Cost, Config.Stories[data.WallLevel + 1].Name .. " + " .. nextLevel.Name
	elseif kind == "Lock" then
		if hasInfiniteLock(session) then
			notify(player, "Your lasers already stay on forever!")
			return
		end
		local nextLock = Config.LockLevels[data.LockLevel + 1]
		if not nextLock then
			notify(player, "Your lock is already maxed out!")
			return
		end
		if nextLock.Rebirths and data.Rebirths < nextLock.Rebirths then
			notify(player, string.format("Rebirth %d time%s to unlock the %ds lock!", nextLock.Rebirths, if nextLock.Rebirths == 1 then "" else "s", nextLock.Duration))
			return
		end
		cost, name = nextLock.Cost, nextLock.Duration .. "s Lock"
	elseif kind == "Vault" then
		local nextVault = Config.VaultLevels[data.VaultLevel + 1]
		if not nextVault then
			notify(player, "Your vault is already maxed out!")
			return
		end
		cost, name = nextVault.Cost, nextVault.Podiums .. " Vault Podiums"
	else
		return
	end

	if data.Cash < cost then
		notify(player, "You need " .. Config.FormatCash(cost) .. " for " .. name .. "!")
		return
	end
	data.Cash -= cost
	if kind == "Base" then
		-- Walls and floor always go up together.
		data.WallLevel += 1
		data.Stories = data.WallLevel
	elseif kind == "Vault" then
		data.VaultLevel += 1
	else
		data.LockLevel += 1
	end
	applyBaseLevels(plot, session)
	notify(player, "Upgraded: " .. name .. "!")
	addQuestProgress(player, "Upgrade", 1)
	push(player)
end

for _, plot in plots do
	updateVipPedestals(plot)


	plot.Parts.CollectPad.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local session = player and sessions[player]
		if not player or not session or plot.Owner ~= player then
			return
		end
		local now = os.clock()
		if now - session.LastCollect < 0.5 or plot.Pending < 1 then
			return
		end
		session.LastCollect = now
		local amount = math.floor(plot.Pending)
		plot.Pending -= amount
		session.Data.Cash += amount
		plot.Parts.PendingLabel.Text = "COLLECT\n$0"
		push(player)
		addQuestProgress(player, "Collect", 1)
	end)

	plot.Parts.LockPad.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local session = player and sessions[player]
		if not player or not session or plot.Owner ~= player then
			return
		end
		local now = os.clock()
		if now < plot.LockedUntil then
			return
		end
		if now < plot.CooldownUntil then
			if now - session.LastHint > 2 then
				session.LastHint = now
				notify(player, string.format("Lock recharging: %ds", math.ceil(plot.CooldownUntil - now)))
			end
			return
		end
		lockBase(plot)
		addQuestProgress(player, "Lock", 1)
	end)

	-- The door button: lock now (same as the lock pad) or open the door early.
	-- Opening early starts the usual recharge, so it can't stretch a lock out.
	-- With the Infinite Laser Door it simply opens and closes.
	local lockPrompt = plot.Parts.LockButton:FindFirstChildOfClass("ProximityPrompt")
	if lockPrompt then
		lockPrompt.Triggered:Connect(function(player)
			local session = sessions[player]
			if not session or not session.Loaded or plot.Owner ~= player then
				return
			end
			local now = os.clock()
			local infinite = hasInfiniteLock(session)
			if now < plot.LockedUntil then
				plot.LockedUntil = now
				plot.CooldownUntil = if infinite then now else now + Config.LockCooldown
				plot.DoorOpen = infinite
				setLaser(plot, false)
				notify(player, "Door open! Press again to lock it.")
			elseif infinite then
				plot.DoorOpen = false
				applyInfiniteLock(plot, session)
				notify(player, "Locked forever again!")
			elseif now < plot.CooldownUntil then
				notify(player, string.format("Lock recharging: %ds", math.ceil(plot.CooldownUntil - now)))
			else
				lockBase(plot)
				addQuestProgress(player, "Lock", 1)
				notify(player, "Base locked!")
			end
		end)
	end

	local function onLaserTouched(beam: BasePart, hit: BasePart)
		if os.clock() >= plot.LockedUntil or not beam:GetAttribute("Active") then
			return
		end
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		if not player or player == plot.Owner then
			return
		end
		local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
			notify(player, "ZAPPED by the base laser!")
		end
	end
	for _, beam in plot.Parts.Lasers do
		beam.Touched:Connect(function(hit)
			onLaserTouched(beam, hit)
		end)
	end
end

-- Followers panel: the client sends up to 3 slot numbers from its base.
SetFollowers.OnServerEvent:Connect(function(player: Player, indexes: unknown)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session or not plot or type(indexes) ~= "table" then
		return
	end
	local chosen: { Model } = {}
	for _, index in indexes :: { any } do
		local slot = if type(index) == "number" then plot.Slots[index] else nil
		if slot and #chosen < 3 and not table.find(chosen, slot.Model) then
			table.insert(chosen, slot.Model)
		end
	end
	session.FollowerModels = chosen
	updateFollowers(player)
	push(player)
end)

-- Shard Shop counter. You have to be at the booth, like a real shop.
ShardPurchase.OnServerEvent:Connect(function(player: Player, itemId: unknown)
	local session = sessions[player]
	local hrp = getRoot(player)
	if not session or not session.Loaded or not hrp or type(itemId) ~= "string" then
		return
	end
	if (hrp.Position - world.ShopPosition).Magnitude > 35 then
		notify(player, "Go to the Shard Shop to buy that!")
		return
	end
	local item: Config.ShardItem? = nil
	for _, candidate in Config.ShardShop do
		if candidate.Id == itemId then
			item = candidate
		end
	end
	if not item then
		return
	end
	local data = session.Data
	if data.Shards < item.Cost then
		notify(player, string.format("You need %d Shards. Earn them from quests and admin abuse!", item.Cost))
		return
	end
	data.Shards -= item.Cost
	if item.Id == "CashBoost" then
		data.CashBoostUntil = math.max(os.time(), data.CashBoostUntil) + Config.CashBoostSeconds
	elseif item.Id == "InfiniteLock" then
		-- (refunded below if they already have it)
		if hasInfiniteLock(session) then
			data.Shards += item.Cost
			notify(player, "You already have the Infinite Laser Door!")
			push(player)
			return
		end
		data.InfiniteLock = true
		if session.Plot then
			applyBaseLevels(session.Plot, session)
		end
	elseif item.Id == "CashBoostBig" then
		data.CashBoostUntil = math.max(os.time(), data.CashBoostUntil) + Config.BigCashBoostSeconds
	elseif item.Id == "ServerLuck" then
		local now = workspace:GetServerTimeNow()
		local current = ReplicatedStorage:GetAttribute("LuckEndsAt") :: number? or 0
		ReplicatedStorage:SetAttribute("LuckEndsAt", math.max(now, current) + Config.ServerLuckDuration)
		Announce:FireAllClients("luck", player.DisplayName, "")
	end
	notify(player, "Bought " .. item.Name .. "!")
	push(player)
end)

-- Codes from the box at the bottom of the shop, once per player: the ones in
-- Config.Codes, plus the ones Corny makes in-game (saved for every server).
local CodeList: RemoteEvent = makeRemote("RemoteEvent", "CodeList")
local CODES_TOPIC = "BrainrotHeistCodes"
local codeStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotHeistCodes")
	end)
	if ok then
		codeStore = result
	end
end
-- CODE -> its rewards. Kept in sync with the DataStore.
local liveCodes: { [string]: Config.Code } = {}

local function cleanCode(text: string): string
	return string.sub(string.upper((string.gsub(text, "[^%w]", ""))), 1, 20)
end

local function sanitizeCodes(raw: any): { [string]: Config.Code }
	local out: { [string]: Config.Code } = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, info in raw do
		if type(key) == "string" and type(info) == "table" then
			local function amount(v: any): number?
				return if type(v) == "number" and v > 0 then v else nil
			end
			-- (Codes made before Diamonds were removed give Shards instead.)
			local shards = (amount(info.Shards) or 0) + (amount(info.Diamonds) or 0) * Config.ShardsPerOldDiamond
			out[key] = {
				Code = key,
				Cash = amount(info.Cash),
				Shards = if shards > 0 then shards else nil,
				Expires = amount(info.Expires),
			}
		end
	end
	return out
end

local function loadLiveCodes()
	local store = codeStore
	if not store then
		return
	end
	local ok, raw = pcall(function()
		return store:GetAsync("codes")
	end)
	if ok then
		liveCodes = sanitizeCodes(raw)
	end
end

-- Changes the saved codes for every server. Returns whether it saved (in a
-- Studio test that can't reach Roblox, it still works in that server).
local function changeLiveCodes(change: ({ [string]: Config.Code }) -> ()): boolean
	local store = codeStore
	local saved = false
	if store then
		saved = pcall(function()
			store:UpdateAsync("codes", function(raw)
				local codes = sanitizeCodes(raw)
				change(codes)
				return codes
			end)
		end)
	end
	if saved then
		loadLiveCodes()
		pcall(function()
			MessagingService:PublishAsync(CODES_TOPIC, "changed")
		end)
	else
		change(liveCodes)
	end
	return saved
end

task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(CODES_TOPIC, function()
			loadLiveCodes()
		end)
	end)
	while true do
		loadLiveCodes()
		task.wait(60)
	end
end)

-- Admin lock: Corny's switch that takes the admin panel away from everyone
-- else (Ace and the mods too). Saved, and shared with every server.
local ADMIN_LOCK_TOPIC = "BrainrotHeistAdminLock"
local adminsLocked = false
ReplicatedStorage:SetAttribute("AdminsLocked", false)
adminsLockedNow = function(): boolean
	return adminsLocked
end

local function setAdminsLocked(locked: boolean)
	if adminsLocked == locked then
		return
	end
	adminsLocked = locked
	ReplicatedStorage:SetAttribute("AdminsLocked", locked)
	for player in sessions do
		push(player)
	end
end

local function loadAdminLock()
	local store = codeStore
	if not store then
		return
	end
	local ok, raw = pcall(function()
		return store:GetAsync("AdminsLocked")
	end)
	if ok then
		setAdminsLocked(raw == true)
	end
end

local function saveAdminLock(locked: boolean): boolean
	setAdminsLocked(locked)
	local store = codeStore
	local saved = store ~= nil and pcall(function()
		(store :: DataStore):SetAsync("AdminsLocked", locked)
	end)
	if saved then
		pcall(function()
			MessagingService:PublishAsync(ADMIN_LOCK_TOPIC, locked)
		end)
	end
	return saved
end

task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(ADMIN_LOCK_TOPIC, function(packet)
			setAdminsLocked(packet.Data == true)
		end)
	end)
	while true do
		loadAdminLock()
		task.wait(60)
	end
end)

local function rewardText(code: Config.Code): string
	local got = {}
	if code.Cash then
		table.insert(got, Config.FormatCash(code.Cash))
	end
	if code.Shards then
		table.insert(got, code.Shards .. " Shards")
	end
	return table.concat(got, " + ")
end

-- Sends Corny the list of codes made in-game (for the admin panel).
local function sendCodeList(player: Player)
	local list = {}
	for key, code in liveCodes do
		table.insert(list, { Code = key, Reward = rewardText(code), Expires = code.Expires or 0 })
	end
	table.sort(list, function(x, y)
		return x.Code < y.Code
	end)
	CodeList:FireClient(player, list)
end

local lastCodeTry: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastCodeTry[player] = nil
end)
RedeemCode.OnServerInvoke = function(player: Player, typed: unknown): (boolean, string)
	local session = sessions[player]
	if not session or not session.Loaded or type(typed) ~= "string" then
		return false, "Try again in a moment."
	end
	local now = os.clock()
	if now - (lastCodeTry[player] or 0) < 2 then
		return false, "Slow down a little!"
	end
	lastCodeTry[player] = now
	local wanted = cleanCode(typed)
	local code: Config.Code? = liveCodes[wanted]
	for _, fixed in Config.Codes do
		if cleanCode(fixed.Code) == wanted then
			code = fixed
		end
	end
	if not code then
		return false, "That code doesn't work."
	end
	if code.Expires and os.time() > code.Expires then
		return false, "That code has expired."
	end
	local data = session.Data
	if table.find(data.Codes, wanted) then
		return false, "You already used that code."
	end
	table.insert(data.Codes, wanted)
	data.Cash += code.Cash or 0
	data.Shards += code.Shards or 0
	push(player)
	return true, "Code redeemed! You got " .. rewardText(code) .. "!"
end

-- Wall skins: buy with Shards, or equip one you own.
SkinAction.OnServerEvent:Connect(function(player: Player, action: unknown, skinId: unknown)
	local session = sessions[player]
	local skin = if type(skinId) == "string" then Config.GetWallSkin(skinId) else nil
	if not session or not session.Loaded or not skin then
		return
	end
	local data = session.Data
	-- Founder-only skins (Corny Gold): only that founder can claim or wear
	-- it. Checked here on the server, so nobody else can get it.
	if not Config.CanUseSkin(skin, session.FounderId, session.Roles) then
		notify(player, string.format("Only %s can use %s!", skin.FounderOnly or ((skin.RoleOnly or "") .. "s"), skin.Name))
		return
	end
	if action == "Buy" and Config.IsExclusiveSkin(skin) and not table.find(data.Skins, skin.Id) then
		table.insert(data.Skins, skin.Id)
		notify(player, "Claimed " .. skin.Name .. "!")
	elseif action == "Buy" and not table.find(data.Skins, skin.Id) then
		local needed = Config.MissingSkinRequirement(skin, data.Skins)
		if needed then
			notify(player, string.format("Unlock %s first!", needed.Name))
			return
		end
		if data.Shards < skin.Cost then
			notify(player, string.format("You need %d Shards for %s.", skin.Cost, skin.Name))
			return
		end
		data.Shards -= skin.Cost
		table.insert(data.Skins, skin.Id)
		notify(player, "Unlocked " .. skin.Name .. "!")
	elseif not table.find(data.Skins, skin.Id) then
		return
	end
	data.Skin = skin.Id
	if session.Plot then
		applyBaseLevels(session.Plot, session)
	end
	push(player)
end)

-- The upgrades panel. You have to be at your base's upgrade post.
RequestUpgrade.OnServerEvent:Connect(function(player: Player, kind: unknown)
	local session = sessions[player]
	local plot = session and session.Plot
	local hrp = getRoot(player)
	if not plot or not hrp or type(kind) ~= "string" then
		return
	end
	if (hrp.Position - plot.Parts.UpgradePost.Position).Magnitude > 25 then
		notify(player, "Go to the upgrade post in your base!")
		return
	end
	onUpgrade(player, plot, kind)
end)

-- Event statues -------------------------------------------------------------
-- Big spinning statues of the current event brainrot and the next one, side
-- by side next to the Shard Shop. Tapping one buys it (same safe
-- reserve-then-prompt flow as the shop).

local function buildEventStatue(itemId: string, folderName: string, base: Vector3)
	local brainrot = Config.GetBrainrot(itemId)
	local item = Config.LimitedItems[itemId]
	if brainrot and item then
		local folder = Instance.new("Model")
		folder.Name = folderName
		folder.Parent = workspace:FindFirstChild("BrainrotHeist")
		local gold = Color3.fromRGB(255, 200, 60)
		local rarityColor = Config.Rarities[brainrot.Rarity].Color

		local function part(name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Shape = shape
			p.Anchored = true
			p.Size = size
			p.CFrame = cframe
			p.Color = color
			p.Material = material
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = folder
			return p
		end
		-- Small round gold plinth with a glowing ring and a marble column (it sits
		-- right beside the shop tent, so it stays compact)
		part("Plinth", Enum.PartType.Cylinder, Vector3.new(1.5, 9, 9), CFrame.new(base + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.pi / 2), gold, Enum.Material.Foil)
		local ring = part("GlowRing", Enum.PartType.Cylinder, Vector3.new(0.3, 9.6, 9.6), CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), rarityColor, Enum.Material.Neon)
		ring.CanCollide = false
		part("Column", Enum.PartType.Cylinder, Vector3.new(4, 5.5, 5.5), CFrame.new(base + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 240, 250), Enum.Material.Marble)

		local statue = BrainrotModel.Create(brainrot, nil, CFrame.new(base + Vector3.new(0, 5.5, 0)) * CFrame.Angles(0, math.pi, 0), false, nil, false, 1.8)
		local tag = statue.PrimaryPart and statue.PrimaryPart:FindFirstChild("Tag")
		if tag then
			tag:Destroy()
		end
		statue.Name = "Statue"
		statue.Parent = folder
		local root = statue.PrimaryPart :: BasePart
		root:SetAttribute("SpinCenter", root.CFrame)
		root:SetAttribute("SpinSpeed", 0.5)
		CollectionService:AddTag(root, "Spinner")

		-- Big invisible box around it to tap / click.
		local hitbox = part("BuyHitbox", Enum.PartType.Block, Vector3.new(9, 18, 9), CFrame.new(base + Vector3.new(0, 10, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		hitbox.Transparency = 1
		hitbox.CanCollide = false
		hitbox:SetAttribute("ItemId", brainrot.Id)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 80
		click.Parent = hitbox
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyEventPrompt"
		prompt.ActionText = "Buy (R$ " .. item.PriceRobux .. ")"
		prompt.ObjectText = brainrot.DisplayName
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", "BuyEvent")
		prompt:SetAttribute("ItemId", brainrot.Id)
		prompt.Parent = hitbox

		-- Live stock sign above it.
		local signGui = Instance.new("BillboardGui")
		signGui.Size = UDim2.fromScale(13, 6.5)
		signGui.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
		signGui.MaxDistance = 400
		signGui.LightInfluence = 0
		signGui.Adornee = hitbox
		signGui.Parent = hitbox
		local sign = Instance.new("TextLabel")
		sign.BackgroundTransparency = 1
		sign.Size = UDim2.fromScale(1, 1)
		sign.Font = Enum.Font.FredokaOne
		sign.TextScaled = true
		sign.TextColor3 = rarityColor
		sign.TextStrokeTransparency = 0
		sign.Parent = signGui
		local function updateSign()
			local left = ReplicatedStorage:GetAttribute("LimitedLeft_" .. brainrot.Id) :: number?
			local stock = if left then left else item.Stock
			-- The stock always shows, even before she's on sale.
			local nextAt = ReplicatedStorage:GetAttribute("LimitedNextUpdate") :: number?
			sign.Text = string.format(
				"%s\n%s\n%s\nStock updates in %s\n%s",
				if Config.LimitedOnSale(item) then "LIMITED EVENT" else "NEXT EVENT",
				brainrot.DisplayName,
				if stock <= 0 then "SOLD OUT" else string.format("%d / %d LEFT", stock, item.Stock),
				Config.StockCountdown(nextAt, os.time()),
				if not Config.LimitedOnSale(item) then "Coming soon!"
					elseif Config.MutationAllowed(brainrot, "Magic") then string.format("R$ %d  -  1%% MAGIC!", item.PriceRobux)
					else string.format("R$ %d", item.PriceRobux)
			)
		end
		-- Ticks every second for the countdown.
		task.spawn(function()
			while folder.Parent do
				updateSign()
				task.wait(1)
			end
		end)
	end
end

buildEventStatue(Config.CurrentEvent, "EventStatue", world.StatuePosition)
if Config.NextEvent ~= Config.CurrentEvent then
	buildEventStatue(Config.NextEvent, "NextEventStatue", world.NextStatuePosition)
end

-- Conveyor -----------------------------------------------------------------

local conveyorTweens: { [Model]: Tween } = {}

local function onBuy(player: Player, model: Model, brainrot: Config.Brainrot, mutation: string?)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session or not session.Loaded or not plot or model:GetAttribute("Sold") then
		return
	end
	local hrp = getRoot(player)
	local root = model.PrimaryPart :: BasePart
	if not hrp or (hrp.Position - root.Position).Magnitude > 20 then
		return
	end
	local price = Config.PriceOf(brainrot, mutation)
	if session.Data.Cash < price then
		notify(player, "You need " .. Config.FormatCash(price) .. " for " .. fullName(brainrot, mutation) .. "!")
		return
	end
	local index = freeSlot(plot, session)
	if not index then
		notify(player, "Your base is full! Sell a brainrot or rebirth.")
		return
	end

	model:SetAttribute("Sold", true)
	local tween = conveyorTweens[model]
	if tween then
		tween:Cancel()
		conveyorTweens[model] = nil
	end
	session.Data.Cash -= price
	placeBrainrot(plot, index, brainrot.Id, mutation, model, true)
	notify(player, (if price <= 0 then "Got a free " else "Bought ") .. fullName(brainrot, mutation) .. "! It's walking to your base.")
	local order = Config.Rarities[brainrot.Rarity].Order
	-- Free ones don't count toward buying quests (no farming them).
	if price > 0 then
		addQuestProgress(player, "Buy", 1)
	end
	if order >= 3 then
		addQuestProgress(player, "BuyEpic", 1)
	end
	if order >= 4 then
		addQuestProgress(player, "BuyLegendary", 1)
	end
	if mutation then
		addQuestProgress(player, "BuyMutated", 1)
	end
	if isNotable(brainrot, mutation) then
		Announce:FireAllClients("buy", player.DisplayName, brainrot.Id, "", mutation)
	end
	push(player)
end

local function spawnOnConveyor(forced: Config.Brainrot?, forcedMutation: string?)
	local luck = luckMultiplier()
	local brainrot = forced or Config.RollConveyor(rng, luck, adminAbuseLive())
	local mutation = if forced then forcedMutation else Config.RollMutation(rng, luck, nightBoost())
	local start = CFrame.lookAt(world.ConveyorStart, world.ConveyorEnd)
	local model = BrainrotModel.Create(brainrot, mutation, start, true)
	local root = model.PrimaryPart :: BasePart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	local price = Config.PriceOf(brainrot, mutation)
	prompt.ActionText = if price <= 0 then "Take (FREE)" else "Buy " .. Config.FormatCash(price)
	prompt.ObjectText = fullName(brainrot, mutation)
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "Buy")
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		onBuy(player, model, brainrot, mutation)
	end)

	model.Parent = world.ConveyorFolder

	local finish = CFrame.lookAt(world.ConveyorEnd, world.ConveyorEnd + start.LookVector) * CFrame.new(0, 0.5, 0)
	local tween = TweenService:Create(root, TweenInfo.new(Config.ConveyorTravelTime, Enum.EasingStyle.Linear), { CFrame = finish })
	conveyorTweens[model] = tween
	tween.Completed:Connect(function(state)
		conveyorTweens[model] = nil
		if state == Enum.PlaybackState.Completed and not model:GetAttribute("Sold") then
			model:Destroy()
		end
	end)
	tween:Play()

	local mutationInfo = Config.GetMutation(mutation)
	if Config.Rarities[brainrot.Rarity].Announce or (mutationInfo and mutationInfo.Chance <= 0.6) then
		Announce:FireAllClients("spawn", "", brainrot.Id, "", mutation)
	end
end

-- Keeps the conveyor going forever: if one spawn ever fails, it's logged
-- (server console) and the next one still comes.
-- Every Config.FreeConveyorEvery-th brainrot is a free one, so new players
-- can always grab something to start making money.
local spawnCount = 0
task.spawn(function()
	while true do
		spawnCount += 1
		local ok, err = pcall(function()
			local free = if spawnCount % Config.FreeConveyorEvery == 0 then Config.RollFree(rng) else nil
			if free then
				spawnOnConveyor(free, Config.RollMutation(rng, 1, nightBoost()))
			else
				spawnOnConveyor()
			end
		end)
		if not ok then
			warn("[BrainrotHeist] Conveyor spawn failed:", err)
		end
		task.wait(Config.ConveyorSpawnInterval)
	end
end)

-- Slap tool ----------------------------------------------------------------

local function onSlap(player: Player, tool: Tool)
	local session = sessions[player]
	local hrp = getRoot(player)
	if not session or not hrp then
		return
	end
	local now = os.clock()
	if now - session.LastSlap < Config.SlapCooldown then
		return
	end
	session.LastSlap = now

	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool

	for _, other in Players:GetPlayers() do
		if other ~= player then
			local otherRoot = getRoot(other)
			if otherRoot then
				local offset = otherRoot.Position - hrp.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if offset.Magnitude <= Config.SlapRange and flat.Magnitude > 0.01 and hrp.CFrame.LookVector:Dot(flat.Unit) > 0.2 then
					local knockback = Instance.new("BodyVelocity")
					knockback.MaxForce = Vector3.new(1, 1, 1) * 1e5
					knockback.Velocity = flat.Unit * Config.SlapForce + Vector3.new(0, 35, 0)
					knockback.Parent = otherRoot
					Debris:AddItem(knockback, 0.2)

					local carry = carries[other]
					if carry then
						returnCarry(carry, player.DisplayName .. " slapped you! The brainrot ran home.")
						notify(player, "You saved the brainrot!")
						addQuestProgress(player, "Slap", 1)
					end
				end
			end
		end
	end
end

-- Corny's hammer --------------------------------------------------------------
-- Only Config.HammerOwner (Corny) gets it. A swing flings everyone in front
-- of him, spinning, with a shockwave. It doesn't ban or hurt anyone.

local lastHammer: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastHammer[player] = nil
end)

local function hammerShockwave(position: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "HammerShockwave"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 60, 60)
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 26, 26), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)
end

-- Sends someone flying (and spinning) away along `direction`.
local function hammerFling(other: Player, otherRoot: BasePart, direction: Vector3, by: Player)
	-- Drop what they're carrying first (it runs home).
	local carry = carries[other]
	if carry then
		returnCarry(carry, by.DisplayName .. "'s hammer sent you flying!")
	end
	-- They tumble (sit) so they cartwheel through the air, then land.
	local humanoid = otherRoot.Parent and otherRoot.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = true
	end
	local fling = Instance.new("BodyVelocity")
	fling.MaxForce = Vector3.one * 1e6
	fling.Velocity = direction * Config.HammerForce + Vector3.new(0, Config.HammerLift, 0)
	fling.Parent = otherRoot
	Debris:AddItem(fling, 0.35)
	local spin = Instance.new("BodyAngularVelocity")
	spin.MaxTorque = Vector3.one * 1e6
	spin.AngularVelocity = Vector3.new(rng:NextNumber(-45, 45), rng:NextNumber(-45, 45), rng:NextNumber(-45, 45))
	spin.Parent = otherRoot
	Debris:AddItem(spin, 1.0)
	-- A burst of sparks where they got hit.
	local burst = Instance.new("Attachment")
	burst.Parent = otherRoot
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 80, 60), Color3.fromRGB(255, 220, 90))
	sparks.LightEmission = 1
	sparks.Speed = NumberRange.new(15, 30)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Size = NumberSequence.new(0.6, 0)
	sparks.Rate = 0
	sparks.Parent = burst
	sparks:Emit(40)
	Debris:AddItem(burst, 1)
end

-- SLAM: the hammer's super move. A red shockwave races across the whole
-- map from Corny and flings every other player sky-high.
local lastSlam: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastSlam[player] = nil
end)
local function hammerSlam(player: Player, hrp: BasePart)
	local center = hrp.Position - Vector3.new(0, 2.8, 0)
	for k = 0, 2 do
		local ring = Instance.new("Part")
		ring.Name = "HammerSlamWave"
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = if k == 1 then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(255, 50, 50)
		ring.Size = Vector3.new(0.4 + k * 0.3, 4, 4)
		ring.CFrame = CFrame.new(center + Vector3.new(0, 0.4 + k * 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.15
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(1.6 + k * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, 900, 900), Transparency = 1 }):Play()
		Debris:AddItem(ring, 2.4)
	end
	local founder = founderOf(player)
	Announce:FireAllClients("slam", if founder then founder.Name else player.DisplayName, "")
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= player then getRoot(other) else nil
		if otherRoot then
			local flat = Vector3.new(otherRoot.Position.X - center.X, 0, otherRoot.Position.Z - center.Z)
			local away = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
			-- The wave reaches farther players a little later.
			task.delay(math.min(1.2, flat.Magnitude / 400), function()
				if otherRoot.Parent then
					hammerFling(other, otherRoot, away, player)
				end
			end)
		end
	end
end

HammerPower.OnServerEvent:Connect(function(player: Player, power: unknown)
	local founder = founderOf(player)
	local character = player.Character
	local hrp = getRoot(player)
	-- Only Corny, with the hammer in his hand.
	if power ~= "Slam" or not founder or founder.Id ~= Config.HammerOwner or not hrp or not character or not character:FindFirstChild("Ban Hammer") then
		return
	end
	local now = os.clock()
	if now - (lastSlam[player] or 0) < Config.HammerSlamCooldown then
		notify(player, string.format("SLAM recharging: %ds", math.ceil(Config.HammerSlamCooldown - (now - (lastSlam[player] or 0)))))
		return
	end
	lastSlam[player] = now
	hammerSlam(player, hrp)
end)

-- The crack in the ground: glowing segments race forward from the hammer,
-- and anyone standing where it passes takes damage and is flung aside.
local function hammerLine(player: Player, origin: Vector3, direction: Vector3, alreadyHit: { [Player]: boolean })
	local step = 3
	local floorY = origin.Y
	for distance = 2, Config.HammerLineLength, step do
		local center = origin + direction * distance
		local crack = Instance.new("Part")
		crack.Name = "HammerCrack"
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CanTouch = false
		crack.Material = Enum.Material.Neon
		crack.Color = if distance % (step * 2) < step then Color3.fromRGB(255, 50, 50) else Color3.fromRGB(255, 140, 40)
		crack.Size = Vector3.new(2.4, 0.3, step + 0.4)
		crack.CFrame = CFrame.lookAt(center, center + direction) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0)
		crack.Parent = workspace
		TweenService:Create(crack, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.6, 0.1, step) }):Play()
		Debris:AddItem(crack, 1.3)

		for _, other in Players:GetPlayers() do
			local otherRoot = if other ~= player and not alreadyHit[other] then getRoot(other) else nil
			if otherRoot then
				local offset = otherRoot.Position - origin
				local along = offset:Dot(direction)
				local flatOffset = Vector3.new(offset.X, 0, offset.Z)
				local sideways = (flatOffset - direction * along).Magnitude
				local high = otherRoot.Position.Y - floorY
				if along >= distance - step and along <= distance + step / 2 and sideways <= Config.HammerLineWidth and high > -2 and high < 8 then
					alreadyHit[other] = true
					local humanoid = otherRoot.Parent and otherRoot.Parent:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid:TakeDamage(Config.HammerLineDamage)
					end
					-- Knocked off the line, to whichever side they were on.
					local side = flatOffset - direction * along
					local away = if side.Magnitude > 0.1 then side.Unit else Vector3.new(-direction.Z, 0, direction.X)
					hammerFling(other, otherRoot, (away + direction).Unit, player)
				end
			end
		end
		task.wait(0.025)
	end
end

local function onHammer(player: Player, tool: Tool)
	local founder = founderOf(player)
	local hrp = getRoot(player)
	if not founder or founder.Id ~= Config.HammerOwner or not hrp then
		return
	end
	local now = os.clock()
	if now - (lastHammer[player] or 0) < Config.HammerCooldown then
		return
	end
	lastHammer[player] = now

	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	local direction = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local feet = hrp.Position - Vector3.new(0, 2.8, 0)
	hammerShockwave(feet + direction * 5 + Vector3.new(0, 0.3, 0))

	-- The swing itself flings everyone close in front.
	local hit: { [Player]: boolean } = {}
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= player then getRoot(other) else nil
		if otherRoot then
			local offset = otherRoot.Position - hrp.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if offset.Magnitude <= Config.HammerRange and flat.Magnitude > 0.01 and direction:Dot(flat.Unit) > 0 then
				hit[other] = true
				hammerFling(other, otherRoot, flat.Unit, player)
			end
		end
	end
	task.spawn(hammerLine, player, feet + Vector3.new(0, 0.15, 0), direction, hit)
end

local function giveHammer(player: Player)
	local founder = founderOf(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not founder or founder.Id ~= Config.HammerOwner or not backpack or backpack:FindFirstChild("Ban Hammer") then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "Ban Hammer"
	tool.ToolTip = "Swing to fling. Also: FLY, SUPER SPRINT and SLAM (whole map)"
	tool.CanBeDropped = false
	tool.GripPos = Vector3.new(0, -1.3, 0)
	-- The stick is the handle; the head is welded on top.
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.45, 4.2, 0.45)
	handle.Color = Color3.fromRGB(70, 45, 30)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = handle.CFrame * offset
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		p.Parent = tool
	end
	piece("Head", Vector3.new(2.8, 1.5, 1.5), CFrame.new(0, 2.3, 0), Color3.fromRGB(35, 35, 40), Enum.Material.Metal)
	piece("Band", Vector3.new(0.4, 1.6, 1.6), CFrame.new(0, 2.3, 0), Color3.fromRGB(255, 50, 50), Enum.Material.Neon)
	for _, side in { -1, 1 } do
		piece("Face", Vector3.new(0.2, 1.3, 1.3), CFrame.new(side * 1.45, 2.3, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
	end
	piece("Grip", Vector3.new(0.55, 1.2, 0.55), CFrame.new(0, -1.3, 0), Color3.fromRGB(200, 30, 30), Enum.Material.Fabric)
	tool.Activated:Connect(function()
		onHammer(player, tool)
	end)
	tool.Parent = backpack
end

local function giveSlap(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild("Slap") then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = "Slap"
	tool.ToolTip = "Slap thieves to make them drop your brainrot"
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 1.6, 2.4)
	handle.Color = Color3.fromRGB(255, 205, 160)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	tool.Activated:Connect(function()
		onSlap(player, tool)
	end)
	tool.Parent = backpack
end

-- VIP name tag -------------------------------------------------------------

-- A gold crown with red, purple and green gems floating over a VIP's head.
-- Welded to the head (massless, no collisions), so it follows them around.
local CROWN_GOLD = Color3.fromRGB(255, 190, 40)
local CROWN_GEMS = { Color3.fromRGB(235, 40, 60), Color3.fromRGB(150, 50, 230), Color3.fromRGB(40, 170, 70), Color3.fromRGB(150, 50, 230), Color3.fromRGB(235, 40, 60) }
local function vipCrown(character: Model, head: BasePart)
	local crown = Instance.new("Model")
	crown.Name = "VipCrown"
	local center = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 1.1, 0)
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Shape = shape or Enum.PartType.Block
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = crown
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local radius, points = 0.85, 5
	-- The band: short gold blocks around a ring, with a gem on each.
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		local cf = center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		piece("Band", Vector3.new(0.6, 0.45, 0.14), cf, CROWN_GOLD, Enum.Material.SmoothPlastic)
	end
	for i = 0, points - 1 do
		local angle = i / points * math.pi * 2
		local around = center * CFrame.Angles(0, angle, 0)
		-- A point rising from the band, topped with a little gold ball.
		piece("Point", Vector3.new(0.42, 0.55, 0.14), around * CFrame.new(0, 0.45, -radius) * CFrame.Angles(0, 0, math.rad(45)), CROWN_GOLD, Enum.Material.SmoothPlastic)
		piece("Tip", Vector3.one * 0.24, around * CFrame.new(0, 0.86, -radius), CROWN_GOLD, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		piece("Gem", Vector3.one * 0.26, around * CFrame.new(0, 0, -radius - 0.08), CROWN_GEMS[i + 1], Enum.Material.Neon, Enum.PartType.Ball)
	end
	crown.Parent = character
end

local function updateVipTag(player: Player)
	local session = sessions[player]
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not session or not head then
		return
	end
	local existing = head:FindFirstChild("VipTag")
	local show = session.Owns.VIP == true and not session.Data.Settings.HideVip
	if not show then
		-- Hidden from the settings panel (or no VIP): take both off.
		if existing then
			existing:Destroy()
		end
		local crown = character and character:FindFirstChild("VipCrown")
		if crown then
			crown:Destroy()
		end
	elseif not existing then
		vipCrown(character :: Model, head)
		local gui = Instance.new("BillboardGui")
		gui.Name = "VipTag"
		gui.Size = UDim2.fromScale(2.2, 0.7)
		gui.StudsOffset = Vector3.new(0, 3.6, 0)
		gui.MaxDistance = 80
		gui.Parent = head
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(255, 210, 60)
		l.TextStrokeTransparency = 0
		l.Text = "VIP"
		l.Parent = gui
	end
end

-- Settings panel: hide the VIP crown/tag, music volume. Both are saved.
ChangeSetting.OnServerEvent:Connect(function(player: Player, key: unknown, value: unknown)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	local settings = session.Data.Settings
	if key == "HideVip" and type(value) == "boolean" then
		settings.HideVip = value
		updateVipTag(player)
	elseif key == "MusicVolume" and type(value) == "number" and value == value then
		settings.MusicVolume = math.clamp(value, 0, 1)
	else
		return
	end
	push(player)
end)

-- Player lifecycle ---------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.1)
	if player.Character ~= character then
		return
	end
	local session = sessions[player]
	local plot = session and session.Plot
	if plot then
		character:PivotTo(plot.Parts.SpawnCFrame)
	end
	giveSlap(player)
	giveHammer(player)
	updateVipTag(player)
	applyMovement(player)
end

local function checkAdmin(player: Player): boolean
	-- The founders (Corny and Ace) are always admins.
	if RunService:IsStudio() or table.find(Config.AdminUserIds, player.UserId) or founderOf(player) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroupAsync(game.CreatorId)
	end)
	return ok and rank >= Config.AdminGroupRank
end

local function load(player: Player)
	local session: Session = {
		Data = defaultData(),
		Loaded = false,
		Plot = nil,
		Owns = {},
		Leaderstats = nil,
		LastSlap = 0,
		LastHint = 0,
		LastCollect = 0,
		IsAdmin = false,
		FullAdmin = false,
		IsFounder = false,
		FounderId = "",
		Roles = {},
		NoSave = false,
		LastLimitedTry = 0,
		FollowerModels = {},
	}
	sessions[player] = session

	if store then
		local key = "Player_" .. player.UserId
		local ok, result = false, nil
		for attempt = 1, 3 do
			ok, result = pcall(function()
				return store:GetAsync(key)
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
		if not ok and RunService:IsStudio() then
			-- Testing in Studio without a connection to Roblox (or with API
			-- access off): play with fresh data and never save it.
			warn("[BrainrotHeist] Couldn't load data in Studio, testing without saving:", result)
			session.NoSave = true
			task.delay(5, notify, player, "Studio test: your data couldn't load, so nothing will save this time.")
		elseif not ok then
			-- Don't risk overwriting real progress with a fresh save.
			sessions[player] = nil
			player:Kick("Could not load your data. Please rejoin.")
			return
		end
		if ok then
			session.Data = sanitize(result)
		end
	end

	for _, pass in Config.GamePasses do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns then
				session.Owns[pass.Key] = true
			end
		end
	end

	session.IsAdmin = checkAdmin(player)
	-- Mods listed in Config.AdminUserIds get the small mod panel; founders,
	-- the owner and Studio testing get the full one.
	session.FullAdmin = session.IsAdmin and (RunService:IsStudio() or founderOf(player) ~= nil or not table.find(Config.AdminUserIds, player.UserId))
	local founder = founderOf(player)
	session.IsFounder = founder ~= nil
	session.FounderId = if founder then founder.Id else ""
	session.Roles = {
		Mod = session.IsAdmin,
		Tester = session.IsAdmin or table.find(Config.TesterUserIds, player.UserId) ~= nil,
		VIP = session.Owns.VIP == true,
	}
	-- A founder-only skin is only ever on its founder's base.
	local equipped = Config.GetWallSkin(session.Data.Skin)
	if equipped and not Config.CanUseSkin(equipped, session.FounderId, session.Roles) then
		session.Data.Skin = "Classic"
	end

	if not player.Parent then
		sessions[player] = nil
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Cash", "Steals", "Rebirths" } do
		local value = Instance.new(if name == "Cash" then "StringValue" else "IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
	session.Leaderstats = leaderstats

	session.Loaded = true
	assignPlot(player, session)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	push(player)
	task.spawn(deliverOwnedLimited, player)
end

-- Bans -------------------------------------------------------------------------
-- Admin panel Kick / Ban / Unban (Roblox's own chat commands don't work in
-- this game). Bans are saved in our own DataStore, checked when anyone
-- joins, and pushed to every server; Roblox's ban list is used too when the
-- game is published (it can't run in Studio).
local BAN_TOPIC = "BrainrotHeistBans"
local banStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotHeistBans")
	end)
	if ok then
		banStore = result
	end
end
local bannedHere: { [number]: boolean } = {} -- this server's copy, in case saving fails

local function banReason(raw: any): string
	return if type(raw) == "table" and type(raw.Reason) == "string" and raw.Reason ~= "" then raw.Reason else "You are banned from this game."
end

-- Kicks the player if they're banned. Runs when they join.
local function enforceBan(player: Player)
	if bannedHere[player.UserId] then
		player:Kick("You are banned from this game.")
		return
	end
	local store = banStore
	if not store then
		return
	end
	local ok, raw = pcall(function()
		return store:GetAsync("u_" .. player.UserId)
	end)
	if ok and raw ~= nil and player.Parent then
		player:Kick(banReason(raw))
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(enforceBan, player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	load(player)
end)

task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(BAN_TOPIC, function(packet)
			local userId = tonumber(packet.Data)
			local player = userId and Players:GetPlayerByUserId(userId)
			if userId then
				bannedHere[userId] = true
			end
			if player then
				player:Kick("You are banned from this game.")
			end
		end)
	end)
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	task.spawn(load, player)
end

local function cashOutPending(session: Session)
	local plot = session.Plot
	if plot then
		session.Data.Cash += math.floor(plot.Pending)
		plot.Pending = 0
	end
end

Players.PlayerRemoving:Connect(function(player)
	local carry = carries[player]
	if carry then
		returnCarry(carry, nil)
	end
	local session = sessions[player]
	if session then
		cashOutPending(session)
		save(player)
		if session.Plot then
			releasePlot(session.Plot)
		end
	end
	sessions[player] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	-- Everyone sees the "GAME UPDATING!" screen (UpdateNotice.client) while
	-- their progress saves, then gets a friendly message instead of a bare
	-- "server shut down".
	local started = os.clock()
	Announce:FireAllClients("updating", "", "")
	local pending = 0
	for player, session in sessions do
		pending += 1
		cashOutPending(session)
		task.spawn(function()
			save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	-- Give the screen a few seconds to show, then send everyone off nicely.
	while os.clock() - started < Config.UpdateNoticeSeconds and os.clock() < deadline do
		task.wait(0.1)
	end
	for _, player in Players:GetPlayers() do
		player:Kick("🛠️ " .. Config.GameName .. " just got updated! Your progress is saved. Rejoin to play the new version.")
	end
end)

-- Base prompts handled in one place: the vault hatch and ladder take the
-- owner down and up, and the gold pad under a max-prestige balcony seats the
-- owner on the throne.
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	local action = prompt:GetAttribute("Action")
	if action == "EnterVault" or action == "ExitVault" then
		-- The vault hatch (in the base) and the ladder back up (in the vault).
		for _, plot in plots do
			if prompt:IsDescendantOf(plot.Parts.Model) then
				if plot.Owner ~= player then
					notify(player, "Only the owner can open this vault!")
					return
				end
				local character = player.Character
				if character and getRoot(player) and not carries[player] then
					character:PivotTo(if action == "EnterVault" then plot.Parts.VaultSpawn else plot.Parts.HatchCFrame)
				end
				return
			end
		end
		return
	end
	if action ~= "Throne" then
		return
	end
	for _, plot in plots do
		if prompt:IsDescendantOf(plot.Parts.Prestige) then
			if plot.Owner ~= player then
				notify(player, "Only the owner of this base can sit on its throne!")
				return
			end
			local seat = plot.Parts.Prestige:FindFirstChild("ThroneSeat")
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if seat and seat:IsA("Seat") and humanoid and humanoid.Health > 0 and not seat.Occupant then
				if carries[player] then
					notify(player, "Drop what you're carrying first!")
					return
				end
				(character :: Model):PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
				seat:Sit(humanoid)
			end
			return
		end
	end
end)

-- Rebirth ------------------------------------------------------------------

RequestRebirth.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	local cost = Config.RebirthCost(session.Data.Rebirths)
	if session.Data.Cash < cost then
		notify(player, "You need " .. Config.FormatCash(cost) .. " to rebirth.")
		return
	end
	local carry = carries[player]
	if carry then
		returnCarry(carry, nil)
	end
	local oldCarpet = Config.CarpetTierFor(session.Data.Rebirths)
	session.Data.Rebirths += 1
	-- Cash, floors and the base's brainrots reset; the vault (and its
	-- upgrades), lock upgrades, skins and passes stay.
	session.Data.Cash = Config.StartingCash
	session.Data.WallLevel = 1
	session.Data.Stories = 1
	local plot = session.Plot
	if plot then
		clearPlotBrainrots(plot, true)
		plot.Pending = 0
		applyBaseLevels(plot, session)
		-- Limited brainrots stay; any left on a floor that just reset move
		-- down to the ground floor.
		for index, slot in table.clone(plot.Slots) do
			local free = if isSlotUnlocked(session, index) then nil else freeSlot(plot, session)
			if free then
				plot.Slots[index] = nil
				placeBrainrot(plot, free, slot.Id, slot.Mutation, slot.Model, false, slot.Serial)
			end
		end
	end
	notify(player, string.format("REBIRTH! Your income is now x%.1f", incomeMultiplier(session)))
	if #session.Data.Vault > 0 or (plot and vaultCount(plot) > 0) then
		notify(player, "Your vault brainrots are safe!")
	end
	local newCarpet = Config.CarpetTierFor(session.Data.Rebirths)
	if newCarpet > oldCarpet then
		notify(player, "Your stairs got a new carpet: " .. Config.CarpetTiers[newCarpet].Name .. "!")
	end
	for _, step in Config.PrestigeLadder do
		if step.Rebirths == session.Data.Rebirths then
			notify(player, "Your base got cooler: " .. step.Name .. "!")
		end
	end
	Announce:FireAllClients("rebirth", player.DisplayName, "", tostring(session.Data.Rebirths))
	push(player)
	addQuestProgress(player, "Rebirth", 1)
	task.spawn(save, player)
end)

GetData.OnServerInvoke = function(player: Player)
	local session = sessions[player]
	while player.Parent and (not session or not session.Loaded) do
		task.wait(0.25)
		session = sessions[player]
	end
	if not session then
		return nil
	end
	return snapshot(session)
end

-- Admin drops --------------------------------------------------------------
-- Brainrots and cash fall from the sky onto the open ground between the
-- conveyor and the bases. First to grab them keeps them.

local dropsFolder = Instance.new("Folder")
dropsFolder.Name = "Drops"
dropsFolder.Parent = workspace:FindFirstChild("BrainrotHeist")
ReplicatedStorage:SetAttribute("AdminAbuseEndsAt", 0)
ReplicatedStorage:SetAttribute("AdminAbuseSkipUntil", 0)

local function randomDropPosition(): Vector3
	while true do
		-- Stay clear of the caves at both ends, the shop tent and the statue.
		local x = rng:NextNumber(world.ConveyorStart.X + 25, world.ConveyorEnd.X - 25)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local position = Vector3.new(x, 0.1, side * rng:NextNumber(12, 38))
		local flat = Vector3.new(1, 0, 1)
		if ((position - world.ShopPosition) * flat).Magnitude > 18 and ((position - world.StatuePosition) * flat).Magnitude > 12
			and ((position - world.NextStatuePosition) * flat).Magnitude > 12 and ((position - world.SellPosition) * flat).Magnitude > 12
		then
			return position
		end
	end
end

-- A landing spot on open ground near `point` (for things a founder drops
-- from the sky): not in a base, a cave, the shop or the statue, and inside
-- the fence.
local function dropPositionNear(point: Vector3): Vector3
	local flat = Vector3.new(1, 0, 1)
	for _ = 1, 25 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, 35)
		local position = Vector3.new(point.X + math.cos(angle) * distance, 0.1, point.Z + math.sin(angle) * distance)
		local inBase = math.abs(position.X) < 190 and math.abs(position.Z) > 62 and math.abs(position.Z) < 140
		local inCave = math.abs(position.X) > 255 and math.abs(position.Z) < 50
		local onBelt = math.abs(position.Z) < 9
		if not inBase and not inCave and not onBelt and (position * flat).Magnitude < 380
			and ((position - world.ShopPosition) * flat).Magnitude > 18
			and ((position - world.StatuePosition) * flat).Magnitude > 12
			and ((position - world.NextStatuePosition) * flat).Magnitude > 12
			and ((position - world.SellPosition) * flat).Magnitude > 12
		then
			return position
		end
	end
	return randomDropPosition()
end

-- Throws a part (a drop's root) from `from` to `to` in a high arc, like a
-- giant founder tossing it onto the map, then calls `landed`.
local function throwArc(part: BasePart, from: Vector3, to: Vector3, rotation: CFrame, landed: () -> ())
	local distance = ((to - from) * Vector3.new(1, 0, 1)).Magnitude
	local duration = math.clamp(distance / 160, 1.2, 3.2)
	local peak = math.max(from.Y, to.Y) + 30 + distance * 0.15
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not part.Parent then
			connection:Disconnect()
			return
		end
		local t = math.min((os.clock() - started) / duration, 1)
		local flat = from:Lerp(to, t)
		-- Quadratic curve through `peak` at the top
		local y = (1 - t) ^ 2 * from.Y + 2 * (1 - t) * t * (2 * peak - (from.Y + to.Y) / 2) + t ^ 2 * to.Y
		part.CFrame = CFrame.new(flat.X, y, flat.Z) * rotation * CFrame.Angles(t * 8, t * 5, 0)
		if t >= 1 then
			connection:Disconnect()
			part.CFrame = CFrame.new(to) * rotation
			landed()
		end
	end)
end

-- A random landing spot anywhere on the open map.
-- Where thrown drops (giants, UFOs) land: most of the time near a random
-- player, otherwise anywhere along the middle of the map between the bases,
-- so they spread out where people are instead of piling up on the far grass.
local function randomOpenPosition(): Vector3
	local everyone = Players:GetPlayers()
	if #everyone > 0 and rng:NextNumber() < 0.6 then
		local hrp = getRoot(everyone[rng:NextInteger(1, #everyone)])
		if hrp then
			return dropPositionNear(hrp.Position)
		end
	end
	return dropPositionNear(Vector3.new(rng:NextNumber(-230, 230), 0, rng:NextNumber(-55, 55)))
end

local function fallBeam(position: Vector3, color: Color3): BasePart
	local beam = Instance.new("Part")
	beam.Name = "DropBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Transparency = 0.6
	beam.Size = Vector3.new(0.6, 120, 0.6)
	beam.CFrame = CFrame.new(position + Vector3.new(0, 60, 0))
	beam.Parent = dropsFolder
	return beam
end

-- `from`: a giant founder's hand it's thrown from (lands anywhere on the
-- map); otherwise it falls straight down from the sky.
local function dropBrainrot(brainrot: Config.Brainrot, mutation: string?, from: Vector3?)
	local landing = if from then randomOpenPosition() else randomDropPosition()
	local facing = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model = BrainrotModel.Create(brainrot, mutation, CFrame.new(from or landing + Vector3.new(0, 90, 0)) * facing, false)
	local root = model.PrimaryPart :: BasePart
	local mutationInfo = Config.GetMutation(mutation)
	local beam = fallBeam(landing, if mutationInfo then mutationInfo.Color else Config.Rarities[brainrot.Rarity].Color)
	model.Destroying:Connect(function()
		beam:Destroy()
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "GRAB!"
	prompt.ObjectText = fullName(brainrot, mutation)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("Action", "Claim")
	prompt.Parent = root
	model.Parent = dropsFolder

	if from then
		throwArc(root, from, landing + Vector3.new(0, 0.5, 0), facing, function()
			prompt.Enabled = true
		end)
	else
		local fall = TweenService:Create(root, TweenInfo.new(2.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(landing + Vector3.new(0, 0.5, 0)) * facing,
		})
		fall.Completed:Connect(function()
			prompt.Enabled = true
		end)
		fall:Play()
	end

	prompt.Triggered:Connect(function(player)
		local session = sessions[player]
		local plot = session and session.Plot
		-- (Gone already: grabbed, or it timed out just as they pressed.)
		if not session or not plot or model:GetAttribute("Claimed") or not model.Parent then
			return
		end
		local index = freeSlot(plot, session)
		if not index then
			notify(player, "Your base is full! Sell something to grab drops.")
			return
		end
		model:SetAttribute("Claimed", true)
		prompt:Destroy()
		beam:Destroy()
		placeBrainrot(plot, index, brainrot.Id, mutation, model, true)
		notify(player, "You grabbed " .. fullName(brainrot, mutation) .. "!")
		addQuestProgress(player, "Grab", 1)
		if isNotable(brainrot, mutation) then
			Announce:FireAllClients("grab", player.DisplayName, brainrot.Id, "", mutation)
		end
		push(player)
	end)

	task.delay(Config.DropLifetime, function()
		if model.Parent == dropsFolder and not model:GetAttribute("Claimed") then
			model:Destroy()
		end
	end)
end

-- `incomeSeconds`: the bag is worth that many seconds of the grabber's own
-- income instead (at least `amount`), for founder-event bags.
local function dropCash(amount: number, from: Vector3?, incomeSeconds: number?)
	local landing = if from then randomOpenPosition() else randomDropPosition()
	local orb = Instance.new("Part")
	orb.Name = "CashDrop"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.5, 2.5, 2.5)
	orb.Anchored = true
	orb.CanCollide = false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(80, 255, 110)
	orb.CFrame = CFrame.new(from or landing + Vector3.new(0, 90, 0))
	orb.Parent = dropsFolder

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromScale(3.5, 1.1)
	tag.StudsOffset = Vector3.new(0, 2.5, 0)
	tag.MaxDistance = 250
	tag.Parent = orb
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(140, 255, 140)
	label.TextStrokeTransparency = 0
	label.Text = if incomeSeconds then "💰 CASH" else Config.FormatCash(amount)
	label.Parent = tag

	if from then
		throwArc(orb, from, landing + Vector3.new(0, 1.5, 0), CFrame.identity, function() end)
	else
		TweenService:Create(orb, TweenInfo.new(2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(landing + Vector3.new(0, 1.5, 0)),
		}):Play()
	end

	orb.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local session = player and sessions[player]
		if not player or not session or not session.Loaded or orb:GetAttribute("Taken") then
			return
		end
		orb:SetAttribute("Taken", true)
		local plot = session.Plot
		local worth = if incomeSeconds and plot then math.max(amount, math.floor(plotIncome(plot, session) * incomeSeconds)) else amount
		session.Data.Cash += worth
		orb:Destroy()
		if incomeSeconds then
			notify(player, "+" .. Config.FormatCash(worth))
		end
		push(player)
	end)
	task.delay(Config.DropLifetime, function()
		if orb.Parent then
			orb:Destroy()
		end
	end)
end

-- Founders ------------------------------------------------------------------
-- Giant founders stand just outside the fence during admin abuse (in their
-- normal avatars), doing one Roblox emote after another. Each founder also
-- has an event of their own where they hover beside the map in their event
-- outfit (Config.FounderEvents), swaying, emoting and throwing cash and
-- brainrots onto the map.

task.spawn(Founders.LoadEventLooks)
task.spawn(Founders.LoadEventMusic)
local foundersFolder = Instance.new("Folder")
foundersFolder.Name = "Founders"
foundersFolder.Parent = workspace:FindFirstChild("BrainrotHeist")
ReplicatedStorage:SetAttribute("FounderEvent", "")
ReplicatedStorage:SetAttribute("FounderEventEndsAt", 0)

-- Roblox's default emotes, played one after another.
-- Roblox's default emotes that stay in place (no dances), played one at a
-- time over the normal standing idle.
local GIANT_EMOTES = {
	"rbxassetid://507770239", -- wave
	"rbxassetid://507770677", -- cheer
	"rbxassetid://507770818", -- laugh
	"rbxassetid://507770453", -- point
}

-- Roughly where a giant's hand is, to throw things from.
local function giantHand(giant: Model): Vector3
	local root = giant.PrimaryPart :: BasePart
	local _, size = giant:GetBoundingBox()
	return root.Position + Vector3.new(0, size.Y * 0.2, 0) + root.CFrame.LookVector * size.Y * 0.12
end

-- Something a founder throws: usually a cash bag, sometimes a brainrot.
local function founderDrop(from: Vector3, brainrotChance: number, luck: number, mutations: { { Id: string, Chance: number } }?)
	if rng:NextNumber() < brainrotChance then
		local brainrot = Config.RollConveyor(rng, luck, false)
		local mutation: string? = nil
		if mutations then
			local roll = rng:NextNumber(0, 100)
			for _, entry in mutations do
				if roll < entry.Chance then
					mutation = entry.Id
					break
				end
				roll -= entry.Chance
			end
		end
		dropBrainrot(brainrot, mutation or Config.RollMutation(rng, luck, nightBoost()), from)
	else
		dropCash(Config.FounderCashDrop, from, Config.FounderCashDropSeconds)
	end
end

-- A puff of sparkles and smoke where a giant appears or leaves.
local function giantPoof(position: Vector3, size: number, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "GiantPoof"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(size * 0.4, size, size * 0.4)
	anchor.Position = position + Vector3.new(0, size / 2, 0)
	anchor.Parent = foundersFolder
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparkles.LightEmission = 1
	sparkles.Rate = 0
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Speed = NumberRange.new(size * 0.2, size * 0.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(size * 0.05, 0)
	sparkles.Parent = anchor
	sparkles:Emit(200)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(240, 240, 255))
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Rate = 0
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(size * 0.05, size * 0.15)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new(size * 0.15, size * 0.3)
	smoke.Parent = anchor
	smoke:Emit(60)
	Debris:AddItem(anchor, 3)
end

-- The lowest point of a giant's body (not its accessories), as it is now.
local function giantFeetY(giant: Model): number?
	local lowest: number? = nil
	for _, part in giant:GetDescendants() do
		if part:IsA("BasePart") and part ~= giant.PrimaryPart and part.Transparency < 1 and not part:FindFirstAncestorOfClass("Accessory") then
			local cf, size = part.CFrame, part.Size
			local extent = math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
			local bottom = cf.Position.Y - extent
			if not lowest or bottom < lowest then
				lowest = bottom
			end
		end
	end
	return lowest
end

-- Lifts or lowers the whole giant so its feet are on `groundY`, if they're
-- off by more than `tolerance` studs.
local function groundGiant(giant: Model, groundY: number, tolerance: number)
	local feet = giantFeetY(giant)
	if feet and math.abs(feet - groundY) > tolerance then
		giant:PivotTo(giant:GetPivot() + Vector3.new(0, groundY - feet, 0))
	end
end

-- Puts a giant at `spot` facing the map, with its feet at `feetY` (the
-- ground, or in the air for floating). The whole model is moved with PivotTo
-- so its body can't get left behind. Roblox finishes rebuilding a scaled-up
-- body a moment after it's made, so the feet are re-measured once it settles.
-- Returns the giant's size.
local function placeGiant(giant: Model, spot: Vector3, feetY: number): Vector3
	local root = giant.PrimaryPart :: BasePart
	local height = Founders.RootHeight(giant)
	local home = CFrame.lookAt(Vector3.new(spot.X, feetY + height, spot.Z), Vector3.new(0, feetY + height, 0))
	giant:PivotTo(home * root.CFrame:ToObjectSpace(giant:GetPivot()))
	for _ = 1, 5 do
		task.wait(0.1)
		groundGiant(giant, feetY, 0.5)
	end
	local _, size = giant:GetBoundingBox()
	return size
end

-- Re-checks a giant a few times while Roblox finishes building it: fixes
-- anything that didn't scale up, re-applies its pose and puts its feet back
-- at `feetY`.
local function settleGiant(giant: Model, feetY: number, pose: Founders.Pose?)
	for _ = 1, 3 do
		task.wait(0.4)
		if not giant.Parent then
			return
		end
		Founders.FixScale(giant)
		if pose then
			Founders.ApplyPose(giant, pose)
		end
		groundGiant(giant, feetY, 0.5)
	end
end

-- Normal standing idle underneath, and one in-place emote at a time with a
-- short pause between them, while `active()` is true.
local function startEmotes(giant: Model, emotes: { string }, active: () -> boolean)
	Founders.Play(giant, Founders.Idle, true, 1, 1, Enum.AnimationPriority.Idle)
	task.spawn(function()
		local index = rng:NextInteger(1, #emotes)
		task.wait(1)
		while giant.Parent and active() do
			local track = Founders.Play(giant, emotes[index], false, 1, 1, Enum.AnimationPriority.Action)
			index = index % #emotes + 1
			local length = if track and track.Length > 0 then track.Length else 3
			task.wait(length + rng:NextNumber(1.5, 3))
		end
	end)
end

-- A giant standing on the ground at `spot`, emoting while `active()` is true
-- (and throwing something every `dropEvery` seconds if there's a `drop`).
-- Then it vanishes in a puff.
local function runGiant(giant: Model, spot: Vector3, emotes: { string }, dropEvery: number, active: () -> boolean, drop: ((Vector3) -> ())?)
	local size = placeGiant(giant, spot, spot.Y)
	giantPoof(spot, size.Y, Color3.fromRGB(255, 220, 90))
	settleGiant(giant, spot.Y, nil)
	startEmotes(giant, emotes, active)
	local nextDrop = os.clock() + 1.5
	while giant.Parent and active() do
		if drop and os.clock() >= nextDrop then
			nextDrop = os.clock() + dropEvery * rng:NextNumber(0.7, 1.3)
			drop(giantHand(giant))
		end
		task.wait(0.1)
	end
	giantPoof(spot, size.Y, Color3.fromRGB(255, 220, 90))
	giant:Destroy()
end

-- Glides a model from one CFrame to another over `seconds` (eased), yielding.
local function glide(model: Model, from: CFrame, to: CFrame, seconds: number)
	local started = os.clock()
	while true do
		local t = math.min((os.clock() - started) / seconds, 1)
		local eased = t * t * (3 - 2 * t)
		model:PivotTo(from:Lerp(to, eased))
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

-- Admin abuse giants: just standing there, emoting.
local function spawnAbuseGiants()
	for founderId, spot in Config.FounderGiantSpots do
		task.spawn(function()
			local giant = Founders.CreateGiant(founderId, Config.FounderGiantScale, foundersFolder)
			if giant then
				runGiant(giant, spot, GIANT_EMOTES, 0, adminAbuseLive)
			end
		end)
	end
end

task.spawn(function()
	local wasLive = false
	while true do
		local live = adminAbuseLive()
		if live and not wasLive then
			spawnAbuseGiants()
		end
		wasLive = live
		task.wait(1)
	end
end)

-- Founder events
local founderEventRunning: string? = nil

local function founderEventActive(): boolean
	return workspace:GetServerTimeNow() < (ReplicatedStorage:GetAttribute("FounderEventEndsAt") :: number)
end

-- Ends the running event's night, sky, music and boosts (set by
-- runFounderEvent while one is running; safe to call more than once).
local endFounderEvent: () -> () = function() end

local function stopFounderEvent()
	-- The giants and UFOs see this and leave on their own...
	ReplicatedStorage:SetAttribute("FounderEventEndsAt", 0)
	-- ...and everything else stops right away.
	endFounderEvent()
end

local function runFounderEvent(eventId: string, minutes: number)
	local event = Config.FounderEvents[eventId]
	if not event or founderEventRunning then
		return
	end
	founderEventRunning = eventId
	-- This run is live until its time is up or it's ended (a later event
	-- never brings an earlier one's giants back).
	local ended = false
	local function active(): boolean
		return not ended and founderEventActive()
	end
	-- Everything this event builds goes in here, so it can all be cleared.
	local eventFolder = Instance.new("Folder")
	eventFolder.Name = "FounderEvent_" .. eventId
	eventFolder.Parent = foundersFolder
	-- Pick up music changed in another server since this one started.
	Founders.LoadEventMusic()
	ReplicatedStorage:SetAttribute("FounderEvent", eventId)
	ReplicatedStorage:SetAttribute("FounderEventEndsAt", workspace:GetServerTimeNow() + minutes * 60)
	Announce:FireAllClients("founder", event.Founder, "", eventId)

	-- Night falls, and one mutation is picked (by its percent chance) to be
	-- much more likely until morning.
	local dayTime = Lighting.ClockTime
	if event.Night then
		TweenService:Create(Lighting, TweenInfo.new(5, Enum.EasingStyle.Sine), { ClockTime = 0 }):Play()
		local picks = event.NightMutations
		if picks and #picks > 0 then
			local total = 0
			for _, pick in picks do
				total += pick.Chance
			end
			local roll = rng:NextNumber(0, total)
			local chosen = picks[#picks]
			for _, pick in picks do
				roll -= pick.Chance
				if roll < 0 then
					chosen = pick
					break
				end
			end
			ReplicatedStorage:SetAttribute("NightMutation", chosen.Id)
			ReplicatedStorage:SetAttribute("NightBoost", chosen.Boost)
			task.delay(7, function()
				Announce:FireAllClients("night", event.Founder, "", tostring(chosen.Boost), chosen.Id)
			end)
		end
	end

	-- One UFO on each side of the map (event.Spots), all at once. They share
	-- the throwing, so the total drop rate stays the same.
	local dropEvery = (event.DropEvery or 2) * #event.Spots
	local function drop(from: Vector3)
		founderDrop(from, event.BrainrotChance or 0.3, event.BrainrotLuck or 1, event.Mutations)
	end
	local ufoSize = event.UfoSize or 260
	local ufoHeight = event.UfoHeight or 230
	local floatHeight = event.FloatHeight or 35
	local poseId = event.PoseAnimationId or ""

	local function runUfo(spot: Vector3)
		local side = if spot.Z < 0 then -1 else 1
		-- 1. A UFO flies in from outside the map and hovers over the spot.
		local ufo = Founders.CreateUfo(ufoSize)
		local hover = CFrame.new(spot.X, ufoHeight, spot.Z)
		local arriveFrom = hover + Vector3.new(-700, 350, 420 * side)
		ufo:PivotTo(arriveFrom)
		ufo.Parent = eventFolder
		glide(ufo, arriveFrom, hover, 5)

		-- 2. The light beam switches on underneath it.
		local beamTop = Vector3.new(spot.X, ufoHeight - ufoSize * 0.14, spot.Z)
		local beam = Founders.CreateBeam(beamTop, Vector3.new(spot.X, spot.Y, spot.Z), ufoSize * 0.3, ufoSize * 0.62)
		beam.Parent = eventFolder
		for _, part in beam:GetChildren() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(1), { Transparency = Founders.BeamTransparency }):Play()
			end
		end
		task.wait(1.2)

		-- 3. The founder appears floating in the beam (in their special event
		-- outfit, not their normal avatar), holding a pose with a rainbow aura.
		local giant = Founders.CreateGiant(event.Founder, event.Scale, eventFolder, event.OutfitId)
		if giant then
			-- Their pose: an animation if one is set, otherwise the floating
			-- sage pose (set by turning their joints).
			if poseId == "" then
				Founders.ApplyPose(giant, Founders.SagePose)
			end
			local feetY = spot.Y + floatHeight
			local size = placeGiant(giant, spot, feetY)
			giantPoof(Vector3.new(spot.X, feetY, spot.Z), size.Y, event.Colors[1])
			if poseId ~= "" then
				Founders.Play(giant, poseId, true, 1, 1, Enum.AnimationPriority.Action)
			end
			settleGiant(giant, feetY, if poseId == "" then Founders.SagePose else nil)
			local aura = Founders.AddAura(giant, false)

			-- Float gently up and down in the beam, throwing things.
			local base = giant:GetPivot()
			local started = os.clock()
			local nextDrop = os.clock() + 1.5 + rng:NextNumber(0, dropEvery)
			local nextColor = 0
			while giant.Parent and active() do
				local t = os.clock() - started
				giant:PivotTo(base + Vector3.new(0, math.sin(t * 0.8) * size.Y * 0.02, 0))
				if os.clock() >= nextColor then
					nextColor = os.clock() + 0.1
					aura.OutlineColor = Color3.fromHSV((t * 0.15) % 1, 0.8, 1)
				end
				if os.clock() >= nextDrop then
					nextDrop = os.clock() + dropEvery * rng:NextNumber(0.7, 1.3)
					drop(giantHand(giant))
				end
				RunService.Heartbeat:Wait()
			end

			-- 4. Beamed back up into the UFO.
			glide(giant, giant:GetPivot(), giant:GetPivot() + Vector3.new(0, ufoHeight - feetY, 0), 2.5)
			giant:Destroy()
		else
			-- No giant (shouldn't happen): the UFO drops things itself.
			while active() do
				drop(beamTop)
				task.wait(dropEvery)
			end
		end

		-- 5. The beam switches off and the UFO flies away.
		for _, part in beam:GetChildren() do
			if part:IsA("BasePart") then
				TweenService:Create(part, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			end
			local sparkles = part:FindFirstChildOfClass("ParticleEmitter")
			if sparkles then
				sparkles.Enabled = false
			end
		end
		task.wait(0.8)
		beam:Destroy()
		glide(ufo, hover, hover + Vector3.new(700, 450, 420 * side), 4)
		ufo:Destroy()
	end

	-- Ace's style: standing in the water while the dancer brainrot (Cigna
	-- Glamourina) flies around him spinning ballet pirouettes.
	local function runBallet(spot: Vector3)
		local giant = Founders.CreateGiant(event.Founder, event.Scale, eventFolder, event.OutfitId)
		if not giant then
			return
		end
		local size = placeGiant(giant, spot, spot.Y)
		giantPoof(spot, size.Y, event.Colors[1])
		settleGiant(giant, spot.Y, {})
		local aura = Founders.AddAura(giant)
		aura.OutlineColor = event.Colors[1]

		-- Two dancers circling him, a little out of step with each other.
		local dancerInfo = event.Dancer and Config.GetBrainrot(event.Dancer)
		local dancers: { Model } = {}
		if dancerInfo then
			for i = 1, 2 do
				local dancer = BrainrotModel.Create(dancerInfo, nil, CFrame.new(spot + Vector3.new(0, size.Y * 0.5, 0)), false, nil, false, size.Y * 0.06)
				local tag = dancer.PrimaryPart and dancer.PrimaryPart:FindFirstChild("Tag")
				if tag then
					tag:Destroy()
				end
				dancer.Name = "BalletDancer" .. i
				dancer.Parent = eventFolder
				table.insert(dancers, dancer)
			end
		end

		-- Ace spins slowly on the spot like a pirouette.
		local home = giant:GetPivot()
		local root = giant.PrimaryPart :: BasePart
		local pivotToRoot = home:ToObjectSpace(root.CFrame)
		local started = os.clock()
		local nextColor = 0
		-- Cash and brainrots keep coming the whole event: Ace and his dancers
		-- take turns throwing them.
		local nextDrop = os.clock() + 2 + rng:NextNumber(0, dropEvery)
		local thrower = 0
		while giant.Parent and active() do
			local t = os.clock() - started
			if os.clock() >= nextDrop then
				nextDrop = os.clock() + dropEvery * rng:NextNumber(0.7, 1.3)
				thrower = thrower % (#dancers + 1) + 1
				local dancer = dancers[thrower]
				drop(if dancer then dancer:GetPivot().Position else giantHand(giant))
			end
			-- Turn around the root's vertical line, so he spins in place.
			local rootNow = (home * pivotToRoot) * CFrame.Angles(0, t * 1.2, 0)
			giant:PivotTo(rootNow * pivotToRoot:Inverse())
			for i, dancer in dancers do
				local phase = (i - 1) * math.pi
				local angle = t * 0.55 + phase
				local radius = size.Y * (0.5 + 0.06 * math.sin(t * 0.7 + phase))
				-- Leaps: a rise and fall every few seconds, with a slow float between.
				local height = size.Y * (0.45 + 0.2 * math.abs(math.sin(t * 0.9 + phase)))
				local position = spot + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
				-- Pirouette: spinning on the spot as it goes round, leaning into the turn.
				dancer:PivotTo(CFrame.new(position) * CFrame.Angles(0, t * 3 + phase, 0) * CFrame.Angles(0, 0, math.rad(12)))
			end
			if os.clock() >= nextColor then
				nextColor = os.clock() + 0.15
				aura.OutlineColor = event.Colors[1]:Lerp(event.Colors[3], (math.sin(t * 1.5) + 1) / 2)
			end
			RunService.Heartbeat:Wait()
		end
		for _, dancer in dancers do
			local _, dancerSize = dancer:GetBoundingBox()
			giantPoof(dancer:GetPivot().Position, dancerSize.Y, event.Colors[2])
			dancer:Destroy()
		end
		giantPoof(spot, size.Y, event.Colors[1])
		giant:Destroy()
	end

	-- 99 Nights plays differently from the other events: nothing is thrown.
	-- The deer prowls the dark; every so often it screams and HUNTS, and
	-- anyone not at a campfire when it strikes gets thrown. Survivors earn
	-- Shards, each night survived makes the server luckier, and supply
	-- chests around the map hold cash or a brainrot for whoever opens them.
	local rules = Config.Nights99
	local campfires: { Vector3 } = {}
	local hunting = false

	local function runForest(spot: Vector3)
		local deerInfo = Config.GetBrainrot("SixtySevenNights")
		if not deerInfo then
			return
		end
		local deer = BrainrotModel.Create(deerInfo, nil, CFrame.new(spot), false, nil, false, event.Scale)
		local tag = deer.PrimaryPart and deer.PrimaryPart:FindFirstChild("Tag")
		if tag then
			tag:Destroy()
		end
		deer.Name = "NightDeer"
		local root = deer.PrimaryPart :: BasePart
		local glow = Instance.new("PointLight")
		glow.Color = event.Colors[2]
		glow.Range = 60
		glow.Brightness = 2
		glow.Parent = root
		deer.Parent = eventFolder
		local _, size = deer:GetBoundingBox()
		giantPoof(spot, size.Y, event.Colors[2])

		-- A slow prowl around the spot; when it hunts it races round, glowing.
		local angle = if spot.Z < 0 then math.pi else 0
		local radius = 70
		local last = os.clock()
		local started = last
		while deer.Parent and active() do
			local now = os.clock()
			local dt = now - last
			last = now
			angle += dt * (if hunting then 0.45 else 0.1)
			glow.Brightness = if hunting then 6 else 2
			local t = now - started
			local stride = math.abs(math.sin(t * (if hunting then 6 else 2)))
			local position = spot + Vector3.new(math.cos(angle) * radius, 0.5 + stride * size.Y * 0.015, math.sin(angle) * radius)
			local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			deer:PivotTo(CFrame.lookAt(position, position + heading) * CFrame.Angles(0, 0, math.sin(t * 2) * 0.05))
			RunService.Heartbeat:Wait()
		end
		giantPoof(deer:GetPivot().Position, size.Y, event.Colors[1])
		deer:Destroy()
	end

	local function nearCampfire(position: Vector3): boolean
		for _, at in campfires do
			if ((position - at) * Vector3.new(1, 0, 1)).Magnitude <= rules.SafeRadius then
				return true
			end
		end
		return false
	end

	-- Caught out in the dark: dropped loot runs home, and they're thrown.
	local function deerCatch(player: Player, hrp: BasePart)
		local carry = carries[player]
		if carry then
			returnCarry(carry, "The deer got you!")
		end
		local humanoid = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = true
		end
		local away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		away = if away.Magnitude > 0.01 then away.Unit else Vector3.new(1, 0, 0)
		local fling = Instance.new("BodyVelocity")
		fling.MaxForce = Vector3.one * 1e6
		fling.Velocity = away * 90 + Vector3.new(0, 140, 0)
		fling.Parent = hrp
		Debris:AddItem(fling, 0.3)
		local spin = Instance.new("BodyAngularVelocity")
		spin.MaxTorque = Vector3.one * 1e6
		spin.AngularVelocity = Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(-30, 30), rng:NextNumber(-30, 30))
		spin.Parent = hrp
		Debris:AddItem(spin, 0.8)
		Announce:FireClient(player, "caught", "", "", "")
	end

	-- A supply chest on open ground. Opening it pays the opener straight
	-- away: cash (a slice of their own income) or a brainrot into their base.
	local chestCount = 0
	local function spawnChest()
		local at = randomDropPosition()
		local chest = Instance.new("Model")
		chest.Name = "SupplyChest"
		local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanCollide = false
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = material
			p.Parent = chest
			return p
		end
		local facing = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		local box = piece("ChestBox", Vector3.new(4, 2.4, 2.8), facing * CFrame.new(0, 1.2, 0), Color3.fromRGB(120, 78, 42), Enum.Material.WoodPlanks)
		piece("ChestLid", Vector3.new(4.1, 0.8, 2.9), facing * CFrame.new(0, 2.8, 0), Color3.fromRGB(100, 64, 34), Enum.Material.WoodPlanks)
		for _, x in { -1.6, 1.6 } do
			piece("ChestBand", Vector3.new(0.3, 3.3, 2.95), facing * CFrame.new(x, 1.65, 0), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
		end
		piece("ChestLock", Vector3.new(0.7, 0.8, 0.3), facing * CFrame.new(0, 2.3, -1.5), Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 90)
		light.Range = 16
		light.Brightness = 1.5
		light.Parent = box
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ChestPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = "Supply Chest"
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = box
		chest.Parent = eventFolder
		chestCount += 1
		local opened = false
		prompt.Triggered:Connect(function(player: Player)
			local session = sessions[player]
			local plot = session and session.Plot
			if opened or not session or not session.Loaded or not plot then
				return
			end
			opened = true
			chestCount -= 1
			giantPoof(at, 6, Color3.fromRGB(255, 200, 90))
			chest:Destroy()
			local index = freeSlot(plot, session)
			if index and rng:NextNumber() < rules.ChestBrainrotChance then
				local brainrot = Config.RollConveyor(rng, rules.ChestLuck, false)
				local mutation = Config.RollMutation(rng, rules.ChestLuck)
				placeBrainrot(plot, index, brainrot.Id, mutation, nil, false)
				notify(player, "Supply chest: " .. fullName(brainrot, mutation) .. " is in your base!")
			else
				local amount = math.floor(math.max(rules.ChestMinimumCash, plotIncome(plot, session) * rules.ChestIncomeSeconds))
				session.Data.Cash += amount
				notify(player, "Supply chest: +" .. Config.FormatCash(amount) .. "!")
			end
			push(player)
		end)
	end

	if event.Forest then
		ReplicatedStorage:SetAttribute("NightsSurvived", 0)
		ReplicatedStorage:SetAttribute("DeerStrikesAt", 0)
		-- Campfires around the lobby, each with a glowing ring showing how
		-- close you need to be to be safe.
		for _, at in { Vector3.new(-60, 0, 40), Vector3.new(60, 0, -40), Vector3.new(150, 0, 40), Vector3.new(-150, 0, -40), Vector3.new(0, 0, 32) } do
			table.insert(campfires, at)
			local fire = Instance.new("Model")
			fire.Name = "Campfire"
			local function piece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
				local p = Instance.new("Part")
				p.Name = name
				p.Shape = shape
				p.Anchored = true
				p.CanCollide = false
				p.Size = size
				p.CFrame = cf
				p.Color = color
				p.Material = material
				p.Parent = fire
				return p
			end
			for k = 0, 7 do
				local a = k / 8 * math.pi * 2
				piece("Stone", Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), CFrame.new(at + Vector3.new(math.cos(a) * 3, 0.5, math.sin(a) * 3)), Color3.fromRGB(110, 110, 115), Enum.Material.Slate)
			end
			for k = 0, 2 do
				piece("Log", Enum.PartType.Cylinder, Vector3.new(4.5, 0.9, 0.9), CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, k * math.pi / 3, math.rad(18)), Color3.fromRGB(95, 60, 35), Enum.Material.Wood)
			end
			local core = piece("Embers", Enum.PartType.Ball, Vector3.new(1.6, 1, 1.6), CFrame.new(at + Vector3.new(0, 0.8, 0)), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
			local ring = piece("SafeRing", Enum.PartType.Cylinder, Vector3.new(0.15, rules.SafeRadius * 2, rules.SafeRadius * 2), CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 160, 60), Enum.Material.Neon)
			ring.Transparency = 0.8
			ring.CanQuery = false
			ring.CanTouch = false
			local flames = Instance.new("Fire")
			flames.Size = 7
			flames.Heat = 12
			flames.Color = Color3.fromRGB(255, 140, 40)
			flames.SecondaryColor = Color3.fromRGB(255, 60, 20)
			flames.Parent = core
			local warm = Instance.new("PointLight")
			warm.Color = Color3.fromRGB(255, 150, 70)
			warm.Range = rules.SafeRadius + 10
			warm.Brightness = 2.5
			warm.Parent = core
			fire.Parent = eventFolder
		end

		-- Supply chests, a few at a time.
		task.spawn(function()
			while active() do
				if chestCount < rules.MaxChests then
					spawnChest()
				end
				task.wait(rules.ChestEvery)
			end
		end)

		-- The hunts.
		task.spawn(function()
			task.wait(rules.HuntEvery * 0.5)
			while active() do
				hunting = true
				ReplicatedStorage:SetAttribute("DeerStrikesAt", workspace:GetServerTimeNow() + rules.HuntWarning)
				Announce:FireAllClients("hunt", "", "", tostring(rules.HuntWarning))
				task.wait(rules.HuntWarning)
				if not active() then
					break
				end
				local nights = ((ReplicatedStorage:GetAttribute("NightsSurvived") :: number?) or 0) + 1
				for _, player in Players:GetPlayers() do
					local session = sessions[player]
					local hrp = getRoot(player)
					if session and session.Loaded and hrp then
						if nearCampfire(hrp.Position) then
							session.Data.Shards += rules.SafeShards
							notify(player, string.format("You survived night %d! +%d Shards", nights, rules.SafeShards))
							push(player)
						else
							deerCatch(player, hrp)
						end
					end
				end
				hunting = false
				ReplicatedStorage:SetAttribute("DeerStrikesAt", 0)
				ReplicatedStorage:SetAttribute("NightsSurvived", nights)
				Announce:FireAllClients("nightdone", "", "", tostring(nights), string.format("%.2f", math.min(rules.MaxLuck, 1 + rules.LuckPerNight * nights)))
				task.wait(rules.HuntEvery - rules.HuntWarning)
			end
			hunting = false
			ReplicatedStorage:SetAttribute("DeerStrikesAt", 0)
		end)
	end

	-- The guaranteed brainrot, with a rare mutation, a little after it starts.
	local guaranteed = event.Guaranteed and Config.GetBrainrot(event.Guaranteed)
	if guaranteed then
		task.delay(10, function()
			if not active() then
				return
			end
			local rare = {}
			for _, mutation in Config.Mutations do
				if mutation.Chance > 0 and mutation.Chance <= 1 and Config.MutationAllowed(guaranteed, mutation.Id) then
					table.insert(rare, mutation.Id)
				end
			end
			spawnOnConveyor(guaranteed, if #rare > 0 then rare[rng:NextInteger(1, #rare)] else nil)
		end)
	end

	-- Ending: day comes back, and the night mutation, sky, music and boosts
	-- stop for everyone. Runs once, whether the time ran out or a founder
	-- pressed END.
	endFounderEvent = function()
		if ended then
			return
		end
		ended = true
		ReplicatedStorage:SetAttribute("FounderEventEndsAt", 0)
		if event.Night then
			ReplicatedStorage:SetAttribute("NightMutation", "")
			ReplicatedStorage:SetAttribute("NightBoost", 0)
			TweenService:Create(Lighting, TweenInfo.new(5, Enum.EasingStyle.Sine), { ClockTime = dayTime }):Play()
		end
		ReplicatedStorage:SetAttribute("FounderEvent", "")
		founderEventRunning = nil
		-- Give the giants and UFOs a moment to fly off, then clear anything left.
		task.delay(15, function()
			eventFolder:Destroy()
		end)
	end

	local running = 0
	for _, spot in event.Spots do
		running += 1
		task.spawn(function()
			-- Even if something goes wrong, the event still ends properly.
			local ok, err = pcall(if event.Style == "Ballet" then runBallet elseif event.Style == "Forest" then runForest else runUfo, spot)
			if not ok then
				warn("[BrainrotHeist] Founder event part failed:", err)
			end
			running -= 1
		end)
	end
	while running > 0 and active() do
		task.wait(0.5)
	end
	endFounderEvent()
end

-- Global announcements -------------------------------------------------------
-- Admins type "/announce <message>" (or "/a <message>") in chat, or use the
-- admin panel, to show a message on screen in EVERY server. The text is run
-- through Roblox's filter first, as Roblox requires.

local ANNOUNCE_TOPIC = "BrainrotHeistAnnouncement"
local lastAnnouncement: { [Player]: { Text: string, At: number } } = {}

local function showAnnouncement(from: string, message: string)
	Announce:FireAllClients("global", from, "", message)
end

task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(ANNOUNCE_TOPIC, function(packet)
			local data = packet.Data
			-- Our own server already showed it.
			if type(data) == "table" and data.Server ~= game.JobId and type(data.From) == "string" and type(data.Text) == "string" then
				showAnnouncement(data.From, data.Text)
			end
		end)
	end)
end)

-- The founder's name ("Corny") for a founder, otherwise their display name.
local function announcerName(player: Player): string
	local founder = founderOf(player)
	return if founder then founder.Name else player.DisplayName
end

local function announceEverywhere(player: Player, raw: string)
	local session = sessions[player]
	if not session or not hasAdminPowers(session) then
		return
	end
	local message = string.sub(string.match(raw, "^%s*(.-)%s*$") or "", 1, 200)
	if message == "" then
		notify(player, "Type a message after /announce")
		return
	end
	-- The chat command and the chat fallback can both see the same message.
	local last = lastAnnouncement[player]
	if last and last.Text == message and os.clock() - last.At < 3 then
		return
	end
	if last and os.clock() - last.At < 5 then
		notify(player, "Wait a few seconds between announcements.")
		return
	end
	lastAnnouncement[player] = { Text = message, At = os.clock() }
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(message, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(filtered) ~= "string" then
		notify(player, "Couldn't send that announcement. Try again.")
		return
	end
	local from = announcerName(player)
	showAnnouncement(from, filtered)
	local sent = pcall(function()
		MessagingService:PublishAsync(ANNOUNCE_TOPIC, { From = from, Text = filtered, Server = game.JobId })
	end)
	notify(player, if sent then "Announced to every server!" else "Announced in this server (other servers couldn't be reached).")
end

-- The chat command (new chat). Messages starting with /announce or /a.
local function stripCommand(text: string): string?
	local lower = string.lower(text)
	for _, alias in { "/announce", "/a" } do
		if string.sub(lower, 1, #alias + 1) == alias .. " " then
			return string.sub(text, #alias + 2)
		end
	end
	return nil
end

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	local command = Instance.new("TextChatCommand")
	command.Name = "GlobalAnnounce"
	command.PrimaryAlias = "/announce"
	command.SecondaryAlias = "/a"
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		local message = stripCommand(text)
		if player and message then
			announceEverywhere(player, message)
		end
	end)
	command.Parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
end
-- Old chat (and a fallback for the new one).
local function watchChat(player: Player)
	player.Chatted:Connect(function(text)
		local message = stripCommand(text)
		if message then
			announceEverywhere(player, message)
		end
	end)
end
Players.PlayerAdded:Connect(watchChat)
for _, player in Players:GetPlayers() do
	watchChat(player)
end
Players.PlayerRemoving:Connect(function(player)
	lastAnnouncement[player] = nil
end)

-- Admin panel --------------------------------------------------------------

-- "250", "1.5k", "2M", "-500" -> number
local function parseAmount(value: unknown): number?
	local textValue = string.lower((string.gsub(tostring(value), "[,%s]", "")))
	local digits, suffix = string.match(textValue, "^(%-?[%d%.]+)([kmbt]?)$")
	local n = digits and tonumber(digits)
	if not n then
		return nil
	end
	local multipliers = { [""] = 1, k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
	return n * multipliers[suffix :: string]
end

-- Who an admin may kick or ban: never Corny, never yourself; founders only
-- by Corny; other admins only by a founder.
local function canModerate(admin: Player, userId: number): (boolean, string?)
	if userId == admin.UserId then
		return false, "You can't do that to yourself."
	end
	local headFounder: Config.Founder? = nil
	local targetFounder: Config.Founder? = nil
	for _, founder in Config.Founders do
		if founder.Id == Config.HeadFounder then
			headFounder = founder
		end
		if founder.UserId == userId then
			targetFounder = founder
		end
	end
	if headFounder and headFounder.UserId == userId then
		return false, "Nobody can kick or ban " .. Config.HeadFounder .. "."
	end
	local adminFounder = founderOf(admin)
	if targetFounder and not (adminFounder and adminFounder.Id == Config.HeadFounder) then
		return false, "Only " .. Config.HeadFounder .. " can kick or ban a founder."
	end
	if table.find(Config.AdminUserIds, userId) and not adminFounder then
		return false, "Only a founder can kick or ban another admin."
	end
	return true, nil
end

-- A player in this server by name (any part), else a Roblox username's id.
local function findUser(name: string): (Player?, number?)
	local q = string.lower(name)
	if q == "" or q == "all" or q == "me" then
		return nil, nil
	end
	for _, other in Players:GetPlayers() do
		if string.sub(string.lower(other.Name), 1, #q) == q or string.sub(string.lower(other.DisplayName), 1, #q) == q then
			return other, other.UserId
		end
	end
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	return nil, if ok then userId else nil
end

local function moderate(admin: Player, action: string, target: unknown, value: unknown)
	local name = string.match(tostring(target or ""), "^%s*(.-)%s*$") or ""
	local reasonText = string.sub(string.match(tostring(value or ""), "^%s*(.-)%s*$") or "", 1, 120)
	local player, userId = findUser(name)
	if not userId then
		notify(admin, "Type a player's name in the Player box (not 'me' or 'all').")
		return
	end
	local who = if player then player.DisplayName else name
	if action ~= "Unban" then
		local allowed, why = canModerate(admin, userId)
		if not allowed then
			notify(admin, why or "You can't do that.")
			return
		end
	end
	if action == "Kick" then
		if not player then
			notify(admin, who .. " isn't in this server.")
			return
		end
		player:Kick(if reasonText ~= "" then "Kicked: " .. reasonText else "You were kicked by an admin.")
		notify(admin, "Kicked " .. who .. ".")
	elseif action == "Ban" then
		local reason = if reasonText ~= "" then "Banned: " .. reasonText else "You are banned from this game."
		bannedHere[userId] = true
		local store = banStore
		local saved = store ~= nil and pcall(function()
			(store :: DataStore):SetAsync("u_" .. userId, { Reason = reason, By = admin.UserId, At = os.time() })
		end)
		pcall(function()
			(Players :: any):BanAsync({ UserIds = { userId }, ApplyToUniverse = true, Duration = -1, DisplayReason = reason, PrivateReason = "Banned by " .. admin.Name })
		end)
		pcall(function()
			MessagingService:PublishAsync(BAN_TOPIC, userId)
		end)
		if player then
			player:Kick(reason)
		end
		notify(admin, "Banned " .. who .. (if saved then " for good (every server)." else " (this server only: the ban couldn't be saved)."))
	elseif action == "Unban" then
		bannedHere[userId] = nil
		local store = banStore
		local saved = store ~= nil and pcall(function()
			(store :: DataStore):RemoveAsync("u_" .. userId)
		end)
		pcall(function()
			(Players :: any):UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
		end)
		notify(admin, "Unbanned " .. who .. (if saved then "." else " (this server only: it couldn't be saved)."))
	end
end

-- Wipes a player back to a brand-new save: cash, rebirths, base levels,
-- brainrots (base and vault), quests, skins and currencies. Only their Robux
-- purchases stay (limited brainrots and the purchase receipts).
local function resetPlayer(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	local carry = carries[player]
	if carry then
		returnCarry(carry, nil)
	end
	local old = session.Data
	local fresh = defaultData()
	fresh.Receipts = old.Receipts
	fresh.Settings = old.Settings
	session.Data = fresh
	session.FollowerModels = {}
	local plot = session.Plot
	if plot then
		clearPlotBrainrots(plot, true)
		for index, slot in plot.Vault do
			slot.Model:Destroy()
			plot.Vault[index] = nil
		end
		plot.Pending = 0
		applyBaseLevels(plot, session)
		-- Limited brainrots left on an upper floor come down to the ground.
		for index, slot in table.clone(plot.Slots) do
			local free = if isSlotUnlocked(session, index) then nil else freeSlot(plot, session)
			if free then
				plot.Slots[index] = nil
				placeBrainrot(plot, free, slot.Id, slot.Mutation, slot.Model, false, slot.Serial)
			end
		end
	end
	updateFollowers(player)
	notify(player, "Your progress was reset by " .. Config.HeadFounder .. ".")
	push(player)
	task.spawn(save, player)
end

-- "me", "all", or the start of someone's name / display name.
local function resolveTargets(admin: Player, query: unknown): { Player }
	local q = string.lower(tostring(query or ""))
	if q == "" or q == "me" then
		return { admin }
	end
	if q == "all" then
		return Players:GetPlayers()
	end
	for _, other in Players:GetPlayers() do
		if string.sub(string.lower(other.Name), 1, #q) == q or string.sub(string.lower(other.DisplayName), 1, #q) == q then
			return { other }
		end
	end
	return {}
end

local function cashPack(session: Session, minutes: number, minimum: number): number
	local plot = session.Plot
	local income = if plot then plotIncome(plot, session) else 0
	return math.max(minimum, math.floor(income * minutes * 60))
end

local function grantProduct(player: Player, session: Session, key: string)
	if key == "SmallCash" then
		local amount = cashPack(session, Config.SmallCashMinutes, Config.SmallCashMinimum)
		session.Data.Cash += amount
		notify(player, "+" .. Config.FormatCash(amount) .. "! Thanks for the support!")
	elseif key == "BigCash" then
		local amount = cashPack(session, Config.BigCashMinutes, Config.BigCashMinimum)
		session.Data.Cash += amount
		notify(player, "+" .. Config.FormatCash(amount) .. "! Thanks for the support!")
	elseif key == "ServerLuck" then
		local now = workspace:GetServerTimeNow()
		local current = ReplicatedStorage:GetAttribute("LuckEndsAt") :: number? or 0
		ReplicatedStorage:SetAttribute("LuckEndsAt", math.max(now, current) + Config.ServerLuckDuration)
		Announce:FireAllClients("luck", player.DisplayName, "")
	elseif key == "InstantLock" then
		local plot = session.Plot
		if plot then
			lockBase(plot)
			notify(player, "Base locked!")
		end
	end
	push(player)
end

-- Corny's gift box: gives a limited brainrot to anyone by username, out of
-- the shop stock. If they aren't in this server they get it when they join
-- (or right away, if they're in another server).
local GIFT_TOPIC = "BrainrotHeistGift"
local function giftLimited(admin: Player, value: unknown)
	local giver = founderOf(admin)
	if not giver or giver.Id ~= Config.LimitedGiver then
		notify(admin, "Only " .. Config.LimitedGiver .. " can gift limited brainrots.")
		return
	end
	local info: { [string]: any } = if type(value) == "table" then value :: any else {}
	local itemId = tostring(info.ItemId)
	local brainrot = Config.GetBrainrot(itemId)
	local typed = string.gsub(string.sub(tostring(info.Name or ""), 1, 40), "%s", "")
	if not brainrot or not Config.LimitedItems[itemId] then
		return
	end
	if typed == "" then
		notify(admin, "Type the player's username first.")
		return
	end
	-- Someone in this server (username or display name), or look them up.
	local lower = string.lower(typed)
	local here: Player? = nil
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			here = p
			break
		end
	end
	local userId: number? = if here then here.UserId else nil
	local name = if here then here.DisplayName else typed
	if not userId then
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(typed)
		end)
		if not ok or type(id) ~= "number" then
			notify(admin, "Couldn't find a Roblox player called " .. typed .. ".")
			return
		end
		userId = id
	end
	local hereSession = here and sessions[here]
	if hereSession and ownsLimited(hereSession, itemId) then
		notify(admin, name .. " already owns " .. brainrot.DisplayName .. ".")
		return
	end
	local serial, why = LimitedStock.Gift(userId :: number, name, itemId)
	if not serial then
		notify(admin, why or "Couldn't gift it.")
		return
	end
	if here and hereSession and hereSession.Loaded then
		local rolled = grantLimited(here, hereSession, brainrot, serial)
		Announce:FireAllClients("limited", here.DisplayName, itemId, tostring(serial), rolled)
		notify(admin, string.format("Gifted %s #%d to %s!", brainrot.DisplayName, serial, name))
	else
		notify(admin, string.format("Gifted %s #%d to %s! They get it as soon as they join.", brainrot.DisplayName, serial, name))
		pcall(function()
			MessagingService:PublishAsync(GIFT_TOPIC, { UserId = userId })
		end)
	end
end
task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync(GIFT_TOPIC, function(packet)
			local data = packet.Data
			local userId = type(data) == "table" and tonumber(data.UserId)
			local player = userId and Players:GetPlayerByUserId(userId)
			if player then
				deliverOwnedLimited(player)
			end
		end)
	end)
end)

AdminAction.OnServerEvent:Connect(function(admin: Player, action: unknown, target: unknown, value: unknown)
	local adminSession = sessions[admin]
	if not adminSession or not adminSession.IsAdmin or type(action) ~= "string" then
		return
	end
	if not hasAdminPowers(adminSession) then
		notify(admin, "The admin panel is locked by " .. Config.HeadFounder .. ".")
		return
	end
	if not adminSession.FullAdmin and not table.find(Config.ModActions, action) then
		notify(admin, "Mods can only kick, ban, unban and announce.")
		return
	end

	-- Only the head founder (Corny) can add mutations: everyone else's Give,
	-- Spawn and Drop come without one, and Give MAGIC is his alone.
	local isHead = (founderOf(admin) or {} :: any).Id == Config.HeadFounder
	if not isHead then
		if action == "Brainrot" or action == "Spawn" or action == "DropBrainrot" then
			local brainrot = Config.Decode(tostring(value))
			value = if brainrot then brainrot.Id else value
		elseif action == "GiveMagic" or action == "MutateLimited" then
			notify(admin, "Only " .. Config.HeadFounder .. " can add mutations.")
			return
		end
	end

	-- Kick / Ban / Unban (by name; Ban and Unban work on players who are offline too)
	if action == "Kick" or action == "Ban" or action == "Unban" then
		task.spawn(moderate, admin, action, target, value)
		return
	end

	-- Corny's security switches
	if action == "AdminLock" or action == "ResetPlayer" then
		if not isHead then
			notify(admin, "Only " .. Config.HeadFounder .. " can do that.")
			return
		end
		if action == "AdminLock" then
			local locked = value == true
			local saved = saveAdminLock(locked)
			notify(admin, (if locked then "Admin panels LOCKED: only you can use one now." else "Admin panels are back on for every admin.")
				.. (if saved then " (every server)" else " (this server only: it couldn't be saved)"))
		else
			if string.lower(tostring(target or "")) == "all" then
				notify(admin, "Reset one player at a time.")
				return
			end
			for _, player in resolveTargets(admin, target) do
				resetPlayer(player)
				notify(admin, "Reset " .. player.DisplayName .. ": money, base, vault and stats are back to the start.")
			end
		end
		return
	end

	-- Server-wide actions
	if action == "GlobalAnnounce" then
		announceEverywhere(admin, tostring(value))
		return
	elseif action == "GiftLimited" then
		task.spawn(giftLimited, admin, value)
		return
	elseif action == "CreateCode" or action == "DeleteCode" or action == "ListCodes" then
		local maker = founderOf(admin)
		if not maker or maker.Id ~= Config.CodeMaker then
			notify(admin, "Only " .. Config.CodeMaker .. " can make codes.")
			return
		end
		if action == "ListCodes" then
			sendCodeList(admin)
			return
		end
		local info: { [string]: any } = if type(value) == "table" then value :: any else { Code = value }
		local key = cleanCode(tostring(info.Code or ""))
		if key == "" then
			notify(admin, "Type a code first (letters and numbers).")
			return
		end
		task.spawn(function()
			local saved
			if action == "DeleteCode" then
				saved = changeLiveCodes(function(codes)
					codes[key] = nil
				end)
				notify(admin, "Deleted code " .. key .. (if saved then "." else " (this server only: it couldn't be saved)."))
			else
				local limits = Config.CodeLimits
				local function amount(v: any, cap: number): number?
					local n = parseAmount(v)
					return if n and n > 0 then math.min(math.floor(n), cap) else nil
				end
				local hours = tonumber(info.Hours) or 0
				local code: Config.Code = {
					Code = key,
					Cash = amount(info.Cash, limits.Cash),
					Shards = amount(info.Shards, limits.Shards),
					Expires = if hours > 0 then os.time() + math.floor(hours * 3600) else nil,
				}
				if not code.Cash and not code.Shards then
					notify(admin, "Give the code a reward: Cash or Shards.")
					return
				end
				saved = changeLiveCodes(function(codes)
					codes[key] = code
				end)
				notify(admin, string.format("Code %s gives %s%s", key, rewardText(code), if saved then ". Works in every server!" else " (this server only: it couldn't be saved)."))
			end
			sendCodeList(admin)
		end)
		return
	elseif action == "Spawn" or action == "DropBrainrot" then
		local brainrot = Config.Decode(tostring(value))
		if brainrot and brainrot.Limited then
			notify(admin, brainrot.DisplayName .. " is limited: use Give to hand out a reserved copy.")
			return
		end
	end
	if action == "Spawn" then
		local brainrot, mutation = Config.Decode(tostring(value))
		if brainrot then
			spawnOnConveyor(brainrot, mutation)
			notify(admin, "Spawned " .. fullName(brainrot, mutation) .. " on the conveyor.")
		end
		return
	elseif action == "DropBrainrot" then
		local brainrot, mutation = Config.Decode(tostring(value))
		if brainrot then
			dropBrainrot(brainrot, mutation)
			Announce:FireAllClients("drop", admin.DisplayName, brainrot.Id, "", mutation)
		end
		return
	elseif action == "BrainrotRain" then
		Announce:FireAllClients("rain", admin.DisplayName, "")
		task.spawn(function()
			for _ = 1, Config.BrainrotRainCount do
				local luck = Config.BrainrotRainLuck
				dropBrainrot(Config.RollConveyor(rng, luck, adminAbuseLive()), Config.RollMutation(rng, luck, nightBoost()))
				task.wait(0.4)
			end
		end)
		return
	elseif action == "CashRain" then
		local amount = parseAmount(value)
		if not amount or amount <= 0 then
			notify(admin, "Type how much each cash drop is worth in the amount box.")
			return
		end
		Announce:FireAllClients("cashrain", admin.DisplayName, "", Config.FormatCash(amount))
		task.spawn(function()
			for _ = 1, Config.CashRainCount do
				dropCash(amount)
				task.wait(0.15)
			end
		end)
		return
	elseif action == "AbuseStart" then
		local minutes = math.clamp(parseAmount(value) or Config.AdminAbuse.DurationMinutes, 1, 600)
		ReplicatedStorage:SetAttribute("AdminAbuseEndsAt", workspace:GetServerTimeNow() + minutes * 60)
		-- "founder" or "admin": the intro says who's here.
		Announce:FireAllClients("abuse", admin.DisplayName, "", if founderOf(admin) then "founder" else "admin")
		return
	elseif action == "FounderEvent" then
		-- Each founder starts only their own event (Corny's, Ace's).
		local founder = founderOf(admin)
		if not founder then
			notify(admin, "Only the founders can start founder events.")
			return
		end
		local info: { [string]: any } = if type(value) == "table" then value :: any else {}
		local eventId = tostring(info.Id)
		local event = Config.FounderEvents[eventId]
		if not event then
			return
		end
		if event.Founder ~= founder.Id and founder.Id ~= Config.HeadFounder and not event.AnyFounder then
			notify(admin, "That's " .. event.Founder .. "'s event: only " .. event.Founder .. " can start it.")
			return
		end
		if founderEventRunning then
			notify(admin, "A founder event is already running.")
			return
		end
		local minutes = math.clamp(parseAmount(info.Minutes) or event.DurationMinutes, 1, 120)
		task.spawn(runFounderEvent, eventId, minutes)
		notify(admin, string.format("%s started for %d minutes.", event.Title, minutes))
		return
	elseif action == "SaveEventLook" then
		local founder = founderOf(admin)
		local character = admin.Character
		if not founder or not character then
			notify(admin, "Only the founders can save an event look.")
			return
		end
		local saved = Founders.SaveEventLook(founder.Id, character)
		notify(admin, if saved then "Saved! Your event giant will look exactly like you do now." else "Used your look for now, but it couldn't be saved. Try again.")
		return
	elseif action == "SaveEventOutfit" then
		local founder = founderOf(admin)
		if not founder then
			notify(admin, "Only the founders can set an event look.")
			return
		end
		-- Accepts just the number, or a pasted link with the number in it.
		local outfitId = tonumber(string.match(tostring(value), "%d+") or "")
		if not outfitId then
			notify(admin, "Paste the outfit ID (the number) first.")
			return
		end
		local saved = Founders.SaveEventOutfit(founder.Id, outfitId)
		notify(admin, if saved then "Saved! Your event giant will wear outfit " .. outfitId .. "." else "Couldn't find outfit " .. outfitId .. ". Check the number.")
		return
	elseif action == "ResetEventLook" then
		local founder = founderOf(admin)
		if not founder then
			return
		end
		Founders.ResetEventLook(founder.Id)
		notify(admin, "Your event giant will wear your normal avatar again.")
		return
	elseif action == "SetEventMusic" then
		local founder = founderOf(admin)
		if not founder then
			notify(admin, "Only the founders can set event music.")
			return
		end
		-- Their own event; accepts the number or a pasted link with it.
		local eventId: string? = nil
		for id, event in Config.FounderEvents do
			if event.Founder == founder.Id then
				eventId = id
			end
		end
		local soundId = tonumber(string.match(tostring(value), "%d+") or "") or 0
		if not eventId then
			return
		end
		local saved = Founders.SaveEventMusic(eventId, soundId)
		local what = if soundId > 0 then "Your event music is now sound " .. soundId else "Your event music is back to the default"
		notify(admin, what .. (if saved then " (saved for every server)." else " (this server only: it couldn't be saved)."))
		return
	elseif action == "FounderEventStop" or action == "AbuseStop" then
		-- Both END buttons end everything that's running: admin abuse (the
		-- weekly one too) and, for a founder, their founder event.
		local isFounder = founderOf(admin) ~= nil
		if action == "FounderEventStop" and not isFounder then
			notify(admin, "Only the founders can end founder events.")
			return
		end
		local ended = {}
		if adminAbuseLive() then
			ReplicatedStorage:SetAttribute("AdminAbuseEndsAt", 0)
			local status, left = Config.AdminAbuseStatus(workspace:GetServerTimeNow())
			if status == "live" then
				ReplicatedStorage:SetAttribute("AdminAbuseSkipUntil", workspace:GetServerTimeNow() + left + 1)
			end
			table.insert(ended, "Admin abuse")
		end
		if founderEventRunning and isFounder then
			stopFounderEvent()
			table.insert(ended, "the founder event")
		end
		notify(admin, if #ended > 0 then table.concat(ended, " and ") .. " ended." else "Nothing is running right now.")
		return
	elseif action == "Luck" then
		local minutes = parseAmount(value) or 0
		if minutes > 0 then
			ReplicatedStorage:SetAttribute("LuckEndsAt", workspace:GetServerTimeNow() + minutes * 60)
			Announce:FireAllClients("luck", admin.DisplayName, "")
		else
			ReplicatedStorage:SetAttribute("LuckEndsAt", 0)
			notify(admin, "Server luck stopped.")
		end
		return
	end

	local targets = resolveTargets(admin, target)
	if #targets == 0 then
		notify(admin, "No player found named \"" .. tostring(target) .. "\".")
		return
	end

	for _, player in targets do
		local session = sessions[player]
		local plot = session and session.Plot
		if session and session.Loaded then
			local data = session.Data
			if action == "Cash" or action == "SetCash" then
				local amount = parseAmount(value)
				if not amount then
					notify(admin, "Type an amount like 5000, 25k or 2m.")
					return
				end
				data.Cash = math.max(0, if action == "Cash" then data.Cash + amount else amount)
				notify(admin, player.DisplayName .. " now has " .. Config.FormatCash(data.Cash))
			elseif action == "Brainrot" then
				local brainrot, mutation = Config.Decode(tostring(value))
				local index = plot and freeSlot(plot, session)
				if brainrot and brainrot.Limited then
					-- Only Corny can hand out limited brainrots. Each one comes out
					-- of the shop stock, so the "X left" count goes down.
					local giver = founderOf(admin)
					if not giver or giver.Id ~= Config.LimitedGiver then
						notify(admin, "Only " .. Config.LimitedGiver .. " can give limited brainrots.")
					elseif ownsLimited(session, brainrot.Id) then
						notify(admin, player.DisplayName .. " already owns " .. brainrot.DisplayName .. ".")
					else
						local serial, why = LimitedStock.Gift(player.UserId, player.DisplayName, brainrot.Id)
						if serial then
							local rolled = grantLimited(player, session, brainrot, serial)
							Announce:FireAllClients("limited", player.DisplayName, brainrot.Id, tostring(serial), rolled)
							notify(admin, string.format("Gave %s #%d to %s", brainrot.DisplayName, serial, player.DisplayName))
						else
							notify(admin, why or "Couldn't give it.")
						end
					end
				elseif brainrot and plot and index then
					placeBrainrot(plot, index, brainrot.Id, mutation, nil, false)
					notify(admin, "Gave " .. fullName(brainrot, mutation) .. " to " .. player.DisplayName)
				else
					notify(admin, player.DisplayName .. "'s base is full.")
				end
			elseif action == "Base" or action == "LockLevel" then
				local n = math.floor(parseAmount(value) or 1)
				if action == "Base" then
					data.WallLevel = math.clamp(n, 1, #Config.WallLevels)
					data.Stories = data.WallLevel
				else
					data.LockLevel = math.clamp(n, 1, #Config.LockLevels)
				end
				if plot then
					applyBaseLevels(plot, session)
				end
				notify(admin, string.format("%s: base level %d, lock level %d", player.DisplayName, data.WallLevel, data.LockLevel))
			elseif action == "GivePass" then
				-- A gamepass for free until they leave (the real one is bought
				-- on Roblox and lasts forever).
				local pass: Config.GamePass? = nil
				for _, p in Config.GamePasses do
					if p.Key == value then
						pass = p
					end
				end
				if pass then
					session.Owns[pass.Key] = true
					session.Roles.VIP = session.Owns.VIP == true
					if plot then
						applyBaseLevels(plot, session)
					end
					updateVipTag(player)
					notify(player, "You got " .. pass.Name .. " until you leave!")
					notify(admin, string.format("Gave %s to %s (until they leave).", pass.Name, player.DisplayName))
				end
			elseif action == "GiveProduct" then
				for _, product in Config.Products do
					if product.Key == value then
						grantProduct(player, session, product.Key)
						notify(admin, string.format("Gave %s to %s.", product.Name, player.DisplayName))
					end
				end
			elseif action == "InfiniteLock" then
				-- Gives (or takes away) the Infinite Laser Door, the same as the
				-- one sold for Shards. The gamepass can't be taken away here.
				local on = value == true
				data.InfiniteLock = on
				if plot then
					if not on and not session.Owns.InfiniteLock and plot.LockedUntil == math.huge then
						plot.LockedUntil = 0
						plot.CooldownUntil = 0
						setLaser(plot, false)
					end
					applyBaseLevels(plot, session)
				end
				notify(admin, string.format("%s: Infinite Laser Door %s", player.DisplayName, if on then "ON" else "OFF"))
			elseif action == "GiveMagic" then
				-- Turns the player's event brainrot (the one Magic is made for) Magic.
				local given = false
				if plot then
					for index, slot in plot.Slots do
						local brainrot = Config.GetBrainrot(slot.Id)
						if brainrot and Config.MutationAllowed(brainrot, "Magic") and not hasMagic(slot.Mutation) and not slot.StolenBy then
							local following = table.find(session.FollowerModels, slot.Model)
							slot.Model:Destroy()
							placeBrainrot(plot, index, slot.Id, Config.JoinMutations({ slot.Mutation or "", "Magic" }), nil, false, slot.Serial)
							if following then
								session.FollowerModels[following] = plot.Slots[index].Model
							end
							given = true
						end
					end
				end
				for i, entry in data.Unclaimed do
					local brainrot, oldMutation, serial = Config.Decode(entry)
					if brainrot and Config.MutationAllowed(brainrot, "Magic") then
						data.Unclaimed[i] = Config.Encode(brainrot.Id, Config.JoinMutations({ oldMutation or "", "Magic" }), serial)
						given = true
					end
				end
				if given then
					notify(player, "An admin made your event brainrot MAGIC!")
					notify(admin, "Gave Magic to " .. player.DisplayName)
					Announce:FireAllClients("magic", player.DisplayName, Config.CurrentEvent, "")
					updateFollowers(player)
				else
					notify(admin, player.DisplayName .. " doesn't own the event brainrot (or it's already Magic).")
				end
			elseif action == "MutateLimited" then
				-- Stacks mutations onto the event brainrot they already own (no
				-- new copy, same serial). The new ones come first, so they stay
				-- when the stack is already full.
				local brainrot, added = Config.Decode(tostring(value))
				local result: string? = nil
				local function stacked(old: string?): string?
					local ids = {}
					for _, m in Config.SplitMutations(added) do
						table.insert(ids, m.Id)
					end
					-- Old ones rarest first, so a full stack drops the commonest.
					local oldList = Config.SplitMutations(old)
					for k = #oldList, 1, -1 do
						table.insert(ids, oldList[k].Id)
					end
					return Config.JoinMutations(ids)
				end
				if brainrot and brainrot.Limited and added then
					if plot then
						for index, slot in plot.Slots do
							if slot.Id == brainrot.Id and not slot.StolenBy then
								result = stacked(slot.Mutation)
								local following = table.find(session.FollowerModels, slot.Model)
								slot.Model:Destroy()
								placeBrainrot(plot, index, slot.Id, result, nil, false, slot.Serial)
								if following then
									session.FollowerModels[following] = plot.Slots[index].Model
								end
							end
						end
					end
					for i, entry in data.Unclaimed do
						local owned, oldMutation, serial = Config.Decode(entry)
						if owned and owned.Id == brainrot.Id then
							result = stacked(oldMutation)
							data.Unclaimed[i] = Config.Encode(owned.Id, result, serial)
						end
					end
				end
				if brainrot and result then
					notify(player, "An admin upgraded your " .. fullName(brainrot, result) .. "!")
					notify(admin, player.DisplayName .. "'s " .. fullName(brainrot, result))
					updateFollowers(player)
				else
					notify(admin, player.DisplayName .. " doesn't own " .. (if brainrot then brainrot.DisplayName else "that") .. " (or no mutation was picked).")
				end
			elseif action == "Shards" then
				local amount = math.floor(parseAmount(value) or 0)
				data.Shards = math.max(0, data.Shards + amount)
				notify(admin, string.format("%s: %d Shards", player.DisplayName, data.Shards))
			elseif action == "Rebirths" then
				data.Rebirths = math.max(0, math.floor(parseAmount(value) or 0))
				if plot then
					applyBaseLevels(plot, session)
				end
				notify(admin, player.DisplayName .. " is now Rebirth " .. data.Rebirths)
			elseif action == "ClearBase" then
				if plot then
					clearPlotBrainrots(plot, true)
				end
				notify(admin, "Cleared " .. player.DisplayName .. "'s base.")
			else
				return
			end
			print(string.format("[Admin] %s: %s %s -> %s", admin.Name, action, tostring(value), player.Name))
			push(player)
		end
	end
end)

-- Robux purchases ----------------------------------------------------------

local productsById: { [number]: Config.Product } = {}
for _, product in Config.Products do
	if product.Id ~= 0 then
		productsById[product.Id] = product
	end
end

local limitedByProduct: { [number]: string } = {}
for itemId, item in Config.LimitedItems do
	if item.ProductId ~= 0 then
		limitedByProduct[item.ProductId] = itemId
	end
end

-- Shop button for a limited brainrot: reserve a copy, then show the prompt.
BuyLimited.OnServerInvoke = function(player: Player, itemId: unknown): (boolean, string?)
	local session = sessions[player]
	local item = if type(itemId) == "string" then Config.LimitedItems[itemId] else nil
	local brainrot = if type(itemId) == "string" then Config.GetBrainrot(itemId) else nil
	if not session or not session.Loaded or not item or not brainrot then
		return false, "Try again in a moment."
	end
	if not Config.LimitedOnSale(item) then
		return false, "Not on sale yet!"
	end
	if ownsLimited(session, brainrot.Id) then
		return false, "You already own " .. brainrot.DisplayName .. "!"
	end
	local now = os.clock()
	if now - session.LastLimitedTry < 3 then
		return false, "Hold on..."
	end
	session.LastLimitedTry = now
	local ok, message = LimitedStock.Reserve(player, brainrot.Id)
	if not ok then
		return false, message
	end
	if item.GamePassId and item.GamePassId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, item.GamePassId)
	else
		MarketplaceService:PromptProductPurchase(player, item.ProductId)
	end
	return true, nil
end

-- Limited brainrots sold as a gamepass: once Roblox says it's bought, turn
-- the reserved copy into theirs (with a serial) and put her in their base.
local function claimLimitedPass(player: Player, itemId: string)
	local brainrot = Config.GetBrainrot(itemId)
	if not brainrot then
		return
	end
	for attempt = 1, 5 do
		local serial = LimitedStock.Claim(player, itemId)
		local session = sessions[player]
		if serial and session and session.Loaded then
			if not ownsLimited(session, itemId) then
				local mutation = grantLimited(player, session, brainrot, serial)
				Announce:FireAllClients("limited", player.DisplayName, itemId, tostring(serial), mutation)
				save(player)
			end
			return
		end
		if not player.Parent then
			return -- they get her when they next join (they own the pass)
		end
		task.wait(attempt * 2)
	end
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	local itemId = limitedByProduct[productId]
	local player = Players:GetPlayerByUserId(userId)
	if itemId and player and not isPurchased then
		LimitedStock.Release(player, itemId)
	end
end)

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local session = player and sessions[player]
	local product = productsById[info.ProductId]
	local limitedId = limitedByProduct[info.ProductId]
	if not player or not session or not session.Loaded or not (product or limitedId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = session.Data.Receipts
	if table.find(receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if limitedId then
		local brainrot = Config.GetBrainrot(limitedId) :: Config.Brainrot
		local serial = LimitedStock.Claim(player, limitedId)
		if not serial then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not ownsLimited(session, limitedId) then
			local mutation = grantLimited(player, session, brainrot, serial)
			Announce:FireAllClients("limited", player.DisplayName, limitedId, tostring(serial), mutation)
		end
	elseif product then
		grantProduct(player, session, product.Key)
	end
	table.insert(receipts, info.PurchaseId)
	while #receipts > 50 do
		table.remove(receipts, 1)
	end

	-- Only confirm once it's saved; Roblox retries otherwise, and the receipt
	-- list above stops it from being granted twice.
	if not store or save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local session = sessions[player]
	for itemId, item in Config.LimitedItems do
		if item.GamePassId == passId then
			if purchased then
				task.spawn(claimLimitedPass, player, itemId)
			else
				LimitedStock.Release(player, itemId)
			end
			return
		end
	end
	if not purchased or not session then
		return
	end
	for _, pass in Config.GamePasses do
		if pass.Id == passId then
			session.Owns[pass.Key] = true
			session.Roles.VIP = session.Owns.VIP == true
			notify(player, "You got " .. pass.Name .. "!")
			if pass.Key == "VIP" then
				notify(player, "Claim your free VIP Royale skin in the skins list!")
			end
		end
	end
	if session.Plot then
		applyBaseLevels(session.Plot, session)
	end
	updateVipTag(player)
	push(player)
end)

-- Income, labels, locks and autosave --------------------------------------

task.spawn(function()
	local sinceSave = 0
	local sinceMinute = 0
	while true do
		-- One bad tick is logged and skipped; the loop never stops.
		local ok, err = pcall(function()
			task.wait(1)
			sinceSave += 1
			sinceMinute += 1
			for player in sessions do
				updateFollowers(player)
			end
			if sinceMinute >= 60 then
				sinceMinute = 0
				for player in sessions do
					task.spawn(addQuestProgress, player, "Minutes", 1)
				end
			end
			local now = os.clock()
			for _, plot in plots do
				local owner = plot.Owner
				local session = owner and sessions[owner]
				if session and session.Loaded then
					plot.Pending = math.min(plot.Pending + plotIncome(plot, session), Config.MaxCash)
					plot.Parts.PendingLabel.Text = "COLLECT\n" .. Config.FormatCash(plot.Pending)

					local button = plot.Parts.LockButtonLabel
					local open = now >= plot.LockedUntil
					button.Text = if open then "LOCK DOOR" else "UNLOCK DOOR"
					button.TextColor3 = if open then Color3.fromRGB(255, 140, 140) else Color3.fromRGB(140, 255, 160)
					plot.Parts.LockButton.Color = if open then Color3.fromRGB(235, 60, 60) else Color3.fromRGB(60, 220, 100)
					if plot.LockedUntil == math.huge then
						plot.Parts.LockLabel.Text = "LOCKED FOREVER"
					elseif now < plot.LockedUntil then
						plot.Parts.LockLabel.Text = string.format("LOCKED %ds", math.ceil(plot.LockedUntil - now))
					else
						if plot.Parts.Model:GetAttribute("Locked") then
							setLaser(plot, false)
						end
						if now < plot.CooldownUntil then
							plot.Parts.LockLabel.Text = string.format("RECHARGING %ds", math.ceil(plot.CooldownUntil - now))
						else
							plot.Parts.LockLabel.Text = "STEP TO LOCK"
						end
					end
				end
			end
			if sinceSave >= 60 then
				sinceSave = 0
				for player in sessions do
					task.spawn(save, player)
				end
			end
		end)
		if not ok then
			warn("[BrainrotHeist] income loop error:", err)
			task.wait(1)
		end
	end
end)

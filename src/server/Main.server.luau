--!strict
-- Brainrot Heist server: saving, bases, conveyor, buying, stealing, locks,
-- slapping, rebirths and Robux purchases. The server decides everything, so
-- exploiters can't give themselves cash or brainrots.

local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
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
local DiamondPurchase: RemoteEvent = makeRemote("RemoteEvent", "DiamondPurchase")

remotes.Parent = ReplicatedStorage
ReplicatedStorage:SetAttribute("LuckEndsAt", 0)

-- Types --------------------------------------------------------------------

type SaveData = {
	Cash: number,
	Rebirths: number,
	Brainrots: { string }, -- brainrot ids placed in the base, in slot order
	Steals: number,
	WallLevel: number,
	Stories: number,
	LockLevel: number,
	Receipts: { string }, -- recent purchase ids, so a purchase is never granted twice
	Unclaimed: { string }, -- paid brainrots waiting for a free slot
	Followers: { string }, -- up to 3 brainrots (encoded) that follow you as minis
	Shards: number,
	Diamonds: number,
	Skins: { string }, -- owned wall skin ids
	Skin: string, -- equipped wall skin
	Quests: QuestState,
	CashBoostUntil: number, -- unix time the Diamond Shop 2x Cash boost ends
	AbuseGiftWeek: number, -- the week this player last got the admin abuse gift
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
	Pending: number, -- cash waiting on the collect pad
	LockedUntil: number,
	CooldownUntil: number,
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
	IsAdmin: boolean,
	IsFounder: boolean,
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
local plots: { Plot } = {}
for i, parts in world.Plots do
	plots[i] = {
		Parts = parts,
		Owner = nil,
		Slots = {},
		Pending = 0,
		LockedUntil = 0,
		CooldownUntil = 0,
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
		if (founder.UserId > 0 and founder.UserId == player.UserId) or (founder.Username ~= "" and string.lower(founder.Username) == string.lower(player.Name)) then
			return founder
		end
	end
	return nil
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
	for _, slot in plot.Slots do
		if not slot.StolenBy then
			local brainrot = Config.GetBrainrot(slot.Id)
			if brainrot then
				total += Config.IncomeOf(brainrot, slot.Mutation, session.Data.Rebirths)
			end
		end
	end
	return total * incomeMultiplier(session)
end

local function placedCount(plot: Plot): number
	local count = 0
	for _ in plot.Slots do
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
	local mutation = Config.GetMutation(mutationId)
	return if mutation then mutation.DisplayName .. " " .. brainrot.DisplayName else brainrot.DisplayName
end

-- Worth telling the whole server about: Legendary+ or a rare mutation.
local function isNotable(brainrot: Config.Brainrot, mutationId: string?): boolean
	local mutation = Config.GetMutation(mutationId)
	return Config.Rarities[brainrot.Rarity].Order >= 4 or (mutation ~= nil and mutation.Chance <= 0.6)
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
	return luck
end

-- Player data --------------------------------------------------------------

local function defaultData(): SaveData
	return {
		Cash = Config.StartingCash,
		Rebirths = 0,
		Brainrots = {},
		Steals = 0,
		WallLevel = 1,
		Stories = 1,
		LockLevel = 1,
		Receipts = {},
		Unclaimed = {},
		Followers = {},
		Shards = 0,
		Diamonds = 0,
		Skins = { "Classic" },
		Skin = "Classic",
		CashBoostUntil = 0,
		AbuseGiftWeek = -1,
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
	if type(raw.Diamonds) == "number" then
		data.Diamonds = math.max(0, math.floor(raw.Diamonds))
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
		Owns = session.Owns,
		PlotIndex = if plot then plot.Parts.Index else 0,
		IsAdmin = session.IsAdmin,
		IsFounder = session.IsFounder,
		Limited = limitedOwned(session),
		Shards = data.Shards,
		CashBoostLeft = math.max(0, data.CashBoostUntil - os.time()),
		Diamonds = data.Diamonds,
		Skins = data.Skins,
		Skin = data.Skin,
		Quests = questSnapshot(data),
		Base = baseList(session),
	}
end

local function updateLeaderstats(session: Session)
	local stats = session.Leaderstats
	if not stats then
		return
	end
	local cash = stats:FindFirstChild("Cash") :: IntValue?
	local steals = stats:FindFirstChild("Steals") :: IntValue?
	local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
	if cash then
		cash.Value = math.floor(session.Data.Cash)
	end
	if steals then
		steals.Value = session.Data.Steals
	end
	if rebirths then
		rebirths.Value = session.Data.Rebirths
	end
end

local function push(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	updateLeaderstats(session)
	DataUpdated:FireClient(player, snapshot(session))
end

local function save(player: Player): boolean
	local session = sessions[player]
	if not session or not session.Loaded or not store then
		return false
	end
	syncBrainrots(session)
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
						data.Diamonds += Config.WeeklyDiamonds
						data.Shards += Config.WeeklyShards
						notify(player, string.format("WEEKLY QUEST DONE: %s  +%d Diamond, +%d Shards!", text, Config.WeeklyDiamonds, Config.WeeklyShards))
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
end

local function pedestalCFrame(plot: Plot, index: number): CFrame
	-- Root sits half a stud above the pedestal top (see BrainrotModel).
	return plot.Parts.Pedestals[index].CFrame * CFrame.new(0, 1, 0)
end

-- Puts a brainrot in a base slot, reusing `model` if given (bought or stolen).
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
	m:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	m:SetAttribute("Carried", false)
	m.Parent = plot.Parts.Model
	addBasePrompts(m, brainrot, mutation)

	root.Anchored = true
	if animate then
		TweenService:Create(root, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
	else
		root.CFrame = target
	end

	plot.Slots[index] = { Id = id, Mutation = mutation, Serial = serial, Model = m }

	-- Income that grows with rebirths shows the owner's current amount.
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

local function lockDuration(session: Session): number
	local duration = Config.LockLevels[session.Data.LockLevel].Duration
	return if session.Owns.LongerLock then duration * 2 else duration
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
	if not plot or not owner or owner == thief or model:GetAttribute("Carried") then
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

onSell = function(player: Player, model: Model)
	local session = sessions[player]
	local plot = session and session.Plot
	if not session or not plot or model:GetAttribute("PlotIndex") ~= plot.Parts.Index then
		return
	end
	local index = model:GetAttribute("Slot") :: number
	local slot = plot.Slots[index]
	if not slot or slot.Model ~= model or slot.StolenBy then
		return
	end
	local brainrot = Config.GetBrainrot(slot.Id)
	if not brainrot or brainrot.Limited then
		return
	end
	plot.Slots[index] = nil
	model:Destroy()
	local value = Config.SellValue(brainrot, slot.Mutation)
	session.Data.Cash += value
	notify(player, "Sold " .. fullName(brainrot, slot.Mutation) .. " for " .. Config.FormatCash(value))
	deliverUnclaimed(player, session)
	push(player)
end

task.spawn(function()
	while true do
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
	-- Every copy rolls for a mutation: normal odds, plus 1% Magic (event-only).
	local mutation: string? = nil
	if Config.MutationAllowed(brainrot, "Magic") and rng:NextNumber(0, 100) < Config.MagicChance then
		mutation = "Magic"
	else
		mutation = Config.RollMutation(rng, 1)
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
	if mutation == "Magic" then
		notify(player, "INCREDIBLE! You rolled the 1% MAGIC mutation!")
	end
	push(player)
	return mutation
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
	data.Diamonds += gift.Diamonds
	data.Shards += gift.Shards
	local brainrot = Config.RollConveyor(rng, gift.BrainrotLuck, false)
	local mutation = Config.RollMutation(rng, gift.BrainrotLuck)
	local plot = session.Plot
	local index = plot and freeSlot(plot, session)
	if plot and index then
		placeBrainrot(plot, index, brainrot.Id, mutation, nil, true)
	else
		table.insert(data.Unclaimed, Config.Encode(brainrot.Id, mutation))
		notify(player, "Your gift brainrot will appear as soon as you have a free slot!")
	end
	Announce:FireClient(player, "abusegift", "", brainrot.Id, string.format("%d,%d", gift.Diamonds, gift.Shards), mutation)
	push(player)
	task.spawn(save, player)
end

task.spawn(function()
	local wasLive = false
	while true do
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
	plot.Parts.UpgradeLabel.Text = string.format(
		"UPGRADES\nBase Lv %d/%d | Lock %ds",
		data.WallLevel,
		#Config.WallLevels,
		lockDuration(session)
	)
end

local function assignPlot(player: Player, session: Session)
	for _, plot in plots do
		if not plot.Owner then
			plot.Owner = player
			plot.Pending = 0
			plot.LockedUntil = 0
			plot.CooldownUntil = 0
			plot.Parts.Model:SetAttribute("OwnerUserId", player.UserId)
			plot.Parts.OwnerLabel.Text = player.DisplayName .. "'s Base"
			session.Plot = plot
			updateVipPedestals(plot)
			WorldBuilder.SetWallLevel(plot.Parts, session.Data.WallLevel, session.Data.Stories, Config.GetWallSkin(session.Data.Skin))
			WorldBuilder.SetStories(plot.Parts, session.Data.Stories)
			WorldBuilder.SetCarpet(plot.Parts, Config.CarpetTierFor(session.Data.Rebirths))
			setLaser(plot, false)
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
	plot.Owner = nil
	plot.Pending = 0
	plot.LockedUntil = 0
	plot.CooldownUntil = 0
	setLaser(plot, false)
	plot.Parts.Model:SetAttribute("OwnerUserId", 0)
	plot.Parts.OwnerLabel.Text = "EMPTY BASE"
	plot.Parts.PendingLabel.Text = "COLLECT\n$0"
	plot.Parts.LockLabel.Text = "STEP TO LOCK"
	updateVipPedestals(plot)
	WorldBuilder.SetWallLevel(plot.Parts, 1, 1)
	WorldBuilder.SetStories(plot.Parts, 1)
	WorldBuilder.SetCarpet(plot.Parts, 0)
	plot.Parts.UpgradeLabel.Text = "UPGRADES"
end

-- Applies a base's saved wall, floor and lock levels to the world.
local function applyBaseLevels(plot: Plot, session: Session)
	WorldBuilder.SetWallLevel(plot.Parts, session.Data.WallLevel, session.Data.Stories, Config.GetWallSkin(session.Data.Skin))
	WorldBuilder.SetStories(plot.Parts, session.Data.Stories)
	WorldBuilder.SetCarpet(plot.Parts, Config.CarpetTierFor(session.Data.Rebirths))
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
		cost, name = nextLevel.Cost, Config.Stories[data.WallLevel + 1].Name .. " + " .. nextLevel.Name
	elseif kind == "Lock" then
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

-- Diamond Shop counter. You have to be at the booth, like a real shop.
DiamondPurchase.OnServerEvent:Connect(function(player: Player, itemId: unknown)
	local session = sessions[player]
	local hrp = getRoot(player)
	if not session or not session.Loaded or not hrp or type(itemId) ~= "string" then
		return
	end
	if (hrp.Position - world.ShopPosition).Magnitude > 35 then
		notify(player, "Go to the Diamond Shop to buy that!")
		return
	end
	local item: Config.DiamondItem? = nil
	for _, candidate in Config.DiamondShop do
		if candidate.Id == itemId then
			item = candidate
		end
	end
	if not item then
		return
	end
	local data = session.Data
	if data.Diamonds < item.Cost then
		notify(player, string.format("You need %d Diamonds. Earn them from weekly quests and admin abuse!", item.Cost))
		return
	end
	data.Diamonds -= item.Cost
	if item.Id == "ShardPack" then
		data.Shards += Config.ShardPackAmount
	elseif item.Id == "CashBoost" then
		data.CashBoostUntil = math.max(os.time(), data.CashBoostUntil) + Config.CashBoostSeconds
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

-- Wall skins: buy with Shards/Diamonds, or equip one you own.
SkinAction.OnServerEvent:Connect(function(player: Player, action: unknown, skinId: unknown)
	local session = sessions[player]
	local skin = if type(skinId) == "string" then Config.GetWallSkin(skinId) else nil
	if not session or not session.Loaded or not skin then
		return
	end
	local data = session.Data
	if action == "Buy" and not table.find(data.Skins, skin.Id) then
		local needed = Config.SkinRequirement(skin)
		if needed and not table.find(data.Skins, needed.Id) then
			notify(player, string.format("Unlock %s first!", needed.Name))
			return
		end
		local balance = if skin.Currency == "Diamonds" then data.Diamonds else data.Shards
		if balance < skin.Cost then
			notify(player, string.format("You need %d %s for %s.", skin.Cost, skin.Currency, skin.Name))
			return
		end
		if skin.Currency == "Diamonds" then
			data.Diamonds -= skin.Cost
		else
			data.Shards -= skin.Cost
		end
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

-- Event statue ---------------------------------------------------------------
-- A big spinning statue of the current event brainrot next to the Diamond
-- Shop. Tapping it buys it (same safe reserve-then-prompt flow as the shop).

do
	local brainrot = Config.GetBrainrot(Config.CurrentEvent)
	local item = Config.LimitedItems[Config.CurrentEvent]
	if brainrot and item then
		local folder = Instance.new("Model")
		folder.Name = "EventStatue"
		folder.Parent = workspace:FindFirstChild("BrainrotHeist")
		local base = world.StatuePosition
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
		signGui.Size = UDim2.fromScale(13, 4)
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
			sign.Text = string.format(
				"LIMITED EVENT\n%s\n%s",
				brainrot.DisplayName,
				if item.ProductId == 0 then "Coming soon!"
					elseif stock <= 0 then "SOLD OUT"
					else string.format("%d / %d left  -  R$ %d  -  1%% MAGIC!", stock, item.Stock, item.PriceRobux)
			)
		end
		ReplicatedStorage:GetAttributeChangedSignal("LimitedLeft_" .. brainrot.Id):Connect(updateSign)
		updateSign()
	end
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
	notify(player, "Bought " .. fullName(brainrot, mutation) .. "! It's walking to your base.")
	local order = Config.Rarities[brainrot.Rarity].Order
	addQuestProgress(player, "Buy", 1)
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
	local mutation = if forced then forcedMutation else Config.RollMutation(rng, luck)
	local start = CFrame.lookAt(world.ConveyorStart, world.ConveyorEnd)
	local model = BrainrotModel.Create(brainrot, mutation, start, true)
	local root = model.PrimaryPart :: BasePart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy " .. Config.FormatCash(Config.PriceOf(brainrot, mutation))
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

task.spawn(function()
	while true do
		spawnOnConveyor()
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

local function updateVipTag(player: Player)
	local session = sessions[player]
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not session or not head then
		return
	end
	local existing = head:FindFirstChild("VipTag")
	if session.Owns.VIP and not existing then
		local gui = Instance.new("BillboardGui")
		gui.Name = "VipTag"
		gui.Size = UDim2.fromScale(2.2, 0.7)
		gui.StudsOffset = Vector3.new(0, 2.5, 0)
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
	updateVipTag(player)
	applyMovement(player)
end

local function checkAdmin(player: Player): boolean
	if RunService:IsStudio() or table.find(Config.AdminUserIds, player.UserId) then
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
		IsFounder = false,
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
		if not ok then
			-- Don't risk overwriting real progress with a fresh save.
			sessions[player] = nil
			player:Kick("Could not load your data. Please rejoin.")
			return
		end
		session.Data = sanitize(result)
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
	session.IsFounder = founderOf(player) ~= nil

	if not player.Parent then
		sessions[player] = nil
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Cash", "Steals", "Rebirths" } do
		local value = Instance.new("IntValue")
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
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	load(player)
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
	session.Data.Cash = Config.StartingCash
	if session.Plot then
		clearPlotBrainrots(session.Plot, true)
		session.Plot.Pending = 0
		applyBaseLevels(session.Plot, session)
	end
	notify(player, string.format("REBIRTH! Your income is now x%.1f", incomeMultiplier(session)))
	local newCarpet = Config.CarpetTierFor(session.Data.Rebirths)
	if newCarpet > oldCarpet then
		notify(player, "Your stairs got a new carpet: " .. Config.CarpetTiers[newCarpet].Name .. "!")
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

local function randomDropPosition(): Vector3
	while true do
		-- Stay clear of the caves at both ends, the shop tent and the statue.
		local x = rng:NextNumber(world.ConveyorStart.X + 25, world.ConveyorEnd.X - 25)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local position = Vector3.new(x, 0.1, side * rng:NextNumber(12, 38))
		local flat = Vector3.new(1, 0, 1)
		if ((position - world.ShopPosition) * flat).Magnitude > 18 and ((position - world.StatuePosition) * flat).Magnitude > 12 then
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
local function randomOpenPosition(): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(rng:NextNumber()) * 330
	return dropPositionNear(Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
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
		if not session or not plot or model:GetAttribute("Claimed") then
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

local function dropCash(amount: number, from: Vector3?)
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
	label.Text = Config.FormatCash(amount)
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
		session.Data.Cash += amount
		orb:Destroy()
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
local foundersFolder = Instance.new("Folder")
foundersFolder.Name = "Founders"
foundersFolder.Parent = workspace:FindFirstChild("BrainrotHeist")
ReplicatedStorage:SetAttribute("FounderEvent", "")
ReplicatedStorage:SetAttribute("FounderEventEndsAt", 0)

-- Roblox's default emotes, played one after another.
local GIANT_EMOTES = {
	"rbxassetid://507770239", -- wave
	"rbxassetid://507771019", -- dance
	"rbxassetid://507770677", -- cheer
	"rbxassetid://507776043", -- dance 2
	"rbxassetid://507770818", -- laugh
	"rbxassetid://507777268", -- dance 3
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
		dropBrainrot(brainrot, mutation or Config.RollMutation(rng, luck), from)
	else
		dropCash(Config.FounderCashDrop, from)
	end
end

-- Brings a giant to life at `spot` (under their feet) facing the map: they
-- arrive (rise from the ground or come down from the sky) and cycle through
-- emotes while `active()` is true. With `drop`, they also bob, sway and throw
-- something every `dropEvery` seconds; without it they just stand and emote.
-- Then they leave and are removed.
local function runGiant(giant: Model, spot: Vector3, hover: boolean, dropEvery: number, active: () -> boolean, drop: ((Vector3) -> ())?)
	local root = giant.PrimaryPart :: BasePart
	local height = Founders.RootHeight(giant)
	local _, size = giant:GetBoundingBox()
	local home = CFrame.lookAt(spot + Vector3.new(0, height, 0), Vector3.new(0, spot.Y + height, 0))
	local away = if hover then home + Vector3.new(0, 600, 0) else home - Vector3.new(0, size.Y * 1.1, 0)

	root.CFrame = away
	local arrive = TweenService:Create(root, TweenInfo.new(4, if hover then Enum.EasingStyle.Quad else Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = home })
	arrive:Play()
	arrive.Completed:Wait()

	-- Emotes, one after another
	task.spawn(function()
		local track: AnimationTrack? = nil
		local index = rng:NextInteger(1, #GIANT_EMOTES)
		while giant.Parent and active() do
			if track then
				track:Stop(0.4)
			end
			track = Founders.Play(giant, GIANT_EMOTES[index], true)
			index = index % #GIANT_EMOTES + 1
			task.wait(rng:NextNumber(5, 8))
		end
		if track then
			track:Stop(0.4)
		end
	end)

	-- Bob and sway (so even the look-alike, which can't emote, moves), and throw.
	local started = os.clock()
	local nextDrop = os.clock() + 1.5
	while giant.Parent and active() and not drop do
		task.wait(0.5)
	end
	while giant.Parent and active() and drop do
		local t = os.clock() - started
		local bob = if hover then math.sin(t * 1.4) * size.Y * 0.03 else math.abs(math.sin(t * 2)) * size.Y * 0.01
		local sway = math.sin(t * 0.7) * math.rad(10)
		root.CFrame = (home + Vector3.new(0, bob, 0)) * CFrame.Angles(0, sway, math.sin(t * 1.1) * math.rad(3))
		if os.clock() >= nextDrop then
			nextDrop = os.clock() + dropEvery * rng:NextNumber(0.7, 1.3)
			drop(giantHand(giant))
		end
		task.wait()
	end

	local leave = TweenService:Create(root, TweenInfo.new(if hover then 4 else 3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = away })
	leave.Completed:Connect(function()
		giant:Destroy()
	end)
	leave:Play()
end

-- Admin abuse giants: just standing there, emoting.
local function spawnAbuseGiants()
	for founderId, spot in Config.FounderGiantSpots do
		task.spawn(function()
			local giant = Founders.CreateGiant(founderId, Config.FounderGiantScale, foundersFolder)
			if giant then
				runGiant(giant, spot, false, 0, adminAbuseLive)
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

local function stopFounderEvent()
	ReplicatedStorage:SetAttribute("FounderEventEndsAt", 0)
end

local function runFounderEvent(eventId: string, minutes: number)
	local event = Config.FounderEvents[eventId]
	if not event or founderEventRunning then
		return
	end
	founderEventRunning = eventId
	ReplicatedStorage:SetAttribute("FounderEvent", eventId)
	ReplicatedStorage:SetAttribute("FounderEventEndsAt", workspace:GetServerTimeNow() + minutes * 60)
	Announce:FireAllClients("founder", event.Founder, "", eventId)

	local function drop(from: Vector3)
		founderDrop(from, event.BrainrotChance, event.BrainrotLuck, event.Mutations)
	end
	-- In their special event outfit, not their normal avatar.
	local giant = Founders.CreateGiant(event.Founder, event.Scale, foundersFolder, event.OutfitId)
	if giant then
		local root = giant.PrimaryPart :: BasePart
		-- Jetpack flames and a sparkle trail while hovering
		for _, side in { -1, 1 } do
			local flame = Instance.new("Attachment")
			flame.Position = Vector3.new(side * root.Size.X * 0.45, -root.Size.Y * 0.2, root.Size.Z * 0.9)
			flame.Parent = root
			local fire = Instance.new("Fire")
			fire.Size = event.Scale * 1.2
			fire.Heat = -15
			fire.Color = Color3.fromRGB(255, 140, 40)
			fire.SecondaryColor = Color3.fromRGB(255, 230, 90)
			fire.Parent = flame
		end
		local trail = Instance.new("ParticleEmitter")
		trail.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		trail.Color = ColorSequence.new(event.Colors[1], event.Colors[#event.Colors])
		trail.LightEmission = 1
		trail.Rate = 40
		trail.Lifetime = NumberRange.new(1, 2)
		trail.Speed = NumberRange.new(4, 10)
		trail.SpreadAngle = Vector2.new(180, 180)
		trail.Size = NumberSequence.new(event.Scale * 0.3, 0)
		trail.Parent = root
		runGiant(giant, event.Spot, true, event.DropEvery, founderEventActive, drop)
	else
		-- No giant (shouldn't happen): still drop things from the sky.
		while founderEventActive() do
			drop(randomOpenPosition() + Vector3.new(0, 120, 0))
			task.wait(event.DropEvery)
		end
	end
	ReplicatedStorage:SetAttribute("FounderEvent", "")
	ReplicatedStorage:SetAttribute("FounderEventEndsAt", 0)
	founderEventRunning = nil
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
	if not session or not session.IsAdmin then
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

AdminAction.OnServerEvent:Connect(function(admin: Player, action: unknown, target: unknown, value: unknown)
	local adminSession = sessions[admin]
	if not adminSession or not adminSession.IsAdmin or type(action) ~= "string" then
		return
	end

	-- Server-wide actions
	if action == "GlobalAnnounce" then
		announceEverywhere(admin, tostring(value))
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
				dropBrainrot(Config.RollConveyor(rng, luck, adminAbuseLive()), Config.RollMutation(rng, luck))
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
		Announce:FireAllClients("abuse", admin.DisplayName, "")
		return
	elseif action == "FounderEvent" then
		-- Founders only (Corny and Ace), not other admins.
		if not founderOf(admin) then
			notify(admin, "Only the founders can start founder events.")
			return
		end
		local info: { [string]: any } = if type(value) == "table" then value :: any else {}
		local eventId = tostring(info.Id)
		local event = Config.FounderEvents[eventId]
		if not event then
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
	elseif action == "FounderEventStop" then
		if not founderOf(admin) then
			notify(admin, "Only the founders can end founder events.")
			return
		end
		stopFounderEvent()
		notify(admin, "Founder event ended.")
		return
	elseif action == "AbuseStop" then
		ReplicatedStorage:SetAttribute("AdminAbuseEndsAt", 0)
		notify(admin, "Admin abuse ended.")
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
					if ownsLimited(session, brainrot.Id) then
						notify(admin, player.DisplayName .. " already owns " .. brainrot.DisplayName .. ".")
					else
						local serial, why = LimitedStock.GiveReserved(player, brainrot.Id)
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
			elseif action == "GiveMagic" then
				-- Turns the player's event brainrot (the one Magic is made for) Magic.
				local given = false
				if plot then
					for index, slot in plot.Slots do
						local brainrot = Config.GetBrainrot(slot.Id)
						if brainrot and Config.MutationAllowed(brainrot, "Magic") and slot.Mutation ~= "Magic" and not slot.StolenBy then
							local following = table.find(session.FollowerModels, slot.Model)
							slot.Model:Destroy()
							placeBrainrot(plot, index, slot.Id, "Magic", nil, false, slot.Serial)
							if following then
								session.FollowerModels[following] = plot.Slots[index].Model
							end
							given = true
						end
					end
				end
				for i, entry in data.Unclaimed do
					local brainrot, _, serial = Config.Decode(entry)
					if brainrot and Config.MutationAllowed(brainrot, "Magic") then
						data.Unclaimed[i] = Config.Encode(brainrot.Id, "Magic", serial)
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
			elseif action == "Shards" or action == "Diamonds" then
				local amount = math.floor(parseAmount(value) or 0)
				if action == "Shards" then
					data.Shards = math.max(0, data.Shards + amount)
				else
					data.Diamonds = math.max(0, data.Diamonds + amount)
				end
				notify(admin, string.format("%s: %d Shards, %d Diamonds", player.DisplayName, data.Shards, data.Diamonds))
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
	if item.ProductId == 0 then
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
	MarketplaceService:PromptProductPurchase(player, item.ProductId)
	return true, nil
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
	if not purchased or not session then
		return
	end
	for _, pass in Config.GamePasses do
		if pass.Id == passId then
			session.Owns[pass.Key] = true
			notify(player, "You got " .. pass.Name .. "!")
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
				plot.Pending += plotIncome(plot, session)
				plot.Parts.PendingLabel.Text = "COLLECT\n" .. Config.FormatCash(plot.Pending)

				if now < plot.LockedUntil then
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
	end
end)

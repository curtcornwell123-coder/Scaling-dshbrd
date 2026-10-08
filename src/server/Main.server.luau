--!strict
-- Brainrot Heist server: saving, bases, conveyor, buying, stealing, locks,
-- slapping, rebirths and Robux purchases. The server decides everything, so
-- exploiters can't give themselves cash or brainrots.

local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local BrainrotModel = require(script.Parent:WaitForChild("BrainrotModel"))

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
}

type Slot = {
	Id: string,
	Mutation: string?,
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

local function incomeMultiplier(session: Session): number
	local multiplier = Config.RebirthMultiplier(session.Data.Rebirths)
	if session.Owns.DoubleCash then
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
				total += Config.IncomeOf(brainrot, slot.Mutation)
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
	return math.abs(p.X) <= 30 and math.abs(p.Z) <= 30 and p.Y > -5 and p.Y < 100
end

local function fullName(brainrot: Config.Brainrot, mutationId: string?): string
	local mutation = Config.GetMutation(mutationId)
	return if mutation then mutation.DisplayName .. " " .. brainrot.DisplayName else brainrot.DisplayName
end

-- Worth telling the whole server about: Legendary+ or a rare mutation.
local function isNotable(brainrot: Config.Brainrot, mutationId: string?): boolean
	local mutation = Config.GetMutation(mutationId)
	return Config.Rarities[brainrot.Rarity].Order >= 4 or (mutation ~= nil and mutation.Chance <= 1)
end

-- True while the weekly admin abuse runs, or one an admin started by hand.
local function adminAbuseLive(): boolean
	local now = workspace:GetServerTimeNow()
	local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
	return (manualEnd ~= nil and manualEnd > now) or Config.AdminAbuseStatus(now) == "live"
end

local function luckMultiplier(): number
	local endsAt = ReplicatedStorage:GetAttribute("LuckEndsAt") :: number?
	if endsAt and workspace:GetServerTimeNow() < endsAt then
		return Config.ServerLuckMultiplier
	end
	return 1
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
	if type(raw.WallLevel) == "number" then
		data.WallLevel = math.clamp(math.floor(raw.WallLevel), 1, #Config.WallLevels)
	end
	if type(raw.Stories) == "number" then
		data.Stories = math.clamp(math.floor(raw.Stories), 1, #Config.Stories)
	end
	if type(raw.LockLevel) == "number" then
		data.LockLevel = math.clamp(math.floor(raw.LockLevel), 1, #Config.LockLevels)
	end
	if type(raw.Brainrots) == "table" then
		for _, entry in raw.Brainrots do
			if type(entry) == "string" then
				local brainrot, mutation = Config.Decode(entry)
				if brainrot then
					table.insert(data.Brainrots, Config.Encode(brainrot.Id, mutation))
				end
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
			table.insert(list, Config.Encode(slot.Id, slot.Mutation))
		end
	end
	session.Data.Brainrots = list
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
		Owns = session.Owns,
		PlotIndex = if plot then plot.Parts.Index else 0,
		IsAdmin = session.IsAdmin,
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

-- Brainrots in bases -------------------------------------------------------

local onSell: (Player, Model) -> ()
local onSteal: (Player, Model) -> ()

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
local function placeBrainrot(plot: Plot, index: number, id: string, mutation: string?, model: Model?, animate: boolean)
	local brainrot = Config.GetBrainrot(id)
	if not brainrot then
		return
	end
	local target = pedestalCFrame(plot, index)

	local m = model or BrainrotModel.Create(brainrot, mutation, target * CFrame.new(0, -0.5, 0), false)
	local root = m.PrimaryPart :: BasePart

	local buy = root:FindFirstChild("BuyPrompt")
	if buy then
		buy:Destroy()
	end
	local tag = root:FindFirstChild("Tag")
	local price = tag and tag:FindFirstChild("Price")
	if price then
		price:Destroy()
		local gui = tag :: BillboardGui
		gui.Size = UDim2.fromOffset(200, gui.Size.Y.Offset - 20)
	end

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

	plot.Slots[index] = { Id = id, Mutation = mutation, Model = m }
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
			gui.Size = UDim2.fromOffset(120, 40)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
			gui.MaxDistance = 60
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

local function setCarrying(player: Player, text: string?)
	player:SetAttribute("Carrying", text)
	local _, humanoid = getRoot(player)
	if humanoid then
		humanoid.WalkSpeed = if text then Config.CarryWalkSpeed else Config.NormalWalkSpeed
	end
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
	if not brainrot then
		return
	end
	plot.Slots[index] = nil
	model:Destroy()
	local value = Config.SellValue(brainrot, slot.Mutation)
	session.Data.Cash += value
	notify(player, "Sold " .. fullName(brainrot, slot.Mutation) .. " for " .. Config.FormatCash(value))
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

local function clearPlotBrainrots(plot: Plot)
	for thief, carry in carries do
		if carry.Plot == plot then
			carries[thief] = nil
			setCarrying(thief, nil)
			notify(thief, "The brainrot vanished!")
		end
	end
	for _, slot in plot.Slots do
		slot.Model:Destroy()
	end
	plot.Slots = {}
end

local function updateUpgradeLabel(plot: Plot)
	local owner = plot.Owner
	local session = owner and sessions[owner]
	if not session then
		plot.Parts.UpgradeLabel.Text = "UPGRADES"
		return
	end
	local data = session.Data
	local function line(key: string, current: string, nextCost: number?): string
		return if nextCost
			then string.format("[%s] %s -> %s", key, current, Config.FormatCash(nextCost))
			else string.format("[%s] %s (MAX)", key, current)
	end
	local nextWall = Config.WallLevels[data.WallLevel + 1]
	local nextStory = Config.Stories[data.Stories + 1]
	local nextLock = Config.LockLevels[data.LockLevel + 1]
	plot.Parts.UpgradeLabel.Text = table.concat({
		line("E", "Walls: " .. Config.WallLevels[data.WallLevel].Name, nextWall and nextWall.Cost),
		line("R", string.format("Floors: %d/%d", data.Stories, #Config.Stories), nextStory and nextStory.Cost),
		line("T", string.format("Lock: %ds", lockDuration(session)), nextLock and nextLock.Cost),
	}, "\n")
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
			WorldBuilder.SetWallLevel(plot.Parts, session.Data.WallLevel, session.Data.Stories)
			WorldBuilder.SetStories(plot.Parts, session.Data.Stories)
			WorldBuilder.SetCarpet(plot.Parts, Config.CarpetTierFor(session.Data.Rebirths))
			setLaser(plot, false)
			for _, entry in session.Data.Brainrots do
				local brainrot, mutation = Config.Decode(entry)
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
					placeBrainrot(plot, index, brainrot.Id, mutation, nil, false)
				end
			end
			updateUpgradeLabel(plot)
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
	WorldBuilder.SetWallLevel(plot.Parts, session.Data.WallLevel, session.Data.Stories)
	WorldBuilder.SetStories(plot.Parts, session.Data.Stories)
	WorldBuilder.SetCarpet(plot.Parts, Config.CarpetTierFor(session.Data.Rebirths))
	setLaser(plot, os.clock() < plot.LockedUntil)
	updateVipPedestals(plot)
	updateUpgradeLabel(plot)
end

local function onUpgrade(player: Player, plot: Plot, kind: string)
	local session = sessions[player]
	if not session or not session.Loaded or plot.Owner ~= player then
		return
	end
	local data = session.Data
	local cost: number, name: string
	if kind == "Walls" then
		local nextLevel = Config.WallLevels[data.WallLevel + 1]
		if not nextLevel then
			notify(player, "Your walls are already maxed out!")
			return
		end
		cost, name = nextLevel.Cost, nextLevel.Name
	elseif kind == "Floors" then
		local nextStory = Config.Stories[data.Stories + 1]
		if not nextStory then
			notify(player, "Your base is already as tall as it gets!")
			return
		end
		cost, name = nextStory.Cost, nextStory.Name
	elseif kind == "Lock" then
		local nextLock = Config.LockLevels[data.LockLevel + 1]
		if not nextLock then
			notify(player, "Your lock is already maxed out!")
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
	if kind == "Walls" then
		data.WallLevel += 1
	elseif kind == "Floors" then
		data.Stories += 1
	else
		data.LockLevel += 1
	end
	applyBaseLevels(plot, session)
	notify(player, "Upgraded: " .. name .. "!")
	push(player)
end

for _, plot in plots do
	updateVipPedestals(plot)

	for _, prompt in plot.Parts.UpgradePost:GetChildren() do
		if prompt:IsA("ProximityPrompt") then
			local kind = prompt:GetAttribute("UpgradeType") :: string
			prompt.Triggered:Connect(function(player)
				onUpgrade(player, plot, kind)
			end)
		end
	end

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
	if Config.Rarities[brainrot.Rarity].Announce or (mutationInfo and mutationInfo.Chance <= 1) then
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
		gui.Size = UDim2.fromOffset(100, 30)
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
		clearPlotBrainrots(session.Plot)
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
	local x = rng:NextNumber(world.ConveyorStart.X + 20, world.ConveyorEnd.X - 10)
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	return Vector3.new(x, 0.1, side * rng:NextNumber(12, 38))
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

local function dropBrainrot(brainrot: Config.Brainrot, mutation: string?)
	local landing = randomDropPosition()
	local facing = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model = BrainrotModel.Create(brainrot, mutation, CFrame.new(landing + Vector3.new(0, 90, 0)) * facing, false)
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

	local fall = TweenService:Create(root, TweenInfo.new(2.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(landing + Vector3.new(0, 0.5, 0)) * facing,
	})
	fall.Completed:Connect(function()
		prompt.Enabled = true
	end)
	fall:Play()

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

local function dropCash(amount: number)
	local landing = randomDropPosition()
	local orb = Instance.new("Part")
	orb.Name = "CashDrop"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.5, 2.5, 2.5)
	orb.Anchored = true
	orb.CanCollide = false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(80, 255, 110)
	orb.CFrame = CFrame.new(landing + Vector3.new(0, 90, 0))
	orb.Parent = dropsFolder

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(110, 34)
	tag.StudsOffset = Vector3.new(0, 2.5, 0)
	tag.MaxDistance = 120
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

	TweenService:Create(orb, TweenInfo.new(2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(landing + Vector3.new(0, 1.5, 0)),
	}):Play()

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
		local minutes = parseAmount(value) or Config.AdminAbuse.DurationMinutes
		ReplicatedStorage:SetAttribute("AdminAbuseEndsAt", workspace:GetServerTimeNow() + minutes * 60)
		Announce:FireAllClients("abuse", admin.DisplayName, "")
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
				if brainrot and plot and index then
					placeBrainrot(plot, index, brainrot.Id, mutation, nil, false)
					notify(admin, "Gave " .. fullName(brainrot, mutation) .. " to " .. player.DisplayName)
				else
					notify(admin, player.DisplayName .. "'s base is full.")
				end
			elseif action == "Walls" or action == "Floors" or action == "LockLevel" then
				local n = math.floor(parseAmount(value) or 1)
				if action == "Walls" then
					data.WallLevel = math.clamp(n, 1, #Config.WallLevels)
				elseif action == "Floors" then
					data.Stories = math.clamp(n, 1, #Config.Stories)
				else
					data.LockLevel = math.clamp(n, 1, #Config.LockLevels)
				end
				if plot then
					applyBaseLevels(plot, session)
				end
				notify(admin, string.format("%s: walls %d, floors %d, lock %d", player.DisplayName, data.WallLevel, data.Stories, data.LockLevel))
			elseif action == "Rebirths" then
				data.Rebirths = math.max(0, math.floor(parseAmount(value) or 0))
				if plot then
					applyBaseLevels(plot, session)
				end
				notify(admin, player.DisplayName .. " is now Rebirth " .. data.Rebirths)
			elseif action == "ClearBase" then
				if plot then
					clearPlotBrainrots(plot)
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

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local session = player and sessions[player]
	local product = productsById[info.ProductId]
	if not player or not session or not session.Loaded or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = session.Data.Receipts
	if table.find(receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	grantProduct(player, session, product.Key)
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
	while true do
		task.wait(1)
		sinceSave += 1
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

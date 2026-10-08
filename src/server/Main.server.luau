--!strict
-- Crate Rush server: player data, crate opening, passive income, pets.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local PetFollower = require(script.Parent:WaitForChild("PetFollower"))

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
local RequestOpen: RemoteEvent = makeRemote("RemoteEvent", "RequestOpen")
local ToggleEquip: RemoteEvent = makeRemote("RemoteEvent", "ToggleEquip")
local EquipBest: RemoteEvent = makeRemote("RemoteEvent", "EquipBest")
local SellPet: RemoteEvent = makeRemote("RemoteEvent", "SellPet")
local DataUpdated: RemoteEvent = makeRemote("RemoteEvent", "DataUpdated")
local CoinsUpdated: RemoteEvent = makeRemote("RemoteEvent", "CoinsUpdated")
local CrateResult: RemoteEvent = makeRemote("RemoteEvent", "CrateResult")
local Announce: RemoteEvent = makeRemote("RemoteEvent", "Announce")
local Notify: RemoteEvent = makeRemote("RemoteEvent", "Notify")

remotes.Parent = ReplicatedStorage

-- Player data --------------------------------------------------------------

type SaveData = {
	Coins: number,
	NextUid: number,
	Inventory: { [string]: string }, -- uid -> petId
	Equipped: { string }, -- list of uids
	Opened: number,
	Mythics: number,
}

type Session = {
	Data: SaveData,
	Loaded: boolean,
	LastOpen: number,
	Leaderstats: Folder?,
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("CrateRush_v1")
	end)
	if ok then
		store = result
	else
		warn("[CrateRush] DataStore unavailable, progress will not save:", result)
	end
end

local sessions: { [Player]: Session } = {}
local rng = Random.new()

local function defaultData(): SaveData
	return {
		Coins = Config.StartingCoins,
		NextUid = 1,
		Inventory = {},
		Equipped = {},
		Opened = 0,
		Mythics = 0,
	}
end

local function sanitize(raw: any): SaveData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.Coins) == "number" then
		data.Coins = raw.Coins
	end
	if type(raw.NextUid) == "number" then
		data.NextUid = raw.NextUid
	end
	if type(raw.Opened) == "number" then
		data.Opened = raw.Opened
	end
	if type(raw.Mythics) == "number" then
		data.Mythics = raw.Mythics
	end
	if type(raw.Inventory) == "table" then
		for uid, petId in raw.Inventory do
			if type(petId) == "string" and Config.GetPet(petId) then
				data.Inventory[tostring(uid)] = petId
			end
		end
	end
	if type(raw.Equipped) == "table" then
		for _, uid in raw.Equipped do
			if data.Inventory[tostring(uid)] and #data.Equipped < Config.MaxEquipped then
				table.insert(data.Equipped, tostring(uid))
			end
		end
	end
	return data
end

local function coinsPerSecond(data: SaveData): number
	local total = Config.BaseCoinsPerSecond
	for _, uid in data.Equipped do
		local pet = Config.GetPet(data.Inventory[uid])
		if pet then
			total += pet.Power
		end
	end
	return total
end

local function snapshot(data: SaveData)
	local inventory = {}
	for uid, petId in data.Inventory do
		table.insert(inventory, { Uid = uid, PetId = petId })
	end
	return {
		Coins = data.Coins,
		CoinsPerSecond = coinsPerSecond(data),
		Inventory = inventory,
		Equipped = data.Equipped,
		Opened = data.Opened,
		Mythics = data.Mythics,
		MaxEquipped = Config.MaxEquipped,
		MaxInventory = Config.MaxInventory,
	}
end

local function inventoryCount(data: SaveData): number
	local count = 0
	for _ in data.Inventory do
		count += 1
	end
	return count
end

local function refreshPets(player: Player, data: SaveData)
	local equippedPets = {}
	for _, uid in data.Equipped do
		local pet = Config.GetPet(data.Inventory[uid])
		if pet then
			table.insert(equippedPets, pet)
		end
	end
	PetFollower.SetPets(player, equippedPets)
end

local function updateLeaderstats(session: Session)
	local stats = session.Leaderstats
	if not stats then
		return
	end
	local coins = stats:FindFirstChild("Coins") :: IntValue?
	local mythics = stats:FindFirstChild("Mythics") :: IntValue?
	if coins then
		coins.Value = math.floor(session.Data.Coins)
	end
	if mythics then
		mythics.Value = session.Data.Mythics
	end
end

local function push(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	updateLeaderstats(session)
	DataUpdated:FireClient(player, snapshot(session.Data))
end

local function save(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded or not store then
		return
	end
	local key = "Player_" .. player.UserId
	local data = session.Data
	local ok, err = pcall(function()
		store:SetAsync(key, data, { player.UserId })
	end)
	if not ok then
		warn("[CrateRush] Failed to save", player.Name, err)
	end
end

local function load(player: Player)
	local session: Session = {
		Data = defaultData(),
		Loaded = false,
		LastOpen = 0,
		Leaderstats = nil,
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
			player:Kick("Could not load your data. Please rejoin.")
			sessions[player] = nil
			return
		end
		session.Data = sanitize(result)
	end

	if not player.Parent then
		sessions[player] = nil
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	local mythics = Instance.new("IntValue")
	mythics.Name = "Mythics"
	mythics.Parent = leaderstats
	leaderstats.Parent = player
	session.Leaderstats = leaderstats

	session.Loaded = true
	refreshPets(player, session.Data)
	push(player)
end

-- Crate opening ------------------------------------------------------------

local function openCrate(player: Player, crateId: unknown)
	local session = sessions[player]
	if not session or not session.Loaded or type(crateId) ~= "string" then
		return
	end
	local crate = Config.GetCrate(crateId)
	if not crate then
		return
	end

	local now = os.clock()
	if now - session.LastOpen < Config.OpenCooldown then
		return
	end

	local data = session.Data
	if data.Coins < crate.Price then
		Notify:FireClient(player, "Not enough coins for the " .. crate.DisplayName .. "!")
		return
	end
	if inventoryCount(data) >= Config.MaxInventory then
		Notify:FireClient(player, "Your pet inventory is full! Sell some pets first.")
		return
	end

	session.LastOpen = now
	data.Coins -= crate.Price
	data.Opened += 1

	local pet = Config.Roll(crate, rng)
	local uid = tostring(data.NextUid)
	data.NextUid += 1
	data.Inventory[uid] = pet.Id

	-- Auto-equip into a free slot so new players feel the upgrade instantly.
	if #data.Equipped < Config.MaxEquipped then
		table.insert(data.Equipped, uid)
		refreshPets(player, data)
	end

	if pet.Rarity == "Mythic" then
		data.Mythics += 1
	end

	CrateResult:FireClient(player, crate.Id, pet.Id, uid)
	push(player)

	if pet.Rarity == "Legendary" or pet.Rarity == "Mythic" then
		Announce:FireAllClients(player.DisplayName, pet.Id, crate.Id)
	end
end

RequestOpen.OnServerEvent:Connect(openCrate)

WorldBuilder.Build(function(player: Player, crateId: string)
	openCrate(player, crateId)
end)

-- Pet management -----------------------------------------------------------

ToggleEquip.OnServerEvent:Connect(function(player: Player, uid: unknown)
	local session = sessions[player]
	if not session or not session.Loaded or type(uid) ~= "string" then
		return
	end
	local data = session.Data
	if not data.Inventory[uid] then
		return
	end
	local index = table.find(data.Equipped, uid)
	if index then
		table.remove(data.Equipped, index)
	elseif #data.Equipped < Config.MaxEquipped then
		table.insert(data.Equipped, uid)
	else
		Notify:FireClient(player, "You can only equip " .. Config.MaxEquipped .. " pets.")
		return
	end
	refreshPets(player, data)
	push(player)
end)

EquipBest.OnServerEvent:Connect(function(player: Player)
	local session = sessions[player]
	if not session or not session.Loaded then
		return
	end
	local data = session.Data
	local owned = {}
	for uid, petId in data.Inventory do
		local pet = Config.GetPet(petId)
		if pet then
			table.insert(owned, { Uid = uid, Power = pet.Power })
		end
	end
	table.sort(owned, function(a, b)
		return a.Power > b.Power
	end)
	data.Equipped = {}
	for i = 1, math.min(Config.MaxEquipped, #owned) do
		table.insert(data.Equipped, owned[i].Uid)
	end
	refreshPets(player, data)
	push(player)
end)

SellPet.OnServerEvent:Connect(function(player: Player, uid: unknown)
	local session = sessions[player]
	if not session or not session.Loaded or type(uid) ~= "string" then
		return
	end
	local data = session.Data
	local pet = Config.GetPet(data.Inventory[uid])
	if not pet then
		return
	end
	data.Inventory[uid] = nil
	local index = table.find(data.Equipped, uid)
	if index then
		table.remove(data.Equipped, index)
		refreshPets(player, data)
	end
	data.Coins += Config.SellValue(pet)
	push(player)
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
	return snapshot(session.Data)
end

-- Player lifecycle ---------------------------------------------------------

Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do
	task.spawn(load, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	PetFollower.Clear(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	local pending = 0
	for player in sessions do
		pending += 1
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

-- Passive income + autosave ------------------------------------------------

task.spawn(function()
	local sinceSave = 0
	while true do
		task.wait(1)
		sinceSave += 1
		for player, session in sessions do
			if session.Loaded then
				local cps = coinsPerSecond(session.Data)
				session.Data.Coins += cps
				updateLeaderstats(session)
				CoinsUpdated:FireClient(player, session.Data.Coins, cps)
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

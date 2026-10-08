--!strict
-- Global stock for limited Robux brainrots, shared by every server.
--
-- One DataStore key per item holds:
--   Sold          copies sold so far (serials 1..Stock)
--   ReservedGiven copies given after the shop stock ran out (serials Stock+1..Stock+Reserved)
--   Owners        userId -> serial (one per player; also makes Claim safe to retry)
--   Holds         userId -> unix time a reservation expires
--
-- Buying works in two steps so we never sell more copies than exist (Robux
-- can't be refunded from code): Reserve holds a copy for a few minutes before
-- the purchase prompt opens, then Claim turns the hold into a serial once
-- Roblox confirms the payment. Cancelling releases the hold.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LimitedStock = {}

local HOLD_SECONDS = 300

type Record = {
	Sold: number,
	ReservedGiven: number,
	Owners: { [string]: number },
	Holds: { [string]: number },
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotHeist_Limited_v1")
	end)
	if ok then
		store = result
	end
end

-- Used when DataStores are unavailable (Studio without API access, or
-- Studio offline): a stock count that lasts only for this test.
local memory: { [string]: Record } = {}
local studioOffline = false

local function normalize(raw: any): Record
	local record: Record = { Sold = 0, ReservedGiven = 0, Owners = {}, Holds = {} }
	if type(raw) == "table" then
		record.Sold = if type(raw.Sold) == "number" then raw.Sold else 0
		record.ReservedGiven = if type(raw.ReservedGiven) == "number" then raw.ReservedGiven else 0
		record.Owners = if type(raw.Owners) == "table" then raw.Owners else {}
		record.Holds = if type(raw.Holds) == "table" then raw.Holds else {}
	end
	-- Drop expired reservations.
	local now = os.time()
	for userId, expires in record.Holds do
		if type(expires) ~= "number" or expires <= now then
			record.Holds[userId] = nil
		end
	end
	return record
end

local function activeHolds(record: Record, exceptUserId: string?): number
	local count = 0
	for userId in record.Holds do
		if userId ~= exceptUserId then
			count += 1
		end
	end
	return count
end

-- Atomically changes an item's record. `change` may run more than once if
-- servers race, so it must only touch the record (and plain locals).
local function update(itemId: string, change: (Record) -> ()): boolean
	if not store or studioOffline then
		local record = normalize(memory[itemId])
		change(record)
		memory[itemId] = record
		return true
	end
	local ok, err = pcall(function()
		store:UpdateAsync(itemId, function(raw)
			local record = normalize(raw)
			change(record)
			return record
		end)
	end)
	if not ok then
		warn("[LimitedStock] Update failed for", itemId, err)
		if RunService:IsStudio() then
			-- Testing in Studio without a connection: keep going with a
			-- temporary count (the live game always uses the real one).
			studioOffline = true
			return update(itemId, change)
		end
	end
	return ok
end

local function publishLeft(itemId: string, record: Record)
	local item = Config.LimitedItems[itemId]
	if item then
		local left = math.max(0, item.Stock - record.Sold - activeHolds(record, nil))
		ReplicatedStorage:SetAttribute("LimitedLeft_" .. itemId, left)
	end
end

-- Holds one copy for this player. Returns ok, or false + a message.
function LimitedStock.Reserve(player: Player, itemId: string): (boolean, string?)
	local item = Config.LimitedItems[itemId]
	if not item then
		return false, "That isn't for sale."
	end
	local key = tostring(player.UserId)
	local result: string? = nil
	local ok = update(itemId, function(record)
		result = nil
		if record.Owners[key] then
			result = "You already own one!"
		elseif record.Sold + activeHolds(record, key) >= item.Stock then
			result = "SOLD OUT!"
		else
			record.Holds[key] = os.time() + HOLD_SECONDS
		end
		publishLeft(itemId, record)
	end)
	if not ok then
		return false, "The shop is busy, try again in a moment."
	end
	return result == nil, result
end

function LimitedStock.Release(player: Player, itemId: string)
	local key = tostring(player.UserId)
	update(itemId, function(record)
		record.Holds[key] = nil
		publishLeft(itemId, record)
	end)
end

-- Called once Roblox confirms payment. Returns the player's serial, or nil
-- if the DataStore failed (the receipt is retried later). Safe to call again
-- for the same player: they get the same serial.
function LimitedStock.Claim(player: Player, itemId: string): number?
	local key = tostring(player.UserId)
	local serial: number? = nil
	local ok = update(itemId, function(record)
		serial = record.Owners[key]
		if not serial then
			-- Even if their hold expired and stock ran out meanwhile, they paid,
			-- so they still get a copy.
			record.Sold += 1
			serial = record.Sold
			record.Owners[key] = record.Sold
		end
		record.Holds[key] = nil
		publishLeft(itemId, record)
	end)
	return if ok then serial else nil
end

-- Gives a copy from the shop stock as a gift (Corny's Gift button), so the
-- "X left" count goes down like a sale. Once the shop stock is gone it uses
-- the reserved copies. Works for anyone by UserId, even if they're offline.
-- Returns the serial, or nil + why not.
function LimitedStock.Gift(userId: number, name: string, itemId: string): (number?, string?)
	local item = Config.LimitedItems[itemId]
	if not item then
		return nil, "Not a limited item."
	end
	local key = tostring(userId)
	local serial: number? = nil
	local reason: string? = nil
	local ok = update(itemId, function(record)
		serial, reason = nil, nil
		if record.Owners[key] then
			reason = name .. " already owns one."
		elseif record.Sold + activeHolds(record, key) < item.Stock then
			record.Sold += 1
			serial = record.Sold
			record.Owners[key] = record.Sold
		elseif record.ReservedGiven < item.Reserved then
			record.ReservedGiven += 1
			serial = item.Stock + record.ReservedGiven
			record.Owners[key] = serial :: number
		else
			reason = "None left to give: all " .. (item.Stock + item.Reserved) .. " are taken."
		end
		record.Holds[key] = nil
		publishLeft(itemId, record)
	end)
	if not ok then
		return nil, "DataStore busy, try again."
	end
	return serial, reason
end

-- The serial this player owns (bought or gifted), if any. Used when they
-- join to deliver gifts given while they were away.
function LimitedStock.OwnedSerial(userId: number, itemId: string): number?
	local key = tostring(userId)
	if not store or studioOffline then
		local record = memory[itemId]
		return if record then record.Owners[key] else nil
	end
	local ok, raw = pcall(function()
		return store:GetAsync(itemId)
	end)
	if not ok then
		return nil
	end
	local serial = normalize(raw).Owners[key]
	return if type(serial) == "number" then serial else nil
end

-- Keeps the "X left" numbers in the shop fresh across servers.
task.spawn(function()
	while true do
		for itemId in Config.LimitedItems do
			if store and not studioOffline then
				local ok, raw = pcall(function()
					return store:GetAsync(itemId)
				end)
				if ok then
					publishLeft(itemId, normalize(raw))
				end
			else
				publishLeft(itemId, normalize(memory[itemId]))
			end
		end
		task.wait(30)
	end
end)

return LimitedStock

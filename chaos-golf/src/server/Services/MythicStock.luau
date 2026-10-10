--!strict
-- Global stock for the Mythic Featured Crate, shared by every server.
-- Reservation is atomic (DataStore UpdateAsync); other servers learn about
-- sales instantly over MessagingService and re-sync every StockRefresh seconds.

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MythicStock = {}

local KEY = "MythicSold_" .. Config.Mythic.Season
local TOPIC = "ChaosGolfMythic"

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Global")
end)

local sold = 0
local changed = Instance.new("BindableEvent")
MythicStock.Changed = changed.Event

local function set(n: number)
	if n ~= sold then
		sold = n
		changed:Fire(MythicStock.remaining())
	end
end

function MythicStock.remaining(): number
	return math.max(0, Config.Mythic.GlobalCap - sold)
end

-- Reserves one crate. Returns true on success, false when sold out or on error.
function MythicStock.reserve(): boolean
	local ds = store
	if not ds then
		-- Offline (Studio without API access): track locally.
		if sold >= Config.Mythic.GlobalCap then
			return false
		end
		set(sold + 1)
		return true
	end
	local success = false
	local ok, result = pcall(function()
		return ds:UpdateAsync(KEY, function(old: any)
			local n = if type(old) == "number" then old else 0
			if n >= Config.Mythic.GlobalCap then
				success = false
				return nil
			end
			success = true
			return n + 1
		end)
	end)
	if not ok then
		warn("[ChaosGolf] mythic reserve failed:", result)
		return false
	end
	if type(result) == "number" then
		set(result)
	end
	if success then
		pcall(function()
			MessagingService:PublishAsync(TOPIC, sold)
		end)
	end
	return success
end

-- Gives a reserved crate back (e.g. the coin payment failed afterwards).
function MythicStock.release()
	local ds = store
	if not ds then
		set(math.max(0, sold - 1))
		return
	end
	pcall(function()
		local result = ds:UpdateAsync(KEY, function(old: any)
			local n = if type(old) == "number" then old else 0
			return math.max(0, n - 1)
		end)
		if type(result) == "number" then
			set(result)
		end
	end)
end

local function refresh()
	local ds = store
	if not ds then
		return
	end
	local ok, result = pcall(function()
		return ds:GetAsync(KEY)
	end)
	if ok then
		set(if type(result) == "number" then result else 0)
	end
end

function MythicStock.start()
	-- Studio without API access hands out a DataStore whose calls all fail:
	-- probe once and fall back to local (per-server) stock tracking.
	if store and RunService:IsStudio() then
		local ds = store :: DataStore
		local ok = pcall(function()
			ds:GetAsync(KEY)
		end)
		if not ok then
			store = nil
			warn("[ChaosGolf] Studio: Mythic stock is tracked locally (enable API access to test the global stock).")
		end
	end
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local n = message.Data
			if type(n) == "number" and n > sold then
				set(n)
			end
		end)
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(Config.Mythic.StockRefresh)
		end
	end)
end

return MythicStock

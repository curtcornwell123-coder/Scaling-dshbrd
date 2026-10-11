--!strict
-- Worldwide limited stock shared by every server (the Mythic Featured Crate, limited-edition
-- balls). Reservation is atomic (DataStore UpdateAsync) and returns the buyer's copy number;
-- other servers learn about sales instantly over MessagingService and re-sync every
-- `refresh` seconds. Unpublished places (and Studio without API access) count locally.

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GlobalStock = {}

export type Stock = {
	Cap: number,
	Changed: RBXScriptSignal, -- (remaining)
	remaining: () -> number,
	sold: () -> number,
	reserve: () -> (boolean, number), -- (success, copy number)
	release: () -> (),
	start: () -> (),
}

local PUBLISHED = game.PlaceId ~= 0 -- unpublished places have no DataStores/MessagingService

function GlobalStock.new(name: string, key: string, topic: string, cap: number, refresh: number): Stock
	local store: DataStore? = nil
	if PUBLISHED then
		pcall(function()
			store = DataStoreService:GetDataStore(Config.DataStoreName .. "_Global")
		end)
	end
	local count = 0
	local changed = Instance.new("BindableEvent")

	local function remaining(): number
		return math.max(0, cap - count)
	end

	local function set(n: number)
		if n ~= count then
			count = n
			changed:Fire(remaining())
		end
	end

	local function reserve(): (boolean, number)
		local ds = store
		if not ds then
			if count >= cap then
				return false, 0
			end
			set(count + 1)
			return true, count
		end
		local success = false
		local ok, result = pcall(function()
			return ds:UpdateAsync(key, function(old: any)
				local n = if type(old) == "number" then old else 0
				if n >= cap then
					success = false
					return nil
				end
				success = true
				return n + 1
			end)
		end)
		if not ok then
			warn("[UltimateGolf] " .. name .. " reserve failed:", result)
			return false, 0
		end
		local n = if type(result) == "number" then result else count
		set(n)
		if success then
			pcall(function()
				MessagingService:PublishAsync(topic, n)
			end)
		end
		return success, n
	end

	-- Gives a reserved copy back (e.g. the payment failed afterwards).
	local function release()
		local ds = store
		if not ds then
			set(math.max(0, count - 1))
			return
		end
		pcall(function()
			local result = ds:UpdateAsync(key, function(old: any)
				local n = if type(old) == "number" then old else 0
				return math.max(0, n - 1)
			end)
			if type(result) == "number" then
				set(result)
			end
		end)
	end

	local function sync()
		local ds = store
		if not ds then
			return
		end
		local ok, result = pcall(function()
			return ds:GetAsync(key)
		end)
		if ok then
			set(if type(result) == "number" then result else 0)
		end
	end

	local function start()
		-- Web calls can stall for a long time (especially in Studio), so none of this may
		-- block server startup: everything runs in its own thread.
		task.spawn(function()
			-- Studio without API access hands out a DataStore whose calls all fail:
			-- probe once and fall back to local (per-server) counting.
			if store and RunService:IsStudio() then
				local ds = store :: DataStore
				local ok = pcall(function()
					ds:GetAsync(key)
				end)
				if not ok then
					store = nil
					warn("[UltimateGolf] Studio: " .. name .. " stock is tracked locally (enable API access to test the global stock).")
				end
			end
			if PUBLISHED then
				pcall(function()
					MessagingService:SubscribeAsync(topic, function(message)
						local n = message.Data
						if type(n) == "number" and n > count then
							set(n)
						end
					end)
				end)
			end
			while true do
				sync()
				task.wait(refresh)
			end
		end)
	end

	return {
		Cap = cap,
		Changed = changed.Event,
		remaining = remaining,
		sold = function(): number
			return count
		end,
		reserve = reserve,
		release = release,
		start = start,
	}
end

return GlobalStock

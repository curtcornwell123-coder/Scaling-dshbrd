--!strict
-- Client-side cache of the local profile with change signals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local State = {}

State.Profile = nil :: any
State.Coins = 0

local profileChanged = Instance.new("BindableEvent")
local coinsChanged = Instance.new("BindableEvent")
State.ProfileChanged = profileChanged.Event -- (profile)
State.CoinsChanged = coinsChanged.Event -- (coins, delta, reason)

function State.owns(category: string, id: string): boolean
	local p = State.Profile
	return p ~= nil and p.Owned ~= nil and p.Owned[category] ~= nil and p.Owned[category][id] == true
end

function State.equipped(category: string): string?
	local p = State.Profile
	return if p and p.Equipped then p.Equipped[category] else nil
end

-- Calls fn now (if loaded) and on every change.
function State.observe(fn: (any) -> ())
	if State.Profile then
		task.spawn(fn, State.Profile)
	end
	State.ProfileChanged:Connect(fn)
end

function State.start()
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		State.Profile = profile
		State.Coins = profile.Coins
		profileChanged:Fire(profile)
	end)
	Net.event("Coins").OnClientEvent:Connect(function(coins: number, delta: number, reason: string?)
		State.Coins = coins
		if State.Profile then
			State.Profile.Coins = coins
		end
		coinsChanged:Fire(coins, delta, reason)
	end)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Net.func("GetProfile"):InvokeServer()
		end)
		if ok and profile and not State.Profile then
			State.Profile = profile
			State.Coins = profile.Coins
			profileChanged:Fire(profile)
			coinsChanged:Fire(profile.Coins, 0, nil)
		end
	end)
end

return State

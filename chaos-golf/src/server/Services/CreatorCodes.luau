--!strict
-- Creator / streamer support codes. Entering a valid code at the East room
-- kiosk caches it on the profile and unlocks the Creator Fan skin. Every coin
-- or Robux purchase made while a code is cached is credited to that creator in
-- the CreatorSales DataStore (Roblox can't split Robux automatically, so
-- payouts are manual; see docs/Monetization.md).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Data = require(script.Parent:WaitForChild("Data"))

local CreatorCodes = {}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName .. "_CreatorSales")
end)

type Pending = { Coins: number, Robux: number, Purchases: number, Supporters: number }
local pending: { [string]: Pending } = {}
local lastSubmit: { [Player]: number } = {}
local warnedFlush = false

local function normalize(code: string): string
	return (string.upper(code):gsub("[^%w_]", ""))
end

function CreatorCodes.record(player: Player, coins: number, robux: number)
	local profile = Data.profile(player)
	local code = profile and profile.Creator
	if not code or not Config.CreatorCodes[code] then
		return
	end
	local p = pending[code] or { Coins = 0, Robux = 0, Purchases = 0, Supporters = 0 }
	p.Coins += coins
	p.Robux += robux
	p.Purchases += 1
	pending[code] = p
end

local function flush()
	local ds = store
	if not ds then
		return
	end
	local batch = pending
	pending = {}
	for code, p in batch do
		local ok, err = pcall(function()
			ds:UpdateAsync(code, function(old: any)
				local o = if type(old) == "table" then old else { Coins = 0, Robux = 0, Purchases = 0, Supporters = 0 }
				o.Coins = (o.Coins or 0) + p.Coins
				o.Robux = (o.Robux or 0) + p.Robux
				o.Purchases = (o.Purchases or 0) + p.Purchases
				o.Supporters = (o.Supporters or 0) + p.Supporters
				return o
			end)
		end)
		if not ok then
			if not warnedFlush then
				warnedFlush = true
				warn("[ChaosGolf] creator sales flush failing (will keep retrying quietly):", err)
			end
			local again = pending[code] or { Coins = 0, Robux = 0, Purchases = 0, Supporters = 0 }
			again.Coins += p.Coins
			again.Robux += p.Robux
			again.Purchases += p.Purchases
			again.Supporters += p.Supporters
			pending[code] = again
		end
	end
end

local function submit(player: Player, raw: any)
	if type(raw) ~= "string" or #raw > 24 then
		return
	end
	local t = os.clock()
	if t - (lastSubmit[player] or 0) < 2 then
		return
	end
	lastSubmit[player] = t
	local profile = Data.profile(player)
	if not profile then
		return
	end
	local code = normalize(raw)
	local entry = Config.CreatorCodes[code]
	if not entry then
		Net.event("Fx"):FireClient(player, "creatorCode", { Ok = false, Text = "That code doesn't exist" })
		return
	end
	local isNewSupporter = profile.Creator ~= code
	profile.Creator = code
	Data.markDirty(player)
	if isNewSupporter then
		local p = pending[code] or { Coins = 0, Robux = 0, Purchases = 0, Supporters = 0 }
		p.Supporters += 1
		pending[code] = p
	end
	local newSkin = Data.grantSkin(player, Config.CreatorFanSkin)
	Data.push(player)
	Net.event("Fx"):FireClient(player, "creatorCode", {
		Ok = true,
		Text = "Now supporting " .. entry.Name .. (if newSkin then "  ·  Creator Fan skin unlocked!" else ""),
	})
end

function CreatorCodes.start()
	Net.event("SubmitCreatorCode").OnServerEvent:Connect(submit)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastSubmit[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return CreatorCodes

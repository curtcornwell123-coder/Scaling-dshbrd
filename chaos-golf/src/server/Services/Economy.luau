--!strict
-- Boosted coin rewards (match payouts only): +10% per Roblox friend in the server
-- (max +40%), VIP +10%, 2x Coins pass doubles the total. Queue drip, gifts, refunds
-- and purchases are never boosted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Data = require(script.Parent:WaitForChild("Data"))
local Social = require(script.Parent:WaitForChild("Social"))

local Economy = {}

export type Breakdown = { Base: number, Friend: boolean, FriendPct: number, VIP: boolean, Double: boolean, Total: number }

local function friendBoost(player: Player): number
	return math.min(Social.friendCount(player) * Config.FriendBoostPerFriend, Config.FriendBoostMax)
end

function Economy.multiplier(player: Player): (number, boolean, boolean, boolean)
	local session = Data.get(player)
	local fb = friendBoost(player)
	local vip = session ~= nil and session.Passes.VIP == true
	local double = session ~= nil and session.Passes.DoubleCoins == true
	local m = 1 + fb + (if vip then Config.VIPBoost else 0)
	if double then
		m *= 2
	end
	return m, fb > 0, vip, double
end

function Economy.awardMatch(player: Player, base: number, reason: string): Breakdown
	local m, friend, vip, double = Economy.multiplier(player)
	local total = math.floor(base * m + 0.5)
	Data.addCoins(player, total, reason)
	return { Base = base, Friend = friend, FriendPct = math.floor(friendBoost(player) * 100 + 0.5), VIP = vip, Double = double, Total = total }
end

return Economy

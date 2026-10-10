--!strict
--[[
	SupplyConfig
	Daily Supply drops: up to ClaimsPerDay claims per UTC day, each at least CooldownSeconds after
	the previous one. Rewards[n] is paid for the n-th claim of the day. No ads, no purchases.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local SupplyConfig = {}

SupplyConfig.ClaimsPerDay = 3
SupplyConfig.CooldownSeconds = 2 * 60 * 60

local rewards: { Types.Reward } = {
	{ coins = 60 },
	{ coins = 90 },
	{ coins = 60, gems = 3 },
}
SupplyConfig.Rewards = rewards

return TableUtil.deepFreeze(SupplyConfig)

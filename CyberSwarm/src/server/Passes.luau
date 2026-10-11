--!strict
--[[
	Passes
	Game pass ownership. ProductService refreshes it from Roblox on every join (and after a purchase)
	and stores it in the profile plus a "Pass_<id>" player attribute the client can read (speed
	boost, VIP tag, shop "OWNED" labels). Ranked code never asks this module anything: no pass
	changes ranked rating, ranked payouts, or ranked loadouts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local DataService = require(script.Parent.Services.DataService)

local Passes = {}

function Passes.attributeName(passId: string): string
	return "Pass_" .. passId
end

function Passes.has(player: Player, passId: string): boolean
	if player:GetAttribute(Passes.attributeName(passId)) == true then
		return true
	end
	local data = DataService.getData(player)
	return data ~= nil and table.find(data.passes, passId) ~= nil
end

-- Casual match coin multiplier from passes (1 in ranked).
function Passes.coinMultiplier(player: Player, ranked: boolean): number
	if ranked then
		return 1
	end
	local multiplier = 1
	if Passes.has(player, "DoubleCash") then
		multiplier *= 2
	end
	if Passes.has(player, "VIP") then
		multiplier *= 1.25
	end
	return multiplier
end

function Passes.known(passId: string): boolean
	return ShopConfig.GamePasses[passId] ~= nil
end

return Passes

--!strict
--[[
	SupplyRules
	Daily Supply drop rules: a fixed number of claims per UTC day with a cooldown between them.
	Pure; SupplyService applies the result to saved data.
]]

local Types = require(script.Parent.Parent.Types)
local Calendar = require(script.Parent.Calendar)

local SupplyRules = {}

-- Claims used today (a stored count from a previous day counts as zero).
function SupplyRules.claimsToday(supply: Types.SupplyData, now: number): number
	if supply.day ~= Calendar.dayNumber(now) then
		return 0
	end
	return supply.claims
end

-- When the next claim becomes available, or nil if none are left today.
function SupplyRules.nextAvailableAt(
	supply: Types.SupplyData,
	now: number,
	claimsPerDay: number,
	cooldown: number
): number?
	local used = SupplyRules.claimsToday(supply, now)
	if used >= claimsPerDay then
		return nil
	end
	if used == 0 then
		return now
	end
	return math.max(now, supply.lastClaimAt + cooldown)
end

-- Returns an ErrorCode value ("OK" when a claim may happen now).
function SupplyRules.check(supply: Types.SupplyData, now: number, claimsPerDay: number, cooldown: number): string
	local available = SupplyRules.nextAvailableAt(supply, now, claimsPerDay, cooldown)
	if available == nil then
		return "SUPPLY_LIMIT"
	end
	if available > now then
		return "SUPPLY_COOLDOWN"
	end
	return "OK"
end

-- Records a claim and returns its 1-based index for today.
function SupplyRules.apply(supply: Types.SupplyData, now: number): number
	local index = SupplyRules.claimsToday(supply, now) + 1
	supply.day = Calendar.dayNumber(now)
	supply.claims = index
	supply.lastClaimAt = now
	return index
end

return SupplyRules

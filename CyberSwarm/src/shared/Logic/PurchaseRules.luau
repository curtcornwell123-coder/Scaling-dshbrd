--!strict
--[[
	PurchaseRules
	Decides whether a troop purchase is allowed. Pure, so every rejection path is unit-tested;
	TroopShopService gathers the facts from server state and applies the result atomically.
]]

local Types = require(script.Parent.Parent.Types)
local Requirements = require(script.Parent.Requirements)

export type Context = {
	troop: Types.TroopDef?,
	inStock: boolean,
	progress: Requirements.Progress,
	coins: number,
	gems: number,
}

local PurchaseRules = {}

-- Returns an ErrorCode value ("OK" when the purchase may proceed).
function PurchaseRules.check(context: Context): string
	local troop = context.troop
	if troop == nil then
		return "UNKNOWN_TROOP"
	end
	if troop.comingSoon then
		return "COMING_SOON"
	end
	if table.find(context.progress.owned, troop.id) ~= nil then
		return "ALREADY_OWNED"
	end
	if not context.inStock then
		return "NOT_IN_STOCK"
	end
	if not Requirements.isMet(troop.unlock, context.progress) then
		return "REQUIREMENT_NOT_MET"
	end
	if troop.currency == "Gems" then
		if context.gems < troop.price then
			return "NOT_ENOUGH_GEMS"
		end
	elseif context.coins < troop.price then
		return "NOT_ENOUGH_COINS"
	end
	return "OK"
end

return PurchaseRules

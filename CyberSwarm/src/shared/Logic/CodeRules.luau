--!strict
--[[
	CodeRules
	Promo code checks. The code list itself is server-only (ServerScriptService), so exploiters
	cannot read unreleased codes; this module only holds the rules. Pure.
]]

local Types = require(script.Parent.Parent.Types)

export type CodeDef = {
	reward: Types.Reward,
	-- Unix time after which the code stops working (0 = never expires).
	expiresAt: number,
}

local MAX_LENGTH = 32

local CodeRules = {}

-- Uppercase, trimmed, letters and digits only. Returns nil for anything else.
function CodeRules.normalize(raw: unknown): string?
	if type(raw) ~= "string" then
		return nil
	end
	local text = raw :: string
	if #text == 0 or #text > MAX_LENGTH then
		return nil
	end
	local trimmed = string.upper((string.gsub(text, "^%s*(.-)%s*$", "%1")))
	if #trimmed == 0 or string.find(trimmed, "[^%w]") ~= nil then
		return nil
	end
	return trimmed
end

-- Returns an ErrorCode value ("OK" when the code may be redeemed).
function CodeRules.check(code: CodeDef?, codeId: string, now: number, redeemed: { string }): string
	if code == nil then
		return "CODE_INVALID"
	end
	if code.expiresAt > 0 and now >= code.expiresAt then
		return "CODE_EXPIRED"
	end
	if table.find(redeemed, codeId) ~= nil then
		return "CODE_USED"
	end
	return "OK"
end

return CodeRules

--!strict
--[[
	CodeService
	Promo code redemption. The client sends the typed text only; CodeRules normalises it
	(trimmed, upper-case, letters and digits, max length) and the server-only CodeConfig decides
	what it is worth. Each code works once per player; redeemed codes are saved in the profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CodeRules = require(ReplicatedStorage.Shared.Logic.CodeRules)
local CodeConfig = require(script.Parent.Parent.Config.CodeConfig)
local Actions = require(script.Parent.Parent.Actions)
local Rewards = require(script.Parent.Parent.Rewards)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)

local ErrorCode = Constants.ErrorCode

local CodeService = {}

local function redeem(player: Player, codeId: string): string
	if DataService.isSandboxed(player) then
		return ErrorCode.Sandbox
	end
	local code = ErrorCode.DataNotLoaded
	local granted: Types.Reward? = nil
	DataService.update(player, function(data)
		code = CodeRules.check(CodeConfig.Codes[codeId], codeId, os.time(), data.codes)
		if code ~= ErrorCode.Ok then
			return
		end
		table.insert(data.codes, codeId)
		granted = Rewards.apply(data, CodeConfig.Codes[codeId].reward)
	end)
	local final = granted
	if final ~= nil then
		Notifier.banner({ player }, "Success", "CODE REDEEMED", Rewards.describe(final))
	end
	return code
end

function CodeService.start()
	Remotes.RequestRedeemCode:connect(function(player: Player, raw: unknown)
		local codeId = CodeRules.normalize(raw)
		Actions.run(player, "RedeemCode", codeId, function(): string
			if codeId == nil then
				return ErrorCode.CodeInvalid
			end
			return redeem(player, codeId)
		end)
	end)
end

return CodeService

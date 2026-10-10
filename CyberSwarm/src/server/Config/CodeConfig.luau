--!strict
--[[
	CodeConfig (server only)
	Promo codes live in ServerScriptService so clients can never read unreleased codes. Keys are
	upper-case letters and digits; expiresAt is unix time (0 = never expires). Each player can
	redeem each code once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodeRules = require(ReplicatedStorage.Shared.Logic.CodeRules)

local CodeConfig = {}

local codes: { [string]: CodeRules.CodeDef } = {
	WELCOME = { reward = { coins = 250 }, expiresAt = 0 },
	SWARMUP = { reward = { coins = 150, gems = 10 }, expiresAt = 1798761600 }, -- until 2027-01-01
	DUELS = { reward = { gems = 15 }, expiresAt = 1798761600 },
}
CodeConfig.Codes = codes

return table.freeze(CodeConfig)

--!strict
--[[
	InputController
	Keyboard and gamepad shortcuts for the match HUD: 1-5 spawn the matching loadout slot, Q/E (or
	the shoulder buttons) cycle lanes. Bindings exist only while a match is active and are dropped
	when it closes. Touch players use the large HUD buttons instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local ClientState = require(script.Parent.Parent.ClientState)
local HudController = require(script.Parent.HudController)

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
}

local LANE_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.Q] = -1,
	[Enum.KeyCode.E] = 1,
	[Enum.KeyCode.ButtonL1] = -1,
	[Enum.KeyCode.ButtonR1] = 1,
}

local InputController = {}

local maid = Maid.new()
local matchMaid = Maid.new()
local bound = false

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	-- Typing in chat or a text box must never spawn robots.
	if gameProcessed then
		return
	end
	local slot = SLOT_KEYS[input.KeyCode]
	if slot ~= nil then
		HudController.trySpawn(slot)
		return
	end
	local laneDelta = LANE_KEYS[input.KeyCode]
	if laneDelta ~= nil then
		HudController.cycleLane(laneDelta)
	end
end

local function onMatchChanged(_snapshot: Types.MatchSnapshot)
	if bound then
		return
	end
	bound = true
	matchMaid:give(UserInputService.InputBegan:Connect(onInputBegan))
end

local function onMatchClosed()
	bound = false
	matchMaid:cleanup()
end

function InputController.init()
	maid:give(matchMaid)
	maid:give(ClientState.matchChanged:connect(onMatchChanged))
	maid:give(ClientState.matchClosed:connect(onMatchClosed))
end

return InputController

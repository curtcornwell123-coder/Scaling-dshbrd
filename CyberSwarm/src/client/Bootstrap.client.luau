--!strict
--[[
	Bootstrap (client)
	The only LocalScript. Waits for the place to finish replicating, connects to the remotes, builds
	every controller in dependency order, then asks the server for a full state sync so the UI is
	correct even if earlier updates arrived before the controllers were listening.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Client = script.Parent
local Controllers = Client.Controllers

local ClientState = require(Client.ClientState)
local UIController = require(Controllers.UIController)
local ShopController = require(Controllers.ShopController)
local LobbyController = require(Controllers.LobbyController)
local HudController = require(Controllers.HudController)
local CameraController = require(Controllers.CameraController)
local InputController = require(Controllers.InputController)
local EffectsController = require(Controllers.EffectsController)

Remotes.init()
ClientState.start()

UIController.init()
ShopController.init()
LobbyController.init()
HudController.init()
CameraController.init()
InputController.init()
EffectsController.init()

Remotes.RequestSync:fire()

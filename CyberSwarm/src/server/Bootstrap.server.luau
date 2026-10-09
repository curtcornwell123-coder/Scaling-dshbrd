--!strict
--[[
	Bootstrap (server)
	The only server Script. Validates config, creates remotes, then initialises and starts every
	service in dependency order. init() builds state and world; start() connects events. Splitting
	the two means no service receives an event before every other service is ready.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ConfigValidator = require(ReplicatedStorage.Shared.ConfigValidator)

local Server = script.Parent
local Services = Server.Services

local DataService = require(Services.DataService)
local MapService = require(Services.MapService)
local LobbyService = require(Services.LobbyService)
local MatchService = require(Services.MatchService)
local QueueService = require(Services.QueueService)
local DebugCommands = require(Server.Debug.DebugCommands)

local issues = ConfigValidator.validateGame()
for _, issue in issues do
	warn(`[Config] {issue}`)
end
if #issues > 0 then
	warn(`[Config] {#issues} config problem(s) found. The game will still start, but fix these.`)
end

Remotes.init()

DataService.init()
MapService.init()
LobbyService.init()
QueueService.init()

DataService.start()
LobbyService.start()
MatchService.start()
QueueService.start()

if RunService:IsStudio() then
	DebugCommands.start()
	if Constants.Debug.RUN_TESTS_IN_STUDIO then
		local TestRunner = require(Server.Tests.TestRunner)
		task.spawn(TestRunner.run, Server.Tests)
	end
end

print(`[{Constants.GAME_NAME}] Server ready.`)

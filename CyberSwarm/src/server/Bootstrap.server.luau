--!strict
--[[
	Bootstrap (server)
	The only server Script. Validates config, creates remotes, then initialises and starts every
	service in dependency order. init() builds state and world; start() connects events. Splitting
	the two means no service receives an event before every other service is ready.

	A Test Realm server (a reserved server this place teleports into) runs the same code with
	DataService in read-only sandbox mode and without the lobby, queues, or parties.
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
local PartyService = require(Services.PartyService)
local LeaderboardService = require(Services.LeaderboardService)
local RankService = require(Services.RankService)
local QueueService = require(Services.QueueService)
local TroopShopService = require(Services.TroopShopService)
local QuestService = require(Services.QuestService)
local SupplyService = require(Services.SupplyService)
local CodeService = require(Services.CodeService)
local ProductService = require(Services.ProductService)
local SeasonService = require(Services.SeasonService)
local TestRealmService = require(Services.TestRealmService)
local DebugCommands = require(Server.Debug.DebugCommands)

local issues = ConfigValidator.validateGame()
for _, issue in issues do
	warn(`[Config] {issue}`)
end
if #issues > 0 then
	warn(`[Config] {#issues} config problem(s) found. The game will still start, but fix these.`)
end
for _, reminder in ConfigValidator.setupWarnings() do
	print(`[Setup] {reminder}`)
end

Remotes.init()

TestRealmService.init()
local testRealmServer = TestRealmService.isTestRealmServer()
DataService.setSandboxServer(testRealmServer)

DataService.init()
MapService.init()
LeaderboardService.init()
RankService.init()
QuestService.init()
if not testRealmServer then
	LobbyService.init()
	PartyService.init()
	QueueService.init()
end

DataService.start()
LobbyService.start()
MatchService.start()
RankService.start()
TroopShopService.start()
QuestService.start()
SupplyService.start()
CodeService.start()
ProductService.start()
SeasonService.start()
TestRealmService.start()
if not testRealmServer then
	PartyService.start()
	LeaderboardService.start()
	QueueService.start()
end

if RunService:IsStudio() then
	DebugCommands.start()
	if Constants.Debug.RUN_TESTS_IN_STUDIO then
		local TestRunner = require(Server.Tests.TestRunner)
		task.spawn(TestRunner.run, Server.Tests)
	end
end

print(`[{Constants.GAME_NAME}] Server ready{if testRealmServer then " (Test Realm)" else ""}.`)

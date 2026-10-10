--!strict
-- Chaos Golf server bootstrap. Order matters: remotes first, then services,
-- then the lobby world and the systems that live in it, and player data last
-- so every Data.Loaded listener is connected before the first profile loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.setup()

local World = script.Parent:WaitForChild("World")
local Services = script.Parent:WaitForChild("Services")
local Golf = script.Parent:WaitForChild("Golf")
local Lobby = script.Parent:WaitForChild("Lobby")

local LobbyBuilder = require(World:WaitForChild("LobbyBuilder"))

local Activity = require(Services:WaitForChild("Activity"))
local Data = require(Services:WaitForChild("Data"))
local Social = require(Services:WaitForChild("Social"))
local MythicStock = require(Services:WaitForChild("MythicStock"))
local CreatorCodes = require(Services:WaitForChild("CreatorCodes"))
local Monetization = require(Services:WaitForChild("Monetization"))
local Tags = require(Services:WaitForChild("Tags"))

local BallService = require(Golf:WaitForChild("BallService"))
local AbilityService = require(Golf:WaitForChild("AbilityService"))
local MatchService = require(Golf:WaitForChild("MatchService"))

local Voting = require(Lobby:WaitForChild("Voting"))
local Matchmaking = require(Lobby:WaitForChild("Matchmaking"))
local Shop = require(Lobby:WaitForChild("Shop"))
local Daily = require(Lobby:WaitForChild("Daily"))
local Leaderboards = require(Lobby:WaitForChild("Leaderboards"))
local Practice = require(Lobby:WaitForChild("Practice"))
local Tutorial = require(Lobby:WaitForChild("Tutorial"))

Activity.start()
Social.start()
BallService.start()
AbilityService.start()
MythicStock.start()
CreatorCodes.start()
Monetization.start()
MatchService.start()

local lobby = LobbyBuilder.build()
Activity.setLobbySpawn(lobby.SpawnCFrame)
Tags.apply(lobby)

Voting.start(lobby)
Matchmaking.start(lobby)
Shop.start(lobby)
Monetization.setCrateOpener(function(player)
	return Shop.openCrate(player, "Featured", true)
end)
Daily.start(lobby)
Leaderboards.start(lobby)
Practice.start(lobby)
Tutorial.start(lobby)

Data.start()

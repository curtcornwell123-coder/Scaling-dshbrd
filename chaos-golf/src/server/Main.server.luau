--!strict
-- Ultimate Golf server bootstrap. Order matters: remotes first, then the local
-- services, then the lobby world (characters may spawn from here on), then the
-- web-backed services and the systems that live in the lobby, and player data
-- last so every Data.Loaded listener is connected before the first profile loads.
-- Nothing before Data.start may yield on a web call.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- No characters until the lobby exists: an early spawn has no floor and falls into
-- the void (the place file also ships with this off; this covers older copies).
Players.CharacterAutoLoads = false

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

-- Template leftovers would show outdoors or steal spawns: the world is code-built.
for _, child in workspace:GetChildren() do
	if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
		child:Destroy()
	end
end
local terrain = workspace:FindFirstChildOfClass("Terrain")
if terrain then
	terrain:Clear()
end

local lobby = LobbyBuilder.build()
Activity.setLobbySpawn(lobby.SpawnCFrame)
Tags.apply(lobby)

-- The world exists now: let characters in (anyone already waiting spawns on the lobby pad).
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(player.LoadCharacter, player)
	end
end

MythicStock.start()
CreatorCodes.start()
Monetization.start()
MatchService.start()

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

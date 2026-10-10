--!strict
--[[
	LobbyBuilder
	BuildLobby() generates the whole Lobby v2 facility from Parts into one Folder: the circular
	hub, the hallways, the Duels Hall, the Troop Depot (with the Test Realm glass wall), the
	Market, and the party alcove. Everything is original low-poly geometry; see World/Lobby/* for
	each area and Layout for where they sit.

	Gameplay hooks are tags and attributes on the built parts (queue pads, party pads, terminals,
	screens, spinners, blast doors, the Test Realm portal). Services and client controllers find
	them through CollectionService, so moving an area never needs code changes elsewhere.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Layout = require(script.Parent.Lobby.Layout)
local Hub = require(script.Parent.Lobby.Hub)
local Hallway = require(script.Parent.Lobby.Hallway)
local DuelsHall = require(script.Parent.Lobby.DuelsHall)
local TroopDepot = require(script.Parent.Lobby.TroopDepot)
local Market = require(script.Parent.Lobby.Market)
local Alcove = require(script.Parent.Lobby.Alcove)

export type Lobby = {
	folder: Folder,
	spawns: { SpawnLocation },
	-- Where players land when sent back to the Duels Hall (match start failed).
	duelsReturn: CFrame,
	doors: { DuelsHall.BlastDoor },
	-- Everything inside this box (lobby-local) is the safe zone.
	bounds: { min: Vector3, max: Vector3 },
}

local LobbyBuilder = {}

local function applyLighting()
	-- Warm, even daylight for a concrete facility; accents carry the colour, not the sky.
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(104, 100, 94)
	Lighting.OutdoorAmbient = Color3.fromRGB(132, 128, 120)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	if Lighting:FindFirstChild("CyberSwarmBloom") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "CyberSwarmBloom"
		bloom.Intensity = 0.12
		bloom.Size = 16
		bloom.Threshold = 1.7
		bloom.Parent = Lighting
	end
	if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 0.6
		atmosphere.Color = Color3.fromRGB(214, 206, 192)
		atmosphere.Decay = Color3.fromRGB(150, 140, 126)
		atmosphere.Parent = Lighting
	end
end

function LobbyBuilder.BuildLobby(parent: Instance): Lobby
	applyLighting()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	local origin = CFrame.new(Constants.World.LOBBY_ORIGIN)

	local hub = Hub.build(folder, origin)
	local duels = DuelsHall.build(folder, origin)
	TroopDepot.build(folder, origin)
	Market.build(folder, origin)
	Alcove.build(folder, origin)

	local Areas = Theme.Areas
	local hubEdge = Layout.HUB_RADIUS + Layout.WALL_THICKNESS
	Hallway.build(folder, origin, Layout.Openings.Duels, hubEdge, Layout.DUELS_CENTER.Z - Layout.DUELS_RADIUS - 1.5, Areas.Duels, "DUELS")
	Hallway.build(folder, origin, Layout.Openings.Troops, hubEdge, Layout.DEPOT_MIN_X - Layout.WALL_THICKNESS, Areas.Troops, "TROOP DEPOT")
	Hallway.build(folder, origin, Layout.Openings.Market, hubEdge, -Layout.MARKET_MAX_X - Layout.WALL_THICKNESS, Areas.Market, "MARKET")
	Hallway.build(folder, origin, Layout.Openings.Alcove, hubEdge, -Layout.ALCOVE_NEAR_Z - Layout.WALL_THICKNESS, Areas.Party, "PARTY & ARMORY")

	folder.Parent = parent
	return {
		folder = folder,
		spawns = hub.spawns,
		duelsReturn = duels.returnPoint,
		doors = duels.doors,
		bounds = {
			min = Constants.World.LOBBY_ORIGIN + Vector3.new(Layout.MARKET_MIN_X - 60, -20, Layout.ALCOVE_FAR_Z - 10),
			max = Constants.World.LOBBY_ORIGIN + Vector3.new(Layout.DEPOT_MAX_X + 60, 80, Layout.DUELS_CENTER.Z + Layout.DUELS_RADIUS + 10),
		},
	}
end

return LobbyBuilder

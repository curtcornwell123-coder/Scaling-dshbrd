--!strict
-- Marks lobby parts that clients render personal UIs on (CollectionService
-- tags + attributes), so client code never depends on model names.

local CollectionService = game:GetService("CollectionService")

local LobbyTypes = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("LobbyTypes"))

local Tags = {}

local function tag(part: Instance?, name: string, attrs: { [string]: any }?)
	if not part then
		return
	end
	CollectionService:AddTag(part, name)
	if attrs then
		for k, v in attrs do
			part:SetAttribute(k, v)
		end
	end
end

function Tags.apply(lobby: LobbyTypes.Lobby)
	tag(lobby.Stations.Locker.Screen, "CatalogScreen")
	tag(lobby.Stations.Locker.Pedestal, "LockerPedestal")
	tag(lobby.Stations.Locker.Prev, "LockerButton", { Action = "prev" })
	tag(lobby.Stations.Locker.Next, "LockerButton", { Action = "next" })
	tag(lobby.Stations.Locker.Equip, "LockerButton", { Action = "equip" })
	tag(lobby.Stations.Upgrades.Screen, "UpgradeScreen")
	tag(lobby.Stations.CreatorKiosk.Screen, "CreatorScreen")
	tag(lobby.Daily.Screen, "DailyScreen")
	tag(lobby.Daily.Button, "DailyButton")
	tag(lobby.North.InviteKiosk, "InviteKiosk")
	for i, sign in lobby.North.VoteSigns do
		tag(sign.Pad, "VotePad", { Index = i })
		tag(sign.Display, "VoteDisplay", { Index = i })
	end
	for stat, board in lobby.West.Boards do
		tag(board.Panel, "BoardPanel", { Board = stat })
	end
end

return Tags

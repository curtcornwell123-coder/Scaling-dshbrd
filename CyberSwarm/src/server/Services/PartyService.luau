--!strict
--[[
	PartyService
	Parties are formed in-world, in the hub alcove: players who stand on the FORM pad together for
	Constants.Lobby.PARTY_FORM_TIME become a party (the first to arrive leads, or the existing
	leader if one of them already has a party with room). Standing on the LEAVE pad leaves it.
	There is no remote for any of this.

	A party leader standing on a Duels bay pad queues the whole party (QueueService asks this
	service who is in it). Members follow the leader into matches and the Test Realm.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Notifier = require(script.Parent.Parent.Notifier)

local LOBBY = Constants.Lobby

export type Party = {
	id: number,
	leader: Player,
	-- Leader first, then join order.
	members: { Player },
}

type Pad = {
	part: BasePart,
	action: string,
}

local PartyService = {}

PartyService.changed = Signal.new() :: Signal.Signal<Party?>

local parties: { [Player]: Party } = {}
local pads: { Pad } = {}
local onPadSince: { [Player]: { action: string, since: number } } = {}
local nextPartyId = 0

local function broadcast(party: Party)
	local names: { string } = {}
	for _, member in party.members do
		table.insert(names, member.DisplayName)
	end
	Remotes.PartyUpdated:fireClients(party.members, { members = names, leader = party.leader.DisplayName })
	PartyService.changed:fire(party)
end

function PartyService.partyOf(player: Player): Party?
	return parties[player]
end

function PartyService.isLeader(player: Player): boolean
	local party = parties[player]
	return party ~= nil and party.leader == player
end

function PartyService.leave(player: Player)
	local party = parties[player]
	if party == nil then
		return
	end
	parties[player] = nil
	local index = table.find(party.members, player)
	if index ~= nil then
		table.remove(party.members, index)
	end
	if player.Parent ~= nil then
		Remotes.PartyUpdated:fireClient(player, { members = {}, leader = nil })
	end
	if #party.members <= 1 then
		-- A party of one is no party.
		for _, member in party.members do
			parties[member] = nil
			Remotes.PartyUpdated:fireClient(member, { members = {}, leader = nil })
		end
		table.clear(party.members)
		PartyService.changed:fire(nil)
		return
	end
	if party.leader == player then
		party.leader = party.members[1]
		Notifier.toast(party.members, "Info", `{party.leader.DisplayName} now leads the party.`)
	end
	broadcast(party)
end

local function join(party: Party, player: Player): boolean
	if parties[player] ~= nil or #party.members >= LOBBY.MAX_PARTY then
		return false
	end
	parties[player] = party
	table.insert(party.members, player)
	return true
end

local function padUnder(player: Player): Pad?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	for _, pad in pads do
		local offset = pad.part.CFrame:PointToObjectSpace(root.Position)
		local half = pad.part.Size * 0.5
		if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z and offset.Y >= 0 and offset.Y <= 8 then
			return pad
		end
	end
	return nil
end

local function formFrom(group: { Player })
	-- Earliest arrival first, so the first one on the pad leads a brand-new party.
	table.sort(group, function(a: Player, b: Player)
		return onPadSince[a].since < onPadSince[b].since
	end)
	local party: Party? = nil
	for _, player in group do
		local existing = parties[player]
		if existing ~= nil and #existing.members < LOBBY.MAX_PARTY then
			party = existing
			break
		end
	end
	local changed = false
	if party == nil then
		local leader = group[1]
		if parties[leader] ~= nil then
			return
		end
		nextPartyId += 1
		local created: Party = { id = nextPartyId, leader = leader, members = { leader } }
		parties[leader] = created
		party = created
		changed = true
	end
	local target = party :: Party
	for _, player in group do
		if parties[player] == nil and join(target, player) then
			changed = true
		end
	end
	if changed then
		broadcast(target)
	end
end

local function tick()
	local now = os.clock()
	local ready: { Player } = {}
	for _, player in Players:GetPlayers() do
		local pad = padUnder(player)
		if pad == nil then
			onPadSince[player] = nil
			continue
		end
		local state = onPadSince[player]
		if state == nil or state.action ~= pad.action then
			onPadSince[player] = { action = pad.action, since = now }
			continue
		end
		if pad.action == "Leave" then
			if now - state.since >= LOBBY.PAD_DWELL and parties[player] ~= nil then
				PartyService.leave(player)
			end
		elseif now - state.since >= LOBBY.PARTY_FORM_TIME then
			table.insert(ready, player)
		end
	end
	if #ready >= 2 then
		formFrom(ready)
	end
end

function PartyService.init()
	for _, instance in CollectionService:GetTagged(Constants.Tags.PartyPad) do
		local action = instance:GetAttribute(Constants.Attributes.PartyAction)
		if instance:IsA("BasePart") and (action == "Form" or action == "Leave") then
			table.insert(pads, { part = instance, action = action :: string })
		end
	end
end

function PartyService.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		onPadSince[player] = nil
		PartyService.leave(player)
	end)
	task.spawn(function()
		while true do
			task.wait(LOBBY.PAD_TICK)
			tick()
		end
	end)
end

return PartyService

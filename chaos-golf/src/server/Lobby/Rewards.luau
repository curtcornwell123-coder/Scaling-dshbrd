--!strict
-- Playtime gifts and the group reward.
--  * Gifts: tiers in Config.Playtime unlock as you stay in a session (the clock starts
--    when your profile loads); claim each from the gift button. Coin gifts are not
--    boosted; crate gifts open a free Playtime Crate. Replicated as player attributes
--    PlaytimeStart (server os.time) and GiftsClaimed ("1,3,...").
--  * Group: members of the Corny Games group claim a one-time coins + ball reward at
--    the group totem by the spawn. Non-members get the in-game join prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Parts = require(Server:WaitForChild("World"):WaitForChild("Parts"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Displays = require(script.Parent:WaitForChild("Displays"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local Rewards = {}

type Gifts = { Start: number, Claimed: { [number]: boolean } }

local gifts: { [Player]: Gifts } = {}
local busy: { [Player]: boolean } = {}

local function result(player: Player, ok: boolean, text: string)
	Net.event("Fx"):FireClient(player, "shopResult", { Ok = ok, Text = text })
end

local function sync(player: Player, g: Gifts)
	local list = {}
	for i in g.Claimed do
		table.insert(list, i)
	end
	table.sort(list)
	local parts = {}
	for _, i in list do
		table.insert(parts, tostring(i))
	end
	player:SetAttribute("PlaytimeStart", g.Start)
	player:SetAttribute("GiftsClaimed", table.concat(parts, ","))
end

function Rewards.claimGift(player: Player, index: any): boolean
	local g = gifts[player]
	local tier = if type(index) == "number" then Config.Playtime.Tiers[math.floor(index)] else nil
	if not g or not tier then
		return false
	end
	local i = math.floor(index)
	if g.Claimed[i] then
		result(player, false, "Already claimed")
		return false
	end
	local left = tier.Minutes * 60 - (os.time() - g.Start)
	if left > 0 then
		result(player, false, string.format("This gift unlocks in %d:%02d", left // 60, left % 60))
		return false
	end
	g.Claimed[i] = true
	sync(player, g)
	if tier.Coins then
		Data.addCoins(player, tier.Coins, "gift")
		Data.push(player)
		result(player, true, string.format("Gift claimed: +%d coins", tier.Coins))
	elseif tier.Crate then
		Shop.openCrate(player, tier.Crate, true)
	end
	return true
end

function Rewards.claimGroup(player: Player): boolean
	local profile = Data.profile(player)
	if not profile or busy[player] then
		return false
	end
	if profile.GroupClaimed then
		result(player, false, "You already claimed the group reward. Thanks for being in " .. Config.Group.Name .. "!")
		return false
	end
	busy[player] = true
	local ok, member = pcall(function()
		return player:IsInGroupAsync(Config.Group.Id)
	end)
	busy[player] = nil
	if not ok then
		result(player, false, "Couldn't check the group right now. Try again in a moment.")
		return false
	end
	if not member then
		Net.event("Fx"):FireClient(player, "groupPrompt", { GroupId = Config.Group.Id })
		result(player, false, "Join the " .. Config.Group.Name .. " group, then claim again")
		return false
	end
	if player.Parent ~= Players or profile.GroupClaimed then
		return false
	end
	profile.GroupClaimed = true
	Data.addCoins(player, Config.Group.Coins, "group")
	Data.grantSkin(player, Config.Group.Skin)
	Data.markDirty(player)
	Data.push(player)
	result(player, true, string.format("Group reward: +%d coins and the %s ball!", Config.Group.Coins, Skins.get(Config.Group.Skin).Name))
	return true
end

function Rewards.start(lobby: LobbyTypes.Lobby)
	Data.Loaded:Connect(function(player)
		local g: Gifts = { Start = os.time(), Claimed = {} }
		gifts[player] = g
		sync(player, g)
	end)
	Players.PlayerRemoving:Connect(function(player)
		gifts[player] = nil
		busy[player] = nil
	end)
	Shop.handle("claimGift", function(player, index)
		Rewards.claimGift(player, index)
	end)
	Shop.handle("claimGroup", function(player)
		Rewards.claimGroup(player)
	end)
	-- The group's ball, printed and spinning in front of the group panel.
	local ball = Displays.ball(lobby.Model, Displays.anchorPoint(lobby.Group.Board), Config.Group.Skin, 1.8)
	ball.Name = "GroupRewardBall"
	local prompt = Parts.prompt(lobby.Group.Button, "Claim reward", Config.Group.Name .. " group", { Distance = 10, Name = "GroupPrompt" })
	prompt.Triggered:Connect(function(player)
		Rewards.claimGroup(player)
	end)
end

return Rewards

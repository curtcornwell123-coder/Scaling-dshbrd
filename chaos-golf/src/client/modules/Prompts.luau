--!strict
-- Personalises the shared ProximityPrompts locally (owned skins say "Equip",
-- crates show your keys, upgrades show your next cost), adds the Invite
-- Friends kiosk prompt, and shows the local vote confirmation in the North room.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local DailyRewards = require(Shared:WaitForChild("DailyRewards"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Hud = require(script.Parent:WaitForChild("Hud"))
local State = require(script.Parent:WaitForChild("State"))

local Prompts = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local prompts: { [ProximityPrompt]: boolean } = {}

local function personalize(prompt: ProximityPrompt)
	local profile = State.Profile
	if not profile then
		return
	end
	local skinId = prompt:GetAttribute("SkinId")
	local crateId = prompt:GetAttribute("CrateId")
	local stat = prompt:GetAttribute("Upgrade")
	if type(skinId) == "string" then
		local skin = Skins.ById[skinId]
		if State.owns("Skins", skinId) then
			prompt.ActionText = if State.equipped("Skins") == skinId then "Equipped" else "Equip"
		elseif skin and skin.Source == "Shop" then
			prompt.ActionText = "Buy · " .. UIKit.formatNumber(Skins.price(skinId))
		end
	elseif type(crateId) == "string" then
		local crate = Crates.get(crateId)
		local keys = (profile.Keys and profile.Keys[crateId]) or 0
		if crate and crate.Keyed and keys > 0 then
			prompt.ActionText = string.format("Open · 1 Key (%d)", keys)
		elseif crate then
			local unit = if crate.Currency == "Coins" then "" else " tokens"
			prompt.ActionText = "Open · " .. UIKit.formatNumber(crate.Price) .. unit
		end
	elseif type(stat) == "string" then
		local lvl = (profile.Upgrades and profile.Upgrades[stat]) or 0
		prompt.ActionText = if lvl >= Config.Upgrades.MaxLevel then stat .. " maxed" else string.format("Upgrade %s · %s", stat, UIKit.formatNumber(Config.Upgrades.Costs[lvl + 1]))
	elseif prompt.Name == "DailyPrompt" and profile.Login then
		local day, can = DailyRewards.status(profile.Login, os.time())
		prompt.ActionText = if can then "Claim Day " .. day else "Claimed today"
	end
end

local function track(d: Instance)
	if d:IsA("ProximityPrompt") then
		prompts[d] = true
		personalize(d)
		d.AncestryChanged:Connect(function(_, parent)
			if not parent then
				prompts[d] = nil
			end
		end)
	end
end

local function refreshAll()
	for p in prompts do
		personalize(p)
	end
end

-- Invite kiosk ------------------------------------------------------------------------

local function inviteKiosk(part: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Invite friends"
	prompt.ObjectText = "+15% coins with a friend"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		else
			Hud.toast("Invites aren't available right now", T.Muted)
		end
	end)
end

-- Vote confirmation -----------------------------------------------------------------------

local voteMarker: BillboardGui? = nil

local function showVote(index: number?)
	if voteMarker then
		voteMarker:Destroy()
		voteMarker = nil
	end
	if not index then
		return
	end
	for _, display in CollectionService:GetTagged("VoteDisplay") do
		if display:GetAttribute("Index") == index and display:IsA("BasePart") then
			local g = Instance.new("BillboardGui")
			g.Name = "YourVote"
			g.Size = UDim2.fromOffset(150, 36)
			g.StudsOffsetWorldSpace = Vector3.new(0, display.Size.Y / 2 + 1.4, 0)
			g.LightInfluence = 0
			g.AlwaysOnTop = true
			g.Adornee = display
			local tag = UIKit.panel({ Size = UDim2.fromScale(1, 1), Parent = g })
			UIKit.text({ Text = "✓ YOUR VOTE", TextSize = 16, TextColor3 = T.Primary, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = tag })
			g.Parent = player:WaitForChild("PlayerGui")
			voteMarker = g
			Hud.toast("Vote locked in", T.Primary)
		end
	end
end

function Prompts.start()
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(track)
	State.ProfileChanged:Connect(refreshAll)

	local function onInvite(p: Instance)
		if p:IsA("BasePart") then
			inviteKiosk(p)
		end
	end
	for _, p in CollectionService:GetTagged("InviteKiosk") do
		onInvite(p)
	end
	CollectionService:GetInstanceAddedSignal("InviteKiosk"):Connect(onInvite)

	Net.event("Vote").OnClientEvent:Connect(showVote)
end

return Prompts

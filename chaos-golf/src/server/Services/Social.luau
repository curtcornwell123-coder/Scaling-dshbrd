--!strict
-- Friend synergy (+15% match coins while a Roblox friend is in the server),
-- overhead nametags with rank / VIP, and the Invite Friends kiosk prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ranks = require(Shared:WaitForChild("Ranks"))

local Data = require(script.Parent:WaitForChild("Data"))

local Social = {}

-- friends[a][b] = true when a and b are Roblox friends (symmetric).
local friends: { [Player]: { [Player]: boolean } } = {}

local function refreshBoost(player: Player)
	player:SetAttribute("FriendBoost", Social.hasFriendInServer(player))
end

function Social.hasFriendInServer(player: Player): boolean
	local set = friends[player]
	if not set then
		return false
	end
	for other in set do
		if other.Parent == Players then
			return true
		end
	end
	return false
end

local function onAdded(player: Player)
	friends[player] = friends[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(function()
				local ok, isFriend = pcall(function()
					return player:IsFriendsWithAsync(other.UserId)
				end)
				if ok and isFriend and player.Parent and other.Parent then
					friends[player] = friends[player] or {}
					friends[other] = friends[other] or {}
					friends[player][other] = true
					friends[other][player] = true
					refreshBoost(player)
					refreshBoost(other)
				end
			end)
		end
	end
	refreshBoost(player)
end

local function onRemoving(player: Player)
	local set = friends[player]
	friends[player] = nil
	if set then
		for other in set do
			if friends[other] then
				friends[other][player] = nil
			end
			refreshBoost(other)
		end
	end
end

-- Nametags ----------------------------------------------------------------

local function nametag(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(200, 54)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Config.Font
	name.TextScaled = true
	name.TextColor3 = Config.Colors.Text
	name.Text = player.DisplayName
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.3
	stroke.Parent = name
	name.Parent = gui

	local rank = Instance.new("TextLabel")
	rank.Name = "Rank"
	rank.BackgroundTransparency = 1
	rank.Position = UDim2.fromScale(0, 0.55)
	rank.Size = UDim2.new(1, 0, 0.42, 0)
	rank.Font = Config.FontBody
	rank.TextScaled = true
	rank.Text = ""
	local stroke2 = stroke:Clone()
	stroke2.Parent = rank
	rank.Parent = gui

	gui.Parent = head
	Social.updateNametag(player)
end

function Social.updateNametag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Nametag")
	local profile = Data.profile(player)
	if not gui or not profile then
		return
	end
	local info = Ranks.fromMMR(profile.Ranked.MMR)
	local rank = gui:FindFirstChild("Rank") :: TextLabel
	local name = gui:FindFirstChild("PlayerName") :: TextLabel
	local tags = {}
	local session = Data.get(player)
	if session and session.Passes.Founder then
		table.insert(tags, "FOUNDER")
	end
	if profile.Ranked.Played > 0 then
		table.insert(tags, info.Label)
	end
	rank.Text = table.concat(tags, " · ")
	rank.TextColor3 = info.Tier.Color
	name.TextColor3 = if session and session.Passes.VIP then Config.Colors.Gold else Config.Colors.Text
end

function Social.start()
	Players.PlayerAdded:Connect(function(player)
		onAdded(player)
		player.CharacterAdded:Connect(function(character)
			nametag(player, character)
		end)
		if player.Character then
			task.spawn(nametag, player, player.Character)
		end
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(onAdded, p)
		if p.Character then
			task.spawn(nametag, p, p.Character)
		end
	end
	Players.PlayerRemoving:Connect(onRemoving)
	Data.Loaded:Connect(function(player: Player)
		Social.updateNametag(player)
	end)
end

return Social

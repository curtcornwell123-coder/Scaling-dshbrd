--!strict
-- Draws every player's mini followers (up to 3 of their brainrots) floating
-- behind them. The server only publishes a "Followers" attribute on each
-- player ("Id:Mutation,Id,..."); the minis themselves are built locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrainrotModel = require(Shared:WaitForChild("BrainrotModel"))

local folder = Instance.new("Folder")
folder.Name = "FollowerMinis"
folder.Parent = workspace

-- Where each follower floats, relative to its owner (behind is +Z).
local OFFSETS = {
	Vector3.new(-3, 1.5, 3.5),
	Vector3.new(3, 1.5, 3.5),
	Vector3.new(0, 2.5, 5.5),
}

type Entry = { Key: string, Models: { Model } }
local entries: { [Player]: Entry } = {}

local function clear(player: Player)
	local entry = entries[player]
	if entry then
		for _, model in entry.Models do
			model:Destroy()
		end
	end
	entries[player] = nil
end

local function rebuild(player: Player)
	local key = player:GetAttribute("Followers")
	local text = if type(key) == "string" then key else ""
	local entry = entries[player]
	if entry and entry.Key == text then
		return
	end
	clear(player)
	local models = {}
	for item in string.gmatch(text, "[^,]+") do
		local brainrot, mutation = Config.Decode(item)
		if brainrot and #models < #OFFSETS then
			local model = BrainrotModel.Create(brainrot, mutation, CFrame.new(0, -500, 0), false, nil, true)
			model.Parent = folder
			table.insert(models, model)
		end
	end
	entries[player] = { Key = text, Models = models }
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Followers"):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(clear)
for _, player in Players:GetPlayers() do
	task.spawn(watch, player)
end

RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock()
	local blend = math.min(1, dt * 8)
	for player, entry in entries do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for i, model in entry.Models do
			local root = model.PrimaryPart
			if root then
				if hrp then
					local offset = OFFSETS[i]
					local bob = math.sin(t * 3 + i) * 0.3
					local target = hrp.CFrame * CFrame.new(offset.X, offset.Y + bob - 2.5, offset.Z)
					-- Snap if far away (e.g. after a respawn), otherwise glide.
					if (root.Position - target.Position).Magnitude > 40 then
						root.CFrame = target
					else
						root.CFrame = root.CFrame:Lerp(target, blend)
					end
				else
					root.CFrame = CFrame.new(0, -500, 0)
				end
			end
		end
	end
end)

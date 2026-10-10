--!strict
-- 14-day login calendar (board near spawn). The client renders the personal
-- calendar on the board's screen; claiming happens here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local DailyRewards = require(Shared:WaitForChild("DailyRewards"))
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Parts = require(Server:WaitForChild("World"):WaitForChild("Parts"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local Daily = {}

function Daily.claim(player: Player)
	local profile = Data.profile(player)
	if not profile then
		return
	end
	local now = os.time()
	local day, can = DailyRewards.status(profile.Login, now)
	if not can then
		Net.event("Fx"):FireClient(player, "shopResult", { Ok = false, Text = "Come back tomorrow for Day " .. day })
		return
	end
	local reward = DailyRewards.Days[day]
	profile.Login.Day = (day % #DailyRewards.Days) + 1
	profile.Login.LastClaim = DailyRewards.today(now)
	Data.markDirty(player)

	local coins = reward.Coins or 0
	if reward.Item then
		local item = reward.Item
		if not Data.grant(player, item.Category, item.Id) then
			coins += item.Fallback -- already owned from an earlier cycle
		else
			local def = Cosmetics.get(item.Category, item.Id)
			if def and item.Category ~= "Skins" then
				Data.equip(player, item.Category, item.Id)
			end
		end
	end
	if reward.Keys then
		for crateId, n in reward.Keys do
			Data.addKeys(player, crateId, n)
		end
	end
	if coins > 0 then
		Data.addCoins(player, coins, "daily")
	end
	Data.push(player)
	Data.saveNow(player)

	Net.event("Fx"):FireClient(player, "daily", { Day = day, Label = reward.Label, Grand = reward.Grand == true })
	if reward.Grand then
		Net.event("Fx"):FireAllClients("announce", {
			Text = player.DisplayName .. " completed the 14-day streak and claimed Eternal Dawn!",
			Color = Config.Colors.Gold,
		})
	end
end

function Daily.start(lobby: LobbyTypes.Lobby)
	local prompt = Parts.prompt(lobby.Daily.Button, "Claim reward", "Daily Rewards", { Distance = 10, Name = "DailyPrompt" })
	prompt.Triggered:Connect(Daily.claim)
	Shop.handle("claimDaily", function(player)
		Daily.claim(player)
	end)
	Data.Loaded:Connect(function(player: Player, session: Data.Session)
		local day, can = DailyRewards.status(session.Profile.Login, os.time())
		if can then
			task.delay(6, function()
				if player.Parent then
					Net.event("Toast"):FireClient(player, "Day " .. day .. " login reward is ready at the Daily Rewards board!", Config.Colors.Gold)
				end
			end)
		end
	end)
end

return Daily

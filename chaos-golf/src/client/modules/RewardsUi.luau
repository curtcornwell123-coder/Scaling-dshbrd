--!strict
-- Playtime gifts on screen: a compact gift button under the coin counter (counts
-- down to the next gift, glows when one is ready) that opens a panel listing every
-- tier. Also shows the in-game join prompt when the group reward asks for it.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local RewardsUi = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local TIERS = Config.Playtime.Tiers

local gui: ScreenGui
local giftButton: TextButton
local panel: Frame? = nil
local rows: { { Button: TextButton, Status: TextLabel } } = {}

local function elapsed(): number
	local start = player:GetAttribute("PlaytimeStart")
	if type(start) ~= "number" then
		return -1
	end
	return workspace:GetServerTimeNow() - start
end

local function claimed(): { [number]: boolean }
	local out = {}
	local s = player:GetAttribute("GiftsClaimed")
	if type(s) == "string" then
		for n in string.gmatch(s, "%d+") do
			out[tonumber(n) :: number] = true
		end
	end
	return out
end

local function rewardText(tier: { Minutes: number, Coins: number?, Crate: string? }): string
	return if tier.Coins then UIKit.formatNumber(tier.Coins) .. " coins" else "Playtime Crate"
end

local function closePanel()
	if panel then
		panel:Destroy()
		panel = nil
		rows = {}
	end
end

local function openPanel()
	if panel then
		closePanel()
		return
	end
	local card = UIKit.panel({
		Name = "Gifts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.98, 0, 0.12, 96),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 20,
		Parent = gui,
	})
	UIKit.padding(card, 12)
	UIKit.list(card, 6)
	UIKit.text({ Text = "PLAYTIME GIFTS", TextSize = 18, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, ZIndex = 21, Parent = card })
	UIKit.text({ Text = "Unlock as you play this session.", TextSize = 13, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, ZIndex = 21, Parent = card })
	rows = {}
	for i, tier in TIERS do
		local row = UIKit.card({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 10 + i, ZIndex = 21, Parent = card })
		UIKit.padding(row, 0, 10)
		UIKit.text({ Text = tier.Minutes .. " min", TextSize = 15, Font = T.FontHeavy, Size = UDim2.new(0, 60, 1, 0), ZIndex = 22, Parent = row })
		local status = UIKit.text({ Text = rewardText(tier), TextSize = 14, Font = T.FontMedium, Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -170, 1, 0), ZIndex = 22, Parent = row })
		local button = UIKit.button("Claim", "Primary", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(96, 30),
			TextSize = 14,
			ZIndex = 22,
			Parent = row,
		}, function()
			Net.event("ShopAction"):FireServer("claimGift", i)
		end)
		rows[i] = { Button = button, Status = status }
	end
	UIKit.button("Close", "Ghost", { Size = UDim2.new(1, 0, 0, 28), TextSize = 14, LayoutOrder = 100, ZIndex = 21, Parent = card }, closePanel)
	panel = card
end

local function render()
	local t = elapsed()
	if t < 0 then
		giftButton.Visible = false
		return
	end
	giftButton.Visible = true
	local done = claimed()
	local ready, nextLeft = 0, math.huge
	for i, tier in TIERS do
		local left = tier.Minutes * 60 - t
		if not done[i] then
			if left <= 0 then
				ready += 1
			else
				nextLeft = math.min(nextLeft, left)
			end
		end
		local row = rows[i]
		if row then
			if done[i] then
				UIKit.setVariant(row.Button, "Disabled", "Claimed")
			elseif left <= 0 then
				UIKit.setVariant(row.Button, "Primary", "Claim")
			else
				UIKit.setVariant(row.Button, "Disabled", UIKit.formatTime(math.ceil(left)))
			end
		end
	end
	if ready > 0 then
		UIKit.setVariant(giftButton, "Primary", if ready > 1 then "🎁  " .. ready .. " GIFTS READY" else "🎁  GIFT READY")
	elseif nextLeft < math.huge then
		UIKit.setVariant(giftButton, "Secondary", "🎁  Next gift " .. UIKit.formatTime(math.ceil(nextLeft)))
	else
		UIKit.setVariant(giftButton, "Secondary", "🎁  All gifts claimed")
	end
end

function RewardsUi.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "RewardsUi"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 6
	giftButton = UIKit.button("🎁  Gifts", "Secondary", {
		Name = "GiftButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.98, 0, 0.12, 50),
		Size = UDim2.fromOffset(180, 36),
		TextSize = 14,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, openPanel)
	gui.Parent = player:WaitForChild("PlayerGui")
	player:GetAttributeChangedSignal("GiftsClaimed"):Connect(render)
	player:GetAttributeChangedSignal("PlaytimeStart"):Connect(render)
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "groupPrompt" and type(payload) == "table" and type(payload.GroupId) == "number" then
			pcall(function()
				GroupService:PromptJoinAsync(payload.GroupId)
			end)
		end
	end)
	task.spawn(function()
		while true do
			render()
			task.wait(1)
		end
	end)
end

return RewardsUi

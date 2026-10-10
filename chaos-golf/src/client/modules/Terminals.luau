--!strict
-- Personal in-world terminal screens (SurfaceGuis in PlayerGui, so each
-- player sees their own data and can click them): stat upgrades, creator
-- code kiosk, the 14-day Daily Rewards calendar and the practice token kiosk.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local DailyRewards = require(Shared:WaitForChild("DailyRewards"))
local Minigames = require(Shared:WaitForChild("Minigames"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local State = require(script.Parent:WaitForChild("State"))

local Terminals = {}

local T = UIKit.Theme
local player = Players.LocalPlayer

local function surface(part: BasePart, canvasWidth: number, name: string): (SurfaceGui, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Adornee = part
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = canvasWidth / math.max(part.Size.X, 1)
	gui.LightInfluence = 0
	gui.MaxDistance = 40
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = T.Base
	root.BorderSizePixel = 0
	UIKit.padding(root, 18)
	root.Parent = gui
	return gui, root
end

local function onTagged(tag: string, fn: (BasePart) -> ())
	task.spawn(function()
		local part = CollectionService:GetTagged(tag)[1]
		while not part do
			CollectionService:GetInstanceAddedSignal(tag):Wait()
			part = CollectionService:GetTagged(tag)[1]
		end
		fn(part :: BasePart)
	end)
end

-- Upgrades --------------------------------------------------------------------------

local function upgrades(part: BasePart)
	local _, root = surface(part, 640, "UpgradeSurface")
	UIKit.list(root, 10)
	UIKit.text({ Text = "BALL UPGRADES", TextSize = 26, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 0, Parent = root })
	UIKit.text({ Text = "Permanent. Active in Classic, Race and Practice; off in Ranked 1v1.", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = root })
	type Row = { Pips: { Frame }, Button: TextButton, Level: TextLabel }
	local rows: { [string]: Row } = {}
	for i, stat in Config.Upgrades.Stats do
		local row = UIKit.card({ Size = UDim2.new(1, 0, 0, 74), LayoutOrder = 10 + i, Parent = root })
		UIKit.padding(row, 10, 14)
		UIKit.text({ Text = stat.Name, TextSize = 20, Size = UDim2.fromOffset(200, 24), Parent = row })
		UIKit.text({ Text = string.format("%s · +%d%% per level", stat.Desc, math.floor(stat.PerLevel * 100 + 0.5)), TextSize = 13, Font = T.FontMedium, TextColor3 = T.Muted, Position = UDim2.fromOffset(0, 26), Size = UDim2.fromOffset(330, 18), Parent = row })
		local pipsFrame = Instance.new("Frame")
		pipsFrame.BackgroundTransparency = 1
		pipsFrame.Position = UDim2.fromOffset(0, 46)
		pipsFrame.Size = UDim2.fromOffset(200, 8)
		pipsFrame.Parent = row
		UIKit.list(pipsFrame, 4, true)
		local pips = {}
		for p = 1, Config.Upgrades.MaxLevel do
			local pip = Instance.new("Frame")
			pip.Size = UDim2.fromOffset(34, 8)
			pip.BorderSizePixel = 0
			pip.BackgroundColor3 = T.SurfaceHi
			pip.LayoutOrder = p
			UIKit.corner(pip, UDim.new(0, 3))
			pip.Parent = pipsFrame
			pips[p] = pip
		end
		local level = UIKit.text({ Text = "", TextSize = 13, TextColor3 = T.Muted, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -170, 0, 4), Size = UDim2.fromOffset(80, 18), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
		local button = UIKit.button("Upgrade", "Primary", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(150, 38), Parent = row }, function()
			Net.event("ShopAction"):FireServer("upgrade", stat.Id)
		end)
		rows[stat.Id] = { Pips = pips, Button = button, Level = level }
	end
	State.observe(function(profile)
		for id, row in rows do
			local lvl = (profile.Upgrades and profile.Upgrades[id]) or 0
			for p, pip in row.Pips do
				pip.BackgroundColor3 = if p <= lvl then T.Primary else T.SurfaceHi
			end
			row.Level.Text = "Lv " .. lvl .. "/" .. Config.Upgrades.MaxLevel
			if lvl >= Config.Upgrades.MaxLevel then
				UIKit.setVariant(row.Button, "Disabled", "Maxed")
			else
				UIKit.setVariant(row.Button, "Primary", "Upgrade · " .. UIKit.formatNumber(Config.Upgrades.Costs[lvl + 1]))
			end
		end
	end)
end

-- Creator code kiosk ----------------------------------------------------------------------

local function creator(part: BasePart)
	local _, root = surface(part, 560, "CreatorSurface")
	UIKit.list(root, 10)
	UIKit.text({ Text = "SUPPORT A CREATOR", TextSize = 26, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 32), Parent = root })
	UIKit.text({ Text = "Enter a creator code. Your purchases support them, and you unlock the Creator Fan ball.", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 36), Parent = root })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.Parent = root
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -140, 1, 0)
	box.BackgroundColor3 = T.Surface
	box.BorderSizePixel = 0
	box.Font = T.Font
	box.TextSize = 20
	box.TextColor3 = T.Text
	box.PlaceholderText = "CODE"
	box.PlaceholderColor3 = T.Muted
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	UIKit.corner(box)
	UIKit.stroke(box)
	UIKit.padding(box, 0, 12)
	box.Parent = row
	local status = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 20), Parent = root })
	UIKit.button("Apply", "Primary", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 128, 1, 0), Parent = row }, function()
		if #box.Text > 0 then
			Net.event("SubmitCreatorCode"):FireServer(box.Text)
		end
	end)
	box.FocusLost:Connect(function(enter)
		if enter and #box.Text > 0 then
			Net.event("SubmitCreatorCode"):FireServer(box.Text)
		end
	end)
	State.observe(function(profile)
		if profile.Creator then
			status.Text = "Currently supporting: " .. profile.Creator
			status.TextColor3 = T.Primary
		end
	end)
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "creatorCode" then
			status.Text = payload.Text
			status.TextColor3 = if payload.Ok then T.Primary else T.Danger
		end
	end)
end

-- Daily rewards calendar -------------------------------------------------------------------

local function daily(part: BasePart)
	local _, root = surface(part, 900, "DailySurface")
	local title = UIKit.text({ Text = "DAILY REWARDS", TextSize = 28, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 34), Parent = root })
	local sub = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, -190, 0, 18), Parent = root })
	local claim = UIKit.button("Claim", "Primary", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(180, 44), Parent = root }, function()
		Net.event("ShopAction"):FireServer("claimDaily")
	end)
	local gridFrame = Instance.new("Frame")
	gridFrame.BackgroundTransparency = 1
	gridFrame.Position = UDim2.fromOffset(0, 66)
	gridFrame.Size = UDim2.new(1, 0, 1, -66)
	gridFrame.Parent = root
	UIKit.grid(gridFrame, UDim2.new(1 / 7, -8, 0.5, -6), 8)
	type Cell = { Frame: Frame, Stroke: UIStroke, Day: TextLabel, Label: TextLabel, Check: TextLabel }
	local cells: { Cell } = {}
	for i, reward in DailyRewards.Days do
		local c = UIKit.card({ LayoutOrder = i, Parent = gridFrame })
		UIKit.padding(c, 8)
		local stroke = c:FindFirstChildOfClass("UIStroke") :: UIStroke
		local dayLabel = UIKit.text({ Text = "DAY " .. i, TextSize = 13, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 16), Parent = c })
		local label = UIKit.text({
			Text = reward.Label,
			TextSize = 13,
			Font = T.FontMedium,
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 1, -40),
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = if reward.Grand then T.Gold else T.Text,
			Parent = c,
		})
		local check = UIKit.text({ Text = "", TextSize = 14, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18), Parent = c })
		if reward.Grand then
			stroke.Color = T.Gold
			stroke.Transparency = 0
		end
		cells[i] = { Frame = c, Stroke = stroke, Day = dayLabel, Label = label, Check = check }
	end
	local function render()
		local profile = State.Profile
		if not profile or not profile.Login then
			return
		end
		local day, can = DailyRewards.status(profile.Login, os.time())
		for i, cell in cells do
			local reward = DailyRewards.Days[i]
			local done = i < day
			local isToday = i == day
			cell.Frame.BackgroundColor3 = if isToday then T.SurfaceHi else T.Surface
			if isToday then
				cell.Stroke.Color = if can then T.Primary else T.Info
				cell.Stroke.Transparency = 0
			elseif not reward.Grand then
				cell.Stroke.Color = T.Stroke
				cell.Stroke.Transparency = 0.3
			end
			cell.Check.Text = if done then "✓ claimed" elseif isToday and can then "ready" elseif isToday then "claimed today" else ""
			cell.Check.TextColor3 = if done then T.Muted elseif can then T.Primary else T.Info
			cell.Label.TextTransparency = if done then 0.45 else 0
		end
		if can then
			UIKit.setVariant(claim, "Primary", "Claim Day " .. day)
			sub.Text = "Log in every day. Miss a day and the streak restarts. Day 14: the exclusive Eternal Dawn ball."
		else
			local left = DailyRewards.untilReset(os.time())
			UIKit.setVariant(claim, "Disabled", string.format("Next in %dh %02dm", left // 3600, (left % 3600) // 60))
			sub.Text = "Come back tomorrow for Day " .. day .. ". Resets at 00:00 UTC."
		end
		title.Text = "DAILY REWARDS  ·  STREAK DAY " .. math.max(day - (if can then 1 else 0), 0)
	end
	State.observe(function()
		render()
	end)
	task.spawn(function()
		while true do
			task.wait(30)
			render()
		end
	end)
end

-- Token kiosk -----------------------------------------------------------------------------

local function tokenKiosk(part: BasePart)
	local _, root = surface(part, 620, "TokenSurface")
	UIKit.list(root, 8)
	local title = UIKit.text({ Text = "", TextSize = 24, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 30), Parent = root })
	local body = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 36), Parent = root })
	local balances: { [string]: TextLabel } = {}
	for i, m in Minigames.List do
		local row = UIKit.card({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 10 + i, Parent = root })
		UIKit.padding(row, 0, 12)
		UIKit.tag(m.Token, m.Color, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Parent = row })
		balances[m.Id] = UIKit.text({ Text = "0", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(1, 1), Parent = row })
	end
	local function render()
		local active = Minigames.active(os.time())
		local crate = Crates.get(active.Id)
		title.Text = string.upper(active.Name) .. " KIOSK"
		body.Text = string.format("Now selling the %s (%d tokens) and %s skins. Tokens are earned on the lanes only.", if crate then crate.Name else "crate", if crate then crate.Price else 0, active.Name)
		local profile = State.Profile
		for id, label in balances do
			label.Text = tostring(if profile and profile.Tokens then profile.Tokens[id] or 0 else 0)
		end
	end
	State.observe(function()
		render()
	end)
	workspace:GetAttributeChangedSignal("PracticeMinigame"):Connect(render)
end

function Terminals.start()
	onTagged("UpgradeScreen", upgrades)
	onTagged("CreatorScreen", creator)
	onTagged("DailyScreen", daily)
	onTagged("TokenScreen", tokenKiosk)
end

return Terminals

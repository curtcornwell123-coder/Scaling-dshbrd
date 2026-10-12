--!strict
-- West room leaderboards, client-isolated: each player pages their own view
-- (Prev / Next / Daily-Weekly-All-Time buttons are in-world prompts) without
-- changing what anyone else sees.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Boards = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local PERIODS = { "Daily", "Weekly", "AllTime" }
local PERIOD_NAMES = { Daily = "Today", Weekly = "This week", AllTime = "All-time" }
local TITLES = { Wins = "MOST WINS", Coins = "COINS EARNED", Sabotages = "TOP SABOTEURS" }

type BoardView = {
	Stat: string,
	Period: number,
	Page: number,
	Title: TextLabel,
	Chips: { TextButton },
	Rows: Frame,
	Footer: TextLabel,
}

local data: any = {}
local views: { [string]: BoardView } = {}

local function render(v: BoardView)
	local period = PERIODS[v.Period]
	local list = (data[v.Stat] and data[v.Stat][period]) or {}
	local size = Config.Leaderboards.PageSize
	local pages = math.max(1, math.ceil(#list / size))
	v.Page = math.clamp(v.Page, 1, pages)
	for i, chip in v.Chips do
		UIKit.setVariant(chip, if i == v.Period then "Primary" else "Ghost")
	end
	for _, child in v.Rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local myRank: number? = nil
	for i, entry in list do
		if entry.UserId == player.UserId then
			myRank = i
		end
	end
	for i = (v.Page - 1) * size + 1, math.min(v.Page * size, #list) do
		local entry = list[i]
		local me = entry.UserId == player.UserId
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = if me then T.SurfaceHi else T.Surface
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		UIKit.corner(row, T.RadiusSmall)
		UIKit.padding(row, 0, 12)
		row.Parent = v.Rows
		local rankColor = if i == 1 then T.Gold elseif i == 2 then Color3.fromRGB(196, 204, 216) elseif i == 3 then Color3.fromRGB(201, 129, 75) else T.Muted
		UIKit.text({ Text = "#" .. i, TextSize = 16, TextColor3 = rankColor, Size = UDim2.new(0, 52, 1, 0), Parent = row })
		UIKit.text({ Text = entry.Name, TextSize = 16, TextColor3 = if me then T.Info else T.Text, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -170, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Parent = row })
		UIKit.text({ Text = UIKit.formatNumber(entry.Value), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(1, 1), Parent = row })
	end
	if #list == 0 then
		local empty = Instance.new("Frame")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.Parent = v.Rows
		UIKit.text({ Text = "No entries yet. Be the first!", TextSize = 16, TextColor3 = T.Muted, Size = UDim2.fromScale(1, 1), Parent = empty })
	end
	v.Footer.Text = string.format("Page %d / %d   ·   %s", v.Page, pages, if myRank then "Your rank: #" .. myRank else "You're not on this board yet")
end

local function build(panel: BasePart)
	local stat = panel:GetAttribute("Board") :: string
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board_" .. stat
	gui.Adornee = panel
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 560 / math.max(panel.Size.X, 1)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = T.Base
	root.BorderSizePixel = 0
	UIKit.padding(root, 18)
	root.Parent = gui
	local title = UIKit.text({ Text = TITLES[stat] or string.upper(stat), TextSize = 30, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 36), Parent = root })
	local chipsRow = Instance.new("Frame")
	chipsRow.BackgroundTransparency = 1
	chipsRow.Position = UDim2.fromOffset(0, 42)
	chipsRow.Size = UDim2.new(1, 0, 0, 30)
	chipsRow.Parent = root
	UIKit.list(chipsRow, 6, true)
	local chips = {}
	for i, p in PERIODS do
		chips[i] = UIKit.button(PERIOD_NAMES[p], "Ghost", { Size = UDim2.fromOffset(110, 28), TextSize = 13, LayoutOrder = i, Parent = chipsRow })
	end
	local rows = Instance.new("Frame")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, 82)
	rows.Size = UDim2.new(1, 0, 1, -112)
	rows.Parent = root
	UIKit.list(rows, 6)
	local footer = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 20), Parent = root })
	local v: BoardView = { Stat = stat, Period = 1, Page = 1, Title = title, Chips = chips, Rows = rows, Footer = footer }
	views[stat] = v
	for i, chip in chips do
		chip.Activated:Connect(function()
			v.Period = i
			v.Page = 1
			render(v)
		end)
	end
	render(v)
end

-- The physical arrow buttons carry server-created prompts; we react locally.
local function hookPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local stat = prompt:GetAttribute("Board")
	if type(stat) ~= "string" then
		return
	end
	prompt.Triggered:Connect(function()
		local v = views[stat]
		if not v then
			return
		end
		if prompt.Name == "BoardPrev" then
			v.Page -= 1
		elseif prompt.Name == "BoardNext" then
			v.Page += 1
		elseif prompt.Name == "BoardPeriod" then
			v.Period = (v.Period % #PERIODS) + 1
			v.Page = 1
		end
		render(v)
	end)
end

function Boards.start()
	for _, p in CollectionService:GetTagged("BoardPanel") do
		build(p :: BasePart)
	end
	CollectionService:GetInstanceAddedSignal("BoardPanel"):Connect(function(p)
		build(p :: BasePart)
	end)
	for _, d in workspace:GetDescendants() do
		hookPrompt(d)
	end
	workspace.DescendantAdded:Connect(hookPrompt)
	Net.event("Leaderboards").OnClientEvent:Connect(function(newData)
		data = newData
		for _, v in views do
			render(v)
		end
	end)
end

return Boards

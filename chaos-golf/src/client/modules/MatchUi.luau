--!strict
-- Transient match screens only (never persistent): intro card, hole banner,
-- turn banner, the scorecard between holes and the results card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local MatchUi = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local gui: ScreenGui
local current: GuiObject? = nil

local function clear()
	if current then
		current:Destroy()
		current = nil
	end
end

local function show(frame: GuiObject, seconds: number?)
	clear()
	current = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0.92
	scale.Parent = frame
	frame.Parent = gui
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if seconds then
		task.delay(seconds, function()
			if current == frame then
				clear()
			end
		end)
	end
end

local function banner(title: string, sub: string?, seconds: number, accent: Color3?)
	local frame = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 0.04,
	})
	UIKit.padding(frame, 10, 18)
	UIKit.list(frame, 2, false, Enum.HorizontalAlignment.Center)
	UIKit.text({ Text = title, TextSize = 24, Font = T.FontHeavy, TextColor3 = accent or T.Text, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Parent = frame })
	if sub then
		UIKit.text({ Text = sub, TextSize = 15, Font = T.FontMedium, TextColor3 = T.Muted, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Parent = frame })
	end
	show(frame, seconds)
end

local function centerPanel(width: number): Frame
	local frame = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.02,
	})
	UIKit.padding(frame, 18)
	UIKit.list(frame, 10)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(width, 560)
	constraint.Parent = frame
	return frame
end

local function intro(p: any)
	local frame = centerPanel(460)
	UIKit.tag(p.ModeName or p.Mode, T.Info, { LayoutOrder = 1, Parent = frame })
	UIKit.text({ Text = p.Map, TextSize = 34, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = frame })
	UIKit.text({ Text = p.Theme .. "  ·  " .. p.Holes .. " holes", TextSize = 16, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3, Parent = frame })
	UIKit.text({
		Text = table.concat(p.Players or {}, "   ·   "),
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = frame,
	})
	show(frame, Config.Match.IntroSeconds)
	if p.Overview then
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = p.Overview
	end
end

local function cell(parent: Instance, text: string, width: number, order: number, color: Color3?, bold: boolean?)
	UIKit.text({
		Text = text,
		TextSize = 15,
		Font = if bold then T.Font else T.FontMedium,
		TextColor3 = color or T.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0, width, 1, 0),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function scoreTable(parent: Instance, p: any, order: number)
	local holes = #(p.Pars or {})
	local race = p.Mode == "Race"
	local nameW = 150
	local colW = 34
	local function row(o: number, bg: Color3?): Frame
		local r = Instance.new("Frame")
		r.Size = UDim2.new(1, 0, 0, 30)
		r.BackgroundColor3 = bg or T.Surface
		r.BackgroundTransparency = if bg then 0 else 1
		r.BorderSizePixel = 0
		r.LayoutOrder = o
		UIKit.corner(r, T.RadiusSmall)
		UIKit.padding(r, 0, 8)
		UIKit.list(r, 0, true)
		r.Parent = parent
		return r
	end
	local head = row(order, nil)
	UIKit.text({ Text = "HOLE", TextSize = 13, TextColor3 = T.Muted, Size = UDim2.new(0, nameW, 1, 0), LayoutOrder = 0, Parent = head })
	for i = 1, holes do
		cell(head, tostring(i), colW, i, if i == p.Hole then T.Info else T.Muted, true)
	end
	cell(head, "TOT", 46, 99, T.Muted, true)
	if race then
		cell(head, "PTS", 46, 100, T.Muted, true)
	end
	local parRow = row(order + 1, nil)
	UIKit.text({ Text = "Par", TextSize = 13, TextColor3 = T.Muted, Size = UDim2.new(0, nameW, 1, 0), LayoutOrder = 0, Parent = parRow })
	local parTotal = 0
	for i = 1, holes do
		parTotal += p.Pars[i]
		cell(parRow, tostring(p.Pars[i]), colW, i, T.Muted)
	end
	cell(parRow, tostring(parTotal), 46, 99, T.Muted)
	for k, r in p.Rows or {} do
		local me = r.UserId == player.UserId
		local line = row(order + 1 + k, if me then T.SurfaceHi else T.Surface)
		UIKit.text({ Text = (if r.Left then "(left) " else "") .. r.Name, TextSize = 15, TextColor3 = if me then T.Info else T.Text, Size = UDim2.new(0, nameW, 1, 0), LayoutOrder = 0, Parent = line })
		for i = 1, holes do
			local s = r.Strokes[i]
			local color = T.Text
			if s and p.Pars[i] then
				color = if s < p.Pars[i] then T.Primary elseif s > p.Pars[i] then T.Danger else T.Text
			end
			cell(line, if s then tostring(s) else "–", colW, i, color)
		end
		cell(line, tostring(r.Total), 46, 99, T.Text, true)
		if race then
			cell(line, tostring(r.Points), 46, 100, T.Gold, true)
		end
	end
end

local function scorecard(p: any)
	local holes = #(p.Pars or {})
	local width = math.max(460, 150 + holes * 34 + 46 + (if p.Mode == "Race" then 46 else 0) + 52)
	local frame = centerPanel(width)
	UIKit.text({ Text = string.format("Hole %d of %d complete", p.Hole, p.Holes), TextSize = 22, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = frame })
	scoreTable(frame, p, 10)
	show(frame, Config.Match.ScorecardSeconds)
end

local function ordinal(n: number): string
	local suffix = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suffix = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return n .. suffix
end

local function results(p: any)
	local frame = centerPanel(480)
	local headline = if p.Players <= 1 then "Run complete" elseif p.Placement == 1 then "Victory!" else ordinal(p.Placement) .. " place"
	UIKit.text({ Text = headline, TextSize = 38, Font = T.FontHeavy, TextColor3 = if p.Placement == 1 and p.Players > 1 then T.Gold else T.Text, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, Parent = frame })
	UIKit.text({ Text = p.Map, TextSize = 15, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, Parent = frame })

	local coins = p.Coins
	local lines = { { "Match reward", "+" .. UIKit.formatNumber(coins.Base) } }
	if coins.Friend then
		table.insert(lines, { "Friend boost", "+15%" })
	end
	if coins.VIP then
		table.insert(lines, { "VIP", "+10%" })
	end
	if coins.Double then
		table.insert(lines, { "2x Coins", "x2" })
	end
	table.insert(lines, { "Total", "+" .. UIKit.formatNumber(coins.Total) .. " coins" })
	for i, l in lines do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 24)
		row.LayoutOrder = 10 + i
		row.Parent = frame
		local last = i == #lines
		UIKit.text({ Text = l[1], TextSize = 16, Font = if last then T.Font else T.FontMedium, TextColor3 = if last then T.Text else T.Muted, Size = UDim2.fromScale(0.6, 1), Parent = row })
		UIKit.text({ Text = l[2], TextSize = 16, TextColor3 = if last then T.Gold else T.Text, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(1, 1), Parent = row })
	end
	if p.Ranked then
		local r = p.Ranked
		local delta = if r.Delta >= 0 then "+" .. r.Delta else tostring(r.Delta)
		UIKit.text({
			Text = string.format("Ranked: %s  (%s)", r.Label, delta),
			TextSize = 18,
			TextColor3 = if r.Delta >= 0 then T.Primary else T.Danger,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 30,
			Parent = frame,
		})
		if r.Label ~= r.OldLabel then
			UIKit.text({ Text = (if r.Delta >= 0 then "Promoted from " else "Demoted from ") .. r.OldLabel, TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 31, Parent = frame })
		end
	end
	local extras = {}
	if p.Birdies > 0 then
		table.insert(extras, p.Birdies .. " under par")
	end
	if p.Aces > 0 then
		table.insert(extras, p.Aces .. " hole-in-one")
	end
	if p.Sabotages > 0 then
		table.insert(extras, p.Sabotages .. " sabotages")
	end
	if #extras > 0 then
		UIKit.text({ Text = table.concat(extras, "  ·  "), TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 40, Parent = frame })
	end
	show(frame, Config.Match.ResultsSeconds)
end

function MatchUi.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "ChaosGolfMatch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.event("MatchEvent").OnClientEvent:Connect(function(kind: string, p: any)
		if kind == "intro" then
			intro(p)
		elseif kind == "hole" then
			banner(string.format("HOLE %d / %d  ·  PAR %d", p.Hole, p.Holes, p.Par), p.Map, 3)
		elseif kind == "turn" then
			if p.UserId == player.UserId then
				banner("YOUR TURN", (p.Deadline and p.Deadline .. " seconds") or nil, 2.2, T.Primary)
			else
				banner(p.Name .. "'s turn", nil, 1.8)
			end
		elseif kind == "window" then
			banner("FINISH WINDOW", p.Seconds .. " seconds left to sink it!", 3, T.Gold)
		elseif kind == "scorecard" then
			scorecard(p)
		elseif kind == "results" then
			results(p)
		elseif kind == "end" then
			clear()
		end
	end)
end

return MatchUi

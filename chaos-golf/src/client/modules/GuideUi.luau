--!strict
-- Player guide and device setup.
--   * First join: "What are you playing on?" with three big cards (Console, Phone/Tablet,
--     Keyboard & Mouse). The choice is saved and every control hint follows it.
--   * The Guide: a full-screen book with tabs that explains the whole game (controls for
--     the chosen device, modes, power-ups, balls and skins, practice, rewards, shop).
--     It opens from the HUD button, G on a keyboard or the Select/View button on a
--     controller; B or Close shuts it. Built for controllers (selectable buttons, focus
--     on open, LB/RB switch tabs) and phones (scales down, every list scrolls).
-- Text is generated from the game's own config, so numbers stay right when they change.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Maps = require(Shared:WaitForChild("Maps"))
local Minigames = require(Shared:WaitForChild("Minigames"))
local Net = require(Shared:WaitForChild("Net"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Hud = require(script.Parent:WaitForChild("Hud"))
local Pad = require(script.Parent:WaitForChild("Pad"))
local State = require(script.Parent:WaitForChild("State"))

local GuideUi = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local GOLD = "#FFC83D"

local gui: ScreenGui
local hudButton: TextButton
local picker: Frame? = nil
local book: Frame? = nil
local bookTab = "Controls"
local bookDevice: Pad.Device = "pc"

local function gold(s: string): string
	return string.format('<font color="%s"><b>%s</b></font>', GOLD, s)
end

local function b(s: string): string
	return "<b>" .. s .. "</b>"
end

local function n(x: number): string
	return UIKit.formatNumber(x)
end

-- Content ---------------------------------------------------------------------------

type Section = { Title: string, Lines: { string } }

local DEVICE_NAMES: { [string]: string } = { pad = "Console", touch = "Phone & Tablet", pc = "Keyboard & Mouse" }

local function controls(d: Pad.Device): { Section }
	if d == "pad" then
		return {
			{ Title = "Walking the clubhouse", Lines = {
				b("Left stick") .. " walks, " .. b("right stick") .. " turns the camera, " .. b("A") .. " jumps.",
				"Walk up to a station or case and press " .. b("X") .. " when the prompt appears (buy, open, claim).",
				b("Select / View") .. " opens this guide. In any menu, the " .. b("D-pad") .. " moves, " .. b("A") .. " picks and " .. b("B") .. " closes.",
			} },
			{ Title = "Putting (you are the ball)", Lines = {
				b("Aim") .. ": turn the camera with the " .. b("right stick") .. ". The arrow on the green shows your line.",
				b("Power") .. ": hold " .. b("R2") .. " to charge, release to putt. Longer hold = harder shot.",
				b("Power-ups") .. ": " .. b("X") .. ", " .. b("Y") .. " and " .. b("L1") .. " use slots 1, 2 and 3.",
				b("B") .. " skips the tutorial or leaves a practice lane.",
			} },
		}
	elseif d == "touch" then
		return {
			{ Title = "Walking the clubhouse", Lines = {
				"Use the " .. b("thumbstick") .. " (bottom left) to walk and " .. b("drag") .. " anywhere else to turn the camera.",
				"Walk up to a station or case and " .. b("tap the prompt") .. " that appears (buy, open, claim).",
				"The " .. b("Guide") .. " button (top right) opens this guide. Every list in a menu scrolls with a swipe.",
			} },
			{ Title = "Putting (you are the ball)", Lines = {
				b("Aim") .. ": drag on the screen to turn the camera. The arrow on the green shows your line.",
				b("Power") .. ": press and hold the " .. b("PUTT") .. " button, let go to shoot. Longer hold = harder shot.",
				b("Power-ups") .. ": tap the ability buttons next to PUTT.",
				"The " .. b("SKIP") .. " / " .. b("EXIT") .. " button leaves the tutorial or a practice lane.",
			} },
		}
	end
	return {
		{ Title = "Walking the clubhouse", Lines = {
			b("W A S D") .. " walk, " .. b("Space") .. " jumps, hold " .. b("Right Click") .. " and drag to turn the camera, " .. b("scroll") .. " to zoom.",
			"Walk up to a station or case and press " .. b("E") .. " when the prompt appears (buy, open, claim).",
			b("G") .. " opens this guide. Menus work with the mouse; " .. b("B") .. " on a controller or the Close button shuts them.",
		} },
		{ Title = "Putting (you are the ball)", Lines = {
			b("Aim") .. ": hold " .. b("Right Click") .. " and drag. The arrow on the green shows your line.",
			b("Power") .. ": hold " .. b("Left Click") .. " (or " .. b("Space") .. ") to charge, release to putt.",
			b("Power-ups") .. ": " .. b("1") .. ", " .. b("2") .. " and " .. b("3") .. " use slots 1, 2 and 3.",
			b("X") .. " skips the tutorial or leaves a practice lane.",
		} },
	}
end

local function modes(): { Section }
	local out: { Section } = {}
	for _, id in Config.ModeOrder do
		local m = Config.Modes[id]
		local lines = {
			string.format("%s players · %d holes · %s.", if m.MinPlayers == m.MaxPlayers then tostring(m.MaxPlayers) else m.MinPlayers .. "–" .. m.MaxPlayers, m.Holes,
				if m.Simultaneous then "everyone putts at the same time" else "turn-based, " .. (m.TurnTime or 25) .. " seconds per turn"),
			if m.BallCollide then "Balls collide: knock rivals off the course for a knockout." else "Balls pass through each other: pure skill.",
		}
		if m.Ranked then
			table.insert(lines, "Everyone starts " .. b("Unranked") .. ": win " .. Config.Ranked.PlacementWins .. " Ranked games to place in " .. b("Bronze") .. ", then win to climb " .. b("MMR") .. " through " .. #Ranks.Tiers .. " tiers (Bronze to Chaos Legend); Gold, Diamond, Onyx and Chaos Legend unlock a ball.")
			table.insert(lines, "Ball upgrades are " .. b("off") .. " in Ranked; everyone starts with the same two power-ups.")
		elseif id == "Race" then
			table.insert(lines, string.format("When the first ball sinks, the rest have %d seconds. Points per place: %s.", m.FinishWindow or 30, table.concat(Config.Match.RacePoints, " / ")))
		else
			table.insert(lines, "Lowest total strokes over the round wins.")
		end
		table.insert(out, { Title = m.Display, Lines = lines })
	end
	local themes = {}
	for _, t in Maps.Themes do
		table.insert(themes, t.Name)
	end
	table.sort(themes)
	table.insert(out, { Title = "Courses", Lines = {
		string.format("%d courses of 6 holes across %d worlds: %s.", #Maps.List, #themes, table.concat(themes, ", ")),
		"Obstacles: windmills, spinners, pushers, bumpers, bridges, humps, tunnels, sand (slow), ice (slippery) and " .. b("boost pads") .. " (they launch you forward).",
		b("Boost jumps") .. ": a boost lane into a ramp sends you flying over a gap. Roll onto it with any speed and the boost does the rest; fall short and it's out of bounds (+1 stroke). Ocean Piers maps are full of them.",
	} })
	table.insert(out, { Title = "Joining a match", Lines = {
		"Go to " .. b("Matchmaking") .. " and stand in a mode's bubble. The match starts when enough players are in.",
		"Vote for the next map on the vote pads. Standing in a bubble pays a few coins while you wait.",
		string.format("Each hole has a %d second limit and strokes are capped at par + %d, so nobody gets stuck.", Config.Match.HoleTimeLimit, Config.Match.StrokeCapOverPar),
	} })
	return out
end

local function powerUps(): { Section }
	local list = {}
	for _, a in Abilities.List do
		table.insert(list, string.format("%s %s: %s.", a.Icon, b(a.Name), a.Desc))
	end
	local ranked = Config.Modes.Ranked
	local start = {}
	local fixed: { string } = ranked.StartAbilities or {}
	for _, id in fixed do
		local def = Abilities.get(id)
		if def then
			table.insert(start, def.Name)
		end
	end
	return {
		{ Title = "How you get them", Lines = {
			"Power-ups are " .. b("never sold") .. ". You earn them by playing:",
			"• Sink a hole: " .. gold("+1") .. " random power-up.",
			"• Knock a rival out of bounds: " .. gold("+1") .. " random power-up.",
			"• Roll through a glowing " .. b("chaos box") .. " (Classic and Race): " .. gold("+1") .. ".",
			string.format("You hold up to %d at once. They last the whole match and reset for the next one.", Config.Match.MaxAbilities),
		} },
		{ Title = "How many you start with", Lines = {
			b("Ranked 1v1") .. ": " .. #start .. " fixed (" .. table.concat(start, " + ") .. "), no chaos boxes.",
			b("Classic") .. ": " .. (Config.Modes.Classic.StartRandomAbilities or 0) .. " random, plus chaos boxes on the course.",
			b("Race") .. ": " .. (Config.Modes.Race.StartRandomAbilities or 0) .. " random, plus chaos boxes on the course.",
			b("Practice") .. " and the " .. b("tutorial") .. ": no power-ups, just your putting.",
		} },
		{ Title = "All power-ups", Lines = list },
	}
end

local function balls(): { Section }
	local rarities = {}
	for _, r in Skins.RarityOrder do
		table.insert(rarities, string.format('<font color="#%s"><b>%s</b></font>', Skins.Rarities[r].Color:ToHex(), r))
	end
	local boards = {}
	for stat, id in Config.Leaderboards.Rewards :: { [string]: string } do
		table.insert(boards, Skins.get(id).Name .. " (" .. stat .. ")")
	end
	table.sort(boards)
	return {
		{ Title = "Your ball", Lines = {
			"Every ball is a dimpled tour ball. A " .. b("skin") .. " changes its finish and its printing: brand stamp, model line, play number, alignment line, emblem and stripes.",
			"Rarities: " .. table.concat(rarities, " · ") .. ". Epic and up have an aura; Legendary and up glow.",
			"Equip what you own at the " .. b("Locker") .. " station. Skins are looks only: they never change how the ball plays.",
		} },
		{ Title = "Where balls come from", Lines = {
			b("Pro Shop cases") .. string.format(": a new set of 12 every %d minutes (1 Legendary, 2 Epic).", math.floor(Skins.RotationSeconds / 60)),
			b("Ball Skin Crate") .. ": odds are on the screen behind it, with a guaranteed Legendary if you get unlucky.",
			b("Mythic Featured Crate") .. string.format(": limited worldwide stock (%s per season).", n(Config.Mythic.GlobalCap)),
			b(Skins.get(Config.Limited.Skin).Name) .. string.format(": only %d will ever exist, %s coins, each printed with its own number. In the vault in the middle of the shop.", Config.Limited.Stock, n(Config.Limited.Price)),
			b("Leaderboard balls") .. ": finish weekly top " .. Config.Leaderboards.RewardTop .. " on a board to unlock its ball: " .. table.concat(boards, ", ") .. ".",
			b("Practice tokens") .. ", " .. b("Ranked tiers") .. ", the " .. b("day-14 login prize") .. " and the " .. b("Corny Games group") .. " reward give exclusive balls too.",
		} },
		{ Title = "Ball upgrades", Lines = {
			"At the " .. b("Ball Upgrades") .. " station: Power, Control and Bounce, up to level " .. Config.Upgrades.MaxLevel .. ".",
			"They work in Classic, Race and Practice and are switched off in Ranked.",
		} },
	}
end

local function practice(): { Section }
	local lines = {}
	for _, m in Minigames.List do
		table.insert(lines, string.format('<font color="#%s"><b>%s</b></font> (%s): %s', m.Color:ToHex(), m.Name, m.BiomeName, m.Rules))
	end
	return {
		{ Title = "The practice range", Lines = {
			string.format("One practice is live at a time on all six lanes. It changes every %d minutes, the same in every server, and the whole range turns into that game's world.", math.floor(Minigames.RotationSeconds / 60)),
			"The " .. b("TV") .. " over the lanes and the two signs by the Practice doorway show what's live, what's next and the countdown.",
			"Step onto a lane's start pad to play. No power-ups; upgrades count.",
			"Every run pays " .. b("tokens") .. " for that game. Tokens can't be bought.",
			"Spend them at the " .. b("Token Exchange") .. " hut: every game's crate and balls, one tab per game.",
			"The " .. b("best-scores board") .. " shows the live game's all-time top scores.",
		} },
		{ Title = "The games", Lines = lines },
		{ Title = "Tutorial", Lines = {
			"The short 3-hole tutorial teaches aiming, power, bank shots and power-ups. Replay it from the pad in the Practice Range.",
		} },
	}
end

local function rewards(): { Section }
	local r = Config.Rewards
	local gifts = {}
	for _, t in Config.Playtime.Tiers do
		table.insert(gifts, t.Minutes .. " min: " .. (if t.Coins then n(t.Coins) .. " coins" else "Playtime Crate"))
	end
	return {
		{ Title = "Match coins", Lines = {
			string.format("Playing: %d · each hole: %d · under par: +%d · hole in one: +%d.", r.Participation, r.PerHole, r.Birdie, r.HoleInOne),
			string.format("Sabotage hits on rivals: +%d each (up to %d a match).", r.SabotageHit, r.SabotageCap),
			string.format("Placing: Ranked win %d · Classic 1st %d · Race 1st %d.", r.Ranked.Win, r.Classic[1], r.Race[1]),
			string.format("Friends bonus: +%d%% match coins per friend in the server (up to +%d%%).", math.floor(Config.FriendBoostPerFriend * 100), math.floor(Config.FriendBoostMax * 100)),
		} },
		{ Title = "Free rewards", Lines = {
			b("Daily Rewards") .. ": a 14-day calendar at the Rewards station with coins, crate keys and an exclusive ball on day 14. Missing a day restarts it.",
			b("Playtime gifts") .. " (gift button, top right): " .. table.concat(gifts, " · ") .. ".",
			b(Config.Group.Name .. " group") .. string.format(": join the group, then claim %s coins + the %s ball once at the Rewards station.", n(Config.Group.Coins), Skins.get(Config.Group.Skin).Name),
			b("Leaderboards") .. ": Wins, Coins and Sabotages, weekly and all-time. Weekly top " .. Config.Leaderboards.RewardTop .. " wins that board's ball.",
		} },
	}
end

local function shop(): { Section }
	local crateNames = {}
	for _, id in Crates.ShopOrder do
		local c = Crates.get(id)
		if c then
			table.insert(crateNames, c.Name)
		end
	end
	return {
		{ Title = "The Pro Shop", Lines = {
			"Coins buy everything in the shop. Walk up to a case and hold the prompt to buy; owned balls equip instead.",
			"Crates: " .. table.concat(crateNames, ", ") .. ". Odds are always on display, duplicates refund part of the price and crate keys from Daily Rewards open them free.",
			"Trails, knockout effects and aim arrows come from their crates and show up in every mode.",
		} },
		{ Title = "Optional extras", Lines = {
			"Game passes and coin packs are optional. Nothing for sale wins matches: power-ups are never sold and upgrades are off in Ranked.",
			"Have a creator code? Enter it at the " .. b("Creator Code") .. " station to support them and unlock the Creator Fan ball.",
		} },
	}
end

local TABS: { { Id: string, Name: string, Build: (Pad.Device) -> { Section } } } = {
	{ Id = "Controls", Name = "Controls", Build = controls },
	{ Id = "Modes", Name = "Modes", Build = function()
		return modes()
	end },
	{ Id = "PowerUps", Name = "Power-ups", Build = function()
		return powerUps()
	end },
	{ Id = "Balls", Name = "Balls & Skins", Build = function()
		return balls()
	end },
	{ Id = "Practice", Name = "Practice", Build = function()
		return practice()
	end },
	{ Id = "Rewards", Name = "Rewards", Build = function()
		return rewards()
	end },
	{ Id = "Shop", Name = "Shop", Build = function()
		return shop()
	end },
}

-- Sizing ------------------------------------------------------------------------------

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

local function compact(): boolean
	local v = viewport()
	return v.X < 760 or v.Y < 460
end

local function overlay(name: string): Frame
	local o = Instance.new("Frame")
	o.Name = name
	o.Size = UDim2.fromScale(1, 1)
	o.BackgroundColor3 = Color3.new(0, 0, 0)
	o.BackgroundTransparency = 1
	o.BorderSizePixel = 0
	o.Active = true
	o.Parent = gui
	TweenService:Create(o, TweenInfo.new(0.2), { BackgroundTransparency = 0.4 }):Play()
	return o
end

-- Device picker -------------------------------------------------------------------------

local function closePicker()
	if picker then
		(picker.Parent :: Instance):Destroy()
		picker = nil
	end
	Pad.closed("DevicePicker")
end

local function choose(choice: string, firstTime: boolean)
	Net.event("ShopAction"):FireServer("setDevice", choice)
	local p = State.Profile
	if p then
		p.Device = choice
	end
	local d: Pad.Device = if choice == "Console" then "pad" elseif choice == "Touch" then "touch" else "pc"
	bookDevice = d
	closePicker()
	if firstTime then
		Hud.toast("Controls set for " .. DEVICE_NAMES[d] .. ". Change them any time in the Guide.", T.Primary)
	end
end

local CARDS = {
	{ Choice = "Console", Icon = "🎮", Title = "Console", Sub = "Xbox or PlayStation controller" },
	{ Choice = "Touch", Icon = "📱", Title = "Phone or Tablet", Sub = "Touch screen" },
	{ Choice = "Keyboard", Icon = "⌨️", Title = "Keyboard & Mouse", Sub = "PC or Mac" },
}

function GuideUi.showPicker(firstTime: boolean)
	closePicker()
	local o = overlay("DevicePicker")
	local small = compact()
	local card = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = o,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, math.huge)
	limit.Parent = card
	UIKit.padding(card, if small then 14 else 22)
	UIKit.list(card, 12, false, Enum.HorizontalAlignment.Center)
	UIKit.text({ Text = if firstTime then "WELCOME! WHAT ARE YOU PLAYING ON?" else "WHAT ARE YOU PLAYING ON?", TextSize = if small then 20 else 26, Font = T.FontHeavy, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = card })
	UIKit.text({ Text = "We'll show the right buttons in the tutorial and the guide. You can change it later.", TextSize = 15, Font = T.FontMedium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = card })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, if small then 3 * 64 + 16 else 170)
	row.LayoutOrder = 3
	row.Parent = card
	local layout = UIKit.list(row, 8, not small, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local suggested = Pad.toChoice(Pad.detected())
	local first: TextButton? = nil
	for i, c in CARDS do
		local button = UIKit.button("", if c.Choice == suggested then "Primary" else "Secondary", {
			Name = c.Choice,
			Size = if small then UDim2.new(1, 0, 0, 64) else UDim2.new(1 / 3, -6, 1, 0),
			LayoutOrder = i,
			Parent = row,
		}, function()
			choose(c.Choice, firstTime)
		end)
		local fg = button.TextColor3
		UIKit.text({ Text = c.Icon, TextSize = if small then 30 else 46, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = if small then Vector2.new(0, 0.5) else Vector2.new(0.5, 0), Position = if small then UDim2.new(0, 10, 0.5, 0) else UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(if small then 44 else 60, if small then 44 else 56), Parent = button })
		UIKit.text({ Text = c.Title, TextSize = 18, Font = T.FontHeavy, TextColor3 = fg, TextXAlignment = if small then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center, Position = if small then UDim2.fromOffset(64, 10) else UDim2.new(0, 6, 0, 86), Size = if small then UDim2.new(1, -70, 0, 22) else UDim2.new(1, -12, 0, 24), Parent = button })
		UIKit.text({ Text = c.Sub, TextSize = 13, Font = T.FontMedium, TextColor3 = fg, TextTransparency = 0.25, TextXAlignment = if small then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center, Position = if small then UDim2.fromOffset(64, 32) else UDim2.new(0, 6, 0, 112), Size = if small then UDim2.new(1, -70, 0, 18) else UDim2.new(1, -12, 0, 36), Parent = button })
		if c.Choice == suggested or not first then
			first = button
		end
	end
	picker = card
	Pad.opened("DevicePicker", function()
		-- Closing without a choice keeps the suggestion (first join must end with a choice).
		choose(suggested, firstTime)
	end)
	Pad.focus(first)
end

-- The guide book --------------------------------------------------------------------------

local tabButtons: { [string]: TextButton } = {}
local deviceButtons: { [string]: TextButton } = {}
local content: ScrollingFrame? = nil

local function renderContent()
	local scroll = content
	if not scroll then
		return
	end
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local small = compact()
	for _, tab in TABS do
		if tab.Id == bookTab then
			for i, section in tab.Build(bookDevice) do
				local c = UIKit.card({ Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = scroll })
				UIKit.padding(c, 12, 14)
				UIKit.list(c, 6)
				UIKit.text({ Text = section.Title, TextSize = if small then 17 else 19, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 0, Parent = c })
				for k, line in section.Lines do
					UIKit.text({ Text = line, TextSize = if small then 14 else 15, Font = T.FontMedium, TextColor3 = T.Text, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = k, Parent = c })
				end
			end
		end
	end
	scroll.CanvasPosition = Vector2.zero
	for id, button in tabButtons do
		UIKit.setVariant(button, if id == bookTab then "Primary" else "Secondary")
	end
	for d, button in deviceButtons do
		UIKit.setVariant(button, if d == bookDevice then "Primary" else "Secondary")
	end
end

local function closeBook()
	if book then
		(book.Parent :: Instance):Destroy()
		book = nil
		content = nil
		tabButtons = {}
		deviceButtons = {}
	end
	ContextActionService:UnbindAction("UG_GuideTabs")
	Pad.closed("Guide")
end

local function stepTab(delta: number)
	for i, tab in TABS do
		if tab.Id == bookTab then
			local nextTab = TABS[((i - 1 + delta) % #TABS) + 1]
			bookTab = nextTab.Id
			renderContent()
			Pad.focus(tabButtons[bookTab])
			return
		end
	end
end

function GuideUi.open(tab: string?)
	closeBook()
	bookDevice = Pad.device()
	if tab then
		bookTab = tab
	end
	local o = overlay("Guide")
	local small = compact()
	local panel = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.96, 0.92),
		Parent = o,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(900, 620)
	limit.Parent = panel
	UIKit.padding(panel, if small then 10 else 16)
	book = panel

	local headH = if small then 34 else 40
	UIKit.text({ Text = "PLAYER GUIDE", TextSize = if small then 20 else 26, Font = T.FontHeavy, Size = UDim2.new(1, -130, 0, headH), Parent = panel })
	local d = Pad.device()
	UIKit.button(if d == "pad" then "Close (B)" else "Close", "Ghost", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(120, headH), TextSize = 15, Parent = panel }, closeBook)

	-- Device switch: one of three tutorials.
	local devRow = Instance.new("Frame")
	devRow.BackgroundTransparency = 1
	devRow.Position = UDim2.fromOffset(0, headH + 8)
	devRow.Size = UDim2.new(1, 0, 0, 34)
	devRow.Parent = panel
	UIKit.list(devRow, 6, true)
	if not small then
		UIKit.text({ Text = "Controls for", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), LayoutOrder = 0, Parent = devRow })
	end
	for i, name in { "pad", "touch", "pc" } do
		local dev: Pad.Device = name :: any
		local label = if small then (if dev == "pad" then "🎮 Console" elseif dev == "touch" then "📱 Touch" else "⌨️ Keyboard") else (if dev == "pad" then "🎮 Console" elseif dev == "touch" then "📱 Phone & Tablet" else "⌨️ Keyboard & Mouse")
		deviceButtons[dev] = UIKit.button(label, "Secondary", { Size = UDim2.fromOffset(if small then 104 else 170, 34), TextSize = if small then 13 else 14, LayoutOrder = i, Parent = devRow }, function()
			bookDevice = dev
			bookTab = "Controls"
			Net.event("ShopAction"):FireServer("setDevice", Pad.toChoice(dev))
			local p = State.Profile
			if p then
				p.Device = Pad.toChoice(dev)
			end
			renderContent()
		end)
	end

	-- Tabs (scroll sideways on small screens).
	local tabsY = headH + 8 + 34 + 8
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.Position = UDim2.fromOffset(0, tabsY)
	tabs.Size = UDim2.new(1, 0, 0, 40)
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new()
	tabs.ScrollBarThickness = 0
	tabs.Selectable = false
	tabs.Parent = panel
	UIKit.list(tabs, 6, true)
	for i, tab in TABS do
		tabButtons[tab.Id] = UIKit.button(tab.Name, "Secondary", { Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, TextSize = if small then 13 else 15, LayoutOrder = i, Parent = tabs }, function()
			bookTab = tab.Id
			renderContent()
		end)
		UIKit.padding(tabButtons[tab.Id], 0, 14)
	end
	local hint = UIKit.text({ Text = if d == "pad" then "LB / RB: switch tabs · right stick: scroll" else "", TextSize = 12, Font = T.FontMedium, TextColor3 = T.Muted, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = panel })
	hint.Visible = d == "pad"

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, tabsY + 48)
	scroll.Size = UDim2.new(1, 0, 1, -(tabsY + 48 + (if d == "pad" then 20 else 0)))
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = if small then 4 else 6
	scroll.ScrollBarImageColor3 = T.Stroke
	scroll.Selectable = true
	scroll.Parent = panel
	UIKit.list(scroll, 10)
	content = scroll
	renderContent()

	Pad.opened("Guide", closeBook)
	ContextActionService:BindActionAtPriority("UG_GuideTabs", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			stepTab(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
	Pad.focus(tabButtons[bookTab])
end

function GuideUi.toggle()
	if book then
		closeBook()
	else
		GuideUi.open()
	end
end

function GuideUi.isOpen(): boolean
	return book ~= nil
end

function GuideUi.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "GuideUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local hudGui = Instance.new("ScreenGui")
	hudGui.Name = "GuideButton"
	hudGui.ResetOnSpawn = false
	hudGui.DisplayOrder = 6
	hudGui.Parent = player:WaitForChild("PlayerGui")
	hudButton = UIKit.button("📖  Guide", "Secondary", {
		Name = "GuideButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.98, 0, 0.12, 134),
		Size = UDim2.fromOffset(180, 36),
		TextSize = 14,
		Parent = hudGui,
	}, GuideUi.toggle)
	local function relabel()
		local d = Pad.device()
		hudButton.Text = if d == "pc" then "📖  Guide  ·  G" elseif d == "pad" then "📖  Guide  ·  Select" else "📖  Guide"
		hudButton.Size = UDim2.fromOffset(180, if d == "touch" then 42 else 36)
	end
	relabel()
	State.observe(function()
		relabel()
	end)
	game:GetService("UserInputService").LastInputTypeChanged:Connect(relabel)

	ContextActionService:BindAction("UG_Guide", function(_, state)
		if state == Enum.UserInputState.Begin then
			GuideUi.toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonSelect)

	Net.event("Tutorial").OnClientEvent:Connect(function(kind: string)
		if kind == "device" then
			GuideUi.showPicker(true)
		elseif kind == "steps" and book then
			closeBook()
		end
	end)
end

return GuideUi

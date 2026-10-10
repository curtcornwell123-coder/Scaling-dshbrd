--!strict
-- Server-wide map vote (North room). Three distinct maps with equal odds are
-- shown on holographic signs; stepping on a sign's floor pad casts (or moves)
-- your vote. The next match to launch from any portal plays the winner, then a
-- fresh set of three is drawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Maps = require(Shared:WaitForChild("Maps"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Zones = require(Server:WaitForChild("Services"):WaitForChild("Zones"))

local Voting = {}

local T = UIKit.Theme
local rng = Random.new()

local choices: { Maps.MapDef } = {}
local votes: { [Player]: number } = {}
local roundStart = os.clock()
local signs: { LobbyTypes.VoteSign } = {}

type SignUi = { Name: TextLabel, Meta: TextLabel, Blurb: TextLabel, Count: TextLabel, Fill: Frame, Strip: Frame }
local ui: { SignUi } = {}

local function counts(): { number }
	local c = {}
	for i = 1, #choices do
		c[i] = 0
	end
	for player, i in votes do
		if player.Parent == Players and c[i] then
			c[i] += 1
		end
	end
	return c
end

local function render()
	local c = counts()
	local total = 0
	for _, n in c do
		total += n
	end
	for i, s in ui do
		local map = choices[i]
		if map then
			local theme = Maps.Themes[map.Theme]
			s.Name.Text = string.upper(map.Name)
			s.Meta.Text = theme.Name .. "  ·  " .. map.Difficulty .. "  ·  " .. map.Holes .. " holes"
			s.Blurb.Text = map.Blurb
			s.Strip.BackgroundColor3 = theme.Trim
			s.Count.Text = c[i] .. (if c[i] == 1 then " vote" else " votes")
			local share = if total > 0 then c[i] / total else 0
			s.Fill.Size = UDim2.fromScale(share, 1)
		end
	end
end

local function reroll()
	choices = Maps.pickDistinct(Config.Voting.Choices, rng)
	for player in votes do
		Net.event("Vote"):FireClient(player, nil)
	end
	votes = {}
	roundStart = os.clock()
	render()
end

-- Returns the winning map id and starts a new round.
function Voting.takeWinner(): string
	local c = counts()
	local best = -1
	local top = {}
	for i, n in c do
		if n > best then
			best = n
			top = { i }
		elseif n == best then
			table.insert(top, i)
		end
	end
	local pick = choices[top[rng:NextInteger(1, #top)]] or Maps.List[1]
	reroll()
	return pick.Id
end

local function buildSign(sign: LobbyTypes.VoteSign): SignUi
	local gui = UIKit.surface(sign.Display, { PixelsPerStud = 50, Name = "VoteUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 10)

	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 0, 6)
	strip.BorderSizePixel = 0
	strip.LayoutOrder = 1
	UIKit.corner(strip, UDim.new(0, 3))
	strip.Parent = root

	local name = UIKit.text({ Text = "", TextSize = 40, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 2, Parent = root })
	local meta = UIKit.text({ Text = "", TextSize = 20, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, Parent = root })
	local blurb = UIKit.text({ Text = "", TextSize = 22, Font = T.FontMedium, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 4, Parent = root })

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 14)
	bar.BackgroundColor3 = T.SurfaceHi
	bar.BorderSizePixel = 0
	bar.LayoutOrder = 5
	UIKit.corner(bar, UDim.new(0, 4))
	bar.Parent = root
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = T.Info
	fill.BorderSizePixel = 0
	UIKit.corner(fill, UDim.new(0, 4))
	fill.Parent = bar

	local count = UIKit.text({ Text = "", TextSize = 26, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 6, Parent = root })
	UIKit.text({
		Text = "Step on the pad to vote",
		TextSize = 18,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 7,
		Parent = root,
	})
	return { Name = name, Meta = meta, Blurb = blurb, Count = count, Fill = fill, Strip = strip }
end

local function buildHeader(part: BasePart)
	local gui = UIKit.surface(part, { PixelsPerStud = 40, Name = "VoteHeader" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 4, false, Enum.HorizontalAlignment.Center)
	UIKit.text({
		Text = "VOTE THE NEXT MAP",
		TextSize = 44,
		Font = T.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0.55, 0),
		Parent = root,
	})
	UIKit.text({
		Text = "The winner is played by the next match that launches. Every map has equal odds of appearing.",
		TextSize = 20,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0.4, 0),
		Parent = root,
	})
end

function Voting.start(lobby: LobbyTypes.Lobby)
	signs = lobby.North.VoteSigns
	for i, sign in signs do
		ui[i] = buildSign(sign)
	end
	buildHeader(lobby.North.VoteHeader)
	reroll()

	Players.PlayerRemoving:Connect(function(player)
		if votes[player] then
			votes[player] = nil
			render()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local changed = false
			for _, entry in Zones.freePlayers() do
				for i, sign in signs do
					if Zones.onPad(sign.Pad, entry.Root.Position) and votes[entry.Player] ~= i then
						votes[entry.Player] = i
						Net.event("Vote"):FireClient(entry.Player, i)
						changed = true
					end
				end
			end
			if changed then
				render()
			end
			if next(votes) == nil and os.clock() - roundStart > Config.Voting.IdleReroll then
				reroll()
			end
		end
	end)
end

return Voting

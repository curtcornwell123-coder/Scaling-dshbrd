--!strict
-- North room portals. Standing inside a mode's bubble queues you for it; leave
-- the bubble to leave the queue. Waiting pays a rising coin drip
-- (Config.QueueRewards) so nobody abandons a slow queue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Zones = require(Server:WaitForChild("Services"):WaitForChild("Zones"))
local MatchService = require(Server:WaitForChild("Golf"):WaitForChild("MatchService"))
local Voting = require(script.Parent:WaitForChild("Voting"))

local Matchmaking = {}

local T = UIKit.Theme

type QueueUi = { Count: TextLabel, Status: TextLabel, Fill: Frame }
type Queue = {
	Mode: Config.ModeDef,
	Portal: LobbyTypes.Portal,
	Members: { Player },
	CountdownEnd: number?,
	Ui: QueueUi,
}
type Waiting = { Mode: string, Since: number, Accum: number }

local queues: { Queue } = {}
local waiting: { [Player]: Waiting } = {}

local function minPlayers(mode: Config.ModeDef): number
	if Config.StudioSoloMatches and RunService:IsStudio() then
		return 1
	end
	return mode.MinPlayers
end

local function rewardTier(elapsed: number)
	for _, tier in Config.QueueRewards do
		if elapsed <= tier.UpTo then
			return tier
		end
	end
	return Config.QueueRewards[#Config.QueueRewards]
end

local function buildSign(portal: LobbyTypes.Portal, mode: Config.ModeDef): QueueUi
	local gui = UIKit.surface(portal.Sign, { PixelsPerStud = 50, Name = "QueueUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 6)

	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 52)
	head.LayoutOrder = 1
	head.Parent = root
	UIKit.list(head, 10, true)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(14, 14)
	dot.BackgroundColor3 = mode.Color
	dot.BorderSizePixel = 0
	UIKit.corner(dot, UDim.new(0, 4))
	dot.LayoutOrder = 1
	dot.Parent = head
	UIKit.text({ Text = mode.Display, TextSize = 38, Font = T.FontHeavy, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 52), LayoutOrder = 2, Parent = head })

	local count = UIKit.text({ Text = "", TextSize = 26, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, Parent = root })
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.BackgroundColor3 = T.SurfaceHi
	bar.BorderSizePixel = 0
	bar.LayoutOrder = 3
	UIKit.corner(bar, UDim.new(0, 4))
	bar.Parent = root
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = T.Primary
	fill.BorderSizePixel = 0
	UIKit.corner(fill, UDim.new(0, 4))
	fill.Parent = bar

	local status = UIKit.text({ Text = "", TextSize = 22, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 4, Parent = root })
	local first = Config.QueueRewards[1]
	UIKit.text({
		Text = string.format("Stand in the bubble to queue  ·  +%d coin every %ds while you wait, rising the longer you stay", first.Amount, first.Every),
		TextSize = 16,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 5,
		Parent = root,
	})
	return { Count = count, Status = status, Fill = fill }
end

local function render(q: Queue)
	local n = #q.Members
	q.Ui.Count.Text = string.format("%d / %d players", n, q.Mode.MaxPlayers)
	q.Ui.Fill.Size = UDim2.fromScale(n / q.Mode.MaxPlayers, 1)
	if q.CountdownEnd then
		q.Ui.Status.Text = string.format("Starting in %ds", math.max(0, math.ceil(q.CountdownEnd - os.clock())))
		q.Ui.Status.TextColor3 = T.Primary
	elseif n == 0 then
		q.Ui.Status.Text = "Empty — step in to start a queue"
		q.Ui.Status.TextColor3 = T.Muted
	else
		q.Ui.Status.Text = string.format("Waiting for %d more", math.max(0, minPlayers(q.Mode) - n))
		q.Ui.Status.TextColor3 = T.Muted
	end
end

local function launch(q: Queue, players: { Player })
	q.CountdownEnd = nil
	local mapId = Voting.takeWinner()
	for _, p in players do
		waiting[p] = nil
		local i = table.find(q.Members, p)
		if i then
			table.remove(q.Members, i)
		end
	end
	if not MatchService.launch(q.Mode.Id, players, mapId) then
		warn("[ChaosGolf] failed to launch", q.Mode.Id)
	end
	render(q)
end

local function tick(dt: number)
	local inside: { [Player]: Queue } = {}
	for _, entry in Zones.freePlayers() do
		if Data.get(entry.Player) then
			for _, q in queues do
				if Zones.inBubble(q.Portal.Bubble, entry.Root.Position) then
					inside[entry.Player] = q
					break
				end
			end
		end
	end

	local now = os.clock()
	for _, q in queues do
		for i = #q.Members, 1, -1 do
			if inside[q.Members[i]] ~= q then
				table.remove(q.Members, i)
			end
		end
	end
	for player, q in inside do
		if not table.find(q.Members, player) then
			table.insert(q.Members, player)
		end
		-- Wait rewards.
		local ww: Waiting = waiting[player] or { Mode = q.Mode.Id, Since = now, Accum = 0 }
		if ww.Mode ~= q.Mode.Id then
			ww = { Mode = q.Mode.Id, Since = now, Accum = 0 }
		end
		waiting[player] = ww
		local tier = rewardTier(now - ww.Since)
		ww.Accum += dt
		if ww.Accum >= tier.Every then
			ww.Accum -= tier.Every
			Data.addCoins(player, tier.Amount, "queue")
			Net.event("Fx"):FireClient(player, "coins", { Amount = tier.Amount })
		end
	end
	for player in waiting do
		if not inside[player] then
			waiting[player] = nil
		end
	end

	for _, q in queues do
		local n = #q.Members
		local min = minPlayers(q.Mode)
		if n >= q.Mode.MaxPlayers then
			local group = table.move(q.Members, 1, q.Mode.MaxPlayers, 1, {})
			launch(q, group)
		elseif n >= min then
			if not q.CountdownEnd then
				q.CountdownEnd = now + q.Mode.Countdown
			end
			if now >= (q.CountdownEnd :: number) then
				launch(q, table.clone(q.Members))
			end
		else
			q.CountdownEnd = nil
		end
		render(q)
	end
end

function Matchmaking.start(lobby: LobbyTypes.Lobby)
	for _, modeId in Config.ModeOrder do
		local portal = lobby.North.Portals[modeId]
		local mode = Config.Modes[modeId]
		if portal and mode then
			local q: Queue = { Mode = mode, Portal = portal, Members = {}, CountdownEnd = nil, Ui = buildSign(portal, mode) }
			table.insert(queues, q)
			render(q)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		waiting[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local t = os.clock()
			tick(t - last)
			last = t
		end
	end)
end

return Matchmaking

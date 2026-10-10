--!strict
-- West room Hall of Leaderboards: Wins, Coins earned and Sabotages, each over
-- Daily / Weekly / All-Time (OrderedDataStores). Clients page the boards
-- locally; the server owns the trophy podiums, which show the current Daily
-- leader's real ball (skin, trail and rank) and refresh every 20 seconds.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Ranks = require(Shared:WaitForChild("Ranks"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Parts = require(Server:WaitForChild("World"):WaitForChild("Parts"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Displays = require(script.Parent:WaitForChild("Displays"))

local Leaderboards = {}

local T = UIKit.Theme
local STATS = { "Wins", "Coins", "Sabotages" }
local PERIODS = { "Daily", "Weekly", "AllTime" }
local STAT_SOURCE = { Wins = "Wins", Coins = "CoinsEarned", Sabotages = "Sabotages" }

export type Entry = { UserId: number, Name: string, Value: number }
local cache: { [string]: { [string]: { Entry } } } = {}
local names: { [number]: string } = {}
local podiumState: { [string]: string } = {}
local warnedWrite = false

local function periodKey(period: string): string
	local day = math.floor(os.time() / 86400)
	if period == "Daily" then
		return "D" .. day
	elseif period == "Weekly" then
		return "W" .. math.floor((day + 3) / 7) -- weeks start on Monday (UTC)
	end
	return "A"
end

local function store(stat: string, period: string): OrderedDataStore?
	local ok, ds = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_LB_" .. stat .. "_" .. periodKey(period))
	end)
	return if ok then ds else nil
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else ("Player " .. userId)
	names[userId] = result
	return result
end

local function flushSession(session: Data.Session)
	local delta = session.LBDelta
	session.LBDelta = {}
	local userKey = tostring(session.Player.UserId)
	for stat, amount in delta do
		if amount > 0 and STAT_SOURCE[stat] then
			for _, period in PERIODS do
				local ds = store(stat, period)
				if ds then
					local ok, err = pcall(function()
						ds:UpdateAsync(userKey, function(old: any)
							return (if type(old) == "number" then old else 0) + amount
						end)
					end)
					if not ok and not warnedWrite then
						warnedWrite = true
						warn("[ChaosGolf] leaderboard writes failing (further warnings suppressed):", err)
					end
				end
			end
		end
	end
end

-- Fallback when DataStores are unavailable: rank the players in this server.
local function localBoard(stat: string): { Entry }
	local out = {}
	for player, session in Data.sessions() do
		if session.Loaded then
			table.insert(out, { UserId = player.UserId, Name = player.DisplayName, Value = session.Profile.Stats[STAT_SOURCE[stat]] or 0 })
		end
	end
	table.sort(out, function(a, b)
		return a.Value > b.Value
	end)
	return out
end

local function refresh()
	for _, stat in STATS do
		cache[stat] = cache[stat] or {}
		for _, period in PERIODS do
			local ds = store(stat, period)
			local entries: { Entry }? = nil
			if ds then
				local ok, pages = pcall(function()
					return ds:GetSortedAsync(false, Config.Leaderboards.MaxEntries)
				end)
				if ok and pages then
					entries = {}
					local pageOk, page = pcall(function()
						return pages:GetCurrentPage()
					end)
					if pageOk then
						for _, row in page do
							local userId = tonumber(row.key)
							if userId then
								table.insert(entries :: { Entry }, { UserId = userId, Name = nameOf(userId), Value = row.value })
							end
						end
					end
				end
			end
			cache[stat][period] = entries or localBoard(stat)
		end
	end
	Net.event("Leaderboards"):FireAllClients(cache)
end

type Podium = { Board: LobbyTypes.Board, Folder: Folder, Name: TextLabel, Value: TextLabel, Rank: TextLabel, Title: TextLabel }

local function buildNameplate(board: LobbyTypes.Board, stat: string): (TextLabel, TextLabel, TextLabel, TextLabel)
	local gui = UIKit.surface(board.Nameplate, { PixelsPerStud = 60, Name = "PodiumUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 2, false, Enum.HorizontalAlignment.Center)
	local title = UIKit.text({ Text = "#1 TODAY · " .. string.upper(stat), TextSize = 16, Font = T.FontMedium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Parent = root })
	local name = UIKit.text({ Text = "—", TextSize = 28, Font = T.FontHeavy, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Parent = root })
	local value = UIKit.text({ Text = "", TextSize = 18, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 22), Parent = root })
	local rank = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Parent = root })
	return title, name, value, rank
end

local function updatePodium(stat: string, podium: Podium)
	local boards = cache[stat]
	if not boards then
		return
	end
	local period = "Daily"
	local leader = boards.Daily and boards.Daily[1]
	if not leader then
		period = "AllTime"
		leader = boards.AllTime and boards.AllTime[1]
	end
	if not leader then
		return
	end
	local pub: { Skin: string?, Trail: string?, MMR: number? } = Data.getPublic(leader.UserId) or { Skin = nil, Trail = nil, MMR = nil }
	local skin = pub.Skin or "classic_white"
	local trail = pub.Trail or "none"
	local key = table.concat({ tostring(leader.UserId), skin, trail, tostring(leader.Value), tostring(pub.MMR) }, "|")
	podium.Title.Text = (if period == "Daily" then "#1 TODAY · " else "#1 ALL-TIME · ") .. string.upper(stat)
	if podiumState[stat] == key then
		return
	end
	podiumState[stat] = key
	podium.Folder:ClearAllChildren()
	local ball = Displays.ball(podium.Folder, Displays.anchorPoint(podium.Board.Podium), skin, 3.2)
	ball:SetAttribute("ShowcaseTrail", trail)
	podium.Name.Text = leader.Name
	podium.Value.Text = UIKit.formatNumber(leader.Value) .. " " .. string.lower(stat)
	if pub.MMR then
		local info = Ranks.fromMMR(pub.MMR)
		podium.Rank.Text = info.Label
		podium.Rank.TextColor3 = info.Tier.Color
	else
		podium.Rank.Text = ""
	end
end

function Leaderboards.start(lobby: LobbyTypes.Lobby)
	local podiums: { [string]: Podium } = {}
	for _, stat in STATS do
		local board = lobby.West.Boards[stat]
		if board then
			local folder = Parts.folder(lobby.Model, "Podium_" .. stat)
			local title, name, value, rank = buildNameplate(board, stat)
			podiums[stat] = { Board = board, Folder = folder, Name = name, Value = value, Rank = rank, Title = title }
			-- Client-side paging buttons (each player pages their own view).
			Parts.prompt(board.Prev, "Previous page", stat, { Distance = 9, Name = "BoardPrev" }):SetAttribute("Board", stat)
			Parts.prompt(board.Next, "Next page", stat, { Distance = 9, Name = "BoardNext" }):SetAttribute("Board", stat)
			Parts.prompt(board.Period, "Daily / Weekly / All-Time", stat, { Distance = 9, Name = "BoardPeriod" }):SetAttribute("Board", stat)
		end
	end

	Data.onRelease(function(session)
		task.spawn(flushSession, session)
	end)
	Players.PlayerAdded:Connect(function(player)
		if next(cache) then
			Net.event("Leaderboards"):FireClient(player, cache)
		end
	end)

	task.spawn(function()
		while true do
			refresh()
			task.wait(Config.Leaderboards.RefreshInterval)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Leaderboards.FlushInterval)
			for _, session in Data.sessions() do
				if session.Loaded and next(session.LBDelta) then
					flushSession(session)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Leaderboards.PodiumInterval)
			for stat, podium in podiums do
				pcall(updatePodium, stat, podium)
			end
		end
	end)
	task.delay(5, function()
		for stat, podium in podiums do
			pcall(updatePodium, stat, podium)
		end
	end)
end

return Leaderboards

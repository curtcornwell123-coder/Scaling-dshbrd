--!strict
-- South wing Practice Range: three permanent stations (Target Putting, Velocity
-- Long-Drive, Hazard Avoidance), two lanes each. Runs pay that minigame's tokens
-- (never sold for Coins or Robux), spent at the station's token hut, which opens the
-- token shop panel. Personal bests feed each station's best-scores board. Players
-- inside the range get the InPractice attribute so the HUD shows their tokens.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Crates = require(Shared:WaitForChild("Crates"))
local Minigames = require(Shared:WaitForChild("Minigames"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Server = script.Parent.Parent
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Parts = require(Server:WaitForChild("World"):WaitForChild("Parts"))
local Activity = require(Server:WaitForChild("Services"):WaitForChild("Activity"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Zones = require(Server:WaitForChild("Services"):WaitForChild("Zones"))
local BallService = require(Server:WaitForChild("Golf"):WaitForChild("BallService"))
local Displays = require(script.Parent:WaitForChild("Displays"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local Practice = {}

local T = UIKit.Theme

local TARGET_RINGS = { { Radius = 1.4, Points = 10 }, { Radius = 2.8, Points = 5 }, { Radius = 4.2, Points = 2 } }
local RAMP_START = 12
local RAMP_ANGLE = math.rad(28)

type LaneState = {
	Lane: LobbyTypes.Lane,
	Def: Minigames.Minigame,
	Index: number,
	Player: Player?,
	Shots: number,
	Score: number,
	Best: number,
	Cup: Vector3?,
	Screen: { Title: TextLabel, Body: TextLabel },
	Blocked: { [Player]: boolean }, -- must step off the pad before starting again
}

local lanes: { LaneState } = {}
local byPlayer: { [Player]: LaneState } = {}
local lobbyRef: LobbyTypes.Lobby
local kioskFolder: Folder

local function laneCF(state: LaneState, distance: number, y: number, x: number?): CFrame
	return state.Lane.Origin * CFrame.new(x or 0, y, -distance)
end

local function setScreen(state: LaneState, title: string, body: string)
	state.Screen.Title.Text = title
	state.Screen.Body.Text = body
end

-- Props --------------------------------------------------------------------

local function buildProps(state: LaneState)
	local lane = state.Lane
	local folder = lane.Props
	folder:ClearAllChildren()
	local W, L = lane.Width, lane.Length
	state.Cup = nil

	-- Back bumper so balls can't roll off the lane start.
	Parts.block(folder, laneCF(state, -1.6, 0.7), Vector3.new(W, 1.4, 0.8), { Color = Color3.fromRGB(38, 44, 60), Name = "BackBumper" })

	if state.Def.Id == "Target" then
		local d = L - 12
		for i = #TARGET_RINGS, 1, -1 do
			local ring = TARGET_RINGS[i]
			local color = if i == 1 then Color3.fromRGB(255, 70, 90) elseif i == 2 then Color3.fromRGB(255, 255, 255) else state.Def.Color
			local disc = Parts.cylinder(folder, laneCF(state, d, 0.02 + i * 0.01), 0.04, ring.Radius * 2, {
				Color = color,
				Material = if i == 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				Name = "Ring" .. ring.Points,
			})
			disc.CastShadow = false
		end
	elseif state.Def.Id == "Drive" then
		local H = L - RAMP_START - 2
		local slope = H / math.cos(RAMP_ANGLE)
		local rise = H * math.tan(RAMP_ANGLE)
		local startCF = laneCF(state, RAMP_START, 0)
		local rampCF = startCF * CFrame.Angles(RAMP_ANGLE, 0, 0) * CFrame.new(0, -0.5, -slope / 2)
		local ramp = Parts.block(folder, rampCF, Vector3.new(W, 1, slope), { Color = Color3.fromRGB(52, 60, 82), Name = "Ramp" })
		ramp.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.2)
		for _, side in { -1, 1 } do
			Parts.block(folder, rampCF * CFrame.new(side * (W / 2 - 0.4), 1.5, 0), Vector3.new(0.8, 2.2, slope), { Color = Color3.fromRGB(30, 34, 46), Name = "RampRail" })
		end
		Parts.block(folder, startCF * CFrame.new(0, rise + 2, -H - 0.4), Vector3.new(W, 5, 0.8), { Color = Color3.fromRGB(30, 34, 46), Name = "RampCap" })
		for mark = 10, math.floor(slope), 10 do
			local strip = Parts.block(folder, startCF * CFrame.Angles(RAMP_ANGLE, 0, 0) * CFrame.new(0, 0.03, -mark), Vector3.new(W - 1.8, 0.05, 0.3), {
				Color = state.Def.Color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
			Parts.label(strip, Enum.NormalId.Top, tostring(mark), { PixelsPerStud = 20, TextColor = T.Text })
		end
	elseif state.Def.Id == "Hazard" then
		for i, d in { 14, 26, 38 } do
			if d < L - 8 then
				local hub = Parts.cylinder(folder, laneCF(state, d, 1), 2, 1.2, { Color = Color3.fromRGB(30, 34, 46), Name = "Hub" })
				local bar = Instance.new("Part")
				bar.Name = "Sweeper"
				bar.Size = Vector3.new(W - 2.2, 0.9, 0.7)
				bar.CFrame = laneCF(state, d, 0.95)
				bar.Color = state.Def.Color
				bar.Material = Enum.Material.Neon
				bar.CustomPhysicalProperties = PhysicalProperties.new(60, 0.2, 0.5)
				bar.Anchored = false
				bar.Parent = folder
				local a0 = Instance.new("Attachment") -- hub cylinder's local X axis is already vertical
				a0.Parent = hub
				local a1 = Instance.new("Attachment")
				a1.Orientation = Vector3.new(0, 0, 90)
				a1.Parent = bar
				local hinge = Instance.new("HingeConstraint")
				hinge.ActuatorType = Enum.ActuatorType.Motor
				hinge.AngularVelocity = (if i % 2 == 0 then -1 else 1) * (1.2 + i * 0.25)
				hinge.MotorMaxTorque = 1e9
				hinge.MotorMaxAcceleration = 1e9
				hinge.Attachment0 = a0
				hinge.Attachment1 = a1
				hinge.Parent = bar
				pcall(function()
					bar:SetNetworkOwner(nil)
				end)
			end
		end
		local cup = laneCF(state, L - 5, 0).Position
		state.Cup = cup
		Parts.cylinder(folder, CFrame.new(cup + Vector3.new(0, 0.02, 0)), 0.04, Config.Physics.CupRadius * 2 + 0.2, { Color = Color3.fromRGB(14, 16, 22), CanCollide = false, CanQuery = false, Name = "Cup" })
		Parts.rod(folder, cup + Vector3.new(1.4, 0, 0), cup + Vector3.new(1.4, 5, 0), 0.15, { Color = Color3.new(1, 1, 1), CanCollide = false, CanQuery = false })
		Parts.block(folder, CFrame.new(cup + Vector3.new(2.2, 4.4, 0)), Vector3.new(1.6, 1, 0.1), { Color = state.Def.Color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
	end
	setScreen(state, "LANE " .. state.Index .. "  ·  " .. string.upper(state.Def.Name), "Step on the pad to play")
end

-- Runs -----------------------------------------------------------------------

local function ballStart(state: LaneState): Vector3
	return laneCF(state, 2.5, Config.Ball.Diameter / 2 + 0.1).Position
end

-- Best scores --------------------------------------------------------------------
-- Ordered stores rank "higher is better"; Hazard strokes (1-4) are stored as 10 - strokes.

export type BestEntry = { Name: string, Score: number }

local boards: { [string]: { Rows: { TextLabel }, Mine: TextLabel? } } = {}
local cache: { [string]: { BestEntry }? } = {}

local function encode(id: string, score: number): number
	return if id == "Hazard" then 10 - score else score
end

local function decode(id: string, value: number): number
	return if id == "Hazard" then 10 - value else value
end

local function better(id: string, new: number, old: number): boolean
	if new <= 0 then
		return false
	end
	if id == "Hazard" then
		return old <= 0 or new < old
	end
	return new > old
end

local function scoreLabel(id: string, score: number): string
	if id == "Drive" then
		return score .. " studs"
	elseif id == "Hazard" then
		return score .. (if score == 1 then " stroke" else " strokes")
	end
	return score .. " pts"
end

local function bestStore(id: string): OrderedDataStore?
	if game.PlaceId == 0 then -- unpublished places have no DataStores
		return nil
	end
	local ok, ds = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_PB_" .. id)
	end)
	return if ok then ds else nil
end

-- Fallback when DataStores are unavailable: the personal bests of players in this server.
local function localBest(id: string): { BestEntry }
	local out: { BestEntry } = {}
	for player, session in Data.sessions() do
		local best = session.Loaded and session.Profile.PracticeBest[id] or 0
		if best > 0 then
			table.insert(out, { Name = player.DisplayName, Score = best })
		end
	end
	table.sort(out, function(x, y)
		return encode(id, x.Score) > encode(id, y.Score)
	end)
	return out
end

local function renderBoard(id: string)
	local b = boards[id]
	if not b then
		return
	end
	local list = cache[id] or localBest(id)
	for i, row in b.Rows do
		local e = list[i]
		row.Text = if e then string.format("%d.  %s  ·  %s", i, e.Name, scoreLabel(id, e.Score)) else (i .. ".  —")
	end
end

local function refreshBoards()
	for _, m in Minigames.List do
		local ds = bestStore(m.Id)
		local entries: { BestEntry }? = nil
		if ds then
			local ok, pages = pcall(function()
				return ds:GetSortedAsync(false, 8)
			end)
			if ok and pages then
				local pageOk, page = pcall(function()
					return pages:GetCurrentPage()
				end)
				if pageOk then
					entries = {}
					for _, r in page do
						local userId = tonumber(r.key)
						if userId and type(r.value) == "number" then
							local okName, name = pcall(function()
								return Players:GetNameFromUserIdAsync(userId)
							end)
							table.insert(entries :: { BestEntry }, { Name = if okName then name else "Player", Score = decode(m.Id, r.value) })
						end
					end
				end
			end
		end
		cache[m.Id] = entries
		renderBoard(m.Id)
	end
end

local function recordBest(player: Player, id: string, score: number)
	local profile = Data.profile(player)
	if not profile or not better(id, score, profile.PracticeBest[id] or 0) then
		return
	end
	profile.PracticeBest[id] = score
	Data.markDirty(player)
	Net.event("Toast"):FireClient(player, "New personal best: " .. scoreLabel(id, score) .. "!", Config.Colors.Gold)
	renderBoard(id)
	local ds = bestStore(id)
	if ds then
		task.spawn(function()
			pcall(function()
				local v = encode(id, score)
				-- Returning nil keeps the stored value (the typings don't allow it, hence the cast).
				local store: any = ds
				store:UpdateAsync(tostring(player.UserId), function(old: any): number?
					if type(old) == "number" and old >= v then
						return nil -- keep the stored best
					end
					return v
				end)
			end)
		end)
	end
end

local function finish(state: LaneState, completed: boolean)
	local player = state.Player
	if not player then
		return
	end
	state.Player = nil
	byPlayer[player] = nil
	BallService.destroy(player)
	local score = if state.Def.Id == "Drive" then math.floor(state.Best) else state.Score
	local tokens = if completed then Minigames.tokensFor(state.Def.Id, score) else 0
	if tokens > 0 then
		Data.addTokens(player, state.Def.Id, tokens)
	end
	if completed then
		recordBest(player, state.Def.Id, score)
	end
	if player.Parent == Players then
		Activity.set(player, nil)
		state.Blocked[player] = true
		Activity.unpark(player, CFrame.lookAt(state.Lane.StartPad.Position + Vector3.new(0, 3, 0) - state.Lane.Origin.LookVector * 4, state.Lane.Origin.Position + Vector3.new(0, 3, 0)))
		Net.event("BallAssigned"):FireClient(player, nil, { Context = "None" })
		Net.event("Fx"):FireClient(player, "practice", {
			Minigame = state.Def.Name,
			Score = score,
			Tokens = tokens,
			Token = state.Def.Token,
			Completed = completed,
		})
	end
	local scoreText = if state.Def.Id == "Drive" then score .. " studs" elseif state.Def.Id == "Hazard" then (if score > 0 then score .. " strokes" else "missed") else score .. " pts"
	setScreen(state, "LANE " .. state.Index .. "  ·  " .. string.upper(state.Def.Name), player.DisplayName .. ": " .. scoreText .. "  ·  +" .. tokens .. " tokens")
end

local function makeContext(state: LaneState): BallService.Context
	return {
		CanShoot = function(ball)
			return state.Player == ball.Player and state.Shots < state.Def.Shots
		end,
		OnShot = function(_ball)
			state.Shots += 1
		end,
		OnRest = function(ball)
			if state.Def.Id == "Target" then
				local center = laneCF(state, state.Lane.Length - 12, 0).Position
				local d = Vector2.new(ball.Part.Position.X - center.X, ball.Part.Position.Z - center.Z).Magnitude
				local pts = 0
				for _, ring in TARGET_RINGS do
					if d <= ring.Radius then
						pts = ring.Points
						break
					end
				end
				state.Score += pts
				Net.event("Toast"):FireClient(ball.Player, if pts > 0 then "+" .. pts .. " points" else "Missed the rings", if pts >= 10 then Config.Colors.Gold else nil)
				setScreen(state, "LANE " .. state.Index .. "  ·  TARGET", string.format("%s  ·  %d pts  ·  shot %d/%d", ball.Player.DisplayName, state.Score, state.Shots, state.Def.Shots))
			elseif state.Def.Id == "Drive" then
				local best = math.floor(ball.MaxDistance)
				state.Best = math.max(state.Best, ball.MaxDistance)
				Net.event("Toast"):FireClient(ball.Player, best .. " studs up the ramp", nil)
				setScreen(state, "LANE " .. state.Index .. "  ·  LONG-DRIVE", string.format("%s  ·  best %d studs  ·  drive %d/%d", ball.Player.DisplayName, math.floor(state.Best), state.Shots, state.Def.Shots))
			elseif state.Def.Id == "Hazard" then
				if state.Shots >= state.Def.Shots then
					Net.event("Toast"):FireClient(ball.Player, "Out of strokes!", Config.Colors.Bad)
					finish(state, true)
					return
				end
				return -- play on from where it stopped
			end
			if state.Shots >= state.Def.Shots then
				task.delay(0.6, function()
					if state.Player == ball.Player then
						finish(state, true)
					end
				end)
			else
				BallService.place(ball, ballStart(state))
			end
		end,
		OnSink = function(ball)
			state.Score = ball.Strokes
			task.delay(0.7, function()
				if state.Player == ball.Player then
					finish(state, true)
				end
			end)
		end,
		OnOOB = function(ball)
			BallService.place(ball, ballStart(state))
		end,
		Tick = function(ball, _dt)
			if state.Def.Id == "Drive" then
				local start = laneCF(state, RAMP_START, 0)
				local dir = (start * CFrame.Angles(RAMP_ANGLE, 0, 0)).LookVector
				local along = (ball.Part.Position - start.Position):Dot(dir)
				if along > ball.MaxDistance then
					ball.MaxDistance = along
				end
			end
		end,
	}
end

local function begin(state: LaneState, player: Player)
	local profile = Data.profile(player)
	if not profile then
		return
	end
	state.Player = player
	state.Shots = 0
	state.Score = 0
	state.Best = 0
	byPlayer[player] = state
	Activity.set(player, "Practice")
	local pad = state.Lane.StartPad
	Activity.park(player, CFrame.lookAt(pad.Position + Vector3.new(0, 3, 0), pad.Position + Vector3.new(0, 3, 0) + state.Lane.Origin.LookVector))
	local ball = BallService.create(player, {
		Position = ballStart(state),
		Context = makeContext(state),
		Ghost = true,
		Upgrades = profile.Upgrades,
		Cup = state.Cup,
		OOBY = state.Lane.Origin.Position.Y - 8,
		Loadout = Data.loadout(player),
	})
	Net.event("BallAssigned"):FireClient(player, ball.Part, {
		Context = "Practice",
		Minigame = state.Def.Id,
		Title = state.Def.Name,
		Rules = state.Def.Rules,
		TeeLook = state.Lane.Origin.LookVector,
		Cup = state.Cup,
		PowerCycle = Config.Physics.PowerCycleSeconds * (1 + (profile.Upgrades.Control or 0) * 0.08),
	})
	Net.event("Toast"):FireClient(player, state.Def.Rules, nil)
	setScreen(state, "LANE " .. state.Index .. "  ·  " .. string.upper(state.Def.Name), player.DisplayName .. " is playing")
end

-- Token huts ----------------------------------------------------------------------

local function buyTokenSkin(player: Player, id: string)
	local skin = Skins.ById[id]
	local profile = Data.profile(player)
	if not skin or not profile then
		return
	end
	if Data.owns(player, "Skins", id) then
		Data.equip(player, "Skins", id)
		Net.event("Fx"):FireClient(player, "shopResult", { Ok = true, Text = "Equipped " .. skin.Name })
		return
	end
	local mgId = string.match(skin.Source, "^Token:(.+)$")
	local mg = mgId and Minigames.ById[mgId]
	if not mgId or not mg then
		return
	end
	local price = Crates.TokenDirectPrice[skin.Rarity] or 999
	if (profile.Tokens[mgId] or 0) < price then
		Net.event("Fx"):FireClient(player, "shopResult", { Ok = false, Text = "Not enough " .. mg.Token })
		return
	end
	Data.addTokens(player, mgId, -price)
	Data.grant(player, "Skins", id)
	Data.equip(player, "Skins", id)
	Net.event("Fx"):FireClient(player, "shopResult", { Ok = true, Text = "Unlocked " .. skin.Name })
end

local function buildStations()
	for id, station in lobbyRef.South.Stations do
		local crate = Crates.get(id)
		if crate then
			Displays.bob(Displays.crate(kioskFolder, Displays.anchorPoint(station.Display), crate.Color, 2.4))
		end
		local mg = Minigames.ById[id]
		local prompt = Parts.prompt(station.Counter, "Open shop", mg.Token, { Distance = 10, Name = "TokenShopPrompt" })
		prompt:SetAttribute("Minigame", id)
		prompt.Triggered:Connect(function(player)
			Net.event("Fx"):FireClient(player, "tokenShop", { Minigame = id })
		end)
		-- Best-scores board.
		local gui = UIKit.surface(station.Board, { PixelsPerStud = 40, Name = "BestScoresUI" })
		local root = UIKit.screen(gui)
		UIKit.list(root, 4)
		UIKit.text({ Text = string.upper(mg.Name) .. "  ·  ALL-TIME", TextSize = 26, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 34), Parent = root })
		local rows: { TextLabel } = {}
		for i = 1, 6 do
			rows[i] = UIKit.text({ Text = i .. ".  —", TextSize = 22, Font = T.FontMedium, TextColor3 = if i == 1 then T.Gold else T.Text, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = i, Parent = root })
		end
		boards[id] = { Rows = rows }
		renderBoard(id)
	end
end

function Practice.leave(player: Player): boolean
	local state = byPlayer[player]
	if not state then
		return false
	end
	finish(state, false)
	return true
end

local function inRange(pos: Vector3): boolean
	local l = lobbyRef.South.Bounds:PointToObjectSpace(pos)
	local half = lobbyRef.South.Size / 2
	return math.abs(l.X) <= half.X and math.abs(l.Z) <= half.Z and l.Y > -2 and l.Y < half.Y
end

function Practice.start(lobby: LobbyTypes.Lobby)
	lobbyRef = lobby
	kioskFolder = Parts.folder(lobby.Model, "TokenHutProps")
	for i, lane in lobby.South.Lanes do
		local gui = UIKit.surface(lane.Screen, { PixelsPerStud = 50, Name = "LaneUI" })
		local root = UIKit.screen(gui)
		UIKit.list(root, 4)
		local title = UIKit.text({ Text = "", TextSize = 20, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0.45, 0), Parent = root })
		local body = UIKit.text({ Text = "", TextSize = 16, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0.5, 0), Parent = root })
		local def = Minigames.ById[lane.Minigame] or Minigames.List[1]
		local state: LaneState = { Lane = lane, Def = def, Index = i, Player = nil, Shots = 0, Score = 0, Best = 0, Cup = nil, Screen = { Title = title, Body = body }, Blocked = {} }
		table.insert(lanes, state)
		buildProps(state)
	end
	buildStations()

	Shop.handle("buyTokenSkin", function(player, id)
		if type(id) == "string" then
			buyTokenSkin(player, id)
		end
	end)
	Net.event("LeaveActivity").OnServerEvent:Connect(function(player)
		Practice.leave(player)
	end)
	Data.Loaded:Connect(function(player)
		for _, m in Minigames.List do
			renderBoard(m.Id)
		end
		player:SetAttribute("InPractice", false)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = byPlayer[player]
		if state then
			state.Player = nil
			byPlayer[player] = nil
		end
		for _, st in lanes do
			st.Blocked[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, state in lanes do
				for player in state.Blocked do
					local root = Zones.rootOf(player)
					if not root or not Zones.onPad(state.Lane.StartPad, root.Position) then
						state.Blocked[player] = nil
					end
				end
			end
			for _, entry in Zones.freePlayers() do
				if Data.get(entry.Player) then
					for _, state in lanes do
						if not state.Player and not state.Blocked[entry.Player] and Zones.onPad(state.Lane.StartPad, entry.Root.Position) then
							begin(state, entry.Player)
							break
						end
					end
				end
			end
			for _, player in Players:GetPlayers() do
				local root = Zones.rootOf(player)
				local inside = byPlayer[player] ~= nil or (root ~= nil and inRange(root.Position))
				if player:GetAttribute("InPractice") ~= inside then
					player:SetAttribute("InPractice", inside)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			refreshBoards()
			task.wait(60)
		end
	end)
end

return Practice

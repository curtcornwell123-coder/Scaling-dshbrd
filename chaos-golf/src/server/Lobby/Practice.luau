--!strict
-- South wing Practice Range. One minigame is live on all six lanes at a time; the live game
-- rotates every Minigames.RotationSeconds (same order, same moment on every server) and the
-- whole range dresses itself as that game's biome (PracticeBiomes). A lane that is mid-run
-- when the game changes lets the run finish, then switches.
-- Screens: the gantry header (live game), the broadcast TV over the lanes and the two signs
-- at the atrium doorway (now playing / up next / countdown), and the live game's
-- best-scores board. Runs pay that game's tokens (never sold for Coins or Robux), spent at
-- the token hut, which shows the live game's crate and balls and sells every game's.
-- Players inside the range get the InPractice attribute so the HUD shows their tokens.

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
local CupHole = require(Server:WaitForChild("World"):WaitForChild("CupHole"))
local PracticeBiomes = require(Server:WaitForChild("World"):WaitForChild("PracticeBiomes"))
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
local GATE_SLACK = 0.2 -- the ball's centre must pass this far inside a gate's posts

type LaneState = {
	Lane: LobbyTypes.Lane,
	Def: Minigames.Minigame,
	Index: number,
	Player: Player?,
	Shots: number,
	Score: number,
	Best: number,
	Cup: Vector3?,
	Gates: { [number]: boolean }, -- gates passed on the current Gate Run shot
	LastD: number,
	Screen: { Title: TextLabel, Body: TextLabel },
	Blocked: { [Player]: boolean }, -- must step off the pad before starting again
}

local lanes: { LaneState } = {}
local byPlayer: { [Player]: LaneState } = {}
local lobbyRef: LobbyTypes.Lobby
local kioskFolder: Folder
local live: Minigames.Minigame = Minigames.List[1]
local liveSlot = -1

local function laneCF(state: LaneState, distance: number, y: number, x: number?): CFrame
	return state.Lane.Origin * CFrame.new(x or 0, y, -distance)
end

local function laneTitle(state: LaneState): string
	return "LANE " .. state.Index .. "  ·  " .. string.upper(state.Def.Name)
end

local function setScreen(state: LaneState, title: string, body: string)
	state.Screen.Title.Text = title
	state.Screen.Body.Text = body
end

-- Props --------------------------------------------------------------------

local DARK = Color3.fromRGB(30, 34, 46)

-- The lane end over the cup wells: shown plain, or hidden while a cut copy holds the cup.
local function showLaneEnd(lane: LobbyTypes.Lane, on: boolean)
	lane.End.Transparency = if on then 0 else 1
	lane.End.CanCollide = on
	lane.End.CanQuery = on
end

-- A real cup (CupHole) at a cup spot of this game: the lane end is swapped for a copy with
-- the hole cut in (over the well beneath), the flag beside it. Returns the rim centre.
local function cup(state: LaneState, spot: { D: number, X: number }, flag: Color3): Vector3
	local lane = state.Lane
	local folder = lane.Props
	local pos = laneCF(state, lane.Length - spot.D, 0, spot.X).Position
	pos = Vector3.new(pos.X, lane.End.Position.Y + lane.End.Size.Y / 2, pos.Z) -- the lane's top
	local live = lane.End:Clone()
	live:SetAttribute("LaneFloor", true)
	live.Parent = folder
	showLaneEnd(lane, false)
	CupHole.cut(live, pos)
	CupHole.build(folder, pos)
	Parts.rod(folder, pos + Vector3.new(1.4, 0, 0), pos + Vector3.new(1.4, 5, 0), 0.15, { Color = Color3.new(1, 1, 1), CanCollide = false, CanQuery = false })
	Parts.block(folder, CFrame.new(pos + Vector3.new(2.2, 4.4, 0)), Vector3.new(1.6, 1, 0.1), { Color = flag, CanCollide = false, CanQuery = false, Name = "Flag" })
	return pos
end

local function buildProps(state: LaneState)
	local lane = state.Lane
	local folder = lane.Props
	folder:ClearAllChildren()
	showLaneEnd(lane, true)
	local W, L = lane.Width, lane.Length
	local id = state.Def.Id
	state.Cup = nil

	-- Back bumper so balls can't roll off the lane start.
	Parts.block(folder, laneCF(state, -1.6, 0.7), Vector3.new(W, 1.4, 0.8), { Color = DARK, Name = "BackBumper" })

	if id == "Target" then
		local d = L - 12
		for i = #TARGET_RINGS, 1, -1 do
			local ring = TARGET_RINGS[i]
			local color = if i == 1 then Color3.fromRGB(230, 57, 70) elseif i == 2 then Color3.fromRGB(255, 255, 255) else state.Def.Color
			local disc = Parts.cylinder(folder, laneCF(state, d, 0.02 + i * 0.01), 0.04, ring.Radius * 2, {
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				Name = "Ring" .. ring.Points,
			})
			disc.CastShadow = false
		end
	elseif id == "Drive" then
		local H = L - RAMP_START - 2
		local slope = H / math.cos(RAMP_ANGLE)
		local rise = H * math.tan(RAMP_ANGLE)
		local startCF = laneCF(state, RAMP_START, 0)
		local rampCF = startCF * CFrame.Angles(RAMP_ANGLE, 0, 0) * CFrame.new(0, -0.5, -slope / 2)
		local ramp = Parts.block(folder, rampCF, Vector3.new(W, 1, slope), { Color = Color3.fromRGB(52, 60, 82), Name = "Ramp" })
		ramp.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.2)
		for _, side in { -1, 1 } do
			Parts.block(folder, rampCF * CFrame.new(side * (W / 2 - 0.4), 1.5, 0), Vector3.new(0.8, 2.2, slope), { Color = DARK, Name = "RampRail" })
		end
		Parts.block(folder, startCF * CFrame.new(0, rise + 2, -H - 0.4), Vector3.new(W, 5, 0.8), { Color = DARK, Name = "RampCap" })
		for mark = 10, math.floor(slope), 10 do
			local strip = Parts.block(folder, startCF * CFrame.Angles(RAMP_ANGLE, 0, 0) * CFrame.new(0, 0.03, -mark), Vector3.new(W - 1.8, 0.05, 0.3), {
				Color = state.Def.Color,
				CanCollide = false,
				CanQuery = false,
			})
			Parts.label(strip, Enum.NormalId.Top, tostring(mark), { PixelsPerStud = 20, TextColor = T.Text })
		end
	elseif id == "Hazard" then
		for i, d in { 14, 26, 38 } do
			if d < L - 8 then
				local hub = Parts.cylinder(folder, laneCF(state, d, 1), 2, 1.2, { Color = DARK, Name = "Hub" })
				local bar = Instance.new("Part")
				bar.Name = "Sweeper"
				bar.Size = Vector3.new(W - 2.2, 0.9, 0.7)
				bar.CFrame = laneCF(state, d, 0.95)
				bar.Color = state.Def.Color
				bar.Material = Enum.Material.SmoothPlastic
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
		state.Cup = cup(state, Minigames.CupSpots.Hazard, state.Def.Color)
	elseif id == "Bank" then
		-- An ice wall from the left rail across most of the lane hides the cup: go through the
		-- gap on the right and bank off the end boards (the lane is slippery ice).
		local wallW = W * 0.62
		local wallD = L - 15
		local wall = Parts.block(folder, laneCF(state, wallD, 0.9, -W / 2 + wallW / 2), Vector3.new(wallW, 1.8, 1.2), {
			Name = "IceWall",
			Color = Color3.fromHex("#A9D8F0"),
			Material = Enum.Material.Ice,
			Reflectance = 0.1,
		})
		wall.CustomPhysicalProperties = PhysicalProperties.new(1, 0.05, 0.8)
		Parts.block(folder, laneCF(state, wallD, 1.9, -W / 2 + wallW / 2), Vector3.new(wallW + 0.1, 0.2, 1.3), { Name = "WallCap", Color = Color3.fromHex("#2A6F97"), CanCollide = false, CanQuery = false })
		-- A low deflector off the right rail near the end sends banked shots back across.
		local def = Parts.block(folder, laneCF(state, L - 3.2, 0.6, W / 2 - 1.6) * CFrame.Angles(0, math.rad(-40), 0), Vector3.new(3.6, 1.2, 0.6), {
			Name = "Deflector",
			Color = Color3.fromHex("#F4F7FA"),
		})
		def.CustomPhysicalProperties = PhysicalProperties.new(1, 0.05, 0.85)
		state.Cup = cup(state, Minigames.CupSpots.Bank, state.Def.Color)
	elseif id == "Gates" then
		local sand, dark = Color3.fromHex("#C98F5A"), Color3.fromHex("#8F4A2B")
		for i, g in Minigames.Gates do
			local cf = laneCF(state, g.D, 0, g.Offset)
			for _, s in { -1, 1 } do
				Parts.block(folder, cf * CFrame.new(s * (g.Width / 2 + 0.45), 1.6, 0), Vector3.new(0.9, 3.2, 0.9), { Name = "GatePost", Color = sand, Material = Enum.Material.Sandstone })
			end
			local lintel = Parts.block(folder, cf * CFrame.new(0, 3.45, 0), Vector3.new(g.Width + 1.8, 0.6, 1.1), { Name = "GateLintel", Color = dark, Material = Enum.Material.Sandstone, CanCollide = false, CanQuery = false })
			Parts.label(lintel, Enum.NormalId.Back, tostring(i), { TextColor = Color3.fromHex("#FCE3B0"), PixelsPerStud = 30 })
		end
		local stop = Minigames.GateStopLine
		Parts.block(folder, laneCF(state, stop, 0.04), Vector3.new(W, 0.05, 0.4), { Name = "StopLine", Color = Color3.fromRGB(214, 40, 40), CanCollide = false, CanQuery = false })
		Parts.block(folder, laneCF(state, (stop + L) / 2, 0.035), Vector3.new(W, 0.03, L - stop), { Name = "NoScore", Color = Color3.fromRGB(150, 50, 40), Transparency = 0.5, CanCollide = false, CanQuery = false })
	end
	setScreen(state, laneTitle(state), "Step on the pad to play")
end

-- Runs -----------------------------------------------------------------------

local function ballStart(state: LaneState): Vector3
	return laneCF(state, 2.5, Config.Ball.Diameter / 2 + 0.1).Position
end

-- Best scores --------------------------------------------------------------------
-- Ordered stores rank "higher is better"; stroke games (1-4) are stored as 10 - strokes.

export type BestEntry = { Name: string, Score: number }

local board: { Title: TextLabel, Rows: { TextLabel } }? = nil
local cache: { [string]: { BestEntry }? } = {}

local function lower(id: string): boolean
	local m = Minigames.ById[id]
	return m ~= nil and m.LowerIsBetter == true
end

local function encode(id: string, score: number): number
	return if lower(id) then 10 - score else score
end

local function decode(id: string, value: number): number
	return if lower(id) then 10 - value else value
end

local function better(id: string, new: number, old: number): boolean
	if new <= 0 then
		return false
	end
	if lower(id) then
		return old <= 0 or new < old
	end
	return new > old
end

local function scoreLabel(id: string, score: number): string
	if id == "Drive" then
		return score .. " studs"
	elseif lower(id) then
		return if score <= 0 then "missed" else score .. (if score == 1 then " stroke" else " strokes")
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

local function renderBoard()
	local b = board
	if not b then
		return
	end
	local id = live.Id
	b.Title.Text = string.upper(live.Name) .. "  ·  ALL-TIME BEST"
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
	end
	renderBoard()
end

local function recordBest(player: Player, id: string, score: number)
	local profile = Data.profile(player)
	if not profile or not better(id, score, profile.PracticeBest[id] or 0) then
		return
	end
	profile.PracticeBest[id] = score
	Data.markDirty(player)
	Net.event("Toast"):FireClient(player, "New personal best: " .. scoreLabel(id, score) .. "!", Config.Colors.Gold)
	if id == live.Id then
		renderBoard()
	end
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

local function switchIfIdle(state: LaneState)
	if not state.Player and state.Def.Id ~= live.Id then
		state.Def = live
		buildProps(state)
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
	local id = state.Def.Id
	local score = if id == "Drive" then math.floor(state.Best) else state.Score
	local tokens = if completed then Minigames.tokensFor(id, score) else 0
	if tokens > 0 then
		Data.addTokens(player, id, tokens)
	end
	if completed then
		recordBest(player, id, score)
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
	setScreen(state, laneTitle(state), player.DisplayName .. ": " .. scoreLabel(id, score) .. "  ·  +" .. tokens .. " tokens")
	-- The live game may have changed during the run: switch this lane now it's free.
	task.delay(1.5, function()
		switchIfIdle(state)
	end)
end

-- Ball position in lane space: (lateral x, distance down the lane).
local function lanePos(state: LaneState, p: Vector3): (number, number)
	local l = state.Lane.Origin:PointToObjectSpace(p)
	return l.X, -l.Z
end

local function makeContext(state: LaneState): BallService.Context
	local def = state.Def
	return {
		CanShoot = function(ball)
			return state.Player == ball.Player and state.Shots < def.Shots
		end,
		OnShot = function(ball)
			state.Shots += 1
			state.Gates = {}
			local _, d = lanePos(state, ball.Part.Position)
			state.LastD = d
		end,
		OnRest = function(ball)
			local player = ball.Player
			if def.Id == "Target" then
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
				Net.event("Toast"):FireClient(player, if pts > 0 then "+" .. pts .. " points" else "Missed the rings", if pts >= 10 then Config.Colors.Gold else nil)
				setScreen(state, laneTitle(state), string.format("%s  ·  %d pts  ·  shot %d/%d", player.DisplayName, state.Score, state.Shots, def.Shots))
			elseif def.Id == "Drive" then
				local best = math.floor(ball.MaxDistance)
				state.Best = math.max(state.Best, ball.MaxDistance)
				Net.event("Toast"):FireClient(player, best .. " studs up the ramp", nil)
				setScreen(state, laneTitle(state), string.format("%s  ·  best %d studs  ·  drive %d/%d", player.DisplayName, math.floor(state.Best), state.Shots, def.Shots))
			elseif def.Id == "Gates" then
				local _, d = lanePos(state, ball.Part.Position)
				local pts, passed = 0, 0
				for i in state.Gates do
					pts += i
					passed += 1
				end
				if d >= Minigames.GateStopLine then
					Net.event("Toast"):FireClient(player, "Past the red line: no score", Config.Colors.Bad)
					pts = 0
				else
					Net.event("Toast"):FireClient(player, string.format("%d gate%s · +%d points", passed, if passed == 1 then "" else "s", pts), if pts >= 12 then Config.Colors.Gold else nil)
				end
				state.Score += pts
				setScreen(state, laneTitle(state), string.format("%s  ·  %d pts  ·  shot %d/%d", player.DisplayName, state.Score, state.Shots, def.Shots))
			else -- Hazard, Bank: play on from where it stopped
				if state.Shots >= def.Shots then
					Net.event("Toast"):FireClient(player, "Out of strokes!", Config.Colors.Bad)
					state.Score = 0
					finish(state, true)
				end
				return
			end
			if state.Shots >= def.Shots then
				task.delay(0.6, function()
					if state.Player == player then
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
			if def.Id == "Drive" then
				local start = laneCF(state, RAMP_START, 0)
				local dir = (start * CFrame.Angles(RAMP_ANGLE, 0, 0)).LookVector
				local along = (ball.Part.Position - start.Position):Dot(dir)
				if along > ball.MaxDistance then
					ball.MaxDistance = along
				end
			elseif def.Id == "Gates" then
				local x, d = lanePos(state, ball.Part.Position)
				for i, g in Minigames.Gates do
					if not state.Gates[i] and state.LastD < g.D and d >= g.D and math.abs(x - g.Offset) <= g.Width / 2 - GATE_SLACK then
						state.Gates[i] = true
					end
				end
				state.LastD = d
			end
		end,
	}
end

local function begin(state: LaneState, player: Player)
	local profile = Data.profile(player)
	if not profile then
		return
	end
	switchIfIdle(state)
	state.Player = player
	state.Shots = 0
	state.Score = 0
	state.Best = 0
	state.Gates = {}
	state.LastD = 0
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
	setScreen(state, laneTitle(state), player.DisplayName .. " is playing")
end

-- Token hut ----------------------------------------------------------------------

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

-- The live game's crate on the counter and its four balls on the shelves.
local function dressHut()
	kioskFolder:ClearAllChildren()
	local hut = lobbyRef.South.Hut
	local crate = Crates.get(live.Id)
	if crate then
		Displays.bob(Displays.crate(kioskFolder, Displays.anchorPoint(hut.Display), crate.Color, 2.4))
	end
	for k, skin in Skins.withSource("Token:" .. live.Id) do
		local spot = hut.Shelf[k]
		if spot then
			Displays.ball(kioskFolder, Displays.anchorPoint(spot), skin.Id, 1.3)
		end
	end
end

local function buildHut()
	local prompt = Parts.prompt(lobbyRef.South.Hut.Counter, "Open shop", "Token Exchange", { Distance = 10, Name = "TokenShopPrompt" })
	prompt.Triggered:Connect(function(player)
		Net.event("Fx"):FireClient(player, "tokenShop", { Minigame = live.Id })
	end)
	local gui = UIKit.surface(lobbyRef.South.Board, { PixelsPerStud = 40, Name = "BestScoresUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 4)
	local title = UIKit.text({ Text = "", TextSize = 26, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 34), Parent = root })
	local rows: { TextLabel } = {}
	for i = 1, 7 do
		rows[i] = UIKit.text({ Text = i .. ".  —", TextSize = 22, Font = T.FontMedium, TextColor3 = if i == 1 then T.Gold else T.Text, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = i, Parent = root })
	end
	board = { Title = title, Rows = rows }
end

-- Screens: gantry header, broadcast TV and the atrium signs ------------------------------

type Broadcast = {
	HeaderName: TextLabel,
	Now: TextLabel,
	NowBiome: TextLabel,
	Rules: TextLabel,
	Next: TextLabel,
	Clock: TextLabel,
	Fill: Frame,
	NowDot: Frame,
	SignNow: { Name: TextLabel, Sub: TextLabel }?,
	SignNext: { Name: TextLabel, Sub: TextLabel }?,
}
local broadcast: Broadcast

local function colorHex(c: Color3): string
	return "#" .. c:ToHex()
end

local function buildBroadcast()
	local south = lobbyRef.South
	-- Gantry header.
	local hg = UIKit.surface(south.Header, { PixelsPerStud = 40, Name = "HeaderUI" })
	local hroot = UIKit.screen(hg)
	local headerName = UIKit.text({ Text = "", TextSize = 64, Font = T.FontHeavy, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = hroot })

	-- Broadcast TV: left = now playing, right = up next with the countdown.
	local tg = UIKit.surface(south.TV, { PixelsPerStud = 40, Name = "BroadcastUI" })
	local troot = UIKit.screen(tg)
	UIKit.padding(troot, 22)
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(0.62, -12, 1, 0)
	left.Parent = troot
	UIKit.list(left, 6)
	UIKit.text({ Text = "● LIVE NOW", TextSize = 30, Font = T.FontHeavy, TextColor3 = Color3.fromRGB(235, 87, 87), Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, Parent = left })
	local now = UIKit.text({ Text = "", TextSize = 72, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 84), TextScaled = true, LayoutOrder = 2, Parent = left })
	local nowBiome = UIKit.text({ Text = "", TextSize = 30, Font = T.Font, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3, Parent = left })
	local rules = UIKit.text({ Text = "", TextSize = 26, Font = T.FontMedium, Size = UDim2.new(1, 0, 0, 110), TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 4, Parent = left })
	local right = UIKit.card({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, -12, 1, 0), Parent = troot })
	UIKit.padding(right, 18)
	UIKit.list(right, 8)
	UIKit.text({ Text = "UP NEXT", TextSize = 28, Font = T.FontHeavy, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, Parent = right })
	local nextName = UIKit.text({ Text = "", TextSize = 44, Font = T.FontHeavy, TextScaled = true, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 2, Parent = right })
	local clock = UIKit.text({ Text = "", TextSize = 64, Font = T.FontHeavy, TextColor3 = T.Gold, Size = UDim2.new(1, 0, 0, 72), LayoutOrder = 3, Parent = right })
	local barBg = Instance.new("Frame")
	barBg.BackgroundColor3 = T.SurfaceHi
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 14)
	barBg.LayoutOrder = 4
	barBg.Parent = right
	UIKit.corner(barBg, UDim.new(1, 0))
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = T.Gold
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = barBg
	UIKit.corner(fill, UDim.new(1, 0))
	UIKit.text({ Text = "Every practice runs " .. math.floor(Minigames.RotationSeconds / 60) .. " minutes. Same game in every server.", TextSize = 18, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 48), TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 5, Parent = right })
	local nowDot = Instance.new("Frame")
	nowDot.BorderSizePixel = 0
	nowDot.Size = UDim2.new(0.62, -12, 0, 8)
	nowDot.AnchorPoint = Vector2.new(0, 1)
	nowDot.Position = UDim2.fromScale(0, 1)
	nowDot.Parent = troot
	UIKit.corner(nowDot, UDim.new(1, 0))

	broadcast = {
		HeaderName = headerName,
		Now = now,
		NowBiome = nowBiome,
		Rules = rules,
		Next = nextName,
		Clock = clock,
		Fill = fill,
		NowDot = nowDot,
	}

	-- Atrium signs: left = now playing, right = up next.
	local function sign(part: BasePart, heading: string): { Name: TextLabel, Sub: TextLabel }
		-- Hung overhead in the doorway: fewer pixels per stud reads larger from across the hub.
		local g = UIKit.surface(part, { PixelsPerStud = 42, Name = "SignUI" })
		local root = UIKit.screen(g)
		UIKit.list(root, 4, false, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Center
		UIKit.text({ Text = heading, TextSize = 22, Font = T.FontHeavy, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = root })
		local name = UIKit.text({ Text = "", TextSize = 40, Font = T.FontHeavy, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 2, Parent = root })
		local sub = UIKit.text({ Text = "", TextSize = 22, Font = T.Font, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, Parent = root })
		return { Name = name, Sub = sub }
	end
	local signs = south.LobbyTVs
	-- Built left then right as seen from the hub: live now on the left, up next on the right.
	if signs[1] then
		broadcast.SignNow = sign(signs[1], "PRACTICE · LIVE NOW")
	end
	if signs[2] then
		broadcast.SignNext = sign(signs[2], "PRACTICE · UP NEXT")
	end
end

local function renderBroadcast()
	local b = broadcast
	if not b then
		return
	end
	local nextGame = Minigames.upNext()
	local left = Minigames.endsIn()
	local clock = UIKit.formatTime(left)
	b.HeaderName.Text = string.format('<font color="%s">%s</font>  ·  %s', colorHex(live.Color), string.upper(live.Name), string.upper(live.BiomeName))
	b.Now.Text = string.format('<font color="%s">%s</font>', colorHex(live.Color), live.Name)
	b.NowBiome.Text = live.BiomeName .. "  ·  " .. live.Token
	b.Rules.Text = live.Rules
	b.Next.Text = string.format('<font color="%s">%s</font>', colorHex(nextGame.Color), nextGame.Name)
	b.Clock.Text = clock
	b.Fill.Size = UDim2.fromScale(1 - left / Minigames.RotationSeconds, 1)
	b.NowDot.BackgroundColor3 = live.Color
	if b.SignNow then
		b.SignNow.Name.Text = string.format('<font color="%s">%s</font>', colorHex(live.Color), live.Name)
		b.SignNow.Sub.Text = live.BiomeName .. "  ·  " .. clock .. " left"
	end
	if b.SignNext then
		b.SignNext.Name.Text = string.format('<font color="%s">%s</font>', colorHex(nextGame.Color), nextGame.Name)
		b.SignNext.Sub.Text = "starts in " .. clock
	end
end

-- Rotation --------------------------------------------------------------------------------

local function applyLive(announce: boolean)
	liveSlot = Minigames.slot()
	live = Minigames.active()
	PracticeBiomes.apply(lobbyRef.South, live.Biome, liveSlot * 7919 + 13)
	for _, state in lanes do
		switchIfIdle(state)
	end
	dressHut()
	renderBoard()
	renderBroadcast()
	if announce then
		Net.event("Fx"):FireAllClients("practiceRotated", { Minigame = live.Name, Biome = live.BiomeName, Color = live.Color })
	end
end

function Practice.live(): Minigames.Minigame
	return live
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
	live = Minigames.active()
	for i, lane in lobby.South.Lanes do
		local gui = UIKit.surface(lane.Screen, { PixelsPerStud = 50, Name = "LaneUI" })
		local root = UIKit.screen(gui)
		UIKit.list(root, 4)
		local title = UIKit.text({ Text = "", TextSize = 20, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0.45, 0), Parent = root })
		local body = UIKit.text({ Text = "", TextSize = 16, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0.5, 0), Parent = root })
		local state: LaneState = {
			Lane = lane,
			Def = live,
			Index = i,
			Player = nil,
			Shots = 0,
			Score = 0,
			Best = 0,
			Cup = nil,
			Gates = {},
			LastD = 0,
			Screen = { Title = title, Body = body },
			Blocked = {},
		}
		table.insert(lanes, state)
		buildProps(state)
	end
	buildHut()
	buildBroadcast()
	applyLive(false)

	Shop.handle("buyTokenSkin", function(player, id)
		if type(id) == "string" then
			buyTokenSkin(player, id)
		end
	end)
	Net.event("LeaveActivity").OnServerEvent:Connect(function(player)
		Practice.leave(player)
	end)
	Data.Loaded:Connect(function(player)
		renderBoard()
		player:SetAttribute("InPractice", false)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = byPlayer[player]
		if state then
			state.Player = nil
			byPlayer[player] = nil
			task.defer(switchIfIdle, state)
		end
		for _, st in lanes do
			st.Blocked[player] = nil
		end
	end)

	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.25)
			tick += 1
			if Minigames.slot() ~= liveSlot then
				applyLive(true)
			elseif tick % 4 == 0 then
				renderBroadcast()
			end
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

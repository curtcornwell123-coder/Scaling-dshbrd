--!strict
-- South room Practice Zone. Five lanes run the active minigame (Target Putting,
-- Velocity Long-Drive, Hazard Avoidance), rotating every 20 minutes on a clock
-- shared by all servers. Runs pay minigame-specific tokens that can't be bought
-- with Coins or Robux; the token kiosk sells the active minigame's crate and
-- skins only.

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
local active: Minigames.Minigame = Minigames.List[1]
local lobbyRef: LobbyTypes.Lobby
local kioskFolder: Folder
local signUi: { Title: TextLabel, Rules: TextLabel, Timer: TextLabel, Next: TextLabel }

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

	if active.Id == "Target" then
		local d = L - 12
		for i = #TARGET_RINGS, 1, -1 do
			local ring = TARGET_RINGS[i]
			local color = if i == 1 then Color3.fromRGB(255, 70, 90) elseif i == 2 then Color3.fromRGB(255, 255, 255) else active.Color
			local disc = Parts.cylinder(folder, laneCF(state, d, 0.02 + i * 0.01), 0.04, ring.Radius * 2, {
				Color = color,
				Material = if i == 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				Name = "Ring" .. ring.Points,
			})
			disc.CastShadow = false
		end
	elseif active.Id == "Drive" then
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
				Color = active.Color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
			Parts.label(strip, Enum.NormalId.Top, tostring(mark), { PixelsPerStud = 20, TextColor = T.Text })
		end
	elseif active.Id == "Hazard" then
		for i, d in { 14, 26, 38 } do
			if d < L - 8 then
				local hub = Parts.cylinder(folder, laneCF(state, d, 1), 2, 1.2, { Color = Color3.fromRGB(30, 34, 46), Name = "Hub" })
				local bar = Instance.new("Part")
				bar.Name = "Sweeper"
				bar.Size = Vector3.new(W - 2.2, 0.9, 0.7)
				bar.CFrame = laneCF(state, d, 0.95)
				bar.Color = active.Color
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
		Parts.block(folder, CFrame.new(cup + Vector3.new(2.2, 4.4, 0)), Vector3.new(1.6, 1, 0.1), { Color = active.Color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
	end
	setScreen(state, "LANE " .. state.Index .. "  ·  " .. string.upper(active.Name), "Step on the pad to play")
end

-- Runs -----------------------------------------------------------------------

local function ballStart(state: LaneState): Vector3
	return laneCF(state, 2.5, Config.Ball.Diameter / 2 + 0.1).Position
end

local function finish(state: LaneState, completed: boolean)
	local player = state.Player
	if not player then
		return
	end
	state.Player = nil
	byPlayer[player] = nil
	BallService.destroy(player)
	local score = if active.Id == "Drive" then math.floor(state.Best) else state.Score
	local tokens = if completed then Minigames.tokensFor(active.Id, score) else 0
	if tokens > 0 then
		Data.addTokens(player, active.Id, tokens)
	end
	if player.Parent == Players then
		Activity.set(player, nil)
		state.Blocked[player] = true
		Activity.unpark(player, CFrame.lookAt(state.Lane.StartPad.Position + Vector3.new(0, 3, 0) - state.Lane.Origin.LookVector * 4, state.Lane.Origin.Position + Vector3.new(0, 3, 0)))
		Net.event("BallAssigned"):FireClient(player, nil, { Context = "None" })
		Net.event("Fx"):FireClient(player, "practice", {
			Minigame = active.Name,
			Score = score,
			Tokens = tokens,
			Token = active.Token,
			Completed = completed,
		})
	end
	local scoreText = if active.Id == "Drive" then score .. " studs" elseif active.Id == "Hazard" then (if score > 0 then score .. " strokes" else "missed") else score .. " pts"
	setScreen(state, "LANE " .. state.Index .. "  ·  " .. string.upper(active.Name), player.DisplayName .. ": " .. scoreText .. "  ·  +" .. tokens .. " tokens")
end

local function makeContext(state: LaneState): BallService.Context
	return {
		CanShoot = function(ball)
			return state.Player == ball.Player and state.Shots < active.Shots
		end,
		OnShot = function(_ball)
			state.Shots += 1
		end,
		OnRest = function(ball)
			if active.Id == "Target" then
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
				setScreen(state, "LANE " .. state.Index .. "  ·  TARGET", string.format("%s  ·  %d pts  ·  shot %d/%d", ball.Player.DisplayName, state.Score, state.Shots, active.Shots))
			elseif active.Id == "Drive" then
				local best = math.floor(ball.MaxDistance)
				state.Best = math.max(state.Best, ball.MaxDistance)
				Net.event("Toast"):FireClient(ball.Player, best .. " studs up the ramp", nil)
				setScreen(state, "LANE " .. state.Index .. "  ·  LONG-DRIVE", string.format("%s  ·  best %d studs  ·  drive %d/%d", ball.Player.DisplayName, math.floor(state.Best), state.Shots, active.Shots))
			elseif active.Id == "Hazard" then
				if state.Shots >= active.Shots then
					Net.event("Toast"):FireClient(ball.Player, "Out of strokes!", Config.Colors.Bad)
					finish(state, true)
					return
				end
				return -- play on from where it stopped
			end
			if state.Shots >= active.Shots then
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
			if active.Id == "Drive" then
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
		Minigame = active.Id,
		Title = active.Name,
		Rules = active.Rules,
		TeeLook = state.Lane.Origin.LookVector,
		Cup = state.Cup,
		PowerCycle = Config.Physics.PowerCycleSeconds * (1 + (profile.Upgrades.Control or 0) * 0.08),
	})
	Net.event("Toast"):FireClient(player, active.Rules, nil)
	setScreen(state, "LANE " .. state.Index .. "  ·  " .. string.upper(active.Name), player.DisplayName .. " is playing")
end

-- Token kiosk -------------------------------------------------------------------

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
	if skin.Source ~= "Token:" .. active.Id then
		Net.event("Fx"):FireClient(player, "shopResult", { Ok = false, Text = skin.Name .. " returns when its minigame is active" })
		return
	end
	local price = Crates.TokenDirectPrice[skin.Rarity] or 999
	if (profile.Tokens[active.Id] or 0) < price then
		Net.event("Fx"):FireClient(player, "shopResult", { Ok = false, Text = "Not enough " .. active.Token })
		return
	end
	Data.addTokens(player, active.Id, -price)
	Data.grant(player, "Skins", id)
	Data.equip(player, "Skins", id)
	Net.event("Fx"):FireClient(player, "shopResult", { Ok = true, Text = "Unlocked " .. skin.Name })
end

local function buildKiosk()
	kioskFolder:ClearAllChildren()
	local kiosk = lobbyRef.South.TokenKiosk
	for _, child in kiosk.CratePedestal:GetChildren() do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
	local crate = Crates.get(active.Id) :: Crates.Crate
	local model = Displays.crate(kioskFolder, Displays.anchorPoint(kiosk.CratePedestal), crate.Color)
	Displays.bob(model)
	local prompt = Parts.prompt(kiosk.CratePedestal, "Open · " .. crate.Price .. " tokens", crate.Name, { Hold = 0.3, Distance = 9 })
	prompt:SetAttribute("CrateId", crate.Id)
	prompt.Triggered:Connect(function(player)
		Shop.openCrate(player, crate.Id)
	end)
	local skins = Skins.withSource("Token:" .. active.Id)
	for i, pedestal in kiosk.SkinPedestals do
		for _, child in pedestal:GetChildren() do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
		local skin = skins[i]
		if skin then
			local ball = Displays.ball(kioskFolder, Displays.anchorPoint(pedestal), skin.Id, 2.6)
			local price = Crates.TokenDirectPrice[skin.Rarity] or 0
			Displays.card(ball, 2.8, skin.Name, skin.Rarity .. " · " .. active.Name .. " exclusive", price .. " tokens", Skins.Rarities[skin.Rarity].Color)
			local p = Parts.prompt(pedestal, "Unlock · " .. price .. " tokens", skin.Name, { Distance = 8 })
			p:SetAttribute("SkinId", skin.Id)
			p.Triggered:Connect(function(player)
				buyTokenSkin(player, skin.Id)
			end)
		end
	end
end

local function buildSign(part: BasePart)
	local gui = UIKit.surface(part, { PixelsPerStud = 40, Name = "RotationUI" })
	local root = UIKit.screen(gui)
	UIKit.list(root, 8)
	local title = UIKit.text({ Text = "", TextSize = 44, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 52), Parent = root })
	local rules = UIKit.text({ Text = "", TextSize = 22, Font = T.FontMedium, Size = UDim2.new(1, 0, 0, 56), Parent = root })
	local timer = UIKit.text({ Text = "", TextSize = 26, TextColor3 = T.Primary, Size = UDim2.new(1, 0, 0, 32), Parent = root })
	local nextText = UIKit.text({ Text = "", TextSize = 18, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 48), Parent = root })
	signUi = { Title = title, Rules = rules, Timer = timer, Next = nextText }
end

local function renderSign()
	local m, remaining = Minigames.active(os.time())
	local index = table.find(Minigames.List, m) or 1
	local upcoming = Minigames.List[(index % #Minigames.List) + 1]
	signUi.Title.Text = "NOW: " .. string.upper(m.Name)
	signUi.Rules.Text = m.Rules
	signUi.Timer.Text = "Rotates in " .. UIKit.formatTime(remaining)
	signUi.Next.Text = "Next up: " .. upcoming.Name .. "  ·  Earn " .. m.Token .. " here; spend them at the kiosk on " .. m.Name .. "-exclusive skins. Tokens can't be bought."
end

local function rotate(m: Minigames.Minigame)
	active = m
	for _, state in lanes do
		if state.Player then
			Net.event("Toast"):FireClient(state.Player, "The practice zone is rotating to " .. m.Name .. "!", nil)
			finish(state, false)
		end
		buildProps(state)
	end
	buildKiosk()
	workspace:SetAttribute("PracticeMinigame", m.Id)
end

function Practice.leave(player: Player): boolean
	local state = byPlayer[player]
	if not state then
		return false
	end
	finish(state, false)
	return true
end

function Practice.start(lobby: LobbyTypes.Lobby)
	lobbyRef = lobby
	kioskFolder = Parts.folder(lobby.Model, "TokenKioskProps")
	for i, lane in lobby.South.Lanes do
		local gui = UIKit.surface(lane.Screen, { PixelsPerStud = 50, Name = "LaneUI" })
		local root = UIKit.screen(gui)
		UIKit.list(root, 4)
		local title = UIKit.text({ Text = "", TextSize = 20, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0.45, 0), Parent = root })
		local body = UIKit.text({ Text = "", TextSize = 16, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0.5, 0), Parent = root })
		table.insert(lanes, { Lane = lane, Index = i, Player = nil, Shots = 0, Score = 0, Best = 0, Cup = nil, Screen = { Title = title, Body = body }, Blocked = {} })
	end
	buildSign(lobby.South.RotationSign)
	rotate((Minigames.active(os.time())))

	Shop.handle("buyTokenSkin", function(player, id)
		if type(id) == "string" then
			buyTokenSkin(player, id)
		end
	end)
	Net.event("LeaveActivity").OnServerEvent:Connect(function(player)
		Practice.leave(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = byPlayer[player]
		if state then
			state.Player = nil
			byPlayer[player] = nil
		end
		for _, s in lanes do
			s.Blocked[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local m = Minigames.active(os.time())
			if m ~= active then
				rotate(m)
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
		end
	end)
	task.spawn(function()
		while true do
			renderSign()
			task.wait(1)
		end
	end)
end

return Practice

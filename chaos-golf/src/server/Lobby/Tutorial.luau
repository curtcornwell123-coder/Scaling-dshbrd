--!strict
-- Tutorial: a private 3-hole course (aim & power, banking, chaos abilities).
-- New players spawn in the lobby and get a one-time invite (Play / Skip); the
-- course explains itself on screen (a step checklist that ticks as you go) and
-- on its signs. Skippable at any time, replayable from the pad in the Practice
-- room. Afterwards, first-timers get a walking arrow to the direction sign.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Server = script.Parent.Parent
local CourseBuilder = require(Server:WaitForChild("World"):WaitForChild("CourseBuilder"))
local LobbyTypes = require(Server:WaitForChild("World"):WaitForChild("LobbyTypes"))
local Activity = require(Server:WaitForChild("Services"):WaitForChild("Activity"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Zones = require(Server:WaitForChild("Services"):WaitForChild("Zones"))
local AbilityService = require(Server:WaitForChild("Golf"):WaitForChild("AbilityService"))
local BallService = require(Server:WaitForChild("Golf"):WaitForChild("BallService"))

local Tutorial = {}

local REWARD_COINS = 200
local REWARD_SKIN = "rookie"

local INSTRUCTIONS = {
	"HOLE 1 · THE BASICS\nAim by moving the camera (drag on mobile).\nHold Left Click, Space or tap & hold to charge power, release to putt.\nSink it in the cup!",
	"HOLE 2 · BANK SHOTS\nRails bounce your ball.\nBank off the wall to get around the corner.",
	"HOLE 3 · CHAOS\nRoll through the glowing CHAOS BOX to grab an ability,\nthen press 1 (or tap its button) to use it. Try the Cup Magnet!",
}

-- On-screen lessons, one per hole. Step keys are worded per device by the client.
local LESSONS = {
	{ Title = "THE BASICS", Steps = { "aim", "charge", "release", "sink" } },
	{ Title = "BANK SHOTS", Steps = { "bank", "sink" } },
	{ Title = "CHAOS ABILITIES", Steps = { "box", "ability", "sink" } },
}
local SHOT_STEPS = { "aim", "charge", "release", "bank" } -- all done by the first putt

type Run = {
	Player: Player,
	Course: CourseBuilder.Course?,
	Hole: number,
	Slot: number,
	Ended: boolean,
	FirstTime: boolean,
	Done: { [string]: boolean },
	Strokes: number,
}

local runs: { [Player]: Run } = {}
local slots: { [number]: boolean } = {}
local lobby: LobbyTypes.Lobby
local padBlocked: { [Player]: boolean } = {}
local invited: { [Player]: boolean } = {}

local function pushSteps(run: Run)
	local lesson = LESSONS[run.Hole]
	if not lesson or run.Ended then
		return
	end
	local steps = {}
	for _, key in lesson.Steps do
		table.insert(steps, { Key = key, Done = run.Done[key] == true })
	end
	Net.event("Tutorial"):FireClient(run.Player, "steps", {
		Hole = run.Hole,
		Holes = #LESSONS,
		Title = lesson.Title,
		Steps = steps,
	})
end

local function complete(run: Run, keys: { string })
	local lesson = LESSONS[run.Hole]
	if not lesson then
		return
	end
	local changed = false
	for _, key in keys do
		if not run.Done[key] and table.find(lesson.Steps, key) then
			run.Done[key] = true
			changed = true
		end
	end
	if changed then
		pushSteps(run)
	end
end

local function setSign(hole: CourseBuilder.Hole, text: string)
	local sign = hole.Model:FindFirstChild("InstructionSign", true)
	if not sign then
		return
	end
	local label = sign:FindFirstChild("Text", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function guide(player: Player)
	local profile = Data.profile(player)
	if profile and not profile.DirectoryDone then
		task.delay(1.5, function()
			if player.Parent then
				Net.event("Guide"):FireClient(player, lobby.Directory.StandPoint)
			end
		end)
	end
end

local function finish(run: Run, completed: boolean)
	if run.Ended then
		return
	end
	run.Ended = true
	local player = run.Player
	runs[player] = nil
	BallService.destroy(player)
	AbilityService.clear(player)
	if run.Course then
		(run.Course :: CourseBuilder.Course).Destroy()
	end
	slots[run.Slot] = nil
	if player.Parent ~= Players then
		return
	end
	local profile = Data.profile(player)
	if profile then
		local firstCompletion = completed and not profile.TutorialDone
		profile.TutorialDone = true
		Data.markDirty(player)
		if firstCompletion or (completed and not Data.owns(player, "Skins", REWARD_SKIN)) then
			Data.addCoins(player, REWARD_COINS, "tutorial")
			Data.grant(player, "Skins", REWARD_SKIN)
			Net.event("Toast"):FireClient(player, "Tutorial complete! +" .. REWARD_COINS .. " coins and the Rookie skin", Config.Colors.Gold)
		end
		Data.push(player)
	end
	Activity.set(player, nil)
	Activity.toLobby(player)
	Net.event("Tutorial"):FireClient(player, "done")
	Net.event("BallAssigned"):FireClient(player, nil, { Context = "None" })
	Net.event("MatchEvent"):FireClient(player, "end", {})
	padBlocked[player] = true
	guide(player)
end

local function playHole(run: Run, index: number)
	local course = run.Course :: CourseBuilder.Course
	local hole = course.Holes[index]
	if not hole then
		finish(run, true)
		return
	end
	run.Hole = index
	run.Done = {}
	run.Strokes = 0
	setSign(hole, INSTRUCTIONS[index] or "")
	local player = run.Player
	local gotBox = false
	local ball = BallService.create(player, {
		Position = hole.Tee,
		Ghost = true,
		Cup = hole.Cup,
		OOBY = hole.FloorY - Config.Physics.OOBDepth,
		Loadout = Data.loadout(player),
		Context = {
			CanShoot = function()
				return not run.Ended and run.Hole == index
			end,
			OnRest = function(b)
				if b.Strokes >= 10 and not run.Ended and run.Hole == index then
					Net.event("Toast"):FireClient(player, "Let's keep going!", nil)
					playHole(run, index + 1)
				end
			end,
			OnSink = function(b)
				complete(run, { "sink" })
				Net.event("Toast"):FireClient(player, if b.Strokes <= hole.Par then "Nice! Sunk in " .. b.Strokes else "Sunk!", Config.Colors.Good)
				task.delay(1.6, function()
					if not run.Ended and run.Hole == index then
						playHole(run, index + 1)
					end
				end)
			end,
			OnOOB = function()
				Net.event("Toast"):FireClient(player, "Out of bounds! Your ball goes back to its last spot.", Config.Colors.Bad)
			end,
			Tick = function(b, _dt)
				if run.Hole == index and b.Strokes > run.Strokes then
					run.Strokes = b.Strokes
					complete(run, SHOT_STEPS)
				end
				if gotBox then
					return
				end
				for _, box in hole.ChaosBoxes do
					if (box.Position - b.Part.Position).Magnitude < 2.6 then
						gotBox = true
						box.Transparency = 1
						AbilityService.give(player, "Magnet")
						complete(run, { "box" })
						Net.event("Fx"):FireClient(player, "pickup", { Position = box.Position, Player = player })
						Net.event("Toast"):FireClient(player, "You got CUP MAGNET! Press 1 (or tap its button) before your next putt.", Config.Colors.Gold)
					end
				end
			end,
		},
	})
	Net.event("BallAssigned"):FireClient(player, ball.Part, {
		Context = "Tutorial",
		Hole = index,
		Holes = #course.Holes,
		Par = hole.Par,
		Cup = hole.Cup,
		TeeLook = hole.TeeLook,
		Overview = hole.Overview,
		PowerCycle = Config.Physics.PowerCycleSeconds,
	})
	Net.event("MatchEvent"):FireClient(player, "hole", { Hole = index, Holes = #course.Holes, Par = hole.Par, Map = "Tutorial", Overview = hole.Overview })
	pushSteps(run)
end

function Tutorial.begin(player: Player)
	if runs[player] or not Activity.isFree(player) or not Data.get(player) then
		return
	end
	local profile = Data.profile(player) :: Data.Profile
	local slot = 0
	while slots[slot] do
		slot += 1
	end
	slots[slot] = true
	invited[player] = nil
	local run: Run = {
		Player = player,
		Course = nil,
		Hole = 0,
		Slot = slot,
		Ended = false,
		FirstTime = not profile.TutorialDone,
		Done = {},
		Strokes = 0,
	}
	runs[player] = run
	Activity.set(player, "Tutorial")
	local ok, err = pcall(function()
		run.Course = CourseBuilder.buildTutorial(Vector3.new(-4000 - slot * 900, 0, 4000))
	end)
	if not ok or not run.Course then
		warn("[UltimateGolf] tutorial build failed:", err)
		finish(run, false)
		return
	end
	local course = run.Course :: CourseBuilder.Course
	Activity.park(player, course.Booth)
	AbilityService.set(player, {})
	AbilityService.bind(player, {
		Opponents = function()
			return {}
		end,
		OnUsed = function()
			complete(run, { "ability" })
		end,
	})
	Net.event("MatchEvent"):FireClient(player, "intro", {
		Mode = "Tutorial",
		ModeName = "TUTORIAL",
		Map = "Welcome to Ultimate Golf",
		Theme = "You are the ball. Skip anytime with the Skip button (or X).",
		Holes = #course.Holes,
		Players = { player.DisplayName },
		Overview = course.Holes[1].Overview,
	})
	task.delay(2.5, function()
		if not run.Ended then
			playHole(run, 1)
		end
	end)
end

function Tutorial.leave(player: Player): boolean
	local run = runs[player]
	if not run then
		return false
	end
	finish(run, false)
	return true
end

function Tutorial.start(l: LobbyTypes.Lobby)
	lobby = l
	Net.event("LeaveActivity").OnServerEvent:Connect(function(player)
		Tutorial.leave(player)
	end)
	Net.event("TutorialChoice").OnServerEvent:Connect(function(player, choice)
		if not invited[player] then
			return
		end
		invited[player] = nil
		if choice == "play" then
			Tutorial.begin(player)
			return
		end
		-- Skipped: don't ask again (the Practice room pad still replays it).
		local profile = Data.profile(player)
		if profile and not profile.TutorialDone then
			profile.TutorialDone = true
			Data.markDirty(player)
			Data.push(player)
		end
		guide(player)
	end)
	Net.event("ClaimDirectory").OnServerEvent:Connect(function(player)
		local profile = Data.profile(player)
		if profile and not profile.DirectoryDone then
			profile.DirectoryDone = true
			Data.markDirty(player)
			Data.push(player)
			Net.event("Guide"):FireClient(player, nil)
		end
	end)
	Data.Loaded:Connect(function(player: Player, session: Data.Session)
		task.spawn(function()
			local character = player.Character or player.CharacterAdded:Wait()
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(2)
			if player.Parent ~= Players then
				return
			end
			if not session.Profile.TutorialDone then
				-- New players land in the lobby and choose; nothing starts on its own.
				invited[player] = true
				Net.event("Tutorial"):FireClient(player, "invite", { Coins = REWARD_COINS })
			else
				guide(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local run = runs[player]
		if run then
			finish(run, false)
		end
		padBlocked[player] = nil
		invited[player] = nil
	end)
	-- Replay pad in the Practice room.
	task.spawn(function()
		while true do
			task.wait(0.3)
			local pad = lobby.South.TutorialPad
			for player in padBlocked do
				local root = Zones.rootOf(player)
				if not root or not Zones.onPad(pad, root.Position) then
					padBlocked[player] = nil
				end
			end
			for _, entry in Zones.freePlayers() do
				if not padBlocked[entry.Player] and Zones.onPad(pad, entry.Root.Position) then
					padBlocked[entry.Player] = true
					Tutorial.begin(entry.Player)
				end
			end
		end
	end)
end

return Tutorial

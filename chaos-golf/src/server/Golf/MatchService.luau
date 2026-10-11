--!strict
-- Runs matches: builds the voted course in its own arena slot, plays every
-- hole (simultaneous for Ranked / Race, turn-based for Classic), scores,
-- pays rewards, updates Ranked MMR and returns everyone to the lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Config = require(Shared:WaitForChild("Config"))
local Maps = require(Shared:WaitForChild("Maps"))
local Net = require(Shared:WaitForChild("Net"))
local Ranks = require(Shared:WaitForChild("Ranks"))

local Server = script.Parent.Parent
local CourseBuilder = require(Server:WaitForChild("World"):WaitForChild("CourseBuilder"))
local Activity = require(Server:WaitForChild("Services"):WaitForChild("Activity"))
local Data = require(Server:WaitForChild("Services"):WaitForChild("Data"))
local Economy = require(Server:WaitForChild("Services"):WaitForChild("Economy"))
local Social = require(Server:WaitForChild("Services"):WaitForChild("Social"))
local AbilityService = require(script.Parent:WaitForChild("AbilityService"))
local BallService = require(script.Parent:WaitForChild("BallService"))

local MatchService = {}

type PlayerState = {
	Player: Player,
	Name: string,
	UserId: number,
	HoleStrokes: { number },
	Points: number,
	Sabotages: number,
	Birdies: number,
	Aces: number,
	Finished: boolean,
	FinishOrder: number?,
	Left: boolean,
	StartMMR: number,
	Forfeited: boolean,
	Timeouts: number, -- consecutive turn timeouts (Classic)
}

type Match = {
	Id: number,
	Mode: Config.ModeDef,
	Map: Maps.MapDef,
	Slot: number,
	Course: CourseBuilder.Course?,
	Players: { PlayerState },
	ByPlayer: { [Player]: PlayerState },
	HoleIndex: number,
	Hole: CourseBuilder.Hole?,
	HoleCount: number,
	TurnPlayer: Player?,
	TurnDeadline: number,
	AwaitingRest: boolean,
	FinishCount: number,
	FinishWindowEnd: number?,
	HoleDeadline: number,
	Ended: boolean,
	Rng: Random,
	BoxCooldown: { [BasePart]: number },
}

local matches: { [number]: Match } = {}
local byPlayer: { [Player]: Match } = {}
local slotsUsed: { [number]: boolean } = {}
local nextId = 0

local function now(): number
	return os.clock()
end

local function allocSlot(): number
	local i = 0
	while slotsUsed[i] do
		i += 1
	end
	slotsUsed[i] = true
	return i
end

local function event(match: Match, kind: string, payload: any)
	for _, ps in match.Players do
		if not ps.Left and ps.Player.Parent == Players then
			Net.event("MatchEvent"):FireClient(ps.Player, kind, payload)
		end
	end
end

local function toastAll(match: Match, text: string, color: Color3?)
	for _, ps in match.Players do
		if not ps.Left then
			Net.event("Toast"):FireClient(ps.Player, text, color)
		end
	end
end

local function active(match: Match): { PlayerState }
	local out = {}
	for _, ps in match.Players do
		if not ps.Left and ps.Player.Parent == Players then
			table.insert(out, ps)
		end
	end
	return out
end

local function cap(match: Match): number
	local hole = match.Hole
	return (if hole then hole.Par else 3) + Config.Match.StrokeCapOverPar
end

local function matchBalls(match: Match): { BallService.Ball }
	local out = {}
	for _, ps in active(match) do
		local b = BallService.get(ps.Player)
		if b then
			table.insert(out, b)
		end
	end
	return out
end

local function allAtRest(match: Match): boolean
	for _, b in matchBalls(match) do
		if not b.AtRest and not b.Sunk then
			return false
		end
	end
	return true
end

local function totalStrokes(ps: PlayerState): number
	local t = 0
	for _, s in ps.HoleStrokes do
		t += s
	end
	return t
end

-- Turn order (Classic) ------------------------------------------------------

local function advanceTurn(match: Match)
	local list = active(match)
	local order = {}
	for _, ps in list do
		if not ps.Finished then
			table.insert(order, ps)
		end
	end
	if #order == 0 then
		match.TurnPlayer = nil
		return
	end
	local currentIndex = 0
	for i, ps in order do
		if ps.Player == match.TurnPlayer then
			currentIndex = i
		end
	end
	local nextPs = order[(currentIndex % #order) + 1]
	match.TurnPlayer = nextPs.Player
	match.TurnDeadline = now() + (match.Mode.TurnTime or 25)
	match.AwaitingRest = false
	event(match, "turn", { UserId = nextPs.UserId, Name = nextPs.Name, Deadline = match.Mode.TurnTime })
	BallService.refreshAll()
end

-- Finishing a hole ------------------------------------------------------------

local function finishPlayer(match: Match, ps: PlayerState, strokes: number, sunk: boolean)
	if ps.Finished then
		return
	end
	ps.Finished = true
	ps.HoleStrokes[match.HoleIndex] = strokes
	local hole = match.Hole :: CourseBuilder.Hole
	if sunk then
		match.FinishCount += 1
		ps.FinishOrder = match.FinishCount
		if strokes == 1 then
			ps.Aces += 1
			toastAll(match, "⛳ HOLE IN ONE by " .. ps.Name .. "!", Config.Colors.Gold)
			Net.event("Fx"):FireAllClients("announce", { Text = ps.Name .. " just hit a HOLE IN ONE!", Color = Config.Colors.Gold })
		elseif strokes < hole.Par then
			ps.Birdies += 1
			toastAll(match, ps.Name .. " sank it in " .. strokes .. " (under par!)", Config.Colors.Good)
		else
			toastAll(match, ps.Name .. " sank it in " .. strokes, nil)
		end
		if match.Mode.Id == "Race" then
			local pts = Config.Match.RacePoints[ps.FinishOrder :: number] or 0
			ps.Points += pts
			if match.FinishCount == 1 and match.Mode.FinishWindow then
				match.FinishWindowEnd = now() + match.Mode.FinishWindow
				event(match, "window", { Seconds = match.Mode.FinishWindow })
			end
		end
	end
	local player = ps.Player
	task.delay(if sunk then 0.6 else 0, function()
		BallService.destroy(player)
		if not match.Ended and player.Parent == Players then
			Net.event("BallAssigned"):FireClient(player, nil, { Spectate = true, Overview = hole.Overview })
		end
	end)
	if not match.Mode.Simultaneous and match.TurnPlayer == player then
		advanceTurn(match)
	end
end

local function makeContext(match: Match, ps: PlayerState): BallService.Context
	return {
		CanShoot = function(ball)
			if match.Ended or ps.Finished then
				return false
			end
			if match.Mode.Simultaneous then
				return true
			end
			return match.TurnPlayer == ball.Player and not match.AwaitingRest and allAtRest(match)
		end,
		OnShot = function(_ball)
			ps.Timeouts = 0
			if not match.Mode.Simultaneous then
				match.AwaitingRest = true
				BallService.refreshAll()
			end
		end,
		OnRest = function(ball)
			if ball.Strokes >= cap(match) and not ball.Sunk then
				Net.event("Toast"):FireClient(ps.Player, "Stroke limit reached", Config.Colors.Muted)
				finishPlayer(match, ps, cap(match), false)
			end
			if not match.Mode.Simultaneous then
				BallService.refreshAll()
			end
		end,
		OnSink = function(ball)
			finishPlayer(match, ps, ball.Strokes, true)
		end,
		OnKnockout = function(_victim, attacker)
			local aps = match.ByPlayer[attacker]
			if aps and not aps.Left then
				aps.Sabotages += 1
				Data.addStat(attacker, "Sabotages", 1)
				Data.addStat(attacker, "Knockouts", 1)
				toastAll(match, "💥 " .. aps.Name .. " knocked " .. ps.Name .. " out of bounds!", Config.Colors.Gold)
			end
		end,
		OnOOB = function(ball)
			Net.event("Toast"):FireClient(ps.Player, "Out of bounds! +1 stroke", Config.Colors.Bad)
			if ball.Strokes >= cap(match) then
				finishPlayer(match, ps, cap(match), false)
			end
		end,
		Tick = function(ball, _dt)
			local hole = match.Hole
			if not hole or not match.Mode.ChaosBoxes then
				return
			end
			local t = now()
			for _, box in hole.ChaosBoxes do
				local ready = (match.BoxCooldown[box] or 0) <= t
				if ready and (box.Position - ball.Part.Position).Magnitude < 2.6 then
					if AbilityService.give(ps.Player, Abilities.random(match.Rng)) then
						match.BoxCooldown[box] = t + 10
						box.Transparency = 1
						Net.event("Fx"):FireAllClients("pickup", { Position = box.Position, Player = ps.Player })
						task.delay(10, function()
							if box.Parent then
								box.Transparency = 0.15
							end
						end)
					end
				end
			end
		end,
	}
end

local function spawnBalls(match: Match, hole: CourseBuilder.Hole)
	local list = active(match)
	local look = hole.TeeLook
	local right = Vector3.new(-look.Z, 0, look.X)
	for i, ps in list do
		local pos = hole.Tee
		if match.Mode.BallCollide and #list > 1 then
			local col = (i - 1) % 4
			local row = math.floor((i - 1) / 4)
			local cols = math.min(#list - row * 4, 4)
			pos += right * ((col - (cols - 1) / 2) * 2.2) - look * (row * 2.4)
		end
		local profile = Data.profile(ps.Player)
		local upgrades = if match.Mode.Upgrades and profile then profile.Upgrades else { Power = 0, Control = 0, Bounce = 0 }
		local ball = BallService.create(ps.Player, {
			Position = pos,
			Context = makeContext(match, ps),
			Ghost = not match.Mode.BallCollide,
			Upgrades = upgrades,
			Cup = hole.Cup,
			OOBY = hole.FloorY - Config.Physics.OOBDepth,
			Loadout = Data.loadout(ps.Player),
		})
		Net.event("BallAssigned"):FireClient(ps.Player, ball.Part, {
			Context = "Match",
			Mode = match.Mode.Id,
			Hole = match.HoleIndex,
			Holes = match.HoleCount,
			Par = hole.Par,
			Cup = hole.Cup,
			TeeLook = hole.TeeLook,
			Overview = hole.Overview,
			PowerCycle = Config.Physics.PowerCycleSeconds * (1 + (upgrades.Control or 0) * 0.08),
		})
	end
end

local function scoreRows(match: Match): { any }
	local rows = {}
	for _, ps in match.Players do
		table.insert(rows, {
			Name = ps.Name,
			UserId = ps.UserId,
			Strokes = ps.HoleStrokes,
			Total = totalStrokes(ps),
			Points = ps.Points,
			Left = ps.Left,
		})
	end
	if match.Mode.Id == "Race" then
		table.sort(rows, function(a, b)
			if a.Left ~= b.Left then
				return not a.Left
			end
			if a.Points ~= b.Points then
				return a.Points > b.Points
			end
			return a.Total < b.Total
		end)
	else
		table.sort(rows, function(a, b)
			if a.Left ~= b.Left then
				return not a.Left
			end
			return a.Total < b.Total
		end)
	end
	return rows
end

local function playHole(match: Match, index: number)
	local course = match.Course :: CourseBuilder.Course
	local hole = course.Holes[index]
	match.HoleIndex = index
	match.Hole = hole
	match.FinishCount = 0
	match.FinishWindowEnd = nil
	match.TurnPlayer = nil
	match.AwaitingRest = false
	match.BoxCooldown = {}
	for _, box in hole.ChaosBoxes do
		box.Transparency = 0.15
	end
	for _, ps in match.Players do
		ps.Finished = ps.Left
		ps.FinishOrder = nil
	end

	event(match, "hole", { Hole = index, Holes = match.HoleCount, Par = hole.Par, Map = match.Map.Name, Overview = hole.Overview })
	spawnBalls(match, hole)
	match.HoleDeadline = now() + Config.Match.HoleTimeLimit
	if not match.Mode.Simultaneous then
		advanceTurn(match)
	end

	while not match.Ended do
		task.wait(0.1)
		local list = active(match)
		if #list == 0 then
			break
		end
		local unfinished = 0
		for _, ps in list do
			if not ps.Finished then
				unfinished += 1
			end
		end
		if unfinished == 0 then
			break
		end
		local t = now()
		if t > match.HoleDeadline or (match.FinishWindowEnd and t > match.FinishWindowEnd) then
			toastAll(match, "Time!", Config.Colors.Muted)
			break
		end
		if not match.Mode.Simultaneous then
			local turnPs = match.TurnPlayer and match.ByPlayer[match.TurnPlayer]
			if not turnPs or turnPs.Left or turnPs.Finished then
				advanceTurn(match)
			elseif match.AwaitingRest then
				if allAtRest(match) then
					advanceTurn(match)
				end
			elseif t > match.TurnDeadline then
				local ball = BallService.get(turnPs.Player)
				turnPs.Timeouts += 1
				if ball then
					ball.Strokes += 1
					BallService.refresh(ball)
					if turnPs.Timeouts >= 2 then
						Net.event("Toast"):FireClient(turnPs.Player, "Two missed turns: hole forfeited", Config.Colors.Bad)
						finishPlayer(match, turnPs, cap(match), false)
					else
						Net.event("Toast"):FireClient(turnPs.Player, "Turn timed out: +1 stroke", Config.Colors.Bad)
						if ball.Strokes >= cap(match) then
							finishPlayer(match, turnPs, cap(match), false)
						end
					end
				end
				if not turnPs.Finished then
					advanceTurn(match)
				end
			end
		end
		-- Ranked forfeit: the remaining player plays on alone only until the hole ends.
	end

	-- Anyone still playing is capped.
	for _, ps in match.Players do
		if not ps.Finished then
			ps.Finished = true
			ps.HoleStrokes[index] = cap(match)
		end
		BallService.destroy(ps.Player)
	end

	local pars = {}
	for i = 1, match.HoleCount do
		pars[i] = course.Holes[i].Par
	end
	event(match, "scorecard", { Hole = index, Holes = match.HoleCount, Par = hole.Par, Pars = pars, Rows = scoreRows(match), Mode = match.Mode.Id })
	task.wait(Config.Match.ScorecardSeconds)
end

-- Results -------------------------------------------------------------------

local function placements(match: Match): { [PlayerState]: number }
	local rows = {}
	for _, ps in match.Players do
		table.insert(rows, ps)
	end
	local race = match.Mode.Id == "Race"
	local function better(a: PlayerState, b: PlayerState): boolean
		if a.Left ~= b.Left then
			return not a.Left
		end
		if race and a.Points ~= b.Points then
			return a.Points > b.Points
		end
		return totalStrokes(a) < totalStrokes(b)
	end
	table.sort(rows, better)
	local out: { [PlayerState]: number } = {}
	for i, ps in rows do
		local place = i
		if i > 1 then
			local prev = rows[i - 1]
			if not better(prev, ps) and not better(ps, prev) then
				place = out[prev]
			end
		end
		out[ps] = place
	end
	return out
end

local function grantRankRewards(player: Player, mmr: number)
	for _, tier in Ranks.Tiers do
		if tier.Reward and mmr >= tier.Min then
			if Data.grantSkin(player, tier.Reward) then
				Net.event("Toast"):FireClient(player, "New rank skin unlocked: " .. tier.Name .. "!", tier.Color)
			end
		end
	end
end

local function applyRanked(match: Match, places: { [PlayerState]: number }): { [Player]: any }
	local out: { [Player]: any } = {}
	if #match.Players ~= 2 then
		return out
	end
	for i, ps in match.Players do
		local other = match.Players[3 - i]
		local profile = Data.profile(ps.Player)
		if ps.Left or not profile then
			continue -- leavers were already charged a loss in the release hook
		end
		local score = if places[ps] < places[other] then 1 elseif places[ps] > places[other] then 0 else 0.5
		if other.Left then
			score = 1
		end
		local old = profile.Ranked.MMR
		local delta = Ranks.delta(old, other.StartMMR, score, profile.Ranked.Played < Config.Ranked.PlacementMatches)
		profile.Ranked.MMR = math.max(0, old + delta)
		profile.Ranked.Played += 1
		profile.Ranked.Peak = math.max(profile.Ranked.Peak, profile.Ranked.MMR)
		if score == 1 then
			profile.Ranked.Wins += 1
		elseif score == 0 then
			profile.Ranked.Losses += 1
		else
			profile.Ranked.Draws += 1
		end
		Data.markDirty(ps.Player)
		local session = Data.get(ps.Player)
		if session then
			session.PublicDirty = true
		end
		grantRankRewards(ps.Player, profile.Ranked.MMR)
		Data.refreshLeaderstats(ps.Player)
		Social.updateNametag(ps.Player)
		out[ps.Player] = {
			Old = old,
			New = profile.Ranked.MMR,
			Delta = profile.Ranked.MMR - old,
			Label = Ranks.fromMMR(profile.Ranked.MMR).Label,
			OldLabel = Ranks.fromMMR(old).Label,
			Score = score,
		}
	end
	return out
end

local function finishMatch(match: Match)
	local places = placements(match)
	local rankedResults = if match.Mode.Ranked then applyRanked(match, places) else {}
	local rows = scoreRows(match)
	local count = #match.Players

	for _, ps in match.Players do
		if ps.Left or ps.Player.Parent ~= Players then
			continue
		end
		local player = ps.Player
		local place = places[ps]
		local holesPlayed = #ps.HoleStrokes
		local R = Config.Rewards
		local placementCoins = 0
		if match.Mode.Ranked then
			local rr = rankedResults[player]
			local score = rr and rr.Score or 0.5
			placementCoins = if score == 1 then R.Ranked.Win elseif score == 0 then R.Ranked.Loss else R.Ranked.Draw
		elseif match.Mode.Id == "Classic" then
			placementCoins = R.Classic[place] or R.Classic[#R.Classic]
		else
			placementCoins = R.Race[place] or R.Race[#R.Race]
		end
		if count == 1 then
			placementCoins = math.floor(placementCoins * 0.25) -- solo (Studio) runs pay a token amount
		end
		local sabotage = math.min(ps.Sabotages * R.SabotageHit, R.SabotageCap)
		local base = R.Participation + R.PerHole * holesPlayed + R.Birdie * ps.Birdies + R.HoleInOne * ps.Aces + placementCoins + sabotage
		local breakdown = Economy.awardMatch(player, base, "match")

		Data.addStat(player, "Matches", 1)
		Data.addStat(player, "Holes", holesPlayed)
		if place == 1 and count > 1 then
			Data.addStat(player, "Wins", 1)
		end
		if ps.Aces > 0 then
			Data.addStat(player, "HoleInOnes", ps.Aces)
			if Data.grantSkin(player, "ace") then
				Net.event("Toast"):FireClient(player, "Unlocked the ACE skin!", Config.Colors.Gold)
			end
		end
		Data.push(player)

		Net.event("MatchEvent"):FireClient(player, "results", {
			Mode = match.Mode.Id,
			Map = match.Map.Name,
			Placement = place,
			Players = count,
			Rows = rows,
			Coins = breakdown,
			Ranked = rankedResults[player],
			Birdies = ps.Birdies,
			Aces = ps.Aces,
			Sabotages = ps.Sabotages,
		})
	end
end

local function teardown(match: Match)
	match.Ended = true
	for _, ps in match.Players do
		local player = ps.Player
		BallService.destroy(player)
		AbilityService.clear(player)
		if byPlayer[player] == match then
			byPlayer[player] = nil
		end
		if player.Parent == Players and not ps.Left then
			Activity.set(player, nil)
			Activity.toLobby(player)
			Net.event("BallAssigned"):FireClient(player, nil, { Context = "None" })
			Net.event("MatchEvent"):FireClient(player, "end", {})
		end
	end
	if match.Course then
		(match.Course :: CourseBuilder.Course).Destroy()
	end
	slotsUsed[match.Slot] = nil
	matches[match.Id] = nil
end

local function run(match: Match)
	local origin = Vector3.new(4000 + match.Slot * 1100, 0, 4000)
	match.Course = CourseBuilder.build(match.Map, origin, { ChaosBoxes = match.Mode.ChaosBoxes })
	local course = match.Course :: CourseBuilder.Course
	match.HoleCount = math.min(match.Mode.Holes, #course.Holes)

	for i, ps in match.Players do
		local player = ps.Player
		Activity.park(player, course.Booth * CFrame.new((i - 1) % 4 * 2 - 3, 0, math.floor((i - 1) / 4) * 2))
		local start = match.Mode.StartAbilities
		if start then
			AbilityService.set(player, start)
		else
			local list = {}
			for _ = 1, match.Mode.StartRandomAbilities do
				table.insert(list, Abilities.random(match.Rng))
			end
			AbilityService.set(player, list)
		end
		AbilityService.bind(player, {
			Opponents = function(p: Player)
				local out = {}
				for _, b in matchBalls(match) do
					if b.Player ~= p then
						table.insert(out, b)
					end
				end
				return out
			end,
			CanUse = function(p: Player)
				if match.Mode.Simultaneous then
					return true
				end
				return match.TurnPlayer == p and not match.AwaitingRest
			end,
			OnUsed = function(_p: Player, _id: string, hits: number)
				if hits > 0 then
					ps.Sabotages += 1
					Data.addStat(player, "Sabotages", 1)
				end
			end,
		})
	end

	local names = {}
	for _, ps in match.Players do
		table.insert(names, ps.Name)
	end
	local theme = Maps.Themes[match.Map.Theme]
	event(match, "intro", {
		Mode = match.Mode.Id,
		ModeName = match.Mode.Display,
		Map = match.Map.Name,
		Theme = theme.Name,
		Holes = match.HoleCount,
		Players = names,
		Overview = course.Holes[1].Overview,
	})
	task.wait(Config.Match.IntroSeconds)

	for i = 1, match.HoleCount do
		if match.Ended then
			break
		end
		local remaining = #active(match)
		if remaining == 0 or (match.Mode.Ranked and remaining < 2 and #match.Players == 2) then
			break
		end
		playHole(match, i)
	end

	finishMatch(match)
	task.wait(Config.Match.ResultsSeconds)
	teardown(match)
end

-- Public API -----------------------------------------------------------------

function MatchService.inMatch(player: Player): boolean
	return byPlayer[player] ~= nil
end

function MatchService.count(): number
	local n = 0
	for _ in matches do
		n += 1
	end
	return n
end

-- Starts a match. `players` must all be free; returns false if it couldn't start.
function MatchService.launch(modeId: string, players: { Player }, mapId: string): boolean
	local mode = Config.Modes[modeId]
	local map = Maps.get(mapId)
	if not mode or not map then
		return false
	end
	local list = {}
	for _, p in players do
		if p.Parent == Players and Activity.isFree(p) and Data.get(p) then
			table.insert(list, p)
		end
	end
	if #list == 0 then
		return false
	end

	nextId += 1
	local match: Match = {
		Id = nextId,
		Mode = mode,
		Map = map,
		Slot = allocSlot(),
		Course = nil,
		Players = {},
		ByPlayer = {},
		HoleIndex = 0,
		Hole = nil,
		HoleCount = mode.Holes,
		TurnPlayer = nil,
		TurnDeadline = 0,
		AwaitingRest = false,
		FinishCount = 0,
		FinishWindowEnd = nil,
		HoleDeadline = 0,
		Ended = false,
		Rng = Random.new(),
		BoxCooldown = {},
	}
	for _, p in list do
		local ps: PlayerState = {
			Player = p,
			Name = p.DisplayName,
			UserId = p.UserId,
			HoleStrokes = {},
			Points = 0,
			Sabotages = 0,
			Birdies = 0,
			Aces = 0,
			Finished = false,
			FinishOrder = nil,
			Left = false,
			StartMMR = (Data.profile(p) :: Data.Profile).Ranked.MMR,
			Forfeited = false,
			Timeouts = 0,
		}
		table.insert(match.Players, ps)
		match.ByPlayer[p] = ps
		byPlayer[p] = match
		Activity.set(p, "Match")
	end
	matches[match.Id] = match

	task.spawn(function()
		local ok, err = pcall(function()
			run(match)
		end)
		if not ok then
			warn("[UltimateGolf] match", match.Id, "crashed:", err)
			if not match.Ended then
				teardown(match)
			end
		end
	end)
	return true
end

-- Ranked leavers take the loss. Called from both PlayerRemoving and the Data
-- release hook (whichever runs first); applied once.
local function forfeit(match: Match, ps: PlayerState, profile: Data.Profile?)
	if ps.Forfeited or not profile or not match.Mode.Ranked or match.Ended or #match.Players ~= 2 then
		return
	end
	ps.Forfeited = true
	local other = if match.Players[1] == ps then match.Players[2] else match.Players[1]
	local delta = Ranks.delta(profile.Ranked.MMR, other.StartMMR, 0, profile.Ranked.Played < Config.Ranked.PlacementMatches)
	profile.Ranked.MMR = math.max(0, profile.Ranked.MMR + delta)
	profile.Ranked.Played += 1
	profile.Ranked.Losses += 1
end

local function onLeave(player: Player, profile: Data.Profile?)
	local match = byPlayer[player]
	if not match then
		return
	end
	local ps = match.ByPlayer[player]
	if ps then
		forfeit(match, ps, profile or Data.profile(player))
	end
	if ps and not ps.Left then
		ps.Left = true
		ps.Finished = true
		BallService.destroy(player)
		toastAll(match, ps.Name .. " left the match", Config.Colors.Muted)
		if match.TurnPlayer == player then
			advanceTurn(match)
		end
	end
	byPlayer[player] = nil
end

function MatchService.start()
	Data.onRelease(function(session)
		onLeave(session.Player, session.Profile)
	end)
	Players.PlayerRemoving:Connect(function(player)
		onLeave(player, nil)
	end)
end

return MatchService

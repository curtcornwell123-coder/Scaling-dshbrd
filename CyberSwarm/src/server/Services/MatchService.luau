--!strict
--[[
	MatchService
	Owns match lifecycle. Every match is an isolated Match record with its own Maid, Random,
	players, arenas (map copies), timers, and one Heartbeat connection, so any number of matches
	can run side by side on one server.

	States: Waiting -> Countdown -> Preparing -> WaveActive -> WaveResult -> (Preparing | MatchEnd)

	Modes plug in through ModeConfig teams / teamSize:
		teams = 1   one arena for every player (Solo, Co-op)
		teams = 2+  one arena per team; the first team to destroy its HQ wins (1v1, 3v3)
	QueueService may pass the exact teams (balanced by Matchmaker); otherwise players are dealt
	round-robin. Test Realm matches pass a SandboxConfig: unlimited coins, a chosen start wave,
	preset mutations, and a time scale.

	Other services observe matches only through the signals below (quests, season XP, ranked
	results), so MatchService never depends on them.

	Gameplay callbacks only record what happened (dirty flags, pendingOutcome); phase transitions
	run at the end of the match tick or from the phase timer, never in the middle of a system update.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local WaveConfig = require(ReplicatedStorage.Shared.Config.WaveConfig)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local Notifier = require(script.Parent.Parent.Notifier)
local PlaceholderModels = require(script.Parent.Parent.World.PlaceholderModels)
local Effects = require(script.Parent.Parent.World.Effects)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local LobbyService = require(script.Parent.LobbyService)
local MutationService = require(script.Parent.MutationService)
local RobotService = require(script.Parent.RobotService)
local TowerService = require(script.Parent.TowerService)
local EconomyService = require(script.Parent.EconomyService)
local WaveService = require(script.Parent.WaveService)

type Match = ServerTypes.Match
type Arena = ServerTypes.Arena
type MatchPlayer = ServerTypes.MatchPlayer

local ErrorCode = Constants.ErrorCode

export type StartOptions = {
	-- Players per team, in team order. Omit to deal players round-robin.
	teams: { { Player } }?,
	sandbox: Types.SandboxConfig?,
}

local MatchService = {}

MatchService.matchStarted = Signal.new() :: Signal.Signal<Match>
-- Fired once per match when a result exists (not on a cancelled or abandoned-by-all match).
MatchService.matchEnded = Signal.new() :: Signal.Signal<Match, ServerTypes.Outcome>
MatchService.matchClosed = Signal.new() :: Signal.Signal<Match>
-- A player left (disconnect, kick) before the match ended.
MatchService.playerAbandoned = Signal.new() :: Signal.Signal<Match, MatchPlayer>
MatchService.waveCleared = Signal.new() :: Signal.Signal<Match, number>
MatchService.robotQueued = Signal.new() :: Signal.Signal<Match, MatchPlayer>

local matches: { [number]: Match } = {}
local playerMatches: { [Player]: Match } = {}
local nextMatchId = 0

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Forward declarations: the state machine functions reference each other.
local onStateTimeout: (match: Match, token: number) -> ()
local closeMatch: (match: Match) -> ()

local function enterState(match: Match, state: Types.MatchState, duration: number?)
	match.state = state
	match.stateToken += 1
	match.dirty = true
	if duration ~= nil then
		match.stateEndsAt = serverNow() + duration
		match.maid:set("stateTimer", task.delay(duration, onStateTimeout, match, match.stateToken))
	else
		match.stateEndsAt = 0
		match.maid:clear("stateTimer")
	end
end

local function activeArenas(match: Match): { Arena }
	local list = {}
	for _, arena in match.arenas do
		if not arena.eliminated then
			table.insert(list, arena)
		end
	end
	return list
end

local function connectedPlayers(match: Match): { Player }
	local list = {}
	for player, matchPlayer in match.players do
		if matchPlayer.connected then
			table.insert(list, player)
		end
	end
	return list
end

-- Puts a player's character on their arena's observation deck and freezes it there.
local function placeInArena(match: Match, matchPlayer: MatchPlayer)
	if match.closed or not matchPlayer.connected then
		return
	end
	local arena = matchPlayer.arena
	local spawns = arena.map.playerSpawns
	local index = table.find(arena.players, matchPlayer) or 1
	local spawnCFrame = spawns[((index - 1) % #spawns) + 1]
	LobbyService.teleport(matchPlayer.player, spawnCFrame + Vector3.new(0, Constants.World.PLAYER_SPAWN_LIFT, 0))
	-- Test Realm players stay free to walk the deck (the RETURN pad is there).
	LobbyService.setMovementLocked(matchPlayer.player, match.sandbox == nil)
end

local function createMatchPlayer(match: Match, player: Player, arena: Arena): MatchPlayer
	-- The loadout is snapshotted at match start; editing it in the lobby later cannot affect this match.
	local loadout: { string } = {}
	local data = DataService.getData(player)
	local sandbox = match.sandbox
	local source: { string }? = if sandbox ~= nil
		then sandbox.loadout
		elseif data ~= nil then data.equippedLoadout
		else nil
	if source ~= nil then
		for _, robotId in source do
			local robot = RobotConfig.Robots[robotId]
			if
				robot ~= nil
				and not robot.locked
				and not table.find(loadout, robotId)
				and #loadout < Constants.MAX_LOADOUT
			then
				table.insert(loadout, robotId)
			end
		end
	end
	if #loadout == 0 then
		loadout = table.clone(RobotConfig.DefaultUnlocked)
	end
	return {
		player = player,
		userId = player.UserId,
		arena = arena,
		coins = WaveConfig.startingCoins,
		loadout = loadout,
		upgrades = {},
		queued = {},
		queuedThisWave = 0,
		sentThisWave = 0,
		connected = true,
		unlimitedCoins = sandbox ~= nil,
		team = arena.index,
	}
end

local function onRobotReachedBase(match: Match, arena: Arena, robot: ServerTypes.RobotUnit)
	if arena.baseHealth <= 0 then
		return
	end
	local dealt = math.min(arena.baseHealth, robot.damage)
	arena.baseHealth -= dealt
	arena.baseBarFill.Size = UDim2.fromScale(math.clamp(arena.baseHealth / arena.baseMaxHealth, 0, 1), 1)
	Effects.send(arena.viewers, "Explosion", robot.position, robot.position, Theme.Military.AlertRed, 5)
	if robot.owner.connected then
		EconomyService.rewardArrival(robot.owner, dealt)
	end
	match.dirty = true
	if arena.baseHealth <= 0 and match.pendingOutcome == nil then
		match.pendingOutcome = { winner = arena, reason = "BaseDestroyed" }
	end
end

local function buildArena(match: Match, index: number, map: ServerTypes.LoadedMap, group: { Player }): Arena
	local maid = Maid.new()
	match.maid:give(maid)
	maid:give(function()
		MapService.unload(map)
	end)

	local hq = PlaceholderModels.commandHQ(map.baseCFrame)
	hq.model.Parent = map.model

	local mapDef = MapConfig.Maps[map.mapId]
	local baseMaxHealth =
		math.floor(mapDef.baseHealth * (1 + match.mode.baseHealthPerExtraPlayer * math.max(0, #group - 1)))

	local spawnQueues: { { ServerTypes.QueuedRobot } } = {}
	local spawnHeads: { number } = {}
	local nextSpawnAt: { number } = {}
	for laneIndex = 1, #map.lanes do
		spawnQueues[laneIndex] = {}
		spawnHeads[laneIndex] = 1
		nextSpawnAt[laneIndex] = 0
	end

	local arena: Arena = {
		index = index,
		maid = maid,
		players = {},
		viewers = {},
		map = map,
		robots = {},
		towers = {},
		mutations = MutationService.newState(),
		towerStats = {},
		magnetActive = false,
		baseModel = hq.model,
		baseBarFill = hq.barFill,
		baseHealth = baseMaxHealth,
		baseMaxHealth = baseMaxHealth,
		spawnQueues = spawnQueues,
		spawnHeads = spawnHeads,
		nextSpawnAt = nextSpawnAt,
		nextUid = 0,
		eliminated = false,
		nextBarFlushAt = 0,
		clock = match.clock,
		robotReachedBase = Signal.new(),
		robotRemoved = Signal.new(),
		towerHitRequested = Signal.new(),
	}
	maid:give(arena.robotReachedBase)
	maid:give(arena.robotRemoved)
	maid:give(arena.towerHitRequested)

	TowerService.refreshStats(arena)
	TowerService.attach(arena)
	maid:give(arena.robotReachedBase:connect(function(robot: ServerTypes.RobotUnit)
		onRobotReachedBase(match, arena, robot)
	end))

	for _, player in group do
		local matchPlayer = createMatchPlayer(match, player, arena)
		table.insert(arena.players, matchPlayer)
		table.insert(arena.viewers, player)
		match.players[player] = matchPlayer
	end
	return arena
end

local function rivalName(arena: Arena): string
	local first = arena.players[1]
	if first == nil then
		return "Rival"
	end
	if #arena.players > 1 then
		return `{first.player.DisplayName} +{#arena.players - 1}`
	end
	return first.player.DisplayName
end

local function snapshotFor(match: Match, matchPlayer: MatchPlayer): Types.MatchSnapshot
	local arena = matchPlayer.arena
	local loadout: { Types.RobotSlotInfo } = {}
	for _, robotId in matchPlayer.loadout do
		local robot = RobotConfig.Robots[robotId]
		local level = matchPlayer.upgrades[robotId] or 0
		table.insert(loadout, {
			robotId = robotId,
			cost = robot.cost,
			queued = matchPlayer.queued[robotId] or 0,
			level = level,
			upgradeCost = robot.upgradeCosts[level + 1],
		})
	end

	local rivals: { Types.RivalInfo } = {}
	for _, other in match.arenas do
		if other ~= arena then
			table.insert(rivals, {
				name = rivalName(other),
				baseHealth = math.ceil(other.baseHealth),
				baseMaxHealth = other.baseMaxHealth,
			})
		end
	end

	return {
		matchId = match.id,
		modeId = match.mode.id,
		mapId = match.mapId,
		state = match.state,
		stateEndsAt = match.stateEndsAt,
		wave = match.waveNumber,
		maxWaves = match.mode.maxWaves,
		coins = matchPlayer.coins,
		baseHealth = math.ceil(arena.baseHealth),
		baseMaxHealth = arena.baseMaxHealth,
		laneCount = #arena.map.lanes,
		waveCap = WaveService.robotCap(match),
		queuedThisWave = matchPlayer.queuedThisWave,
		loadout = loadout,
		activeMutations = MutationService.activeList(arena.mutations),
		nextMutation = MutationService.pendingInfo(arena.mutations),
		rivals = rivals,
		cameraCFrame = arena.map.cameraCFrame,
		result = match.results[matchPlayer.player],
	}
end

local function sync(match: Match, now: number)
	match.dirty = false
	match.nextSyncAt = now + Constants.Match.STATE_SYNC_INTERVAL
	for player, matchPlayer in match.players do
		if matchPlayer.connected then
			Remotes.MatchUpdated:fireClient(player, snapshotFor(match, matchPlayer))
		end
	end
end

local function beginPreparing(match: Match)
	match.waveNumber += 1
	WaveService.beginPreparing(match)
	local catchUp = match.waveNumber == match.firstWave and match.firstWave > 1
	for _, arena in activeArenas(match) do
		if catchUp then
			-- Test Realm starting past wave 1: deploy the defense earlier waves would have built.
			for earlier = 1, match.waveNumber - 1 do
				TowerService.prepareWave(arena, earlier)
			end
		end
		local deployed = TowerService.prepareWave(arena, match.waveNumber)
		local text = if #deployed > 0
			then "Enemy deployed: " .. table.concat(deployed, ", ")
			else "Queue your swarm before the timer runs out."
		Notifier.banner(arena.viewers, "Info", `WAVE {match.waveNumber}`, text)
	end
	enterState(match, "Preparing", WaveConfig.preparingDuration)
end

local function beginWave(match: Match)
	local now = match.clock
	for _, arena in activeArenas(match) do
		local applied = MutationService.applyPending(arena.mutations)
		if applied ~= nil then
			TowerService.refreshStats(arena)
			Notifier.banner(
				arena.viewers,
				"Mutation",
				"MUTATION ACTIVE: " .. string.upper(applied.displayName),
				applied.description
			)
		else
			Notifier.toast(arena.viewers, "Info", "Swarm released!")
		end
		WaveService.beginWave(arena, now)
	end
	enterState(match, "WaveActive", WaveConfig.maxWaveDuration)
end

local WINNER_REASON: { [Types.MatchEndReason]: Types.MatchEndReason } = {
	BaseDestroyed = "BaseDestroyed",
	OutOfCoins = "RivalOutOfCoins",
	RivalLeft = "RivalLeft",
}

local LOSER_REASON: { [Types.MatchEndReason]: Types.MatchEndReason } = {
	BaseDestroyed = "RivalDestroyedBase",
}

local function endMatch(match: Match, outcome: ServerTypes.Outcome)
	if match.state == "MatchEnd" or match.closed then
		return
	end
	for player, matchPlayer in match.players do
		if matchPlayer.connected then
			local won = outcome.winner ~= nil and matchPlayer.arena == outcome.winner
			local reason: Types.MatchEndReason = outcome.reason
			local mapped: Types.MatchEndReason? = nil
			if won then
				mapped = WINNER_REASON[outcome.reason]
			else
				mapped = LOSER_REASON[outcome.reason]
			end
			if mapped ~= nil then
				reason = mapped
			end
			local coins = if match.sandbox ~= nil
				then 0
				else EconomyService.payoutMatch(player, match.mode, won, match.wavesCompleted)
			match.results[player] = {
				won = won,
				reason = reason,
				wavesCompleted = match.wavesCompleted,
				coinsAwarded = coins,
			}
			Notifier.banner(
				{ player },
				if won then "Success" else "Error",
				if won then "VICTORY" else "DEFEAT",
				Constants.MatchEndText[reason]
			)
		end
	end
	enterState(match, "MatchEnd", WaveConfig.matchEndDuration)
	MatchService.matchEnded:fire(match, outcome)
end

local function finishWave(match: Match)
	if match.state ~= "WaveActive" then
		return
	end
	for _, arena in match.arenas do
		RobotService.clearAll(arena)
		WaveService.clearQueues(arena)
	end
	match.wavesCompleted = match.waveNumber
	MatchService.waveCleared:fire(match, match.waveNumber)

	for _, matchPlayer in match.players do
		if matchPlayer.connected then
			local bonus = EconomyService.rewardWaveCompletion(matchPlayer, match.waveNumber)
			if bonus > 0 then
				Notifier.toast({ matchPlayer.player }, "Success", `Wave {match.waveNumber} cleared! +{bonus} coins`)
			end
		end
	end

	-- An arena whose players can no longer afford any robot is out of the fight.
	for _, arena in activeArenas(match) do
		local canContinue = false
		for _, matchPlayer in arena.players do
			if matchPlayer.connected and EconomyService.canAffordAnyRobot(matchPlayer) then
				canContinue = true
				break
			end
		end
		if not canContinue then
			arena.eliminated = true
		end
	end

	local remaining = activeArenas(match)
	if #remaining == 0 then
		endMatch(match, { winner = nil, reason = "OutOfCoins" })
		return
	end
	if #match.arenas > 1 and #remaining == 1 then
		endMatch(match, { winner = remaining[1], reason = "OutOfCoins" })
		return
	end
	if match.waveNumber >= match.mode.maxWaves then
		endMatch(match, { winner = nil, reason = "WaveLimit" })
		return
	end

	for _, arena in remaining do
		local rolled = MutationService.rollPending(arena.mutations, match.rng)
		if rolled ~= nil then
			Notifier.banner(
				arena.viewers,
				"Mutation",
				"INCOMING: " .. string.upper(rolled.displayName),
				rolled.description
			)
		end
	end
	enterState(match, "WaveResult", WaveConfig.waveResultDuration)
end

local function allArenasResolved(match: Match): boolean
	for _, arena in match.arenas do
		if not arena.eliminated and not WaveService.isArenaResolved(arena) then
			return false
		end
	end
	return true
end

local function tick(match: Match, realDt: number)
	if match.closed then
		return
	end
	-- Systems run on the match clock so the Test Realm speed setting scales all of combat.
	local dt = realDt * match.timeScale
	match.clock += dt
	local now = match.clock
	for _, arena in match.arenas do
		arena.clock = now
	end

	if match.state == "WaveActive" then
		for _, arena in match.arenas do
			if not arena.eliminated then
				WaveService.step(arena, now)
				RobotService.step(arena, dt, now)
				TowerService.step(arena, dt, now)
				RobotService.compact(arena)
			end
		end
	end

	for _, arena in match.arenas do
		if now >= arena.nextBarFlushAt then
			arena.nextBarFlushAt = now + Constants.Match.HEALTH_BAR_FLUSH_INTERVAL
			RobotService.flushBars(arena)
			TowerService.flushBars(arena)
		end
	end

	local outcome = match.pendingOutcome
	if outcome ~= nil then
		match.pendingOutcome = nil
		endMatch(match, outcome)
	elseif match.state == "WaveActive" and allArenasResolved(match) then
		finishWave(match)
	end

	if match.dirty and now >= match.nextSyncAt then
		sync(match, now)
	end
end

onStateTimeout = function(match: Match, token: number)
	if match.closed or match.stateToken ~= token then
		return
	end
	local state = match.state
	if state == "Waiting" then
		enterState(match, "Countdown", WaveConfig.countdownDuration)
		Notifier.banner(connectedPlayers(match), "Info", "GET READY", "The defense is digging in...")
	elseif state == "Countdown" or state == "WaveResult" then
		beginPreparing(match)
	elseif state == "Preparing" then
		beginWave(match)
	elseif state == "WaveActive" then
		finishWave(match)
	elseif state == "MatchEnd" then
		closeMatch(match)
	end
end

closeMatch = function(match: Match)
	if match.closed then
		return
	end
	match.closed = true
	matches[match.id] = nil
	MatchService.matchClosed:fire(match)
	for player, matchPlayer in match.players do
		if playerMatches[player] == match then
			playerMatches[player] = nil
		end
		if matchPlayer.connected and player.Parent ~= nil then
			-- Test Realm players stay in the yard; TestRealmService restarts or returns them.
			if match.sandbox == nil then
				LobbyService.returnToLobby(player)
			end
			Remotes.MatchClosed:fireClient(player, true)
		end
	end
	-- Destroys the Heartbeat connection, timers, signals, every map copy, and all units.
	match.maid:destroy()
end

local function removePlayer(match: Match, player: Player)
	local matchPlayer = match.players[player]
	if matchPlayer == nil then
		return
	end
	matchPlayer.connected = false
	match.players[player] = nil
	playerMatches[player] = nil
	if match.state ~= "MatchEnd" and not match.closed then
		MatchService.playerAbandoned:fire(match, matchPlayer)
	end

	local arena = matchPlayer.arena
	local playerIndex = table.find(arena.players, matchPlayer)
	if playerIndex ~= nil then
		table.remove(arena.players, playerIndex)
	end
	local viewerIndex = table.find(arena.viewers, player)
	if viewerIndex ~= nil then
		table.remove(arena.viewers, viewerIndex)
	end

	if next(match.players) == nil then
		closeMatch(match)
		return
	end

	if #arena.players == 0 and not arena.eliminated then
		arena.eliminated = true
		RobotService.clearAll(arena)
		WaveService.clearQueues(arena)
		local remaining = activeArenas(match)
		if match.state ~= "MatchEnd" and #match.arenas > 1 and #remaining == 1 then
			match.pendingOutcome = { winner = remaining[1], reason = "RivalLeft" }
		end
	end
	match.dirty = true
end

function MatchService.isInMatch(player: Player): boolean
	return playerMatches[player] ~= nil
end

function MatchService.getMatch(player: Player): (Match?, MatchPlayer?)
	local match = playerMatches[player]
	if match == nil then
		return nil, nil
	end
	return match, match.players[player]
end

local function canJoin(player: Player): boolean
	return player.Parent ~= nil and DataService.isLoaded(player) and playerMatches[player] == nil
end

-- Splits players into the mode's teams. Returns nil when the teams cannot be filled.
local function buildGroups(mode: Types.ModeDef, candidates: { Player }, options: StartOptions?): { { Player } }?
	local requested = if options ~= nil then options.teams else nil
	if requested ~= nil then
		local groups: { { Player } } = {}
		local total = 0
		for _, team in requested do
			local group: { Player } = {}
			for _, player in team do
				if canJoin(player) then
					table.insert(group, player)
				end
			end
			-- Team modes need full teams; anyone missing means the match cannot start fairly.
			if mode.teams > 1 and #group ~= mode.teamSize then
				return nil
			end
			total += #group
			table.insert(groups, group)
		end
		if #groups ~= mode.teams or total < mode.minPlayers or total > mode.maxPlayers then
			return nil
		end
		return groups
	end

	local players: { Player } = {}
	for _, player in candidates do
		if canJoin(player) then
			table.insert(players, player)
		end
	end
	if #players < mode.minPlayers then
		return nil
	end
	while #players > mode.maxPlayers do
		table.remove(players)
	end
	local groups: { { Player } } = {}
	for team = 1, mode.teams do
		groups[team] = {}
	end
	for index, player in players do
		table.insert(groups[((index - 1) % mode.teams) + 1], player)
	end
	return groups
end

-- Creates and starts a match. Returns false and an error code when it cannot start; nothing is
-- changed for any player in that case (the caller returns them to the lobby with no penalty).
function MatchService.startMatch(
	modeId: string,
	candidates: { Player },
	options: StartOptions?
): (boolean, string?, Match?)
	local mode = ModeConfig.Modes[modeId]
	if mode == nil then
		return false, ErrorCode.InvalidMode, nil
	end

	local groups = buildGroups(mode, candidates, options)
	if groups == nil then
		return false, ErrorCode.MatchFailed, nil
	end

	local rng = Random.new()
	local available: { string } = {}
	for _, mapId in mode.mapPool do
		if MapService.isAvailable(mapId) then
			table.insert(available, mapId)
		end
	end
	if #available == 0 then
		return false, ErrorCode.NoMapAvailable, nil
	end
	local mapId = available[rng:NextInteger(1, #available)]

	local maps: { ServerTypes.LoadedMap } = {}
	for _ in groups do
		local map = MapService.load(mapId)
		if map == nil then
			for _, loaded in maps do
				MapService.unload(loaded)
			end
			return false, ErrorCode.MatchFailed, nil
		end
		table.insert(maps, map)
	end

	nextMatchId += 1
	local sandbox = if options ~= nil then options.sandbox else nil
	local match: Match = {
		id = nextMatchId,
		mode = mode,
		mapId = mapId,
		state = "Waiting",
		stateEndsAt = 0,
		stateToken = 0,
		waveNumber = 0,
		wavesCompleted = 0,
		maid = Maid.new(),
		arenas = {},
		players = {},
		rng = rng,
		dirty = true,
		nextSyncAt = 0,
		pendingOutcome = nil,
		results = {},
		closed = false,
		key = `{game.JobId}:{nextMatchId}`,
		clock = 0,
		timeScale = if sandbox ~= nil then sandbox.speed else 1,
		sandbox = sandbox,
		firstWave = if sandbox ~= nil then sandbox.wave else 1,
	}
	if sandbox ~= nil then
		match.waveNumber = sandbox.wave - 1
	end
	for index, group in groups do
		table.insert(match.arenas, buildArena(match, index, maps[index], group))
	end
	if sandbox ~= nil then
		for _, arena in match.arenas do
			for mutationId, stacks in sandbox.mutations do
				for _ = 1, stacks do
					MutationService.force(arena.mutations, mutationId)
				end
			end
			TowerService.refreshStats(arena)
		end
	end

	matches[match.id] = match
	for player, matchPlayer in match.players do
		playerMatches[player] = match
		match.maid:give(player.CharacterAdded:Connect(function()
			-- Deferred so the new character has its root part before we move it.
			task.defer(placeInArena, match, matchPlayer)
		end))
		placeInArena(match, matchPlayer)
	end

	match.maid:give(RunService.Heartbeat:Connect(function(dt: number)
		tick(match, dt)
	end))

	local mapName = MapConfig.Maps[mapId].displayName
	Notifier.banner(
		connectedPlayers(match),
		"Info",
		string.upper(mode.displayName) .. " - " .. string.upper(mapName),
		"Break through the defense and destroy the Command HQ!"
	)
	enterState(match, "Waiting", Constants.Match.WAITING_DURATION)
	MatchService.matchStarted:fire(match)
	return true, nil, match
end

-- Ends a match early with no result (Test Realm reset). Nothing is paid or rated.
function MatchService.cancel(match: Match)
	closeMatch(match)
end

function MatchService.playersOf(match: Match): { MatchPlayer }
	local list: { MatchPlayer } = {}
	for _, matchPlayer in match.players do
		table.insert(list, matchPlayer)
	end
	return list
end

-- QA: jumps the match to the next phase.
function MatchService.skipPhase(match: Match)
	local state = match.state
	if state == "Waiting" or state == "Countdown" or state == "WaveResult" then
		beginPreparing(match)
	elseif state == "Preparing" then
		beginWave(match)
	elseif state == "WaveActive" then
		finishWave(match)
	end
end

-- QA: applies a mutation to the player's arena right now.
function MatchService.forceMutation(match: Match, matchPlayer: MatchPlayer, mutationId: string): boolean
	local arena = matchPlayer.arena
	local mutation = MutationService.force(arena.mutations, mutationId)
	if mutation == nil then
		return false
	end
	TowerService.refreshStats(arena)
	Notifier.banner(
		arena.viewers,
		"Mutation",
		"MUTATION ACTIVE: " .. string.upper(mutation.displayName),
		mutation.description
	)
	match.dirty = true
	return true
end

function MatchService.addCoins(match: Match, matchPlayer: MatchPlayer, amount: number)
	EconomyService.grant(matchPlayer, amount)
	match.dirty = true
end

local function withMatchPlayer(player: Player, action: (Match, MatchPlayer) -> string?)
	local match, matchPlayer = MatchService.getMatch(player)
	if match == nil or matchPlayer == nil then
		Notifier.error(player, ErrorCode.NotInMatch)
		return
	end
	local errorCode = action(match, matchPlayer)
	if errorCode ~= nil then
		Notifier.error(player, errorCode)
	end
end

function MatchService.start()
	Remotes.RequestSpawnRobot:connect(function(player: Player, robotId: unknown, laneIndex: unknown)
		withMatchPlayer(player, function(match, matchPlayer)
			local errorCode = WaveService.requestSpawn(match, matchPlayer, robotId, laneIndex)
			if errorCode == nil then
				MatchService.robotQueued:fire(match, matchPlayer)
			end
			return errorCode
		end)
	end)

	Remotes.RequestUpgradeRobot:connect(function(player: Player, robotId: unknown)
		withMatchPlayer(player, function(match, matchPlayer)
			return WaveService.requestUpgrade(match, matchPlayer, robotId)
		end)
	end)

	Remotes.RequestSync:connect(function(player: Player)
		local match, matchPlayer = MatchService.getMatch(player)
		if match ~= nil and matchPlayer ~= nil then
			Remotes.MatchUpdated:fireClient(player, snapshotFor(match, matchPlayer))
		end
	end)

	-- A leaving player is removed before their final save, so an abandon (a ranked loss) is
	-- part of the data that gets saved. PlayerRemoving covers players whose data never loaded.
	local function onLeaving(player: Player)
		local match = playerMatches[player]
		if match ~= nil then
			removePlayer(match, player)
		end
	end
	DataService.beforeRelease:connect(onLeaving)
	Players.PlayerRemoving:Connect(onLeaving)
end

return MatchService

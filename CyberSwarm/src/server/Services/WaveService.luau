--!strict
--[[
	WaveService
	The player's side of a wave: validating robot purchases and upgrades, queueing robots per lane
	during Preparing, and releasing them down their lanes with WaveConfig.spawnSpacing between them
	once the wave starts. Every request is validated here against server state; nothing the
	client sends is trusted beyond "which robot" and "which lane".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local WaveConfig = require(ReplicatedStorage.Shared.Config.WaveConfig)
local WaveMath = require(ReplicatedStorage.Shared.Logic.WaveMath)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local RobotService = require(script.Parent.RobotService)
local EconomyService = require(script.Parent.EconomyService)

type Arena = ServerTypes.Arena
type Match = ServerTypes.Match
type MatchPlayer = ServerTypes.MatchPlayer

local ErrorCode = Constants.ErrorCode

local WaveService = {}

function WaveService.robotCap(match: Match): number
	return WaveMath.robotCap(match.waveNumber, WaveConfig.RobotCap)
end

-- Shared validation for anything that names a robot from the player's loadout.
local function resolveLoadoutRobot(matchPlayer: MatchPlayer, robotIdRaw: unknown): (string?, string?)
	if type(robotIdRaw) ~= "string" then
		return nil, ErrorCode.InvalidRobot
	end
	local robotId = robotIdRaw :: string
	local robot = RobotConfig.Robots[robotId]
	if robot == nil or robot.locked then
		return nil, ErrorCode.InvalidRobot
	end
	if not table.find(matchPlayer.loadout, robotId) then
		return nil, ErrorCode.NotEquipped
	end
	return robotId, nil
end

-- Returns nil on success, or an error code.
function WaveService.requestSpawn(match: Match, matchPlayer: MatchPlayer, robotIdRaw: unknown, laneRaw: unknown): string?
	if match.state ~= "Preparing" or matchPlayer.arena.eliminated then
		return ErrorCode.WrongPhase
	end
	local robotId, robotError = resolveLoadoutRobot(matchPlayer, robotIdRaw)
	if robotId == nil then
		return robotError
	end
	local arena = matchPlayer.arena
	if type(laneRaw) ~= "number" then
		return ErrorCode.InvalidLane
	end
	local laneIndex = laneRaw :: number
	if laneIndex ~= laneIndex or laneIndex % 1 ~= 0 or laneIndex < 1 or laneIndex > #arena.map.lanes then
		return ErrorCode.InvalidLane
	end
	if matchPlayer.queuedThisWave >= WaveService.robotCap(match) then
		return ErrorCode.WaveFull
	end
	local robot = RobotConfig.Robots[robotId]
	if not EconomyService.trySpend(matchPlayer, robot.cost) then
		return ErrorCode.NotEnoughCoins
	end

	table.insert(arena.spawnQueues[laneIndex], {
		robotId = robotId,
		owner = matchPlayer,
		laneIndex = laneIndex,
	})
	matchPlayer.queued[robotId] = (matchPlayer.queued[robotId] or 0) + 1
	matchPlayer.queuedThisWave += 1
	match.dirty = true
	return nil
end

-- Upgrades apply to robots released after the purchase. Returns nil on success, or an error code.
function WaveService.requestUpgrade(match: Match, matchPlayer: MatchPlayer, robotIdRaw: unknown): string?
	if match.state == "MatchEnd" or match.state == "Waiting" then
		return ErrorCode.WrongPhase
	end
	local robotId, robotError = resolveLoadoutRobot(matchPlayer, robotIdRaw)
	if robotId == nil then
		return robotError
	end
	local robot = RobotConfig.Robots[robotId]
	local level = matchPlayer.upgrades[robotId] or 0
	local cost = robot.upgradeCosts[level + 1]
	if cost == nil then
		return ErrorCode.MaxLevel
	end
	if not EconomyService.trySpend(matchPlayer, cost) then
		return ErrorCode.NotEnoughCoins
	end
	matchPlayer.upgrades[robotId] = level + 1
	match.dirty = true
	return nil
end

function WaveService.clearQueues(arena: Arena)
	for laneIndex, queue in arena.spawnQueues do
		table.clear(queue)
		arena.spawnHeads[laneIndex] = 1
	end
end

-- Resets per-wave purchase counters before a new Preparing phase.
function WaveService.beginPreparing(match: Match)
	for _, matchPlayer in match.players do
		matchPlayer.queuedThisWave = 0
		matchPlayer.sentThisWave = 0
		table.clear(matchPlayer.queued)
	end
	for _, arena in match.arenas do
		WaveService.clearQueues(arena)
	end
end

function WaveService.beginWave(arena: Arena, now: number)
	for laneIndex in arena.spawnQueues do
		arena.nextSpawnAt[laneIndex] = now
	end
end

-- Releases at most one robot per lane per spacing interval.
function WaveService.step(arena: Arena, now: number)
	for laneIndex, queue in arena.spawnQueues do
		local head = arena.spawnHeads[laneIndex]
		if head <= #queue and now >= arena.nextSpawnAt[laneIndex] then
			local entry = queue[head]
			arena.spawnHeads[laneIndex] = head + 1
			arena.nextSpawnAt[laneIndex] = now + WaveConfig.spawnSpacing
			local def = RobotConfig.Robots[entry.robotId]
			if def ~= nil then
				local level = entry.owner.upgrades[entry.robotId] or 0
				if RobotService.spawn(arena, def, entry.owner, entry.laneIndex, level, now) ~= nil then
					entry.owner.sentThisWave += 1
				end
			end
		end
	end
end

function WaveService.pendingCount(arena: Arena): number
	local pending = 0
	for laneIndex, queue in arena.spawnQueues do
		pending += math.max(0, #queue - arena.spawnHeads[laneIndex] + 1)
	end
	return pending
end

-- A wave is over for an arena once nothing is queued and nothing is still walking.
function WaveService.isArenaResolved(arena: Arena): boolean
	return WaveService.pendingCount(arena) == 0 and RobotService.aliveCount(arena) == 0
end

return WaveService

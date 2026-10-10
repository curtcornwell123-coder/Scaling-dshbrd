--!strict
--[[
	RobotService
	Spawns robots, moves them along lane waypoints, runs their abilities, and applies damage,
	stuns, and slows. Movement is plain CFrame math along the waypoint polyline (no Humanoids, no
	pathfinding): each match tick moves every robot root in one workspace:BulkMoveTo call.

	Robots never call into TowerService. Hostile effects on towers (Glitch, Bomber, Striker, Mortar)
	are requested through arena.towerHitRequested, which TowerService handles, so the dependency
	stays one-way. Auras (Sentinel guard, Relay boost) are marks on nearby robots with an expiry,
	and Phantom's stealth is a time stamp TowerService checks when picking targets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local StatResolver = require(ReplicatedStorage.Shared.Logic.StatResolver)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local PlaceholderModels = require(script.Parent.Parent.World.PlaceholderModels)
local Effects = require(script.Parent.Parent.World.Effects)

type Arena = ServerTypes.Arena
type RobotUnit = ServerTypes.RobotUnit
type TowerUnit = ServerTypes.TowerUnit

local FLAT_EPSILON = 1e-3
-- Aura marks outlive one tick slightly so a robot at the edge never flickers in and out.
local AURA_REFRESH = 0.3
local STEALTH_TRANSPARENCY = 0.75
local BASE_TRANSPARENCY_ATTRIBUTE = "BaseTransparency"
local World = Constants.World

local RobotService = {}

-- Reused every tick so moving robots allocates no new tables.
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function flightAltitude(arena: Arena): number
	if arena.magnetActive then
		return RobotConfig.FlyingAltitude * MutationConfig.Tuning.magnetAltitudeScale
	end
	return RobotConfig.FlyingAltitude
end

local function liftedPosition(robot: RobotUnit, now: number, altitude: number): Vector3
	local height = robot.heightOffset
	if robot.flying then
		height += altitude + math.sin(now * World.FLYER_BOB_SPEED + robot.uid) * World.FLYER_BOB_HEIGHT
	end
	return robot.pathPoint + Vector3.new(0, height, 0)
end

-- Moves the robot `distance` studs along its lane. Returns true when it reached the end.
local function advance(robot: RobotUnit, distance: number): boolean
	local lane = robot.lane
	robot.distance += distance
	robot.segmentDistance += distance
	while robot.segmentDistance >= lane.segmentLengths[robot.segment] do
		robot.segmentDistance -= lane.segmentLengths[robot.segment]
		robot.segment += 1
		if robot.segment >= #lane.points then
			return true
		end
	end

	local from = lane.points[robot.segment]
	local to = lane.points[robot.segment + 1]
	local length = lane.segmentLengths[robot.segment]
	local alpha = if length > 0 then robot.segmentDistance / length else 1
	robot.pathPoint = from:Lerp(to, alpha)
	local direction = to - from
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > FLAT_EPSILON then
		robot.facing = flat.Unit
	end
	robot.progress = math.min(1, robot.distance / lane.length)
	return false
end

local function nearestTower(
	arena: Arena,
	position: Vector3,
	radius: number,
	now: number,
	mustBeActive: boolean
): TowerUnit?
	local best: TowerUnit? = nil
	local bestDistance = radius * radius
	for _, tower in arena.towers do
		if not tower.destroyed and (not mustBeActive or now >= tower.disabledUntil) then
			local distance = MathUtil.distanceSquared(position, tower.position)
			if distance <= bestDistance then
				best = tower
				bestDistance = distance
			end
		end
	end
	return best
end

function RobotService.kill(arena: Arena, robot: RobotUnit, reason: ServerTypes.RemovalReason)
	if not robot.alive then
		return
	end
	robot.alive = false
	if reason == "Destroyed" then
		local visual = robot.def.visual
		Effects.send(
			arena.viewers,
			"Explosion",
			robot.position,
			robot.position,
			visual.color,
			math.max(visual.size.X, visual.size.Y)
		)
	end
	robot.model:Destroy()
	arena.robotRemoved:fire(robot, reason)
end

local function isImmune(robot: RobotUnit, effect: Types.Immunity): boolean
	local immunities = robot.def.immunities
	return immunities ~= nil and table.find(immunities, effect) ~= nil
end

-- Returns true if this damage destroyed the robot.
function RobotService.damage(arena: Arena, robot: RobotUnit, amount: number): boolean
	if not robot.alive or amount <= 0 then
		return false
	end
	if arena.clock < robot.guardedUntil then
		amount *= 1 - robot.guardReduction
	end
	robot.health -= amount
	robot.barDirty = true
	if robot.health <= 0 then
		RobotService.kill(arena, robot, "Destroyed")
		return true
	end
	return false
end

function RobotService.stun(robot: RobotUnit, untilTime: number)
	if isImmune(robot, "Stun") then
		return
	end
	robot.stunnedUntil = math.max(robot.stunnedUntil, untilTime)
end

-- The strongest active slow wins; a weaker slow can only extend nothing.
function RobotService.slow(robot: RobotUnit, multiplier: number, untilTime: number, now: number)
	if isImmune(robot, "Slow") then
		return
	end
	if now >= robot.slowedUntil then
		robot.slowMultiplier = multiplier
	else
		robot.slowMultiplier = math.min(robot.slowMultiplier, multiplier)
	end
	robot.slowedUntil = math.max(robot.slowedUntil, untilTime)
end

local function runHeal(arena: Arena, robot: RobotUnit, ability: Types.AbilityDef, index: number, now: number)
	local radius = ability.radius or 0
	local amount = ability.amount or 0
	local radiusSquared = radius * radius
	local healed = false
	for _, ally in arena.robots do
		if
			ally.alive
			and ally.health < ally.maxHealth
			and MathUtil.distanceSquared(ally.position, robot.position) <= radiusSquared
		then
			ally.health = math.min(ally.maxHealth, ally.health + amount)
			ally.barDirty = true
			healed = true
		end
	end
	robot.abilityReadyAt[index] = now + (ability.interval or 0)
	if healed then
		Effects.send(arena.viewers, "Heal", robot.position, robot.position, robot.def.visual.accent, radius)
	end
end

local function runDisable(arena: Arena, robot: RobotUnit, ability: Types.AbilityDef, index: number, now: number)
	local tower = nearestTower(arena, robot.position, ability.radius or 0, now, true)
	if tower == nil then
		return
	end
	robot.abilityReadyAt[index] = now + (ability.cooldown or 0)
	Effects.send(arena.viewers, "Glitch", robot.position, tower.position, robot.def.visual.color, 0)
	arena.towerHitRequested:fire(tower, robot, 0, ability.duration or 0)
end

-- Returns true when the robot detonated (and is now dead).
local function runExplode(arena: Arena, robot: RobotUnit, ability: Types.AbilityDef, now: number): boolean
	if nearestTower(arena, robot.position, ability.triggerRadius or 0, now, false) == nil then
		return false
	end
	local radius = ability.radius or 0
	local radiusSquared = radius * radius
	local damage = ability.damage or 0
	Effects.send(arena.viewers, "Explosion", robot.position, robot.position, robot.def.visual.accent, radius)
	for _, tower in arena.towers do
		if not tower.destroyed and MathUtil.distanceSquared(tower.position, robot.position) <= radiusSquared then
			arena.towerHitRequested:fire(tower, robot, damage, 0)
		end
	end
	RobotService.kill(arena, robot, "Exploded")
	return true
end

-- Sentinel: allies in range (itself included) take less damage while the mark lasts.
local function runGuard(arena: Arena, robot: RobotUnit, ability: Types.AbilityDef, now: number)
	local radius = ability.radius or 0
	local radiusSquared = radius * radius
	local reduction = math.clamp(ability.reduction or 0, 0, 0.9)
	for _, ally in arena.robots do
		if ally.alive and MathUtil.distanceSquared(ally.position, robot.position) <= radiusSquared then
			if now >= ally.guardedUntil or reduction > ally.guardReduction then
				ally.guardReduction = reduction
			end
			ally.guardedUntil = now + AURA_REFRESH
		end
	end
end

-- Relay: pulses a speed boost onto nearby allies (not itself).
local function runBoost(arena: Arena, robot: RobotUnit, ability: Types.AbilityDef, index: number, now: number)
	local radius = ability.radius or 0
	local radiusSquared = radius * radius
	local amount = ability.amount or 0
	local boosted = false
	for _, ally in arena.robots do
		if
			ally ~= robot
			and ally.alive
			and MathUtil.distanceSquared(ally.position, robot.position) <= radiusSquared
		then
			if now >= ally.boostedUntil or amount > ally.boostAmount then
				ally.boostAmount = amount
			end
			ally.boostedUntil = math.max(ally.boostedUntil, now + (ability.duration or 0))
			boosted = true
		end
	end
	robot.abilityReadyAt[index] = now + (ability.interval or 0)
	if boosted then
		Effects.send(arena.viewers, "Pulse", robot.position, robot.position, robot.def.visual.accent, radius)
	end
end

-- Striker (short range) and Mortar (long range): hit the nearest standing tower and keep going.
local function runTowerAttack(arena: Arena, robot: RobotUnit, ability: Types.AbilityDef, index: number, now: number)
	local tower = nearestTower(arena, robot.position, ability.radius or 0, now, false)
	if tower == nil then
		return
	end
	robot.abilityReadyAt[index] = now + (ability.cooldown or 0)
	local kind: Types.EffectKind = if ability.kind == "Bombard" then "Explosion" else "Shot"
	Effects.send(
		arena.viewers,
		kind,
		robot.position,
		tower.position,
		robot.def.visual.accent,
		if kind == "Explosion" then 3 else 0
	)
	arena.towerHitRequested:fire(tower, robot, ability.damage or 0, 0)
end

local function setStealthVisual(robot: RobotUnit, hidden: boolean)
	robot.stealthShown = hidden
	for _, descendant in robot.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local base = descendant:GetAttribute(BASE_TRANSPARENCY_ATTRIBUTE)
			if base == nil then
				base = descendant.Transparency
				descendant:SetAttribute(BASE_TRANSPARENCY_ATTRIBUTE, base)
			end
			local baseValue = if type(base) == "number" then base else 0
			descendant.Transparency = if hidden then math.max(baseValue, STEALTH_TRANSPARENCY) else baseValue
		end
	end
end

-- Phantom: cycles between a stealth window and its cooldown.
local function runStealth(robot: RobotUnit, ability: Types.AbilityDef, index: number, now: number)
	local duration = ability.duration or 0
	robot.stealthUntil = now + duration
	robot.abilityReadyAt[index] = now + duration + (ability.cooldown or 0)
end

local function runAbilities(arena: Arena, robot: RobotUnit, now: number)
	for index, ability in robot.def.abilities do
		local kind = ability.kind
		if kind == "Guard" then
			-- Passive aura: refreshed every tick, no cooldown.
			runGuard(arena, robot, ability, now)
		elseif now >= robot.abilityReadyAt[index] then
			if kind == "Heal" then
				runHeal(arena, robot, ability, index, now)
			elseif kind == "Disable" then
				runDisable(arena, robot, ability, index, now)
			elseif kind == "Explode" then
				if runExplode(arena, robot, ability, now) then
					return
				end
			elseif kind == "Strike" or kind == "Bombard" then
				runTowerAttack(arena, robot, ability, index, now)
			elseif kind == "Boost" then
				runBoost(arena, robot, ability, index, now)
			elseif kind == "Stealth" then
				runStealth(robot, ability, index, now)
			end
		end
	end
	local hidden = now < robot.stealthUntil
	if hidden ~= robot.stealthShown then
		setStealthVisual(robot, hidden)
	end
end

function RobotService.spawn(
	arena: Arena,
	def: Types.RobotDef,
	owner: ServerTypes.MatchPlayer,
	laneIndex: number,
	level: number,
	now: number
): RobotUnit?
	local lane = arena.map.lanes[laneIndex]
	if lane == nil then
		return nil
	end
	local health, damage = StatResolver.robotStats(def, level, RobotConfig.Upgrade)
	local built = PlaceholderModels.robot(def)
	arena.nextUid += 1

	local abilityReadyAt: { number } = {}
	for index in def.abilities do
		abilityReadyAt[index] = now
	end

	local start = lane.points[1]
	local firstStep = lane.points[2] - start
	local flatStep = Vector3.new(firstStep.X, 0, firstStep.Z)
	local robot: RobotUnit = {
		uid = arena.nextUid,
		def = def,
		owner = owner,
		lane = lane,
		model = built.model,
		root = built.root,
		heightOffset = built.heightOffset,
		maxHealth = health,
		health = health,
		speed = def.speed,
		damage = damage,
		flying = def.flying,
		segment = 1,
		segmentDistance = 0,
		distance = 0,
		progress = 0,
		pathPoint = start,
		position = start,
		facing = if flatStep.Magnitude > FLAT_EPSILON then flatStep.Unit else Vector3.zAxis,
		stunnedUntil = 0,
		slowedUntil = 0,
		slowMultiplier = 1,
		guardedUntil = 0,
		guardReduction = 0,
		boostedUntil = 0,
		boostAmount = 0,
		stealthUntil = 0,
		stealthShown = false,
		abilityReadyAt = abilityReadyAt,
		alive = true,
		barFill = built.barFill,
		barDirty = false,
	}
	robot.position = liftedPosition(robot, now, flightAltitude(arena))
	robot.root.CFrame = CFrame.lookAt(robot.position, robot.position + robot.facing)
	robot.model.Parent = arena.map.unitFolder
	table.insert(arena.robots, robot)
	return robot
end

function RobotService.step(arena: Arena, dt: number, now: number)
	table.clear(moveParts)
	table.clear(moveCFrames)
	local altitude = flightAltitude(arena)

	for _, robot in arena.robots do
		if not robot.alive then
			continue
		end
		if now >= robot.stunnedUntil then
			local speed = robot.speed
			if now < robot.slowedUntil then
				speed *= robot.slowMultiplier
			end
			if now < robot.boostedUntil then
				speed *= 1 + robot.boostAmount
			end
			if advance(robot, speed * dt) then
				arena.robotReachedBase:fire(robot)
				RobotService.kill(arena, robot, "ReachedBase")
				continue
			end
		end

		robot.position = liftedPosition(robot, now, altitude)
		runAbilities(arena, robot, now)
		if robot.alive then
			table.insert(moveParts, robot.root)
			table.insert(moveCFrames, CFrame.lookAt(robot.position, robot.position + robot.facing))
		end
	end

	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Drops dead robots from the arena list. Called once per tick after all systems ran, so no
-- system ever iterates a list that is being reshuffled underneath it.
function RobotService.compact(arena: Arena)
	local robots = arena.robots
	for index = #robots, 1, -1 do
		if not robots[index].alive then
			TableUtil.swapRemove(robots, index)
		end
	end
end

function RobotService.flushBars(arena: Arena)
	for _, robot in arena.robots do
		if robot.alive and robot.barDirty then
			robot.barDirty = false
			robot.barFill.Size = UDim2.fromScale(math.clamp(robot.health / robot.maxHealth, 0, 1), 1)
		end
	end
end

function RobotService.clearAll(arena: Arena)
	for _, robot in arena.robots do
		RobotService.kill(arena, robot, "Cleared")
	end
	table.clear(arena.robots)
end

function RobotService.aliveCount(arena: Arena): number
	local count = 0
	for _, robot in arena.robots do
		if robot.alive then
			count += 1
		end
	end
	return count
end

return RobotService

--!strict
--[[
	TowerService
	The AI military defense. Places towers into map slots following WaveConfig.DefensePlan, keeps
	their stats in sync with the mutation stack, and runs every tower of an arena from one step
	function called by the match's single Heartbeat connection (never one loop per tower).

	Targeting: among robots the tower can hit and that are in range, pick the one furthest along
	its lane (closest to the HQ). Mutation behaviours (Reactive Armor, EMP Strike, Shrapnel Rounds,
	Field Engineers, Flak Barrage) all read resolved stats, so they stack exactly like the numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local WaveConfig = require(ReplicatedStorage.Shared.Config.WaveConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local PlaceholderModels = require(script.Parent.Parent.World.PlaceholderModels)
local Effects = require(script.Parent.Parent.World.Effects)
local RobotService = require(script.Parent.RobotService)
local MutationService = require(script.Parent.MutationService)

type Arena = ServerTypes.Arena
type RobotUnit = ServerTypes.RobotUnit
type TowerUnit = ServerTypes.TowerUnit

local Tuning = MutationConfig.Tuning
local AIM_EPSILON = 1e-3

local TowerService = {}

-- Reused by Shrapnel Rounds so chaining never allocates.
local chainVisited: { [number]: boolean } = {}

local function canTarget(tower: TowerUnit, robot: RobotUnit): boolean
	if robot.flying then
		-- Flak Barrage drags flyers low enough for ground guns.
		return tower.def.targetsAir or (tower.def.targetsGround and tower.stats.magnet > 0)
	end
	return tower.def.targetsGround
end

local function findTarget(arena: Arena, tower: TowerUnit): RobotUnit?
	local rangeSquared = tower.stats.range * tower.stats.range
	local best: RobotUnit? = nil
	local bestProgress = -1
	for _, robot in arena.robots do
		if
			robot.alive
			and robot.progress > bestProgress
			and canTarget(tower, robot)
			and MathUtil.distanceSquared(tower.position, robot.position) <= rangeSquared
		then
			best = robot
			bestProgress = robot.progress
		end
	end
	return best
end

local function aim(tower: TowerUnit, target: Vector3)
	local headPosition = tower.head.Position
	local flatTarget = Vector3.new(target.X, headPosition.Y, target.Z)
	if (flatTarget - headPosition).Magnitude > AIM_EPSILON then
		tower.head.CFrame = CFrame.lookAt(headPosition, flatTarget)
	end
end

local function hitRobot(arena: Arena, tower: TowerUnit, robot: RobotUnit, damage: number, now: number)
	local slowDuration = tower.stats.slowDuration
	if slowDuration > 0 and tower.def.slowMultiplier < 1 then
		RobotService.slow(robot, tower.def.slowMultiplier, now + slowDuration, now)
	end
	RobotService.damage(arena, robot, damage)
end

local function chain(arena: Arena, tower: TowerUnit, first: RobotUnit, origin: Vector3, damage: number, now: number)
	local jumps = math.floor(tower.stats.chainCount)
	if jumps <= 0 then
		return
	end
	table.clear(chainVisited)
	chainVisited[first.uid] = true
	local rangeSquared = Tuning.chainRange * Tuning.chainRange
	local from = origin
	local chainDamage = damage
	for _ = 1, jumps do
		chainDamage *= Tuning.chainDamageFactor
		local nextTarget: RobotUnit? = nil
		local nearest = rangeSquared
		for _, robot in arena.robots do
			if robot.alive and not chainVisited[robot.uid] and canTarget(tower, robot) then
				local distance = MathUtil.distanceSquared(from, robot.position)
				if distance <= nearest then
					nearest = distance
					nextTarget = robot
				end
			end
		end
		if nextTarget == nil then
			return
		end
		chainVisited[nextTarget.uid] = true
		Effects.send(arena.viewers, "Chain", from, nextTarget.position, Theme.Military.Amber, 0)
		from = nextTarget.position
		hitRobot(arena, tower, nextTarget, chainDamage, now)
	end
end

local function fire(arena: Arena, tower: TowerUnit, target: RobotUnit, now: number)
	local stats = tower.stats
	tower.nextFireAt = now + 1 / math.max(stats.fireRate, Constants.Match.MIN_FIRE_RATE)
	local impact = target.position
	aim(tower, impact)
	Effects.send(arena.viewers, "Shot", tower.position, impact, tower.def.visual.accent, 0)

	if stats.splashRadius > 0 then
		local splashSquared = stats.splashRadius * stats.splashRadius
		Effects.send(arena.viewers, "Explosion", impact, impact, Theme.Military.Amber, stats.splashRadius)
		for _, robot in arena.robots do
			if
				robot.alive
				and canTarget(tower, robot)
				and MathUtil.distanceSquared(impact, robot.position) <= splashSquared
			then
				hitRobot(arena, tower, robot, stats.damage, now)
			end
		end
	else
		hitRobot(arena, tower, target, stats.damage, now)
	end
	chain(arena, tower, target, impact, stats.damage, now)
end

local function empPulse(arena: Arena, tower: TowerUnit, now: number)
	local rangeSquared = tower.stats.range * tower.stats.range
	local stunned = false
	for _, robot in arena.robots do
		if robot.alive and MathUtil.distanceSquared(tower.position, robot.position) <= rangeSquared then
			RobotService.stun(robot, now + tower.stats.empStun)
			stunned = true
		end
	end
	-- The cooldown only starts when a pulse actually caught something, so towers never waste it.
	if stunned then
		tower.nextEmpAt = now + Tuning.empPulseInterval
		Effects.send(arena.viewers, "Pulse", tower.position, tower.position, Theme.Colors.Primary, tower.stats.range)
	end
end

local function setDisabledVisual(tower: TowerUnit, disabled: boolean)
	tower.showingDisabled = disabled
	local light = tower.light
	if light ~= nil then
		light.Color = if disabled then Theme.Colors.TextDim else tower.def.visual.accent
		light.Material = if disabled then Enum.Material.SmoothPlastic else Enum.Material.Neon
	end
end

local function destroyTower(arena: Arena, tower: TowerUnit)
	tower.destroyed = true
	tower.health = 0
	Effects.send(arena.viewers, "Explosion", tower.position, tower.position, Theme.Military.AlertRed, 6)
	-- Hidden rather than destroyed so it can be rebuilt next wave; the arena maid still owns it.
	tower.model.Parent = nil
end

-- Robots request hits through arena.towerHitRequested; Reactive Armor absorbs the first
-- `armorHits` hits each individual robot lands on each tower.
function TowerService.applyHit(
	arena: Arena,
	tower: TowerUnit,
	source: RobotUnit,
	damage: number,
	disableSeconds: number,
	now: number
)
	if tower.destroyed then
		return
	end
	local blocked = tower.hitsBlocked[source.uid] or 0
	if blocked < math.floor(tower.stats.armorHits) then
		tower.hitsBlocked[source.uid] = blocked + 1
		Effects.send(arena.viewers, "Shield", tower.position, tower.position, Theme.Military.Amber, 4)
		return
	end
	if disableSeconds > 0 then
		tower.disabledUntil = math.max(tower.disabledUntil, now + disableSeconds)
	end
	if damage > 0 then
		tower.health -= damage
		tower.barDirty = true
		if tower.health <= 0 then
			destroyTower(arena, tower)
		end
	end
end

function TowerService.attach(arena: Arena)
	arena.maid:give(
		arena.towerHitRequested:connect(
			function(tower: TowerUnit, source: RobotUnit, damage: number, disableSeconds: number)
				TowerService.applyHit(arena, tower, source, damage, disableSeconds, os.clock())
			end
		)
	)
end

-- Re-resolves every tower type from base stats + the full mutation stack. Health keeps its ratio
-- when max health changes, so Fortifications heals proportionally instead of resetting.
function TowerService.refreshStats(arena: Arena)
	local magnet = false
	for towerId, def in TowerConfig.Towers do
		local stats = MutationService.resolveTowerStats(arena.mutations, def)
		arena.towerStats[towerId] = stats
		if stats.magnet > 0 then
			magnet = true
		end
	end
	arena.magnetActive = magnet

	for _, tower in arena.towers do
		local stats = arena.towerStats[tower.def.id]
		local oldMax = tower.stats.maxHealth
		if not tower.destroyed and oldMax > 0 then
			tower.health = tower.health * stats.maxHealth / oldMax
		end
		tower.stats = stats
		tower.barDirty = true
	end
end

local function place(arena: Arena, def: Types.TowerDef, slotIndex: number): TowerUnit
	local built = PlaceholderModels.tower(def, arena.map.towerSlots[slotIndex])
	built.model.Parent = arena.map.unitFolder
	arena.maid:give(built.model)

	local stats = arena.towerStats[def.id] or MutationService.resolveTowerStats(arena.mutations, def)
	arena.nextUid += 1
	local tower: TowerUnit = {
		uid = arena.nextUid,
		def = def,
		slotIndex = slotIndex,
		model = built.model,
		head = built.head,
		light = built.light,
		position = built.head.Position,
		stats = stats,
		health = stats.maxHealth,
		destroyed = false,
		disabledUntil = 0,
		showingDisabled = false,
		nextFireAt = 0,
		nextEmpAt = 0,
		hitsBlocked = {},
		barFill = built.barFill,
		barDirty = true,
	}
	table.insert(arena.towers, tower)
	return tower
end

-- Called at the start of every Preparing phase: rebuilds and repairs existing towers, then
-- deploys this wave's reinforcements. Returns the display names of the new towers.
function TowerService.prepareWave(arena: Arena, waveNumber: number): { string }
	for _, tower in arena.towers do
		if tower.destroyed then
			tower.destroyed = false
			tower.model.Parent = arena.map.unitFolder
		end
		tower.health = tower.stats.maxHealth
		tower.disabledUntil = 0
		tower.nextEmpAt = 0
		table.clear(tower.hitsBlocked)
		tower.barDirty = true
		if tower.showingDisabled then
			setDisabledVisual(tower, false)
		end
	end

	local deployed: { string } = {}
	local plan = WaveConfig.DefensePlan[waveNumber]
	if plan ~= nil then
		for _, towerId in plan do
			local slotIndex = #arena.towers + 1
			if slotIndex > #arena.map.towerSlots then
				break
			end
			local def = TowerConfig.Towers[towerId]
			if def ~= nil then
				place(arena, def, slotIndex)
				table.insert(deployed, def.displayName)
			end
		end
	end
	return deployed
end

function TowerService.step(arena: Arena, dt: number, now: number)
	for _, tower in arena.towers do
		if tower.destroyed then
			continue
		end
		local disabled = now < tower.disabledUntil
		if disabled ~= tower.showingDisabled then
			setDisabledVisual(tower, disabled)
		end
		if disabled then
			continue
		end

		local stats = tower.stats
		if stats.regenPerSecond > 0 and tower.health < stats.maxHealth then
			tower.health = math.min(stats.maxHealth, tower.health + stats.regenPerSecond * dt)
			tower.barDirty = true
		end
		if stats.empStun > 0 and now >= tower.nextEmpAt then
			empPulse(arena, tower, now)
		end
		if now >= tower.nextFireAt then
			local target = findTarget(arena, tower)
			if target ~= nil then
				fire(arena, tower, target, now)
			end
		end
	end
end

function TowerService.flushBars(arena: Arena)
	for _, tower in arena.towers do
		if tower.barDirty and not tower.destroyed then
			tower.barDirty = false
			tower.barFill.Size = UDim2.fromScale(math.clamp(tower.health / math.max(tower.stats.maxHealth, 1), 0, 1), 1)
		end
	end
end

return TowerService

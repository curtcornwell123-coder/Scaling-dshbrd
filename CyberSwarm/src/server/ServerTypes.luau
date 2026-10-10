--!strict
--[[
	ServerTypes
	Runtime records for live matches. Services pass these plain records around instead of requiring
	each other, which keeps the dependency graph one-directional (see README "Architecture").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type Lane = {
	points: { Vector3 },
	segmentLengths: { number },
	length: number,
}

export type LoadedMap = {
	mapId: string,
	model: Model,
	slotIndex: number,
	lanes: { Lane },
	towerSlots: { CFrame },
	baseCFrame: CFrame,
	playerSpawns: { CFrame },
	cameraCFrame: CFrame,
	unitFolder: Folder,
}

export type MutationState = {
	counts: { [string]: number },
	-- Mutation ids in the order they were first gained, for stable UI ordering.
	history: { string },
	-- Rolled after a wave, shown during Preparing, applied when the next wave starts.
	pending: string?,
}

export type RemovalReason = "Destroyed" | "ReachedBase" | "Exploded" | "Cleared"

export type RobotUnit = {
	uid: number,
	def: Types.RobotDef,
	owner: MatchPlayer,
	lane: Lane,
	model: Model,
	root: BasePart,
	heightOffset: number,
	maxHealth: number,
	health: number,
	speed: number,
	damage: number,
	flying: boolean,
	segment: number,
	segmentDistance: number,
	distance: number,
	progress: number,
	-- Point on the lane centre line; `position` is the model centre (lifted for height and flight).
	pathPoint: Vector3,
	position: Vector3,
	facing: Vector3,
	stunnedUntil: number,
	slowedUntil: number,
	slowMultiplier: number,
	-- Sentinel aura: damage taken is reduced by guardReduction until guardedUntil.
	guardedUntil: number,
	guardReduction: number,
	-- Relay aura: speed is raised by boostAmount until boostedUntil.
	boostedUntil: number,
	boostAmount: number,
	-- Phantom: towers cannot target the robot until stealthUntil.
	stealthUntil: number,
	stealthShown: boolean,
	abilityReadyAt: { number },
	alive: boolean,
	barFill: Frame,
	barDirty: boolean,
}

export type TowerUnit = {
	uid: number,
	def: Types.TowerDef,
	slotIndex: number,
	model: Model,
	head: BasePart,
	light: BasePart?,
	position: Vector3,
	stats: Types.StatBlock,
	health: number,
	destroyed: boolean,
	disabledUntil: number,
	showingDisabled: boolean,
	nextFireAt: number,
	nextEmpAt: number,
	-- Robot uid -> hits from that robot already absorbed by Reactive Armor.
	hitsBlocked: { [number]: number },
	barFill: Frame,
	barDirty: boolean,
}

export type QueuedRobot = {
	robotId: string,
	owner: MatchPlayer,
	laneIndex: number,
}

export type Arena = {
	index: number,
	maid: Maid.Maid,
	players: { MatchPlayer },
	viewers: { Player },
	map: LoadedMap,
	robots: { RobotUnit },
	towers: { TowerUnit },
	mutations: MutationState,
	towerStats: { [string]: Types.StatBlock },
	magnetActive: boolean,
	baseModel: Model,
	baseBarFill: Frame,
	baseHealth: number,
	baseMaxHealth: number,
	spawnQueues: { { QueuedRobot } },
	spawnHeads: { number },
	nextSpawnAt: { number },
	nextUid: number,
	eliminated: boolean,
	nextBarFlushAt: number,
	-- Match clock (seconds, scaled by the match's time scale). Systems read this, never os.clock().
	clock: number,
	robotReachedBase: Signal.Signal<RobotUnit>,
	robotRemoved: Signal.Signal<RobotUnit, RemovalReason>,
	-- tower, attacking robot, damage, disable seconds
	towerHitRequested: Signal.Signal<TowerUnit, RobotUnit, number, number>,
}

export type MatchPlayer = {
	player: Player,
	userId: number,
	arena: Arena,
	coins: number,
	loadout: { string },
	upgrades: { [string]: number },
	queued: { [string]: number },
	queuedThisWave: number,
	sentThisWave: number,
	connected: boolean,
	-- Test Realm: spending never fails and nothing is paid out.
	unlimitedCoins: boolean,
	team: number,
}

export type Outcome = {
	winner: Arena?,
	reason: Types.MatchEndReason,
}

export type Match = {
	id: number,
	mode: Types.ModeDef,
	mapId: string,
	state: Types.MatchState,
	stateEndsAt: number,
	-- Bumped on every state change so a stale timer can never advance the wrong phase.
	stateToken: number,
	waveNumber: number,
	wavesCompleted: number,
	maid: Maid.Maid,
	arenas: { Arena },
	players: { [Player]: MatchPlayer },
	rng: Random,
	dirty: boolean,
	nextSyncAt: number,
	pendingOutcome: Outcome?,
	results: { [Player]: Types.MatchResult },
	closed: boolean,
	-- Unique across servers (JobId + local id); rating results are keyed by it.
	key: string,
	-- Scaled match clock and its speed (Test Realm speed setting; 1 everywhere else).
	clock: number,
	timeScale: number,
	sandbox: Types.SandboxConfig?,
	-- Wave the match starts on (Test Realm can start later than wave 1).
	firstWave: number,
}

return {}

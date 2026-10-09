--!strict
--[[
	Types
	Shared type definitions for config entries, saved player data, and the snapshots the server
	sends to clients. Server-only runtime types live in ServerScriptService.Server.ServerTypes.
]]

export type MatchState = "Waiting" | "Countdown" | "Preparing" | "WaveActive" | "WaveResult" | "MatchEnd"

-- Shared: every player attacks one AI defense together (Solo, Co-op).
-- PerPlayer: each player gets their own lane copy and races to destroy their base first (1v1).
export type SideLayout = "Shared" | "PerPlayer"

export type AbilityKind = "Heal" | "Disable" | "Explode"

export type AbilityDef = {
	kind: AbilityKind,
	radius: number?,
	amount: number?,
	interval: number?,
	duration: number?,
	cooldown: number?,
	damage: number?,
	triggerRadius: number?,
}

export type UnitShape = "Block" | "Ball"

export type UnitVisual = {
	size: Vector3,
	color: Color3,
	accent: Color3,
	shape: UnitShape,
}

export type RobotDef = {
	id: string,
	displayName: string,
	description: string,
	rarity: string,
	cost: number,
	health: number,
	speed: number,
	damage: number,
	flying: boolean,
	abilities: { AbilityDef },
	modelPath: string,
	visual: UnitVisual,
	unlockCost: number,
	locked: boolean,
	upgradeCosts: { number },
}

export type RobotUpgradeRules = {
	healthPerLevel: number,
	damagePerLevel: number,
}

export type TowerDef = {
	id: string,
	displayName: string,
	description: string,
	damage: number,
	fireRate: number,
	range: number,
	maxHealth: number,
	splashRadius: number,
	targetsGround: boolean,
	targetsAir: boolean,
	slowMultiplier: number,
	slowDuration: number,
	modelPath: string,
	visual: UnitVisual,
}

-- A resolved set of numeric tower stats keyed by stat name (see Constants.TOWER_STATS).
export type StatBlock = { [string]: number }

export type Modifier = {
	stat: string,
	multiplier: number?,
	add: number?,
}

export type MutationRarity = "Common" | "Rare" | "Mythic"

export type MutationDef = {
	id: string,
	displayName: string,
	rarity: MutationRarity,
	description: string,
	modifiers: { Modifier },
	maxStacks: number,
}

export type MutationRarityDef = {
	weight: number,
}

export type MutationTuning = {
	empPulseInterval: number,
	chainRange: number,
	chainDamageFactor: number,
	magnetAltitudeScale: number,
}

export type MapDef = {
	id: string,
	displayName: string,
	description: string,
	templateName: string,
	laneCount: number,
	baseHealth: number,
	builtIn: boolean,
}

export type WaveRewards = {
	perSurvivor: number,
	perBaseDamage: number,
	completionBonus: number,
	completionBonusPerWave: number,
}

export type RobotCapRules = {
	base: number,
	perWave: number,
	max: number,
}

export type MatchRewards = {
	winCoins: number,
	lossCoins: number,
	perWaveCoins: number,
}

export type ModeDef = {
	id: string,
	displayName: string,
	description: string,
	minPlayers: number,
	maxPlayers: number,
	sideLayout: SideLayout,
	maxWaves: number,
	queueCountdown: number,
	mapPool: { string },
	rewards: MatchRewards,
	baseHealthPerExtraPlayer: number,
	padColor: Color3,
}

export type PlayerStats = {
	wins: number,
	losses: number,
	wavesSurvived: number,
	highestWave: number,
}

export type PlayerSettings = {
	musicVolume: number,
	sfxVolume: number,
}

export type PlayerData = {
	coins: number,
	gems: number,
	unlockedRobots: { string },
	equippedLoadout: { string },
	stats: PlayerStats,
	settings: PlayerSettings,
}

export type MutationInfo = {
	id: string,
	displayName: string,
	rarity: MutationRarity,
	description: string,
	stacks: number,
}

export type RobotSlotInfo = {
	robotId: string,
	cost: number,
	queued: number,
	level: number,
	upgradeCost: number?,
}

export type RivalInfo = {
	name: string,
	baseHealth: number,
	baseMaxHealth: number,
}

export type MatchEndReason =
	"BaseDestroyed"
	| "RivalDestroyedBase"
	| "OutOfCoins"
	| "RivalOutOfCoins"
	| "WaveLimit"
	| "RivalLeft"

export type MatchResult = {
	won: boolean,
	reason: MatchEndReason,
	wavesCompleted: number,
	coinsAwarded: number,
}

export type MatchSnapshot = {
	matchId: number,
	modeId: string,
	mapId: string,
	state: MatchState,
	stateEndsAt: number,
	wave: number,
	maxWaves: number,
	coins: number,
	baseHealth: number,
	baseMaxHealth: number,
	laneCount: number,
	waveCap: number,
	queuedThisWave: number,
	loadout: { RobotSlotInfo },
	activeMutations: { MutationInfo },
	nextMutation: MutationInfo?,
	rivals: { RivalInfo },
	cameraCFrame: CFrame,
	result: MatchResult?,
}

export type QueueSnapshot = {
	modeId: string?,
	count: number,
	required: number,
	capacity: number,
	countdownEndsAt: number?,
}

export type NoticeStyle = "Toast" | "Banner"
export type NoticeTone = "Info" | "Success" | "Error" | "Mutation"

export type NoticePayload = {
	style: NoticeStyle,
	tone: NoticeTone,
	code: string?,
	title: string?,
	text: string?,
}

export type EffectKind = "Shot" | "Pulse" | "Explosion" | "Chain" | "Heal" | "Glitch" | "Shield"

export type EffectPayload = {
	kind: EffectKind,
	origin: Vector3,
	target: Vector3,
	color: Color3,
	radius: number,
}

-- Types-only module; the empty table keeps require() returning exactly one value.
return {}

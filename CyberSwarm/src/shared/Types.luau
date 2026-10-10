--!strict
--[[
	Types
	Shared type definitions for config entries, saved player data, and the snapshots the server
	sends to clients. Server-only runtime types live in ServerScriptService.Server.ServerTypes.
]]

export type MatchState = "Waiting" | "Countdown" | "Preparing" | "WaveActive" | "WaveResult" | "MatchEnd"

export type AbilityKind =
	"Heal" -- repair nearby robots
	| "Disable" -- hack the nearest tower offline
	| "Explode" -- detonate on towers
	| "Guard" -- nearby robots take reduced damage
	| "Strike" -- melee hit on a nearby tower without dying
	| "Boost" -- speed up nearby robots
	| "Bombard" -- long-range shelling of a tower
	| "Stealth" -- briefly untargetable

export type AbilityDef = {
	kind: AbilityKind,
	radius: number?,
	amount: number?,
	interval: number?,
	duration: number?,
	cooldown: number?,
	damage: number?,
	triggerRadius: number?,
	reduction: number?,
}

-- Effects a robot ignores entirely.
export type Immunity = "Stun" | "Slow"

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
	locked: boolean,
	upgradeCosts: { number },
	immunities: { Immunity }?,
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

export type ModeCategory = "Casual" | "Ranked" | "Coop" | "Limited"

export type ModeDef = {
	id: string,
	displayName: string,
	description: string,
	-- 1 team = everyone attacks one defense together; 2+ teams race each other on separate arenas.
	teams: number,
	teamSize: number,
	minPlayers: number,
	maxPlayers: number,
	ranked: boolean,
	requiresParty: boolean,
	-- Every requirement must be met to stand-queue this mode.
	unlock: { UnlockRequirement },
	rewardsEnabled: boolean,
	category: ModeCategory,
	signColor: Color3,
	-- Position of this mode's bay along the Duels Hall wall (0 = not shown).
	bayOrder: number,
	-- Hard cap on players waiting in this mode's queue.
	queueCap: number,
	queueCountdown: number,
	-- Shown on the bay screen until real wait times are measured.
	estimatedWait: number,
	maxWaves: number,
	mapPool: { string },
	rewards: MatchRewards,
	baseHealthPerExtraPlayer: number,
	-- Test Realm: unlimited coins, any troop, nothing earned or lost, restarts instead of ending.
	sandbox: boolean,
}

export type PlayerStats = {
	wins: number,
	losses: number,
	wavesSurvived: number,
	highestWave: number,
	winStreak: number,
	bestWinStreak: number,
}

export type PlayerSettings = {
	musicVolume: number,
	sfxVolume: number,
}

export type Currency = "Coins" | "Gems"

-- Anything the game can hand out: quests, supply drops, codes, the season pass, products.
export type Reward = {
	coins: number?,
	gems: number?,
	xp: number?,
	troopId: string?,
}

export type UnlockKind = "None" | "Wins" | "HighestWave" | "OwnsTroop" | "LoadoutSize" | "MatchesPlayed"

export type UnlockRequirement = {
	kind: UnlockKind,
	value: number,
	troopId: string?,
}

-- Shop catalog entry. Combat stats (hp, spd, cost, rarity, name) are read from RobotConfig so
-- they can never disagree with the robot that actually spawns.
export type TroopDef = {
	id: string,
	name: string,
	role: string,
	hp: number,
	spd: number,
	cost: number,
	rarity: string,
	price: number,
	currency: Currency,
	unlock: UnlockRequirement,
	builderId: string,
	description: string,
	comingSoon: boolean,
}

export type TroopRotation = {
	day: number,
	permanent: { string },
	rotating: { string },
	resetsAt: number,
}

export type QuestKind =
	"PlayMatches"
	| "WinMatches"
	| "CompleteWaves"
	| "DeployRobots"
	| "TryTroops"
	| "TestRealmWaves"

export type QuestDef = {
	id: string,
	description: string,
	kind: QuestKind,
	target: number,
	reward: Reward,
	-- Test Realm quests progress only inside the sandbox; all others never do.
	testRealm: boolean,
}

export type QuestData = {
	day: number,
	progress: { [string]: number },
	claimed: { string },
	-- Distinct troops tried today in the Test Realm (for TryTroops quests).
	tried: { string },
}

export type SupplyData = {
	day: number,
	claims: number,
	lastClaimAt: number,
}

export type SeasonData = {
	seasonId: string,
	xp: number,
	premium: boolean,
	claimedFree: { number },
	claimedPremium: { number },
}

export type SeasonTier = {
	tier: number,
	free: Reward?,
	premium: Reward?,
}

export type PassTrack = "Free" | "Premium" | "Ranked"

export type ProductKind = "Coins" | "Gems" | "Bundle" | "SeasonPremium"

export type ShopProduct = {
	id: string,
	productId: number,
	name: string,
	kind: ProductKind,
	reward: Reward,
	description: string,
}

export type RatingData = {
	rating: number,
	played: number,
	wins: number,
	losses: number,
	peak: number,
}

export type RankedReward = {
	seasonId: string,
	tier: string,
	reward: Reward,
}

export type RankData = {
	seasonId: string,
	-- Keyed by RankConfig rating key ("Duel", "Squad"), one per ranked format.
	ratings: { [string]: RatingData },
	-- Match ids already applied, so a result can never be counted twice.
	appliedMatches: { string },
	-- Recent ranked opponents for the win-trading guard.
	recentOpponents: { { userId: number, at: number } },
	-- Dodge cooldown: no ranked queueing until this unix time.
	cooldownUntil: number,
	-- End-of-season reward waiting to be claimed through the pass claim flow.
	pendingReward: RankedReward?,
}

export type PlayerData = {
	coins: number,
	gems: number,
	unlockedRobots: { string },
	equippedLoadout: { string },
	stats: PlayerStats,
	settings: PlayerSettings,
	-- Developer-product receipt ids already granted (idempotent ProcessReceipt).
	purchases: { string },
	season: SeasonData,
	quests: QuestData,
	supply: SupplyData,
	codes: { string },
	rank: RankData,
}

export type LeaderboardEntry = {
	rank: number,
	userId: number,
	name: string,
	value: number,
}

-- One leaderboard wall: "WinStreak" on the hub, "Duel"/"Squad" ranked boards in the Duels Hall.
export type LeaderboardSnapshot = {
	board: string,
	entries: { LeaderboardEntry },
	updatedAt: number,
	-- False when the data store is unreachable and the cached copy is shown.
	live: boolean,
}

export type PartySnapshot = {
	-- Display names, leader first. Empty when not in a party.
	members: { string },
	leader: string?,
}

-- Result of any request that changes saved data (buy, claim, redeem).
export type ActionResult = {
	action: string,
	ok: boolean,
	code: string,
	id: string?,
}

export type SandboxConfig = {
	loadout: { string },
	wave: number,
	mutations: { [string]: number },
	speed: number,
}

export type SandboxState = {
	active: boolean,
	config: SandboxConfig,
}

-- Rating change after a ranked match, shown on the result screen.
export type RankResult = {
	ratingKey: string,
	before: number,
	after: number,
	won: boolean,
	note: string?,
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

-- Live status of one mode's pad, broadcast to everyone in the lobby.
export type QueueBoardEntry = {
	modeId: string,
	-- Players currently queued (standing, or carried by their party leader).
	count: number,
	-- Players needed for one match.
	matchSize: number,
	countdownEndsAt: number?,
	-- Seconds, from recent matches (or the config estimate before any).
	estimatedWait: number,
}

-- Per-player queue feedback the server decides (e.g. a party that is too large).
export type QueueNotice = {
	modeId: string,
	reason: string,
}

export type QueueSnapshot = {
	modeId: string?,
	count: number,
	matchSize: number,
	countdownEndsAt: number?,
	-- True while carried into the queue by a party leader rather than standing on the pad.
	viaParty: boolean,
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

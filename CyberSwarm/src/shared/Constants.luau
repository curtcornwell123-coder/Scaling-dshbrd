--!strict
--[[
	Constants
	Engineering constants: names, tags, timings for infrastructure, layout offsets, and error codes.
	Gameplay balance (health, damage, costs, rewards, wave sizes) does NOT belong here; it lives in
	the Config modules so designers can tune it without touching code.
]]

local Constants = {}

Constants.GAME_NAME = "Cyber Swarm"

Constants.REMOTES_FOLDER = "CyberSwarmRemotes"

-- Loadouts are capped by the design spec, so this is a rule rather than a balance number.
Constants.MAX_LOADOUT = 5

Constants.Tags = {
	QueuePad = "CyberSwarm_QueuePad",
	QueueBoard = "CyberSwarm_QueueBoard",
	Robot = "CyberSwarm_Robot",
	Tower = "CyberSwarm_Tower",
	EnemyBase = "CyberSwarm_EnemyBase",
	ActiveMap = "CyberSwarm_ActiveMap",
	-- Lobby world (built by World/Lobby). Clients find these to render screens and run prompts.
	WorldScreen = "CyberSwarm_WorldScreen",
	BlastDoor = "CyberSwarm_BlastDoor",
	TroopTable = "CyberSwarm_TroopTable",
	Spinner = "CyberSwarm_Spinner",
	Terminal = "CyberSwarm_Terminal",
	PartyPad = "CyberSwarm_PartyPad",
	TestRealmPortal = "CyberSwarm_TestRealmPortal",
	TestRealmReturn = "CyberSwarm_TestRealmReturn",
}

Constants.Attributes = {
	ModeId = "ModeId",
	-- Radius of a queue pad's standing zone, in studs (falls back to half the pad's footprint).
	QueueRadius = "QueueRadius",
	MatchId = "MatchId",
	TowerId = "TowerId",
	RobotId = "RobotId",
	-- Which client-rendered screen a WorldScreen part shows (see WorldScreensController).
	Screen = "Screen",
	TableIndex = "TableIndex",
	TroopId = "TroopId",
	-- What a Terminal prompt opens on the client: "Loadout", "Code", "RobuxShop", "Pass", "Supply".
	Terminal = "Terminal",
	-- "Form" or "Leave" for party pads.
	PartyAction = "PartyAction",
	Board = "Board",
	-- Spinner speed in degrees per second.
	SpinSpeed = "SpinSpeed",
}

-- Screens rendered on world parts tagged WorldScreen.
Constants.ScreenKind = {
	Tasks = "Tasks",
	Supply = "Supply",
	Code = "Code",
	-- Uses the Board attribute (a LeaderboardSnapshot board id).
	Leaderboard = "Leaderboard",
	Event = "Event",
	Rotation = "Rotation",
	-- Duels Hall: one per bay (ModeId attribute), the hall-wide rank card, and the DUELS plate.
	Bay = "Bay",
	LimitedBay = "LimitedBay",
	DuelsStatus = "DuelsStatus",
	RankCard = "RankCard",
	-- Troop Depot: table plates (TableIndex attribute) and the coin/gem counter.
	Table = "Table",
	Currency = "Currency",
	Pass = "Pass",
	Party = "Party",
	TestRealm = "TestRealm",
}

-- Folder and part names that every map template must follow (documented in README.md).
Constants.MapLayout = {
	WAYPOINTS = "Waypoints",
	WAYPOINT_PREFIX = "Waypoint_",
	LANE_PREFIX = "Lane_",
	TOWER_SLOTS = "TowerSlots",
	TOWER_SLOT_PREFIX = "TowerSlot_",
	BASE_SPAWN = "BaseSpawn",
	PLAYER_SPAWNS = "PlayerSpawns",
	CAMERA = "Camera",
	UNITS_FOLDER = "Units",
	MAPS_FOLDER = "Maps",
	ASSETS_FOLDER = "Assets",
}

Constants.Data = {
	STORE_NAME = "CyberSwarm_PlayerData",
	KEY_PREFIX = "Player_",
	SCHEMA_VERSION = 2,
	-- Receipt ids kept for idempotency; Roblox stops re-delivering a receipt once it is granted.
	PURCHASE_HISTORY = 200,
	AUTOSAVE_INTERVAL = 60,
	MAX_ATTEMPTS = 5,
	RETRY_BASE_DELAY = 1,
	-- A live server refreshes its lock on every autosave, so a lock older than three autosaves is from a dead server.
	SESSION_LOCK_TIMEOUT = 180,
	BIND_TO_CLOSE_TIMEOUT = 25,
	SAVE_WAIT_TIMEOUT = 15,
}

Constants.World = {
	LOBBY_ORIGIN = Vector3.new(0, 100, 0),
	MAP_ORIGIN = Vector3.new(1200, 100, 0),
	-- Each concurrent arena gets its own slot this far apart so matches never overlap.
	MAP_SPACING = 600,
	ROBOT_LEG_HEIGHT = 0.8,
	FLYER_BOB_HEIGHT = 0.35,
	FLYER_BOB_SPEED = 3,
	PLAYER_SPAWN_LIFT = 3,
}

Constants.Match = {
	WAITING_DURATION = 2,
	STATE_SYNC_INTERVAL = 0.15,
	HEALTH_BAR_FLUSH_INTERVAL = 0.2,
	MIN_FIRE_RATE = 0.05,
}

Constants.Queue = {
	-- Pad checks run on the server this often; it must be well under LEAVE_GRACE.
	TICK = 0.1,
	-- Seconds a player may be off their pad (jitter, a bump) before they leave the queue.
	LEAVE_GRACE = 0.3,
	-- Height above the pad that still counts as standing on it, so jumping in place keeps your spot.
	PAD_VERTICAL_TOLERANCE = 12,
	RING_SEGMENTS = 24,
}

Constants.Camera = {
	FIELD_OF_VIEW = 50,
	TWEEN_TIME = 0.9,
	-- Fallback framing when a map has no Camera part: distance scales with the map's footprint.
	HEIGHT_FACTOR = 0.55,
	BACK_FACTOR = 0.5,
}

Constants.Debug = {
	STUDIO_COMMANDS_ENABLED = true,
	RUN_TESTS_IN_STUDIO = true,
	COMMAND_PREFIX = "/cs",
}

-- Each ability kind is implemented in RobotService; these are the numeric fields it reads.
Constants.ABILITY_FIELDS = {
	Heal = { "radius", "amount", "interval" },
	Disable = { "radius", "duration", "cooldown" },
	Explode = { "triggerRadius", "radius", "damage" },
	Guard = { "radius", "reduction" },
	Strike = { "radius", "damage", "cooldown" },
	Boost = { "radius", "amount", "duration", "interval" },
	Bombard = { "radius", "damage", "cooldown" },
	Stealth = { "duration", "cooldown" },
} :: { [string]: { string } }

Constants.IMMUNITIES = { "Stun", "Slow" }

Constants.Lobby = {
	-- Seconds a player must stand on the Test Realm portal or return pad before it triggers.
	PAD_DWELL = 0.6,
	PAD_TICK = 0.2,
	PORTAL_COOLDOWN = 8,
	TELEPORT_ATTEMPTS = 3,
	-- Players standing on the party pad together this long form a party.
	PARTY_FORM_TIME = 2.5,
	MAX_PARTY = 4,
	BLAST_DOOR_OPEN_TIME = 4,
	SANDBOX_ARRIVAL_WAIT = 2,
}

Constants.Leaderboard = {
	-- OrderedDataStore names. Ranked boards append the ranked season id and rating key.
	WIN_STREAK_STORE = "CyberSwarm_LB_WinStreak",
	RANKED_STORE_PREFIX = "CyberSwarm_LB_Rank_",
	REFRESH_INTERVAL = 120,
	SIZE = 10,
	-- Board ids sent to clients.
	WIN_STREAK = "WinStreak",
}

Constants.TestRealm = {
	PROGRESS_STORE = "CyberSwarm_TestRealmProgress",
	FLUSH_INTERVAL = 15,
	-- Teleport data marker so a reserved server knows it is a Test Realm.
	TELEPORT_TAG = "CyberSwarmTestRealm",
	MAX_WAVE = 50,
	MIN_SPEED = 0.5,
	MAX_SPEED = 3,
	MAX_MUTATION_STACKS = 10,
}

Constants.Nameplate = {
	NAME = "CyberSwarmNameplate",
	MAX_DISTANCE = 60,
}

Constants.Receipts = {
	-- How long ProcessReceipt waits for a just-joined player's data before deferring the receipt.
	PROFILE_WAIT = 10,
}

-- Every tower stat the resolver knows about. Mutation modifiers may only target these names.
Constants.TOWER_STATS = {
	"damage",
	"fireRate",
	"range",
	"maxHealth",
	"splashRadius",
	"slowDuration",
	"armorHits",
	"empStun",
	"chainCount",
	"regenPerSecond",
	"magnet",
}

Constants.ErrorCode = {
	NotInMatch = "NOT_IN_MATCH",
	WrongPhase = "WRONG_PHASE",
	InvalidRobot = "INVALID_ROBOT",
	NotEquipped = "NOT_EQUIPPED",
	InvalidLane = "INVALID_LANE",
	WaveFull = "WAVE_FULL",
	NotEnoughCoins = "NOT_ENOUGH_COINS",
	MaxLevel = "MAX_LEVEL",
	InvalidLoadout = "INVALID_LOADOUT",
	RobotLocked = "ROBOT_LOCKED",
	AlreadyUnlocked = "ALREADY_UNLOCKED",
	InvalidMode = "INVALID_MODE",
	DataNotLoaded = "DATA_NOT_LOADED",
	NoMapAvailable = "NO_MAP_AVAILABLE",
	MatchFailed = "MATCH_FAILED",
	Busy = "BUSY",
	UnknownTroop = "UNKNOWN_TROOP",
	NotInStock = "NOT_IN_STOCK",
	AlreadyOwned = "ALREADY_OWNED",
	ComingSoon = "COMING_SOON",
	RequirementNotMet = "REQUIREMENT_NOT_MET",
	NotEnoughGems = "NOT_ENOUGH_GEMS",
	Sandbox = "SANDBOX",
	QuestUnknown = "QUEST_UNKNOWN",
	QuestIncomplete = "QUEST_INCOMPLETE",
	AlreadyClaimed = "ALREADY_CLAIMED",
	SupplyLimit = "SUPPLY_LIMIT",
	SupplyCooldown = "SUPPLY_COOLDOWN",
	CodeInvalid = "CODE_INVALID",
	CodeExpired = "CODE_EXPIRED",
	CodeUsed = "CODE_USED",
	TierLocked = "TIER_LOCKED",
	PremiumRequired = "PREMIUM_REQUIRED",
	SeasonEnded = "SEASON_ENDED",
	InvalidRequest = "INVALID_REQUEST",
	TeleportFailed = "TELEPORT_FAILED",
	MatchStartFailed = "MATCH_START_FAILED",
	PartyTooLarge = "PARTY_TOO_LARGE",
	Ok = "OK",
}

Constants.NoticeText = {
	NOT_IN_MATCH = "You are not in a match.",
	WRONG_PHASE = "You can only do that between waves.",
	INVALID_ROBOT = "That robot does not exist.",
	NOT_EQUIPPED = "That robot is not in your loadout.",
	INVALID_LANE = "That lane does not exist.",
	WAVE_FULL = "Your swarm is full for this wave.",
	NOT_ENOUGH_COINS = "Not enough coins.",
	MAX_LEVEL = "That robot is already max level.",
	INVALID_LOADOUT = "That loadout is not allowed.",
	ROBOT_LOCKED = "That robot is not available yet.",
	ALREADY_UNLOCKED = "You already own that robot.",
	INVALID_MODE = "That mode is not available.",
	DATA_NOT_LOADED = "Your data is still loading.",
	NO_MAP_AVAILABLE = "No map is available for that mode.",
	MATCH_FAILED = "The match could not start. Please try again.",
	BUSY = "Hold on, your last request is still processing.",
	UNKNOWN_TROOP = "That troop does not exist.",
	NOT_IN_STOCK = "That troop is not in the depot today.",
	ALREADY_OWNED = "You already own that troop.",
	COMING_SOON = "That troop is coming soon.",
	REQUIREMENT_NOT_MET = "You have not met the unlock requirement yet.",
	NOT_ENOUGH_GEMS = "Not enough gems.",
	SANDBOX = "Nothing can be earned or bought in the Test Realm.",
	QUEST_UNKNOWN = "That task is not active today.",
	QUEST_INCOMPLETE = "That task is not finished yet.",
	ALREADY_CLAIMED = "Already claimed.",
	SUPPLY_LIMIT = "No supply drops left today. Back after the daily reset.",
	SUPPLY_COOLDOWN = "The next supply drop is not ready yet.",
	CODE_INVALID = "That code does not exist.",
	CODE_EXPIRED = "That code has expired.",
	CODE_USED = "You already redeemed that code.",
	TIER_LOCKED = "You have not reached that tier yet.",
	PREMIUM_REQUIRED = "That reward needs the premium pass.",
	SEASON_ENDED = "This season has ended.",
	INVALID_REQUEST = "That request was not valid.",
	TELEPORT_FAILED = "Could not reach the Test Realm. Please try again.",
	MATCH_START_FAILED = "The match could not start. You are back in the Duels Hall with no penalty.",
	PARTY_TOO_LARGE = "Your party is too large for that mode.",
	TROOP_PURCHASED = "Troop unlocked!",
	REWARD_CLAIMED = "Reward claimed!",
	SUPPLY_CLAIMED = "Supply drop claimed!",
	CODE_REDEEMED = "Code redeemed!",
	ROBOT_UNLOCKED = "Robot unlocked!",
	LOADOUT_MIN = "Keep at least one robot equipped.",
	LOADOUT_FULL = "Your loadout is full. Unequip a robot first.",
	BUY_IN_ARMORY = "Unlock this robot in the Armory first.",
} :: { [string]: string }

Constants.MatchEndText = {
	BaseDestroyed = "The enemy Command HQ was destroyed!",
	RivalDestroyedBase = "Your rival destroyed their HQ first.",
	OutOfCoins = "Your swarm ran out of coins and robots.",
	RivalOutOfCoins = "Your rival's swarm ran out of coins.",
	WaveLimit = "The defense held out until the wave limit.",
	RivalLeft = "Your rival left the match.",
} :: { [string]: string }

return Constants

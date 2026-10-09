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
	Robot = "CyberSwarm_Robot",
	Tower = "CyberSwarm_Tower",
	EnemyBase = "CyberSwarm_EnemyBase",
	ActiveMap = "CyberSwarm_ActiveMap",
}

Constants.Attributes = {
	ModeId = "ModeId",
	MatchId = "MatchId",
	TowerId = "TowerId",
	RobotId = "RobotId",
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
	SCHEMA_VERSION = 1,
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
	TICK = 0.25,
	PAD_VERTICAL_TOLERANCE = 8,
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
} :: { [string]: { string } }

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
	AlreadyInMatch = "ALREADY_IN_MATCH",
	DataNotLoaded = "DATA_NOT_LOADED",
	NoCharacter = "NO_CHARACTER",
	NoMapAvailable = "NO_MAP_AVAILABLE",
	MatchFailed = "MATCH_FAILED",
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
	ALREADY_IN_MATCH = "You are already in a match.",
	DATA_NOT_LOADED = "Your data is still loading.",
	NO_CHARACTER = "Wait for your character to spawn.",
	NO_MAP_AVAILABLE = "No map is available for that mode.",
	MATCH_FAILED = "The match could not start. Please try again.",
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

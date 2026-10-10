--!strict
-- Chaos Golf: every tunable number in the game lives here.
-- Economy rationale and the Robux price sheet are in docs/Monetization.md.

local Config = {}

Config.DataStoreName = "ChaosGolf_v1"
Config.StartingCoins = 250

-- Ball -------------------------------------------------------------------

Config.Ball = {
	Diameter = 1.5,
	-- Upload assets/mesh/golfball.obj (Studio > Asset Manager > Bulk Import) and paste the
	-- asset id here, e.g. "rbxassetid://1234567890". Empty = smooth placeholder sphere.
	MeshId = "",
	MeshScale = Vector3.new(1, 1, 1),
	Density = 2.2,
	Friction = 0.25,
	Elasticity = 0.5,
}

Config.Physics = {
	MaxShotSpeed = 95, -- studs/s at 100% power, before the Power upgrade
	MinPower = 0.06,
	RollResistance = 10, -- constant deceleration while grounded (studs/s^2)
	Drag = 0.55, -- proportional deceleration while grounded (1/s)
	RestSpeed = 1.1, -- below this (and grounded) for RestTime the ball is at rest
	RestTime = 0.35,
	MaxRollTime = 25, -- safety: a ball still moving after this is settled where it is
	GroundProbe = 1.25,
	SandMultiplier = 4.5,
	IceMultiplier = 0.2,
	BoostSpeed = 70,
	CupRadius = 1.3,
	CupMagnetRadius = 7,
	MaxSinkSpeed = 24, -- faster than this and the ball lips out
	OOBDepth = 7, -- falling this far below the lowest floor of a hole = out of bounds
	PowerCycleSeconds = 1.6, -- full 0 -> 1 -> 0 sweep of the power meter
}

-- Permanent stat upgrades (East room terminal). Disabled in Ranked 1v1.
Config.Upgrades = {
	MaxLevel = 5,
	Costs = { 400, 900, 1800, 3500, 6500 },
	Stats = {
		{ Id = "Power", Name = "Power", Desc = "Max shot speed", PerLevel = 0.05 },
		{ Id = "Control", Name = "Control", Desc = "Grip on slopes & ice, steadier power meter", PerLevel = 0.08 },
		{ Id = "Bounce", Name = "Bounce", Desc = "Rail rebound energy", PerLevel = 0.06 },
	},
}

-- Match modes ------------------------------------------------------------

export type ModeDef = {
	Id: string,
	Display: string,
	Short: string,
	MinPlayers: number,
	MaxPlayers: number,
	Holes: number,
	Simultaneous: boolean,
	BallCollide: boolean,
	ChaosBoxes: boolean,
	StartAbilities: { string }?, -- fixed loadout (Ranked); nil = random
	StartRandomAbilities: number,
	Countdown: number, -- seconds to wait for more players once MinPlayers is reached
	TurnTime: number?,
	FinishWindow: number?, -- Race: seconds the others get after the first ball sinks
	Upgrades: boolean,
	Ranked: boolean,
	Color: Color3,
}

Config.Modes = {
	Ranked = {
		Id = "Ranked",
		Display = "RANKED 1V1",
		Short = "Ranked",
		MinPlayers = 2,
		MaxPlayers = 2,
		Holes = 6,
		Simultaneous = true,
		BallCollide = false,
		ChaosBoxes = false,
		StartAbilities = { "Mulligan", "Magnet" },
		StartRandomAbilities = 0,
		Countdown = 0,
		Upgrades = false,
		Ranked = true,
		Color = Color3.fromRGB(255, 196, 0),
	},
	Classic = {
		Id = "Classic",
		Display = "CLASSIC · TURN-BASED",
		Short = "Classic",
		MinPlayers = 2,
		MaxPlayers = 4,
		Holes = 6,
		Simultaneous = false,
		BallCollide = true,
		ChaosBoxes = true,
		StartRandomAbilities = 1,
		Countdown = 20,
		TurnTime = 25,
		Upgrades = true,
		Ranked = false,
		Color = Color3.fromRGB(0, 200, 255),
	},
	Race = {
		Id = "Race",
		Display = "RACE · CHAOS",
		Short = "Race",
		MinPlayers = 2,
		MaxPlayers = 8,
		Holes = 6,
		Simultaneous = true,
		BallCollide = true,
		ChaosBoxes = true,
		StartRandomAbilities = 1,
		Countdown = 25,
		FinishWindow = 30,
		Upgrades = true,
		Ranked = false,
		Color = Color3.fromRGB(255, 0, 160),
	},
} :: { [string]: ModeDef }

Config.ModeOrder = { "Ranked", "Classic", "Race" }

-- In Studio a single tester can start any mode alone.
Config.StudioSoloMatches = true

Config.Match = {
	HoleTimeLimit = 120,
	StrokeCapOverPar = 4, -- strokes are capped at par + this
	MaxAbilities = 2,
	IntroSeconds = 4,
	ScorecardSeconds = 5,
	ResultsSeconds = 8,
	RacePoints = { 10, 8, 6, 5, 4, 3, 2, 1 },
}

-- Rewards (Coins) ----------------------------------------------------------

Config.Rewards = {
	Participation = 25,
	PerHole = 3,
	Birdie = 10, -- per hole finished under par
	HoleInOne = 50,
	SabotageHit = 4,
	SabotageCap = 40,
	Ranked = { Win = 120, Draw = 70, Loss = 40 },
	Classic = { 150, 90, 60, 40 },
	Race = { 180, 140, 110, 90, 75, 60, 50, 40 },
}

-- Standing in a matchmaking bubble pays out on a rising schedule.
Config.QueueRewards = {
	{ UpTo = 60, Amount = 1, Every = 30 },
	{ UpTo = 120, Amount = 2, Every = 20 },
	{ UpTo = math.huge, Amount = 5, Every = 15 },
}

Config.FriendBoost = 0.15 -- +15% match coins while a Roblox friend is in the server

-- Lobby systems ------------------------------------------------------------

Config.Voting = {
	Choices = 3,
	IdleReroll = 150, -- reshuffle the three signs if nobody voted for this long
}

Config.Leaderboards = {
	RefreshInterval = 60,
	FlushInterval = 90,
	PodiumInterval = 20,
	PageSize = 10,
	MaxEntries = 50,
}

Config.Practice = {
	RotationSeconds = 20 * 60,
	Lanes = 5,
}

Config.Ranked = {
	StartMMR = 1000,
	K = 32,
	PlacementK = 48,
	PlacementMatches = 5,
}

-- Mythic featured crate: one global stock shared by every server.
Config.Mythic = {
	Season = "S1",
	GlobalCap = 10000,
	CoinPrice = 6000,
	StockRefresh = 30,
}

-- Monetization ------------------------------------------------------------
-- Create these in the Creator Dashboard and paste the ids. 0 = not configured yet:
-- the kiosk shows "COMING SOON" and nothing can be bought.

export type ProductDef = { Id: number, Robux: number, Coins: number?, Name: string }
export type PassDef = { Id: number, Robux: number, Name: string, Desc: string }

Config.DevProducts = {
	Coins1 = { Id = 0, Robux = 49, Coins = 1000, Name = "Coin Pouch" },
	Coins2 = { Id = 0, Robux = 149, Coins = 3500, Name = "Coin Sack" },
	Coins3 = { Id = 0, Robux = 399, Coins = 10000, Name = "Coin Chest" },
	Coins4 = { Id = 0, Robux = 999, Coins = 28000, Name = "Coin Vault" },
	MythicCrate = { Id = 0, Robux = 99, Name = "Mythic Featured Crate" },
} :: { [string]: ProductDef }

Config.GamePasses = {
	VIP = { Id = 0, Robux = 249, Name = "VIP", Desc = "+10% Coins, VIP Aurum skin, gold nametag" },
	DoubleCoins = { Id = 0, Robux = 399, Name = "2x Coins", Desc = "Double Coins from every match" },
	Celebrations = { Id = 0, Robux = 149, Name = "Celebration Pack", Desc = "3 exclusive cup-sink celebrations" },
	Founder = { Id = 0, Robux = 99, Name = "Founder", Desc = "Founder skin + Founder title (launch only)" },
} :: { [string]: PassDef }

Config.GamePassOrder = { "VIP", "DoubleCoins", "Celebrations", "Founder" }

-- Cup-sink celebrations. Everything except Default needs the Celebrations pass.
Config.Celebrations = { "Default", "Fireworks", "Galaxy", "Confetti" }
Config.VIPBoost = 0.10

-- Creator codes. Sales made while a code is active are logged to the
-- CreatorSales DataStore so you can pay creators out manually.
Config.CreatorCodes = {
	CHAOS = { Name = "Chaos Golf Team", UserId = 0 },
} :: { [string]: { Name: string, UserId: number } }
Config.CreatorFanSkin = "creator_fan"

-- Look & feel ------------------------------------------------------------

Config.Colors = {
	North = Color3.fromHex("#FF6B00"),
	East = Color3.fromHex("#00FF66"),
	South = Color3.fromHex("#FF00A0"),
	West = Color3.fromHex("#00E5FF"),
	Gold = Color3.fromRGB(255, 200, 40),
	Panel = Color3.fromRGB(24, 28, 36),
	PanelLight = Color3.fromRGB(42, 48, 62),
	Text = Color3.fromRGB(240, 243, 248),
	Muted = Color3.fromRGB(148, 158, 178),
	Good = Color3.fromRGB(46, 212, 122),
	Bad = Color3.fromRGB(235, 87, 87),
}

Config.Font = Enum.Font.GothamBlack
Config.FontBody = Enum.Font.GothamBold

-- 2D UI. All kiosks are in-world SurfaceGuis ("World", zero-overlay mandate).
-- "Screen" opens the same shop grid as a centred overlay when a kiosk prompt is used.
Config.UI = {
	ShopMode = "World", -- "World" | "Screen"
}

-- Built-in engine sounds (always available, no uploads needed).
Config.Sounds = {
	Putt = "rbxasset://sounds/swoosh.wav",
	Sink = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/clickfast.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Win = "rbxasset://sounds/victory.wav",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Bonk = "rbxasset://sounds/collide.wav",
}

return Config

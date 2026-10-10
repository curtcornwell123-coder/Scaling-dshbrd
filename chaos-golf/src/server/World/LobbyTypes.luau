--!strict
-- Contract between LobbyBuilder (geometry) and the lobby services (behaviour).
-- LobbyBuilder only builds parts; services add prompts, SurfaceGuis and logic.
--
-- Conventions
--  * Lobby floor top surface is Y = 0. Fountain centre is (0, 0, 0).
--  * Compass: North = -Z, South = +Z, East = +X, West = -X.
--  * "Screen" parts: the display face is Enum.NormalId.Front (the part's
--    LookVector points toward the viewer standing in front of it).
--  * Pedestals / podiums contain an Attachment named "Display" whose
--    WorldPosition is where the showcased ball (3 studs wide) is centred.
--  * Pads / bubbles carry a number attribute "Radius"; a player is inside when
--    their HumanoidRootPart is within Radius (horizontal distance) of the part's
--    Position and less than 10 studs above it (bubbles: 3D distance < Radius).
--  * Buttons are plain parts; services parent ProximityPrompts to them.

export type Portal = {
	Bubble: BasePart, -- queue zone (attribute Radius)
	Sign: BasePart, -- status screen above the portal
}

export type VoteSign = {
	Display: BasePart, -- holographic screen
	Pad: BasePart, -- floor pad in front (attribute Radius)
}

export type Lane = {
	Origin: CFrame, -- floor-level centre of the lane start, LookVector runs down the lane
	Length: number,
	Width: number,
	StartPad: BasePart, -- step on to play (attribute Radius); sits just behind Origin
	Props: Folder, -- empty folder: Practice builds the active minigame's props in here
	Screen: BasePart, -- small per-lane score screen
}

export type Board = {
	Panel: BasePart, -- leaderboard screen (Front face)
	Prev: BasePart, -- arrow buttons
	Next: BasePart,
	Period: BasePart, -- Daily / Weekly / All-Time toggle
	Podium: BasePart, -- spinning showcase of the leader's ball (Display attachment)
	Nameplate: BasePart, -- screen under the podium for the leader's name
}

export type Lobby = {
	Model: Model,
	Spawn: SpawnLocation,
	SpawnCFrame: CFrame, -- character CFrame on spawn, facing south toward the fountain
	Directory: {
		Sign: BasePart, -- solid (non-neon) 4-way direction sign in front of spawn
		StandPoint: Vector3, -- where the first-join arrow leads
	},
	Daily: { Screen: BasePart, Button: BasePart }, -- 14-day login calendar near spawn
	North: {
		Portals: { [string]: Portal }, -- keys: "Ranked", "Classic", "Race"
		VoteSigns: { VoteSign }, -- exactly 3
		VoteHeader: BasePart, -- screen above the vote signs (round timer / title)
		InviteKiosk: BasePart, -- Invite Friends terminal
	},
	East: {
		SkinPedestals: { BasePart }, -- 12 coin-shop pedestals (Display attachment)
		CratePedestals: { [string]: BasePart }, -- "Skins", "Trails", "Knockouts", "Arrows"
		CrateScreens: { [string]: BasePart }, -- odds boards behind each crate pedestal (same keys)
		Locker: { Pedestal: BasePart, Screen: BasePart, Prev: BasePart, Next: BasePart, Equip: BasePart }, -- Screen ≈14x8: catalog terminal
		Upgrades: { Screen: BasePart, Buttons: { [string]: BasePart } }, -- buttons: "Power", "Control", "Bounce"
		CreatorKiosk: { Screen: BasePart },
		Mythic: { Pedestal: BasePart, Counter: BasePart, OddsBoard: BasePart },
		PassPedestals: { [string]: BasePart }, -- keys = Config.GamePassOrder (Display attachment)
		CoinPackPads: { [string]: BasePart }, -- keys "Coins1".."Coins4"
	},
	South: {
		Lanes: { Lane },
		RotationSign: BasePart, -- big screen: active minigame + countdown
		TokenKiosk: { Screen: BasePart, CratePedestal: BasePart, SkinPedestals: { BasePart } }, -- 4 skin pedestals
		TutorialPad: BasePart, -- replay tutorial (attribute Radius)
	},
	West: {
		Boards: { [string]: Board }, -- keys "Wins", "Coins", "Sabotages"
	},
}

return {}

--!strict
--[[
	Theme
	The single source of truth for the game's look. The player's robot swarm and the UI use cyan and
	magenta accents on deep navy; the AI defense uses a military palette (olive, khaki, gunmetal,
	warning red) so the two sides read instantly. The lobby world uses solid painted-metal tones
	(Theme.World) with glow kept to small accents. Server world parts and client UI both read here.
]]

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(7, 9, 18),
	Panel = Color3.fromRGB(14, 18, 34),
	PanelLight = Color3.fromRGB(24, 30, 54),
	PanelDark = Color3.fromRGB(5, 6, 12),
	Primary = Color3.fromRGB(64, 196, 226),
	Secondary = Color3.fromRGB(214, 78, 166),
	Text = Color3.fromRGB(236, 244, 255),
	TextDim = Color3.fromRGB(136, 150, 184),
	Success = Color3.fromRGB(86, 214, 146),
	Warning = Color3.fromRGB(236, 190, 84),
	Danger = Color3.fromRGB(230, 86, 100),
	Metal = Color3.fromRGB(28, 32, 46),
	MetalDark = Color3.fromRGB(16, 18, 28),
	Ground = Color3.fromRGB(18, 20, 30),
}

-- Lobby facility: stylized low-poly concrete and steel. Glow lives in signs and trim only.
Theme.World = {
	Concrete = Color3.fromRGB(180, 176, 166), -- warm light grey #B4B0A6
	ConcreteMid = Color3.fromRGB(140, 138, 132), -- mid grey #8C8A84
	Steel = Color3.fromRGB(42, 44, 47), -- dark steel #2A2C2F
	SteelLight = Color3.fromRGB(70, 73, 78),
	Hazard = Color3.fromRGB(242, 193, 0), -- hazard yellow #F2C100
	HazardBlack = Color3.fromRGB(24, 24, 26),
	Floor = Color3.fromRGB(150, 147, 139),
	FloorSeam = Color3.fromRGB(122, 120, 114),
	Screen = Color3.fromRGB(18, 21, 28),
	RingUnlit = Color3.fromRGB(60, 62, 66),
	RingLocked = Color3.fromRGB(214, 52, 52),
	Glass = Color3.fromRGB(120, 200, 230),
	Stencil = Color3.fromRGB(46, 48, 52),
	Curtain = Color3.fromRGB(150, 24, 34),
	GreenScreen = Color3.fromRGB(40, 178, 72),
	EmblemRed = Color3.fromRGB(196, 40, 40),
	EmblemWhite = Color3.fromRGB(236, 232, 224),
}

-- Neon accent per lobby area.
Theme.Areas = {
	HubRing = Color3.fromRGB(242, 193, 0),
	HubRingAccent = Color3.fromRGB(64, 196, 226),
	Duels = Color3.fromRGB(236, 240, 246),
	DuelsGold = Color3.fromRGB(242, 193, 0),
	DuelsPurple = Color3.fromRGB(150, 84, 230),
	Troops = Color3.fromRGB(150, 84, 230),
	TestRealm = Color3.fromRGB(64, 210, 236),
	Market = Color3.fromRGB(242, 178, 40),
	Party = Color3.fromRGB(86, 214, 146),
	Armory = Color3.fromRGB(242, 193, 0),
}

-- Military palette for towers, the enemy HQ, and battlefield props.
Theme.Military = {
	Olive = Color3.fromRGB(78, 90, 50),
	OliveDark = Color3.fromRGB(52, 60, 34),
	Khaki = Color3.fromRGB(150, 136, 96),
	Sand = Color3.fromRGB(176, 158, 112),
	Gunmetal = Color3.fromRGB(46, 50, 54),
	Steel = Color3.fromRGB(88, 94, 100),
	AlertRed = Color3.fromRGB(255, 52, 40),
	Amber = Color3.fromRGB(255, 170, 30),
	Dirt = Color3.fromRGB(44, 40, 32),
}

Theme.RarityColors = {
	Common = Color3.fromRGB(150, 170, 200),
	Uncommon = Color3.fromRGB(86, 214, 146),
	Rare = Color3.fromRGB(64, 196, 226),
	Epic = Color3.fromRGB(176, 92, 255),
	Legendary = Color3.fromRGB(255, 202, 64),
	Mythic = Color3.fromRGB(214, 78, 166),
} :: { [string]: Color3 }

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Body = Enum.Font.GothamBold,
	Light = Enum.Font.GothamMedium,
}

Theme.Text = {
	TITLE_MAX = 48,
	HEADER_MAX = 30,
	BODY_MAX = 22,
	SMALL_MAX = 16,
}

Theme.CornerRadius = UDim.new(0, 12)
Theme.StrokeThickness = 2

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- UI motion is 0.2 s ease-out everywhere, never a bounce.
	Pop = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

function Theme.rarityColor(rarity: string): Color3
	return Theme.RarityColors[rarity] or Theme.Colors.Text
end

return Theme

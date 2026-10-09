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

-- Lobby hall: solid surfaces lit by the scene, not by glow.
Theme.World = {
	Floor = Color3.fromRGB(62, 66, 76),
	FloorSeam = Color3.fromRGB(48, 52, 60),
	Wall = Color3.fromRGB(92, 98, 110),
	WallPanel = Color3.fromRGB(116, 122, 136),
	Pillar = Color3.fromRGB(58, 62, 72),
	Trim = Color3.fromRGB(40, 44, 52),
	Beam = Color3.fromRGB(70, 74, 84),
	Stencil = Color3.fromRGB(226, 220, 200),
	RingUnlit = Color3.fromRGB(44, 48, 56),
	Screen = Color3.fromRGB(20, 24, 34),
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
	Normal = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

function Theme.rarityColor(rarity: string): Color3
	return Theme.RarityColors[rarity] or Theme.Colors.Text
end

return Theme

--!strict
-- Every cosmetic category in one registry. The player IS the ball, so all
-- cosmetics attach to the ball:
--   Skins      the ball itself (Skins.luau; Epic+ skins carry built-in auras)
--   Trails     ribbon left behind while rolling
--   Knockouts  effect played when your ball smashes into another ball, and a
--              bigger version when that hit knocks them out of bounds
--   Arrows     the aiming / launch indicator arrow
-- Sources: "Crate" (category crate in the shop), "Login" (14-day calendar),
-- "Default" (everyone owns it).

local Skins = require(script.Parent:WaitForChild("Skins"))

local Cosmetics = {}

export type Category = "Skins" | "Trails" | "Knockouts" | "Arrows"

Cosmetics.Categories = { "Skins", "Trails", "Knockouts", "Arrows" } :: { Category }

Cosmetics.CategoryInfo = {
	Skins = { Name = "Ball Skins", Singular = "Ball Skin", Color = Color3.fromHex("#3D8BFF") },
	Trails = { Name = "Ball Trails", Singular = "Trail", Color = Color3.fromHex("#00E5FF") },
	Knockouts = { Name = "Knockout Effects", Singular = "Knockout Effect", Color = Color3.fromHex("#FF5A36") },
	Arrows = { Name = "Arrow Skins", Singular = "Arrow Skin", Color = Color3.fromHex("#FFC83D") },
} :: { [string]: { Name: string, Singular: string, Color: Color3 } }

export type Item = {
	Id: string,
	Name: string,
	Rarity: Skins.Rarity,
	Source: string,
	Order: number,
	Color: Color3,
	-- Trails
	Colors: { Color3 }?,
	Width: number?,
	Lifetime: number?,
	Glow: number?, -- LightEmission
	Sparks: boolean?,
	-- Knockouts
	Style: string?, -- Knockouts: Burst | Stars | Ring | Confetti | Shatter | Lightning | Flames | Vortex | Nova
	Scale: number?, -- Arrows: Classic | Chevron | Dotted | Laser | Comet | Rainbow
	-- Arrows
	Tip: Color3?,
	Neon: boolean?,
	Pulse: boolean?,
}

local defs: { [string]: { Item } } = { Trails = {}, Knockouts = {}, Arrows = {} }

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local function add(category: string, item: { [string]: any })
	local list = defs[category]
	item.Order = #list + 1
	table.insert(list, item :: any)
end

-- Trails ---------------------------------------------------------------------
local function trail(id: string, name: string, rarity: string, source: string, colors: { string }, width: number, lifetime: number, glow: number, sparks: boolean?)
	local cs = {}
	for _, c in colors do
		table.insert(cs, hex(c))
	end
	add("Trails", { Id = id, Name = name, Rarity = rarity, Source = source, Color = cs[1], Colors = cs, Width = width, Lifetime = lifetime, Glow = glow, Sparks = sparks })
end

trail("none", "No Trail", "Common", "Default", { "#FFFFFF" }, 0, 0, 0)
trail("chalk", "Chalk Line", "Common", "Crate", { "#FFFFFF", "#DDE3EE" }, 0.5, 0.35, 0)
trail("mint_breeze", "Mint Breeze", "Common", "Crate", { "#7CF2B8", "#C9FFE6" }, 0.55, 0.4, 0.2)
trail("sunbeam", "Sunbeam", "Common", "Crate", { "#FFD93B", "#FFF3B0" }, 0.55, 0.4, 0.3)
trail("neon_ribbon", "Neon Ribbon", "Rare", "Crate", { "#00E5FF", "#0066FF" }, 0.6, 0.5, 0.8)
trail("bubblegum_pop", "Bubblegum Pop", "Rare", "Crate", { "#FF8BD1", "#FF4FA3" }, 0.6, 0.5, 0.6)
trail("lime_zip", "Lime Zip", "Rare", "Crate", { "#B5F53C", "#3CF57A" }, 0.6, 0.5, 0.7)
trail("fire_streak", "Fire Streak", "Epic", "Crate", { "#FFE14D", "#FF7A00", "#FF1E00" }, 0.75, 0.6, 1, true)
trail("frost_wake", "Frost Wake", "Epic", "Crate", { "#FFFFFF", "#9BE7FF", "#2F80ED" }, 0.75, 0.6, 0.9, true)
trail("toxic_drip", "Toxic Drip", "Epic", "Crate", { "#E6FF00", "#66FF00", "#008F3A" }, 0.75, 0.6, 1, true)
trail("rainbow_road", "Rainbow Road", "Legendary", "Crate", { "#FF0055", "#FF9A00", "#FFE600", "#00E676", "#00B0FF", "#B04DFF" }, 0.9, 0.75, 1, true)
trail("comet_tail", "Comet Tail", "Legendary", "Crate", { "#FFFFFF", "#FFE08A", "#FF9A3C" }, 1.1, 0.85, 1, true)
trail("chaos_rift", "Chaos Rift", "Mythic", "Crate", { "#FF0033", "#B000FF", "#14001F" }, 1.2, 1, 1, true)
trail("daily_spark", "Daily Spark", "Rare", "Login", { "#FFB347", "#FFE7A3" }, 0.65, 0.55, 0.9, true)

-- Knockout effects ---------------------------------------------------------------
local function knockout(id: string, name: string, rarity: string, source: string, style: string, color: string, scale: number)
	add("Knockouts", { Id = id, Name = name, Rarity = rarity, Source = source, Style = style, Color = hex(color), Scale = scale })
end

knockout("pop", "Pop", "Common", "Default", "Burst", "#FFFFFF", 1)
knockout("bonk_stars", "Bonk Stars", "Common", "Crate", "Stars", "#FFE14D", 1)
knockout("splash", "Splash", "Common", "Crate", "Ring", "#3BA7FF", 1)
knockout("confetti_blast", "Confetti Blast", "Rare", "Crate", "Confetti", "#FF4FA3", 1.1)
knockout("shockring", "Shockring", "Rare", "Crate", "Ring", "#00E5FF", 1.3)
knockout("ice_shatter", "Ice Shatter", "Epic", "Crate", "Shatter", "#BDF4FF", 1.2)
knockout("thunderclap", "Thunderclap", "Epic", "Crate", "Lightning", "#FFF27A", 1.3)
knockout("inferno", "Inferno", "Legendary", "Crate", "Flames", "#FF6A00", 1.5)
knockout("black_hole", "Black Hole", "Legendary", "Crate", "Vortex", "#7A00FF", 1.5)
knockout("supernova", "Supernova", "Mythic", "Crate", "Nova", "#FFD000", 1.8)
knockout("daily_fireworks", "Daily Fireworks", "Epic", "Login", "Confetti", "#FFB347", 1.4)

-- Arrow skins ---------------------------------------------------------------------
local function arrow(id: string, name: string, rarity: string, source: string, style: string, color: string, tip: string, neon: boolean, pulse: boolean?)
	add("Arrows", { Id = id, Name = name, Rarity = rarity, Source = source, Style = style, Color = hex(color), Tip = hex(tip), Neon = neon, Pulse = pulse })
end

arrow("classic", "Classic", "Common", "Default", "Classic", "#FFFFFF", "#FFFFFF", false)
arrow("tangerine", "Tangerine", "Common", "Crate", "Classic", "#FF9A3C", "#FFD08A", false)
arrow("mint_chevron", "Mint Chevron", "Common", "Crate", "Chevron", "#7CF2B8", "#FFFFFF", false)
arrow("dotted", "Dotted Line", "Common", "Crate", "Dotted", "#DDE3EE", "#FFFFFF", false)
arrow("cyber_laser", "Cyber Laser", "Rare", "Crate", "Laser", "#00E5FF", "#FFFFFF", true)
arrow("hot_chevron", "Hot Chevron", "Rare", "Crate", "Chevron", "#FF4FA3", "#FFD1E8", true)
arrow("gold_rush", "Gold Rush", "Epic", "Crate", "Classic", "#FFC83D", "#FFF3B0", true, true)
arrow("plasma_beam", "Plasma Beam", "Epic", "Crate", "Laser", "#7A00FF", "#00E5FF", true, true)
arrow("comet_path", "Comet Path", "Legendary", "Crate", "Comet", "#FFFFFF", "#FF9A3C", true, true)
arrow("rainbow_guide", "Rainbow Guide", "Legendary", "Crate", "Rainbow", "#FF0055", "#00B0FF", true, true)
arrow("chaos_pointer", "Chaos Pointer", "Mythic", "Crate", "Chevron", "#FF0033", "#FFB000", true, true)
arrow("sunrise_chevron", "Sunrise Chevron", "Epic", "Login", "Chevron", "#FF8A00", "#FFE14D", true, true)

-- Registry -------------------------------------------------------------------

local byId: { [string]: { [string]: Item } } = {}
for category, list in defs do
	local map = {}
	for _, item in list do
		assert(map[item.Id] == nil, "duplicate " .. category .. " id " .. item.Id)
		map[item.Id] = item
	end
	byId[category] = map
end

Cosmetics.Defaults = {
	Skins = Skins.Default,
	Trails = "none",
	Knockouts = "pop",
	Arrows = "classic",
} :: { [string]: string }

-- Unified view (Skins are adapted from Skins.luau).
function Cosmetics.list(category: string): { Item }
	if category == "Skins" then
		return Skins.List :: any
	end
	return defs[category] or {}
end

function Cosmetics.get(category: string, id: string?): Item?
	if not id then
		return nil
	end
	if category == "Skins" then
		return Skins.ById[id] :: any
	end
	local map = byId[category]
	return map and map[id]
end

function Cosmetics.getOrDefault(category: string, id: string?): Item
	return Cosmetics.get(category, id) or (Cosmetics.get(category, Cosmetics.Defaults[category]) :: Item)
end

function Cosmetics.withSource(category: string, source: string): { Item }
	local out = {}
	for _, item in Cosmetics.list(category) do
		if item.Source == source then
			table.insert(out, item)
		end
	end
	return out
end

function Cosmetics.isCategory(category: any): boolean
	return type(category) == "string" and Cosmetics.CategoryInfo[category] ~= nil
end

return Cosmetics

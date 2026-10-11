--!strict
-- Course registry. Every map is a 6-hole course generated deterministically from
-- its Seed by server/World/CourseBuilder, so a map always plays the same and
-- players can learn it. Add a map = add one entry (new seed and/or theme).
-- All maps have equal weight in the lobby vote rotation.

local Maps = {}

export type Theme = {
	Id: string,
	Name: string,
	Floor: Color3,
	FloorAlt: Color3,
	Rail: Color3,
	Trim: Color3, -- neon accents on rail tops, cups, pads
	Wall: Color3,
	WallAlt: Color3,
	Ceiling: Color3,
	Accent: Color3,
	Water: Color3,
	Sand: Color3,
	Ice: Color3,
	Light: Color3,
	Decor: string, -- decoration set the builder uses for props around the holes
}

export type MapDef = {
	Id: string,
	Name: string,
	Theme: string,
	Seed: number,
	Holes: number,
	Length: { number }, -- {min, max} tiles per hole (12-stud tiles)
	RampChance: number,
	Hazards: { [string]: number }, -- per-tile chance of each feature
	Difficulty: string,
	Blurb: string,
}

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

Maps.Themes = {
	Arcade = {
		Id = "Arcade",
		Name = "Neon Arcade",
		Floor = hex("#2B2F4A"),
		FloorAlt = hex("#343956"),
		Rail = hex("#1B1E33"),
		Trim = hex("#00E5FF"),
		Wall = hex("#15172A"),
		WallAlt = hex("#1F2240"),
		Ceiling = hex("#0E0F1C"),
		Accent = hex("#FF00A0"),
		Water = hex("#00B7FF"),
		Sand = hex("#E9C46A"),
		Ice = hex("#BDF4FF"),
		Light = hex("#9BE8FF"),
		Decor = "Arcade",
	},
	Candy = {
		Id = "Candy",
		Name = "Candy Clash",
		Floor = hex("#FFC4DD"),
		FloorAlt = hex("#FFD6E8"),
		Rail = hex("#FFFFFF"),
		Trim = hex("#FF4FA3"),
		Wall = hex("#FFE3EF"),
		WallAlt = hex("#C6F1FF"),
		Ceiling = hex("#FFF4F9"),
		Accent = hex("#7AE7FF"),
		Water = hex("#7A5CFF"),
		Sand = hex("#FFE29A"),
		Ice = hex("#E3FBFF"),
		Light = hex("#FFE4F2"),
		Decor = "Candy",
	},
	Frost = {
		Id = "Frost",
		Name = "Frost Factory",
		Floor = hex("#DDEBFA"),
		FloorAlt = hex("#E8F2FC"),
		Rail = hex("#5C7EA8"),
		Trim = hex("#7FE7FF"),
		Wall = hex("#B9CFE8"),
		WallAlt = hex("#A5C0DF"),
		Ceiling = hex("#EEF5FD"),
		Accent = hex("#2F80ED"),
		Water = hex("#3BA7FF"),
		Sand = hex("#D9D2C3"),
		Ice = hex("#C9F6FF"),
		Light = hex("#DDF6FF"),
		Decor = "Frost",
	},
	Lava = {
		Id = "Lava",
		Name = "Lava Lab",
		Floor = hex("#3A2A2E"),
		FloorAlt = hex("#45323A"),
		Rail = hex("#24181C"),
		Trim = hex("#FF6A00"),
		Wall = hex("#2A1C20"),
		WallAlt = hex("#36242A"),
		Ceiling = hex("#1A1013"),
		Accent = hex("#FFC300"),
		Water = hex("#FF3D00"),
		Sand = hex("#C9A27A"),
		Ice = hex("#FFE0C2"),
		Light = hex("#FFB27A"),
		Decor = "Lava",
	},
	Jungle = {
		Id = "Jungle",
		Name = "Jungle Temple",
		Floor = hex("#5FA35A"),
		FloorAlt = hex("#6BB065"),
		Rail = hex("#8A6A45"),
		Trim = hex("#C6FF4D"),
		Wall = hex("#6E8B5A"),
		WallAlt = hex("#7F9C68"),
		Ceiling = hex("#3D5A35"),
		Accent = hex("#FFD23F"),
		Water = hex("#2EC4B6"),
		Sand = hex("#E9D8A6"),
		Ice = hex("#D8FFF6"),
		Light = hex("#FFF2C2"),
		Decor = "Jungle",
	},
	Space = {
		Id = "Space",
		Name = "Orbit Station",
		Floor = hex("#3C4256"),
		FloorAlt = hex("#464D63"),
		Rail = hex("#C7CEDB"),
		Trim = hex("#B266FF"),
		Wall = hex("#252A3A"),
		WallAlt = hex("#2E3446"),
		Ceiling = hex("#171A25"),
		Accent = hex("#00FFC6"),
		Water = hex("#6A00FF"),
		Sand = hex("#BFB8A5"),
		Ice = hex("#D6E6FF"),
		Light = hex("#D7C2FF"),
		Decor = "Space",
	},
} :: { [string]: Theme }

local sprint = { Bumper = 0.18, Spinner = 0.08, Pusher = 0.05, Sand = 0.08, Ice = 0.06, Boost = 0.08, Bridge = 0.04, ChaosBox = 0.12 }
local gauntlet = { Bumper = 0.2, Spinner = 0.16, Pusher = 0.12, Sand = 0.1, Ice = 0.1, Boost = 0.1, Bridge = 0.1, ChaosBox = 0.14 }

local function map(id: string, name: string, theme: string, seed: number, gauntletMode: boolean, overrides: { [string]: number }?, blurb: string): MapDef
	local hazards = table.clone(if gauntletMode then gauntlet else sprint)
	if overrides then
		for k, v in overrides do
			hazards[k] = v
		end
	end
	return {
		Id = id,
		Name = name,
		Theme = theme,
		Seed = seed,
		Holes = 6,
		Length = if gauntletMode then { 7, 10 } else { 4, 7 },
		RampChance = if gauntletMode then 0.22 else 0.12,
		Hazards = hazards,
		Difficulty = if gauntletMode then "Gauntlet" else "Sprint",
		Blurb = blurb,
	}
end

Maps.List = {
	map("arcade_sprint", "Pixel Putt", "Arcade", 11021, false, nil, "Quick neon lanes and boost pads"),
	map("arcade_gauntlet", "High Score Hall", "Arcade", 22917, true, { Boost = 0.16 }, "Spinners, boosts and long neon runs"),
	map("candy_sprint", "Sugar Rush", "Candy", 31337, false, { Bumper = 0.26 }, "Gumdrop bumpers everywhere"),
	map("candy_gauntlet", "Jawbreaker Jam", "Candy", 44012, true, { Pusher = 0.16 }, "Candy pushers punish slow putts"),
	map("frost_sprint", "Cold Open", "Frost", 51719, false, { Ice = 0.16 }, "Slippery ice sheets, short holes"),
	map("frost_gauntlet", "Deep Freeze", "Frost", 60451, true, { Ice = 0.22, Sand = 0.04 }, "Ice rinks and spinning blades"),
	map("lava_sprint", "Hot Shot", "Lava", 72203, false, { Bridge = 0.1 }, "Narrow bridges over lava"),
	map("lava_gauntlet", "Meltdown", "Lava", 83377, true, { Bridge = 0.16, Spinner = 0.18 }, "The hardest course in the lab"),
	map("jungle_sprint", "Vine Swing", "Jungle", 91847, false, { Sand = 0.16 }, "Sand traps and temple steps"),
	map("jungle_gauntlet", "Lost Temple", "Jungle", 10391, true, { Sand = 0.16, Pusher = 0.14 }, "Stone pushers guard the idol"),
	map("space_sprint", "Zero-G Green", "Space", 12007, false, { Boost = 0.14, Ice = 0.1 }, "Low-friction decks and boosters"),
	map("space_gauntlet", "Event Horizon", "Space", 13931, true, { Boost = 0.14, Bridge = 0.14 }, "Gaps into the void"),
} :: { MapDef }

local byId: { [string]: MapDef } = {}
for _, m in Maps.List do
	assert(Maps.Themes[m.Theme], "unknown theme " .. m.Theme)
	byId[m.Id] = m
end
Maps.ById = byId

function Maps.get(id: string): MapDef?
	return byId[id]
end

-- Picks `count` distinct maps with equal weight.
function Maps.pickDistinct(count: number, rng: Random): { MapDef }
	local pool = table.clone(Maps.List)
	local out = {}
	for _ = 1, math.min(count, #pool) do
		local i = rng:NextInteger(1, #pool)
		table.insert(out, pool[i])
		table.remove(pool, i)
	end
	return out
end

return Maps

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
	Trim: Color3, -- painted rail caps, posts and cup rims
	Wall: Color3,
	WallAlt: Color3,
	Ceiling: Color3,
	Accent: Color3,
	Water: Color3,
	Sand: Color3,
	Ice: Color3,
	Light: Color3,
	Decor: string, -- biome: terrain + props around the holes (server/World/CourseNature)
	Foliage: Color3, -- leaves of trees, bushes and ferns
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
		Name = "Meadow Greens",
		Floor = hex("#4FAE4A"),
		FloorAlt = hex("#5ABA54"),
		Rail = hex("#9B6B3E"),
		Trim = hex("#F3E9D6"),
		Wall = hex("#7A5634"),
		WallAlt = hex("#8E8A82"),
		Ceiling = hex("#9FC9EE"),
		Accent = hex("#E63946"),
		Water = hex("#3FA7D6"),
		Sand = hex("#E9D29A"),
		Ice = hex("#CFEFFF"),
		Light = hex("#FFF4D6"),
		Decor = "Meadow",
		Foliage = hex("#4E9A3A"),
	},
	Candy = {
		Id = "Candy",
		Name = "Sunset Canyon",
		Floor = hex("#6CA84A"),
		FloorAlt = hex("#79B455"),
		Rail = hex("#B5743F"),
		Trim = hex("#F5DDB5"),
		Wall = hex("#A85A34"),
		WallAlt = hex("#C9874E"),
		Ceiling = hex("#9FC9EE"),
		Accent = hex("#F4A261"),
		Water = hex("#2A9D8F"),
		Sand = hex("#E9C46A"),
		Ice = hex("#F1E3D3"),
		Light = hex("#FFD9A8"),
		Decor = "Canyon",
		Foliage = hex("#6B8E3A"),
	},
	Frost = {
		Id = "Frost",
		Name = "Snowy Peaks",
		Floor = hex("#4C8F67"),
		FloorAlt = hex("#57A06F"),
		Rail = hex("#7A5B44"),
		Trim = hex("#F4F7FA"),
		Wall = hex("#6E7C87"),
		WallAlt = hex("#A9B7C6"),
		Ceiling = hex("#9FC9EE"),
		Accent = hex("#2F80ED"),
		Water = hex("#6EC6FF"),
		Sand = hex("#D9D2C3"),
		Ice = hex("#CFF3FF"),
		Light = hex("#E6F4FF"),
		Decor = "Snow",
		Foliage = hex("#2F5D46"),
	},
	Lava = {
		Id = "Lava",
		Name = "Volcano Ridge",
		Floor = hex("#4C7A3B"),
		FloorAlt = hex("#568644"),
		Rail = hex("#4A3B33"),
		Trim = hex("#9C8B7C"),
		Wall = hex("#3A2E2A"),
		WallAlt = hex("#55504C"),
		Ceiling = hex("#9FC9EE"),
		Accent = hex("#FF7A00"),
		Water = hex("#FF5A1F"),
		Sand = hex("#BFA58A"),
		Ice = hex("#F3D6C0"),
		Light = hex("#FFB27A"),
		Decor = "Volcano",
		Foliage = hex("#5B6B2E"),
	},
	Jungle = {
		Id = "Jungle",
		Name = "Jungle Temple",
		Floor = hex("#3F9A47"),
		FloorAlt = hex("#49A651"),
		Rail = hex("#7A5A3A"),
		Trim = hex("#C9B48A"),
		Wall = hex("#5A4630"),
		WallAlt = hex("#7E8C6A"),
		Ceiling = hex("#9FC9EE"),
		Accent = hex("#FFD23F"),
		Water = hex("#2EC4B6"),
		Sand = hex("#E9D8A6"),
		Ice = hex("#D8FFF6"),
		Light = hex("#FFF2C2"),
		Decor = "Jungle",
		Foliage = hex("#2F7D32"),
	},
	Space = {
		Id = "Space",
		Name = "Tropical Cove",
		Floor = hex("#52B65A"),
		FloorAlt = hex("#5EC266"),
		Rail = hex("#C49A6C"),
		Trim = hex("#FFFFFF"),
		Wall = hex("#A58A5F"),
		WallAlt = hex("#D8C59C"),
		Ceiling = hex("#9FC9EE"),
		Accent = hex("#FF6B6B"),
		Water = hex("#22B8CF"),
		Sand = hex("#F2DFA7"),
		Ice = hex("#DDF6FF"),
		Light = hex("#FFF1C9"),
		Decor = "Tropical",
		Foliage = hex("#3E9B4F"),
	},
	Autumn = {
		Id = "Autumn",
		Name = "Autumn Woods",
		Floor = hex("#5E9E3F"),
		FloorAlt = hex("#6AA947"),
		Rail = hex("#7B4A2A"),
		Trim = hex("#F2E6D0"),
		Wall = hex("#6B4428"),
		WallAlt = hex("#9A8C78"),
		Ceiling = hex("#A9CBEA"),
		Accent = hex("#B5332E"),
		Water = hex("#3A8FB7"),
		Sand = hex("#E4CC92"),
		Ice = hex("#D6F0FF"),
		Light = hex("#FFE7C2"),
		Decor = "Meadow",
		Foliage = hex("#D9822B"),
	},
	Blossom = {
		Id = "Blossom",
		Name = "Blossom Gardens",
		Floor = hex("#58B25C"),
		FloorAlt = hex("#63BD66"),
		Rail = hex("#5A3E36"),
		Trim = hex("#FFF5F8"),
		Wall = hex("#6E4A42"),
		WallAlt = hex("#B9AFA8"),
		Ceiling = hex("#B6D9F2"),
		Accent = hex("#D94F7A"),
		Water = hex("#4FB3D9"),
		Sand = hex("#F0DDB0"),
		Ice = hex("#E2F6FF"),
		Light = hex("#FFF0F4"),
		Decor = "Meadow",
		Foliage = hex("#F2A7C3"),
	},
} :: { [string]: Theme }

local sprint = { Windmill = 0.06, Bumper = 0.3, Spinner = 0.2, Pusher = 0.16, Sand = 0.08, Ice = 0.06, Boost = 0.08, Bridge = 0.06, Hump = 0.08, Tunnel = 0.05, ChaosBox = 0.18 }
local gauntlet = { Windmill = 0.1, Bumper = 0.32, Spinner = 0.28, Pusher = 0.24, Sand = 0.1, Ice = 0.1, Boost = 0.1, Bridge = 0.1, Hump = 0.1, Tunnel = 0.06, ChaosBox = 0.2 }

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
	map("arcade_sprint", "Sunny Meadow", "Arcade", 11021, false, nil, "Gentle greens, flower beds and a duck pond"),
	map("arcade_gauntlet", "Windmill Way", "Arcade", 22917, true, { Boost = 0.16 }, "Spinners, boosts and long fairways"),
	map("candy_sprint", "Red Rock Run", "Candy", 31337, false, { Bumper = 0.26 }, "Canyon bumpers around every bend"),
	map("candy_gauntlet", "Mesa Mayhem", "Candy", 44012, true, { Pusher = 0.16 }, "Pushers on the cliff edge punish slow putts"),
	map("frost_sprint", "Powder Putt", "Frost", 51719, false, { Ice = 0.16 }, "Icy patches on short snowy holes"),
	map("frost_gauntlet", "Avalanche Alley", "Frost", 60451, true, { Ice = 0.22, Sand = 0.04 }, "Frozen rinks and spinning gates"),
	map("lava_sprint", "Hot Shot", "Lava", 72203, false, { Bridge = 0.1 }, "Narrow bridges over lava rivers"),
	map("lava_gauntlet", "Meltdown", "Lava", 83377, true, { Bridge = 0.16, Spinner = 0.18 }, "The hardest course on the volcano"),
	map("jungle_sprint", "Vine Swing", "Jungle", 91847, false, { Sand = 0.16 }, "Sand traps and temple steps"),
	map("jungle_gauntlet", "Lost Temple", "Jungle", 10391, true, { Sand = 0.16, Pusher = 0.14 }, "Stone pushers guard the idol"),
	map("space_sprint", "Palm Beach", "Space", 12007, false, { Boost = 0.14, Ice = 0.1 }, "Breezy greens by the shore"),
	map("space_gauntlet", "Shipwreck Shoals", "Space", 13931, true, { Boost = 0.14, Bridge = 0.14 }, "Bridges over the lagoon"),
	map("autumn_sprint", "Maple Mile", "Autumn", 14411, false, { Hump = 0.16 }, "Rolling fairways under falling leaves"),
	map("autumn_gauntlet", "Harvest Hollow", "Autumn", 15583, true, { Windmill = 0.16 }, "Windmills guard the old farm"),
	map("blossom_sprint", "Petal Path", "Blossom", 16661, false, { Tunnel = 0.16, Bridge = 0.1 }, "Blossom arches over koi ponds"),
	map("blossom_gauntlet", "Sakura Summit", "Blossom", 17779, true, { Windmill = 0.12, Hump = 0.12 }, "Hills, windmills and pink canopies"),
	map("arcade_windmill", "Windmill Hollow", "Arcade", 18803, false, { Windmill = 0.22 }, "A windmill on almost every hole"),
	map("candy_dunes", "Dune Drift", "Candy", 19927, false, { Hump = 0.22, Boost = 0.12 }, "Humps and boost pads through the dunes"),
	map("frost_gate", "Glacier Gate", "Frost", 21149, true, { Windmill = 0.14, Ice = 0.16 }, "Icy windmill gates in the peaks"),
	map("jungle_caves", "Canopy Caves", "Jungle", 22271, true, { Tunnel = 0.18, Hump = 0.1 }, "Ruined arches and rolling roots"),
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

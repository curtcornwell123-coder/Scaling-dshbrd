--!strict
-- Practice range minigames. One game is live at a time on all six lanes, rotating every
-- RotationSeconds in the same order on every server; the whole range dresses itself as
-- the live game's biome. Each game pays its own tokens (never sold), spent at the token
-- hut on that game's crate and skins.

local Minigames = {}

export type Minigame = {
	Id: string,
	Name: string,
	Token: string, -- display name of its currency
	Color: Color3,
	Shots: number,
	Rules: string,
	Biome: string, -- range dressing while this game is live (see PracticeBiomes)
	BiomeName: string,
	LowerIsBetter: boolean?, -- scores are strokes (best = fewest)
}

Minigames.List = {
	{
		Id = "Target",
		Name = "Target Putting",
		Token = "Target Tokens",
		Color = Color3.fromHex("#E63946"),
		Shots = 5,
		Rules = "5 putts. Stop your ball on the rings: bullseye 10, middle 5, outer 2.",
		Biome = "Park",
		BiomeName = "Garden Green",
	},
	{
		Id = "Drive",
		Name = "Velocity Long-Drive",
		Token = "Drive Tokens",
		Color = Color3.fromHex("#00B4FF"),
		Shots = 3,
		Rules = "3 drives up the launch ramp. Your best distance counts.",
		Biome = "Range",
		BiomeName = "Night Driving Range",
	},
	{
		Id = "Hazard",
		Name = "Hazard Avoidance",
		Token = "Hazard Tokens",
		Color = Color3.fromHex("#FFB703"),
		Shots = 4,
		Rules = "Thread the sweepers and sink it in 4 strokes or fewer.",
		Biome = "Yard",
		BiomeName = "Construction Yard",
		LowerIsBetter = true,
	},
	{
		Id = "Bank",
		Name = "Bank Shot",
		Token = "Bank Tokens",
		Color = Color3.fromHex("#5BC0EB"),
		Shots = 3,
		Rules = "The cup hides behind the ice wall. Bank off the boards and sink it in 3 strokes or fewer.",
		Biome = "Rink",
		BiomeName = "Frozen Rink",
		LowerIsBetter = true,
	},
	{
		Id = "Gates",
		Name = "Gate Run",
		Token = "Gate Tokens",
		Color = Color3.fromHex("#E07A2F"),
		Shots = 3,
		Rules = "3 shots through 5 canyon gates (gate 1 = 1 pt ... gate 5 = 5 pts). Stop before the red line or the shot scores nothing.",
		Biome = "Canyon",
		BiomeName = "Desert Canyon",
	},
} :: { Minigame }

local byId: { [string]: Minigame } = {}
for _, m in Minigames.List do
	byId[m.Id] = m
end
Minigames.ById = byId

-- Rotation ------------------------------------------------------------------------

Minigames.RotationSeconds = 20 * 60

function Minigames.slot(now: number?): number
	return math.floor((now or os.time()) / Minigames.RotationSeconds)
end

function Minigames.active(now: number?): Minigame
	return Minigames.List[Minigames.slot(now) % #Minigames.List + 1]
end

function Minigames.upNext(now: number?): Minigame
	return Minigames.List[(Minigames.slot(now) + 1) % #Minigames.List + 1]
end

function Minigames.endsIn(now: number?): number
	local t = now or os.time()
	return Minigames.RotationSeconds - (t % Minigames.RotationSeconds)
end

-- Gate Run layout (shared so the server's scoring and the guide agree).
Minigames.Gates = {
	{ D = 10, Width = 4.6, Offset = 0 },
	{ D = 17, Width = 3.8, Offset = 1.2 },
	{ D = 24, Width = 3.4, Offset = -1.2 },
	{ D = 31, Width = 3.0, Offset = 0.8 },
	{ D = 38, Width = 2.6, Offset = 0 },
}
Minigames.GateStopLine = 42 -- a shot only counts if the ball stops before this distance

-- Token payout tables -----------------------------------------------------

function Minigames.tokensFor(id: string, score: number): number
	if id == "Target" then
		-- max score 50
		return if score >= 40 then 6 elseif score >= 25 then 4 elseif score >= 10 then 2 elseif score > 0 then 1 else 0
	elseif id == "Drive" then
		-- score = best distance in studs along the ramp (the 48-stud lanes give ~38 studs of ramp;
		-- a full-power base drive reaches ~35, Power upgrades reach the cap)
		return if score >= 36 then 6 elseif score >= 30 then 4 elseif score >= 22 then 3 elseif score >= 12 then 2 else 1
	elseif id == "Hazard" then
		-- score = strokes used (0 = failed)
		return if score == 1 then 6 elseif score == 2 then 4 elseif score == 3 then 3 elseif score == 4 then 2 else 0
	elseif id == "Bank" then
		-- score = strokes used (0 = failed); a one-stroke bank is hard
		return if score == 1 then 7 elseif score == 2 then 4 elseif score == 3 then 2 else 0
	elseif id == "Gates" then
		-- score = points over 3 shots (max 45)
		return if score >= 36 then 6 elseif score >= 24 then 4 elseif score >= 12 then 3 elseif score >= 4 then 2 elseif score > 0 then 1 else 0
	end
	return 0
end

return Minigames

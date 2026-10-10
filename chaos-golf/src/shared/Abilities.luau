--!strict
-- Chaos abilities. Players hold up to Config.Match.MaxAbilities charges.
-- Sabotages target opponents automatically (no targeting UI): the opponent
-- closest to the cup, or everyone nearby for area effects.

local Abilities = {}

export type Ability = {
	Id: string,
	Name: string,
	Desc: string,
	Sabotage: boolean,
	Color: Color3,
	Icon: string, -- short glyph shown on the ball's in-world ability strip
}

local list: { Ability } = {
	{
		Id = "Shockwave",
		Name = "Shockwave",
		Desc = "Blasts every opponent ball within 22 studs away from yours",
		Sabotage = true,
		Color = Color3.fromRGB(255, 120, 40),
		Icon = "💥",
	},
	{
		Id = "Frost",
		Name = "Frost Curse",
		Desc = "The leader's next shot skids like it's on ice",
		Sabotage = true,
		Color = Color3.fromRGB(120, 220, 255),
		Icon = "❄",
	},
	{
		Id = "Gust",
		Name = "Gust",
		Desc = "Wind pushes every opponent's next shot sideways",
		Sabotage = true,
		Color = Color3.fromRGB(190, 255, 220),
		Icon = "🌪",
	},
	{
		Id = "TinyCup",
		Name = "Tiny Cup",
		Desc = "Shrinks the cup for all opponents for 15 seconds",
		Sabotage = true,
		Color = Color3.fromRGB(255, 70, 160),
		Icon = "🎯",
	},
	{
		Id = "Magnet",
		Name = "Cup Magnet",
		Desc = "Your next shot is pulled into the cup from close range",
		Sabotage = false,
		Color = Color3.fromRGB(255, 210, 60),
		Icon = "🧲",
	},
	{
		Id = "Mulligan",
		Name = "Mulligan",
		Desc = "Undo your last shot and get the stroke back",
		Sabotage = false,
		Color = Color3.fromRGB(140, 255, 120),
		Icon = "↩",
	},
}

local byId: { [string]: Ability } = {}
for _, a in list do
	byId[a.Id] = a
end

Abilities.List = list
Abilities.ById = byId

Abilities.ShockwaveRadius = 22
Abilities.ShockwaveForce = 55
Abilities.GustSpeed = 18
Abilities.TinyCupSeconds = 15
Abilities.TinyCupScale = 0.45

function Abilities.get(id: string?): Ability?
	return if id then byId[id] else nil
end

function Abilities.random(rng: Random): string
	return list[rng:NextInteger(1, #list)].Id
end

return Abilities

--!strict
-- South room practice minigames. The active one rotates every 20 minutes on a
-- clock shared by every server (os.time based), so all servers agree.

local Config = require(script.Parent:WaitForChild("Config"))

local Minigames = {}

export type Minigame = {
	Id: string,
	Name: string,
	Token: string, -- display name of its currency
	Color: Color3,
	Shots: number,
	Rules: string,
}

Minigames.List = {
	{
		Id = "Target",
		Name = "Target Putting",
		Token = "Target Tokens",
		Color = Color3.fromHex("#E63946"),
		Shots = 5,
		Rules = "5 putts. Stop your ball on the rings: bullseye 10, middle 5, outer 2.",
	},
	{
		Id = "Drive",
		Name = "Velocity Long-Drive",
		Token = "Drive Tokens",
		Color = Color3.fromHex("#00B4FF"),
		Shots = 3,
		Rules = "3 drives up the launch ramp. Your best distance counts.",
	},
	{
		Id = "Hazard",
		Name = "Hazard Avoidance",
		Token = "Hazard Tokens",
		Color = Color3.fromHex("#FFB703"),
		Shots = 4,
		Rules = "Thread the sweepers and sink it in 4 strokes or fewer.",
	},
} :: { Minigame }

local byId: { [string]: Minigame } = {}
for _, m in Minigames.List do
	byId[m.Id] = m
end
Minigames.ById = byId

-- Token payout tables -----------------------------------------------------

function Minigames.tokensFor(id: string, score: number): number
	if id == "Target" then
		-- max score 50
		return if score >= 40 then 6 elseif score >= 25 then 4 elseif score >= 10 then 2 elseif score > 0 then 1 else 0
	elseif id == "Drive" then
		-- score = best distance in studs along the ramp
		return if score >= 40 then 6 elseif score >= 32 then 4 elseif score >= 24 then 3 elseif score >= 14 then 2 else 1
	elseif id == "Hazard" then
		-- score = strokes used (0 = failed)
		return if score == 1 then 6 elseif score == 2 then 4 elseif score == 3 then 3 elseif score == 4 then 2 else 0
	end
	return 0
end

-- Rotation ----------------------------------------------------------------

function Minigames.active(now: number): (Minigame, number)
	local period = Config.Practice.RotationSeconds
	local slot = math.floor(now / period)
	local m = Minigames.List[(slot % #Minigames.List) + 1]
	local remaining = period - (now % period)
	return m, remaining
end

return Minigames

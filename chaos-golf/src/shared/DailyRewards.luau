--!strict
-- 14-day progressive login calendar. One claim per UTC day; missing a day
-- resets the streak to Day 1 (Config: ResetOnMiss). After Day 14 the cycle
-- restarts; cosmetics you already own convert to their Fallback coins.

local DailyRewards = {}

DailyRewards.ResetOnMiss = true

export type Reward = {
	Coins: number?,
	Keys: { [string]: number }?, -- crate id -> keys
	Item: { Category: string, Id: string, Fallback: number }?,
	Label: string,
	Grand: boolean?,
}

DailyRewards.Days = {
	{ Coins = 150, Label = "150 Coins" },
	{ Keys = { Arrows = 1 }, Label = "Arrow Crate Key" },
	{ Coins = 250, Label = "250 Coins" },
	{ Item = { Category = "Trails", Id = "daily_spark", Fallback = 400 }, Label = "Daily Spark Trail" },
	{ Keys = { Knockouts = 1 }, Label = "Knockout Crate Key" },
	{ Coins = 400, Label = "400 Coins" },
	{ Coins = 300, Keys = { Skins = 1 }, Label = "Skin Crate Key + 300" },
	{ Keys = { Trails = 1 }, Label = "Trail Crate Key" },
	{ Item = { Category = "Arrows", Id = "sunrise_chevron", Fallback = 600 }, Label = "Sunrise Chevron Arrow" },
	{ Coins = 600, Label = "600 Coins" },
	{ Keys = { Knockouts = 1, Arrows = 1 }, Label = "Knockout + Arrow Keys" },
	{ Item = { Category = "Knockouts", Id = "daily_fireworks", Fallback = 800 }, Label = "Daily Fireworks Knockout" },
	{ Coins = 500, Keys = { Skins = 2 }, Label = "2 Skin Keys + 500" },
	{
		Coins = 1500,
		Item = { Category = "Skins", Id = "eternal_dawn", Fallback = 2500 },
		Label = "EXCLUSIVE: Eternal Dawn + 1,500",
		Grand = true,
	},
} :: { Reward }

function DailyRewards.today(now: number): number
	return math.floor(now / 86400)
end

export type State = { Day: number, LastClaim: number }

-- Which calendar day the player would claim now, and whether they can.
function DailyRewards.status(state: State, now: number): (number, boolean)
	local today = DailyRewards.today(now)
	if state.LastClaim == today then
		return state.Day, false
	end
	local day = state.Day
	if DailyRewards.ResetOnMiss and state.LastClaim > 0 and state.LastClaim < today - 1 then
		day = 1
	end
	return day, true
end

-- Seconds until the next UTC day.
function DailyRewards.untilReset(now: number): number
	return 86400 - (now % 86400)
end

return DailyRewards

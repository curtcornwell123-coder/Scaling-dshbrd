--!strict
--[[
	Matchmaking.spec
	Matchmaker (skill windows, parties, team balance, win-trade guard) and RankMath (Elo, tiers,
	soft reset). Pure modules, so every queue race the server can hit is simulated here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matchmaker = require(ReplicatedStorage.Shared.Logic.Matchmaker)
local RankMath = require(ReplicatedStorage.Shared.Logic.RankMath)
local RankConfig = require(ReplicatedStorage.Shared.Config.RankConfig)
local TestRunner = require(script.Parent.TestRunner)

local DUEL: Matchmaker.ModeShape = { teams = 2, teamSize = 1, minPlayers = 2, maxPlayers = 2, ranked = true }
local SQUAD: Matchmaker.ModeShape = { teams = 2, teamSize = 3, minPlayers = 6, maxPlayers = 6, ranked = false }
local COOP: Matchmaker.ModeShape = { teams = 1, teamSize = 4, minPlayers = 2, maxPlayers = 4, ranked = false }
local WINDOW: Matchmaker.Window = { base = 100, step = 50, interval = 10, cap = 400, maxGap = 500 }

local SETTINGS: RankMath.Settings = {
	startRating = 1000,
	minRating = 0,
	eloScale = 400,
	kFactor = 32,
	placementMatches = 10,
	placementKFactor = 64,
}

local function entry(key: string, value: number, joinedAt: number, members: { string }?): Matchmaker.Entry
	return { key = key, members = members or { key }, value = value, joinedAt = joinedAt }
end

local function teamSum(team: { any }, values: { [string]: number }): number
	local total = 0
	for _, member in team do
		total += values[member]
	end
	return total
end

return function(t: TestRunner.TestApi)
	t.describe("Matchmaker", function()
		t.it("pairs players inside the skill window and ignores ones far away", function()
			local entries = { entry("A", 1000, 0), entry("B", 1600, 0), entry("C", 1080, 0) }
			local selection = Matchmaker.select(entries, DUEL, 1, WINDOW, nil)
			t.expect(selection).toBeTruthy()
			local chosen = (selection :: Matchmaker.Selection).entries
			t.expect(chosen[1].key).toBe("A")
			t.expect(chosen[2].key).toBe("C")
		end)

		t.it("widens the window while waiting but never past the max gap", function()
			local entries = { entry("A", 1000, 0), entry("B", 1350, 0) }
			t.expect(Matchmaker.select(entries, DUEL, 5, WINDOW, nil)).toBeNil()
			t.expect(Matchmaker.select(entries, DUEL, 60, WINDOW, nil)).toBeTruthy()
			local far = { entry("A", 1000, 0), entry("B", 1600, 0) }
			t.expect(Matchmaker.select(far, DUEL, 10000, WINDOW, nil)).toBeNil()
		end)

		t.it("balances 3v3 teams and keeps parties together", function()
			local values = { A = 1300, B = 1200, C = 1100, D = 1100, E = 1000, F = 950 }
			local entries = {
				entry("A", 1300, 0),
				entry("P", 1100, 0, { "C", "D" }),
				entry("B", 1200, 0),
				entry("E", 1000, 0),
				entry("F", 950, 0),
			}
			-- Party members' values are averaged into the entry value.
			local selection = Matchmaker.select(entries, SQUAD, 100, WINDOW, nil)
			t.expect(selection).toBeTruthy()
			local teams = (selection :: Matchmaker.Selection).teams
			t.expect(#teams[1]).toBe(3)
			t.expect(#teams[2]).toBe(3)
			local cTeam = if table.find(teams[1], "C") then 1 else 2
			t.expect(table.find(teams[cTeam], "D") ~= nil).toBe(true)
			local gap = math.abs(teamSum(teams[1], values) - teamSum(teams[2], values))
			t.expect(gap <= 400).toBe(true)
		end)

		t.it("skips a party larger than the team but still matches everyone else", function()
			local entries = { entry("P", 1000, 0, { "A", "B" }), entry("C", 1000, 0), entry("D", 1000, 0) }
			local selection = Matchmaker.select(entries, DUEL, 100, WINDOW, nil) :: Matchmaker.Selection
			t.expect(#selection.entries).toBe(2)
			t.expect(selection.entries[1].key ~= "P" and selection.entries[2].key ~= "P").toBe(true)
			t.expect(Matchmaker.select({ entries[1] }, DUEL, 100, WINDOW, nil)).toBeNil()
		end)

		t.it("never pairs a blocked (win-trading) pair", function()
			local entries = { entry("A", 1000, 0), entry("B", 1000, 0) }
			local blocked = function(a: Matchmaker.Entry, b: Matchmaker.Entry): boolean
				return (a.key == "A" and b.key == "B") or (a.key == "B" and b.key == "A")
			end
			t.expect(Matchmaker.select(entries, DUEL, 100, WINDOW, blocked)).toBeNil()
		end)

		t.it("co-op takes everyone up to the cap and starts at the minimum", function()
			t.expect(Matchmaker.select({ entry("A", 1000, 0) }, COOP, 0, nil, nil)).toBeNil()
			local five = { entry("A", 1, 0), entry("B", 1, 0), entry("C", 1, 0), entry("D", 1, 0), entry("E", 1, 0) }
			local selection = Matchmaker.select(five, COOP, 0, nil, nil) :: Matchmaker.Selection
			t.expect(#selection.teams[1]).toBe(4)
		end)

		t.it("forms every disjoint match at once", function()
			local entries = { entry("A", 1000, 0), entry("B", 1010, 0), entry("C", 1020, 0), entry("D", 1030, 0) }
			t.expect(#Matchmaker.selectAll(entries, DUEL, 0, WINDOW, nil)).toBe(2)
		end)
	end)

	t.describe("RankMath", function()
		t.it("an even match moves rating by half of K", function()
			t.expect(RankMath.delta(1000, 1000, 1, 50, SETTINGS)).toBe(16)
			t.expect(RankMath.delta(1000, 1000, 0, 50, SETTINGS)).toBe(-16)
		end)

		t.it("placement matches use the bigger K", function()
			t.expect(RankMath.delta(1000, 1000, 1, 0, SETTINGS)).toBe(32)
		end)

		t.it("an upset gains more than an expected win", function()
			t.expect(RankMath.delta(1000, 1400, 1, 50, SETTINGS) > RankMath.delta(1400, 1000, 1, 50, SETTINGS))
				.toBe(true)
		end)

		t.it("ratings never drop below the floor", function()
			local data = RankMath.newRating(SETTINGS)
			data.rating = 5
			RankMath.apply(data, -40, false, SETTINGS)
			t.expect(data.rating).toBe(0)
			t.expect(data.losses).toBe(1)
		end)

		t.it("maps ratings to tiers and divisions", function()
			t.expect(RankMath.tierFor(0, RankConfig.Tiers).tier.id).toBe("Recruit")
			t.expect(RankMath.tierFor(1210, RankConfig.Tiers).label).toBe("Sergeant III")
			t.expect(RankMath.tierFor(1340, RankConfig.Tiers).label).toBe("Sergeant I")
			t.expect(RankMath.tierFor(2500, RankConfig.Tiers).label).toBe("Commander")
		end)

		t.it("soft reset pulls ratings halfway back to the start", function()
			t.expect(RankMath.softReset(1600, 0.5, SETTINGS)).toBe(1300)
			t.expect(RankMath.softReset(800, 0.5, SETTINGS)).toBe(900)
		end)
	end)
end

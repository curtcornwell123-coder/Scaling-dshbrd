--!strict
--[[
	WaveRewards.spec
	In-match coin formulas, swarm size limits, and end-of-match payouts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local WaveMath = require(ReplicatedStorage.Shared.Logic.WaveMath)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local TestRunner = require(script.Parent.TestRunner)

local REWARDS: Types.WaveRewards = {
	perSurvivor = 5,
	perBaseDamage = 0.5,
	completionBonus = 30,
	completionBonusPerWave = 6,
}

return function(t: TestRunner.TestApi)
	t.describe("arrivalReward", function()
		t.it("pays per survivor plus per point of damage, rounded down", function()
			t.expect(WaveMath.arrivalReward(10, REWARDS)).toBe(10)
			t.expect(WaveMath.arrivalReward(5, REWARDS)).toBe(7)
		end)

		t.it("never pays for negative damage", function()
			t.expect(WaveMath.arrivalReward(-50, REWARDS)).toBe(5)
		end)
	end)

	t.describe("completionBonus", function()
		t.it("grows each wave", function()
			t.expect(WaveMath.completionBonus(1, 3, REWARDS)).toBe(30)
			t.expect(WaveMath.completionBonus(4, 3, REWARDS)).toBe(48)
		end)

		t.it("is zero for players who sent no robots", function()
			t.expect(WaveMath.completionBonus(5, 0, REWARDS)).toBe(0)
		end)
	end)

	t.describe("waveTotal", function()
		t.it("equals the sum of arrivals plus the completion bonus", function()
			local total = WaveMath.waveTotal({ 10, 5, 14 }, 2, 6, REWARDS)
			t.expect(total).toBe(10 + 7 + 12 + 36)
		end)
	end)

	t.describe("robotCap", function()
		t.it("grows per wave and stops at the max", function()
			local rules: Types.RobotCapRules = { base = 10, perWave = 3, max = 20 }
			t.expect(WaveMath.robotCap(1, rules)).toBe(10)
			t.expect(WaveMath.robotCap(3, rules)).toBe(16)
			t.expect(WaveMath.robotCap(50, rules)).toBe(20)
		end)
	end)

	t.describe("matchPayout", function()
		t.it("pays win or loss coins plus a per-wave amount", function()
			local rewards: Types.MatchRewards = { winCoins = 100, lossCoins = 20, perWaveCoins = 5 }
			t.expect(WaveMath.matchPayout(true, 6, rewards)).toBe(130)
			t.expect(WaveMath.matchPayout(false, 6, rewards)).toBe(50)
		end)
	end)

	t.describe("cheapestCost", function()
		t.it("finds the cheapest robot in a loadout", function()
			t.expect(WaveMath.cheapestCost({ "Brute", "Scout" }, RobotConfig.Robots)).toBe(RobotConfig.Robots.Scout.cost)
		end)

		t.it("is nil for an empty loadout", function()
			t.expect(WaveMath.cheapestCost({}, RobotConfig.Robots)).toBeNil()
		end)
	end)
end

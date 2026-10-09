--!strict
--[[
	StatResolver.spec
	Stat resolution: mutations layer on top of base tower stats without ever compounding.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local StatResolver = require(ReplicatedStorage.Shared.Logic.StatResolver)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local TestRunner = require(script.Parent.TestRunner)

local function mutation(id: string, modifiers: { Types.Modifier }): Types.MutationDef
	return {
		id = id,
		displayName = id,
		rarity = "Common",
		description = "",
		modifiers = modifiers,
		maxStacks = 10,
	}
end

local FAST = mutation("Fast", { { stat = "fireRate", multiplier = 1.25 } })
local FLAT = mutation("Flat", { { stat = "damage", add = 5 } })
local BOTH = mutation("Both", { { stat = "damage", add = 2 }, { stat = "damage", multiplier = 2 } })
local MUTATIONS = { Fast = FAST, Flat = FLAT, Both = BOTH }
local NO_CAPS: { [string]: number } = {}

return function(t: TestRunner.TestApi)
	local basic = TowerConfig.Towers.BasicTurret
	local base = StatResolver.baseTowerStats(basic)

	t.describe("baseTowerStats", function()
		t.it("copies config values and zeroes mutation-only stats", function()
			t.expect(base.damage).toBe(basic.damage)
			t.expect(base.fireRate).toBe(basic.fireRate)
			t.expect(base.range).toBe(basic.range)
			t.expect(base.maxHealth).toBe(basic.maxHealth)
			t.expect(base.armorHits).toBe(0)
			t.expect(base.chainCount).toBe(0)
			t.expect(base.magnet).toBe(0)
		end)
	end)

	t.describe("resolve", function()
		t.it("returns base values when nothing is stacked", function()
			local resolved = StatResolver.resolve(base, {}, MUTATIONS, NO_CAPS)
			t.expect(resolved.fireRate).toBe(base.fireRate)
			t.expect(resolved.damage).toBe(base.damage)
		end)

		t.it("stacks multipliers additively instead of compounding", function()
			local resolved = StatResolver.resolve(base, { Fast = 2 }, MUTATIONS, NO_CAPS)
			-- Two 1.25x stacks are +50%, not 1.25 * 1.25 = +56.25%.
			t.expect(resolved.fireRate).toBeNear(base.fireRate * 1.5)
		end)

		t.it("adds flat bonuses per stack", function()
			local resolved = StatResolver.resolve(base, { Flat = 3 }, MUTATIONS, NO_CAPS)
			t.expect(resolved.damage).toBeNear(base.damage + 15)
		end)

		t.it("applies adds before multipliers", function()
			local resolved = StatResolver.resolve(base, { Both = 1 }, MUTATIONS, NO_CAPS)
			t.expect(resolved.damage).toBeNear((base.damage + 2) * 2)
		end)

		t.it("respects caps", function()
			local resolved = StatResolver.resolve(base, { Fast = 10 }, MUTATIONS, { fireRate = 2 })
			t.expect(resolved.fireRate).toBe(2)
		end)

		t.it("never mutates the base block, so re-resolving gives the same answer", function()
			local before = base.fireRate
			local first = StatResolver.resolve(base, { Fast = 3 }, MUTATIONS, NO_CAPS)
			local second = StatResolver.resolve(base, { Fast = 3 }, MUTATIONS, NO_CAPS)
			t.expect(base.fireRate).toBe(before)
			t.expect(first.fireRate).toBeNear(second.fireRate)
		end)

		t.it("ignores unknown mutation ids and zero stacks", function()
			local resolved = StatResolver.resolve(base, { Ghost = 4, Fast = 0 }, MUTATIONS, NO_CAPS)
			t.expect(resolved.fireRate).toBe(base.fireRate)
		end)
	end)

	t.describe("robotStats", function()
		t.it("scales health and damage linearly per level", function()
			local robot = {
				id = "Test",
				displayName = "Test",
				description = "",
				rarity = "Common",
				cost = 1,
				health = 100,
				speed = 1,
				damage = 10,
				flying = false,
				abilities = {},
				modelPath = "",
				visual = {
					size = Vector3.one,
					color = Color3.new(1, 1, 1),
					accent = Color3.new(1, 1, 1),
					shape = "Block",
				},
				unlockCost = 0,
				locked = false,
				upgradeCosts = {},
			} :: Types.RobotDef
			local health, damage = StatResolver.robotStats(robot, 2, { healthPerLevel = 0.25, damagePerLevel = 0.1 })
			t.expect(health).toBeNear(150)
			t.expect(damage).toBeNear(12)
		end)
	end)
end

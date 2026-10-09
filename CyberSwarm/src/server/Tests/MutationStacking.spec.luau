--!strict
--[[
	MutationStacking.spec
	Mutation selection by rarity weight, max-stack limits, and the real config stacked to its limits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MutationRoller = require(ReplicatedStorage.Shared.Logic.MutationRoller)
local StatResolver = require(ReplicatedStorage.Shared.Logic.StatResolver)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local TestRunner = require(script.Parent.TestRunner)

local function mutation(id: string, rarity: Types.MutationRarity, maxStacks: number): Types.MutationDef
	return {
		id = id,
		displayName = id,
		rarity = rarity,
		description = "",
		modifiers = { { stat = "damage", add = 1 } },
		maxStacks = maxStacks,
	}
end

local COMMON = mutation("CommonOne", "Common", 2)
local RARE = mutation("RareOne", "Rare", 1)
local MYTHIC = mutation("MythicOne", "Mythic", 1)
local MUTATIONS = { CommonOne = COMMON, RareOne = RARE, MythicOne = MYTHIC }
local ORDER = { "CommonOne", "RareOne", "MythicOne" }
local RARITIES: { [string]: Types.MutationRarityDef } = {
	Common = { weight = 60 },
	Rare = { weight = 30 },
	Mythic = { weight = 10 },
}
local RARITY_ORDER = { "Common", "Rare", "Mythic" }

return function(t: TestRunner.TestApi)
	t.describe("addStack", function()
		t.it("stacks up to maxStacks and then refuses", function()
			local counts = {}
			t.expect(MutationRoller.addStack(counts, COMMON)).toBe(true)
			t.expect(MutationRoller.addStack(counts, COMMON)).toBe(true)
			t.expect(MutationRoller.addStack(counts, COMMON)).toBe(false)
			t.expect(counts.CommonOne).toBe(2)
		end)
	end)

	t.describe("candidates", function()
		t.it("excludes maxed mutations and keeps config order", function()
			local list = MutationRoller.candidates({ RareOne = 1 }, MUTATIONS, ORDER)
			t.expect(#list).toBe(2)
			t.expect(list[1].id).toBe("CommonOne")
			t.expect(list[2].id).toBe("MythicOne")
		end)
	end)

	t.describe("pick", function()
		local all = MutationRoller.candidates({}, MUTATIONS, ORDER)

		t.it("maps the roll onto rarity weight bands", function()
			t.expect((MutationRoller.pick(all, RARITIES, RARITY_ORDER, 0.0, 0) :: Types.MutationDef).id).toBe("CommonOne")
			t.expect((MutationRoller.pick(all, RARITIES, RARITY_ORDER, 0.59, 0) :: Types.MutationDef).id).toBe("CommonOne")
			t.expect((MutationRoller.pick(all, RARITIES, RARITY_ORDER, 0.61, 0) :: Types.MutationDef).id).toBe("RareOne")
			t.expect((MutationRoller.pick(all, RARITIES, RARITY_ORDER, 0.95, 0) :: Types.MutationDef).id).toBe("MythicOne")
			t.expect((MutationRoller.pick(all, RARITIES, RARITY_ORDER, 1.0, 0.999) :: Types.MutationDef).id).toBe("MythicOne")
		end)

		t.it("re-weights over the rarities that still have options", function()
			-- With every Common maxed, Rare (30) and Mythic (10) split the roll 75% / 25%.
			local remaining = MutationRoller.candidates({ CommonOne = 2 }, MUTATIONS, ORDER)
			t.expect((MutationRoller.pick(remaining, RARITIES, RARITY_ORDER, 0.7, 0) :: Types.MutationDef).id).toBe("RareOne")
			t.expect((MutationRoller.pick(remaining, RARITIES, RARITY_ORDER, 0.8, 0) :: Types.MutationDef).id).toBe("MythicOne")
		end)

		t.it("returns nil when every mutation is maxed", function()
			local none = MutationRoller.candidates({ CommonOne = 2, RareOne = 1, MythicOne = 1 }, MUTATIONS, ORDER)
			t.expect(MutationRoller.pick(none, RARITIES, RARITY_ORDER, 0.5, 0.5)).toBeNil()
		end)
	end)

	t.describe("real config", function()
		t.it("every mutation can be rolled from a fresh state", function()
			local list = MutationRoller.candidates({}, MutationConfig.Mutations, MutationConfig.Order)
			t.expect(#list).toBe(#MutationConfig.Order)
		end)

		t.it("stacking every mutation to its max stays within the stat caps", function()
			local counts: { [string]: number } = {}
			for _, mutationId in MutationConfig.Order do
				local def = MutationConfig.Mutations[mutationId]
				while MutationRoller.addStack(counts, def) do
					-- Keep stacking until the roller refuses.
				end
				t.expect(counts[mutationId]).toBe(def.maxStacks)
			end
			for _, tower in TowerConfig.Towers do
				local resolved = StatResolver.resolve(
					StatResolver.baseTowerStats(tower),
					counts,
					MutationConfig.Mutations,
					MutationConfig.StatCaps
				)
				for statName, cap in MutationConfig.StatCaps do
					t.expect(resolved[statName] <= cap).toBe(true)
				end
				t.expect(resolved.fireRate > tower.fireRate).toBe(true)
			end
		end)
	end)
end

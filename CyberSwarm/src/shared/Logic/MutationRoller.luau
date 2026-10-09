--!strict
--[[
	MutationRoller
	Pure rules for choosing and stacking mutations. Rolls are passed in as numbers in [0, 1) so the
	server can use a per-match Random and tests can use fixed values.
	Selection is two-step: pick a rarity by weight (only rarities with an eligible mutation count),
	then pick uniformly within that rarity. Mutations at maxStacks are never offered again.
]]

local Types = require(script.Parent.Parent.Types)
local MathUtil = require(script.Parent.Parent.Util.Math)

local MutationRoller = {}

function MutationRoller.isEligible(mutation: Types.MutationDef, counts: { [string]: number }): boolean
	return (counts[mutation.id] or 0) < mutation.maxStacks
end

-- Eligible mutations in config order, so the same rolls always produce the same result.
function MutationRoller.candidates(
	counts: { [string]: number },
	mutations: { [string]: Types.MutationDef },
	order: { string }
): { Types.MutationDef }
	local result = {}
	for _, mutationId in order do
		local mutation = mutations[mutationId]
		if mutation ~= nil and MutationRoller.isEligible(mutation, counts) then
			table.insert(result, mutation)
		end
	end
	return result
end

function MutationRoller.pick(
	candidates: { Types.MutationDef },
	rarities: { [string]: Types.MutationRarityDef },
	rarityOrder: { string },
	rarityRoll: number,
	itemRoll: number
): Types.MutationDef?
	local pools: { { Types.MutationDef } } = {}
	local weights: { number } = {}
	for index, rarityName in rarityOrder do
		local pool = {}
		for _, mutation in candidates do
			if mutation.rarity == rarityName then
				table.insert(pool, mutation)
			end
		end
		pools[index] = pool
		local rarity = rarities[rarityName]
		weights[index] = if #pool > 0 and rarity ~= nil then rarity.weight else 0
	end

	local rarityIndex = MathUtil.weightedIndex(weights, rarityRoll)
	if rarityIndex == nil then
		return nil
	end
	local pool = pools[rarityIndex]
	local itemIndex = math.clamp(math.floor(itemRoll * #pool) + 1, 1, #pool)
	return pool[itemIndex]
end

-- Adds one stack. Returns false (and changes nothing) when the mutation is already maxed.
function MutationRoller.addStack(counts: { [string]: number }, mutation: Types.MutationDef): boolean
	local current = counts[mutation.id] or 0
	if current >= mutation.maxStacks then
		return false
	end
	counts[mutation.id] = current + 1
	return true
end

return MutationRoller

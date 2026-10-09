--!strict
--[[
	MutationService
	Per-arena mutation state for the AI defense: rolling the next mutation, applying it when a wave
	starts, resolving tower stats through StatResolver, and describing mutations for the HUD.
	Timeline: wave N ends -> roll (shown as "incoming" during Preparing) -> wave N+1 starts -> applied.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local StatResolver = require(ReplicatedStorage.Shared.Logic.StatResolver)
local MutationRoller = require(ReplicatedStorage.Shared.Logic.MutationRoller)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

local MutationService = {}

function MutationService.newState(): ServerTypes.MutationState
	return {
		counts = {},
		history = {},
		pending = nil,
	}
end

-- Rolls the mutation the defense will gain at the start of the next wave.
function MutationService.rollPending(state: ServerTypes.MutationState, rng: Random): Types.MutationDef?
	local candidates = MutationRoller.candidates(state.counts, MutationConfig.Mutations, MutationConfig.Order)
	local picked = MutationRoller.pick(
		candidates,
		MutationConfig.Rarities,
		MutationConfig.RarityOrder,
		rng:NextNumber(),
		rng:NextNumber()
	)
	state.pending = if picked ~= nil then picked.id else nil
	return picked
end

local function stack(state: ServerTypes.MutationState, mutation: Types.MutationDef): boolean
	if not MutationRoller.addStack(state.counts, mutation) then
		return false
	end
	if not table.find(state.history, mutation.id) then
		table.insert(state.history, mutation.id)
	end
	return true
end

-- Applies and clears the pending mutation. Returns it when something changed.
function MutationService.applyPending(state: ServerTypes.MutationState): Types.MutationDef?
	local pendingId = state.pending
	state.pending = nil
	if pendingId == nil then
		return nil
	end
	local mutation = MutationConfig.Mutations[pendingId]
	if mutation == nil or not stack(state, mutation) then
		return nil
	end
	return mutation
end

-- QA helper: applies a mutation immediately, ignoring the roll.
function MutationService.force(state: ServerTypes.MutationState, mutationId: string): Types.MutationDef?
	local mutation = MutationConfig.Mutations[mutationId]
	if mutation == nil or not stack(state, mutation) then
		return nil
	end
	return mutation
end

function MutationService.resolveTowerStats(state: ServerTypes.MutationState, tower: Types.TowerDef): Types.StatBlock
	return StatResolver.resolve(
		StatResolver.baseTowerStats(tower),
		state.counts,
		MutationConfig.Mutations,
		MutationConfig.StatCaps
	)
end

function MutationService.describe(mutationId: string, stacks: number): Types.MutationInfo?
	local mutation = MutationConfig.Mutations[mutationId]
	if mutation == nil then
		return nil
	end
	return {
		id = mutation.id,
		displayName = mutation.displayName,
		rarity = mutation.rarity,
		description = mutation.description,
		stacks = stacks,
	}
end

function MutationService.activeList(state: ServerTypes.MutationState): { Types.MutationInfo }
	local list = {}
	for _, mutationId in state.history do
		local info = MutationService.describe(mutationId, state.counts[mutationId] or 0)
		if info ~= nil then
			table.insert(list, info)
		end
	end
	return list
end

function MutationService.pendingInfo(state: ServerTypes.MutationState): Types.MutationInfo?
	local pendingId = state.pending
	if pendingId == nil then
		return nil
	end
	return MutationService.describe(pendingId, (state.counts[pendingId] or 0) + 1)
end

return MutationService

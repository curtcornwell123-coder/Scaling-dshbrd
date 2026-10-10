--!strict
--[[
	SupplyService
	Daily Supply: up to SupplyConfig.ClaimsPerDay claims per UTC day, each at least
	SupplyConfig.CooldownSeconds after the previous one. Claimed from the hub's supply terminal
	(server-side ProximityPrompt) or the Tasks panel; both go through the same validated claim.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SupplyConfig = require(ReplicatedStorage.Shared.Config.SupplyConfig)
local SupplyRules = require(ReplicatedStorage.Shared.Logic.SupplyRules)
local Actions = require(script.Parent.Parent.Actions)
local Rewards = require(script.Parent.Parent.Rewards)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)

local ErrorCode = Constants.ErrorCode

local SupplyService = {}

local function claim(player: Player): string
	if DataService.isSandboxed(player) then
		return ErrorCode.Sandbox
	end
	local code = ErrorCode.DataNotLoaded
	local granted: Types.Reward? = nil
	local now = os.time()
	DataService.update(player, function(data)
		code = SupplyRules.check(data.supply, now, SupplyConfig.ClaimsPerDay, SupplyConfig.CooldownSeconds)
		if code ~= ErrorCode.Ok then
			return
		end
		local index = SupplyRules.apply(data.supply, now)
		local reward = SupplyConfig.Rewards[index] or SupplyConfig.Rewards[#SupplyConfig.Rewards]
		granted = Rewards.apply(data, reward)
	end)
	local final = granted
	if final ~= nil then
		Notifier.banner({ player }, "Success", "SUPPLY DROP", Rewards.describe(final))
	end
	return code
end

local function request(player: Player)
	Actions.run(player, "ClaimSupply", nil, function(): string
		return claim(player)
	end)
end

function SupplyService.start()
	Remotes.RequestClaimSupply:connect(request)
	for _, instance in CollectionService:GetTagged(Constants.Tags.Terminal) do
		if instance:GetAttribute(Constants.Attributes.Terminal) == "Supply" then
			local prompt = instance:FindFirstChildOfClass("ProximityPrompt")
			if prompt ~= nil then
				prompt.Triggered:Connect(request)
			end
		end
	end
end

return SupplyService

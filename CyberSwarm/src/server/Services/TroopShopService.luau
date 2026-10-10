--!strict
--[[
	TroopShopService
	Troop Depot purchases. The client sends only a troop id. The server checks, in order: the id
	is a string naming a catalog troop, it is in today's stock (TroopRotation), not already owned,
	not Coming Soon, its unlock requirement is met, and the player has the coins or gems. All of
	that and the purchase itself run inside one DataService.update, so the check and the spend can
	never be split. A per-player lock (Actions) and the remote's rate limiter stop spam.

	Result: one typed ActionResult ("BuyTroop", code, troop id). The client then shows the
	confirmation banner, plays a sound, and opens the equip slot picker.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local TroopRotation = require(ReplicatedStorage.Shared.Logic.TroopRotation)
local PurchaseRules = require(ReplicatedStorage.Shared.Logic.PurchaseRules)
local Requirements = require(ReplicatedStorage.Shared.Logic.Requirements)
local DataService = require(script.Parent.DataService)
local Actions = require(script.Parent.Parent.Actions)

local ErrorCode = Constants.ErrorCode

local TroopShopService = {}

local rotationSettings: TroopRotation.RotationSettings = {
	permanent = TroopConfig.Permanent,
	rotatingPool = TroopConfig.RotatingPool,
	rotatingCount = TroopConfig.RotatingCount,
	seed = TroopConfig.RotationSeed,
}

function TroopShopService.rotation(): any
	return TroopRotation.forTime(os.time(), rotationSettings)
end

local function buy(player: Player, troopId: string): string
	if DataService.isSandboxed(player) then
		return ErrorCode.Sandbox
	end
	if DataService.getData(player) == nil then
		return ErrorCode.DataNotLoaded
	end
	local rotation = TroopRotation.forTime(os.time(), rotationSettings)
	local troop = TroopConfig.Troops[troopId]
	local code = ErrorCode.InvalidRequest
	DataService.update(player, function(data)
		code = PurchaseRules.check({
			troop = troop,
			inStock = TroopRotation.inStock(rotation, troopId),
			progress = Requirements.progressOf(data),
			coins = data.coins,
			gems = data.gems,
		})
		if code ~= ErrorCode.Ok or troop == nil then
			return
		end
		if troop.currency == "Gems" then
			data.gems -= troop.price
		else
			data.coins -= troop.price
		end
		table.insert(data.unlockedRobots, troop.id)
	end)
	return code
end

function TroopShopService.start()
	Remotes.RequestBuyTroop:connect(function(player: Player, raw: unknown)
		local troopId = Actions.readId(raw)
		if troopId == nil then
			Actions.run(player, "BuyTroop", nil, function(): string
				return ErrorCode.UnknownTroop
			end)
			return
		end
		local id = troopId :: string
		Actions.run(player, "BuyTroop", id, function(): string
			return buy(player, id)
		end)
	end)
end

return TroopShopService

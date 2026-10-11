--!strict
--[[
	ProductService
	Robux developer products and the premium pass game pass.

	ProcessReceipt is idempotent and grants exactly once, even across servers:
	- The receipt's PurchaseId is saved in the player's profile together with the grant, inside one
	  DataService.update. Session locking means only one server can own that profile at a time.
	- PurchaseGranted is returned only after DataService.saveNow has written that profile. If the
	  save fails, NotProcessedYet is returned; Roblox retries, sees the saved PurchaseId (if it
	  made it) and answers PurchaseGranted without granting again.
	- Unknown products, players not in this server, players whose data is not loaded yet, and
	  Test Realm servers (which cannot save) all answer NotProcessedYet so Roblox retries later.

	Prices shown in the shop come from MarketplaceService on the client, never from config.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local ReceiptLedger = require(ReplicatedStorage.Shared.Logic.ReceiptLedger)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Rewards = require(script.Parent.Parent.Rewards)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)
local Passes = require(script.Parent.Parent.Passes)

local ProductService = {}

local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted

local function waitForProfile(player: Player): boolean
	local started = os.clock()
	while not DataService.isLoaded(player) and player.Parent ~= nil do
		if os.clock() - started > Constants.Receipts.PROFILE_WAIT then
			return false
		end
		task.wait(0.25)
	end
	return DataService.isLoaded(player)
end

local function grantProduct(data: Types.PlayerData, product: Types.ShopProduct): Types.Reward
	if product.kind == "SeasonPremium" then
		SeasonRules.normalize(data.season, SeasonConfig.SeasonId)
		data.season.premium = true
		return {}
	end
	return Rewards.apply(data, product.reward)
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	if DataService.isSandboxServer() then
		return NOT_YET
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil or not waitForProfile(player) then
		return NOT_YET
	end
	local product = ShopConfig.byProductId(receipt.ProductId)
	if product == nil then
		warn(`[ProductService] Receipt for unknown product {receipt.ProductId}; leaving it unprocessed.`)
		return NOT_YET
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local data = DataService.getData(player)
	if data ~= nil and ReceiptLedger.has(data.purchases, purchaseId) then
		-- Already granted (an earlier attempt saved it); just confirm.
		return if DataService.saveNow(player) then GRANTED else NOT_YET
	end

	local granted: Types.Reward? = nil
	local applied = DataService.update(player, function(profile)
		if ReceiptLedger.has(profile.purchases, purchaseId) then
			return
		end
		ReceiptLedger.record(profile.purchases, purchaseId, Constants.Data.PURCHASE_HISTORY)
		granted = grantProduct(profile, product)
	end)
	if not applied then
		return NOT_YET
	end
	if not DataService.saveNow(player) then
		-- The grant stays in memory with its PurchaseId; the retry or the next save settles it.
		return NOT_YET
	end
	local final = granted
	if final ~= nil then
		local text = if product.kind == "SeasonPremium" then "Premium track unlocked!" else Rewards.describe(final)
		Notifier.banner({ player }, "Success", "PURCHASE COMPLETE", text)
	end
	return GRANTED
end

-- Refreshes every game pass this player owns (profile + "Pass_<id>" attributes).
local function refreshPasses(player: Player)
	local owned: { string } = {}
	for _, passId in ShopConfig.GamePassOrder do
		local def = ShopConfig.GamePasses[passId]
		if def.gamePassId ~= 0 then
			local ok, owns = pcall(function(): boolean
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.gamePassId)
			end)
			if ok and owns then
				table.insert(owned, passId)
			end
		end
	end
	-- Season Premium may also be sold as a game pass.
	local premiumPass = ShopConfig.PremiumGamePassId
	local premium = false
	if premiumPass ~= 0 then
		local ok, owns = pcall(function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, premiumPass)
		end)
		premium = ok and owns
	end
	if player.Parent == nil then
		return
	end
	for _, passId in ShopConfig.GamePassOrder do
		player:SetAttribute(Passes.attributeName(passId), table.find(owned, passId) ~= nil)
	end
	DataService.update(player, function(data)
		data.passes = owned
		if premium then
			SeasonRules.normalize(data.season, SeasonConfig.SeasonId)
			data.season.premium = true
		end
	end)
end

function ProductService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	DataService.profileLoaded:connect(function(player: Player)
		task.spawn(refreshPasses, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, _passId: number, purchased: boolean)
			if purchased then
				refreshPasses(player)
				Notifier.celebrate({ player }, "PASS UNLOCKED", "Thanks for supporting the game!")
			end
		end
	)
end

return ProductService

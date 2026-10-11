--!strict
--[[
	ShopController
	The Troop Shop (Troop Depot terminal, or the TROOPS bar's shop button): today's six troops
	(three always in stock, three on the daily rotation) as big 3D cards with stats, role,
	abilities and price, then every other troop greyed out as "back another day".
	The client never decides a purchase: it sends RequestBuyTroop with the troop id only and the
	server answers with an ActionResult. On success a celebration plays and `purchased` fires so
	the Loadout window opens as the equip slot picker.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local TroopRotation = require(ReplicatedStorage.Shared.Logic.TroopRotation)
local Requirements = require(ReplicatedStorage.Shared.Logic.Requirements)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)

local UI = Theme.UI
local ACCENT = UI.Purple

local ROTATION: TroopRotation.RotationSettings = {
	permanent = TroopConfig.Permanent,
	rotatingPool = TroopConfig.RotatingPool,
	rotatingCount = TroopConfig.RotatingCount,
	seed = TroopConfig.RotationSeed,
}

local ShopController = {}
ShopController.rotationSettings = ROTATION
-- Fires with the troop id after the server confirms a purchase.
ShopController.purchased = Signal.new() :: Signal.Signal<string>
ShopController.closed = Signal.new() :: Signal.Signal<()>

local maid = Maid.new()
local contentMaid = Maid.new()
local window: Widgets.Window

-- A short summary of what makes a robot special, derived from its config.
function ShopController.describeRobot(robot: Types.RobotDef): string
	local parts: { string } = {}
	if robot.flying then
		table.insert(parts, "FLYING")
	end
	for _, ability in robot.abilities do
		table.insert(parts, string.upper(ability.kind))
	end
	local immunities = robot.immunities
	if immunities ~= nil then
		for _, immunity in immunities do
			table.insert(parts, `NO {string.upper(immunity)}`)
		end
	end
	return if #parts > 0 then table.concat(parts, "  ") else "NO SPECIAL ABILITY"
end

local function priceText(troop: Types.TroopDef): string
	return `{MathUtil.formatCount(troop.price)} {if troop.currency == "Gems" then "GEMS" else "COINS"}`
end

local function buildCard(parent: Instance, order: number, troopId: string, inStock: boolean, profile: Types.PlayerData)
	local robot = RobotConfig.Robots[troopId]
	local troop = TroopConfig.Troops[troopId]
	local rarity = Theme.rarityColor(robot.rarity)
	local owned = table.find(profile.unlockedRobots, troopId) ~= nil
	local card =
		Widgets.card(parent, rarity, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 150) }, not inStock and not owned)
	Widgets.robotViewport(card, robot, { Size = UDim2.fromOffset(130, 130), Position = UDim2.fromOffset(10, 10) })
	Widgets.label(card, string.upper(robot.displayName), {
		Size = UDim2.new(1, -160, 0, 26),
		Position = UDim2.fromOffset(150, 10),
		Font = Theme.Fonts.Title,
	}, 24)
	Widgets.chip(card, string.upper(robot.rarity), rarity, { Position = UDim2.fromOffset(150, 40) })
	Widgets.chip(
		card,
		string.upper(troop.role),
		UI.Gem,
		{ Position = UDim2.fromOffset(248, 40), Size = UDim2.fromOffset(120, 22) }
	)
	Widgets.label(card, `HP {robot.health}   SPD {robot.speed}   DMG {robot.damage}   COST {robot.cost}`, {
		Size = UDim2.new(1, -160, 0, 18),
		Position = UDim2.fromOffset(150, 68),
		TextColor3 = Color3.fromRGB(190, 198, 228),
	}, 16)
	Widgets.label(card, ShopController.describeRobot(robot), {
		Size = UDim2.new(1, -160, 0, 16),
		Position = UDim2.fromOffset(150, 88),
		TextColor3 = rarity,
		Font = Theme.Fonts.Title,
	}, 14)

	local met = Requirements.isMet(troop.unlock, Requirements.progressOf(profile))
	local balance = if troop.currency == "Gems" then profile.gems else profile.coins
	local text: string
	local enabled = false
	if owned then
		text = "OWNED"
	elseif troop.comingSoon then
		text = "COMING SOON"
	elseif not inStock then
		text = "BACK ANOTHER DAY"
	elseif not met then
		local _, reason = Requirements.check({ troop.unlock }, Requirements.progressOf(profile), "to unlock")
		text = string.upper(reason)
	else
		text = `BUY  {priceText(troop)}`
		enabled = balance >= troop.price
		if not enabled then
			text = `NEED {priceText(troop)}`
		end
	end
	local button = Widgets.button(
		card,
		text,
		if troop.currency == "Gems" then UI.Gem else UI.Gold,
		{
			Size = UDim2.new(1, -164, 0, Widgets.TOUCH),
			Position = UDim2.new(0, 150, 1, -(Widgets.TOUCH + 10)),
		},
		contentMaid,
		function()
			if enabled then
				Remotes.RequestBuyTroop:fire(troopId)
			end
		end
	)
	Widgets.setButton(
		button,
		text,
		if owned then UI.Green elseif troop.currency == "Gems" then UI.Gem else UI.Gold,
		enabled or owned
	)
end

local function section(parent: Instance, order: number, text: string)
	Widgets.label(parent, text, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Title,
		TextColor3 = ACCENT,
	}, 20)
end

local function refresh()
	local profile = ClientState.profile
	if profile == nil or not window.isOpen() then
		return
	end
	contentMaid:cleanup()
	window.clear()
	local now = workspace:GetServerTimeNow()
	local rotation = TroopRotation.forTime(now, ROTATION)
	UIKit.setText(
		window.subtitle,
		`COINS {MathUtil.formatCount(profile.coins)}   GEMS {MathUtil.formatCount(profile.gems)}   -   new troops in {Calendar.formatDuration(
			rotation.resetsAt - now
		)}`
	)
	section(window.body, 1, "IN STOCK TODAY")
	local order = 2
	for _, troopId in TroopRotation.tables(rotation) do
		buildCard(window.body, order, troopId, true, profile)
		order += 1
	end
	section(window.body, order, "OTHER TROOPS")
	order += 1
	for _, troopId in TroopConfig.Order do
		local troop = TroopConfig.Troops[troopId]
		if troop ~= nil and not TroopRotation.inStock(rotation, troopId) and not troop.robuxOnly then
			buildCard(window.body, order, troopId, false, profile)
			order += 1
		end
	end
end

local function onActionResult(result: Types.ActionResult)
	if result.action ~= "BuyTroop" or not result.ok or result.id == nil then
		return
	end
	local troop = TroopConfig.Troops[result.id :: string]
	UIController.celebrate("NEW TROOP!", if troop ~= nil then `{troop.name} joined your swarm. Pick a slot.` else "")
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.6
	SoundService:PlayLocalSound(sound)
	task.delay(2, function()
		sound:Destroy()
	end)
	ShopController.close()
	ShopController.purchased:fire(result.id :: string)
end

function ShopController.open()
	window.open()
	refresh()
end

function ShopController.close()
	window.close()
end

function ShopController.isOpen(): boolean
	return window.isOpen()
end

function ShopController.init()
	window = Widgets.window({
		name = "TroopShop",
		title = "TROOP SHOP",
		accent = ACCENT,
		side = "Right",
		width = 0.36,
		height = 0.78,
		parent = UIController.getLayer("Modal"),
		maid = maid,
		onClose = function()
			contentMaid:cleanup()
			ShopController.closed:fire()
		end,
	})
	maid:give(Remotes.ActionResult:connect(onActionResult))
	maid:give(ClientState.profileChanged:connect(function()
		refresh()
	end))
end

return ShopController

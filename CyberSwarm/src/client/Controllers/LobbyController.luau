--!strict
--[[
	LobbyController
	The lobby HUD that is not navigation:
	- Loadout window (left side): your five equipped slots on top, then every troop as a 3D card
	  in a scrolling grid. Owned troops come first; tap one to equip or unequip it. Troops you do
	  not own point you to the Troop Depot.
	- Queue card (bottom centre): shows the server's queue decision while you stand on a Duels
	  pad. Nothing here can queue a player; pads are the only way in.
	Built once; refreshed in place from ClientState.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local ShopController = require(script.Parent.ShopController)

export type PanelName = "Loadout" | "Armory"

type Card = {
	robotId: string,
	frame: Frame,
	stroke: UIStroke,
	button: TextButton,
}

local UI = Theme.UI
local ACCENT = UI.Pink
local STAT_MAX = { hp = 1500, spd = 18, cost = 250 }

local LobbyController = {}

local maid = Maid.new()
local window: Widgets.Window
local slotsRow: Frame
local slotViews: { Frame } = {}
local grid: Frame
local cards: { Card } = {}
local queueCard: Frame
local queueTitle: TextLabel
local queueStatus: TextLabel
local shownQueueSeconds = -1

local function owned(profile: Types.PlayerData?, robotId: string): boolean
	return profile ~= nil and table.find(profile.unlockedRobots, robotId) ~= nil
end

local function toggleRobot(robotId: string)
	local profile = ClientState.profile
	if profile == nil then
		UIController.showToast(Constants.NoticeText.DATA_NOT_LOADED, "Error")
		return
	end
	local troop = TroopConfig.Troops[robotId]
	if not owned(profile, robotId) then
		if troop ~= nil and troop.robuxOnly then
			UIController.showToast("Exclusive troop: get it in the Robux shop.", "Info")
		else
			UIController.showToast("Buy this troop at the Troop Depot.", "Info")
		end
		return
	end
	local loadout = table.clone(profile.equippedLoadout)
	local index = table.find(loadout, robotId)
	if index ~= nil then
		if #loadout <= 1 then
			UIController.showToast(Constants.NoticeText.LOADOUT_MIN, "Error")
			return
		end
		table.remove(loadout, index)
	else
		if #loadout >= Constants.MAX_LOADOUT then
			UIController.showToast(Constants.NoticeText.LOADOUT_FULL, "Error")
			return
		end
		table.insert(loadout, robotId)
	end
	Remotes.RequestSetLoadout:fire(loadout)
end

local function statRow(parent: Instance, order: number, label: string, value: number, max: number, color: Color3)
	local row =
		UIKit.frame({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Parent = parent })
	Widgets.label(row, label, {
		Size = UDim2.new(0, 34, 1, 0),
		TextColor3 = Color3.fromRGB(150, 158, 190),
		Font = Theme.Fonts.Title,
	}, 12)
	Widgets.bar(row, value / max, color, { Size = UDim2.new(1, -40, 0, 7), Position = UDim2.new(0, 38, 0.5, -3) })
end

local function buildCard(order: number, robotId: string): Card
	local robot = RobotConfig.Robots[robotId]
	local rarity = Theme.rarityColor(robot.rarity)
	local frame = Widgets.card(grid, rarity, { LayoutOrder = order })
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	Widgets.robotViewport(frame, robot, {
		Size = UDim2.new(1, -16, 0, 92),
		Position = UDim2.fromOffset(8, 8),
	})
	Widgets.chip(frame, string.upper(robot.rarity), rarity, {
		Size = UDim2.fromOffset(78, 20),
		Position = UDim2.fromOffset(14, 14),
		ZIndex = 3,
	})
	Widgets.label(frame, string.upper(robot.displayName), {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(10, 104),
		Font = Theme.Fonts.Title,
	}, 20)
	local stats = UIKit.frame({
		Size = UDim2.new(1, -20, 0, 48),
		Position = UDim2.fromOffset(10, 128),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	UIKit.list(stats, Enum.FillDirection.Vertical, UDim.new(0, 3))
	statRow(stats, 1, "HP", robot.health, STAT_MAX.hp, UI.Green)
	statRow(stats, 2, "SPD", robot.speed, STAT_MAX.spd, UI.Gem)
	statRow(stats, 3, "COST", robot.cost, STAT_MAX.cost, UI.Gold)
	local button = Widgets.button(
		frame,
		"EQUIP",
		ACCENT,
		{
			Size = UDim2.new(1, -20, 0, Widgets.TOUCH),
			Position = UDim2.new(0, 10, 1, -(Widgets.TOUCH + 10)),
		},
		maid,
		function()
			toggleRobot(robotId)
		end
	)
	return { robotId = robotId, frame = frame, stroke = stroke, button = button }
end

local function sortCards(profile: Types.PlayerData)
	-- Equipped first (slot order), then owned, then the rest in catalog order.
	for _, card in cards do
		local slot = table.find(profile.equippedLoadout, card.robotId)
		local base = table.find(RobotConfig.Order, card.robotId) or 99
		card.frame.LayoutOrder = if slot ~= nil
			then slot
			elseif owned(profile, card.robotId) then 100 + base
			else 1000 + base
	end
end

local function refreshSlots(profile: Types.PlayerData)
	for index, slot in slotViews do
		for _, child in slot:GetChildren() do
			if child:IsA("ViewportFrame") or child.Name == "Empty" then
				child:Destroy()
			end
		end
		local robotId = profile.equippedLoadout[index]
		local robot = if robotId ~= nil then RobotConfig.Robots[robotId] else nil
		if robot ~= nil then
			Widgets.robotViewport(slot, robot, { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4) })
		else
			Widgets.label(slot, "+", {
				Name = "Empty",
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = Color3.fromRGB(110, 118, 150),
				Font = Theme.Fonts.Title,
			}, 28)
		end
	end
end

local function refreshProfile(profile: Types.PlayerData)
	UIKit.setText(window.title, `LOADOUT  {#profile.equippedLoadout}/{Constants.MAX_LOADOUT}`)
	UIKit.setText(window.subtitle, "Tap a troop to equip it. Exclusive troops never enter ranked.")
	for _, card in cards do
		local slot = table.find(profile.equippedLoadout, card.robotId)
		local troop = TroopConfig.Troops[card.robotId]
		if slot ~= nil then
			Widgets.setButton(card.button, `EQUIPPED #{slot}`, UI.Green, true)
			card.stroke.Transparency = 0
			card.stroke.Thickness = 2.5
		elseif owned(profile, card.robotId) then
			Widgets.setButton(card.button, "EQUIP", ACCENT, true)
			card.stroke.Transparency = 0.35
			card.stroke.Thickness = 1.5
		else
			local text = if troop ~= nil and troop.robuxOnly then "ROBUX SHOP" else "TROOP DEPOT"
			Widgets.setButton(card.button, text, ACCENT, false)
			card.stroke.Transparency = 0.7
			card.stroke.Thickness = 1
		end
	end
	sortCards(profile)
	refreshSlots(profile)
end

local function buildLoadout(layer: Frame)
	window = Widgets.window({
		name = "Loadout",
		title = "LOADOUT",
		accent = ACCENT,
		side = "Left",
		width = 0.33,
		height = 0.76,
		parent = layer,
		maid = maid,
	})
	slotsRow = UIKit.frame({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundTransparency = 1,
		Parent = window.body,
	})
	UIKit.list(slotsRow, Enum.FillDirection.Horizontal, UDim.new(0, 8), Enum.HorizontalAlignment.Center)
	for index = 1, Constants.MAX_LOADOUT do
		local slot = Widgets.card(slotsRow, ACCENT, { LayoutOrder = index, Size = UDim2.fromOffset(70, 70) })
		table.insert(slotViews, slot)
	end
	grid = UIKit.frame({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = window.body,
	})
	UIKit.create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 236),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for order, robotId in RobotConfig.Order do
		table.insert(cards, buildCard(order, robotId))
	end
end

local function secondsUntil(serverTime: number): number
	return math.max(0, math.ceil(serverTime - workspace:GetServerTimeNow()))
end

local function updateQueueStatus(queue: Types.QueueSnapshot, force: boolean)
	local endsAt = queue.countdownEndsAt
	local party = if queue.viaParty then "  (PARTY)" else ""
	if endsAt == nil then
		shownQueueSeconds = -1
		UIKit.setText(queueStatus, `{queue.count}/{queue.matchSize} QUEUED{party}  -  stay on the pad`)
		return
	end
	local remaining = secondsUntil(endsAt)
	if remaining ~= shownQueueSeconds or force then
		shownQueueSeconds = remaining
		UIKit.setText(queueStatus, `{queue.count}/{queue.matchSize} QUEUED{party}  -  LAUNCHING IN {remaining}`)
	end
end

local function refreshQueue(queue: Types.QueueSnapshot)
	local modeId = queue.modeId
	maid:clear("queueTicker")
	if modeId == nil then
		queueCard.Visible = false
		return
	end
	local mode = ModeConfig.Modes[modeId]
	UIKit.setText(queueTitle, `QUEUED: {string.upper(mode.displayName)}`)
	queueTitle.TextColor3 = mode.signColor
	queueCard.Visible = true
	updateQueueStatus(queue, true)
	if queue.countdownEndsAt ~= nil then
		maid:set(
			"queueTicker",
			RunService.Heartbeat:Connect(function()
				updateQueueStatus(queue, false)
			end)
		)
	end
end

local function buildQueueCard(layer: Frame)
	queueCard = Widgets.card(layer, UI.Gem, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(440, 74),
		Visible = false,
	})
	queueTitle = Widgets.label(queueCard, "", {
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 8),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 24)
	queueStatus = Widgets.label(queueCard, "", {
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(200, 210, 240),
	}, 18)
end

-- Used by the nav bar and in-world terminals.
function LobbyController.openPanel(name: PanelName)
	if name == "Armory" then
		ShopController.open()
		return
	end
	if window.isOpen() then
		window.close()
	else
		window.open()
	end
end

function LobbyController.init()
	local layer = UIController.getLayer("Lobby")
	buildLoadout(layer)
	buildQueueCard(layer)

	maid:give(ClientState.profileChanged:connect(refreshProfile))
	maid:give(ClientState.queueChanged:connect(refreshQueue))
	-- After buying a troop the Loadout window opens as the equip slot picker.
	maid:give(ShopController.purchased:connect(function()
		window.open()
	end))
	maid:give(ClientState.matchChanged:connect(function()
		queueCard.Visible = false
		maid:clear("queueTicker")
		Widgets.closeAll()
	end))
	local profile = ClientState.profile
	if profile ~= nil then
		refreshProfile(profile)
	end
end

return LobbyController

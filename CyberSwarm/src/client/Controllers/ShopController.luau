--!strict
--[[
	ShopController
	The Armory: a modal where players unlock new robots with profile coins. Rows are built once
	from RobotConfig and only re-coloured when the profile changes. The client never decides a
	purchase; it sends RequestUnlockRobot and waits for the server's updated profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)

local ROW_HEIGHT = 120
-- The Armory opens beside the lobby's side rail, like the Play and Loadout panels.
local PANEL_X = 0.135
local PANEL_SLIDE_FROM = 0.115
local ROW_GAP = 10

type Row = {
	robotId: string,
	button: TextButton,
	stroke: UIStroke,
}

local ShopController = {}

-- Fires when the panel closes (its X button or another panel opening), so the rail can update.
ShopController.closed = Signal.new() :: Signal.Signal<()>

local maid = Maid.new()
local panel: Frame
local coinsLabel: TextLabel
local rows: { Row } = {}

-- A one-line summary of what makes a robot special, derived from its config.
function ShopController.describeRobot(robot: Types.RobotDef): string
	local parts = { `HP {robot.health}`, `SPD {robot.speed}`, `DMG {robot.damage}`, `COST {robot.cost}` }
	if robot.flying then
		table.insert(parts, "FLYING")
	end
	for _, ability in robot.abilities do
		table.insert(parts, string.upper(ability.kind))
	end
	return table.concat(parts, "  |  ")
end

local function refresh(profile: Types.PlayerData?)
	local coins = if profile ~= nil then profile.coins else 0
	UIKit.setText(coinsLabel, `COINS {MathUtil.formatCount(coins)}`)
	for _, row in rows do
		local robot = RobotConfig.Robots[row.robotId]
		local owned = profile ~= nil and table.find(profile.unlockedRobots, row.robotId) ~= nil
		if robot.locked then
			UIKit.setText(row.button, "COMING SOON")
			row.button.BackgroundColor3 = Theme.Colors.PanelDark
			row.button.TextColor3 = Theme.Colors.TextDim
			row.stroke.Color = Theme.Colors.TextDim
		elseif owned then
			UIKit.setText(row.button, "OWNED")
			row.button.BackgroundColor3 = Theme.Colors.PanelDark
			row.button.TextColor3 = Theme.Colors.Success
			row.stroke.Color = Theme.Colors.Success
		else
			local affordable = coins >= robot.unlockCost
			UIKit.setText(row.button, `UNLOCK  {MathUtil.formatCount(robot.unlockCost)}`)
			row.button.BackgroundColor3 = if affordable then Theme.Colors.Primary else Theme.Colors.PanelLight
			row.button.TextColor3 = if affordable then Theme.Colors.PanelDark else Theme.Colors.TextDim
			row.stroke.Color = Theme.Colors.Primary
		end
	end
end

local function buildRow(list: ScrollingFrame, robotId: string, order: number)
	local robot = RobotConfig.Robots[robotId]
	local rarityColor = Theme.rarityColor(robot.rarity)

	local frame = UIKit.frame({
		Name = robotId,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = list,
	})
	UIKit.corner(frame)
	UIKit.stroke(frame, rarityColor, 1.5, 0.3)

	UIKit.frame({
		Name = "RarityBar",
		Size = UDim2.new(0, 8, 1, 0),
		BackgroundColor3 = rarityColor,
		Parent = frame,
	})
	UIKit.label({
		Size = UDim2.fromScale(0.5, 0.32),
		Position = UDim2.fromScale(0.04, 0.08),
		Font = Theme.Fonts.Title,
		Text = string.upper(robot.displayName),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, Theme.Text.HEADER_MAX)
	UIKit.label({
		Size = UDim2.fromScale(0.2, 0.22),
		Position = UDim2.fromScale(0.5, 0.12),
		Text = string.upper(robot.rarity),
		TextColor3 = rarityColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, Theme.Text.SMALL_MAX)
	UIKit.label({
		Size = UDim2.fromScale(0.66, 0.26),
		Position = UDim2.fromScale(0.04, 0.42),
		Font = Theme.Fonts.Light,
		Text = robot.description,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, Theme.Text.SMALL_MAX)
	UIKit.label({
		Size = UDim2.fromScale(0.66, 0.2),
		Position = UDim2.fromScale(0.04, 0.72),
		Text = ShopController.describeRobot(robot),
		TextColor3 = Theme.Colors.Primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, Theme.Text.SMALL_MAX)

	local button = UIKit.button({
		Size = UDim2.fromScale(0.25, 0.5),
		Position = UDim2.fromScale(0.72, 0.25),
		Parent = frame,
	}, Theme.Text.BODY_MAX)
	local stroke = UIKit.stroke(button, Theme.Colors.Primary)
	UIKit.bindButton(button, maid, function()
		local profile = ClientState.profile
		if robot.locked or profile == nil or table.find(profile.unlockedRobots, robotId) ~= nil then
			return
		end
		Remotes.RequestUnlockRobot:fire(robotId)
	end)

	table.insert(rows, { robotId = robotId, button = button, stroke = stroke })
end

function ShopController.open()
	if panel.Visible then
		return
	end
	refresh(ClientState.profile)
	panel.Position = UDim2.fromScale(PANEL_SLIDE_FROM, 0.5)
	panel.Visible = true
	UIKit.tween(panel, Theme.Tween.Normal, { Position = UDim2.fromScale(PANEL_X, 0.5) })
end

function ShopController.close()
	if not panel.Visible then
		return
	end
	panel.Visible = false
	ShopController.closed:fire()
end

function ShopController.isOpen(): boolean
	return panel.Visible
end

function ShopController.init()
	local modal = UIController.getLayer("Modal")
	panel = UIKit.frame({
		Name = "Armory",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(PANEL_X, 0.5),
		Size = UDim2.fromScale(0.5, 0.78),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = modal,
	})
	UIKit.corner(panel)
	UIKit.stroke(panel, Theme.Colors.Secondary, 3)

	UIKit.label({
		Size = UDim2.fromScale(0.5, 0.08),
		Position = UDim2.fromScale(0.04, 0.03),
		Font = Theme.Fonts.Title,
		Text = "ARMORY",
		TextColor3 = Theme.Colors.Secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, Theme.Text.TITLE_MAX)
	coinsLabel = UIKit.label({
		Size = UDim2.fromScale(0.3, 0.05),
		Position = UDim2.fromScale(0.52, 0.045),
		Text = "COINS 0",
		TextColor3 = Theme.Colors.Warning,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	}, Theme.Text.HEADER_MAX)

	local closeButton = UIKit.button({
		Size = UDim2.fromScale(0.08, 0.08),
		Position = UDim2.fromScale(0.88, 0.03),
		Text = "X",
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = panel,
	}, Theme.Text.HEADER_MAX)
	UIKit.aspect(closeButton, 1)
	UIKit.bindButton(closeButton, maid, ShopController.close)

	local list = UIKit.create("ScrollingFrame", {
		Name = "Robots",
		Size = UDim2.fromScale(0.92, 0.82),
		Position = UDim2.fromScale(0.04, 0.14),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Primary,
		Parent = panel,
	}) :: ScrollingFrame
	UIKit.list(list, Enum.FillDirection.Vertical, UDim.new(0, ROW_GAP))

	for order, robotId in RobotConfig.Order do
		buildRow(list, robotId, order)
	end

	maid:give(ClientState.profileChanged:connect(refresh))
	refresh(ClientState.profile)
end

return ShopController

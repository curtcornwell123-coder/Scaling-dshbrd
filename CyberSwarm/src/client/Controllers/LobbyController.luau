--!strict
--[[
	LobbyController
	The hub screen: coin display, Play buttons for each mode, queue status with a leave button, and
	the loadout editor. Every card is built once at startup and refreshed in place from
	ClientState, so profile updates never rebuild UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local ShopController = require(script.Parent.ShopController)

type RobotCard = {
	robotId: string,
	button: TextButton,
	stroke: UIStroke,
	status: TextLabel,
}

local LobbyController = {}

local maid = Maid.new()
local coinsLabel: TextLabel
local statsLabel: TextLabel
local loadoutHeader: TextLabel
local queuePanel: Frame
local queueTitle: TextLabel
local queueStatus: TextLabel
local cards: { RobotCard } = {}

local function playerCountText(mode: Types.ModeDef): string
	if mode.minPlayers == mode.maxPlayers then
		return if mode.maxPlayers == 1 then "1 PLAYER" else `{mode.maxPlayers} PLAYERS`
	end
	return `{mode.minPlayers}-{mode.maxPlayers} PLAYERS`
end

local function toggleRobot(robotId: string)
	local profile = ClientState.profile
	if profile == nil then
		UIController.showToast(Constants.NoticeText.DATA_NOT_LOADED, "Error")
		return
	end
	local robot = RobotConfig.Robots[robotId]
	if robot.locked then
		UIController.showToast(Constants.NoticeText.ROBOT_LOCKED, "Info")
		return
	end
	if table.find(profile.unlockedRobots, robotId) == nil then
		UIController.showToast(Constants.NoticeText.BUY_IN_ARMORY, "Info")
		ShopController.open()
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

local function refreshProfile(profile: Types.PlayerData)
	UIKit.setText(coinsLabel, `COINS {MathUtil.formatCount(profile.coins)}   GEMS {MathUtil.formatCount(profile.gems)}`)
	local stats = profile.stats
	UIKit.setText(statsLabel, `WINS {stats.wins}   LOSSES {stats.losses}   BEST WAVE {stats.highestWave}`)
	UIKit.setText(loadoutHeader, `LOADOUT  {#profile.equippedLoadout}/{Constants.MAX_LOADOUT}`)

	for _, card in cards do
		local robot = RobotConfig.Robots[card.robotId]
		local equippedSlot = table.find(profile.equippedLoadout, card.robotId)
		local owned = table.find(profile.unlockedRobots, card.robotId) ~= nil
		if equippedSlot ~= nil then
			UIKit.setText(card.status, `EQUIPPED  #{equippedSlot}`)
			card.status.TextColor3 = Theme.Colors.Primary
			card.stroke.Color = Theme.Colors.Primary
			card.stroke.Thickness = 3
			card.button.BackgroundColor3 = Theme.Colors.PanelLight
		elseif owned then
			UIKit.setText(card.status, "TAP TO EQUIP")
			card.status.TextColor3 = Theme.Colors.TextDim
			card.stroke.Color = Theme.rarityColor(robot.rarity)
			card.stroke.Thickness = 1.5
			card.button.BackgroundColor3 = Theme.Colors.Panel
		else
			UIKit.setText(card.status, if robot.locked then "COMING SOON" else `LOCKED  {MathUtil.formatCount(robot.unlockCost)}`)
			card.status.TextColor3 = Theme.Colors.Secondary
			card.stroke.Color = Theme.Colors.PanelLight
			card.stroke.Thickness = 1.5
			card.button.BackgroundColor3 = Theme.Colors.PanelDark
		end
	end
end

local shownQueueSeconds = -1

local function updateQueueCountdown(queue: Types.QueueSnapshot, force: boolean)
	local endsAt = queue.countdownEndsAt
	if endsAt == nil then
		shownQueueSeconds = -1
		UIKit.setText(queueStatus, `{queue.count}/{queue.capacity} READY  -  NEED {queue.required}`)
		return
	end
	local remaining = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
	-- Only build a new string when the visible number changes.
	if remaining ~= shownQueueSeconds or force then
		shownQueueSeconds = remaining
		UIKit.setText(queueStatus, `LAUNCHING IN {remaining}`)
	end
end

local function refreshQueue(queue: Types.QueueSnapshot)
	local modeId = queue.modeId
	maid:clear("queueTicker")
	if modeId == nil then
		queuePanel.Visible = false
		return
	end
	local mode = ModeConfig.Modes[modeId]
	UIKit.setText(queueTitle, `QUEUED: {string.upper(mode.displayName)}`)
	queuePanel.Visible = true
	updateQueueCountdown(queue, true)
	if queue.countdownEndsAt ~= nil then
		maid:set("queueTicker", RunService.Heartbeat:Connect(function()
			updateQueueCountdown(queue, false)
		end))
	end
end

local function buildTopBar(layer: Frame)
	local bar = UIKit.frame({
		Name = "TopBar",
		Size = UDim2.fromScale(1, 0.085),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		Parent = layer,
	})
	UIKit.gradient(bar, Theme.Colors.PanelDark, Theme.Colors.Panel, 0)
	UIKit.frame({
		Name = "Accent",
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Primary,
		Parent = bar,
	})
	UIKit.label({
		Size = UDim2.fromScale(0.3, 0.7),
		Position = UDim2.fromScale(0.02, 0.15),
		Font = Theme.Fonts.Title,
		Text = string.upper(Constants.GAME_NAME),
		TextColor3 = Theme.Colors.Primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	}, Theme.Text.TITLE_MAX)
	coinsLabel = UIKit.label({
		Size = UDim2.fromScale(0.3, 0.5),
		Position = UDim2.fromScale(0.52, 0.25),
		Text = "COINS 0",
		TextColor3 = Theme.Colors.Warning,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = bar,
	}, Theme.Text.HEADER_MAX)

	local shopButton = UIKit.button({
		Size = UDim2.fromScale(0.12, 0.7),
		Position = UDim2.fromScale(0.86, 0.15),
		Text = "ARMORY",
		BackgroundColor3 = Theme.Colors.Secondary,
		TextColor3 = Theme.Colors.PanelDark,
		Parent = bar,
	}, Theme.Text.HEADER_MAX)
	UIKit.bindButton(shopButton, maid, ShopController.toggle)
end

local function buildPlayPanel(layer: Frame)
	local panel = UIKit.frame({
		Name = "Play",
		Position = UDim2.fromScale(0.02, 0.13),
		Size = UDim2.fromScale(0.27, 0.62),
		BackgroundTransparency = 0.1,
		Parent = layer,
	})
	UIKit.corner(panel)
	UIKit.stroke(panel, Theme.Colors.Primary, 2, 0.3)

	UIKit.label({
		Size = UDim2.fromScale(0.9, 0.09),
		Position = UDim2.fromScale(0.05, 0.03),
		Font = Theme.Fonts.Title,
		Text = "DEPLOY",
		TextColor3 = Theme.Colors.Primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, Theme.Text.HEADER_MAX)

	local list = UIKit.frame({
		Size = UDim2.fromScale(0.9, 0.72),
		Position = UDim2.fromScale(0.05, 0.14),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.list(list, Enum.FillDirection.Vertical, UDim.new(0.03, 0))

	for order, modeId in ModeConfig.Order do
		local mode = ModeConfig.Modes[modeId]
		local button = UIKit.button({
			Name = modeId,
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0.3),
			BackgroundColor3 = Theme.Colors.PanelLight,
			Parent = list,
		})
		UIKit.stroke(button, mode.padColor, 2)
		UIKit.label({
			Size = UDim2.fromScale(0.62, 0.45),
			Position = UDim2.fromScale(0.05, 0.1),
			Font = Theme.Fonts.Title,
			Text = string.upper(mode.displayName),
			TextColor3 = mode.padColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		}, Theme.Text.HEADER_MAX)
		UIKit.label({
			Size = UDim2.fromScale(0.32, 0.3),
			Position = UDim2.fromScale(0.64, 0.15),
			Text = playerCountText(mode),
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = button,
		}, Theme.Text.SMALL_MAX)
		UIKit.label({
			Size = UDim2.fromScale(0.9, 0.3),
			Position = UDim2.fromScale(0.05, 0.6),
			Font = Theme.Fonts.Light,
			Text = mode.description,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		}, Theme.Text.SMALL_MAX)
		UIKit.bindButton(button, maid, function()
			Remotes.RequestJoinQueue:fire(modeId)
		end)
	end

	statsLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.06),
		Position = UDim2.fromScale(0.05, 0.9),
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, Theme.Text.SMALL_MAX)
end

local function buildQueuePanel(layer: Frame)
	queuePanel = UIKit.frame({
		Name = "Queue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.36, 0.12),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = layer,
	})
	UIKit.corner(queuePanel)
	UIKit.stroke(queuePanel, Theme.Colors.Secondary, 2)
	queueTitle = UIKit.label({
		Size = UDim2.fromScale(0.62, 0.42),
		Position = UDim2.fromScale(0.04, 0.1),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = queuePanel,
	}, Theme.Text.HEADER_MAX)
	queueStatus = UIKit.label({
		Size = UDim2.fromScale(0.62, 0.34),
		Position = UDim2.fromScale(0.04, 0.56),
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = queuePanel,
	}, Theme.Text.BODY_MAX)
	local leave = UIKit.button({
		Size = UDim2.fromScale(0.28, 0.64),
		Position = UDim2.fromScale(0.69, 0.18),
		Text = "LEAVE",
		BackgroundColor3 = Theme.Colors.Danger,
		Parent = queuePanel,
	}, Theme.Text.HEADER_MAX)
	UIKit.bindButton(leave, maid, function()
		Remotes.RequestLeaveQueue:fire()
	end)
end

local function buildLoadoutPanel(layer: Frame)
	local panel = UIKit.frame({
		Name = "Loadout",
		Position = UDim2.fromScale(0.69, 0.13),
		Size = UDim2.fromScale(0.29, 0.8),
		BackgroundTransparency = 0.1,
		Parent = layer,
	})
	UIKit.corner(panel)
	UIKit.stroke(panel, Theme.Colors.Secondary, 2, 0.3)

	loadoutHeader = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.06),
		Position = UDim2.fromScale(0.05, 0.025),
		Font = Theme.Fonts.Title,
		Text = "LOADOUT",
		TextColor3 = Theme.Colors.Secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, Theme.Text.HEADER_MAX)

	local grid = UIKit.frame({
		Size = UDim2.fromScale(0.92, 0.86),
		Position = UDim2.fromScale(0.04, 0.11),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.create("UIGridLayout", {
		CellSize = UDim2.fromScale(0.48, 0.23),
		CellPadding = UDim2.fromScale(0.04, 0.025),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	for order, robotId in RobotConfig.Order do
		local robot = RobotConfig.Robots[robotId]
		local button = UIKit.button({
			Name = robotId,
			LayoutOrder = order,
			BackgroundColor3 = Theme.Colors.Panel,
			Parent = grid,
		})
		local stroke = UIKit.stroke(button, Theme.rarityColor(robot.rarity), 1.5)
		UIKit.frame({
			Name = "Swatch",
			Size = UDim2.fromScale(0.16, 0.22),
			Position = UDim2.fromScale(0.06, 0.1),
			BackgroundColor3 = robot.visual.color,
			Parent = button,
		})
		UIKit.label({
			Size = UDim2.fromScale(0.7, 0.28),
			Position = UDim2.fromScale(0.26, 0.08),
			Font = Theme.Fonts.Title,
			Text = string.upper(robot.displayName),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		}, Theme.Text.BODY_MAX)
		UIKit.label({
			Size = UDim2.fromScale(0.88, 0.22),
			Position = UDim2.fromScale(0.06, 0.42),
			Font = Theme.Fonts.Light,
			Text = `HP {robot.health}  SPD {robot.speed}  COST {robot.cost}`,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		}, Theme.Text.SMALL_MAX)
		local status = UIKit.label({
			Size = UDim2.fromScale(0.88, 0.22),
			Position = UDim2.fromScale(0.06, 0.7),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		}, Theme.Text.SMALL_MAX)
		UIKit.bindButton(button, maid, function()
			toggleRobot(robotId)
		end)
		table.insert(cards, { robotId = robotId, button = button, stroke = stroke, status = status })
	end
end

function LobbyController.init()
	local layer = UIController.getLayer("Lobby")
	buildTopBar(layer)
	buildPlayPanel(layer)
	buildQueuePanel(layer)
	buildLoadoutPanel(layer)

	maid:give(ClientState.profileChanged:connect(refreshProfile))
	maid:give(ClientState.queueChanged:connect(refreshQueue))
	-- Entering a match clears any queue display left over from the lobby.
	maid:give(ClientState.matchChanged:connect(function()
		if queuePanel.Visible then
			queuePanel.Visible = false
			maid:clear("queueTicker")
		end
	end))

	local profile = ClientState.profile
	if profile ~= nil then
		refreshProfile(profile)
	end
end

return LobbyController

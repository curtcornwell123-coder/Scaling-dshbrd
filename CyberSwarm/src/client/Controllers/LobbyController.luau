--!strict
--[[
	LobbyController
	The hub screen. A top bar on the right shows the player's name, Coins, Gems, and the Armory
	button. A side rail on the left (DEPLOY / LOADOUT) opens one panel at a time beside it, so the
	lobby world stays visible. Nothing here can queue a player: queues are joined only by standing
	on a pad in the world, so the Deploy panel is information only (modes and live pad counts), and
	the queue panel at the bottom just reports the server's decision.
	Every element is built once and refreshed in place from ClientState.
]]

local Players = game:GetService("Players")
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

type PanelName = "Deploy" | "Loadout" | "Armory"

type RailButton = {
	name: PanelName,
	button: TextButton,
	title: TextLabel,
	subtitle: TextLabel,
	color: Color3,
}

type RobotCard = {
	robotId: string,
	button: TextButton,
	stroke: UIStroke,
	status: TextLabel,
}

type ModeCard = {
	live: TextLabel,
	shownCount: number,
	shownSeconds: number,
}

-- Panels open just right of the rail and slide in from slightly further left.
local PANEL_X = 0.135
local PANEL_SLIDE_FROM = 0.115

local LobbyController = {}

local maid = Maid.new()
local coinsLabel: TextLabel
local gemsLabel: TextLabel
local statsLabel: TextLabel
local loadoutHeader: TextLabel
local armoryButton: TextButton
local queuePanel: Frame
local queueTitle: TextLabel
local queueStatus: TextLabel
local cards: { RobotCard } = {}
local modeCards: { [string]: ModeCard } = {}
local railButtons: { RailButton } = {}
local panels: { [string]: Frame } = {}
local openPanel: PanelName? = nil
local shownQueueSeconds = -1
local boardTicking = false
-- Defined below; declared here because robot cards open the Armory through it.
local setPanel: (name: PanelName?) -> ()

local function playerCountText(mode: Types.ModeDef): string
	if mode.minPlayers == mode.maxPlayers then
		return if mode.maxPlayers == 1 then "1 PLAYER" else `{mode.maxPlayers} PLAYERS`
	end
	return `{mode.minPlayers}-{mode.maxPlayers} PLAYERS`
end

local function secondsUntil(serverTime: number): number
	return math.max(0, math.ceil(serverTime - workspace:GetServerTimeNow()))
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
		setPanel("Armory")
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
	UIKit.setText(coinsLabel, `COINS {MathUtil.formatCount(profile.coins)}`)
	UIKit.setText(gemsLabel, `GEMS {MathUtil.formatCount(profile.gems)}`)
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
			card.stroke.Thickness = 2.5
			card.button.BackgroundColor3 = Theme.Colors.PanelLight
		elseif owned then
			UIKit.setText(card.status, "TAP TO EQUIP")
			card.status.TextColor3 = Theme.Colors.TextDim
			card.stroke.Color = Theme.rarityColor(robot.rarity)
			card.stroke.Thickness = 1.5
			card.button.BackgroundColor3 = Theme.Colors.Panel
		else
			UIKit.setText(card.status, if robot.locked then "COMING SOON" else "BUY IN TROOP DEPOT")
			card.status.TextColor3 = Theme.Colors.Secondary
			card.stroke.Color = Theme.Colors.PanelLight
			card.stroke.Thickness = 1.5
			card.button.BackgroundColor3 = Theme.Colors.PanelDark
		end
	end
end

-- Live pad counts in the Deploy panel. Strings are only rebuilt when a number on screen changes.
local function renderBoard(board: { Types.QueueBoardEntry })
	local counting = false
	for _, entry in board do
		local card = modeCards[entry.modeId]
		if card ~= nil then
			local endsAt = entry.countdownEndsAt
			local seconds = if endsAt ~= nil then secondsUntil(endsAt) else -1
			if endsAt ~= nil then
				counting = true
			end
			if seconds ~= card.shownSeconds or entry.count ~= card.shownCount then
				card.shownSeconds = seconds
				card.shownCount = entry.count
				card.live.Text = if seconds >= 0
					then `ON PAD {entry.count}/{entry.matchSize}  -  STARTING IN {seconds}`
					else `ON PAD {entry.count}/{entry.matchSize}`
				card.live.TextColor3 = if seconds >= 0 then Theme.Colors.Success else Theme.Colors.TextDim
			end
		end
	end
	-- A per-frame ticker only runs while some pad is counting down, and is connected once.
	if counting and not boardTicking then
		boardTicking = true
		maid:set(
			"boardTicker",
			RunService.Heartbeat:Connect(function()
				renderBoard(ClientState.queueBoard)
			end)
		)
	elseif not counting and boardTicking then
		boardTicking = false
		maid:clear("boardTicker")
	end
end

local function updateQueueStatus(queue: Types.QueueSnapshot, force: boolean)
	local endsAt = queue.countdownEndsAt
	if endsAt == nil then
		shownQueueSeconds = -1
		UIKit.setText(queueStatus, `{queue.count}/{queue.matchSize} QUEUED{if queue.viaParty then " (PARTY)" else ""}`)
		return
	end
	local remaining = secondsUntil(endsAt)
	if remaining ~= shownQueueSeconds or force then
		shownQueueSeconds = remaining
		UIKit.setText(queueStatus, `{queue.count}/{queue.matchSize} QUEUED  -  LAUNCHING IN {remaining}`)
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
	queueTitle.TextColor3 = mode.signColor
	queuePanel.Visible = true
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

-- Shows one panel at a time; picking the open panel's button again closes it.
setPanel = function(name: PanelName?)
	if name == openPanel then
		name = nil
	end
	openPanel = name
	for panelName, frame in panels do
		local show = panelName == name
		if show and not frame.Visible then
			frame.Position = UDim2.fromScale(PANEL_SLIDE_FROM, 0.5)
			frame.Visible = true
			UIKit.tween(frame, Theme.Tween.Normal, { Position = UDim2.fromScale(PANEL_X, 0.5) })
		elseif not show then
			frame.Visible = false
		end
	end
	if name == "Armory" then
		ShopController.open()
	else
		ShopController.close()
	end
	for _, railButton in railButtons do
		local selected = railButton.name == name
		railButton.button.BackgroundColor3 = if selected then railButton.color else Theme.Colors.PanelDark
		railButton.title.TextColor3 = if selected then Theme.Colors.PanelDark else railButton.color
		railButton.subtitle.TextColor3 = if selected then Theme.Colors.PanelDark else Theme.Colors.TextDim
	end
	local armoryOpen = name == "Armory"
	armoryButton.BackgroundColor3 = if armoryOpen then Theme.Colors.Warning else Theme.Colors.PanelDark
	armoryButton.TextColor3 = if armoryOpen then Theme.Colors.PanelDark else Theme.Colors.Warning
end

local function topBarChip(parent: Instance, order: number, width: number, color: Color3, text: string): TextLabel
	local chip = UIKit.frame({
		LayoutOrder = order,
		Size = UDim2.fromScale(width, 1),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		Parent = parent,
	})
	UIKit.corner(chip, UDim.new(0.5, 0))
	UIKit.stroke(chip, color, 1.5, 0.4)
	return UIKit.label({
		Size = UDim2.fromScale(0.86, 0.6),
		Position = UDim2.fromScale(0.07, 0.2),
		Text = text,
		TextColor3 = color,
		Parent = chip,
	}, Theme.Text.BODY_MAX)
end

-- Top bar: player name, Coins, Gems, and the Armory button. No game name or logo.
local function buildTopBar(layer: Frame)
	local bar = UIKit.frame({
		Name = "TopBar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.985, 0.02),
		Size = UDim2.fromScale(0.56, 0.055),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(bar, Enum.FillDirection.Horizontal, UDim.new(0.012, 0), Enum.HorizontalAlignment.Right)

	topBarChip(bar, 1, 0.3, Theme.Colors.Text, Players.LocalPlayer.DisplayName)
	coinsLabel = topBarChip(bar, 2, 0.22, Theme.Colors.Warning, "COINS 0")
	gemsLabel = topBarChip(bar, 3, 0.18, Theme.Colors.Primary, "GEMS 0")
	-- Coins and gems are shown top-centre with "+" buttons (NavController); these stay hidden.
	for _, label in { coinsLabel, gemsLabel } do
		local chip = label.Parent
		if chip ~= nil and chip:IsA("GuiObject") then
			chip.Visible = false
		end
	end

	armoryButton = UIKit.button({
		Name = "Armory",
		LayoutOrder = 4,
		Size = UDim2.fromScale(0.22, 1),
		Text = "ARMORY",
		BackgroundColor3 = Theme.Colors.PanelDark,
		TextColor3 = Theme.Colors.Warning,
		Parent = bar,
	}, Theme.Text.BODY_MAX)
	UIKit.stroke(armoryButton, Theme.Colors.Warning, 1.5, 0.2)
	UIKit.bindButton(armoryButton, maid, function()
		setPanel("Armory")
	end)
end

local RAIL_ENTRIES: { { name: PanelName, title: string, subtitle: string, color: Color3 } } = {
	{ name = "Deploy", title = "DEPLOY", subtitle = "Modes & pads", color = Theme.Colors.Primary },
	{ name = "Loadout", title = "LOADOUT", subtitle = "Equip robots", color = Theme.Colors.Secondary },
}

local function buildSideRail(layer: Frame)
	local rail = UIKit.frame({
		Name = "SideRail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.012, 0.5),
		Size = UDim2.fromScale(0.11, 0.3),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(rail, Enum.FillDirection.Vertical, UDim.new(0.06, 0))

	for order, entry in RAIL_ENTRIES do
		-- Big buttons: easy to hit on touch screens, quiet when not selected.
		local button = UIKit.button({
			Name = entry.name,
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0.47),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.1,
			Parent = rail,
		})
		UIKit.stroke(button, entry.color, 1.5, 0.3)
		local title = UIKit.label({
			Size = UDim2.fromScale(0.86, 0.46),
			Position = UDim2.fromScale(0.07, 0.14),
			Font = Theme.Fonts.Title,
			Text = entry.title,
			TextColor3 = entry.color,
			Parent = button,
		}, Theme.Text.HEADER_MAX)
		local subtitle = UIKit.label({
			Size = UDim2.fromScale(0.86, 0.24),
			Position = UDim2.fromScale(0.07, 0.64),
			Font = Theme.Fonts.Light,
			Text = entry.subtitle,
			TextColor3 = Theme.Colors.TextDim,
			Parent = button,
		}, Theme.Text.SMALL_MAX)
		UIKit.bindButton(button, maid, function()
			setPanel(entry.name)
		end)
		table.insert(railButtons, {
			name = entry.name,
			button = button,
			title = title,
			subtitle = subtitle,
			color = entry.color,
		})
	end
end

-- Information only: mode names, descriptions, and how many players stand on each pad.
local function buildDeployPanel(layer: Frame)
	local panel = UIKit.frame({
		Name = "Deploy",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(PANEL_X, 0.5),
		Size = UDim2.fromScale(0.3, 0.62),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = layer,
	})
	panels.Deploy = panel
	UIKit.corner(panel)
	UIKit.stroke(panel, Theme.Colors.Primary, 1.5, 0.35)

	UIKit.label({
		Size = UDim2.fromScale(0.9, 0.08),
		Position = UDim2.fromScale(0.05, 0.03),
		Font = Theme.Fonts.Title,
		Text = "MODES",
		TextColor3 = Theme.Colors.Primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, Theme.Text.HEADER_MAX)

	local list = UIKit.frame({
		Size = UDim2.fromScale(0.9, 0.74),
		Position = UDim2.fromScale(0.05, 0.13),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.list(list, Enum.FillDirection.Vertical, UDim.new(0.01, 0))

	-- Info only: the Duels Hall bays, in bay order. Joining happens on the pads, never here.
	for order, mode in ModeConfig.bayModes() do
		local modeId = mode.id
		local card = UIKit.frame({
			Name = modeId,
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0.155),
			BackgroundColor3 = Theme.Colors.PanelLight,
			Parent = list,
		})
		UIKit.corner(card)
		UIKit.stroke(card, mode.signColor, 1.5, 0.35)
		UIKit.label({
			Size = UDim2.fromScale(0.6, 0.34),
			Position = UDim2.fromScale(0.05, 0.08),
			Font = Theme.Fonts.Title,
			Text = string.upper(mode.displayName),
			TextColor3 = mode.signColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		}, Theme.Text.HEADER_MAX)
		UIKit.label({
			Size = UDim2.fromScale(0.34, 0.24),
			Position = UDim2.fromScale(0.62, 0.12),
			Text = playerCountText(mode),
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		}, Theme.Text.SMALL_MAX)
		UIKit.label({
			Size = UDim2.fromScale(0.9, 0.26),
			Position = UDim2.fromScale(0.05, 0.44),
			Font = Theme.Fonts.Light,
			Text = mode.description,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		}, Theme.Text.SMALL_MAX)
		local live = UIKit.label({
			Size = UDim2.fromScale(0.9, 0.22),
			Position = UDim2.fromScale(0.05, 0.72),
			Text = `ON PAD 0/{mode.maxPlayers}`,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		}, Theme.Text.SMALL_MAX)
		modeCards[modeId] = { live = live, shownCount = 0, shownSeconds = -1 }
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

-- Status only (no buttons): appears while the server has the player in a pad's queue.
local function buildQueuePanel(layer: Frame)
	queuePanel = UIKit.frame({
		Name = "Queue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.3, 0.1),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = layer,
	})
	UIKit.corner(queuePanel)
	UIKit.stroke(queuePanel, Theme.Colors.Secondary, 1.5, 0.3)
	queueTitle = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.44),
		Position = UDim2.fromScale(0.05, 0.08),
		Font = Theme.Fonts.Title,
		Parent = queuePanel,
	}, Theme.Text.HEADER_MAX)
	queueStatus = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.34),
		Position = UDim2.fromScale(0.05, 0.56),
		TextColor3 = Theme.Colors.Text,
		Parent = queuePanel,
	}, Theme.Text.BODY_MAX)
end

local function buildLoadoutPanel(layer: Frame)
	local panel = UIKit.frame({
		Name = "Loadout",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(PANEL_X, 0.5),
		Size = UDim2.fromScale(0.32, 0.78),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = layer,
	})
	panels.Loadout = panel
	UIKit.corner(panel)
	UIKit.stroke(panel, Theme.Colors.Secondary, 1.5, 0.35)

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
	buildSideRail(layer)
	buildDeployPanel(layer)
	buildQueuePanel(layer)
	buildLoadoutPanel(layer)

	maid:give(ClientState.profileChanged:connect(refreshProfile))
	maid:give(ClientState.queueChanged:connect(refreshQueue))
	maid:give(ClientState.queueBoardChanged:connect(renderBoard))
	-- After buying a troop the Loadout panel opens as the equip slot picker.
	maid:give(ShopController.purchased:connect(function()
		setPanel("Loadout")
	end))
	maid:give(ShopController.closed:connect(function()
		if openPanel == "Armory" then
			setPanel(nil)
		end
	end))
	-- Entering a match clears the queue display and closes any open panel.
	maid:give(ClientState.matchChanged:connect(function()
		if queuePanel.Visible then
			queuePanel.Visible = false
			maid:clear("queueTicker")
		end
		if openPanel ~= nil then
			setPanel(nil)
		end
	end))

	local profile = ClientState.profile
	if profile ~= nil then
		refreshProfile(profile)
	end
	renderBoard(ClientState.queueBoard)
end

-- Used by in-world terminals (Armory loadout terminal, Troop Shop terminal).
function LobbyController.openPanel(name: PanelName)
	setPanel(name)
end

return LobbyController

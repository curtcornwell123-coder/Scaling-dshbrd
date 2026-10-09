--!strict
--[[
	HudController
	The in-match HUD: coins, wave and phase timer, enemy HQ health, the defense's active mutations,
	the incoming-mutation preview, lane selection, the robot spawn bar with upgrade buttons, and
	the end-of-match results. Every element is built once at startup and pooled; a match only
	updates text, colours, and sizes. The per-match timer connection lives in a match maid that is
	cleaned when the server closes the match.
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
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)

local MAX_LANE_BUTTONS = 3
local MUTATION_ROW_HEIGHT = 0.1

type Slot = {
	frame: Frame,
	spawnButton: TextButton,
	spawnStroke: UIStroke,
	nameLabel: TextLabel,
	costLabel: TextLabel,
	queuedLabel: TextLabel,
	levelLabel: TextLabel,
	upgradeButton: TextButton,
}

type MutationRow = {
	frame: Frame,
	nameLabel: TextLabel,
	descriptionLabel: TextLabel,
}

local PHASE_TEXT: { [Types.MatchState]: string } = {
	Waiting = "DEPLOYING",
	Countdown = "GET READY",
	Preparing = "BUILD YOUR SWARM",
	WaveActive = "SWARM ATTACKING",
	WaveResult = "WAVE CLEARED",
	MatchEnd = "MATCH OVER",
}

local HudController = {}

local maid = Maid.new()
local matchMaid = Maid.new()
local currentMatchId: number? = nil
local selectedLane = 1
local shownPhaseKey = ""

local coinsLabel: TextLabel
local swarmLabel: TextLabel
local waveLabel: TextLabel
local phaseLabel: TextLabel
local hqFill: Frame
local hqLabel: TextLabel
local rivalLabel: TextLabel
local incomingCard: Frame
local incomingName: TextLabel
local incomingDescription: TextLabel
local mutationEmpty: TextLabel
local mutationRows: { MutationRow } = {}
local slots: { Slot } = {}
local laneBar: Frame
local laneButtons: { TextButton } = {}
local resultPanel: Frame
local resultTitle: TextLabel
local resultReason: TextLabel
local resultStats: TextLabel

local function panel(name: string, props: { [string]: any }, accent: Color3): Frame
	props.Name = name
	props.BackgroundColor3 = Theme.Colors.PanelDark
	props.BackgroundTransparency = 0.12
	local frame = UIKit.frame(props)
	UIKit.corner(frame)
	UIKit.stroke(frame, accent, 2, 0.25)
	return frame
end

-- Sends a spawn request for loadout slot `index` in the selected lane. Used by buttons and hotkeys.
function HudController.trySpawn(index: number)
	local snapshot = ClientState.match
	if snapshot == nil then
		return
	end
	local info = snapshot.loadout[index]
	if info == nil then
		return
	end
	if snapshot.state ~= "Preparing" then
		UIController.showToast(Constants.NoticeText.WRONG_PHASE, "Error")
		return
	end
	Remotes.RequestSpawnRobot:fire(info.robotId, math.clamp(selectedLane, 1, snapshot.laneCount))
end

function HudController.tryUpgrade(index: number)
	local snapshot = ClientState.match
	if snapshot == nil then
		return
	end
	local info = snapshot.loadout[index]
	if info ~= nil and info.upgradeCost ~= nil then
		Remotes.RequestUpgradeRobot:fire(info.robotId)
	end
end

local function renderLanes(snapshot: Types.MatchSnapshot)
	laneBar.Visible = snapshot.laneCount > 1
	selectedLane = math.clamp(selectedLane, 1, math.max(1, snapshot.laneCount))
	for index, button in laneButtons do
		button.Visible = index <= snapshot.laneCount
		local selected = index == selectedLane
		button.BackgroundColor3 = if selected then Theme.Colors.Primary else Theme.Colors.PanelLight
		button.TextColor3 = if selected then Theme.Colors.PanelDark else Theme.Colors.Text
	end
end

function HudController.selectLane(index: number)
	local snapshot = ClientState.match
	if snapshot == nil then
		return
	end
	selectedLane = math.clamp(index, 1, snapshot.laneCount)
	renderLanes(snapshot)
end

function HudController.cycleLane(delta: number)
	local snapshot = ClientState.match
	if snapshot == nil or snapshot.laneCount <= 1 then
		return
	end
	HudController.selectLane((selectedLane - 1 + delta) % snapshot.laneCount + 1)
end

local function updatePhase()
	local snapshot = ClientState.match
	if snapshot == nil then
		return
	end
	local remaining = 0
	if snapshot.stateEndsAt > 0 then
		remaining = math.max(0, math.ceil(snapshot.stateEndsAt - workspace:GetServerTimeNow()))
	end
	-- Rebuild the string only when the state or the visible second changes.
	local timed = snapshot.state == "Preparing" or snapshot.state == "Countdown"
	local key = snapshot.state .. (if timed then tostring(remaining) else "")
	if key == shownPhaseKey then
		return
	end
	shownPhaseKey = key
	local text = PHASE_TEXT[snapshot.state]
	phaseLabel.Text = if timed then `{text}  {remaining}` else text
	phaseLabel.TextColor3 = if snapshot.state == "WaveActive" then Theme.Colors.Secondary else Theme.Colors.Primary
end

local function renderMutations(snapshot: Types.MatchSnapshot)
	mutationEmpty.Visible = #snapshot.activeMutations == 0
	for index, row in mutationRows do
		local info = snapshot.activeMutations[index]
		row.frame.Visible = info ~= nil
		if info ~= nil then
			local stacks = if info.stacks > 1 then `  x{info.stacks}` else ""
			UIKit.setText(row.nameLabel, string.upper(info.displayName) .. stacks)
			row.nameLabel.TextColor3 = Theme.rarityColor(info.rarity)
			UIKit.setText(row.descriptionLabel, info.description)
		end
	end

	local incoming = snapshot.nextMutation
	local showIncoming = incoming ~= nil and (snapshot.state == "Preparing" or snapshot.state == "WaveResult")
	incomingCard.Visible = showIncoming
	if incoming ~= nil and showIncoming then
		UIKit.setText(incomingName, `{string.upper(incoming.displayName)}  ({string.upper(incoming.rarity)})`)
		incomingName.TextColor3 = Theme.rarityColor(incoming.rarity)
		UIKit.setText(incomingDescription, incoming.description)
	end
end

local function renderSlots(snapshot: Types.MatchSnapshot)
	local preparing = snapshot.state == "Preparing"
	local swarmFull = snapshot.queuedThisWave >= snapshot.waveCap
	for index, slot in slots do
		local info = snapshot.loadout[index]
		slot.frame.Visible = info ~= nil
		if info ~= nil then
			local robot = RobotConfig.Robots[info.robotId]
			local canBuy = preparing and not swarmFull and snapshot.coins >= info.cost
			UIKit.setText(slot.nameLabel, string.upper(robot.displayName))
			UIKit.setText(slot.costLabel, `{info.cost}`)
			UIKit.setText(slot.queuedLabel, if info.queued > 0 then `x{info.queued}` else "")
			UIKit.setText(slot.levelLabel, `LV {info.level + 1}`)
			slot.spawnButton.BackgroundColor3 = if canBuy then Theme.Colors.PanelLight else Theme.Colors.PanelDark
			slot.spawnStroke.Color = if canBuy then robot.visual.color else Theme.Colors.TextDim
			slot.nameLabel.TextColor3 = if canBuy then Theme.Colors.Text else Theme.Colors.TextDim

			local upgradeCost = info.upgradeCost
			if upgradeCost == nil then
				UIKit.setText(slot.upgradeButton, "MAX LEVEL")
				slot.upgradeButton.BackgroundColor3 = Theme.Colors.PanelDark
				slot.upgradeButton.TextColor3 = Theme.Colors.TextDim
			else
				local affordable = snapshot.coins >= upgradeCost
				UIKit.setText(slot.upgradeButton, `UPGRADE  {upgradeCost}`)
				slot.upgradeButton.BackgroundColor3 = if affordable
					then Theme.Colors.Secondary
					else Theme.Colors.PanelDark
				slot.upgradeButton.TextColor3 = if affordable then Theme.Colors.PanelDark else Theme.Colors.TextDim
			end
		end
	end
end

local function renderResult(snapshot: Types.MatchSnapshot)
	local result = snapshot.result
	if result == nil then
		resultPanel.Visible = false
		return
	end
	if not resultPanel.Visible then
		resultPanel.Size = UDim2.fromScale(0.3, 0.3)
		resultPanel.Visible = true
		UIKit.tween(resultPanel, Theme.Tween.Pop, { Size = UDim2.fromScale(0.4, 0.42) })
	end
	resultTitle.Text = if result.won then "VICTORY" else "DEFEAT"
	resultTitle.TextColor3 = if result.won then Theme.Colors.Success else Theme.Colors.Danger
	resultReason.Text = Constants.MatchEndText[result.reason] or ""
	resultStats.Text =
		`WAVES CLEARED  {result.wavesCompleted}\nCOINS EARNED  +{MathUtil.formatCount(result.coinsAwarded)}`
end

local function render(snapshot: Types.MatchSnapshot)
	UIKit.setText(coinsLabel, `COINS {MathUtil.formatCount(snapshot.coins)}`)
	UIKit.setText(swarmLabel, `SWARM {snapshot.queuedThisWave}/{snapshot.waveCap}`)
	UIKit.setText(waveLabel, `WAVE {math.max(1, snapshot.wave)} / {snapshot.maxWaves}`)

	local fraction = math.clamp(snapshot.baseHealth / math.max(1, snapshot.baseMaxHealth), 0, 1)
	if hqFill.Size.X.Scale ~= fraction then
		UIKit.tween(hqFill, Theme.Tween.Normal, { Size = UDim2.fromScale(fraction, 1) })
	end
	UIKit.setText(
		hqLabel,
		`{MathUtil.formatCount(snapshot.baseHealth)} / {MathUtil.formatCount(snapshot.baseMaxHealth)}`
	)

	local rival = snapshot.rivals[1]
	rivalLabel.Visible = rival ~= nil
	if rival ~= nil then
		UIKit.setText(rivalLabel, `RIVAL {string.upper(rival.name)}: {rival.baseHealth}/{rival.baseMaxHealth}`)
	end

	renderMutations(snapshot)
	renderSlots(snapshot)
	renderLanes(snapshot)
	renderResult(snapshot)
	updatePhase()
end

local function onMatchChanged(snapshot: Types.MatchSnapshot)
	if currentMatchId ~= snapshot.matchId then
		currentMatchId = snapshot.matchId
		selectedLane = 1
		shownPhaseKey = ""
		matchMaid:cleanup()
		matchMaid:give(RunService.Heartbeat:Connect(updatePhase))
	end
	render(snapshot)
end

local function onMatchClosed()
	currentMatchId = nil
	matchMaid:cleanup()
	resultPanel.Visible = false
end

local function buildTop(layer: Frame)
	local left = panel("Economy", {
		Position = UDim2.fromScale(0.02, 0.02),
		Size = UDim2.fromScale(0.2, 0.11),
		Parent = layer,
	}, Theme.Colors.Warning)
	coinsLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.5),
		Position = UDim2.fromScale(0.05, 0.08),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Warning,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = left,
	}, Theme.Text.HEADER_MAX)
	swarmLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.32),
		Position = UDim2.fromScale(0.05, 0.6),
		TextColor3 = Theme.Colors.Primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = left,
	}, Theme.Text.BODY_MAX)

	local center = panel("Wave", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.26, 0.11),
		Parent = layer,
	}, Theme.Colors.Primary)
	waveLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.52),
		Position = UDim2.fromScale(0.05, 0.06),
		Font = Theme.Fonts.Title,
		Parent = center,
	}, Theme.Text.TITLE_MAX)
	phaseLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.32),
		Position = UDim2.fromScale(0.05, 0.6),
		TextColor3 = Theme.Colors.Primary,
		Parent = center,
	}, Theme.Text.BODY_MAX)

	local right = panel("EnemyHQ", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.98, 0.02),
		Size = UDim2.fromScale(0.22, 0.13),
		Parent = layer,
	}, Theme.Military.AlertRed)
	UIKit.label({
		Size = UDim2.fromScale(0.5, 0.26),
		Position = UDim2.fromScale(0.05, 0.06),
		Font = Theme.Fonts.Title,
		Text = "ENEMY HQ",
		TextColor3 = Theme.Military.AlertRed,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = right,
	}, Theme.Text.BODY_MAX)
	hqLabel = UIKit.label({
		Size = UDim2.fromScale(0.42, 0.24),
		Position = UDim2.fromScale(0.53, 0.07),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = right,
	}, Theme.Text.SMALL_MAX)
	local barBack = UIKit.frame({
		Size = UDim2.fromScale(0.9, 0.22),
		Position = UDim2.fromScale(0.05, 0.4),
		BackgroundColor3 = Theme.Colors.Panel,
		Parent = right,
	})
	UIKit.corner(barBack, UDim.new(0, 6))
	hqFill = UIKit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Military.AlertRed,
		Parent = barBack,
	})
	UIKit.corner(hqFill, UDim.new(0, 6))
	UIKit.gradient(hqFill, Theme.Military.Amber, Theme.Military.AlertRed, 0)
	rivalLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.22),
		Position = UDim2.fromScale(0.05, 0.72),
		TextColor3 = Theme.Colors.Secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = right,
	}, Theme.Text.SMALL_MAX)
end

local function buildMutations(layer: Frame)
	local listPanel = panel("Mutations", {
		Position = UDim2.fromScale(0.02, 0.16),
		Size = UDim2.fromScale(0.2, 0.5),
		Parent = layer,
	}, Theme.Military.Amber)
	UIKit.label({
		Size = UDim2.fromScale(0.9, 0.07),
		Position = UDim2.fromScale(0.05, 0.02),
		Font = Theme.Fonts.Title,
		Text = "DEFENSE MUTATIONS",
		TextColor3 = Theme.Military.Amber,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = listPanel,
	}, Theme.Text.BODY_MAX)
	mutationEmpty = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.06),
		Position = UDim2.fromScale(0.05, 0.11),
		Font = Theme.Fonts.Light,
		Text = "None yet. They grow after every wave.",
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = listPanel,
	}, Theme.Text.SMALL_MAX)

	local list = UIKit.frame({
		Size = UDim2.fromScale(0.9, 0.88),
		Position = UDim2.fromScale(0.05, 0.1),
		BackgroundTransparency = 1,
		Parent = listPanel,
	})
	UIKit.list(list, Enum.FillDirection.Vertical, UDim.new(0.005, 0), Enum.HorizontalAlignment.Left)
	for index = 1, #MutationConfig.Order do
		local row = UIKit.frame({
			Name = "Row" .. index,
			LayoutOrder = index,
			Size = UDim2.fromScale(1, MUTATION_ROW_HEIGHT),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = list,
		})
		local nameLabel = UIKit.label({
			Size = UDim2.fromScale(1, 0.5),
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, Theme.Text.SMALL_MAX)
		local descriptionLabel = UIKit.label({
			Size = UDim2.fromScale(1, 0.48),
			Position = UDim2.fromScale(0, 0.5),
			Font = Theme.Fonts.Light,
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, Theme.Text.SMALL_MAX)
		table.insert(mutationRows, { frame = row, nameLabel = nameLabel, descriptionLabel = descriptionLabel })
	end

	incomingCard = panel("Incoming", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.34, 0.1),
		Visible = false,
		Parent = layer,
	}, Theme.Military.Amber)
	UIKit.label({
		Size = UDim2.fromScale(0.9, 0.26),
		Position = UDim2.fromScale(0.05, 0.06),
		Text = "INCOMING DEFENSE MUTATION - PLAN YOUR COUNTER",
		TextColor3 = Theme.Military.Amber,
		Parent = incomingCard,
	}, Theme.Text.SMALL_MAX)
	incomingName = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.34),
		Position = UDim2.fromScale(0.05, 0.32),
		Font = Theme.Fonts.Title,
		Parent = incomingCard,
	}, Theme.Text.HEADER_MAX)
	incomingDescription = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.26),
		Position = UDim2.fromScale(0.05, 0.68),
		Font = Theme.Fonts.Light,
		Parent = incomingCard,
	}, Theme.Text.SMALL_MAX)
end

local function buildSpawnBar(layer: Frame)
	local bar = UIKit.frame({
		Name = "SpawnBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.985),
		Size = UDim2.fromScale(0.72, 0.21),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(
		bar,
		Enum.FillDirection.Horizontal,
		UDim.new(0.012, 0),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Bottom
	)

	for index = 1, Constants.MAX_LOADOUT do
		local frame = UIKit.frame({
			Name = "Slot" .. index,
			LayoutOrder = index,
			Size = UDim2.fromScale(0.19, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = bar,
		})
		-- Large buttons: the whole card is the hit area, which matters on touch screens.
		local spawnButton = UIKit.button({
			Size = UDim2.fromScale(1, 0.7),
			BackgroundColor3 = Theme.Colors.PanelLight,
			Parent = frame,
		})
		local spawnStroke = UIKit.stroke(spawnButton, Theme.Colors.Primary, 2)
		UIKit.label({
			Size = UDim2.fromScale(0.2, 0.26),
			Position = UDim2.fromScale(0.05, 0.05),
			Text = tostring(index),
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = spawnButton,
		}, Theme.Text.SMALL_MAX)
		local levelLabel = UIKit.label({
			Size = UDim2.fromScale(0.4, 0.24),
			Position = UDim2.fromScale(0.55, 0.06),
			TextColor3 = Theme.Colors.Secondary,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = spawnButton,
		}, Theme.Text.SMALL_MAX)
		local nameLabel = UIKit.label({
			Size = UDim2.fromScale(0.9, 0.32),
			Position = UDim2.fromScale(0.05, 0.32),
			Font = Theme.Fonts.Title,
			Parent = spawnButton,
		}, Theme.Text.HEADER_MAX)
		local costLabel = UIKit.label({
			Size = UDim2.fromScale(0.5, 0.26),
			Position = UDim2.fromScale(0.05, 0.68),
			TextColor3 = Theme.Colors.Warning,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = spawnButton,
		}, Theme.Text.BODY_MAX)
		local queuedLabel = UIKit.label({
			Size = UDim2.fromScale(0.4, 0.26),
			Position = UDim2.fromScale(0.55, 0.68),
			TextColor3 = Theme.Colors.Primary,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = spawnButton,
		}, Theme.Text.BODY_MAX)

		local upgradeButton = UIKit.button({
			Size = UDim2.fromScale(1, 0.25),
			Position = UDim2.fromScale(0, 0.75),
			BackgroundColor3 = Theme.Colors.PanelDark,
			Parent = frame,
		}, Theme.Text.SMALL_MAX)

		UIKit.bindButton(spawnButton, maid, function()
			HudController.trySpawn(index)
		end)
		UIKit.bindButton(upgradeButton, maid, function()
			HudController.tryUpgrade(index)
		end)

		table.insert(slots, {
			frame = frame,
			spawnButton = spawnButton,
			spawnStroke = spawnStroke,
			nameLabel = nameLabel,
			costLabel = costLabel,
			queuedLabel = queuedLabel,
			levelLabel = levelLabel,
			upgradeButton = upgradeButton,
		})
	end

	laneBar = UIKit.frame({
		Name = "Lanes",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.76),
		Size = UDim2.fromScale(0.3, 0.05),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	UIKit.list(laneBar, Enum.FillDirection.Horizontal, UDim.new(0.03, 0), Enum.HorizontalAlignment.Center)
	for index = 1, MAX_LANE_BUTTONS do
		local button = UIKit.button({
			LayoutOrder = index,
			Size = UDim2.fromScale(0.3, 1),
			Text = `LANE {index}`,
			Parent = laneBar,
		}, Theme.Text.BODY_MAX)
		UIKit.bindButton(button, maid, function()
			HudController.selectLane(index)
		end)
		table.insert(laneButtons, button)
	end
end

local function buildResult(layer: Frame)
	resultPanel = panel("Result", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.4, 0.42),
		Visible = false,
		ZIndex = 5,
		Parent = layer,
	}, Theme.Colors.Primary)
	resultTitle = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.3),
		Position = UDim2.fromScale(0.05, 0.06),
		Font = Theme.Fonts.Title,
		ZIndex = 6,
		Parent = resultPanel,
	}, 72)
	resultReason = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.14),
		Position = UDim2.fromScale(0.05, 0.38),
		Font = Theme.Fonts.Light,
		ZIndex = 6,
		Parent = resultPanel,
	}, Theme.Text.BODY_MAX)
	resultStats = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.24),
		Position = UDim2.fromScale(0.05, 0.54),
		TextColor3 = Theme.Colors.Warning,
		ZIndex = 6,
		Parent = resultPanel,
	}, Theme.Text.HEADER_MAX)
	UIKit.label({
		Size = UDim2.fromScale(0.9, 0.1),
		Position = UDim2.fromScale(0.05, 0.84),
		Text = "RETURNING TO LOBBY...",
		TextColor3 = Theme.Colors.TextDim,
		ZIndex = 6,
		Parent = resultPanel,
	}, Theme.Text.SMALL_MAX)
end

function HudController.init()
	local layer = UIController.getLayer("Hud")
	buildTop(layer)
	buildMutations(layer)
	buildSpawnBar(layer)
	buildResult(layer)

	maid:give(matchMaid)
	maid:give(ClientState.matchChanged:connect(onMatchChanged))
	maid:give(ClientState.matchClosed:connect(onMatchClosed))
end

return HudController

--!strict
--[[
	PanelsController
	Lobby navigation and the service panels:
	- Bottom bar: TROOPS (loadout), TASKS, SHOP, PASS, each with a red count badge. There is no
	  Play button: modes are joined only by standing on a Duels Hall pad.
	- Top centre: Coins and Gems with "+" buttons that open the Robux shop. No game title.
	- A dismissable red hint bubble when a new troop can be bought.
	- Panels: Tasks (daily tasks, daily supply, code entry), Shop (Robux products with live prices
	  from MarketplaceService), Pass (season tiers, premium, ranked season reward).
	- Test Realm panel (only inside the sandbox): start wave, speed, mutations, Apply and Reset.
	Every button sends an id-only request; the server validates and answers.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local SupplyConfig = require(ReplicatedStorage.Shared.Config.SupplyConfig)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local QuestRules = require(ReplicatedStorage.Shared.Logic.QuestRules)
local SupplyRules = require(ReplicatedStorage.Shared.Logic.SupplyRules)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Requirements = require(ReplicatedStorage.Shared.Logic.Requirements)
local TroopRotation = require(ReplicatedStorage.Shared.Logic.TroopRotation)
local RewardRules = require(ReplicatedStorage.Shared.Logic.RewardRules)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local ShopController = require(script.Parent.ShopController)
local LobbyController = require(script.Parent.LobbyController)

export type PanelName = "Tasks" | "Shop" | "Pass"

local ROW = 64
local TOUCH = 44

local PanelsController = {}

PanelsController.questSettings = {
	regularPool = QuestConfig.RegularPool,
	testRealmPool = QuestConfig.TestRealmPool,
	regularPerDay = QuestConfig.RegularPerDay,
	testRealmPerDay = QuestConfig.TestRealmPerDay,
	seed = QuestConfig.Seed,
} :: QuestRules.QuestSettings

local maid = Maid.new()
local contentMaid = Maid.new()
local panel: Frame
local panelTitle: TextLabel
local list: ScrollingFrame
local openName: PanelName? = nil
local badges: { [string]: TextLabel } = {}
local coinsLabel: TextLabel
local gemsLabel: TextLabel
local hint: TextButton
local hintDismissed = false
local sandboxPanel: Frame
local sandboxDraft: Types.SandboxConfig? = nil
local sandboxLabel: TextLabel
local priceCache: { [number]: string } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function row(order: number, height: number?): Frame
	local frame = UIKit.frame({
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, height or ROW),
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = list,
	})
	UIKit.corner(frame)
	return frame
end

local function rowText(frame: Frame, title: string, detail: string, color: Color3?)
	UIKit.label({
		Size = UDim2.fromScale(0.64, 0.48),
		Position = UDim2.fromScale(0.03, 0.06),
		Font = Theme.Fonts.Title,
		Text = title,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, Theme.Text.BODY_MAX)
	UIKit.label({
		Size = UDim2.fromScale(0.64, 0.4),
		Position = UDim2.fromScale(0.03, 0.54),
		Font = Theme.Fonts.Light,
		Text = detail,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, Theme.Text.SMALL_MAX)
end

local function rowButton(frame: Frame, text: string, enabled: boolean, onActivated: () -> ())
	local button = UIKit.button({
		Size = UDim2.new(0.28, 0, 0, TOUCH),
		Position = UDim2.new(0.7, 0, 0.5, -TOUCH / 2),
		Text = text,
		BackgroundColor3 = if enabled then Theme.Colors.Primary else Theme.Colors.PanelDark,
		TextColor3 = if enabled then Theme.Colors.PanelDark else Theme.Colors.TextDim,
		Parent = frame,
	}, Theme.Text.BODY_MAX)
	UIKit.bindButton(button, contentMaid, function()
		if enabled then
			onActivated()
		end
	end)
end

local function todaysQuests(): { string }
	return QuestRules.dailyQuests(Calendar.dayNumber(now()), PanelsController.questSettings)
end

local function buildTasks(profile: Types.PlayerData)
	local day = Calendar.dayNumber(now())
	for order, questId in todaysQuests() do
		local quest = QuestConfig.Quests[questId]
		local progress = if profile.quests.day == day then profile.quests.progress[questId] or 0 else 0
		local claimed = profile.quests.day == day and table.find(profile.quests.claimed, questId) ~= nil
		local frame = row(order)
		local where = if quest.testRealm then "  (Test Realm)" else ""
		rowText(frame, quest.description .. where, `{progress}/{quest.target}  -  {RewardRules.describe(quest.reward)}`)
		rowButton(frame, if claimed then "DONE" else "CLAIM", not claimed and progress >= quest.target, function()
			Remotes.RequestClaimQuest:fire(questId)
		end)
	end
	local supply = row(10)
	local nextAt =
		SupplyRules.nextAvailableAt(profile.supply, now(), SupplyConfig.ClaimsPerDay, SupplyConfig.CooldownSeconds)
	local used = SupplyRules.claimsToday(profile.supply, now())
	local detail = if nextAt == nil
		then "All claimed today"
		elseif nextAt <= now() then "Ready"
		else `Next in {Calendar.formatDuration(nextAt - now())}`
	rowText(supply, `DAILY SUPPLY  {used}/{SupplyConfig.ClaimsPerDay}`, detail, Theme.Colors.Warning)
	rowButton(supply, "CLAIM", nextAt ~= nil and nextAt <= now(), function()
		Remotes.RequestClaimSupply:fire()
	end)

	local code = row(11)
	local box = UIKit.create("TextBox", {
		Size = UDim2.new(0.64, 0, 0, TOUCH),
		Position = UDim2.new(0.03, 0, 0.5, -TOUCH / 2),
		BackgroundColor3 = Theme.Colors.PanelDark,
		PlaceholderText = "ENTER CODE",
		PlaceholderColor3 = Theme.Colors.TextDim,
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Body,
		Parent = code,
	}) :: TextBox
	UIKit.corner(box)
	rowButton(code, "REDEEM", true, function()
		if box.Text ~= "" then
			Remotes.RequestRedeemCode:fire(string.sub(box.Text, 1, 32))
		end
	end)
end

local function priceText(productId: number): string
	if productId == 0 then
		return "Not set up"
	end
	local cached = priceCache[productId]
	if cached ~= nil then
		return cached
	end
	priceCache[productId] = "..."
	task.spawn(function()
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		priceCache[productId] = if ok
				and type(info) == "table"
				and type(info.PriceInRobux) == "number"
			then `R$ {info.PriceInRobux}`
			else "Unavailable"
		if openName == "Shop" then
			PanelsController.refresh()
		end
	end)
	return "..."
end

local function buildShop()
	for order, productKey in ShopConfig.Order do
		local product = ShopConfig.Products[productKey]
		local frame = row(order)
		rowText(frame, string.upper(product.name), product.description, Theme.Colors.Warning)
		rowButton(frame, priceText(product.productId), product.productId ~= 0, function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.productId)
		end)
	end
end

local function claimableTiers(profile: Types.PlayerData): number
	if now() >= SeasonConfig.EndsAt or profile.season.seasonId ~= SeasonConfig.SeasonId then
		return 0
	end
	local reached = SeasonRules.tierForXp(profile.season.xp, SeasonConfig.XpPerTier, SeasonConfig.TierCount)
	local count = 0
	for tier = 1, reached do
		if table.find(profile.season.claimedFree, tier) == nil then
			count += 1
		end
		if profile.season.premium and table.find(profile.season.claimedPremium, tier) == nil then
			count += 1
		end
	end
	return count
end

local function buildPass(profile: Types.PlayerData)
	local season = profile.season
	local reached = SeasonRules.tierForXp(season.xp, SeasonConfig.XpPerTier, SeasonConfig.TierCount)
	local remaining = SeasonConfig.EndsAt - now()
	local header = row(0)
	rowText(
		header,
		`TIER {reached}/{SeasonConfig.TierCount}  -  {season.xp % SeasonConfig.XpPerTier}/{SeasonConfig.XpPerTier} XP`,
		if remaining > 0 then `Ends in {Calendar.formatDuration(remaining)}` else "Season ended: rewards stay visible",
		Theme.Areas.Market
	)
	local premium = ShopConfig.Products.SeasonPremium
	rowButton(
		header,
		if season.premium then "PREMIUM" else "GET PREMIUM",
		not season.premium and premium.productId ~= 0,
		function()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, premium.productId)
		end
	)
	local pending = profile.rank.pendingReward
	if pending ~= nil then
		local ranked = row(1)
		rowText(
			ranked,
			`RANKED REWARD: {string.upper(pending.tier)}`,
			RewardRules.describe(pending.reward),
			Theme.Areas.DuelsGold
		)
		rowButton(ranked, "CLAIM", true, function()
			Remotes.RequestClaimPassReward:fire(0, "Ranked")
		end)
	end
	local open = remaining > 0
	for _, tierDef in SeasonConfig.Tiers do
		local tier = tierDef.tier
		local frame = row(10 + tier, 84)
		UIKit.label({
			Size = UDim2.fromScale(0.12, 1),
			Font = Theme.Fonts.Title,
			Text = tostring(tier),
			TextColor3 = if tier <= reached then Theme.Areas.Market else Theme.Colors.TextDim,
			Parent = frame,
		}, Theme.Text.HEADER_MAX)
		for column, track in { "Free", "Premium" } do
			local reward = if track == "Free" then tierDef.free else tierDef.premium
			local claimedList = if track == "Free" then season.claimedFree else season.claimedPremium
			local claimed = table.find(claimedList, tier) ~= nil
			local allowed = open and tier <= reached and not claimed and (track == "Free" or season.premium)
			local button = UIKit.button({
				Size = UDim2.new(0.42, 0, 0, TOUCH + 20),
				Position = UDim2.new(0.13 + (column - 1) * 0.44, 0, 0.5, -(TOUCH + 20) / 2),
				Text = `{string.upper(track)}: {if reward ~= nil then RewardRules.describe(reward) else "-"}{if claimed
					then " (CLAIMED)"
					else ""}`,
				BackgroundColor3 = if allowed then Theme.Colors.Primary else Theme.Colors.PanelDark,
				TextColor3 = if allowed then Theme.Colors.PanelDark else Theme.Colors.TextDim,
				Parent = frame,
			}, Theme.Text.SMALL_MAX)
			UIKit.bindButton(button, contentMaid, function()
				if allowed then
					Remotes.RequestClaimPassReward:fire(tier, track)
				end
			end)
		end
	end
end

function PanelsController.refresh()
	contentMaid:cleanup()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = ClientState.profile
	if openName == nil or profile == nil then
		return
	end
	if openName == "Tasks" then
		buildTasks(profile)
	elseif openName == "Shop" then
		buildShop()
	elseif openName == "Pass" then
		buildPass(profile)
	end
end

function PanelsController.open(name: PanelName)
	if ClientState.sandbox ~= nil then
		UIController.showToast(Constants.NoticeText.SANDBOX, "Error")
		return
	end
	ShopController.close()
	openName = name
	UIKit.setText(
		panelTitle,
		if name == "Tasks"
			then "TASKS & CODES"
			elseif name == "Shop" then "ROBUX SHOP"
			else `{SeasonConfig.DisplayName} PASS`
	)
	panel.Visible = true
	panel.Position = UDim2.fromScale(0.5, 0.53)
	UIKit.tween(panel, Theme.Tween.Normal, { Position = UDim2.fromScale(0.5, 0.5) })
	PanelsController.refresh()
end

function PanelsController.close()
	openName = nil
	panel.Visible = false
	contentMaid:cleanup()
end

local function affordableTroops(profile: Types.PlayerData): number
	local rotation = TroopRotation.forTime(now(), ShopController.rotationSettings)
	local progress = Requirements.progressOf(profile)
	local count = 0
	for _, troopId in TroopRotation.tables(rotation) do
		local troop = TroopConfig.Troops[troopId]
		if troop ~= nil and not troop.comingSoon and table.find(profile.unlockedRobots, troopId) == nil then
			local balance = if troop.currency == "Gems" then profile.gems else profile.coins
			if balance >= troop.price and Requirements.isMet(troop.unlock, progress) then
				count += 1
			end
		end
	end
	return count
end

local function refreshBadges(profile: Types.PlayerData)
	UIKit.setText(coinsLabel, `COINS {MathUtil.formatCount(profile.coins)}`)
	UIKit.setText(gemsLabel, `GEMS {MathUtil.formatCount(profile.gems)}`)
	local day = Calendar.dayNumber(now())
	local tasks = 0
	for _, questId in todaysQuests() do
		local quest = QuestConfig.Quests[questId]
		local progress = if profile.quests.day == day then profile.quests.progress[questId] or 0 else 0
		if progress >= quest.target and table.find(profile.quests.claimed, questId) == nil then
			tasks += 1
		end
	end
	if SupplyRules.check(profile.supply, now(), SupplyConfig.ClaimsPerDay, SupplyConfig.CooldownSeconds) == "OK" then
		tasks += 1
	end
	local troops = affordableTroops(profile)
	local counts = {
		Troops = troops,
		Tasks = tasks,
		Pass = claimableTiers(profile) + (if profile.rank.pendingReward ~= nil then 1 else 0),
		Shop = 0,
	}
	for name, label in badges do
		local count = counts[name] or 0
		label.Visible = count > 0
		label.Text = tostring(count)
	end
	hint.Visible = troops > 0 and not hintDismissed and ClientState.match == nil
end

local function navButton(bar: Frame, order: number, name: string, onActivated: () -> ())
	local button = UIKit.button({
		LayoutOrder = order,
		Size = UDim2.new(0.23, 0, 1, 0),
		Text = string.upper(name),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = bar,
	}, Theme.Text.BODY_MAX)
	UIKit.stroke(button, Theme.Colors.PanelLight, 1.5)
	UIKit.bindButton(button, maid, onActivated)
	local badge = UIKit.label({
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -16, 0, -10),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Danger,
		Text = "0",
		Visible = false,
		Parent = button,
	}, Theme.Text.SMALL_MAX)
	UIKit.corner(badge, UDim.new(0.5, 0))
	badges[name] = badge
end

local function buildNav(layer: Frame)
	local bar = UIKit.frame({
		Name = "NavBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.975),
		Size = UDim2.new(0.46, 0, 0, 56),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(bar, Enum.FillDirection.Horizontal, UDim.new(0.02, 0), Enum.HorizontalAlignment.Center)
	navButton(bar, 1, "Troops", function()
		PanelsController.close()
		LobbyController.openPanel("Loadout")
	end)
	navButton(bar, 2, "Tasks", function()
		PanelsController.open("Tasks")
	end)
	navButton(bar, 3, "Shop", function()
		PanelsController.open("Shop")
	end)
	navButton(bar, 4, "Pass", function()
		PanelsController.open("Pass")
	end)

	hint = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.975, -66),
		Size = UDim2.fromOffset(300, TOUCH),
		BackgroundColor3 = Theme.Colors.Danger,
		Text = "New troop available!  (tap to hide)",
		Visible = false,
		Parent = layer,
	}, Theme.Text.BODY_MAX)
	UIKit.corner(hint)
	UIKit.bindButton(hint, maid, function()
		hintDismissed = true
		hint.Visible = false
	end)

	local top = UIKit.frame({
		Name = "Currency",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.new(0.34, 0, 0, TOUCH),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(top, Enum.FillDirection.Horizontal, UDim.new(0.02, 0), Enum.HorizontalAlignment.Center)
	local function chip(order: number, color: Color3): TextLabel
		local frame = UIKit.frame({
			LayoutOrder = order,
			Size = UDim2.fromScale(0.48, 1),
			BackgroundColor3 = Theme.Colors.PanelDark,
			BackgroundTransparency = 0.15,
			Parent = top,
		})
		UIKit.corner(frame, UDim.new(0.5, 0))
		UIKit.stroke(frame, color, 1.5, 0.4)
		local plus = UIKit.button({
			Size = UDim2.new(0, TOUCH, 1, 0),
			Position = UDim2.new(1, -TOUCH, 0, 0),
			Text = "+",
			BackgroundColor3 = color,
			TextColor3 = Theme.Colors.PanelDark,
			Parent = frame,
		}, Theme.Text.HEADER_MAX)
		UIKit.corner(plus, UDim.new(0.5, 0))
		UIKit.bindButton(plus, maid, function()
			PanelsController.open("Shop")
		end)
		return UIKit.label({
			Size = UDim2.new(1, -TOUCH - 12, 0.7, 0),
			Position = UDim2.new(0, 10, 0.15, 0),
			Text = "",
			TextColor3 = color,
			Parent = frame,
		}, Theme.Text.BODY_MAX)
	end
	coinsLabel = chip(1, Theme.Colors.Warning)
	gemsLabel = chip(2, Theme.Colors.Primary)
end

local function buildPanel(modal: Frame)
	panel = UIKit.frame({
		Name = "ServicePanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.74),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		Parent = modal,
	})
	UIKit.corner(panel)
	UIKit.stroke(panel, Theme.Colors.Primary, 2)
	panelTitle = UIKit.label({
		Size = UDim2.fromScale(0.7, 0.08),
		Position = UDim2.fromScale(0.04, 0.03),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = panel,
	}, Theme.Text.HEADER_MAX)
	local close = UIKit.button({
		Size = UDim2.fromOffset(TOUCH, TOUCH),
		Position = UDim2.new(0.96, -TOUCH, 0.03, 0),
		Text = "X",
		BackgroundColor3 = Theme.Colors.PanelLight,
		Parent = panel,
	}, Theme.Text.HEADER_MAX)
	UIKit.bindButton(close, maid, PanelsController.close)
	list = UIKit.create("ScrollingFrame", {
		Size = UDim2.fromScale(0.92, 0.84),
		Position = UDim2.fromScale(0.04, 0.13),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	}) :: ScrollingFrame
	UIKit.list(list, Enum.FillDirection.Vertical, UDim.new(0, 8))
end

-- Test Realm --------------------------------------------------------------------------------

local function sandboxSummary(config: Types.SandboxConfig): string
	local mutations: { string } = {}
	for mutationId, stacks in config.mutations do
		table.insert(mutations, `{MutationConfig.Mutations[mutationId].displayName} x{stacks}`)
	end
	return `WAVE {config.wave}   SPEED x{config.speed}\n{if #mutations > 0
		then table.concat(mutations, ", ")
		else "No mutations"}`
end

local function editSandbox(change: (Types.SandboxConfig) -> ())
	local draft = sandboxDraft
	if draft == nil then
		return
	end
	change(draft)
	UIKit.setText(sandboxLabel, sandboxSummary(draft))
end

local function buildSandboxPanel(layer: Frame)
	sandboxPanel = UIKit.frame({
		Name = "TestRealm",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.985, 0.5),
		Size = UDim2.fromScale(0.24, 0.5),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = layer,
	})
	UIKit.corner(sandboxPanel)
	UIKit.stroke(sandboxPanel, Theme.Areas.TestRealm, 2)
	UIKit.label({
		Size = UDim2.fromScale(0.9, 0.1),
		Position = UDim2.fromScale(0.05, 0.02),
		Font = Theme.Fonts.Title,
		Text = "TEST REALM",
		TextColor3 = Theme.Areas.TestRealm,
		Parent = sandboxPanel,
	}, Theme.Text.HEADER_MAX)
	sandboxLabel = UIKit.label({
		Size = UDim2.fromScale(0.9, 0.18),
		Position = UDim2.fromScale(0.05, 0.13),
		Text = "",
		TextWrapped = true,
		Parent = sandboxPanel,
	}, Theme.Text.SMALL_MAX)
	local buttons = UIKit.frame({
		Size = UDim2.fromScale(0.9, 0.62),
		Position = UDim2.fromScale(0.05, 0.34),
		BackgroundTransparency = 1,
		Parent = sandboxPanel,
	})
	UIKit.create(
		"UIGridLayout",
		{ CellSize = UDim2.new(0.48, 0, 0, TOUCH), CellPadding = UDim2.fromOffset(6, 6), Parent = buttons }
	)
	local mutationIndex = 1
	local actions: { { label: string, run: () -> () } } = {
		{
			label = "WAVE -",
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.wave = math.max(1, c.wave - 1)
				end)
			end,
		},
		{
			label = "WAVE +",
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.wave = math.min(Constants.TestRealm.MAX_WAVE, c.wave + 1)
				end)
			end,
		},
		{
			label = "SPEED -",
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.speed = math.max(Constants.TestRealm.MIN_SPEED, c.speed - 0.5)
				end)
			end,
		},
		{
			label = "SPEED +",
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.speed = math.min(Constants.TestRealm.MAX_SPEED, c.speed + 0.5)
				end)
			end,
		},
		{
			label = "NEXT MUTATION",
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					local mutationId = MutationConfig.Order[mutationIndex]
					mutationIndex = mutationIndex % #MutationConfig.Order + 1
					local cap = math.min(
						MutationConfig.Mutations[mutationId].maxStacks,
						Constants.TestRealm.MAX_MUTATION_STACKS
					)
					c.mutations[mutationId] = ((c.mutations[mutationId] or 0) + 1) % (cap + 1)
				end)
			end,
		},
		{
			label = "CLEAR MUTATIONS",
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.mutations = {}
				end)
			end,
		},
		{
			label = "APPLY",
			run = function()
				if sandboxDraft ~= nil then
					Remotes.RequestSandboxConfig:fire(sandboxDraft)
				end
			end,
		},
		{
			label = "RESET",
			run = function()
				Remotes.RequestSandboxReset:fire()
			end,
		},
	}
	for order, action in actions do
		local button = UIKit.button(
			{ LayoutOrder = order, Text = action.label, BackgroundColor3 = Theme.Colors.PanelLight, Parent = buttons },
			Theme.Text.SMALL_MAX
		)
		UIKit.bindButton(button, maid, action.run)
	end
end

local function onSandbox(state: Types.SandboxState)
	sandboxPanel.Visible = state.active
	if state.active then
		local copy = table.clone(state.config)
		copy.mutations = table.clone(state.config.mutations)
		sandboxDraft = copy
		UIKit.setText(sandboxLabel, sandboxSummary(copy) .. "\nWalk onto RETURN to leave.")
	else
		sandboxDraft = nil
	end
end

function PanelsController.init()
	local lobbyLayer = UIController.getLayer("Lobby")
	buildNav(lobbyLayer)
	buildPanel(UIController.getLayer("Modal"))
	buildSandboxPanel(UIController.getLayer("Overlay"))
	maid:give(ClientState.profileChanged:connect(function(profile: Types.PlayerData)
		refreshBadges(profile)
		if openName ~= nil then
			PanelsController.refresh()
		end
	end))
	maid:give(ClientState.sandboxChanged:connect(onSandbox))
	maid:give(ClientState.matchChanged:connect(function()
		PanelsController.close()
		hint.Visible = false
	end))
	maid:give(Remotes.ActionResult:connect(function(result: Types.ActionResult)
		if result.ok and result.action == "RedeemCode" then
			UIController.showToast(Constants.NoticeText.CODE_REDEEMED, "Success")
		end
	end))
	local profile = ClientState.profile
	if profile ~= nil then
		refreshBadges(profile)
	end
end

return PanelsController

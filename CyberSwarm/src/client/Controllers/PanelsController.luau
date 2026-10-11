--!strict
--[[
	PanelsController
	Lobby navigation and the service windows.
	- Bottom bar: TROOPS (loadout), DEPOT (troop shop), TASKS, SHOP, PASS, each with a red count
	  badge. There is no Play button: modes are joined only by standing on a Duels Hall pad.
	- Top centre: Coins and Gems; each "+" opens the shop on its own section. No game title.
	- A dismissable hint bubble when a new troop can be bought.
	- Tasks window (left): Daily, Weekly, and Supply & Codes tabs.
	- Shop window (right): Coins, Gems, Passes (VIP, Speed Boost, 2x Cash, 2x XP) and Specials,
	  with live Robux prices from MarketplaceService.
	- Pass window (centre): every tier's quest, progress, and free / premium rewards.
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
local Requirements = require(ReplicatedStorage.Shared.Logic.Requirements)
local TroopRotation = require(ReplicatedStorage.Shared.Logic.TroopRotation)
local RewardRules = require(ReplicatedStorage.Shared.Logic.RewardRules)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local ShopController = require(script.Parent.ShopController)
local LobbyController = require(script.Parent.LobbyController)

export type PanelName = "Tasks" | "Shop" | "Pass"

local UI = Theme.UI
local TOUCH = Widgets.TOUCH

local PanelsController = {}

PanelsController.questSettings = {
	regularPool = QuestConfig.RegularPool,
	testRealmPool = QuestConfig.TestRealmPool,
	regularPerDay = QuestConfig.RegularPerDay,
	testRealmPerDay = QuestConfig.TestRealmPerDay,
	seed = QuestConfig.Seed,
	weeklyPool = QuestConfig.WeeklyPool,
	weeklyPerWeek = QuestConfig.WeeklyPerWeek,
} :: QuestRules.QuestSettings

local maid = Maid.new()
local contentMaid = Maid.new()
local tasksWindow: Widgets.Window
local shopWindow: Widgets.Window
local passWindow: Widgets.Window
local tasksTab = "Daily"
local shopTab = "Coins"
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

local function today(): number
	return Calendar.dayNumber(now())
end

local function thisWeek(): number
	return Calendar.weekNumber(now())
end

-- Row: title, detail, progress bar, and an action button on the right.
local function taskRow(
	parent: Instance,
	order: number,
	accent: Color3,
	title: string,
	detail: string,
	fraction: number?,
	buttonText: string,
	enabled: boolean,
	onActivated: () -> ()
): Frame
	local card = Widgets.card(parent, accent, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 92) })
	Widgets.label(card, title, {
		Size = UDim2.new(0.62, 0, 0, 24),
		Position = UDim2.fromOffset(14, 10),
		Font = Theme.Fonts.Title,
	}, 20)
	Widgets.label(card, detail, {
		Size = UDim2.new(0.62, 0, 0, 18),
		Position = UDim2.fromOffset(14, 38),
		TextColor3 = Color3.fromRGB(180, 188, 220),
	}, 16)
	if fraction ~= nil then
		Widgets.bar(card, fraction, accent, { Size = UDim2.new(0.62, 0, 0, 10), Position = UDim2.fromOffset(14, 66) })
	end
	local button = Widgets.button(
		card,
		buttonText,
		accent,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.new(0.32, 0, 0, TOUCH),
		},
		contentMaid,
		function()
			if enabled then
				onActivated()
			end
		end
	)
	Widgets.setButton(button, buttonText, accent, enabled)
	return card
end

-- Tasks ------------------------------------------------------------------------------------

local function buildQuestRows(profile: Types.PlayerData, weekly: boolean)
	local list: { string } = if weekly
		then QuestRules.weeklyQuests(thisWeek(), PanelsController.questSettings)
		else QuestRules.dailyQuests(today(), PanelsController.questSettings)
	local current = if weekly then profile.quests.week == thisWeek() else profile.quests.day == today()
	local resetsAt = if weekly then Calendar.nextWeeklyResetAt(now()) else Calendar.nextResetAt(now())
	UIKit.setText(
		tasksWindow.subtitle,
		`{if weekly then "Weekly" else "Daily"} tasks reset in {Calendar.formatDuration(resetsAt - now())}`
	)
	for order, questId in list do
		local quest = QuestConfig.Quests[questId]
		local progressMap = if weekly then profile.quests.weeklyProgress else profile.quests.progress
		local claimedList = if weekly then profile.quests.weeklyClaimed else profile.quests.claimed
		local progress = if current then progressMap[questId] or 0 else 0
		local claimed = current and table.find(claimedList, questId) ~= nil
		local accent = if weekly then UI.Purple elseif quest.testRealm then Theme.Areas.TestRealm else UI.Gold
		local title = quest.description .. (if quest.testRealm then "  (Test Realm)" else "")
		taskRow(
			tasksWindow.body,
			order,
			accent,
			title,
			`{progress}/{quest.target}   -   {RewardRules.describe(quest.reward)}`,
			progress / quest.target,
			if claimed then "CLAIMED" elseif progress >= quest.target then "CLAIM" else "IN PROGRESS",
			not claimed and progress >= quest.target,
			function()
				Remotes.RequestClaimQuest:fire(questId)
			end
		)
	end
end

local function buildSupplyAndCodes(profile: Types.PlayerData)
	UIKit.setText(tasksWindow.subtitle, "Free supply drops every day, plus promo codes")
	local nextAt =
		SupplyRules.nextAvailableAt(profile.supply, now(), SupplyConfig.ClaimsPerDay, SupplyConfig.CooldownSeconds)
	local used = SupplyRules.claimsToday(profile.supply, now())
	local reward = SupplyConfig.Rewards[math.min(used + 1, #SupplyConfig.Rewards)]
	local detail = if nextAt == nil
		then `All claimed - resets in {Calendar.formatDuration(Calendar.nextResetAt(now()) - now())}`
		elseif nextAt <= now() then `Ready: {RewardRules.describe(reward)}`
		else `Next drop in {Calendar.formatDuration(nextAt - now())}`
	taskRow(
		tasksWindow.body,
		1,
		UI.Gold,
		`DAILY SUPPLY  {used}/{SupplyConfig.ClaimsPerDay}`,
		detail,
		used / SupplyConfig.ClaimsPerDay,
		"CLAIM",
		nextAt ~= nil and nextAt <= now(),
		function()
			Remotes.RequestClaimSupply:fire()
		end
	)

	local card = Widgets.card(tasksWindow.body, UI.Gem, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 120) })
	Widgets.label(card, "REDEEM A CODE", {
		Size = UDim2.new(1, -28, 0, 24),
		Position = UDim2.fromOffset(14, 10),
		Font = Theme.Fonts.Title,
		TextColor3 = UI.Gem,
	}, 20)
	local box = UIKit.create("TextBox", {
		Size = UDim2.new(0.62, 0, 0, TOUCH + 6),
		Position = UDim2.fromOffset(14, 50),
		BackgroundColor3 = UI.TrackBack,
		PlaceholderText = "Type a code...",
		PlaceholderColor3 = Color3.fromRGB(110, 118, 150),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Title,
		Parent = card,
	}) :: TextBox
	UIKit.corner(box, UDim.new(0, 12))
	UIKit.stroke(box, UI.Gem, 1.5, 0.5)
	UIKit.textLimit(box, 24)
	Widgets.button(
		card,
		"REDEEM",
		UI.Gem,
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 50),
			Size = UDim2.new(0.32, 0, 0, TOUCH + 6),
		},
		contentMaid,
		function()
			if box.Text ~= "" then
				Remotes.RequestRedeemCode:fire(string.sub(box.Text, 1, 32))
			end
		end
	)
end

local function refreshTasks(profile: Types.PlayerData)
	tasksWindow.clear()
	if tasksTab == "Weekly" then
		buildQuestRows(profile, true)
	elseif tasksTab == "Supply & Codes" then
		buildSupplyAndCodes(profile)
	else
		buildQuestRows(profile, false)
	end
end

-- Shop -------------------------------------------------------------------------------------

local function priceText(id: number, infoType: Enum.InfoType): string
	if id == 0 then
		return "SOON"
	end
	local cached = priceCache[id]
	if cached ~= nil then
		return cached
	end
	priceCache[id] = "..."
	task.spawn(function()
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		priceCache[id] = if ok
				and type(info) == "table"
				and type(info.PriceInRobux) == "number"
			then `R$ {info.PriceInRobux}`
			else "N/A"
		if shopWindow.isOpen() then
			PanelsController.refresh()
		end
	end)
	return "..."
end

local function productCard(order: number, productKey: string)
	local product = ShopConfig.Products[productKey]
	local accent = if product.kind == "Gems" then UI.Gem elseif product.kind == "Coins" then UI.Gold else UI.Pink
	local card = Widgets.card(shopWindow.body, accent, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 104) })
	local icon = UIKit.frame({
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.fromOffset(14, 14),
		BackgroundColor3 = accent,
		Parent = card,
	})
	UIKit.corner(icon, UDim.new(0, 16))
	UIKit.gradient(icon, accent:Lerp(Color3.new(1, 1, 1), 0.35), accent:Lerp(Color3.new(0, 0, 0), 0.25), 120)
	Widgets.label(
		icon,
		if product.kind == "Coins"
			then "$"
			elseif product.kind == "Gems" then "◆"
			elseif product.kind == "Troop" then "★"
			else "+",
		{
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Title,
			TextColor3 = Color3.fromRGB(20, 22, 34),
		},
		44
	)
	Widgets.label(card, string.upper(product.name), {
		Size = UDim2.new(1, -250, 0, 26),
		Position = UDim2.fromOffset(104, 16),
		Font = Theme.Fonts.Title,
	}, 22)
	Widgets.label(card, product.description, {
		Size = UDim2.new(1, -250, 0, 40),
		Position = UDim2.fromOffset(104, 46),
		TextColor3 = Color3.fromRGB(180, 188, 220),
		TextWrapped = true,
	}, 15)
	Widgets.button(
		card,
		priceText(product.productId, Enum.InfoType.Product),
		accent,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(120, TOUCH + 4),
		},
		contentMaid,
		function()
			if product.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.productId)
			end
		end
	)
end

local function passCard(order: number, passId: string)
	local pass = ShopConfig.GamePasses[passId]
	local owned = Players.LocalPlayer:GetAttribute("Pass_" .. passId) == true
	local card = Widgets.card(shopWindow.body, pass.color, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 104) })
	local badge = UIKit.frame({
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.fromOffset(14, 14),
		BackgroundColor3 = pass.color,
		Parent = card,
	})
	UIKit.corner(badge, UDim.new(1, 0))
	UIKit.gradient(badge, pass.color:Lerp(Color3.new(1, 1, 1), 0.35), pass.color:Lerp(Color3.new(0, 0, 0), 0.3), 120)
	Widgets.label(
		badge,
		if passId == "VIP"
			then "VIP"
			elseif passId == "SpeedBoost" then ">>"
			elseif passId == "DoubleCash" then "2x$"
			else "2xXP",
		{
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Title,
			TextColor3 = Color3.fromRGB(20, 22, 34),
		},
		24
	)
	Widgets.label(card, string.upper(pass.name), {
		Size = UDim2.new(1, -250, 0, 26),
		Position = UDim2.fromOffset(104, 16),
		Font = Theme.Fonts.Title,
	}, 22)
	Widgets.label(card, pass.description, {
		Size = UDim2.new(1, -250, 0, 40),
		Position = UDim2.fromOffset(104, 46),
		TextColor3 = Color3.fromRGB(180, 188, 220),
	}, 15)
	local button = Widgets.button(
		card,
		if owned then "OWNED" else priceText(pass.gamePassId, Enum.InfoType.GamePass),
		pass.color,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(120, TOUCH + 4),
		},
		contentMaid,
		function()
			if not owned and pass.gamePassId ~= 0 then
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.gamePassId)
			end
		end
	)
	if owned then
		Widgets.setButton(button, "OWNED", UI.Green, true)
	end
end

local function refreshShop()
	shopWindow.clear()
	if shopTab == "Passes" then
		UIKit.setText(shopWindow.subtitle, "Game passes never affect ranked")
		for order, passId in ShopConfig.GamePassOrder do
			passCard(order, passId)
		end
		return
	end
	UIKit.setText(
		shopWindow.subtitle,
		if shopTab == "Specials" then "Bundles and exclusive troops" else `Top up your {string.lower(shopTab)}`
	)
	local list: { string } = ShopConfig.Sections[shopTab] or {}
	for order, productKey in list do
		productCard(order, productKey)
	end
end

-- Season Pass ------------------------------------------------------------------------------

local function claimable(profile: Types.PlayerData): number
	if now() >= SeasonConfig.EndsAt or profile.season.seasonId ~= SeasonConfig.SeasonId then
		return 0
	end
	local count = 0
	for tier = 1, profile.season.tier do
		if table.find(profile.season.claimedFree, tier) == nil then
			count += 1
		end
		if profile.season.premium and table.find(profile.season.claimedPremium, tier) == nil then
			count += 1
		end
	end
	return count
end

local function rewardButton(
	parent: Instance,
	position: UDim2,
	track: Types.PassTrack,
	tier: number,
	reward: Types.Reward?,
	profile: Types.PlayerData
)
	local season = profile.season
	local claimedList = if track == "Free" then season.claimedFree else season.claimedPremium
	local claimed = table.find(claimedList, tier) ~= nil
	local reached = tier <= season.tier and season.seasonId == SeasonConfig.SeasonId
	local allowed = now() < SeasonConfig.EndsAt and reached and not claimed and (track == "Free" or season.premium)
	local accent = if track == "Free" then UI.Gem else UI.Gold
	local card = Widgets.card(parent, accent, { Position = position, Size = UDim2.new(1, -16, 0, 96) }, not reached)
	Widgets.label(card, if track == "Free" then "FREE" else "PREMIUM", {
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(8, 6),
		TextColor3 = accent,
		Font = Theme.Fonts.Title,
	}, 14)
	Widgets.label(card, if reward ~= nil then RewardRules.describe(reward) else "-", {
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(8, 22),
		TextWrapped = true,
	}, 15)
	local text = if claimed
		then "CLAIMED"
		elseif allowed then "CLAIM"
		elseif track == "Premium" and not season.premium then "LOCKED"
		else "..."
	local button = Widgets.button(
		card,
		text,
		accent,
		{
			Position = UDim2.new(0, 8, 1, -(TOUCH + 4)),
			Size = UDim2.new(1, -16, 0, TOUCH - 6),
		},
		contentMaid,
		function()
			if allowed then
				Remotes.RequestClaimPassReward:fire(tier, track)
			end
		end
	)
	Widgets.setButton(button, text, if claimed then UI.Green else accent, allowed or claimed)
end

local function refreshPass(profile: Types.PlayerData)
	passWindow.clear()
	local season = profile.season
	local current = if season.seasonId == SeasonConfig.SeasonId then season.tier else 0
	local remaining = SeasonConfig.EndsAt - now()
	UIKit.setText(
		passWindow.subtitle,
		if remaining > 0
			then `TIER {current}/{SeasonConfig.TierCount}   -   season ends in {Calendar.formatDuration(remaining)}`
			else "Season ended - rewards stay visible"
	)

	-- Header: current tier quest and premium.
	local header = Widgets.card(passWindow.body, UI.Gold, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 104) })
	local nextTier = SeasonConfig.Tiers[current + 1]
	Widgets.label(
		header,
		if nextTier ~= nil
			then `NEXT TIER {current + 1}: {string.upper(nextTier.quest.description)}`
			else "PASS COMPLETE!",
		{
			Size = UDim2.new(0.66, 0, 0, 26),
			Position = UDim2.fromOffset(16, 14),
			Font = Theme.Fonts.Title,
			TextColor3 = UI.Gold,
		},
		22
	)
	if nextTier ~= nil then
		Widgets.label(
			header,
			`{season.tierProgress}/{nextTier.quest.target}{if Players.LocalPlayer:GetAttribute("Pass_DoubleXP")
					== true
				then "   (2x XP active)"
				else ""}`,
			{
				Size = UDim2.new(0.66, 0, 0, 18),
				Position = UDim2.fromOffset(16, 46),
				TextColor3 = Color3.fromRGB(200, 208, 236),
			},
			16
		)
		Widgets.bar(header, season.tierProgress / nextTier.quest.target, UI.Gold, {
			Size = UDim2.new(0.66, 0, 0, 12),
			Position = UDim2.fromOffset(16, 74),
		})
	end
	local premium = ShopConfig.Products.SeasonPremium
	local premiumButton = Widgets.button(
		header,
		if season.premium then "PREMIUM ACTIVE" else "GET PREMIUM",
		UI.Gold,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.new(0.28, 0, 0, TOUCH + 6),
		},
		contentMaid,
		function()
			if not season.premium and premium.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, premium.productId)
			end
		end
	)
	if season.premium then
		Widgets.setButton(premiumButton, "PREMIUM ACTIVE", UI.Green, true)
	end

	local pending = profile.rank.pendingReward
	if pending ~= nil then
		taskRow(
			passWindow.body,
			2,
			Theme.Areas.DuelsGold,
			`RANKED REWARD: {string.upper(pending.tier)}`,
			RewardRules.describe(pending.reward),
			nil,
			"CLAIM",
			true,
			function()
				Remotes.RequestClaimPassReward:fire(0, "Ranked")
			end
		)
	end

	-- The tier track: a horizontal strip of tier columns, scrolled to the current tier.
	local track = UIKit.create("ScrollingFrame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 330),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = UI.Gold,
		Parent = passWindow.body,
	}) :: ScrollingFrame
	UIKit.list(track, Enum.FillDirection.Horizontal, UDim.new(0, 10), Enum.HorizontalAlignment.Left)
	local columnWidth = 176
	for _, tierDef in SeasonConfig.Tiers do
		local tier = tierDef.tier
		local reached = tier <= current
		local isNext = tier == current + 1
		local column = Widgets.card(track, if isNext then UI.Gold elseif reached then UI.Green else nil, {
			LayoutOrder = tier,
			Size = UDim2.new(0, columnWidth, 1, -14),
		}, not reached and not isNext)
		Widgets.label(column, `TIER {tier}`, {
			Size = UDim2.new(1, -16, 0, 26),
			Position = UDim2.fromOffset(8, 8),
			Font = Theme.Fonts.Title,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if reached then UI.Green elseif isNext then UI.Gold else Color3.fromRGB(150, 156, 180),
		}, 22)
		Widgets.label(column, tierDef.quest.description, {
			Size = UDim2.new(1, -16, 0, 34),
			Position = UDim2.fromOffset(8, 36),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.fromRGB(200, 208, 236),
			TextWrapped = true,
		}, 15)
		rewardButton(column, UDim2.fromOffset(8, 76), "Free", tier, tierDef.free, profile)
		rewardButton(column, UDim2.fromOffset(8, 180), "Premium", tier, tierDef.premium, profile)
	end
	task.defer(function()
		track.CanvasPosition = Vector2.new(math.max(0, (current - 1) * (columnWidth + 10)), 0)
	end)
end

-- Refresh / open --------------------------------------------------------------------------

function PanelsController.refresh()
	local profile = ClientState.profile
	if profile == nil then
		return
	end
	contentMaid:cleanup()
	if tasksWindow.isOpen() then
		refreshTasks(profile)
	end
	if shopWindow.isOpen() then
		refreshShop()
	end
	if passWindow.isOpen() then
		refreshPass(profile)
	end
end

-- `section` picks the shop tab ("Coins", "Gems", "Passes", "Specials").
function PanelsController.open(name: PanelName, section: string?)
	if ClientState.sandbox ~= nil then
		UIController.showToast(Constants.NoticeText.SANDBOX, "Error")
		return
	end
	if name == "Tasks" then
		tasksWindow.open()
	elseif name == "Shop" then
		shopWindow.open()
		if section ~= nil then
			shopWindow.setTab(section)
		end
	else
		passWindow.open()
	end
	PanelsController.refresh()
end

-- Badges and nav --------------------------------------------------------------------------

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

local function claimableTasks(profile: Types.PlayerData): number
	local count = 0
	local day = today()
	for _, questId in QuestRules.dailyQuests(day, PanelsController.questSettings) do
		local quest = QuestConfig.Quests[questId]
		if
			profile.quests.day == day
			and (profile.quests.progress[questId] or 0) >= quest.target
			and table.find(profile.quests.claimed, questId) == nil
		then
			count += 1
		end
	end
	local week = thisWeek()
	for _, questId in QuestRules.weeklyQuests(week, PanelsController.questSettings) do
		local quest = QuestConfig.Quests[questId]
		if
			profile.quests.week == week
			and (profile.quests.weeklyProgress[questId] or 0) >= quest.target
			and table.find(profile.quests.weeklyClaimed, questId) == nil
		then
			count += 1
		end
	end
	if SupplyRules.check(profile.supply, now(), SupplyConfig.ClaimsPerDay, SupplyConfig.CooldownSeconds) == "OK" then
		count += 1
	end
	return count
end

local function refreshBadges(profile: Types.PlayerData)
	UIKit.setText(coinsLabel, MathUtil.formatCount(profile.coins))
	UIKit.setText(gemsLabel, MathUtil.formatCount(profile.gems))
	local troops = affordableTroops(profile)
	local counts = {
		Depot = troops,
		Tasks = claimableTasks(profile),
		Pass = claimable(profile) + (if profile.rank.pendingReward ~= nil then 1 else 0),
	}
	for name, label in badges do
		local count = counts[name] or 0
		label.Visible = count > 0
		label.Text = tostring(count)
	end
	hint.Visible = troops > 0 and not hintDismissed and ClientState.match == nil
end

local NAV: { { name: string, icon: string, color: Color3 } } = {
	{ name = "Troops", icon = "⚙", color = UI.Pink },
	{ name = "Depot", icon = "◈", color = UI.Purple },
	{ name = "Tasks", icon = "✔", color = UI.Gold },
	{ name = "Shop", icon = "$", color = UI.Green },
	{ name = "Pass", icon = "★", color = UI.Gem },
}

local function navButton(bar: Frame, order: number, entry: { name: string, icon: string, color: Color3 })
	local button = UIKit.button({
		LayoutOrder = order,
		Size = UDim2.fromOffset(104, 64),
		Text = "",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
	})
	UIKit.corner(button, UDim.new(0, 16))
	UIKit.gradient(button, UI.WindowTop, UI.WindowBottom, 90)
	UIKit.stroke(button, entry.color, 2, 0.25)
	Widgets.label(button, entry.icon, {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 6),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = entry.color,
		Font = Theme.Fonts.Title,
	}, 26)
	Widgets.label(button, string.upper(entry.name), {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
	}, 15)
	UIKit.bindButton(button, maid, function()
		if entry.name == "Troops" then
			LobbyController.openPanel("Loadout")
		elseif entry.name == "Depot" then
			if ShopController.isOpen() then
				ShopController.close()
			else
				ShopController.open()
			end
		elseif entry.name == "Tasks" then
			if tasksWindow.isOpen() then
				tasksWindow.close()
			else
				PanelsController.open("Tasks")
			end
		elseif entry.name == "Shop" then
			if shopWindow.isOpen() then
				shopWindow.close()
			else
				PanelsController.open("Shop")
			end
		else
			if passWindow.isOpen() then
				passWindow.close()
			else
				PanelsController.open("Pass")
			end
		end
	end)
	local badge = UIKit.label({
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, 6, 0, -8),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(235, 52, 72),
		Font = Theme.Fonts.Title,
		Text = "0",
		Visible = false,
		ZIndex = 5,
		Parent = button,
	}, 16)
	UIKit.corner(badge, UDim.new(1, 0))
	UIKit.stroke(badge, Color3.new(1, 1, 1), 2)
	badges[entry.name] = badge
end

local function currencyChip(parent: Instance, order: number, color: Color3, icon: string, section: string): TextLabel
	local chip = UIKit.frame({
		LayoutOrder = order,
		Size = UDim2.fromOffset(196, 48),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	})
	UIKit.corner(chip, UDim.new(1, 0))
	UIKit.gradient(chip, UI.WindowTop, UI.WindowBottom, 90)
	UIKit.stroke(chip, color, 2, 0.2)
	local iconFrame = UIKit.frame({
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.fromOffset(5, 5),
		BackgroundColor3 = color,
		Parent = chip,
	})
	UIKit.corner(iconFrame, UDim.new(1, 0))
	Widgets.label(iconFrame, icon, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(20, 22, 34),
	}, 22)
	local label = Widgets.label(chip, "0", {
		Size = UDim2.new(1, -104, 1, -12),
		Position = UDim2.fromOffset(50, 6),
		Font = Theme.Fonts.Title,
		TextColor3 = color,
	}, 24)
	Widgets.button(
		chip,
		"+",
		color,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -5, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
		},
		maid,
		function()
			PanelsController.open("Shop", section)
		end
	)
	return label
end

local function buildNav(layer: Frame)
	local bar = UIKit.frame({
		Name = "NavBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(600, 64),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(bar, Enum.FillDirection.Horizontal, UDim.new(0, 12), Enum.HorizontalAlignment.Center)
	for order, entry in NAV do
		navButton(bar, order, entry)
	end

	hint = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -88),
		Size = UDim2.fromOffset(330, TOUCH),
		BackgroundColor3 = Color3.fromRGB(235, 52, 72),
		Text = "New troop available at the Depot!  ✕",
		Visible = false,
		Parent = layer,
	}, 18)
	UIKit.corner(hint, UDim.new(1, 0))
	UIKit.stroke(hint, Color3.new(1, 1, 1), 2, 0.3)
	UIKit.bindButton(hint, maid, function()
		hintDismissed = true
		hint.Visible = false
	end)

	local top = UIKit.frame({
		Name = "Currency",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 48),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(top, Enum.FillDirection.Horizontal, UDim.new(0, 14), Enum.HorizontalAlignment.Center)
	coinsLabel = currencyChip(top, 1, UI.Gold, "$", "Coins")
	gemsLabel = currencyChip(top, 2, UI.Gem, "◆", "Gems")
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
		Position = UDim2.fromScale(0.975, 0.5),
		Size = UDim2.fromOffset(340, 420),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = layer,
	})
	UIKit.corner(sandboxPanel, UDim.new(0, 18))
	UIKit.gradient(sandboxPanel, UI.WindowTop, UI.WindowBottom, 90)
	UIKit.stroke(sandboxPanel, Theme.Areas.TestRealm, 2, 0.2)
	Widgets.label(sandboxPanel, "TEST REALM", {
		Size = UDim2.new(1, -32, 0, 30),
		Position = UDim2.fromOffset(16, 12),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Areas.TestRealm,
	}, 26)
	sandboxLabel = Widgets.label(sandboxPanel, "", {
		Size = UDim2.new(1, -32, 0, 70),
		Position = UDim2.fromOffset(16, 46),
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(200, 208, 236),
	}, 16)
	local buttons = UIKit.frame({
		Size = UDim2.new(1, -32, 1, -136),
		Position = UDim2.fromOffset(16, 124),
		BackgroundTransparency = 1,
		Parent = sandboxPanel,
	})
	UIKit.create(
		"UIGridLayout",
		{ CellSize = UDim2.new(0.5, -5, 0, TOUCH + 6), CellPadding = UDim2.fromOffset(10, 10), Parent = buttons }
	)
	local mutationIndex = 1
	local actions: { { label: string, color: Color3, run: () -> () } } = {
		{
			label = "WAVE -",
			color = UI.Gem,
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.wave = math.max(1, c.wave - 1)
				end)
			end,
		},
		{
			label = "WAVE +",
			color = UI.Gem,
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.wave = math.min(Constants.TestRealm.MAX_WAVE, c.wave + 1)
				end)
			end,
		},
		{
			label = "SPEED -",
			color = UI.Gem,
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.speed = math.max(Constants.TestRealm.MIN_SPEED, c.speed - 0.5)
				end)
			end,
		},
		{
			label = "SPEED +",
			color = UI.Gem,
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.speed = math.min(Constants.TestRealm.MAX_SPEED, c.speed + 0.5)
				end)
			end,
		},
		{
			label = "+ MUTATION",
			color = UI.Purple,
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
			label = "CLEAR",
			color = UI.Purple,
			run = function()
				editSandbox(function(c: Types.SandboxConfig)
					c.mutations = {}
				end)
			end,
		},
		{
			label = "APPLY",
			color = UI.Green,
			run = function()
				if sandboxDraft ~= nil then
					Remotes.RequestSandboxConfig:fire(sandboxDraft)
				end
			end,
		},
		{
			label = "RESET",
			color = UI.Gold,
			run = function()
				Remotes.RequestSandboxReset:fire()
			end,
		},
	}
	for order, action in actions do
		local button = Widgets.button(buttons, action.label, action.color, { LayoutOrder = order }, maid, action.run)
		button.Size = UDim2.new()
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
	local modal = UIController.getLayer("Modal")
	buildNav(lobbyLayer)
	tasksWindow = Widgets.window({
		name = "Tasks",
		title = "TASKS",
		accent = UI.Gold,
		side = "Left",
		width = 0.33,
		height = 0.74,
		parent = modal,
		maid = maid,
		tabs = { "Daily", "Weekly", "Supply & Codes" },
		onTab = function(name: string)
			tasksTab = name
			PanelsController.refresh()
		end,
	})
	shopWindow = Widgets.window({
		name = "Shop",
		title = "SHOP",
		accent = UI.Green,
		side = "Right",
		width = 0.36,
		height = 0.76,
		parent = modal,
		maid = maid,
		tabs = { "Coins", "Gems", "Passes", "Specials" },
		onTab = function(name: string)
			shopTab = name
			PanelsController.refresh()
		end,
	})
	passWindow = Widgets.window({
		name = "Pass",
		title = `{SeasonConfig.DisplayName} PASS`,
		accent = UI.Gem,
		side = "Center",
		width = 0.66,
		height = 0.72,
		parent = modal,
		maid = maid,
	})
	buildSandboxPanel(UIController.getLayer("Overlay"))

	maid:give(ClientState.profileChanged:connect(function(profile: Types.PlayerData)
		refreshBadges(profile)
		PanelsController.refresh()
	end))
	maid:give(ClientState.sandboxChanged:connect(onSandbox))
	maid:give(ClientState.matchChanged:connect(function()
		Widgets.closeAll()
		hint.Visible = false
	end))
	maid:give(Remotes.ActionResult:connect(function(result: Types.ActionResult)
		if not result.ok then
			return
		end
		if result.action == "RedeemCode" then
			UIController.celebrate("CODE REDEEMED!", "Rewards added to your account.")
		elseif result.action == "ClaimPass" then
			UIController.showToast("Pass reward claimed!", "Success")
		end
	end))
	local profile = ClientState.profile
	if profile ~= nil then
		refreshBadges(profile)
	end
end

return PanelsController

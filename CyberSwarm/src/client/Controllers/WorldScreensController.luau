--!strict
--[[
	WorldScreensController
	Draws every live screen in the lobby for this player only: parts tagged WorldScreen get a
	SurfaceGui whose text depends on their Screen attribute (bay screens, hub screens, leaderboards,
	rank card, table plates, pass board, party list). Also:
	- Queue pad rings fill from the QueueBoard broadcast and turn red when the mode is locked for
	  this player (the bay plate then shows why). Locked pads never queue on the server either.
	- Troop Depot plinths show today's troops (TroopRotation) and spin.
	- Terminal ProximityPrompts open the matching panel. Terminals never queue for a mode.
	Nothing here sends a request that changes server state.
]]

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local ModeConfig = require(ReplicatedStorage.Shared.Config.ModeConfig)
local RankConfig = require(ReplicatedStorage.Shared.Config.RankConfig)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local SupplyConfig = require(ReplicatedStorage.Shared.Config.SupplyConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local Requirements = require(ReplicatedStorage.Shared.Logic.Requirements)
local QuestRules = require(ReplicatedStorage.Shared.Logic.QuestRules)
local SupplyRules = require(ReplicatedStorage.Shared.Logic.SupplyRules)
local RankMath = require(ReplicatedStorage.Shared.Logic.RankMath)
local TroopRotation = require(ReplicatedStorage.Shared.Logic.TroopRotation)
local RobotModels = require(ReplicatedStorage.Shared.Visual.RobotModels)
local ClientState = require(script.Parent.Parent.ClientState)
local ShopController = require(script.Parent.ShopController)
local LobbyController = require(script.Parent.LobbyController)
local PanelsController = require(script.Parent.PanelsController)

local Screen = Constants.ScreenKind
local Attributes = Constants.Attributes
local REFRESH = 0.5
local PIXELS_PER_STUD = 32

type ScreenView = {
	part: BasePart,
	kind: string,
	title: TextLabel,
	body: TextLabel,
	header: Frame?,
	stroke: UIStroke,
}

type Plinth = {
	part: BasePart,
	index: number,
	base: CFrame,
	model: Model?,
	troopId: string?,
}

local WorldScreensController = {}

local maid = Maid.new()
local screens: { ScreenView } = {}
local plinths: { Plinth } = {}
local rings: { [string]: { BasePart } } = {}
local spinAngle = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rotation(): Types.TroopRotation
	return TroopRotation.forTime(now(), ShopController.rotationSettings)
end

-- Client copy of the server's lock rules, for the red ring and the plate text.
function WorldScreensController.lockReason(mode: Types.ModeDef): string?
	local profile = ClientState.profile
	if profile == nil then
		return "Loading"
	end
	local ok, reason = Requirements.check(mode.unlock, Requirements.progressOf(profile), `to play {mode.displayName}`)
	if not ok then
		return reason
	end
	if mode.ranked then
		if now() >= SeasonConfig.Ranked.endsAt then
			return "Ranked season has ended"
		end
		local remaining = profile.rank.cooldownUntil - now()
		if remaining > 0 then
			return `Ranked cooldown {Calendar.formatDuration(remaining)}`
		end
	end
	return nil
end

local function boardEntry(modeId: string): Types.QueueBoardEntry?
	for _, entry in ClientState.queueBoard do
		if entry.modeId == modeId then
			return entry
		end
	end
	return nil
end

local function bar(value: number, target: number): string
	local filled = math.clamp(math.floor(value / math.max(target, 1) * 10 + 0.5), 0, 10)
	return string.rep("|", filled) .. string.rep(".", 10 - filled)
end

local function rankLines(profile: Types.PlayerData): string
	local lines: { string } = {}
	for ratingKey, label in RankConfig.RatingKeyNames do
		local data = profile.rank.ratings[ratingKey]
		if data == nil or data.played == 0 then
			table.insert(lines, `{label}: UNRANKED`)
		else
			local tier = RankMath.tierFor(data.rating, RankConfig.Tiers)
			local placement = if data.played < RankConfig.PlacementMatches
				then `  (placement {data.played}/{RankConfig.PlacementMatches})`
				else ""
			table.insert(lines, `{label}: {string.upper(tier.label)}  {math.floor(data.rating)}{placement}`)
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function textFor(view: ScreenView): (string, string, Color3?)
	local part = view.part
	local profile = ClientState.profile
	local kind = view.kind
	if kind == Screen.Event then
		local remaining = EventConfig.EndsAt - now()
		if remaining <= 0 then
			return EventConfig.AfterTitle, "New unit unlocked!", EventConfig.Accent
		end
		return EventConfig.Title, Calendar.formatDuration(remaining), EventConfig.Accent
	elseif kind == Screen.Supply then
		if profile == nil then
			return "DAILY SUPPLY", "", nil
		end
		local used = SupplyRules.claimsToday(profile.supply, now())
		local nextAt =
			SupplyRules.nextAvailableAt(profile.supply, now(), SupplyConfig.ClaimsPerDay, SupplyConfig.CooldownSeconds)
		local status = if nextAt == nil
			then `All claimed. Resets in {Calendar.formatDuration(Calendar.nextResetAt(now()) - now())}`
			elseif nextAt <= now() then "READY - use the supply terminal"
			else `Next drop in {Calendar.formatDuration(nextAt - now())}`
		return "DAILY SUPPLY", `{used}/{SupplyConfig.ClaimsPerDay} claimed today\n{status}`, Theme.Areas.HubRing
	elseif kind == Screen.Code then
		return "CODES", "Redeem codes at the terminal below", Theme.Areas.HubRingAccent
	elseif kind == Screen.Tasks then
		if profile == nil then
			return "DAILY TASKS", "", nil
		end
		local day = Calendar.dayNumber(now())
		local lines: { string } = {}
		for _, questId in QuestRules.dailyQuests(day, PanelsController.questSettings) do
			local quest = QuestConfig.Quests[questId]
			local progress = if profile.quests.day == day then profile.quests.progress[questId] or 0 else 0
			local done = if profile.quests.day == day and table.find(profile.quests.claimed, questId) ~= nil
				then "  DONE"
				else ""
			table.insert(lines, `{quest.description}\n[{bar(progress, quest.target)}] {progress}/{quest.target}{done}`)
		end
		return "DAILY TASKS", table.concat(lines, "\n"), Theme.Areas.HubRing
	elseif kind == Screen.Leaderboard then
		local boardId = part:GetAttribute(Attributes.Board)
		local snapshot = if type(boardId) == "string" then ClientState.leaderboards[boardId] else nil
		local title = if boardId == Constants.Leaderboard.WIN_STREAK then "WIN STREAKS" else "RANKED"
		if snapshot == nil or #snapshot.entries == 0 then
			return title, "No entries yet. Be the first!", Theme.Areas.DuelsGold
		end
		local lines: { string } = {}
		for _, entry in snapshot.entries do
			table.insert(lines, `{entry.rank}. {entry.name}  {entry.value}`)
		end
		return `{title}{if snapshot.live then "   LIVE" else ""}`, table.concat(lines, "\n"), Theme.Areas.DuelsGold
	elseif kind == Screen.Bay then
		local modeId = part:GetAttribute(Attributes.ModeId)
		local mode = if type(modeId) == "string" then ModeConfig.Modes[modeId] else nil
		if mode == nil then
			return "", "", nil
		end
		local teamText = if mode.teams > 1
			then `{mode.teamSize}v{mode.teamSize}`
			else `{mode.minPlayers}-{mode.maxPlayers} PLAYERS`
		local lock = WorldScreensController.lockReason(mode)
		local notice = ClientState.queueNotice
		if lock ~= nil then
			return string.upper(mode.displayName), `{teamText}\nLOCKED: {lock}`, Theme.World.RingLocked
		end
		if notice ~= nil and notice.modeId == mode.id then
			return string.upper(mode.displayName), `{teamText}\n{notice.reason}`, Theme.World.RingLocked
		end
		local entry = boardEntry(mode.id)
		local count = if entry ~= nil then entry.count else 0
		local size = if entry ~= nil then entry.matchSize else mode.minPlayers
		local status = "Step on the pad to queue"
		if entry ~= nil and entry.countdownEndsAt ~= nil then
			status = `STARTING IN {math.max(0, math.ceil(entry.countdownEndsAt - now()))}`
		elseif count > 0 then
			status =
				`Est. wait {Calendar.formatDuration(if entry ~= nil then entry.estimatedWait else mode.estimatedWait)}`
		end
		return string.upper(mode.displayName), `{teamText}   QUEUED {count}/{size}\n{status}`, mode.signColor
	elseif kind == Screen.LimitedBay then
		return "LIMITED TIME", "Coming soon", ModeConfig.CategoryColors.Limited
	elseif kind == Screen.DuelsStatus then
		local total = 0
		for _, entry in ClientState.queueBoard do
			total += entry.count
		end
		return "", `{total} QUEUED`, Theme.Areas.Duels
	elseif kind == Screen.RankCard then
		if profile == nil then
			return "RANK", "", nil
		end
		local remaining = SeasonConfig.Ranked.endsAt - now()
		local season = if remaining > 0 then `Season ends in {Calendar.formatDuration(remaining)}` else "Season ended"
		return SeasonConfig.Ranked.displayName, `{rankLines(profile)}\n{season}`, Theme.Areas.DuelsGold
	elseif kind == Screen.Table then
		local index = part:GetAttribute(Attributes.TableIndex)
		local troopId = if type(index) == "number" then TroopRotation.tables(rotation())[index] else nil
		local troop = if troopId ~= nil then TroopConfig.Troops[troopId] else nil
		if troop == nil then
			return "", "", nil
		end
		local owned = profile ~= nil and table.find(profile.unlockedRobots, troop.id) ~= nil
		local price = if troop.comingSoon
			then "COMING SOON"
			elseif owned then "OWNED"
			else `{troop.price} {if troop.currency == "Gems" then "GEMS" else "COINS"}`
		return string.upper(troop.name), `{string.upper(troop.rarity)}  -  {price}`, Theme.rarityColor(troop.rarity)
	elseif kind == Screen.Rotation then
		local current = rotation()
		return "DAILY ROTATION", `New troops in {Calendar.formatDuration(current.resetsAt - now())}`, Theme.Areas.Troops
	elseif kind == Screen.Currency then
		if profile == nil then
			return "", "", nil
		end
		return "", `COINS {profile.coins}   GEMS {profile.gems}`, Theme.Areas.Troops
	elseif kind == Screen.Pass then
		if profile == nil then
			return SeasonConfig.DisplayName, "", nil
		end
		local tier = if profile.season.seasonId == SeasonConfig.SeasonId then profile.season.tier else 0
		local remaining = SeasonConfig.EndsAt - now()
		local ends = if remaining > 0
			then `Ends in {Calendar.formatDuration(remaining)}`
			else "Season ended - rewards still visible"
		return `{SeasonConfig.DisplayName} PASS`,
			`Tier {tier}/{SeasonConfig.TierCount}{if profile.season.premium then "  PREMIUM" else ""}\n{ends}`,
			Theme.Areas.Market
	elseif kind == Screen.Party then
		local party = ClientState.party
		if #party.members == 0 then
			return "PARTY", "Stand on FORM PARTY with friends", Theme.Areas.Party
		end
		return "PARTY", `Leader: {party.leader or ""}\n{table.concat(party.members, ", ")}`, Theme.Areas.Party
	elseif kind == Screen.TestRealm then
		return "TEST REALM",
			"Stand on the portal.\nAny troop, any defense.\nNothing earned or lost.",
			Theme.Areas.TestRealm
	end
	return "", "", nil
end

-- Plain-text screens with no title use the whole face.
local BARE_SCREENS = { [Screen.DuelsStatus] = true, [Screen.Currency] = true }

local function buildView(part: BasePart, kind: string): ScreenView
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveScreen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Adornee = part

	-- Glassy panel with a soft gradient and a glowing edge.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(1, -16, 1, -16)
	panel.Position = UDim2.fromOffset(8, 8)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = panel
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Theme.UI.WindowTop, Theme.UI.WindowBottom)
	gradient.Rotation = 90
	gradient.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Theme.Colors.Primary
	stroke.Transparency = 0.2
	stroke.Parent = panel

	local bare = BARE_SCREENS[kind] == true
	local header: Frame? = nil
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Theme.Fonts.Title
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(16, 18, 30)
	if not bare then
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, 0, 0.27, 0)
		strip.BackgroundColor3 = Theme.Colors.Primary
		strip.BorderSizePixel = 0
		strip.Parent = panel
		local stripCorner = Instance.new("UICorner")
		stripCorner.CornerRadius = UDim.new(0, 18)
		stripCorner.Parent = strip
		-- Square off the strip's bottom corners so it reads as a header bar.
		local filler = Instance.new("Frame")
		filler.Size = UDim2.new(1, 0, 0.4, 0)
		filler.Position = UDim2.fromScale(0, 0.6)
		filler.BackgroundColor3 = Color3.new(1, 1, 1)
		filler.BorderSizePixel = 0
		filler.Parent = strip
		local stripGradient = Instance.new("UIGradient")
		stripGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
		stripGradient.Rotation = 90
		stripGradient.Parent = strip
		title.Size = UDim2.new(0.92, 0, 0.8, 0)
		title.Position = UDim2.fromScale(0.04, 0.1)
		title.Parent = strip
		header = strip
	else
		title.Visible = false
		title.Parent = panel
	end

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Size = if bare then UDim2.fromScale(0.92, 0.84) else UDim2.fromScale(0.92, 0.62)
	body.Position = if bare then UDim2.fromScale(0.04, 0.08) else UDim2.fromScale(0.04, 0.32)
	body.Font = Theme.Fonts.Body
	body.TextScaled = true
	body.TextWrapped = true
	body.TextColor3 = Color3.fromRGB(232, 238, 255)
	body.Parent = panel
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 120
	limit.Parent = body
	gui.Parent = part
	return { part = part, kind = kind, title = title, body = body, header = header, stroke = stroke }
end

local function render(view: ScreenView)
	local title, body, accent = textFor(view)
	if view.title.Text ~= title then
		view.title.Text = title
	end
	if view.body.Text ~= body then
		view.body.Text = body
	end
	local color = accent or Theme.Colors.Primary
	view.stroke.Color = color
	local header = view.header
	if header ~= nil then
		header.BackgroundColor3 = color
		for _, child in header:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundColor3 = color
			end
		end
	else
		view.body.TextColor3 = color
	end
end

local function renderRings()
	for modeId, segments in rings do
		local mode = ModeConfig.Modes[modeId]
		local entry = boardEntry(modeId)
		local locked = WorldScreensController.lockReason(mode) ~= nil
		local fill = if entry ~= nil and entry.matchSize > 0 then math.min(1, entry.count / entry.matchSize) else 0
		local lit = if fill <= 0 then 0 else math.max(1, math.floor(fill * #segments + 0.5))
		for index, segment in segments do
			if locked then
				segment.Color = Theme.World.RingLocked
				segment.Material = Enum.Material.SmoothPlastic
			else
				local on = index <= lit
				segment.Color = if on then mode.signColor else Theme.World.RingUnlit
				segment.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end

local function refreshPlinths()
	local tables = TroopRotation.tables(rotation())
	for _, plinth in plinths do
		local troopId = tables[plinth.index]
		if troopId == plinth.troopId then
			continue
		end
		plinth.troopId = troopId
		if plinth.model ~= nil then
			plinth.model:Destroy()
			plinth.model = nil
		end
		local robot = if troopId ~= nil then RobotConfig.Robots[troopId] else nil
		if robot ~= nil then
			local model = RobotModels.build(robot)
			model:PivotTo(plinth.base * CFrame.new(0, 3, 0))
			model.Parent = plinth.part.Parent
			plinth.model = model
		end
		for _, sibling in (plinth.part.Parent :: Instance):GetChildren() do
			if sibling:IsA("BasePart") and sibling.Name == "RarityTrim" then
				sibling.Color = if robot ~= nil then Theme.rarityColor(robot.rarity) else Theme.World.RingUnlit
				sibling.Material = Enum.Material.Neon
			end
		end
	end
end

type Spinner = { part: BasePart, base: CFrame, speed: number }
type Orbiter = { parts: { BasePart }, offsets: { Vector3 }, center: Vector3, index: number }

local spinners: { Spinner } = {}
local orbiters: { Orbiter } = {}
local clockTime = 0

local function animateDisplays(dt: number)
	clockTime += dt
	for _, spinner in spinners do
		spinner.part.CFrame = spinner.base * CFrame.Angles(0, math.rad(clockTime * spinner.speed), 0)
	end
	-- Mannequin drones circle their robot, bobbing slightly.
	for _, orbiter in orbiters do
		local angle = clockTime * 1.4 + (orbiter.index - 1) / 3 * math.pi * 2
		local radius = Vector3.new(orbiter.offsets[1].X, 0, orbiter.offsets[1].Z).Magnitude
		local height = orbiter.offsets[1].Y + math.sin(clockTime * 2 + orbiter.index) * 0.4
		local position = orbiter.center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		for partIndex, part in orbiter.parts do
			local relative = orbiter.offsets[partIndex] - orbiter.offsets[1]
			part.CFrame = CFrame.lookAt(
				position + relative,
				position + relative + Vector3.new(-math.sin(angle), 0, math.cos(angle))
			)
		end
	end
end

local function collectDisplays()
	for _, instance in CollectionService:GetTagged(Constants.Tags.Spinner) do
		if instance:IsA("BasePart") and not CollectionService:HasTag(instance, Constants.Tags.TroopTable) then
			local speed = instance:GetAttribute(Attributes.SpinSpeed)
			table.insert(
				spinners,
				{ part = instance, base = instance.CFrame, speed = if type(speed) == "number" then speed else 40 }
			)
		end
	end
	for _, instance in CollectionService:GetTagged(Constants.Tags.Mannequin) do
		if instance:IsA("Model") then
			local center = instance:GetPivot().Position
			local groups: { [number]: { BasePart } } = {}
			for _, descendant in instance:GetDescendants() do
				local index = descendant:GetAttribute("OrbitIndex")
				if descendant:IsA("BasePart") and type(index) == "number" then
					groups[index] = groups[index] or {}
					table.insert(groups[index], descendant)
				end
			end
			for index, parts in groups do
				-- Body part first so the group orbits around its own centre.
				table.sort(parts, function(a: BasePart, b: BasePart)
					return a.Name < b.Name
				end)
				local offsets: { Vector3 } = {}
				for _, part in parts do
					table.insert(offsets, part.Position - center)
				end
				table.insert(orbiters, { parts = parts, offsets = offsets, center = center, index = index })
			end
		end
	end
end

local function spin(dt: number)
	animateDisplays(dt)
	spinAngle = (spinAngle + dt * 40) % 360
	local turn = CFrame.Angles(0, math.rad(spinAngle), 0)
	for _, plinth in plinths do
		local model = plinth.model
		if model ~= nil then
			model:PivotTo(CFrame.new(plinth.base.Position + Vector3.new(0, 3, 0)) * turn)
		end
	end
end

local function onPrompt(prompt: ProximityPrompt)
	local parent = prompt.Parent
	if parent == nil then
		return
	end
	local terminal = parent:GetAttribute(Attributes.Terminal)
	if terminal == "Loadout" then
		LobbyController.openPanel("Loadout")
	elseif terminal == "TroopShop" then
		ShopController.open()
	elseif terminal == "Code" then
		PanelsController.open("Tasks")
	elseif terminal == "RobuxShop" then
		PanelsController.open("Shop")
	elseif terminal == "Pass" then
		PanelsController.open("Pass")
	elseif terminal == "RobuxPasses" then
		PanelsController.open("Shop", "Passes")
	elseif terminal == "RobuxSpecials" then
		PanelsController.open("Shop", "Specials")
	end
	-- "Supply" is claimed by the server's own prompt handler.
end

function WorldScreensController.init()
	for _, instance in CollectionService:GetTagged(Constants.Tags.WorldScreen) do
		local kind = instance:GetAttribute(Attributes.Screen)
		if instance:IsA("BasePart") and type(kind) == "string" then
			table.insert(screens, buildView(instance, kind))
		end
	end
	for _, instance in CollectionService:GetTagged(Constants.Tags.QueuePad) do
		local modeId = instance:GetAttribute(Attributes.ModeId)
		local folder = instance:FindFirstChild("Ring")
		if type(modeId) == "string" and ModeConfig.Modes[modeId] ~= nil and folder ~= nil then
			local segments: { BasePart } = {}
			for index = 1, #folder:GetChildren() do
				local segment = folder:FindFirstChild(`Segment_{index}`)
				if segment ~= nil and segment:IsA("BasePart") then
					table.insert(segments, segment)
				end
			end
			rings[modeId] = segments
		end
	end
	collectDisplays()
	for _, instance in CollectionService:GetTagged(Constants.Tags.TroopTable) do
		local index = instance:GetAttribute(Attributes.TableIndex)
		if instance:IsA("BasePart") and type(index) == "number" then
			table.insert(
				plinths,
				{ part = instance, index = index, base = instance.CFrame, model = nil, troopId = nil }
			)
		end
	end

	local function renderAll()
		for _, view in screens do
			render(view)
		end
		renderRings()
		refreshPlinths()
	end
	maid:give(ClientState.profileChanged:connect(renderAll))
	maid:give(ClientState.queueBoardChanged:connect(renderAll))
	maid:give(ClientState.leaderboardChanged:connect(renderAll))
	maid:give(ClientState.partyChanged:connect(renderAll))
	maid:give(ProximityPromptService.PromptTriggered:Connect(onPrompt))
	local elapsed = 0
	maid:give(RunService.Heartbeat:Connect(function(dt: number)
		spin(dt)
		elapsed += dt
		if elapsed >= REFRESH then
			elapsed = 0
			renderAll()
		end
	end))
	renderAll()
end

return WorldScreensController

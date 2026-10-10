--!strict
--[[
	TestRealmService
	The Test Realm sandbox: try any troop against any defense, with nothing earned or lost.

	Getting there: stand on the portal pad behind the Troop Depot's glass wall for
	Constants.Lobby.PAD_DWELL seconds (no key press). A party leader takes their free party
	members along; anyone else goes solo. The group is teleported to a private reserved server of
	this place (TeleportOptions.ShouldReserveServer). In Studio, where teleports do not work, the
	same sandbox runs locally on this server instead.

	On a Test Realm server (a reserved server: PrivateServerId set, no owner):
	- DataService runs read-only (setSandboxServer), so no write can happen at all.
	- One sandbox match (mode TestRealm, map TestYard) runs for everyone present, with unlimited
	  coins, every troop available, and the group's SandboxConfig (start wave, mutation stacks,
	  speed). Ranked is impossible: QueueService does not even run there.
	- RequestSandboxConfig changes the settings (validated); RequestSandboxReset restarts the
	  match with them. A finished match restarts on its own.
	- The RETURN pad on the yard deck teleports the player back to a public server.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local Notifier = require(script.Parent.Parent.Notifier)
local DataService = require(script.Parent.DataService)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local PartyService = require(script.Parent.PartyService)
local QuestService = require(script.Parent.QuestService)

local LOBBY = Constants.Lobby
local REALM = Constants.TestRealm
local ErrorCode = Constants.ErrorCode
local RESTART_DELAY = 3
local MODE_ID = "TestRealm"

type Realm = {
	players: { Player },
	config: Types.SandboxConfig,
	match: ServerTypes.Match?,
	-- Bumped on every (re)start so a stale restart timer does nothing.
	generation: number,
	isLocal: boolean,
}

local TestRealmService = {}

local realms: { Realm } = {}
local playerRealm: { [Player]: Realm } = {}
local portalSince: { [Player]: number } = {}
local portalCooldown: { [Player]: number } = {}
local returnSince: { [Player]: number } = {}
local serverMode = false

function TestRealmService.isTestRealmServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function defaultConfig(): Types.SandboxConfig
	local loadout: { string } = {}
	for _, robotId in RobotConfig.Order do
		local robot = RobotConfig.Robots[robotId]
		if not robot.locked and #loadout < Constants.MAX_LOADOUT then
			table.insert(loadout, robotId)
		end
	end
	return { loadout = loadout, wave = 1, mutations = {}, speed = 1 }
end

-- Validates a client-sent config. Returns nil when anything is off.
local function readConfig(raw: unknown): Types.SandboxConfig?
	if not TableUtil.isTable(raw) then
		return nil
	end
	local source = raw :: any
	local wave = source.wave
	local speed = source.speed
	if type(wave) ~= "number" or wave ~= wave or wave % 1 ~= 0 or wave < 1 or wave > REALM.MAX_WAVE then
		return nil
	end
	if type(speed) ~= "number" or speed ~= speed or speed < REALM.MIN_SPEED or speed > REALM.MAX_SPEED then
		return nil
	end
	if not TableUtil.isStrictArray(source.loadout, Constants.MAX_LOADOUT) or #source.loadout == 0 then
		return nil
	end
	local loadout: { string } = {}
	for _, robotId in source.loadout do
		local robot = if type(robotId) == "string" then RobotConfig.Robots[robotId] else nil
		if robot == nil or robot.locked or table.find(loadout, robot.id) ~= nil then
			return nil
		end
		table.insert(loadout, robot.id)
	end
	local mutations: { [string]: number } = {}
	if not TableUtil.isTable(source.mutations) then
		return nil
	end
	local count = 0
	for mutationId, stacks in source.mutations do
		count += 1
		local mutation = if type(mutationId) == "string" then MutationConfig.Mutations[mutationId] else nil
		if mutation == nil or count > #MutationConfig.Order then
			return nil
		end
		local cap = math.min(mutation.maxStacks, REALM.MAX_MUTATION_STACKS)
		if type(stacks) ~= "number" or stacks % 1 ~= 0 or stacks < 0 or stacks > cap then
			return nil
		end
		if stacks > 0 then
			mutations[mutation.id] = stacks
		end
	end
	return { loadout = loadout, wave = wave, mutations = mutations, speed = math.floor(speed * 4 + 0.5) / 4 }
end

local function broadcast(realm: Realm)
	Remotes.SandboxState:fireClients(realm.players, { active = true, config = realm.config })
end

local startRealm: (realm: Realm) -> ()

startRealm = function(realm: Realm)
	realm.generation += 1
	local current = realm.match
	realm.match = nil
	if current ~= nil and not current.closed then
		MatchService.cancel(current)
	end
	local present: { Player } = {}
	for _, player in realm.players do
		if player.Parent ~= nil and DataService.isLoaded(player) then
			table.insert(present, player)
		end
	end
	if #present == 0 then
		return
	end
	local ok, errorCode, match = MatchService.startMatch(MODE_ID, present, {
		teams = { present },
		sandbox = TableUtil.deepCopy(realm.config),
	})
	if not ok then
		warn(`[TestRealmService] Sandbox match failed to start: {errorCode}`)
		return
	end
	realm.match = match
	broadcast(realm)
end

local function restartSoon(realm: Realm)
	local generation = realm.generation
	task.delay(RESTART_DELAY, function()
		if realm.generation == generation and #realm.players > 0 then
			startRealm(realm)
		end
	end)
end

local function removeFromRealm(player: Player)
	local realm = playerRealm[player]
	if realm == nil then
		return
	end
	playerRealm[player] = nil
	local index = table.find(realm.players, player)
	if index ~= nil then
		table.remove(realm.players, index)
	end
	if #realm.players == 0 then
		realm.generation += 1
		local match = realm.match
		realm.match = nil
		if match ~= nil and not match.closed then
			MatchService.cancel(match)
		end
		local realmIndex = table.find(realms, realm)
		if realmIndex ~= nil then
			table.remove(realms, realmIndex)
		end
	end
end

-- Studio: run the sandbox on this server and block every write for these players.
local function enterLocal(group: { Player })
	local realm: Realm = { players = {}, config = defaultConfig(), match = nil, generation = 0, isLocal = true }
	for _, player in group do
		DataService.setSandbox(player, true)
		playerRealm[player] = realm
		table.insert(realm.players, player)
	end
	table.insert(realms, realm)
	Notifier.banner(group, "Info", "TEST REALM", "Local sandbox (Studio). Nothing here is earned or lost.")
	startRealm(realm)
end

local function leaveLocal(player: Player)
	removeFromRealm(player)
	DataService.setSandbox(player, false)
	QuestService.mergeLocalSandbox(player)
	Remotes.SandboxState:fireClient(player, { active = false, config = defaultConfig() })
	Remotes.MatchClosed:fireClient(player, true)
	LobbyService.returnToLobby(player)
end

local function teleportGroup(group: { Player }, reserve: boolean)
	local options = Instance.new("TeleportOptions")
	if reserve then
		options.ShouldReserveServer = true
		options:SetTeleportData({ [REALM.TELEPORT_TAG] = true })
	end
	for attempt = 1, LOBBY.TELEPORT_ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, group, options)
		end)
		if ok then
			return
		end
		warn(`[TestRealmService] Teleport attempt {attempt} failed: {err}`)
		task.wait(2 ^ attempt)
	end
	for _, player in group do
		if player.Parent ~= nil then
			Notifier.error(player, ErrorCode.TeleportFailed)
		end
	end
end

local function groupFor(player: Player): { Player }
	local party = PartyService.partyOf(player)
	if party == nil or party.leader ~= player then
		return { player }
	end
	local group: { Player } = {}
	for _, member in party.members do
		if member.Parent ~= nil and DataService.isLoaded(member) and not MatchService.isInMatch(member) and playerRealm[member] == nil then
			table.insert(group, member)
		end
	end
	return group
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function onTagged(position: Vector3, tag: string): boolean
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			local offset = instance.CFrame:PointToObjectSpace(position)
			local half = instance.Size * 0.5
			local radius = math.max(half.Y, half.Z)
			if instance:IsA("Part") and instance.Shape == Enum.PartType.Cylinder then
				if math.sqrt(offset.Y * offset.Y + offset.Z * offset.Z) <= radius and offset.X >= -1 and offset.X <= 8 then
					return true
				end
			elseif math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z and offset.Y >= 0 and offset.Y <= 8 then
				return true
			end
		end
	end
	return false
end

-- Main server: portal pad dwell.
local function checkPortal(player: Player, now: number)
	local root = rootOf(player)
	local onPortal = root ~= nil
		and onTagged(root.Position, Constants.Tags.TestRealmPortal)
		and not MatchService.isInMatch(player)
		and playerRealm[player] == nil
		and DataService.isLoaded(player)
	if not onPortal then
		portalSince[player] = nil
		return
	end
	local since = portalSince[player]
	if since == nil then
		portalSince[player] = now
		return
	end
	if now - since < LOBBY.PAD_DWELL or now < (portalCooldown[player] or 0) then
		return
	end
	portalSince[player] = nil
	local group = groupFor(player)
	for _, member in group do
		portalCooldown[member] = now + LOBBY.PORTAL_COOLDOWN
	end
	if RunService:IsStudio() then
		enterLocal(group)
	else
		Notifier.toast(group, "Info", "Heading to the Test Realm...")
		task.spawn(teleportGroup, group, true)
	end
end

-- Yard RETURN pad (both Studio's local realm and Test Realm servers).
local function checkReturn(player: Player, now: number)
	local root = rootOf(player)
	if root == nil or playerRealm[player] == nil or not onTagged(root.Position, Constants.Tags.TestRealmReturn) then
		returnSince[player] = nil
		return
	end
	local since = returnSince[player]
	if since == nil then
		returnSince[player] = now
		return
	end
	if now - since < LOBBY.PAD_DWELL then
		return
	end
	returnSince[player] = nil
	if serverMode then
		Notifier.toast({ player }, "Info", "Returning to the main game...")
		task.spawn(teleportGroup, { player }, false)
	else
		leaveLocal(player)
	end
end

local function tick()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if not serverMode then
			checkPortal(player, now)
		end
		checkReturn(player, now)
	end
end

local function realmOfMatch(match: ServerTypes.Match): Realm?
	for _, realm in realms do
		if realm.match == match then
			return realm
		end
	end
	return nil
end

-- Test Realm server: everyone here shares one realm.
local function startServerMode()
	local realm: Realm = { players = {}, config = defaultConfig(), match = nil, generation = 0, isLocal = false }
	table.insert(realms, realm)
	-- Arrival platform so nobody falls before the yard match places them.
	local arrival = Instance.new("SpawnLocation")
	arrival.Name = "TestRealmArrival"
	arrival.Anchored = true
	arrival.Size = Vector3.new(30, 1, 30)
	arrival.CFrame = CFrame.new(Constants.World.LOBBY_ORIGIN)
	arrival.Neutral = true
	arrival.Duration = 0
	arrival.Color = Color3.fromRGB(64, 196, 226)
	arrival.Parent = workspace

	local function join(player: Player)
		if playerRealm[player] ~= nil then
			return
		end
		playerRealm[player] = realm
		table.insert(realm.players, player)
		-- Late arrivals (party members) join through a restart with everyone present.
		local generation = realm.generation
		task.delay(LOBBY.SANDBOX_ARRIVAL_WAIT, function()
			if realm.generation == generation then
				startRealm(realm)
			end
		end)
	end
	DataService.profileLoaded:connect(join)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			join(player)
		end
	end
end

function TestRealmService.init()
	serverMode = TestRealmService.isTestRealmServer()
end

function TestRealmService.start()
	if serverMode then
		startServerMode()
	end

	Remotes.RequestSandboxConfig:connect(function(player: Player, raw: unknown)
		local realm = playerRealm[player]
		if realm == nil then
			return
		end
		local config = readConfig(raw)
		if config == nil then
			Notifier.error(player, ErrorCode.InvalidRequest)
			return
		end
		realm.config = config
		broadcast(realm)
		Notifier.toast(realm.players, "Info", "Test Realm settings updated. Reset to apply.")
	end)
	Remotes.RequestSandboxReset:connect(function(player: Player)
		local realm = playerRealm[player]
		if realm ~= nil then
			startRealm(realm)
		end
	end)
	Remotes.RequestSync:connect(function(player: Player)
		local realm = playerRealm[player]
		if realm ~= nil then
			Remotes.SandboxState:fireClient(player, { active = true, config = realm.config })
		end
	end)
	MatchService.matchEnded:connect(function(match: ServerTypes.Match)
		local realm = realmOfMatch(match)
		if realm ~= nil then
			restartSoon(realm)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		removeFromRealm(player)
		portalSince[player] = nil
		portalCooldown[player] = nil
		returnSince[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(LOBBY.PAD_TICK)
			tick()
		end
	end)
end

return TestRealmService

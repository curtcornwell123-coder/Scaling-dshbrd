--!strict
--[[
	LobbyService
	Owns the hub: builds the lobby, keeps players spawning there, moves characters between the
	lobby and arenas, and handles lobby intents (loadout changes and robot unlocks). All of those
	intents are validated against the player's saved data before anything changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local RobotConfig = require(ReplicatedStorage.Shared.Config.RobotConfig)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Parent.Notifier)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)

local ErrorCode = Constants.ErrorCode
local SPAWN_SCATTER = 4

local LobbyService = {}

local lobby: LobbyBuilder.Lobby
local scatter = Random.new()

function LobbyService.getPads(): { LobbyBuilder.PadInfo }
	return lobby.pads
end

-- Moves a character, guarded because the character can be mid-respawn or already destroyed.
function LobbyService.teleport(player: Player, cframe: CFrame): boolean
	local character = player.Character
	if character == nil or character.Parent == nil then
		return false
	end
	local ok, err = pcall(function()
		character:PivotTo(cframe)
	end)
	if not ok then
		warn(`[LobbyService] Could not teleport {player.Name}: {err}`)
	end
	return ok
end

-- Players watch matches from a fixed camera, so their characters are frozen in place meanwhile.
function LobbyService.setMovementLocked(player: Player, locked: boolean)
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	if locked then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	else
		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
		humanoid.JumpPower = StarterPlayer.CharacterJumpPower
		humanoid.JumpHeight = StarterPlayer.CharacterJumpHeight
	end
end

function LobbyService.returnToLobby(player: Player)
	LobbyService.setMovementLocked(player, false)
	local offset = Vector3.new(
		scatter:NextNumber(-SPAWN_SCATTER, SPAWN_SCATTER),
		Constants.World.PLAYER_SPAWN_LIFT,
		scatter:NextNumber(-SPAWN_SCATTER, SPAWN_SCATTER)
	)
	LobbyService.teleport(player, lobby.spawn.CFrame + offset)
end

function LobbyService.teleportToPad(player: Player, modeId: string): boolean
	for _, padInfo in lobby.pads do
		if padInfo.modeId == modeId then
			return LobbyService.teleport(player, padInfo.pad.CFrame + Vector3.new(0, Constants.World.PLAYER_SPAWN_LIFT, 0))
		end
	end
	return false
end

local function onSetLoadout(player: Player, loadout: unknown)
	local data = DataService.getData(player)
	if data == nil then
		Notifier.error(player, ErrorCode.DataNotLoaded)
		return
	end
	if not TableUtil.isStrictArray(loadout, Constants.MAX_LOADOUT) then
		Notifier.error(player, ErrorCode.InvalidLoadout)
		return
	end

	local requested = loadout :: { unknown }
	if #requested == 0 then
		Notifier.error(player, ErrorCode.InvalidLoadout)
		return
	end
	local clean: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, entry in requested do
		if type(entry) ~= "string" then
			Notifier.error(player, ErrorCode.InvalidLoadout)
			return
		end
		local robotId = entry :: string
		local robot = RobotConfig.Robots[robotId]
		if seen[robotId] or robot == nil or robot.locked or not table.find(data.unlockedRobots, robotId) then
			Notifier.error(player, ErrorCode.InvalidLoadout)
			return
		end
		seen[robotId] = true
		table.insert(clean, robotId)
	end

	DataService.update(player, function(profile)
		profile.equippedLoadout = clean
	end)
end

local function onUnlockRobot(player: Player, robotIdRaw: unknown)
	if type(robotIdRaw) ~= "string" then
		Notifier.error(player, ErrorCode.InvalidRobot)
		return
	end
	local robotId = robotIdRaw :: string
	local robot = RobotConfig.Robots[robotId]
	if robot == nil then
		Notifier.error(player, ErrorCode.InvalidRobot)
		return
	end
	if robot.locked then
		Notifier.error(player, ErrorCode.RobotLocked)
		return
	end
	local data = DataService.getData(player)
	if data == nil then
		Notifier.error(player, ErrorCode.DataNotLoaded)
		return
	end
	if table.find(data.unlockedRobots, robotId) then
		Notifier.error(player, ErrorCode.AlreadyUnlocked)
		return
	end
	if data.coins < robot.unlockCost then
		Notifier.error(player, ErrorCode.NotEnoughCoins)
		return
	end

	DataService.update(player, function(profile)
		profile.coins -= robot.unlockCost
		table.insert(profile.unlockedRobots, robotId)
		-- Fill a free loadout slot so a new unlock is usable straight away.
		if #profile.equippedLoadout < Constants.MAX_LOADOUT then
			table.insert(profile.equippedLoadout, robotId)
		end
	end)
	Notifier.success(player, "ROBOT_UNLOCKED")
end

local function onPlayerAdded(player: Player)
	-- Explicit respawn point so templates with their own SpawnLocation never pull players away.
	player.RespawnLocation = lobby.spawn
end

function LobbyService.init()
	lobby = LobbyBuilder.build(workspace)
end

function LobbyService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		-- Players who spawned before the lobby existed are moved onto it.
		if player.Character ~= nil then
			LobbyService.returnToLobby(player)
		end
	end
	Remotes.RequestSetLoadout:connect(onSetLoadout)
	Remotes.RequestUnlockRobot:connect(onUnlockRobot)
end

return LobbyService

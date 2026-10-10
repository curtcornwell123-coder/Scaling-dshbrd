--!strict
--[[
	LobbyService
	Owns the hub: builds the lobby (LobbyBuilder.BuildLobby), keeps players spawning there, moves
	characters between the lobby and arenas, keeps the lobby a safe zone (no damage, no tools),
	opens Duels Hall blast doors when a match starts, and handles the loadout intent. Troop
	purchases moved to TroopShopService. Every intent is validated against saved data first.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
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
local SAFE_ZONE_FIELD = "LobbySafeZone"
local DOOR_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LobbyService = {}

-- Nil on a Test Realm server, which has no lobby.
local lobby: LobbyBuilder.Lobby? = nil
local scatter = Random.new()

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

local function randomSpawn(): SpawnLocation?
	local current = lobby
	if current == nil then
		return nil
	end
	return current.spawns[scatter:NextInteger(1, #current.spawns)]
end

local function scatterOffset(): Vector3
	return Vector3.new(
		scatter:NextNumber(-SPAWN_SCATTER, SPAWN_SCATTER),
		Constants.World.PLAYER_SPAWN_LIFT,
		scatter:NextNumber(-SPAWN_SCATTER, SPAWN_SCATTER)
	)
end

function LobbyService.returnToLobby(player: Player)
	LobbyService.setMovementLocked(player, false)
	local spawn = randomSpawn()
	if spawn ~= nil then
		LobbyService.teleport(player, spawn.CFrame + scatterOffset())
	end
end

-- Used when a Duels match could not start: back into the hall, off the pads, no penalty.
function LobbyService.returnToDuelsHall(player: Player)
	LobbyService.setMovementLocked(player, false)
	local current = lobby
	if current ~= nil then
		LobbyService.teleport(player, current.duelsReturn + scatterOffset())
	end
end

-- Slides a bay's blast door up while its match starts, then closes it again.
function LobbyService.openBlastDoor(modeId: string)
	local current = lobby
	if current == nil then
		return
	end
	for _, entry in current.doors do
		if entry.modeId == modeId then
			local door = entry.door
			local open = entry.closed * CFrame.new(0, door.Size.Y - 0.6, 0)
			TweenService:Create(door, DOOR_TWEEN, { CFrame = open }):Play()
			task.delay(Constants.Lobby.BLAST_DOOR_OPEN_TIME, function()
				if door.Parent ~= nil then
					TweenService:Create(door, DOOR_TWEEN, { CFrame = entry.closed }):Play()
				end
			end)
		end
	end
end

function LobbyService.isInLobby(position: Vector3): boolean
	local current = lobby
	if current == nil then
		return false
	end
	local bounds = current.bounds
	return position.X >= bounds.min.X
		and position.X <= bounds.max.X
		and position.Y >= bounds.min.Y
		and position.Y <= bounds.max.Y
		and position.Z >= bounds.min.Z
		and position.Z <= bounds.max.Z
end

-- Safe zone: an invisible ForceField blocks all damage, and tools are removed. Arenas are far
-- away from the lobby, so the field never matters there (players watch matches from a deck).
local function applySafeZone(player: Player, character: Model)
	if character:FindFirstChild(SAFE_ZONE_FIELD) == nil then
		local field = Instance.new("ForceField")
		field.Name = SAFE_ZONE_FIELD
		field.Visible = false
		field.Parent = character
	end
	local function stripTool(child: Instance)
		if child:IsA("Tool") or child:IsA("HopperBin") then
			task.defer(function()
				child:Destroy()
			end)
		end
	end
	for _, child in character:GetChildren() do
		stripTool(child)
	end
	character.ChildAdded:Connect(stripTool)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack ~= nil then
		for _, child in backpack:GetChildren() do
			stripTool(child)
		end
		backpack.ChildAdded:Connect(stripTool)
	end
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

local function onPlayerAdded(player: Player)
	-- Explicit respawn point (one of the hub spawns) so map templates with their own
	-- SpawnLocation never pull players away.
	player.RespawnLocation = randomSpawn()
	player.CharacterAdded:Connect(function(character: Model)
		applySafeZone(player, character)
	end)
	if player.Character ~= nil then
		applySafeZone(player, player.Character)
	end
end

function LobbyService.init()
	lobby = LobbyBuilder.BuildLobby(workspace)
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
end

return LobbyService

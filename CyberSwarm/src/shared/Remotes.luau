--!strict
--[[
	Remotes
	Every RemoteEvent in the game is declared here, once, with a typed wrapper.

	Client -> server remotes are "intents": the client asks, the server decides. Their server-side
	handlers receive `...unknown` so every argument must be type-checked before use, and each remote
	has its own per-player token-bucket rate limiter applied before any handler runs.

	Server -> client remotes carry one typed payload table.

	Call Remotes.init() once from each Bootstrap before using any wrapper: the server creates the
	instances, the client waits for them to replicate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)
local Signal = require(script.Parent.Util.Signal)
local RateLimiter = require(script.Parent.Util.RateLimiter)

export type IntentHandler = (player: Player, ...unknown) -> ()

export type ClientIntent<A...> = {
	name: string,
	-- Client only.
	fire: (self: ClientIntent<A...>, A...) -> (),
	-- Server only. Handlers run after the rate limiter accepts the request.
	connect: (self: ClientIntent<A...>, handler: IntentHandler) -> Signal.Connection,
}

export type ServerEvent<T> = {
	name: string,
	-- Server only.
	fireClient: (self: ServerEvent<T>, player: Player, payload: T) -> (),
	fireClients: (self: ServerEvent<T>, players: { Player }, payload: T) -> (),
	fireAll: (self: ServerEvent<T>, payload: T) -> (),
	-- Client only.
	connect: (self: ServerEvent<T>, handler: (payload: T) -> ()) -> RBXScriptConnection,
}

type IntentRecord = {
	name: string,
	limiter: RateLimiter.RateLimiter,
	signal: Signal.Signal<(Player, ...unknown)>,
}

type ServerEventRecord = {
	name: string,
	unreliable: boolean,
}

local IS_SERVER = RunService:IsServer()
local CLIENT_WAIT_TIMEOUT = 30

local intentRecords: { IntentRecord } = {}
local serverEventRecords: { ServerEventRecord } = {}
local reliableEvents: { [string]: RemoteEvent } = {}
local unreliableEvents: { [string]: UnreliableRemoteEvent } = {}
local initialized = false

local function getReliable(name: string): RemoteEvent
	local remote: RemoteEvent? = reliableEvents[name]
	assert(remote ~= nil, `Remote "{name}" used before Remotes.init()`)
	return remote
end

local function getUnreliable(name: string): UnreliableRemoteEvent
	local remote: UnreliableRemoteEvent? = unreliableEvents[name]
	assert(remote ~= nil, `Remote "{name}" used before Remotes.init()`)
	return remote
end

-- capacity = burst size, refillPerSecond = sustained requests per second.
local function intent<A...>(name: string, capacity: number, refillPerSecond: number): ClientIntent<A...>
	local record: IntentRecord = {
		name = name,
		limiter = RateLimiter.new(capacity, refillPerSecond),
		signal = Signal.new(),
	}
	table.insert(intentRecords, record)

	local wrapper = {}
	wrapper.name = name

	function wrapper.fire(_self: any, ...: any)
		getReliable(name):FireServer(...)
	end

	function wrapper.connect(_self: any, handler: IntentHandler): Signal.Connection
		return record.signal:connect(handler)
	end

	return wrapper :: any
end

local function serverEvent<T>(name: string, unreliable: boolean): ServerEvent<T>
	table.insert(serverEventRecords, { name = name, unreliable = unreliable })

	local wrapper = {}
	wrapper.name = name

	function wrapper.fireClient(_self: any, player: Player, payload: T)
		if unreliable then
			getUnreliable(name):FireClient(player, payload)
		else
			getReliable(name):FireClient(player, payload)
		end
	end

	function wrapper.fireClients(_self: any, players: { Player }, payload: T)
		for _, player in players do
			if unreliable then
				getUnreliable(name):FireClient(player, payload)
			else
				getReliable(name):FireClient(player, payload)
			end
		end
	end

	function wrapper.fireAll(_self: any, payload: T)
		if unreliable then
			getUnreliable(name):FireAllClients(payload)
		else
			getReliable(name):FireAllClients(payload)
		end
	end

	function wrapper.connect(_self: any, handler: (payload: T) -> ()): RBXScriptConnection
		if unreliable then
			return getUnreliable(name).OnClientEvent:Connect(handler)
		end
		return getReliable(name).OnClientEvent:Connect(handler)
	end

	return wrapper :: any
end

local Remotes = {}

-- Client -> server intents.
Remotes.RequestSync = intent("RequestSync", 3, 0.5) :: ClientIntent<()>
Remotes.RequestJoinQueue = intent("RequestJoinQueue", 4, 1) :: ClientIntent<string>
Remotes.RequestLeaveQueue = intent("RequestLeaveQueue", 4, 1) :: ClientIntent<()>
Remotes.RequestSpawnRobot = intent("RequestSpawnRobot", 15, 10) :: ClientIntent<string, number>
Remotes.RequestUpgradeRobot = intent("RequestUpgradeRobot", 5, 3) :: ClientIntent<string>
Remotes.RequestSetLoadout = intent("RequestSetLoadout", 5, 2) :: ClientIntent<{ string }>
Remotes.RequestUnlockRobot = intent("RequestUnlockRobot", 3, 1) :: ClientIntent<string>

-- Server -> client events.
Remotes.ProfileUpdated = serverEvent("ProfileUpdated", false) :: ServerEvent<Types.PlayerData>
Remotes.QueueUpdated = serverEvent("QueueUpdated", false) :: ServerEvent<Types.QueueSnapshot>
Remotes.MatchUpdated = serverEvent("MatchUpdated", false) :: ServerEvent<Types.MatchSnapshot>
Remotes.MatchClosed = serverEvent("MatchClosed", false) :: ServerEvent<boolean>
Remotes.Notify = serverEvent("Notify", false) :: ServerEvent<Types.NoticePayload>
-- Cosmetic only; losing a packet just skips one tracer, so the cheaper unreliable channel fits.
Remotes.Effect = serverEvent("Effect", true) :: ServerEvent<Types.EffectPayload>

local function initServer()
	local folder = Instance.new("Folder")
	folder.Name = Constants.REMOTES_FOLDER

	for _, record in intentRecords do
		local remote = Instance.new("RemoteEvent")
		remote.Name = record.name
		remote.Parent = folder
		reliableEvents[record.name] = remote

		remote.OnServerEvent:Connect(function(player: Player, ...: unknown)
			if not record.limiter:consume(player, os.clock()) then
				return
			end
			record.signal:fire(player, ...)
		end)
	end

	for _, record in serverEventRecords do
		if record.unreliable then
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = record.name
			remote.Parent = folder
			unreliableEvents[record.name] = remote
		else
			local remote = Instance.new("RemoteEvent")
			remote.Name = record.name
			remote.Parent = folder
			reliableEvents[record.name] = remote
		end
	end

	-- Parent last so clients never see a half-built folder.
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, record in intentRecords do
			record.limiter:forget(player)
		end
	end)
end

local function initClient()
	local folder = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER, CLIENT_WAIT_TIMEOUT)
	if folder == nil then
		error(`[Remotes] {Constants.REMOTES_FOLDER} did not replicate within {CLIENT_WAIT_TIMEOUT}s`)
	end
	local function await(name: string): Instance
		local remote = folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
		if remote == nil then
			error(`[Remotes] Remote "{name}" did not replicate`)
		end
		return remote
	end

	for _, record in intentRecords do
		reliableEvents[record.name] = await(record.name) :: RemoteEvent
	end
	for _, record in serverEventRecords do
		local remote = await(record.name)
		if record.unreliable then
			unreliableEvents[record.name] = remote :: UnreliableRemoteEvent
		else
			reliableEvents[record.name] = remote :: RemoteEvent
		end
	end
end

function Remotes.init()
	if initialized then
		return
	end
	initialized = true
	if IS_SERVER then
		initServer()
	else
		initClient()
	end
end

return Remotes

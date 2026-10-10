-- Merge A Egg: server entry point.
-- Creates remotes, wires every module together, runs the player lifecycle
-- and the admin commands (kick, ban, unban, money, egg, night, boss).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Models = require(Shared:WaitForChild("Models"))

local Data = require(script.Parent:WaitForChild("Data"))
local World = require(script.Parent:WaitForChild("World"))
local Economy = require(script.Parent:WaitForChild("Economy"))
local Eggs = require(script.Parent:WaitForChild("Eggs"))
local Guardians = require(script.Parent:WaitForChild("Guardians"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Boss = require(script.Parent:WaitForChild("Boss"))

---------------------------------------------------------------------------
-- Networking
---------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local Request = remote("Request")
local SyncRemote = remote("Sync")
local NotifyRemote = remote("Notify")
local AnnounceRemote = remote("Announce")
local FxRemote = remote("Fx")
remotes.Parent = ReplicatedStorage

local handlers: { [string]: (Player, ...any) -> () } = {}
local requestBudget: { [Player]: { count: number, window: number } } = {}
local REQUESTS_PER_SECOND = 25

local Net = {}

function Net.on(action: string, handler: (Player, ...any) -> ())
	handlers[action] = handler
end

function Net.sync(player: Player, patch)
	SyncRemote:FireClient(player, patch)
end

-- kind: "success" | "error" | "info"
function Net.notify(player: Player, text: string, kind: string?)
	NotifyRemote:FireClient(player, text, kind or "info")
end

function Net.announce(text: string, color: Color3?)
	AnnounceRemote:FireAllClients(text, color or Color3.new(1, 1, 1))
end

function Net.fx(player: Player, name: string, ...)
	FxRemote:FireClient(player, name, ...)
end

function Net.fxAll(name: string, ...)
	FxRemote:FireAllClients(name, ...)
end

Request.OnServerEvent:Connect(function(player: Player, action, ...)
	if type(action) ~= "string" then
		return
	end
	local budget = requestBudget[player]
	local now = os.clock()
	if not budget or now - budget.window >= 1 then
		budget = { count = 0, window = now }
		requestBudget[player] = budget
	end
	budget.count += 1
	if budget.count > REQUESTS_PER_SECOND then
		return
	end
	local handler = handlers[action]
	if handler and Data.get(player) then
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Main] Request "{action}" from {player.Name} failed: {err}`)
		end
	end
end)

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local ctx = {
	Config = Config,
	Models = Models,
	Net = Net,
	Data = Data,
	World = World,
	Economy = Economy,
	Eggs = Eggs,
	Guardians = Guardians,
	Combat = Combat,
	Boss = Boss,
}

for _, module in { Data, World, Economy, Eggs, Guardians, Combat, Boss } do
	module.init(ctx)
end

World.build()
Combat.start()
World.start()
Eggs.start()
Guardians.start()
Economy.start()
Boss.start()
Data.startAutosave()

---------------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------------

local function isAdmin(player: Player): boolean
	if table.find(Config.AdminUserIds, player.UserId) then
		return true
	end
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if not ok or type(groups) ~= "table" then
		return false
	end
	for _, group in groups do
		if group.Id == Config.GroupId then
			return group.Rank >= Config.AdminGroupRank
		end
	end
	return false
end

local function findPlayer(query: string): Player?
	query = query:lower()
	for _, player in Players:GetPlayers() do
		if player.Name:lower() == query or player.DisplayName:lower() == query then
			return player
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Name:lower():sub(1, #query) == query or player.DisplayName:lower():sub(1, #query) == query then
			return player
		end
	end
	return nil
end

-- Accepts an exact online name, an offline username, or a numeric user id.
-- No prefix matching here: a ban must never land on the wrong person.
local function resolveUserId(query: string): (number?, string)
	for _, online in Players:GetPlayers() do
		if online.Name:lower() == query:lower() then
			return online.UserId, online.Name
		end
	end
	local numeric = tonumber(query)
	if numeric then
		return numeric, query
	end
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(query)
	end)
	if ok and userId then
		return userId, query
	end
	return nil, query
end

-- "30s", "30m", "12h", "7d", "perm" -> seconds (-1 = permanent).
local function parseDuration(text: string?): number?
	if not text then
		return nil
	end
	text = text:lower()
	if text == "perm" or text == "permanent" or text == "forever" then
		return -1
	end
	local amount, unit = text:match("^(%d+)([smhd]?)$")
	if not amount then
		return nil
	end
	local multipliers = { s = 1, m = 60, h = 3600, d = 86400, [""] = 60 }
	local seconds = tonumber(amount) * multipliers[unit]
	return if seconds > 0 then seconds else nil
end

local function describeDuration(seconds: number): string
	if seconds < 0 then
		return "permanently"
	end
	return "for " .. Config.formatTime(seconds)
end

local function joinFrom(args: { string }, start: number): string
	local parts = {}
	for i = start, #args do
		table.insert(parts, args[i])
	end
	return table.concat(parts, " ")
end

local commands = {}

commands.kick = function(admin: Player, args)
	local target = args[1] and findPlayer(args[1])
	if not target then
		return "Usage: /kick <player> <reason>"
	end
	local reason = joinFrom(args, 2)
	if reason == "" then
		reason = "Kicked by an admin."
	end
	print(`[Admin] {admin.Name} kicked {target.Name}: {reason}`)
	target:Kick(reason)
	return `Kicked {target.Name}: {reason}`
end

commands.ban = function(admin: Player, args)
	if not args[1] then
		return "Usage: /ban <exact username or userId> <30m|12h|7d|perm> <reason>"
	end
	local duration = parseDuration(args[2])
	if not duration then
		return "Duration must look like 30m, 12h, 7d or perm."
	end
	local userId, name = resolveUserId(args[1])
	if not userId then
		return `Couldn't find a player called "{args[1]}".`
	end
	if userId == admin.UserId then
		return "You can't ban yourself."
	end
	local reason = joinFrom(args, 3)
	if reason == "" then
		reason = "Banned by an admin."
	end
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = duration,
			DisplayReason = reason,
			PrivateReason = `Banned by {admin.Name} ({admin.UserId})`,
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		-- Ban API can fail in Studio; still remove them from this server.
		local online = Players:GetPlayerByUserId(userId)
		if online then
			online:Kick(`Banned {describeDuration(duration)}: {reason}`)
		end
		return `Ban API error ({err}). Kicked them from this server instead.`
	end
	print(`[Admin] {admin.Name} banned {name} ({userId}) {describeDuration(duration)}: {reason}`)
	return `Banned {name} {describeDuration(duration)}: {reason}`
end

commands.unban = function(admin: Player, args)
	if not args[1] then
		return "Usage: /unban <userId or username>"
	end
	local userId, name = resolveUserId(args[1])
	if not userId then
		return `Couldn't find "{args[1]}".`
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	if not ok then
		return `Unban failed: {err}`
	end
	print(`[Admin] {admin.Name} unbanned {name} ({userId})`)
	return `Unbanned {name}.`
end

commands.money = function(admin: Player, args)
	local target = args[1] and findPlayer(args[1])
	local amount = tonumber(args[2])
	if not target or not amount then
		return "Usage: /money <player> <amount>"
	end
	Economy.addMoney(target, amount)
	Economy.sync(target, "money")
	return `Gave {target.Name} ${Config.format(amount)}`
end

commands.speed = function(admin: Player, args)
	local target = args[1] and findPlayer(args[1])
	local amount = tonumber(args[2])
	if not target or not amount then
		return "Usage: /speed <player> <amount>"
	end
	Economy.addSpeed(target, amount)
	Economy.sync(target, "speed")
	return `Gave {target.Name} {Config.format(amount)} speed`
end

commands.egg = function(admin: Player, args)
	local target = args[1] and findPlayer(args[1])
	if not target then
		return "Usage: /egg <player> <biome> <rarity>"
	end
	local biomeKey
	local query = (args[2] or "Forest"):lower()
	for _, biome in Config.Biomes do
		if biome.key:lower():sub(1, #query) == query or biome.name:lower():sub(1, #query) == query then
			biomeKey = biome.key
			break
		end
	end
	local rarity = tonumber(args[3])
	if not rarity and args[3] then
		for i, r in Config.Rarities do
			if r.name:lower():sub(1, #args[3]) == args[3]:lower() then
				rarity = i
				break
			end
		end
	end
	rarity = math.clamp(rarity or 1, 1, #Config.Rarities)
	if not biomeKey then
		return `Unknown biome "{args[2]}".`
	end
	local data = Data.get(target)
	if not data then
		return "That player hasn't loaded yet."
	end
	local egg = Eggs.makeEgg(data, biomeKey, rarity, {})
	Eggs.addEgg(target, egg)
	return `Gave {target.Name} a {Eggs.title(egg)}`
end

commands.night = function()
	World.forceNight()
	return "Night started."
end

commands.boss = function()
	if Boss.isActive() then
		return "The boss is already out."
	end
	Boss.spawn()
	return "Boss spawned."
end

-- Switches your own pen to any treadmill design (Corny's Top Hat stays owner-only).
commands.treadmill = function(admin: Player, args)
	if not args[1] then
		return "Usage: /treadmill <name>, e.g. /treadmill CornyTopHat"
	end
	return Economy.adminSetTreadmill(admin, args[1])
end

commands.adminhelp = function()
	return "Commands: /kick, /ban, /unban, /money, /speed, /egg, /night, /boss, /treadmill"
end

local function execute(admin: Player, name: string, args: { string })
	local command = commands[name]
	if not command then
		return
	end
	local ok, result = pcall(command, admin, args)
	Net.notify(admin, if ok then tostring(result) else `Command error: {result}`, if ok then "info" else "error")
end

local function runCommand(admin: Player, message: string)
	local args = string.split(message, " ")
	local name = table.remove(args, 1)
	if not name then
		return
	end
	name = name:lower():gsub("^[/;:]", "")
	local cleaned = {}
	for _, a in args do
		if a ~= "" then
			table.insert(cleaned, a)
		end
	end
	execute(admin, name, cleaned)
end

-- The admin panel sends the same commands with arguments already split.
Net.on("Admin", function(player: Player, name, args)
	if not player:GetAttribute("Admin") or type(name) ~= "string" or type(args) ~= "table" then
		return
	end
	local cleaned = {}
	for _, a in args do
		if type(a) == "string" or type(a) == "number" then
			local text = tostring(a)
			if text ~= "" then
				table.insert(cleaned, text)
			end
		end
	end
	execute(player, name:lower(), cleaned)
end)

-- "/command" through TextChatService commands (hidden from public chat).
local commandFolder = Instance.new("Folder")
commandFolder.Name = "AdminCommands"
commandFolder.Parent = TextChatService
for name in commands do
	local command = Instance.new("TextChatCommand")
	command.Name = "Admin_" .. name
	command.PrimaryAlias = "/" .. name
	command.Parent = commandFolder
	command.Triggered:Connect(function(source: TextSource, message: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and player:GetAttribute("Admin") then
			runCommand(player, message)
		end
	end)
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if isAdmin(player) then
		player:SetAttribute("Admin", true)
	end
	-- ";command" fallback for admins in any chat setup.
	player.Chatted:Connect(function(message)
		if player:GetAttribute("Admin") and message:sub(1, 1) == ";" then
			runCommand(player, message)
		end
	end)

	local data = Data.load(player)
	if not data or not player.Parent then
		return
	end
	local pen = World.assignPen(player)
	if not pen then
		player:Kick("This server is full! Please join another one.")
		return
	end
	Economy.playerAdded(player, data, pen)
	Eggs.playerAdded(player)
end

local function onPlayerRemoving(player: Player)
	requestBudget[player] = nil
	if Data.get(player) then
		Eggs.playerRemoving(player)
		Economy.playerRemoving(player)
	end
	World.releasePen(player)
	Data.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

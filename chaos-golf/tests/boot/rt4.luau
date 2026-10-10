-- ===== part 4: environment, modules, players, loop =====
local env = {}
local mos = table.clone(os)
mos.time = function(t)
	if t then
		return os.time(t)
	end
	return Sim.EPOCH + math.floor(Sim.now)
end
mos.clock = function()
	return Sim.now
end
mos.date = function(fmt, t)
	return os.date(fmt, t or (Sim.EPOCH + math.floor(Sim.now)))
end
local function argsToString(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end
for k, v in {
	print = function(...)
		table.insert(Sim.prints, { side = currentSide(), msg = argsToString(...), t = Sim.now })
	end,
	warn = function(...)
		table.insert(Sim.warnings, { side = currentSide(), msg = argsToString(...), t = Sim.now, trace = shortTrace(debug.traceback("", 2)) })
	end,
	error = error, assert = assert, pcall = pcall, xpcall = xpcall, select = select, tostring = tostring, tonumber = tonumber,
	type = Sim.type, typeof = Sim.typeof, ipairs = ipairs, pairs = pairs, next = next, rawget = rawget, rawset = rawset,
	rawequal = rawequal, rawlen = rawlen, setmetatable = setmetatable, getmetatable = getmetatable, unpack = table.unpack,
	string = string, table = table, math = math, os = mos, coroutine = coroutine, bit32 = bit32, utf8 = utf8, debug = debug,
	buffer = buffer, task = Sim.task, gcinfo = gcinfo,
	wait = function(t)
		local e = Sim.task.wait(math.max(t or 0.03, 0.03))
		return e, Sim.now
	end,
	delay = function(t, f)
		Sim.task.delay(t, f)
	end,
	spawn = function(f)
		Sim.task.defer(f)
	end,
	tick = function()
		return Sim.EPOCH + Sim.now
	end,
	time = function()
		return Sim.now
	end,
	elapsedTime = function()
		return Sim.now
	end,
	game = Sim.game, Game = Sim.game, workspace = Sim.workspace, Workspace = Sim.workspace,
	Instance = Sim.Instance, Enum = Sim.Enum, shared = {}, _G = {},
} do
	env[k] = v
end
for k, v in Sim.types do
	env[k] = v
end
Sim.env = env

-- Modules ------------------------------------------------------------------------------------
Sim.sources = Sim.sources or {}
Sim.scriptPath = {}
local moduleCache = { server = {}, client = {} }
local loading = { server = {}, client = {} }
Sim.moduleCache = moduleCache
local function requireModule(ms)
	if not Sim.isInstance(ms) or D[ms].cls ~= "ModuleScript" then
		Sim.misuse("Attempted to call require with invalid argument(s).")
	end
	local side = currentSide()
	local cache = moduleCache[side]
	if cache[ms] ~= nil then
		return cache[ms]
	end
	if loading[side][ms] then
		Sim.misuse("Requested module was required recursively: " .. Sim.scriptPath[ms])
	end
	loading[side][ms] = true
	local path = Sim.scriptPath[ms]
	local fn, err = loadstring(Sim.sources[path], "=" .. path)
	if not fn then
		error("SYNTAX " .. tostring(err), 2)
	end
	setfenv(fn, setmetatable({ script = ms }, { __index = env }))
	local results = table.pack(fn())
	loading[side][ms] = nil
	if results.n ~= 1 then
		Sim.misuse("Module code did not return exactly one value: " .. path)
	end
	cache[ms] = results[1]
	return results[1]
end
env.require = requireModule

local function folderAt(parent, name, cls)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Sim.newInstance(cls or "Folder")
		D[f].props.Name = name
		Sim.setParent(f, D[f], parent)
	end
	return f
end
Sim.folderAt = folderAt
function Sim.addScript(parent, name, cls, path)
	local s = Sim.newInstance(cls)
	D[s].props.Name = name
	Sim.setParent(s, D[s], parent)
	Sim.scriptPath[s] = path
	return s
end
function Sim.runScript(s, side)
	local path = Sim.scriptPath[s]
	local fn, err = loadstring(Sim.sources[path], "=" .. path)
	if not fn then
		Sim.report("syntax", err, "")
		return
	end
	setfenv(fn, setmetatable({ script = s }, { __index = env }))
	local co = Sim.newThread(fn, side)
	Sim.resume(co)
end
function Sim.module(side, name)
	for ms, mod in moduleCache[side] do
		if D[ms].props.Name == name then
			return mod
		end
	end
	return nil
end

-- Players / characters -----------------------------------------------------------------------
function Sim.addPlayer(userId, name)
	local p = Sim.newInstance("Player")
	local d = D[p]
	d.props.Name = name
	d.props.DisplayName = name
	d.props.UserId = userId
	for _, c in { "PlayerGui", "Backpack", "PlayerScripts" } do
		local x = Sim.newInstance(c)
		D[x].props.Name = c
		Sim.setParent(x, D[x], p)
	end
	Sim.setParent(p, d, Sim.Players)
	table.insert(Sim.players, p)
	local co = Sim.newThread(function()
		fireIf(D[Sim.Players], "PlayerAdded", p)
	end, "server")
	Sim.resume(co)
	return p
end
function Sim.spawnCharacter(p)
	local d = D[p]
	if d.props.Character then
		Sim.destroy(d.props.Character)
	end
	local spawnPos = Vector3.new(0, 3, -25)
	for _, x in Sim.descendants(Sim.workspace) do
		if D[x].cls == "SpawnLocation" then
			spawnPos = x.Position + Vector3.new(0, 3, 0)
			break
		end
	end
	local m = Sim.newInstance("Model")
	D[m].props.Name = d.props.Name
	local hrp = Sim.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.CFrame = Sim.types.CFrame.new(spawnPos)
	hrp.Transparency = 1
	hrp.Parent = m
	local head = Sim.Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.CFrame = Sim.types.CFrame.new(spawnPos + Vector3.new(0, 1.5, 0))
	head.Parent = m
	local hum = Sim.Instance.new("Humanoid")
	hum.Parent = m
	m.PrimaryPart = hrp
	d.props.Character = m
	Sim.setParent(m, D[m], Sim.workspace)
	local co = Sim.newThread(function()
		fireIf(d, "CharacterAdded", m)
	end, "server")
	Sim.resume(co)
	return m
end
function Sim.removePlayer(p)
	local d = D[p]
	if d.parent ~= Sim.Players then
		return
	end
	local co = Sim.newThread(function()
		fireIf(D[Sim.Players], "PlayerRemoving", p)
	end, "server")
	Sim.resume(co)
	if d.props.Character then
		Sim.destroy(d.props.Character)
	end
	Sim.setParent(p, d, nil)
end
function Sim.setRoot(p, pos)
	local ch = D[p].props.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = Sim.types.CFrame.new(pos)
	end
end

-- Frame loop ----------------------------------------------------------------------------------
function Sim.step(dt)
	Sim.now += dt
	local rsd = D[Sim.RunService]
	if Sim.clientStarted then
		fireIf(rsd, "RenderStepped", dt)
		for _, fn in Sim.renderBound do
			Sim.resume(Sim.newThread(fn, "client"), dt)
		end
	end
	fireIf(rsd, "Stepped", Sim.now, dt)
	Sim.physicsStep(dt)
	fireIf(rsd, "Heartbeat", dt)
	Sim.wakeSleepers()
	Sim.runDeferred()
end
function Sim.run(seconds, until_)
	local n = math.floor(seconds * 60 + 0.5)
	for _ = 1, n do
		Sim.step(1 / 60)
		if until_ and until_() then
			return true
		end
	end
	return false
end
function Sim.asSide(side, fn, ...)
	Sim.resume(Sim.newThread(fn, side), ...)
end
function Sim.fireServerAs(player, name, ...)
	local folder = Sim.game:GetService("ReplicatedStorage"):FindFirstChild("ChaosGolfRemotes")
	local remote = folder and folder:FindFirstChild(name)
	if not remote then
		Sim.report("harness", "no remote " .. name, "")
		return
	end
	local d = D[remote]
	local args = Sim.copyArgs(name, ...)
	table.insert(Sim.remoteLog, { dir = "C->S", name = name, t = Sim.now, player = player, args = args })
	local packed = table.pack(player, table.unpack(args, 1, args.n))
	Sim.asSide("server", function()
		Sim.getSignal(remote, d, "OnServerEvent"):_fire(table.unpack(packed, 1, packed.n))
	end)
end
function Sim.fireEvent(inst, name, ...)
	local args = table.pack(...)
	Sim.asSide("server", function()
		Sim.getSignal(inst, D[inst], name):_fire(table.unpack(args, 1, args.n))
	end)
end
function Sim.clientEvents(name, player)
	local out = {}
	for _, e in Sim.remoteLog do
		if e.dir == "S->C" and e.name == name and (player == nil or e.player == player) then
			table.insert(out, e)
		end
	end
	return out
end

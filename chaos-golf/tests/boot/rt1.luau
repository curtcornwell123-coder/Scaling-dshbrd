-- ===== Headless Roblox runtime mock (part 1: core, scheduler, signals, datatypes) =====
local Sim = {}
Sim.now = 0
Sim.EPOCH = 1791633600
Sim.errors = {} -- { kind, side, msg, trace }
Sim.warnings = {}
Sim.prints = {}
Sim.remoteLog = {}
Sim.apiMisuse = {}
Sim.defaultSide = "server"
Sim.verbose = false

local rawtype = type
local rawtypeof = typeof
local threadSide = setmetatable({}, { __mode = "k" })
Sim.threadSide = threadSide

local function currentSide(): string
	local co = coroutine.running()
	return (co and threadSide[co]) or Sim.defaultSide
end
Sim.currentSide = currentSide

local function shortTrace(tb)
	tb = tb or ""
	local out = {}
	for line in string.gmatch(tb, "[^\n]+") do
		if not string.find(line, "boot_", 1, true) then
			table.insert(out, line)
		end
		if #out >= 8 then
			break
		end
	end
	return table.concat(out, " | ")
end

function Sim.report(kind, msg, trace)
	table.insert(Sim.errors, { kind = kind, side = currentSide(), msg = tostring(msg), trace = shortTrace(trace), t = Sim.now })
	if Sim.verbose then
		print(string.format("[%7.2f][%s] %s: %s\n    %s", Sim.now, currentSide(), kind, tostring(msg), shortTrace(trace)))
	end
end

-- API misuse is logged even when the game code pcalls it.
function Sim.misuse(msg)
	table.insert(Sim.apiMisuse, { side = currentSide(), msg = msg, trace = shortTrace(debug.traceback("", 3)), t = Sim.now })
	error(msg, 3)
end

-- Scheduler ------------------------------------------------------------------
local sleeping = {} -- { co, wake, seq }
local deferred = {} -- { co, args }
local seq = 0
local cancelled = setmetatable({}, { __mode = "k" })

local function resume(co, ...)
	if cancelled[co] or coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		Sim.report("error", err, debug.traceback(co))
	end
end
Sim.resume = resume

local function newThread(fn, side)
	local co = coroutine.create(fn)
	threadSide[co] = side or currentSide()
	return co
end
Sim.newThread = newThread

local function schedule(co, wake, args)
	seq += 1
	table.insert(sleeping, { co = co, wake = wake, seq = seq, args = args })
end

local task = {}
function task.spawn(f, ...)
	local co = if rawtype(f) == "thread" then f else newThread(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = if rawtype(f) == "thread" then f else newThread(f)
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(t, f, ...)
	local co = if rawtype(f) == "thread" then f else newThread(f)
	schedule(co, Sim.now + math.max(t or 0, 0), table.pack(...))
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local start = Sim.now
	schedule(co, Sim.now + math.max(t or 0, 0), nil)
	coroutine.yield()
	return Sim.now - start
end
function task.cancel(co)
	cancelled[co] = true
end
function task.synchronize() end
function task.desynchronize() end
Sim.task = task

function Sim.runDeferred()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		if guard > 10000 then
			Sim.report("error", "deferred loop overflow", "")
			break
		end
		local list = deferred
		deferred = {}
		for _, d in list do
			resume(d.co, table.unpack(d.args, 1, d.args.n))
		end
	end
end

function Sim.wakeSleepers()
	local due = {}
	local keep = {}
	for _, s in sleeping do
		if s.wake <= Sim.now + 1e-9 then
			table.insert(due, s)
		else
			table.insert(keep, s)
		end
	end
	sleeping = keep
	table.sort(due, function(a, b)
		if a.wake ~= b.wake then
			return a.wake < b.wake
		end
		return a.seq < b.seq
	end)
	for _, s in due do
		if s.args then
			resume(s.co, table.unpack(s.args, 1, s.args.n))
		else
			resume(s.co)
		end
	end
end

-- Signals --------------------------------------------------------------------
local SignalMT = {}
SignalMT.__index = SignalMT
SignalMT.__type = "RBXScriptSignal"
local ConnMT = {}
ConnMT.__index = ConnMT
ConnMT.__type = "RBXScriptConnection"

local function newSignal(name)
	return setmetatable({ _conns = {}, _waiting = {}, _name = name or "Signal", _onConnect = nil }, SignalMT)
end
Sim.newSignal = newSignal

function ConnMT:Disconnect()
	self.Connected = false
end

function SignalMT:Connect(fn)
	if rawtype(fn) ~= "function" then
		Sim.misuse("Attempt to connect failed: Passed value is not a function")
	end
	local c = setmetatable({ fn = fn, side = currentSide(), Connected = true }, ConnMT)
	table.insert(self._conns, c)
	if self._onConnect then
		self._onConnect(self, c)
	end
	return c
end
function SignalMT:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Connected = false
		fn(...)
	end)
	return c
end
SignalMT.connect = SignalMT.Connect
function SignalMT:Wait()
	local co = coroutine.running()
	table.insert(self._waiting, co)
	return coroutine.yield()
end
function SignalMT:ConnectParallel(fn)
	return self:Connect(fn)
end
-- internal fire
function SignalMT:_fire(...)
	local conns = self._conns
	local alive = {}
	for _, c in conns do
		if c.Connected then
			table.insert(alive, c)
		end
	end
	self._conns = alive
	local mode = Sim.signalMode or "forward"
	local order = alive
	if mode == "reverse" then
		order = {}
		for i = #alive, 1, -1 do
			table.insert(order, alive[i])
		end
	end
	for _, c in order do
		if c.Connected then
			local co = newThread(c.fn, c.side)
			if mode == "deferred" then
				table.insert(deferred, { co = co, args = table.pack(...) })
			else
				resume(co, ...)
			end
		end
	end
	if #self._waiting > 0 then
		local w = self._waiting
		self._waiting = {}
		for _, co in w do
			if mode == "deferred" then
				table.insert(deferred, { co = co, args = table.pack(...) })
			else
				resume(co, ...)
			end
		end
	end
end
function SignalMT:_disconnectAll()
	for _, c in self._conns do
		c.Connected = false
	end
	self._conns = {}
end
function SignalMT:_count()
	local n = 0
	for _, c in self._conns do
		if c.Connected then
			n += 1
		end
	end
	return n
end

-- Datatypes ------------------------------------------------------------------
local freeze = table.freeze

local V3 = { __type = "Vector3" }
local function v3(x, y, z)
	return freeze(setmetatable({ X = x, Y = y, Z = z }, V3))
end
local function isV3(v)
	return rawtype(v) == "table" and getmetatable(v) == V3
end
V3.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(t.X / m, t.Y / m, t.Z / m)
	elseif k == "x" then
		return t.X
	elseif k == "y" then
		return t.Y
	elseif k == "z" then
		return t.Z
	end
	local f = rawget(V3, k)
	if f == nil or k:sub(1, 2) == "__" then
		error(tostring(k) .. " is not a valid member of Vector3", 2)
	end
	return f
end
V3.__add = function(a, b)
	if not isV3(a) or not isV3(b) then
		error("invalid argument to Vector3 + (" .. rawtypeof(a) .. ", " .. rawtypeof(b) .. ")", 2)
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	if not isV3(a) or not isV3(b) then
		error("invalid argument to Vector3 -", 2)
	end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__mul = function(a, b)
	if rawtype(a) == "number" and isV3(b) then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif isV3(a) and rawtype(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	error("invalid argument to Vector3 *", 2)
end
V3.__div = function(a, b)
	if isV3(a) and rawtype(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	error("invalid argument to Vector3 /", 2)
end
V3.__idiv = function(a, b)
	if rawtype(b) == "number" then
		return v3(a.X // b, a.Y // b, a.Z // b)
	end
	return v3(a.X // b.X, a.Y // b.Y, a.Z // b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	if not isV3(b) or rawtype(t) ~= "number" then
		error("invalid argument to Vector3:Lerp", 2)
	end
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
function V3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function V3.Sign(a)
	return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function V3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3.Angle(a, b)
	local d = a:Dot(b) / (a.Magnitude * b.Magnitude)
	return math.acos(math.clamp(d, -1, 1))
end
local Vector3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}
function Vector3.FromNormalId(n)
	local m = { Right = v3(1, 0, 0), Left = v3(-1, 0, 0), Top = v3(0, 1, 0), Bottom = v3(0, -1, 0), Back = v3(0, 0, 1), Front = v3(0, 0, -1) }
	return m[n.Name]
end
Sim.v3 = v3
Sim.isV3 = isV3

local V2 = { __type = "Vector2" }
local function v2(x, y)
	return freeze(setmetatable({ X = x, Y = y }, V2))
end
V2.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y)
		return v2(t.X / m, t.Y / m)
	end
	local f = rawget(V2, k)
	if f == nil or k:sub(1, 2) == "__" then
		error(tostring(k) .. " is not a valid member of Vector2", 2)
	end
	return f
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if rawtype(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif rawtype(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	if rawtype(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
function V2.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
local Vector2 = {
	new = function(x, y)
		return v2(x or 0, y or 0)
	end,
	zero = v2(0, 0),
	one = v2(1, 1),
	xAxis = v2(1, 0),
	yAxis = v2(0, 1),
}

-- CFrame: position p + rotation columns rx, ry, rz
local CF = { __type = "CFrame" }
local function cf(p, rx, ry, rz)
	return freeze(setmetatable({ p = p, rx = rx, ry = ry, rz = rz }, CF))
end
local function isCF(v)
	return rawtype(v) == "table" and getmetatable(v) == CF
end
local function rot(c, v)
	return v3(c.rx.X * v.X + c.ry.X * v.Y + c.rz.X * v.Z, c.rx.Y * v.X + c.ry.Y * v.Y + c.rz.Y * v.Z, c.rx.Z * v.X + c.ry.Z * v.Y + c.rz.Z * v.Z)
end
local IDENT = cf(v3(0, 0, 0), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
CF.__index = function(t, k)
	if k == "Position" then
		return t.p
	elseif k == "LookVector" then
		return -t.rz
	elseif k == "RightVector" or k == "XVector" then
		return t.rx
	elseif k == "UpVector" or k == "YVector" then
		return t.ry
	elseif k == "ZVector" then
		return t.rz
	elseif k == "X" then
		return t.p.X
	elseif k == "Y" then
		return t.p.Y
	elseif k == "Z" then
		return t.p.Z
	elseif k == "Rotation" then
		return cf(v3(0, 0, 0), t.rx, t.ry, t.rz)
	end
	local f = rawget(CF, k)
	if f == nil or k:sub(1, 2) == "__" then
		error(tostring(k) .. " is not a valid member of CFrame", 2)
	end
	return f
end
CF.__mul = function(a, b)
	if not isCF(a) then
		error("invalid argument #1 to CFrame * (CFrame expected)", 2)
	end
	if isV3(b) then
		return a.p + rot(a, b)
	elseif isCF(b) then
		return cf(a.p + rot(a, b.p), rot(a, b.rx), rot(a, b.ry), rot(a, b.rz))
	end
	error("invalid argument #2 to CFrame * (CFrame or Vector3 expected, got " .. rawtypeof(b) .. ")", 2)
end
CF.__add = function(a, b)
	if not isCF(a) or not isV3(b) then
		error("invalid argument to CFrame + (CFrame + Vector3 expected)", 2)
	end
	return cf(a.p + b, a.rx, a.ry, a.rz)
end
CF.__sub = function(a, b)
	if not isCF(a) or not isV3(b) then
		error("invalid argument to CFrame - (CFrame - Vector3 expected)", 2)
	end
	return cf(a.p - b, a.rx, a.ry, a.rz)
end
CF.__eq = function(a, b)
	return a.p == b.p and a.rx == b.rx and a.ry == b.ry and a.rz == b.rz
end
CF.__tostring = function(a)
	return tostring(a.p)
end
function CF.Inverse(c)
	-- Exact 3x3 inverse (a transpose would let rounding error grow without bound
	-- under repeated PivotTo, which Roblox avoids by orthonormalizing).
	local a, b, z = c.rx, c.ry, c.rz
	local r1, r2, r3 = b:Cross(z), z:Cross(a), a:Cross(b)
	local det = a:Dot(r1)
	r1, r2, r3 = r1 / det, r2 / det, r3 / det
	local inv = cf(v3(0, 0, 0), v3(r1.X, r2.X, r3.X), v3(r1.Y, r2.Y, r3.Y), v3(r1.Z, r2.Z, r3.Z))
	return cf(-rot(inv, c.p), inv.rx, inv.ry, inv.rz)
end
function CF.ToObjectSpace(a, b)
	return CF.Inverse(a) * b
end
function CF.ToWorldSpace(a, b)
	return a * b
end
function CF.PointToWorldSpace(a, v)
	return a * v
end
function CF.PointToObjectSpace(a, v)
	return CF.Inverse(a) * v
end
function CF.VectorToWorldSpace(a, v)
	return rot(a, v)
end
function CF.VectorToObjectSpace(a, v)
	return rot(CF.Inverse(a), v)
end
function CF.Lerp(a, b, t)
	-- position lerp + nearest rotation (good enough for the mock)
	return cf(a.p:Lerp(b.p, t), if t < 0.5 then a.rx else b.rx, if t < 0.5 then a.ry else b.ry, if t < 0.5 then a.rz else b.rz)
end
function CF.GetComponents(c)
	return c.p.X, c.p.Y, c.p.Z, c.rx.X, c.ry.X, c.rz.X, c.rx.Y, c.ry.Y, c.rz.Y, c.rx.Z, c.ry.Z, c.rz.Z
end
CF.components = CF.GetComponents
function CF.ToEulerAnglesXYZ(c)
	local r02 = c.rz.X
	local y = math.asin(math.clamp(r02, -1, 1))
	local x = math.atan2(-c.rz.Y, c.rz.Z)
	local z = math.atan2(-c.ry.X, c.rx.X)
	return x, y, z
end
function CF.ToOrientation(c)
	local x = math.asin(math.clamp(-c.rz.Y, -1, 1))
	local y = math.atan2(c.rz.X, c.rz.Z)
	local z = math.atan2(c.rx.Y, c.ry.Y)
	return x, y, z
end
CF.ToEulerAnglesYXZ = CF.ToOrientation
function CF.FuzzyEq(a, b, eps)
	return a.p:FuzzyEq(b.p, eps or 1e-5)
end
local function rx(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(v3(0, 0, 0), v3(1, 0, 0), v3(0, c, s), v3(0, -s, c))
end
local function ry(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(v3(0, 0, 0), v3(c, 0, -s), v3(0, 1, 0), v3(s, 0, c))
end
local function rz(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(v3(0, 0, 0), v3(c, s, 0), v3(-s, c, 0), v3(0, 0, 1))
end
local function checkNum(n, fname, i)
	if rawtype(n) ~= "number" then
		error(string.format("invalid argument #%d to '%s' (number expected, got %s)", i, fname, rawtypeof(n)), 3)
	end
end
local CFrame = {
	identity = IDENT,
	new = function(...)
		local n = select("#", ...)
		local a, b, c = ...
		if n == 0 then
			return IDENT
		elseif n == 1 then
			if not isV3(a) then
				error("invalid argument #1 to 'new' (Vector3 expected, got " .. rawtypeof(a) .. ")", 2)
			end
			return cf(a, IDENT.rx, IDENT.ry, IDENT.rz)
		elseif n == 2 and isV3(a) and isV3(b) then
			local look = (b - a).Unit
			local right = look:Cross(v3(0, 1, 0)).Unit
			local up = right:Cross(look)
			return cf(a, right, up, -look)
		elseif n == 3 then
			checkNum(a, "new", 1)
			checkNum(b, "new", 2)
			checkNum(c, "new", 3)
			return cf(v3(a, b, c), IDENT.rx, IDENT.ry, IDENT.rz)
		elseif n == 7 then
			local x, y, z, qx, qy, qz, qw = ...
			local m = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
			qx, qy, qz, qw = qx / m, qy / m, qz / m, qw / m
			return cf(
				v3(x, y, z),
				v3(1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qz * qw), 2 * (qx * qz - qy * qw)),
				v3(2 * (qx * qy - qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz + qx * qw)),
				v3(2 * (qx * qz + qy * qw), 2 * (qy * qz - qx * qw), 1 - 2 * (qx * qx + qy * qy))
			)
		elseif n == 12 then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = ...
			return cf(v3(x, y, z), v3(r00, r10, r20), v3(r01, r11, r21), v3(r02, r12, r22))
		end
		error("invalid arguments to CFrame.new (" .. n .. " args)", 2)
	end,
	lookAt = function(at, target, up)
		if not isV3(at) or not isV3(target) then
			error("invalid argument to CFrame.lookAt (Vector3 expected)", 2)
		end
		up = up or v3(0, 1, 0)
		local d = target - at
		if d.Magnitude < 1e-9 then
			return cf(at, IDENT.rx, IDENT.ry, IDENT.rz)
		end
		local look = d.Unit
		local right = look:Cross(up)
		if right.Magnitude < 1e-6 then
			right = v3(1, 0, 0)
		end
		right = right.Unit
		local up2 = right:Cross(look).Unit
		return cf(at, right, up2, -look)
	end,
	Angles = function(ax, ay, az)
		checkNum(ax, "Angles", 1)
		checkNum(ay, "Angles", 2)
		checkNum(az, "Angles", 3)
		return rx(ax) * ry(ay) * rz(az)
	end,
	fromOrientation = function(ax, ay, az)
		return ry(ay) * rx(ax) * rz(az)
	end,
	fromAxisAngle = function(axis, angle)
		local u = axis.Unit
		local c, s = math.cos(angle), math.sin(angle)
		local t = 1 - c
		local x, y, z = u.X, u.Y, u.Z
		return cf(v3(0, 0, 0), v3(t * x * x + c, t * x * y + s * z, t * x * z - s * y), v3(t * x * y - s * z, t * y * y + c, t * y * z + s * x), v3(t * x * z + s * y, t * y * z - s * x, t * z * z + c))
	end,
	fromMatrix = function(p, x, y, z)
		if not isV3(p) or not isV3(x) or not isV3(y) then
			error("invalid argument to CFrame.fromMatrix", 2)
		end
		z = z or x:Cross(y).Unit
		return cf(p, x, y, z)
	end,
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromEulerAnglesYXZ = CFrame.fromOrientation
CFrame.lookAlong = function(at, dir, up)
	return CFrame.lookAt(at, at + dir, up)
end
Sim.cf = cf
Sim.isCF = isCF

local C3 = { __type = "Color3" }
local function c3(r, g, b)
	return freeze(setmetatable({ R = r, G = g, B = b }, C3))
end
C3.__index = function(t, k)
	local f = rawget(C3, k)
	if f == nil or k:sub(1, 2) == "__" then
		error(tostring(k) .. " is not a valid member of Color3", 2)
	end
	return f
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3.__tostring = function(a)
	return string.format("%g, %g, %g", a.R, a.G, a.B)
end
function C3.Lerp(a, b, t)
	if getmetatable(b) ~= C3 then
		error("invalid argument #1 to 'Lerp' (Color3 expected)", 2)
	end
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHex(a)
	return string.format("%02X%02X%02X", math.floor(a.R * 255 + 0.5), math.floor(a.G * 255 + 0.5), math.floor(a.B * 255 + 0.5))
end
function C3.ToHSV(a)
	local r, g, b = a.R, a.G, a.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, mx
	local d = mx - mn
	s = if mx == 0 then 0 else d / mx
	if d ~= 0 then
		if mx == r then
			h = (g - b) / d % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, s, v
end
local Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHex = function(h)
		if rawtype(h) ~= "string" then
			error("invalid argument #1 to 'fromHex' (string expected)", 2)
		end
		h = h:gsub("#", "")
		if #h ~= 6 and #h ~= 3 then
			error("Unable to convert characters to hex value", 2)
		end
		if #h == 3 then
			h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2)
		end
		return c3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
	end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		i = i % 6
		if i == 0 then
			return c3(v, t, p)
		elseif i == 1 then
			return c3(q, v, p)
		elseif i == 2 then
			return c3(p, v, t)
		elseif i == 3 then
			return c3(p, q, v)
		elseif i == 4 then
			return c3(t, p, v)
		end
		return c3(v, p, q)
	end,
}

local function simpleType(typeName, fields, validate)
	local mt = { __type = typeName }
	mt.__index = function(t, k)
		local f = rawget(mt, k)
		if f ~= nil and k:sub(1, 2) ~= "__" then
			return f
		end
		error(tostring(k) .. " is not a valid member of " .. typeName, 2)
	end
	mt.__eq = function(a, b)
		for _, f in fields do
			if rawget(a, f) ~= rawget(b, f) then
				return false
			end
		end
		return true
	end
	return mt
end

local UDimMT = simpleType("UDim", { "Scale", "Offset" })
local function udim(s, o)
	return freeze(setmetatable({ Scale = s or 0, Offset = o or 0 }, UDimMT))
end
UDimMT.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimMT.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
local UDim = { new = udim }
local UDim2MT = simpleType("UDim2", { "X", "Y" })
local function udim2(xs, xo, ys, yo)
	local x, y = udim(xs, xo), udim(ys, yo)
	return freeze(setmetatable({ X = x, Y = y, Width = x, Height = y }, UDim2MT))
end
UDim2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UDim2MT.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UDim2MT.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
function UDim2MT.Lerp(a, b, t)
	return udim2(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
end
local UDim2 = {
	new = function(a, b, c, d)
		if getmetatable(a) == UDimMT then
			return udim2(a.Scale, a.Offset, b.Scale, b.Offset)
		end
		for i, v in { a or 0, b or 0, c or 0, d or 0 } do
			if rawtype(v) ~= "number" then
				error("invalid argument #" .. i .. " to 'new' (number expected)", 2)
			end
		end
		return udim2(a or 0, b or 0, c or 0, d or 0)
	end,
	fromScale = function(x, y)
		return udim2(x or 0, 0, y or 0, 0)
	end,
	fromOffset = function(x, y)
		return udim2(0, x or 0, 0, y or 0)
	end,
}

local NRMT = simpleType("NumberRange", { "Min", "Max" })
local NumberRange = {
	new = function(a, b)
		if rawtype(a) ~= "number" then
			error("invalid argument #1 to 'new' (number expected)", 2)
		end
		b = b or a
		if a > b then
			error("NumberRange: invalid range (min > max)", 2)
		end
		return freeze(setmetatable({ Min = a, Max = b }, NRMT))
	end,
}
local NSKMT = simpleType("NumberSequenceKeypoint", { "Time", "Value", "Envelope" })
local NumberSequenceKeypoint = {
	new = function(t, v, e)
		if rawtype(t) ~= "number" or rawtype(v) ~= "number" then
			error("invalid argument to NumberSequenceKeypoint.new", 2)
		end
		return freeze(setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NSKMT))
	end,
}
local NSMT = simpleType("NumberSequence", { "Keypoints" })
local function checkKeypoints(kps, what)
	if #kps < 2 then
		error(what .. ": requires at least 2 keypoints", 3)
	end
	if #kps > 20 then
		error(what .. ": too many keypoints (max 20)", 3)
	end
	if kps[1].Time ~= 0 then
		error(what .. " ctor: starting keypoint time must be 0", 3)
	end
	if kps[#kps].Time ~= 1 then
		error(what .. " ctor: last keypoint time must be 1", 3)
	end
	for i = 2, #kps do
		if kps[i].Time < kps[i - 1].Time then
			error(what .. " ctor: keypoints must be ordered by time", 3)
		end
	end
end
local NumberSequence = {
	new = function(a, b)
		local kps
		if rawtype(a) == "number" then
			kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
		elseif rawtype(a) == "table" then
			kps = a
			for _, k in kps do
				if getmetatable(k) ~= NSKMT then
					error("NumberSequence.new: table of NumberSequenceKeypoints expected", 2)
				end
			end
			checkKeypoints(kps, "NumberSequence")
		else
			error("invalid argument #1 to NumberSequence.new", 2)
		end
		return freeze(setmetatable({ Keypoints = kps }, NSMT))
	end,
}
local CSKMT = simpleType("ColorSequenceKeypoint", { "Time", "Value" })
local ColorSequenceKeypoint = {
	new = function(t, c)
		if rawtype(t) ~= "number" or getmetatable(c) ~= C3 then
			error("invalid argument to ColorSequenceKeypoint.new (number, Color3 expected)", 2)
		end
		return freeze(setmetatable({ Time = t, Value = c }, CSKMT))
	end,
}
local CSMT = simpleType("ColorSequence", { "Keypoints" })
local ColorSequence = {
	new = function(a, b)
		local kps
		if getmetatable(a) == C3 then
			if b ~= nil and getmetatable(b) ~= C3 then
				error("invalid argument #2 to ColorSequence.new (Color3 expected)", 2)
			end
			kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
		elseif rawtype(a) == "table" and getmetatable(a) == nil then
			kps = a
			for _, k in kps do
				if getmetatable(k) ~= CSKMT then
					error("ColorSequence.new: table of ColorSequenceKeypoints expected", 2)
				end
			end
			checkKeypoints(kps, "ColorSequence")
		else
			error("invalid argument #1 to ColorSequence.new (Color3 or table expected, got " .. rawtypeof(a) .. ")", 2)
		end
		return freeze(setmetatable({ Keypoints = kps }, CSMT))
	end,
}
local TIMT = simpleType("TweenInfo", { "Time" })
local TweenInfo = {
	new = function(t, style, dir, rep, rev, delay)
		return freeze(setmetatable({ Time = t or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rep or 0, Reverses = rev or false, DelayTime = delay or 0 }, TIMT))
	end,
}
local PPMT = simpleType("PhysicalProperties", { "Density", "Friction", "Elasticity" })
local PhysicalProperties = {
	new = function(...)
		local n = select("#", ...)
		if n ~= 1 and n ~= 3 and n ~= 5 then
			error("PhysicalProperties.new: expected 1, 3 or 5 arguments, got " .. n, 2)
		end
		local d, f, e, fw, ew = ...
		return freeze(setmetatable({ Density = d, Friction = f, Elasticity = e, FrictionWeight = fw or 1, ElasticityWeight = ew or 1 }, PPMT))
	end,
}
local RectMT = simpleType("Rect", { "Min", "Max" })
local Rect = {
	new = function(a, b, c, d)
		return freeze(setmetatable({ Min = v2(a, b), Max = v2(c, d), Width = c - a, Height = d - b }, RectMT))
	end,
}

-- Random (deterministic xorshift)
local RandomMT = { __type = "Random" }
RandomMT.__index = RandomMT
local function rnext(self)
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x / 4294967296
end
function RandomMT:NextNumber(a, b)
	local r = rnext(self)
	if a == nil then
		return r
	end
	return a + (b - a) * r
end
function RandomMT:NextInteger(a, b)
	if rawtype(a) ~= "number" or rawtype(b) ~= "number" then
		error("invalid argument to 'NextInteger' (number expected)", 2)
	end
	if a > b then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	return a + math.floor(rnext(self) * (b - a + 1))
end
function RandomMT:Clone()
	return setmetatable({ s = self.s }, RandomMT)
end
function RandomMT:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomMT:NextUnitVector()
	return v3(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1)).Unit
end
local seedCounter = 12345
local Random = {
	new = function(seed)
		seedCounter += 7919
		local s = math.floor(math.abs(seed or seedCounter)) % 4294967295
		if s == 0 then
			s = 2463534242
		end
		local r = setmetatable({ s = s }, RandomMT)
		rnext(r)
		rnext(r)
		return r
	end,
}

Sim.types = {
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	UDim = UDim,
	UDim2 = UDim2,
	NumberRange = NumberRange,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	TweenInfo = TweenInfo,
	PhysicalProperties = PhysicalProperties,
	Rect = Rect,
	Random = Random,
}
Sim.V3 = V3
Sim.C3 = C3

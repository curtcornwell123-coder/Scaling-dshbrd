-- ===== part 2: enums + instances =====
local Classes = API.Classes

-- Enums -----------------------------------------------------------------------
local EnumItemMT = { __type = "EnumItem" }
local EnumMT = { __type = "Enum" }
local enumObjs = {}
EnumItemMT.__index = function(t, k)
	if k == "IsA" then
		return function(self, name)
			return rawget(self, "EnumType").__name == name
		end
	end
	error(tostring(k) .. " is not a valid member of EnumItem", 2)
end
EnumItemMT.__tostring = function(t)
	return "Enum." .. t.EnumType.__name .. "." .. t.Name
end
local function getEnum(name)
	local e = enumObjs[name]
	if e then
		return e
	end
	local items = API.Enums[name]
	if not items then
		return nil
	end
	e = { __name = name, __items = {}, __list = {} }
	for i, itemName in items do
		local it = setmetatable({ Name = itemName, Value = i - 1, EnumType = e }, EnumItemMT)
		e.__items[itemName] = it
		e.__list[i] = it
		table.freeze(it)
	end
	setmetatable(e, EnumMT)
	enumObjs[name] = e
	return e
end
EnumMT.__index = function(t, k)
	local items = rawget(t, "__items")
	local it = items[k]
	if it then
		return it
	end
	if k == "GetEnumItems" then
		return function(self)
			return table.clone(rawget(self, "__list"))
		end
	elseif k == "FromName" then
		return function(self, n)
			return rawget(self, "__items")[n]
		end
	elseif k == "FromValue" then
		return function(self, v)
			return rawget(self, "__list")[v + 1]
		end
	end
	Sim.misuse(tostring(k) .. ' is not a valid member of "Enum.' .. rawget(t, "__name") .. '"')
end
EnumMT.__tostring = function(t)
	return rawget(t, "__name")
end
local Enum = setmetatable({}, {
	__index = function(_, name)
		local e = getEnum(name)
		if not e then
			Sim.misuse(tostring(name) .. " is not a valid member of Enums")
		end
		return e
	end,
})
Sim.Enum = Enum
Sim.getEnum = getEnum

-- typeof / type -----------------------------------------------------------------
local function mtype(v)
	if rawtype(v) == "table" then
		local mt = getmetatable(v)
		if rawtype(mt) == "table" then
			local t = rawget(mt, "__type")
			if t then
				return t
			end
		end
	end
	return rawtypeof(v)
end
Sim.typeof = mtype
Sim.type = function(v)
	if rawtype(v) == "table" then
		local mt = getmetatable(v)
		if rawtype(mt) == "table" and rawget(mt, "__type") then
			return "userdata"
		end
	end
	return rawtype(v)
end

-- Instances ---------------------------------------------------------------------
local D = setmetatable({}, { __mode = "k" })
Sim.D = D
local InstMT = { __type = "Instance" }
local function isInstance(v)
	return rawtype(v) == "table" and getmetatable(v) == InstMT
end
Sim.isInstance = isInstance

local memberCache = {}
local function member(cls, name)
	local key = cls .. "\0" .. name
	local m = memberCache[key]
	if m == nil then
		m = false
		local c = cls
		while c do
			local def = Classes[c]
			if not def then
				break
			end
			if def.Props[name] then
				m = { "prop", def.Props[name] }
				break
			elseif def.Methods[name] then
				m = { "method" }
				break
			elseif def.Events[name] then
				m = { "event" }
				break
			elseif def.Callbacks[name] then
				m = { "callback" }
				break
			end
			c = def.Super
		end
		memberCache[key] = m
	end
	return m
end
local isACache = {}
local function classIsA(cls, target)
	local key = cls .. "\0" .. target
	local r = isACache[key]
	if r == nil then
		r = false
		local c = cls
		while c do
			if c == target then
				r = true
				break
			end
			local def = Classes[c]
			c = def and def.Super
		end
		isACache[key] = r
	end
	return r
end
Sim.classIsA = classIsA

local Impl = {} -- Impl[class] = { methods = {}, get = {}, set = {} }
local function impl(cls)
	Impl[cls] = Impl[cls] or { methods = {}, get = {}, set = {} }
	return Impl[cls]
end
Sim.impl = impl
local implCache = {}
local function findImpl(cls, kind, name)
	local key = cls .. "\0" .. kind .. "\0" .. name
	local f = implCache[key]
	if f == nil then
		f = false
		local c = cls
		while c do
			local im = Impl[c]
			if im and im[kind][name] then
				f = im[kind][name]
				break
			end
			local def = Classes[c]
			c = def and def.Super
		end
		implCache[key] = f
	end
	return f
end

local READONLY = {
	ClassName = true, AbsoluteSize = true, AbsolutePosition = true, AbsoluteRotation = true, AbsoluteContentSize = true,
	AbsoluteCanvasSize = true, AbsoluteWindowSize = true, TextBounds = true, TextFits = true, ContentText = true,
	LocalPlayer = true, AccountAge = true, MembershipType = true, AssemblyMass = true, AssemblyRootPart = true, Mass = true,
	IsLoaded = true, PlaybackLoudness = true, TimeLength = true, IsPlaying = true, MoveDirection = true, FloorMaterial = true,
	RootPart = true, JobId = true, PlaceId = true, GameId = true, CreatorId = true, ViewportSize = true, PlaybackState = true,
	TouchEnabled = true, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = true, UserId = true, Character_ = true,
}

local function fullName(inst)
	local parts = {}
	local cur = inst
	while cur and D[cur] and D[cur].cls ~= "DataModel" do
		table.insert(parts, 1, D[cur].props.Name)
		cur = D[cur].parent
	end
	return table.concat(parts, ".")
end
Sim.fullName = fullName

local function getSignal(inst, d, name)
	local s = d.signals[name]
	if not s then
		s = Sim.newSignal(name)
		d.signals[name] = s
	end
	return s
end
local function fireIf(d, name, ...)
	local s = d.signals[name]
	if s and (#s._conns > 0 or #s._waiting > 0) then
		s:_fire(...)
	end
end
Sim.getSignal = getSignal
Sim.fireIf = fireIf

-- defaults
local DEFAULTS = {
	BasePart = {
		Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, Transparency = 0,
		Reflectance = 0, Locked = false, Massless = false, CollisionGroup = "Default",
	},
	Part = { Size = Vector3.new(4, 1, 2) },
	WedgePart = { Size = Vector3.new(4, 1, 2) },
	SpawnLocation = { Duration = 10, Neutral = true, Enabled = true, Size = Vector3.new(12, 1, 12) },
	Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, HipHeight = 2 },
	GuiObject = { Visible = true, BackgroundTransparency = 0, ZIndex = 1, BorderSizePixel = 1, Active = false },
	TextLabel = { Text = "Label", TextSize = 14 },
	TextButton = { Text = "Button", TextSize = 14, AutoButtonColor = true },
	TextBox = { Text = "TextBox", TextSize = 14 },
	LayerCollector = { Enabled = true, ResetOnSpawn = true },
	ProximityPrompt = { Enabled = true, ActionText = "Interact", MaxActivationDistance = 10, RequiresLineOfSight = true },
	ParticleEmitter = { Enabled = true, Rate = 20 },
	Light = { Enabled = true, Brightness = 1, Range = 8 },
	Sound = { Volume = 0.5 },
	Camera = { FieldOfView = 70 },
	Player = { CameraMinZoomDistance = 0.5, CameraMaxZoomDistance = 400 },
	UIScale = { Scale = 1 },
	UIStroke = { Thickness = 1 },
	Workspace = { Gravity = 196.2, FallenPartsDestroyHeight = -500 },
	BillboardGui = { MaxDistance = math.huge },
	SurfaceGui = { PixelsPerStud = 50 },
}
local function typeDefault(t)
	local nilable = t:sub(-1) == "?"
	if nilable then
		return nil
	end
	if t == "number" then
		return 0
	elseif t == "boolean" then
		return false
	elseif t == "string" or t == "ContentId" or t == "Content" then
		return ""
	elseif t == "Vector3" then
		return Vector3.zero
	elseif t == "Vector2" then
		return Sim.types.Vector2.zero
	elseif t == "CFrame" then
		return Sim.types.CFrame.identity
	elseif t == "Color3" then
		return Sim.types.Color3.fromRGB(163, 162, 165)
	elseif t == "UDim2" then
		return Sim.types.UDim2.new()
	elseif t == "UDim" then
		return Sim.types.UDim.new()
	elseif t:sub(1, 4) == "Enum" then
		local e = getEnum(t:sub(5))
		if e then
			return rawget(e, "__list")[1]
		end
	elseif t == "NumberRange" then
		return Sim.types.NumberRange.new(0)
	elseif t == "NumberSequence" then
		return Sim.types.NumberSequence.new(0)
	elseif t == "ColorSequence" then
		return Sim.types.ColorSequence.new(Sim.types.Color3.new(1, 1, 1))
	end
	return nil
end
local defaultCache = {}
local function defaultFor(cls, key, t)
	local ck = cls .. "\0" .. key
	local v = defaultCache[ck]
	if v == nil then
		local c = cls
		local found = false
		while c do
			local dd = DEFAULTS[c]
			if dd and dd[key] ~= nil then
				v = dd[key]
				found = true
				break
			end
			local def = Classes[c]
			c = def and def.Super
		end
		if not found then
			v = typeDefault(t)
		end
		defaultCache[ck] = if v == nil then false else v
		return v
	end
	if v == false and t ~= "boolean" then
		return nil
	end
	return v
end

local DATATYPES = {
	Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, NumberRange = true,
	NumberSequence = true, ColorSequence = true, PhysicalProperties = true, Rect = true,
}
local function coerce(cls, key, t, v)
	local nilable = t:sub(-1) == "?"
	local base = if nilable then t:sub(1, -2) else t
	if v == nil then
		if nilable or Classes[base] or base == "PhysicalProperties" then
			return nil
		end
		Sim.misuse(string.format("Unable to assign property %s. %s expected, got nil", key, base))
	end
	if base == "number" then
		if rawtype(v) ~= "number" then
			Sim.misuse(string.format("Unable to assign property %s. number expected, got %s", key, mtype(v)))
		end
	elseif base == "boolean" then
		if rawtype(v) ~= "boolean" then
			Sim.misuse(string.format("Unable to assign property %s. bool expected, got %s", key, mtype(v)))
		end
	elseif base == "string" or base == "ContentId" or base == "Content" then
		if rawtype(v) == "number" then
			return tostring(v)
		elseif rawtype(v) ~= "string" then
			Sim.misuse(string.format("Unable to assign property %s. string expected, got %s", key, mtype(v)))
		end
	elseif base:sub(1, 4) == "Enum" and API.Enums[base:sub(5)] then
		local e = getEnum(base:sub(5))
		if mtype(v) == "EnumItem" then
			if rawget(v, "EnumType") ~= e then
				Sim.misuse(string.format("Unable to assign property %s. Expected Enum.%s, got %s", key, base:sub(5), tostring(v)))
			end
		elseif rawtype(v) == "string" then
			local it = rawget(e, "__items")[v]
			if not it then
				Sim.misuse(string.format('Unable to assign property %s. Invalid value "%s" for enum %s', key, v, base:sub(5)))
			end
			return it
		elseif rawtype(v) == "number" then
			local it = rawget(e, "__list")[v + 1]
			if not it then
				Sim.misuse(string.format("Unable to assign property %s. Invalid value %d for enum %s", key, v, base:sub(5)))
			end
			return it
		else
			Sim.misuse(string.format("Unable to assign property %s. EnumItem expected, got %s", key, mtype(v)))
		end
	elseif DATATYPES[base] then
		if mtype(v) ~= base then
			Sim.misuse(string.format("Unable to assign property %s. %s expected, got %s", key, base, mtype(v)))
		end
	elseif Classes[base] then
		if not isInstance(v) then
			Sim.misuse(string.format("Unable to assign property %s. Object expected, got %s", key, mtype(v)))
		end
		if not classIsA(D[v].cls, base) then
			Sim.misuse(string.format("Unable to assign property %s. %s expected, got %s", key, base, D[v].cls))
		end
	end
	return v
end

local function inDataModel(inst)
	local cur = inst
	while cur do
		local d = D[cur]
		if d.cls == "DataModel" then
			return true
		end
		cur = d.parent
	end
	return false
end
Sim.inDataModel = inDataModel
local function descendants(inst, out)
	out = out or {}
	for _, c in D[inst].children do
		table.insert(out, c)
		descendants(c, out)
	end
	return out
end
Sim.descendants = descendants
local function isDescendantOf(inst, anc)
	local cur = D[inst].parent
	while cur do
		if cur == anc then
			return true
		end
		cur = D[cur].parent
	end
	return false
end

-- CollectionService state
local tagged = {} -- tag -> { [inst] = true }
local tagAdded = {}
local tagRemoved = {}
local function tagSignal(tbl, tag)
	tbl[tag] = tbl[tag] or Sim.newSignal("Tag:" .. tag)
	return tbl[tag]
end
Sim.tagged = tagged

Sim.raycastDirty = true
local function markDirtyFor(inst, d)
	if d.isBasePart or #d.children > 0 or d.cls == "Model" then
		Sim.raycastDirty = true
	end
end

local function setParent(inst, d, newParent)
	if newParent ~= nil and not isInstance(newParent) then
		Sim.misuse("Unable to assign property Parent. Instance expected, got " .. mtype(newParent))
	end
	if newParent == d.parent then
		return
	end
	if d.locked then
		Sim.misuse(string.format("The Parent property of %s is locked, current parent: NULL, new parent %s", tostring(d.props.Name), if newParent then tostring(D[newParent].props.Name) else "NULL"))
	end
	if d.isService then
		Sim.misuse("Cannot change the Parent of a service")
	end
	if newParent then
		local p = newParent
		while p do
			if p == inst then
				Sim.misuse(string.format("Attempt to set parent of %s to %s would result in circular reference", tostring(d.props.Name), tostring(D[newParent].props.Name)))
			end
			p = D[p].parent
		end
	end
	local old = d.parent
	local wasInDM = old ~= nil and inDataModel(old)
	if old then
		local od = D[old]
		local idx = table.find(od.children, inst)
		if idx then
			table.remove(od.children, idx)
		end
		fireIf(od, "ChildRemoved", inst)
		local a = old
		while a do
			local ad = D[a]
			if ad.signals.DescendantRemoving then
				fireIf(ad, "DescendantRemoving", inst)
			end
			a = ad.parent
		end
	end
	d.parent = newParent
	markDirtyFor(inst, d)
	if newParent then
		local nd = D[newParent]
		table.insert(nd.children, inst)
		fireIf(nd, "ChildAdded", inst)
		local a = newParent
		local descs = nil
		while a do
			local ad = D[a]
			local s = ad.signals.DescendantAdded
			if s and #s._conns > 0 then
				s:_fire(inst)
				descs = descs or descendants(inst)
				for _, x in descs do
					s:_fire(x)
				end
			end
			a = ad.parent
		end
	end
	fireIf(d, "AncestryChanged", inst, newParent)
	local needDesc = false
	for _, x in descendants(inst) do
		local xd = D[x]
		if xd.signals.AncestryChanged then
			fireIf(xd, "AncestryChanged", inst, newParent)
		end
		needDesc = true
	end
	local nowInDM = newParent ~= nil and inDataModel(newParent)
	if wasInDM ~= nowInDM then
		local list = { inst }
		if needDesc then
			for _, x in descendants(inst) do
				table.insert(list, x)
			end
		end
		for _, x in list do
			for tag in D[x].tags do
				local sig = if nowInDM then tagAdded[tag] else tagRemoved[tag]
				if sig then
					sig:_fire(x)
				end
			end
		end
	end
end

local function attrValid(v)
	if v == nil then
		return true
	end
	local t = mtype(v)
	return t == "boolean" or t == "number" or t == "string" or t == "Vector3" or t == "Vector2" or t == "CFrame" or t == "Color3" or t == "UDim" or t == "UDim2" or t == "NumberRange" or t == "NumberSequence" or t == "ColorSequence" or t == "Rect" or t == "BrickColor" or t == "Font" or t == "EnumItem"
end

local instCount = 0
local function newInstance(cls)
	instCount += 1
	local inst = setmetatable({}, InstMT)
	D[inst] = {
		cls = cls,
		props = { Name = cls },
		children = {},
		parent = nil,
		attrs = {},
		tags = {},
		signals = {},
		propSignals = {},
		attrSignals = {},
		isBasePart = classIsA(cls, "BasePart"),
		id = instCount,
		createdBy = currentSide(),
	}
	return inst
end
Sim.newInstance = newInstance

InstMT.__index = function(inst, key)
	local d = D[inst]
	if rawtype(key) ~= "string" then
		Sim.misuse("invalid key type " .. rawtype(key) .. " when indexing " .. d.cls)
	end
	local g = findImpl(d.cls, "get", key)
	if g then
		return g(inst, d)
	end
	local m = member(d.cls, key)
	if m then
		local kind = m[1]
		if kind == "prop" then
			local v = d.props[key]
			if v == nil then
				return defaultFor(d.cls, key, m[2])
			end
			return v
		elseif kind == "method" then
			local f = findImpl(d.cls, "methods", key)
			if f then
				return f
			end
			return function()
				table.insert(Sim.apiMisuse, { side = currentSide(), msg = "MOCK-UNIMPLEMENTED " .. d.cls .. ":" .. key, trace = shortTrace(debug.traceback("", 2)), t = Sim.now, mock = true })
				error("MOCK-UNIMPLEMENTED " .. d.cls .. ":" .. key, 2)
			end
		elseif kind == "event" then
			return getSignal(inst, d, key)
		elseif kind == "callback" then
			Sim.misuse(key .. " is a callback member of " .. d.cls .. "; you can only set the callback value, get is not available")
		end
	end
	for _, c in d.children do
		if D[c].props.Name == key then
			return c
		end
	end
	Sim.misuse(string.format('%s is not a valid member of %s "%s"', key, d.cls, fullName(inst)))
end

local function rawSet(inst, d, key, value)
	local old = d.props[key]
	if old == value and old ~= nil then
		return
	end
	d.props[key] = value
	local ps = d.propSignals[key]
	if ps then
		ps:_fire()
	end
	if d.signals.Changed then
		if classIsA(d.cls, "ValueBase") then
			if key == "Value" then
				d.signals.Changed:_fire(value)
			end
		else
			d.signals.Changed:_fire(key)
		end
	end
end
Sim.rawSet = rawSet

InstMT.__newindex = function(inst, key, value)
	local d = D[inst]
	local m = member(d.cls, key)
	if not m then
		Sim.misuse(string.format('%s is not a valid member of %s "%s"', tostring(key), d.cls, fullName(inst)))
	end
	local kind = m[1]
	if kind == "method" or kind == "event" then
		Sim.misuse(key .. " cannot be assigned to")
	end
	if kind == "callback" then
		if value ~= nil and rawtype(value) ~= "function" then
			Sim.misuse("Unable to assign property " .. key .. ". function expected")
		end
		d.props[key] = value
		local s = findImpl(d.cls, "set", key)
		if s then
			s(inst, d, value)
		end
		return
	end
	if READONLY[key] then
		Sim.misuse("Unable to assign property " .. key .. ". Property is read only")
	end
	if d.destroyed and key ~= "Parent" then
		-- allowed in Roblox
	end
	value = coerce(d.cls, key, m[2], value)
	local s = findImpl(d.cls, "set", key)
	if s then
		s(inst, d, value)
		return
	end
	rawSet(inst, d, key, value)
end
InstMT.__tostring = function(inst)
	return tostring(D[inst].props.Name)
end

-- Instance methods -------------------------------------------------------------
local I = impl("Instance")
I.get.Parent = function(inst, d)
	return d.parent
end
I.set.Parent = function(inst, d, v)
	setParent(inst, d, v)
end
I.get.ClassName = function(inst, d)
	return d.cls
end
I.set.Name = function(inst, d, v)
	if rawtype(v) ~= "string" then
		Sim.misuse("Unable to assign property Name. string expected")
	end
	rawSet(inst, d, "Name", v)
end
local function checkSelf(self, method)
	if not isInstance(self) then
		Sim.misuse("Expected ':' not '.' calling member function " .. method)
	end
	return D[self]
end
I.methods.FindFirstChild = function(self, name, recursive)
	local d = checkSelf(self, "FindFirstChild")
	if rawtype(name) ~= "string" then
		Sim.misuse("Argument 1 missing or nil (FindFirstChild)")
	end
	for _, c in d.children do
		if D[c].props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in descendants(self) do
			if D[c].props.Name == name then
				return c
			end
		end
	end
	return nil
end
I.methods.FindFirstChildOfClass = function(self, cls)
	local d = checkSelf(self, "FindFirstChildOfClass")
	for _, c in d.children do
		if D[c].cls == cls then
			return c
		end
	end
	return nil
end
I.methods.FindFirstChildWhichIsA = function(self, cls, recursive)
	local d = checkSelf(self, "FindFirstChildWhichIsA")
	local list = if recursive then descendants(self) else d.children
	for _, c in list do
		if classIsA(D[c].cls, cls) then
			return c
		end
	end
	return nil
end
I.methods.FindFirstDescendant = function(self, name)
	for _, c in descendants(self) do
		if D[c].props.Name == name then
			return c
		end
	end
	return nil
end
I.methods.FindFirstAncestor = function(self, name)
	local cur = D[self].parent
	while cur do
		if D[cur].props.Name == name then
			return cur
		end
		cur = D[cur].parent
	end
	return nil
end
I.methods.FindFirstAncestorOfClass = function(self, cls)
	local cur = D[self].parent
	while cur do
		if D[cur].cls == cls then
			return cur
		end
		cur = D[cur].parent
	end
	return nil
end
I.methods.FindFirstAncestorWhichIsA = function(self, cls)
	local cur = D[self].parent
	while cur do
		if classIsA(D[cur].cls, cls) then
			return cur
		end
		cur = D[cur].parent
	end
	return nil
end
I.methods.GetChildren = function(self)
	return table.clone(checkSelf(self, "GetChildren").children)
end
I.methods.GetDescendants = function(self)
	checkSelf(self, "GetDescendants")
	return descendants(self)
end
I.methods.IsA = function(self, cls)
	local d = checkSelf(self, "IsA")
	if rawtype(cls) ~= "string" then
		Sim.misuse("Argument 1 missing or nil (IsA)")
	end
	return classIsA(d.cls, cls)
end
I.methods.IsDescendantOf = function(self, anc)
	checkSelf(self, "IsDescendantOf")
	if anc == nil then
		return false
	end
	return isDescendantOf(self, anc)
end
I.methods.IsAncestorOf = function(self, desc)
	if desc == nil then
		return false
	end
	return isDescendantOf(desc, self)
end
I.methods.GetFullName = function(self)
	return fullName(self)
end
I.methods.GetDebugId = function(self)
	return tostring(D[self].id)
end
I.methods.WaitForChild = function(self, name, timeout)
	local d = checkSelf(self, "WaitForChild")
	if rawtype(name) ~= "string" then
		Sim.misuse("Argument 1 missing or nil (WaitForChild)")
	end
	local function find()
		for _, c in d.children do
			if D[c].props.Name == name then
				return c
			end
		end
		return nil
	end
	local c = find()
	if c then
		return c
	end
	local start = Sim.now
	local warned = false
	while true do
		Sim.task.wait(1 / 30)
		c = find()
		if c then
			return c
		end
		if timeout and Sim.now - start >= timeout then
			return nil
		end
		if not timeout and not warned and Sim.now - start > 5 then
			warned = true
			table.insert(Sim.warnings, { side = currentSide(), msg = string.format('Infinite yield possible on \'%s:WaitForChild("%s")\'', fullName(self), name), trace = shortTrace(debug.traceback("", 2)), t = Sim.now })
		end
	end
end
local function destroy(inst)
	local d = D[inst]
	if d.destroyed then
		return
	end
	fireIf(d, "Destroying")
	d.destroyed = true
	for _, c in table.clone(d.children) do
		destroy(c)
	end
	if d.parent then
		setParent(inst, d, nil)
	end
	d.locked = true
	for _, s in d.signals do
		s:_disconnectAll()
	end
	for _, s in d.propSignals do
		s:_disconnectAll()
	end
	for _, s in d.attrSignals do
		s:_disconnectAll()
	end
	if d.onDestroy then
		d.onDestroy(inst, d)
	end
end
Sim.destroy = destroy
I.methods.Destroy = function(self)
	checkSelf(self, "Destroy")
	destroy(self)
end
I.methods.ClearAllChildren = function(self)
	for _, c in table.clone(D[self].children) do
		destroy(c)
	end
end
local function clone(inst)
	local d = D[inst]
	if d.props.Archivable == false then
		return nil
	end
	local c = newInstance(d.cls)
	local cd = D[c]
	for k, v in d.props do
		cd.props[k] = v
	end
	for k, v in d.attrs do
		cd.attrs[k] = v
	end
	for t in d.tags do
		cd.tags[t] = true
		tagged[t] = tagged[t] or {}
		tagged[t][c] = true
	end
	for _, ch in d.children do
		local cc = clone(ch)
		if cc then
			cc.Parent = c
		end
	end
	return c
end
I.methods.Clone = function(self)
	return clone(self)
end
I.methods.GetAttribute = function(self, name)
	if rawtype(name) ~= "string" then
		Sim.misuse("GetAttribute: Argument 1 missing or nil")
	end
	return D[self].attrs[name]
end
I.methods.GetAttributes = function(self)
	return table.clone(D[self].attrs)
end
I.methods.SetAttribute = function(self, name, value)
	local d = checkSelf(self, "SetAttribute")
	if rawtype(name) ~= "string" or #name > 100 or not string.match(name, "^[%w_]+$") or name:sub(1, 3) == "RBX" then
		Sim.misuse("SetAttribute: invalid attribute name " .. tostring(name))
	end
	if not attrValid(value) then
		Sim.misuse("SetAttribute: " .. mtype(value) .. " is not a supported attribute type (attribute " .. name .. ")")
	end
	local old = d.attrs[name]
	d.attrs[name] = value
	if old ~= value then
		local s = d.attrSignals[name]
		if s then
			s:_fire()
		end
		fireIf(d, "AttributeChanged", name)
	end
end
I.methods.GetAttributeChangedSignal = function(self, name)
	local d = D[self]
	local s = d.attrSignals[name]
	if not s then
		s = Sim.newSignal("AttrChanged:" .. name)
		d.attrSignals[name] = s
	end
	return s
end
I.methods.GetPropertyChangedSignal = function(self, prop)
	local d = checkSelf(self, "GetPropertyChangedSignal")
	local m = member(d.cls, prop)
	if not m or m[1] ~= "prop" then
		Sim.misuse(tostring(prop) .. " is not a valid property name.")
	end
	local s = d.propSignals[prop]
	if not s then
		s = Sim.newSignal("PropChanged:" .. prop)
		d.propSignals[prop] = s
	end
	return s
end
local function addTag(inst, tag)
	local d = D[inst]
	if d.tags[tag] then
		return
	end
	d.tags[tag] = true
	tagged[tag] = tagged[tag] or {}
	tagged[tag][inst] = true
	if tagAdded[tag] and inDataModel(inst) then
		tagAdded[tag]:_fire(inst)
	end
end
local function removeTag(inst, tag)
	local d = D[inst]
	if not d.tags[tag] then
		return
	end
	d.tags[tag] = nil
	if tagged[tag] then
		tagged[tag][inst] = nil
	end
	if tagRemoved[tag] and inDataModel(inst) then
		tagRemoved[tag]:_fire(inst)
	end
end
I.methods.AddTag = function(self, tag)
	addTag(self, tag)
end
I.methods.RemoveTag = function(self, tag)
	removeTag(self, tag)
end
I.methods.HasTag = function(self, tag)
	return D[self].tags[tag] == true
end
I.methods.GetTags = function(self)
	local out = {}
	for t in D[self].tags do
		table.insert(out, t)
	end
	return out
end

local CS = impl("CollectionService")
CS.methods.AddTag = function(self, inst, tag)
	if not isInstance(inst) or rawtype(tag) ~= "string" then
		Sim.misuse("CollectionService:AddTag(instance, string) expected")
	end
	addTag(inst, tag)
end
CS.methods.RemoveTag = function(self, inst, tag)
	removeTag(inst, tag)
end
CS.methods.HasTag = function(self, inst, tag)
	return D[inst].tags[tag] == true
end
CS.methods.GetTags = function(self, inst)
	return I.methods.GetTags(inst)
end
CS.methods.GetTagged = function(self, tag)
	if rawtype(tag) ~= "string" then
		Sim.misuse("GetTagged: string expected")
	end
	local out = {}
	for inst in tagged[tag] or {} do
		if inDataModel(inst) and not D[inst].destroyed then
			table.insert(out, inst)
		end
	end
	table.sort(out, function(a, b)
		return D[a].id < D[b].id
	end)
	return out
end
CS.methods.GetInstanceAddedSignal = function(self, tag)
	return tagSignal(tagAdded, tag)
end
CS.methods.GetInstanceRemovedSignal = function(self, tag)
	return tagSignal(tagRemoved, tag)
end
CS.methods.GetAllTags = function(self)
	local out = {}
	for t in tagged do
		table.insert(out, t)
	end
	return out
end

-- PVInstance / Model / BasePart / Attachment -------------------------------------
local types = Sim.types
local function partMoved(inst, d)
	if d.isBasePart and d.props.CanQuery ~= false and not d.inBallFolder then
		Sim.raycastDirty = true
	end
end
local BP = impl("BasePart")
BP.get.CFrame = function(inst, d)
	return d.props.CFrame or types.CFrame.identity
end
BP.set.CFrame = function(inst, d, v)
	d.props.CFrame = v
	partMoved(inst, d)
	local ps = d.propSignals.CFrame
	if ps then
		ps:_fire()
	end
end
BP.get.Position = function(inst, d)
	return (d.props.CFrame or types.CFrame.identity).p
end
BP.set.Position = function(inst, d, v)
	local c = d.props.CFrame or types.CFrame.identity
	d.props.CFrame = Sim.cf(v, c.rx, c.ry, c.rz)
	partMoved(inst, d)
end
BP.get.Orientation = function(inst, d)
	local x, y, z = (d.props.CFrame or types.CFrame.identity):ToOrientation()
	return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
end
BP.set.Orientation = function(inst, d, v)
	local p = (d.props.CFrame or types.CFrame.identity).p
	d.props.CFrame = types.CFrame.new(p) * types.CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
	partMoved(inst, d)
end
BP.get.Rotation = BP.get.Orientation
BP.set.Rotation = BP.set.Orientation
BP.set.Size = function(inst, d, v)
	v = Vector3.new(math.clamp(v.X, 0.001, 2048), math.clamp(v.Y, 0.001, 2048), math.clamp(v.Z, 0.001, 2048))
	rawSet(inst, d, "Size", v)
	partMoved(inst, d)
end
BP.set.CanQuery = function(inst, d, v)
	rawSet(inst, d, "CanQuery", v)
	Sim.raycastDirty = true
end
BP.get.AssemblyMass = function(inst, d)
	local s = inst.Size
	return s.X * s.Y * s.Z * 0.7
end
BP.get.Mass = BP.get.AssemblyMass
BP.get.AssemblyRootPart = function(inst)
	return inst
end
BP.methods.GetMass = function(self)
	return self.AssemblyMass
end
BP.methods.SetNetworkOwner = function(self, owner)
	if currentSide() ~= "server" then
		Sim.misuse("SetNetworkOwner can only be called from the server")
	end
	if owner ~= nil and (not isInstance(owner) or D[owner].cls ~= "Player") then
		Sim.misuse("SetNetworkOwner: Player expected")
	end
	if D[self].props.Anchored then
		error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.", 2)
	end
	if not inDataModel(self) then
		error("Network Ownership API can only be called on descendants of the Workspace", 2)
	end
end
BP.methods.SetNetworkOwnershipAuto = function(self) end
BP.methods.GetNetworkOwner = function(self)
	return nil
end
BP.methods.ApplyImpulse = function(self, imp)
	local d = D[self]
	d.props.AssemblyLinearVelocity = (d.props.AssemblyLinearVelocity or Vector3.zero) + imp / self.AssemblyMass
end
BP.methods.ApplyAngularImpulse = function(self) end
BP.methods.GetTouchingParts = function(self)
	return {}
end
BP.methods.GetConnectedParts = function(self)
	return { self }
end
BP.methods.GetJoints = function(self)
	return {}
end
BP.methods.CanCollideWith = function(self, other)
	return true
end
BP.methods.PivotTo = function(self, c)
	self.CFrame = c
end
BP.methods.GetPivot = function(self)
	return self.CFrame
end

local MD = impl("Model")
local function modelPivot(m, d)
	local pp = d.props.PrimaryPart
	if pp and D[pp] and not D[pp].destroyed then
		return pp.CFrame
	end
	if d.props.WorldPivot then
		return d.props.WorldPivot
	end
	for _, x in descendants(m) do
		if D[x].isBasePart then
			return types.CFrame.new(x.Position)
		end
	end
	return types.CFrame.identity
end
MD.get.WorldPivot = function(inst, d)
	return modelPivot(inst, d)
end
MD.set.WorldPivot = function(inst, d, v)
	d.props.WorldPivot = v
end
MD.methods.GetPivot = function(self)
	return modelPivot(self, D[self])
end
MD.methods.PivotTo = function(self, target)
	if not Sim.isCF(target) then
		Sim.misuse("PivotTo: CFrame expected")
	end
	local d = D[self]
	local cur = modelPivot(self, d)
	local delta = target * cur:Inverse()
	for _, x in descendants(self) do
		if D[x].isBasePart then
			x.CFrame = delta * x.CFrame
		end
	end
	if d.props.WorldPivot and not d.props.PrimaryPart then
		d.props.WorldPivot = target
	end
end
MD.methods.GetBoundingBox = function(self)
	return modelPivot(self, D[self]), Vector3.new(4, 4, 4)
end
MD.methods.GetExtentsSize = function(self)
	return Vector3.new(4, 4, 4)
end
MD.methods.MoveTo = function(self, pos)
	self:PivotTo(types.CFrame.new(pos))
end
MD.methods.GetScale = function()
	return 1
end
MD.methods.ScaleTo = function() end
impl("PVInstance").methods.GetPivot = function(self)
	return types.CFrame.identity
end
impl("PVInstance").methods.PivotTo = function(self) end

local AT = impl("Attachment")
local function attParentCF(d)
	local p = d.parent
	if p and D[p].isBasePart then
		return p.CFrame
	end
	return types.CFrame.identity
end
AT.get.CFrame = function(inst, d)
	return d.props.CFrame or types.CFrame.identity
end
AT.get.Position = function(inst, d)
	return (d.props.CFrame or types.CFrame.identity).p
end
AT.set.Position = function(inst, d, v)
	local c = d.props.CFrame or types.CFrame.identity
	d.props.CFrame = Sim.cf(v, c.rx, c.ry, c.rz)
end
AT.get.Orientation = function(inst, d)
	local x, y, z = (d.props.CFrame or types.CFrame.identity):ToOrientation()
	return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
end
AT.set.Orientation = function(inst, d, v)
	local p = (d.props.CFrame or types.CFrame.identity).p
	d.props.CFrame = types.CFrame.new(p) * types.CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end
AT.get.WorldCFrame = function(inst, d)
	return attParentCF(d) * (d.props.CFrame or types.CFrame.identity)
end
AT.set.WorldCFrame = function(inst, d, v)
	d.props.CFrame = attParentCF(d):Inverse() * v
end
AT.get.WorldPosition = function(inst, d)
	return (attParentCF(d) * (d.props.CFrame or types.CFrame.identity)).p
end
AT.set.WorldPosition = function(inst, d, v)
	local local_ = attParentCF(d):Inverse() * v
	local c = d.props.CFrame or types.CFrame.identity
	d.props.CFrame = Sim.cf(local_, c.rx, c.ry, c.rz)
end
AT.get.Axis = function(inst, d)
	return (d.props.CFrame or types.CFrame.identity).rx
end
AT.get.SecondaryAxis = function(inst, d)
	return (d.props.CFrame or types.CFrame.identity).ry
end

Sim.InstMT = InstMT
Sim.setParent = setParent
Sim.addTag = addTag

-- ===== part 3: services, remotes, tweens, raycast, physics =====
local SERVICES = {
	"Workspace", "Players", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui",
	"StarterPack", "Lighting", "RunService", "TweenService", "CollectionService", "DataStoreService", "MessagingService",
	"MarketplaceService", "PhysicsService", "HttpService", "TextChatService", "SocialService", "UserInputService",
	"ContextActionService", "Debris", "SoundService", "Teams", "Chat", "GuiService", "ProximityPromptService",
	"TeleportService", "BadgeService", "PolicyService", "LocalizationService", "AssetService", "GroupService",
	"ContentProvider", "TestService", "HapticService", "VRService", "TextService",
}
local isServiceName = {}
for _, s in SERVICES do
	isServiceName[s] = true
end
local NOT_CREATABLE = {}
for _, c in {
	"Instance", "Object", "BasePart", "FormFactorPart", "PVInstance", "GuiObject", "GuiBase", "GuiBase2d", "GuiBase3d",
	"LayerCollector", "GuiButton", "GuiLabel", "ValueBase", "Light", "Constraint", "JointInstance", "BaseRemoteEvent",
	"PartAdornment", "HandleAdornment", "BevelMesh", "DataModelMesh", "FileMesh", "BaseScript", "LuaSourceContainer",
	"BackpackItem", "Controller", "UIBase", "UIComponent", "UIConstraint", "UILayout", "UIGridStyleLayout",
	"BasePlayerGui", "CharacterAppearance", "Feature", "TriangleMeshPart", "Clothing", "DataModel", "Player",
} do
	NOT_CREATABLE[c] = true
end

local game = Sim.newInstance("DataModel")
D[game].props.Name = "Game"
Sim.game = game
local services = {}
local function getService(name)
	if services[name] then
		return services[name]
	end
	if not isServiceName[name] then
		Sim.misuse("'" .. tostring(name) .. "' is not a valid Service name")
	end
	local s = Sim.newInstance(name)
	D[s].props.Name = name
	setParent(s, D[s], game)
	D[s].isService = true
	services[name] = s
	return s
end
Sim.getService = getService
local DM = impl("DataModel")
DM.methods.GetService = function(self, name)
	return getService(name)
end
DM.methods.FindService = function(self, name)
	return services[name]
end
DM.get.Workspace = function()
	return getService("Workspace")
end
DM.get.JobId = function()
	return ""
end
DM.get.PlaceId = function()
	return 0
end
DM.get.GameId = function()
	return 0
end
Sim.closeCallbacks = {}
DM.methods.BindToClose = function(self, fn)
	if currentSide() ~= "server" then
		Sim.misuse("BindToClose can only be called on the server")
	end
	table.insert(Sim.closeCallbacks, fn)
end
DM.methods.IsLoaded = function()
	return true
end

local Instance = {
	new = function(cls, parent)
		if rawtype(cls) ~= "string" then
			Sim.misuse("Instance.new: string expected")
		end
		if not Classes[cls] or NOT_CREATABLE[cls] or isServiceName[cls] or not classIsA(cls, "Instance") then
			Sim.misuse('Unable to create an Instance of type "' .. cls .. '"')
		end
		local inst = Sim.newInstance(cls)
		if parent then
			inst.Parent = parent
		end
		return inst
	end,
}
Sim.Instance = Instance

local workspace = getService("Workspace")
local terrain = Sim.newInstance("Terrain")
D[terrain].props.Name = "Terrain"
setParent(terrain, D[terrain], workspace)
local serverCamera = Sim.newInstance("Camera")
D[serverCamera].props.Name = "Camera"
setParent(serverCamera, D[serverCamera], workspace)
local clientCamera = Sim.newInstance("Camera")
D[clientCamera].props.Name = "Camera"
Sim.clientCamera = clientCamera
Sim.workspace = workspace
impl("Terrain").methods.Clear = function() end
local WS = impl("Workspace")
WS.get.CurrentCamera = function()
	return if currentSide() == "client" then clientCamera else serverCamera
end
WS.set.CurrentCamera = function() end
WS.get.Terrain = function()
	return terrain
end
WS.methods.GetServerTimeNow = function()
	return Sim.EPOCH + Sim.now
end
WS.methods.GetRealPhysicsFPS = function()
	return 60
end

-- Players -------------------------------------------------------------------------
local Players = getService("Players")
Sim.players = {}
local PL = impl("Players")
PL.get.LocalPlayer = function()
	if currentSide() == "client" then
		return Sim.localPlayer
	end
	return nil
end
PL.methods.GetPlayers = function()
	local out = {}
	for _, c in D[Players].children do
		if D[c].cls == "Player" then
			table.insert(out, c)
		end
	end
	return out
end
PL.methods.GetPlayerByUserId = function(self, id)
	for _, p in PL.methods.GetPlayers() do
		if D[p].props.UserId == id then
			return p
		end
	end
	return nil
end
PL.methods.GetNameFromUserIdAsync = function(self, id)
	Sim.task.wait(0.05)
	error("HTTP 400 (mock: no web access)")
end
PL.methods.GetUserIdFromNameAsync = function()
	error("HTTP 400")
end
local PLY = impl("Player")
PLY.methods.Kick = function(self, msg)
	Sim.report("kick", "Player " .. tostring(D[self].props.Name) .. " kicked: " .. tostring(msg), debug.traceback("", 2))
	Sim.removePlayer(self)
end
PLY.methods.IsFriendsWithAsync = function(self, id)
	Sim.task.wait(0.05)
	return false
end
PLY.methods.GetFriendsOnline = function()
	return {}
end
PLY.methods.GetJoinData = function()
	return {}
end
PLY.methods.LoadCharacter = function(self)
	Sim.spawnCharacter(self)
end
PLY.methods.GetRankInGroup = function()
	return 0
end
PLY.methods.IsInGroup = function()
	return false
end

-- RunService -----------------------------------------------------------------------
local RS = getService("RunService")
local RSI = impl("RunService")
RSI.methods.IsServer = function()
	return currentSide() == "server"
end
RSI.methods.IsClient = function()
	return currentSide() == "client"
end
RSI.methods.IsStudio = function()
	return true
end
RSI.methods.IsRunning = function()
	return true
end
RSI.methods.IsRunMode = function()
	return false
end
RSI.methods.IsEdit = function()
	return false
end
Sim.renderBound = {}
RSI.methods.BindToRenderStep = function(self, name, prio, fn)
	if currentSide() ~= "client" then
		Sim.misuse("BindToRenderStep can only be called from a LocalScript")
	end
	Sim.renderBound[name] = fn
end
RSI.methods.UnbindFromRenderStep = function(self, name)
	Sim.renderBound[name] = nil
end
local renderSignal = Sim.getSignal(RS, D[RS], "RenderStepped")
renderSignal._onConnect = function(sig, c)
	if c.side ~= "client" then
		Sim.report("api", "RenderStepped connected from server code (RenderStepped event can only be used from local scripts)", debug.traceback("", 3))
	end
end

-- TweenService -----------------------------------------------------------------------
local TWEENABLE = { number = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim2 = true, UDim = true, Rect = true, NumberRange = true, boolean = true }
local TS = impl("TweenService")
TS.methods.Create = function(self, inst, info, goals)
	if not Sim.isInstance(inst) then
		Sim.misuse("TweenService:Create: Argument 1 must be an Instance")
	end
	if Sim.typeof(info) ~= "TweenInfo" then
		Sim.misuse("TweenService:Create: Argument 2 must be a TweenInfo")
	end
	if rawtype(goals) ~= "table" then
		Sim.misuse("TweenService:Create: Argument 3 must be a table")
	end
	local d = D[inst]
	for k, v in goals do
		local m = member(d.cls, k)
		if not m or m[1] ~= "prop" then
			Sim.misuse(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a 'nil', but given type is '%s') on %s", tostring(k), Sim.typeof(v), d.cls))
		end
		local t = Sim.typeof(v)
		if not TWEENABLE[t] then
			Sim.misuse(string.format("TweenService:Create no property named '%s' for object '%s' (type %s not tweenable)", k, tostring(d.props.Name), t))
		end
		if t == "boolean" then
			-- booleans are allowed (switch at end)
		end
		local cur = inst[k]
		if Sim.typeof(cur) ~= t then
			Sim.misuse(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", k, Sim.typeof(cur), t))
		end
	end
	local tw = Sim.newInstance("Tween")
	local td = D[tw]
	td.props.Name = "Tween"
	td.tweenTarget = inst
	td.tweenInfo = info
	td.tweenGoals = goals
	return tw
end
local TW = impl("Tween")
TW.methods.Play = function(self)
	local td = D[self]
	if td.playing then
		return
	end
	td.playing = true
	td.token = (td.token or 0) + 1
	local token = td.token
	local info = td.tweenInfo
	local total = info.Time * (1 + math.max(info.RepeatCount, 0)) * (if info.Reverses then 2 else 1) + info.DelayTime
	Sim.task.delay(total, function()
		if td.token ~= token or not td.playing then
			return
		end
		td.playing = false
		local target = td.tweenTarget
		for k, v in td.tweenGoals do
			if not D[target].destroyed or true then
				local ok, err = pcall(function()
					target[k] = if info.Reverses then target[k] else v
				end)
				if not ok then
					Sim.report("api", "tween apply failed: " .. tostring(err), "")
				end
			end
		end
		td.props.PlaybackState = Sim.Enum.PlaybackState.Completed
		fireIf(td, "Completed", Sim.Enum.PlaybackState.Completed)
	end)
end
TW.methods.Cancel = function(self)
	local td = D[self]
	if td.playing then
		td.playing = false
		fireIf(td, "Completed", Sim.Enum.PlaybackState.Cancelled)
	end
end
TW.methods.Pause = function(self)
	D[self].playing = false
end

-- Debris ------------------------------------------------------------------------------
impl("Debris").methods.AddItem = function(self, inst, life)
	if not Sim.isInstance(inst) then
		Sim.misuse("Debris:AddItem: Instance expected")
	end
	Sim.task.delay(life or 10, function()
		if not D[inst].destroyed then
			Sim.destroy(inst)
		end
	end)
end

-- DataStores (Studio without API access: every request errors) ------------------------
local DSS = impl("DataStoreService")
local function makeStore(cls, name)
	if rawtype(name) ~= "string" or #name == 0 or #name > 50 then
		Sim.misuse("DataStore name must be 1-50 characters: " .. tostring(name))
	end
	local s = Sim.newInstance(cls)
	D[s].props.Name = name
	return s
end
DSS.methods.GetDataStore = function(self, name, scope)
	if currentSide() ~= "server" then
		Sim.misuse("DataStoreService can only be used from the server")
	end
	return makeStore("DataStore", name)
end
DSS.methods.GetOrderedDataStore = function(self, name, scope)
	return makeStore("OrderedDataStore", name)
end
DSS.methods.GetGlobalDataStore = function(self)
	return makeStore("DataStore", "global")
end
local function dsError(self, key)
	if rawtype(key) ~= "string" or #key == 0 or #key > 50 then
		Sim.misuse("DataStore key must be 1-50 characters: " .. tostring(key))
	end
	Sim.dsCalls = (Sim.dsCalls or 0) + 1
	Sim.task.wait(0.05)
	error("502: API Services rejected request with error. HTTP 403 (Forbidden)", 2)
end
for _, cls in { "GlobalDataStore", "DataStore", "OrderedDataStore" } do
	local x = impl(cls)
	x.methods.UpdateAsync = function(self, key, fn)
		if rawtype(fn) ~= "function" then
			Sim.misuse("UpdateAsync: function expected")
		end
		dsError(self, key)
	end
	x.methods.GetAsync = dsError
	x.methods.SetAsync = dsError
	x.methods.IncrementAsync = dsError
	x.methods.RemoveAsync = dsError
end
impl("OrderedDataStore").methods.GetSortedAsync = function(self, asc, pageSize)
	if rawtype(pageSize) ~= "number" or pageSize < 1 or pageSize > 100 then
		Sim.misuse("GetSortedAsync: pageSize must be 1-100")
	end
	Sim.task.wait(0.05)
	error("502: API Services rejected request with error. HTTP 403 (Forbidden)", 2)
end

-- Messaging / Marketplace / Physics / Http / Social / TextChat ---------------------------
local MS = impl("MessagingService")
MS.methods.PublishAsync = function(self, topic, msg)
	error("MessagingService is not available in Studio (mock)", 2)
end
MS.methods.SubscribeAsync = function(self, topic, fn)
	error("MessagingService is not available in Studio (mock)", 2)
end
local MKT = impl("MarketplaceService")
Sim.prompts = {}
MKT.methods.UserOwnsGamePassAsync = function(self, userId, passId)
	Sim.task.wait(0.05)
	return false
end
MKT.methods.PromptGamePassPurchase = function(self, player, id)
	table.insert(Sim.prompts, { "pass", id })
end
MKT.methods.PromptProductPurchase = function(self, player, id)
	table.insert(Sim.prompts, { "product", id })
end
MKT.methods.GetProductInfo = function()
	return {}
end
local PHY = impl("PhysicsService")
Sim.collisionGroups = { Default = true }
Sim.collidable = {}
PHY.methods.RegisterCollisionGroup = function(self, name)
	Sim.collisionGroups[name] = true
end
PHY.methods.IsCollisionGroupRegistered = function(self, name)
	return Sim.collisionGroups[name] == true
end
PHY.methods.CollisionGroupSetCollidable = function(self, a, b, c)
	if not Sim.collisionGroups[a] or not Sim.collisionGroups[b] then
		Sim.misuse("CollisionGroupSetCollidable: collision group does not exist (" .. tostring(a) .. ", " .. tostring(b) .. ")")
	end
	Sim.collidable[a .. "|" .. b] = c
	Sim.collidable[b .. "|" .. a] = c
end
local function groupsCollide(a, b)
	local v = Sim.collidable[a .. "|" .. b]
	if v == nil then
		return true
	end
	return v
end
PHY.methods.CollisionGroupsAreCollidable = function(self, a, b)
	return groupsCollide(a, b)
end
PHY.methods.GetRegisteredCollisionGroups = function()
	local out = {}
	for g in Sim.collisionGroups do
		table.insert(out, { name = g })
	end
	return out
end
local guid = 0
impl("HttpService").methods.GenerateGUID = function(self, braces)
	guid += 1
	return string.format("%08x-0000-4000-8000-%012x", guid, guid)
end
impl("HttpService").methods.JSONEncode = function(self, v)
	return "{}"
end
impl("SocialService").methods.CanSendGameInviteAsync = function()
	return false
end
impl("SocialService").methods.PromptGameInvite = function() end
impl("StarterGui").methods.SetCore = function(self, name, value)
	if currentSide() ~= "client" then
		Sim.misuse("SetCore can only be called from a LocalScript")
	end
end
impl("StarterGui").methods.SetCoreGuiEnabled = function() end
impl("StarterGui").methods.GetCore = function()
	return nil
end

-- UserInputService / ContextActionService ---------------------------------------------
local UIS = impl("UserInputService")
UIS.get.TouchEnabled = function()
	return false
end
UIS.get.KeyboardEnabled = function()
	return true
end
UIS.get.MouseEnabled = function()
	return true
end
UIS.get.GamepadEnabled = function()
	return false
end
UIS.methods.GetLastInputType = function()
	return Sim.Enum.UserInputType.Keyboard
end
local CAS = impl("ContextActionService")
Sim.actions = {}
local function bindAction(name, fn, button, ...)
	if currentSide() ~= "client" then
		Sim.misuse("ContextActionService is client-only")
	end
	if rawtype(name) ~= "string" or rawtype(fn) ~= "function" or rawtype(button) ~= "boolean" then
		Sim.misuse("BindAction(name: string, fn: function, createTouchButton: boolean, ...inputs) expected")
	end
	for i = 1, select("#", ...) do
		local inp = select(i, ...)
		if Sim.typeof(inp) ~= "EnumItem" then
			Sim.misuse("BindAction: input #" .. i .. " must be an Enum.KeyCode / Enum.UserInputType")
		end
	end
	Sim.actions[name] = fn
end
CAS.methods.BindAction = function(self, name, fn, button, ...)
	bindAction(name, fn, button, ...)
end
CAS.methods.BindActionAtPriority = function(self, name, fn, button, prio, ...)
	if rawtype(prio) ~= "number" then
		Sim.misuse("BindActionAtPriority: priority must be a number")
	end
	bindAction(name, fn, button, ...)
end
CAS.methods.UnbindAction = function(self, name)
	Sim.actions[name] = nil
end
CAS.methods.SetTitle = function(self, name, title)
	if rawtype(title) ~= "string" then
		Sim.misuse("SetTitle: string expected")
	end
end
CAS.methods.SetPosition = function(self, name, pos)
	if Sim.typeof(pos) ~= "UDim2" then
		Sim.misuse("SetPosition: UDim2 expected")
	end
end
CAS.methods.SetImage = function() end
CAS.methods.GetButton = function()
	return nil
end

-- Remotes & bindables -----------------------------------------------------------------------
local function remoteCopy(v, path, seen)
	local t = Sim.typeof(v)
	if t == "function" then
		Sim.report("remote", "function passed through a remote at " .. path .. " (becomes nil)", debug.traceback("", 4))
		return nil
	end
	if t ~= "table" then
		return v
	end
	seen = seen or {}
	if seen[v] then
		Sim.report("remote", "cyclic table passed through a remote at " .. path, debug.traceback("", 4))
		return nil
	end
	seen[v] = true
	if getmetatable(v) ~= nil then
		Sim.report("remote", "table with metatable passed through a remote at " .. path .. " (metatable lost)", debug.traceback("", 4))
	end
	local n = #v
	local hasStr, hasOther = false, false
	for k in v do
		if rawtype(k) == "number" and k >= 1 and k <= n and k % 1 == 0 then
			-- array part
		elseif rawtype(k) == "string" then
			hasStr = true
		else
			hasOther = true
		end
	end
	if hasOther then
		Sim.report("remote", "table with non-string, non-array keys passed through a remote at " .. path .. " (keys will be dropped/converted)", debug.traceback("", 4))
	end
	if hasStr and n > 0 then
		Sim.report("remote", "mixed array/dictionary table passed through a remote at " .. path .. " (data loss)", debug.traceback("", 4))
	end
	local out = {}
	for k, val in v do
		out[k] = remoteCopy(val, path .. "." .. tostring(k), seen)
	end
	return out
end
local function copyArgs(name, ...)
	local n = select("#", ...)
	local args = table.pack(...)
	local out = { n = n }
	for i = 1, n do
		out[i] = remoteCopy(args[i], name .. "#" .. i)
	end
	return out
end
Sim.copyArgs = copyArgs

local function queuedFire(d, sigName, args)
	local s = Sim.getSignal(nil, d, sigName)
	if #s._conns == 0 then
		d.queue = d.queue or {}
		d.queue[sigName] = d.queue[sigName] or {}
		table.insert(d.queue[sigName], args)
		if not s._onConnect then
			s._onConnect = function(sig)
				local q = d.queue[sigName]
				d.queue[sigName] = nil
				if q then
					Sim.task.defer(function()
						for _, a in q do
							sig:_fire(table.unpack(a, 1, a.n))
						end
					end)
				end
			end
		end
		return
	end
	s:_fire(table.unpack(args, 1, args.n))
end

local RE = impl("RemoteEvent")
RE.methods.FireServer = function(self, ...)
	if currentSide() ~= "client" then
		Sim.misuse("FireServer can only be called from the client")
	end
	local d = D[self]
	local player = Sim.localPlayer
	local args = copyArgs(d.props.Name, ...)
	table.insert(Sim.remoteLog, { dir = "C->S", name = d.props.Name, t = Sim.now, player = player, args = args })
	local packed = table.pack(player, table.unpack(args, 1, args.n))
	local co = Sim.newThread(function()
		queuedFire(d, "OnServerEvent", packed)
	end, "server")
	Sim.resume(co)
end
local function deliverToClient(self, d, player, args)
	table.insert(Sim.remoteLog, { dir = "S->C", name = d.props.Name, t = Sim.now, player = player, args = args })
	if player == Sim.localPlayer and Sim.clientStarted then
		local co = Sim.newThread(function()
			queuedFire(d, "OnClientEvent", args)
		end, "client")
		Sim.resume(co)
	end
end
RE.methods.FireClient = function(self, player, ...)
	if currentSide() ~= "server" then
		Sim.misuse("FireClient can only be called from the server")
	end
	if not Sim.isInstance(player) or D[player].cls ~= "Player" then
		Sim.misuse("FireClient: Argument 1 must be a Player (got " .. Sim.typeof(player) .. ")")
	end
	local d = D[self]
	deliverToClient(self, d, player, copyArgs(d.props.Name, ...))
end
RE.methods.FireAllClients = function(self, ...)
	if currentSide() ~= "server" then
		Sim.misuse("FireAllClients can only be called from the server")
	end
	local d = D[self]
	local args = copyArgs(d.props.Name, ...)
	for _, p in PL.methods.GetPlayers() do
		deliverToClient(self, d, p, args)
	end
end
local RF = impl("RemoteFunction")
RF.methods.InvokeServer = function(self, ...)
	if currentSide() ~= "client" then
		Sim.misuse("InvokeServer can only be called from the client")
	end
	local d = D[self]
	local args = copyArgs(d.props.Name, ...)
	while not d.props.OnServerInvoke do
		Sim.task.wait(0.1)
	end
	local result
	local done = false
	local co = Sim.newThread(function()
		local r = table.pack(pcall(d.props.OnServerInvoke, Sim.localPlayer, table.unpack(args, 1, args.n)))
		result = r
		done = true
	end, "server")
	Sim.resume(co)
	while not done do
		Sim.task.wait(1 / 60)
	end
	if not result[1] then
		error(result[2], 2)
	end
	local out = copyArgs("InvokeServer result", table.unpack(result, 2, result.n))
	return table.unpack(out, 1, out.n)
end
local BE = impl("BindableEvent")
BE.methods.Fire = function(self, ...)
	local d = D[self]
	Sim.getSignal(self, d, "Event"):_fire(...)
end
local BF = impl("BindableFunction")
BF.methods.Invoke = function(self, ...)
	local f = D[self].props.OnInvoke
	if not f then
		error("BindableFunction has no OnInvoke", 2)
	end
	return f(...)
end

-- Sound / particles / prompts / gui bits ------------------------------------------------------
local SND = impl("Sound")
SND.methods.Play = function(self)
	local d = D[self]
	d.props.Playing = true
	if not D[self].parent then
		return
	end
	Sim.task.delay(0.6, function()
		if not d.destroyed then
			d.props.Playing = false
			fireIf(d, "Ended", d.props.SoundId or "")
		end
	end)
end
SND.methods.Stop = function(self)
	D[self].props.Playing = false
end
SND.methods.Pause = SND.methods.Stop
SND.methods.Resume = SND.methods.Play
SND.get.IsPlaying = function(inst, d)
	return d.props.Playing == true
end
SND.get.TimeLength = function()
	return 0.6
end
local PE = impl("ParticleEmitter")
PE.methods.Emit = function(self, n)
	if rawtype(n) ~= "number" then
		Sim.misuse("Emit: number expected")
	end
end
PE.methods.Clear = function() end
impl("ProximityPrompt").methods.InputHoldBegin = function() end
impl("ProximityPrompt").methods.InputHoldEnd = function() end
local GB = impl("GuiBase2d")
GB.get.AbsoluteSize = function()
	return Sim.types.Vector2.new(100, 100)
end
GB.get.AbsolutePosition = function()
	return Sim.types.Vector2.zero
end
GB.get.AbsoluteRotation = function()
	return 0
end
impl("UIListLayout").get.AbsoluteContentSize = function()
	return Sim.types.Vector2.new(100, 100)
end
impl("UIGridStyleLayout").get.AbsoluteContentSize = function()
	return Sim.types.Vector2.new(100, 100)
end
impl("TextLabel").get.TextBounds = function()
	return Sim.types.Vector2.new(50, 14)
end
impl("TextBox").methods.CaptureFocus = function() end
impl("TextBox").methods.ReleaseFocus = function() end
impl("GuiObject").methods.TweenSize = function()
	return true
end
impl("GuiObject").methods.TweenPosition = function()
	return true
end
impl("Camera").get.ViewportSize = function()
	return Sim.types.Vector2.new(1920, 1080)
end
impl("Camera").methods.WorldToViewportPoint = function(self, p)
	return Vector3.new(0, 0, 1), true
end
impl("Camera").methods.WorldToScreenPoint = function(self, p)
	return Vector3.new(0, 0, 1), true
end
local HUM = impl("Humanoid")
HUM.methods.TakeDamage = function(self, n)
	self.Health = math.max(0, self.Health - n)
end
HUM.methods.MoveTo = function() end
HUM.methods.ChangeState = function() end
HUM.methods.GetState = function()
	return Sim.Enum.HumanoidStateType.Running
end
HUM.methods.SetStateEnabled = function() end
HUM.get.RootPart = function(inst, d)
	local ch = d.parent
	return ch and ch:FindFirstChild("HumanoidRootPart")
end
impl("Constraint").methods.GetConstraints = nil

-- Raycasting ----------------------------------------------------------------------------------
local RPMT = { __type = "RaycastParams" }
local RPFIELDS = { FilterType = true, FilterDescendantsInstances = true, CollisionGroup = true, IgnoreWater = true, RespectCanCollide = true, BruteForceAllSlow = true }
RPMT.__index = function(t, k)
	if k == "AddToFilter" then
		return function(self, x)
			local list = rawget(self, "_f").FilterDescendantsInstances
			if Sim.isInstance(x) then
				table.insert(list, x)
			else
				for _, y in x do
					table.insert(list, y)
				end
			end
		end
	end
	if not RPFIELDS[k] then
		error(tostring(k) .. " is not a valid member of RaycastParams", 2)
	end
	return rawget(t, "_f")[k]
end
RPMT.__newindex = function(t, k, v)
	if not RPFIELDS[k] then
		Sim.misuse(tostring(k) .. " is not a valid member of RaycastParams")
	end
	if k == "FilterDescendantsInstances" then
		if rawtype(v) ~= "table" then
			Sim.misuse("FilterDescendantsInstances must be an array of Instances")
		end
		for i, x in v do
			if not Sim.isInstance(x) then
				Sim.misuse("FilterDescendantsInstances[" .. tostring(i) .. "] is not an Instance (" .. Sim.typeof(x) .. ")")
			end
		end
		v = table.clone(v)
	elseif k == "FilterType" then
		if Sim.typeof(v) ~= "EnumItem" or rawget(v, "EnumType") ~= Sim.Enum.RaycastFilterType then
			Sim.misuse("FilterType must be Enum.RaycastFilterType")
		end
	elseif k == "CollisionGroup" then
		if rawtype(v) ~= "string" then
			Sim.misuse("CollisionGroup must be a string")
		end
	end
	rawget(t, "_f")[k] = v
end
local RaycastParams = {
	new = function()
		return setmetatable({ _f = { FilterType = Sim.Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, CollisionGroup = "Default", IgnoreWater = false, RespectCanCollide = false } }, RPMT)
	end,
}
Sim.types.RaycastParams = RaycastParams
local RRMT = { __type = "RaycastResult" }
RRMT.__index = function(t, k)
	error(tostring(k) .. " is not a valid member of RaycastResult", 2)
end

local CELL = 32
local index = nil
local function aabb(part, d)
	local c = d.props.CFrame or Sim.types.CFrame.identity
	local s = (d.props.Size or Vector3.new(4, 1, 2)) / 2
	local ex = math.abs(c.rx.X) * s.X + math.abs(c.ry.X) * s.Y + math.abs(c.rz.X) * s.Z
	local ey = math.abs(c.rx.Y) * s.X + math.abs(c.ry.Y) * s.Y + math.abs(c.rz.Y) * s.Z
	local ez = math.abs(c.rx.Z) * s.X + math.abs(c.ry.Z) * s.Y + math.abs(c.rz.Z) * s.Z
	return c.p.X - ex, c.p.Y - ey, c.p.Z - ez, c.p.X + ex, c.p.Y + ey, c.p.Z + ez
end
local function rebuildIndex()
	index = {}
	local count = 0
	for _, x in descendants(workspace) do
		local d = D[x]
		if d.isBasePart and d.props.CanQuery ~= false then
			local x0, _, z0, x1, _, z1 = aabb(x, d)
			for cx = math.floor(x0 / CELL), math.floor(x1 / CELL) do
				for cz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
					local k = cx * 100003 + cz
					index[k] = index[k] or {}
					table.insert(index[k], x)
				end
			end
			count += 1
		end
	end
	Sim.raycastDirty = false
	Sim.indexCount = count
end
local function rayPart(part, d, o, dir)
	-- returns t (0..1 along dir), normal (world) or nil
	local c = d.props.CFrame or Sim.types.CFrame.identity
	local inv = c:Inverse()
	local lo = inv * o
	local ld = Sim.cf(Vector3.zero, inv.rx, inv.ry, inv.rz) * dir
	local h = (d.props.Size or Vector3.new(4, 1, 2)) / 2
	local t0, t1 = 0, 1
	local nAxis, nSign = nil, 0
	for _, ax in { "X", "Y", "Z" } do
		local oo, dd, hh = lo[ax], ld[ax], h[ax]
		if math.abs(dd) < 1e-12 then
			if oo < -hh or oo > hh then
				return nil
			end
		else
			local a, b = (-hh - oo) / dd, (hh - oo) / dd
			local sgn = -1
			if a > b then
				a, b = b, a
				sgn = 1
			end
			if a > t0 then
				t0 = a
				nAxis = ax
				nSign = sgn
			end
			t1 = math.min(t1, b)
			if t0 > t1 then
				return nil
			end
		end
	end
	local shape = if d.cls == "Part" then (d.props.Shape and d.props.Shape.Name or "Block") else (if d.cls == "WedgePart" then "Wedge" else "Block")
	local function worldN(ln)
		return (Sim.cf(Vector3.zero, c.rx, c.ry, c.rz) * ln).Unit
	end
	if shape == "Block" then
		if not nAxis then
			return 0, worldN(Vector3.new(0, 1, 0))
		end
		local ln = Vector3.new(if nAxis == "X" then nSign else 0, if nAxis == "Y" then nSign else 0, if nAxis == "Z" then nSign else 0)
		return t0, worldN(ln)
	elseif shape == "Ball" then
		local r = h.X
		local a = ld:Dot(ld)
		local b = 2 * lo:Dot(ld)
		local cc = lo:Dot(lo) - r * r
		local disc = b * b - 4 * a * cc
		if disc < 0 then
			return nil
		end
		local t = (-b - math.sqrt(disc)) / (2 * a)
		if t < 0 or t > 1 then
			return nil
		end
		return t, worldN((lo + ld * t).Unit)
	elseif shape == "Cylinder" then
		-- caps along local X, radius h.Y
		local r = math.min(h.Y, h.Z)
		local best, bn = nil, nil
		for _, sx in { -1, 1 } do
			if math.abs(ld.X) > 1e-12 then
				local t = (sx * h.X - lo.X) / ld.X
				if t >= 0 and t <= 1 then
					local p = lo + ld * t
					if p.Y * p.Y + p.Z * p.Z <= r * r and (not best or t < best) then
						best, bn = t, Vector3.new(sx, 0, 0)
					end
				end
			end
		end
		local a = ld.Y * ld.Y + ld.Z * ld.Z
		if a > 1e-12 then
			local b = 2 * (lo.Y * ld.Y + lo.Z * ld.Z)
			local cc = lo.Y * lo.Y + lo.Z * lo.Z - r * r
			local disc = b * b - 4 * a * cc
			if disc >= 0 then
				local t = (-b - math.sqrt(disc)) / (2 * a)
				if t >= 0 and t <= 1 then
					local p = lo + ld * t
					if math.abs(p.X) <= h.X and (not best or t < best) then
						best, bn = t, Vector3.new(0, p.Y, p.Z).Unit
					end
				end
			end
		end
		if lo.Y * lo.Y + lo.Z * lo.Z <= r * r and math.abs(lo.X) <= h.X then
			return 0, worldN(Vector3.new(0, 1, 0))
		end
		if best then
			return best, worldN(bn)
		end
		return nil
	elseif shape == "Wedge" then
		local function f(t)
			local y = lo.Y + ld.Y * t
			local z = lo.Z + ld.Z * t
			return y / h.Y - z / h.Z
		end
		if f(t0) <= 0 then
			if not nAxis then
				return 0, worldN(Vector3.new(0, 1, 0))
			end
			local ln = Vector3.new(if nAxis == "X" then nSign else 0, if nAxis == "Y" then nSign else 0, if nAxis == "Z" then nSign else 0)
			return t0, worldN(ln)
		elseif f(t1) <= 0 then
			-- crosses the slope plane
			local a, b = f(t0), f(t1)
			local t = t0 + (t1 - t0) * a / (a - b)
			return t, worldN(Vector3.new(0, h.Z, -h.Y).Unit)
		end
		return nil
	end
	return t0, worldN(Vector3.new(0, 1, 0))
end
local function raycast(origin, dir, params)
	if not Sim.isV3(origin) or not Sim.isV3(dir) then
		Sim.misuse("Raycast: Vector3 origin and direction expected")
	end
	if params ~= nil and Sim.typeof(params) ~= "RaycastParams" then
		Sim.misuse("Raycast: RaycastParams expected")
	end
	if Sim.raycastDirty or not index then
		rebuildIndex()
	end
	local f = params and rawget(params, "_f") or { FilterType = Sim.Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, CollisionGroup = "Default", RespectCanCollide = false }
	local include = f.FilterType == Sim.Enum.RaycastFilterType.Include
	local function filtered(x)
		for _, root in f.FilterDescendantsInstances do
			if x == root or isDescendantOf(x, root) then
				return true
			end
		end
		return false
	end
	local e = origin + dir
	local x0, x1 = math.min(origin.X, e.X), math.max(origin.X, e.X)
	local z0, z1 = math.min(origin.Z, e.Z), math.max(origin.Z, e.Z)
	local seen = {}
	local bestT, bestPart, bestN = math.huge, nil, nil
	for cx = math.floor(x0 / CELL), math.floor(x1 / CELL) do
		for cz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
			for _, part in index[cx * 100003 + cz] or {} do
				if not seen[part] then
					seen[part] = true
					local d = D[part]
					if d.parent and not d.destroyed and d.props.CanQuery ~= false then
						local ok = true
						if f.RespectCanCollide and d.props.CanCollide == false then
							ok = false
						end
						if ok and not groupsCollide(f.CollisionGroup or "Default", d.props.CollisionGroup or "Default") then
							ok = false
						end
						if ok then
							local isF = filtered(part)
							if (include and not isF) or (not include and isF) then
								ok = false
							end
						end
						if ok then
							local t, n = rayPart(part, d, origin, dir)
							if t and t < bestT then
								bestT, bestPart, bestN = t, part, n
							end
						end
					end
				end
			end
		end
	end
	if not bestPart then
		return nil
	end
	local pos = origin + dir * bestT
	return table.freeze(setmetatable({ Instance = bestPart, Position = pos, Normal = bestN, Material = bestPart.Material, Distance = dir.Magnitude * bestT }, RRMT))
end
Sim.raycast = raycast
WS.methods.Raycast = function(self, o, d, p)
	return raycast(o, d, p)
end
WS.methods.GetPartBoundsInRadius = function()
	return {}
end
WS.methods.GetPartsInPart = function()
	return {}
end
WS.methods.GetPartBoundsInBox = function()
	return {}
end

-- Ball physics: integrate unanchored parts in workspace.GolfBalls ----------------------------
function Sim.physicsStep(dt)
	local folder = workspace:FindFirstChild("GolfBalls")
	if not folder then
		return
	end
	local g = workspace.Gravity
	for _, ball in D[folder].children do
		local d = D[ball]
		d.inBallFolder = true
		if d.isBasePart and not d.props.Anchored and not d.destroyed then
			local v = d.props.AssemblyLinearVelocity or Vector3.zero
			local c = d.props.CFrame or Sim.types.CFrame.identity
			local r = (d.props.Size or Vector3.one).Y / 2
			v = v - Vector3.new(0, g * dt, 0)
			local pos = c.p + v * dt
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { folder }
			params.RespectCanCollide = true
			params.CollisionGroup = d.props.CollisionGroup or "Default"
			local hit = raycast(c.p + Vector3.new(0, r, 0), Vector3.new(0, -(2 * r + math.abs(v.Y * dt) + 0.3), 0) + Vector3.new(v.X * dt, 0, v.Z * dt), params)
			if hit and pos.Y - r <= hit.Position.Y + 0.01 then
				pos = Vector3.new(pos.X, hit.Position.Y + r, pos.Z)
				if v.Y < 0 then
					v = Vector3.new(v.X, 0, v.Z)
				end
			end
			d.props.CFrame = Sim.cf(pos, c.rx, c.ry, c.rz)
			d.props.AssemblyLinearVelocity = v
		end
	end
end

Sim.Players = Players
Sim.RunService = RS
Sim.groupsCollide = groupsCollide

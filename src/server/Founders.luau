--!strict
-- Giant founders, scaled up into giants the server can move around.
--  * Admin abuse: each founder's normal Roblox avatar (from the UserId or
--    Username in Config.Founders). Founders without one don't appear.
--  * Their own events: their special event look. In order:
--      1. the look they saved with "Save My Event Look" in the admin panel
--         (an exact copy of their character at that moment, kept forever),
--      2. the outfit id in Config.FounderEvents (OutfitId),
--      3. their character right now, if they're in this server,
--      4. their Roblox avatar,
--      5. for Corny, a look-alike built from parts.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Founders = {}

local userIds: { [string]: number } = {}
local descriptions: { [number]: HumanoidDescription } = {}

local function resolveUserId(founder: Config.Founder): number?
	if founder.UserId > 0 then
		return founder.UserId
	end
	if userIds[founder.Id] then
		return userIds[founder.Id]
	end
	if founder.Username ~= "" then
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(founder.Username)
		end)
		if ok and type(id) == "number" then
			userIds[founder.Id] = id
			return id
		end
	end
	return nil
end

local function description(userId: number): HumanoidDescription?
	if descriptions[userId] then
		return descriptions[userId]
	end
	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if ok and result then
		descriptions[userId] = result
		return result
	end
	return nil
end

-- Saved event looks ------------------------------------------------------------
-- A HumanoidDescription can't go in a DataStore, so its properties are
-- copied into a plain table and back.

-- GetDataStore errors in places that aren't published (or don't allow API
-- access in Studio); then looks just aren't saved between servers.
local lookStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("BrainrotHeistFounderLooks")
	end)
	if ok then
		lookStore = result
	end
end
local savedLooks: { [string]: HumanoidDescription } = {}

local NUMBER_PROPERTIES = {
	"BodyTypeScale", "DepthScale", "HeadScale", "HeightScale", "ProportionScale", "WidthScale",
	"Face", "Head", "LeftArm", "LeftLeg", "RightArm", "RightLeg", "Torso",
	"GraphicTShirt", "Pants", "Shirt",
	"ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation", "MoodAnimation",
}
local COLOR_PROPERTIES = { "HeadColor", "LeftArmColor", "LeftLegColor", "RightArmColor", "RightLegColor", "TorsoColor" }

local function serialize(desc: HumanoidDescription): { [string]: any }
	local data: { [string]: any } = { Numbers = {}, Colors = {}, Accessories = {} }
	for _, name in NUMBER_PROPERTIES do
		data.Numbers[name] = (desc :: any)[name]
	end
	for _, name in COLOR_PROPERTIES do
		data.Colors[name] = ((desc :: any)[name] :: Color3):ToHex()
	end
	for _, accessory in desc:GetAccessories(true) do
		table.insert(data.Accessories, {
			AssetId = accessory.AssetId,
			AccessoryType = accessory.AccessoryType.Name,
			IsLayered = accessory.IsLayered,
			Order = accessory.Order,
			Puffiness = accessory.Puffiness,
		})
	end
	return data
end

local function deserialize(data: any): HumanoidDescription?
	if type(data) ~= "table" or type(data.Numbers) ~= "table" then
		return nil
	end
	local desc = Instance.new("HumanoidDescription")
	pcall(function()
		for _, name in NUMBER_PROPERTIES do
			if type(data.Numbers[name]) == "number" then
				(desc :: any)[name] = data.Numbers[name]
			end
		end
		for _, name in COLOR_PROPERTIES do
			if type(data.Colors[name]) == "string" then
				(desc :: any)[name] = Color3.fromHex(data.Colors[name])
			end
		end
		local accessories = {}
		for _, entry in data.Accessories do
			local accessoryType = (Enum.AccessoryType :: any)[entry.AccessoryType]
			if type(entry.AssetId) == "number" and accessoryType then
				table.insert(accessories, {
					AssetId = entry.AssetId,
					AccessoryType = accessoryType,
					IsLayered = entry.IsLayered == true,
					Order = entry.Order,
					Puffiness = entry.Puffiness,
				})
			end
		end
		desc:SetAccessories(accessories, true)
	end)
	return desc
end

-- Event music a founder pasted in the admin panel (an uploaded sound id),
-- saved for good. Shared with clients as ReplicatedStorage attributes
-- "EventMusic_<eventId>"; empty means the event's MusicId in Config.
function Founders.LoadEventMusic()
	local store = lookStore
	if not store then
		return
	end
	for eventId in Config.FounderEvents do
		local ok, id = pcall(function()
			return store:GetAsync("music_" .. eventId)
		end)
		if ok and type(id) == "number" then
			ReplicatedStorage:SetAttribute("EventMusic_" .. eventId, if id > 0 then "rbxassetid://" .. id else "")
		end
	end
end

-- Saves a founder event's music (0 = back to the default). Returns whether
-- it was saved for every server (it's used in this one either way).
function Founders.SaveEventMusic(eventId: string, soundId: number): boolean
	ReplicatedStorage:SetAttribute("EventMusic_" .. eventId, if soundId > 0 then "rbxassetid://" .. soundId else "")
	local store = lookStore
	if not store then
		return false
	end
	return (pcall(function()
		store:SetAsync("music_" .. eventId, soundId)
	end))
end

-- Loads the saved event looks (call once when the server starts).
function Founders.LoadEventLooks()
	for _, founder in Config.Founders do
		local store = lookStore
		if not store then
			return
		end
		local ok, data = pcall(function()
			return store:GetAsync("look_" .. founder.Id)
		end)
		local desc = if ok then deserialize(data) else nil
		if desc then
			savedLooks[founder.Id] = desc
		end
	end
end

-- Saves a founder's current character as their event look, for good.
function Founders.SaveEventLook(founderId: string, character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	local ok, desc = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not desc then
		return false
	end
	savedLooks[founderId] = desc
	local store = lookStore
	if not store then
		return false
	end
	return (pcall(function()
		store:SetAsync("look_" .. founderId, serialize(desc))
	end))
end

-- Saves a costume (outfit id) as a founder's event look, for good.
function Founders.SaveEventOutfit(founderId: string, outfitId: number): boolean
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromOutfitId(outfitId)
	end)
	if not ok or not desc then
		return false
	end
	savedLooks[founderId] = desc
	local store = lookStore
	if not store then
		return true
	end
	pcall(function()
		store:SetAsync("look_" .. founderId, serialize(desc))
	end)
	return true
end

-- Forgets a founder's saved event look, so their giant wears their normal
-- avatar (or the event's own outfit) again.
function Founders.ResetEventLook(founderId: string)
	savedLooks[founderId] = nil
	local store = lookStore
	if store then
		pcall(function()
			store:RemoveAsync("look_" .. founderId)
		end)
	end
end

-- The founder's character right now, if they're in this server.
local function liveDescription(founder: Config.Founder): HumanoidDescription?
	for _, player in Players:GetPlayers() do
		local matches = if founder.UserId > 0
			then player.UserId == founder.UserId
			else founder.Username ~= "" and string.lower(player.Name) == string.lower(founder.Username)
		local humanoid = matches and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local ok, desc = pcall(function()
				return humanoid:GetAppliedDescription()
			end)
			if ok and desc then
				return desc
			end
		end
	end
	return nil
end

local function outfitDescription(outfitId: number): HumanoidDescription?
	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromOutfitId(outfitId)
	end)
	return if ok then result else nil
end

-- Look-alikes -------------------------------------------------------------

local function part(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function cylinder(model: Model, root: BasePart, name: string, height: number, diameter: number, offset: CFrame, color: Color3): Part
	local p = part(model, root, name, Vector3.new(height, diameter, diameter), offset * CFrame.Angles(0, 0, math.pi / 2), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A blocky figure, 5 studs tall, facing -Z, in Corny's outfit: black
-- suit and tie, rainbow-striped pants and shoes, pixel shades, a white
-- sprinkle top hat with a red band, and a jetpack.
local function cornyLookAlike(): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	model.PrimaryPart = root

	local skin = Color3.fromRGB(234, 200, 165)
	local suit = Color3.fromRGB(25, 25, 30)
	local pants = Color3.fromRGB(20, 20, 25)

	part(model, root, "Torso", Vector3.new(2, 2, 1), CFrame.new(), suit)
	local head = part(model, root, "Head", Vector3.new(2, 1, 1), CFrame.new(0, 1.5, 0), skin)
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	for _, side in { -1, 1 } do
		part(model, root, "Arm", Vector3.new(1, 1.6, 1), CFrame.new(side * 1.5, 0.2, 0), suit)
		part(model, root, "Hand", Vector3.new(0.9, 0.4, 0.9), CFrame.new(side * 1.5, -0.8, 0), skin)
		part(model, root, "Leg", Vector3.new(1, 2, 1), CFrame.new(side * 0.5, -2, 0), pants)
	end

	do
		-- Shirt, tie and shades
		part(model, root, "Shirt", Vector3.new(0.7, 1.1, 0.05), CFrame.new(0, 0.45, -0.51), Color3.new(1, 1, 1))
		part(model, root, "Tie", Vector3.new(0.22, 1.0, 0.06), CFrame.new(0, 0.4, -0.53), Color3.fromRGB(15, 15, 15))
		part(model, root, "Shades", Vector3.new(1.3, 0.28, 0.1), CFrame.new(0, 1.6, -0.62), Color3.fromRGB(10, 10, 10))
		for _, x in { -0.4, 0.25 } do
			part(model, root, "ShadesShine", Vector3.new(0.12, 0.1, 0.02), CFrame.new(x, 1.66, -0.68), Color3.new(1, 1, 1))
		end
		-- Rainbow stripes down the outside of each leg and around the soles
		for _, side in { -1, 1 } do
			for k = 0, 5 do
				local stripe = part(model, root, "Stripe", Vector3.new(0.12, 0.34, 0.5), CFrame.new(side * 1.0, -1.15 - k * 0.33, 0), Color3.fromHSV(k / 6, 0.9, 1), Enum.Material.Neon)
				stripe.CanCollide = false
			end
			part(model, root, "Sole", Vector3.new(1.05, 0.2, 1.1), CFrame.new(side * 0.5, -2.95, -0.02), Color3.fromHSV((side + 1) / 4, 0.9, 1), Enum.Material.Neon)
		end
		-- Sprinkle top hat with a red band
		local white = Color3.fromRGB(245, 245, 245)
		cylinder(model, root, "HatBrim", 0.15, 2.3, CFrame.new(0, 2.15, 0), white)
		cylinder(model, root, "HatBand", 0.45, 1.5, CFrame.new(0, 2.45, 0), Color3.fromRGB(205, 30, 40))
		cylinder(model, root, "HatTop", 1.6, 1.42, CFrame.new(0, 3.4, 0), white)
		local rng = Random.new(5)
		for _ = 1, 26 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local y = rng:NextNumber(2.75, 4.1)
			local sprinkle = part(model, root, "Sprinkle", Vector3.new(0.08, 0.28, 0.08), CFrame.new(math.cos(angle) * 0.72, y, math.sin(angle) * 0.72) * CFrame.Angles(0, -angle, rng:NextNumber(-1, 1)), Color3.fromHSV(rng:NextNumber(), 0.75, 1))
			sprinkle.CanCollide = false
		end
		-- Jetpack: two rockets and a red frame on the back
		part(model, root, "Jetpack", Vector3.new(1.6, 1.8, 0.5), CFrame.new(0, 0.1, 0.75), Color3.fromRGB(170, 30, 35))
		for _, side in { -1, 1 } do
			cylinder(model, root, "Rocket", 2.2, 0.6, CFrame.new(side * 0.95, 0.1, 0.9), Color3.fromRGB(70, 70, 75))
			part(model, root, "Wing", Vector3.new(0.1, 1.2, 0.9), CFrame.new(side * 1.25, -0.3, 1.1) * CFrame.Angles(0, 0, side * 0.4), Color3.fromRGB(150, 25, 30))
		end
	end
	return model
end

local function humanoidAccessories(model: Model): { Accessory }
	local list = {}
	for _, child in model:GetChildren() do
		if child:IsA("Accessory") then
			table.insert(list, child)
		end
	end
	return list
end

-- Scale fix-up ----------------------------------------------------------------
-- Model:ScaleTo doesn't reliably scale everything on newer avatars: the head
-- and the hats and hair on it could stay normal size (or get shrunk back)
-- while the body grew. So every size and offset is recorded before scaling,
-- and FixScale sets anything that ended up wrong to original x scale.

type SizeRecord = {
	Parts: { [BasePart]: Vector3 },
	Attachments: { [Attachment]: CFrame },
	Joints: { [JointInstance]: { CFrame } },
	Meshes: { [SpecialMesh]: { Vector3 } },
}
local scaleInfo: { [Model]: { Originals: SizeRecord, Scale: number } } = setmetatable({}, { __mode = "k" }) :: any

local function recordSizes(model: Model): SizeRecord
	local record: SizeRecord = { Parts = {}, Attachments = {}, Joints = {}, Meshes = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			record.Parts[d] = d.Size
		elseif d:IsA("Attachment") then
			record.Attachments[d] = d.CFrame
		elseif d:IsA("Motor6D") or d:IsA("Weld") then
			record.Joints[d] = { d.C0, d.C1 }
		elseif d:IsA("SpecialMesh") then
			record.Meshes[d] = { d.Scale, d.Offset }
		end
	end
	return record
end

local function scaled(cf: CFrame, s: number): CFrame
	return cf.Rotation + cf.Position * s
end

local function wrong(now: Vector3, expected: Vector3): boolean
	return (now - expected).Magnitude > math.max(0.05, expected.Magnitude * 0.05)
end

-- Makes sure every part, attachment, joint and mesh of a giant is its
-- original size x the giant's scale. Safe to call again later.
function Founders.FixScale(giant: Model)
	local info = scaleInfo[giant]
	if not info then
		return
	end
	local s = info.Scale
	local o = info.Originals
	for part, size in o.Parts do
		if part.Parent and wrong(part.Size, size * s) then
			part.Size = size * s
		end
	end
	for attachment, cf in o.Attachments do
		if attachment.Parent and wrong(attachment.CFrame.Position, cf.Position * s) then
			attachment.CFrame = scaled(cf, s)
		end
	end
	for joint, frames in o.Joints do
		if joint.Parent then
			if wrong(joint.C0.Position, frames[1].Position * s) then
				joint.C0 = scaled(frames[1], s)
			end
			if wrong(joint.C1.Position, frames[2].Position * s) then
				joint.C1 = scaled(frames[2], s)
			end
		end
	end
	for mesh, values in o.Meshes do
		-- Only file meshes have absolute sizes; other mesh types follow the part.
		if mesh.Parent and mesh.MeshType == Enum.MeshType.FileMesh and wrong(mesh.Scale, values[1] * s) then
			mesh.Scale = values[1] * s
			mesh.Offset = values[2] * s
		end
	end
end

-- Giants --------------------------------------------------------------------

local building = false -- a giant's avatar is being built right now

-- Parts of a giant are only for looking at: no collisions or touches, and
-- massless, so the joints hold the limbs up easily from the anchored root.
-- Scripts are removed. The joints themselves are left exactly as Roblox
-- made them (changing them, e.g. making them kinematic with infinite force,
-- broke the head and clothing).
local function prepareGiantParts(giant: Model)
	for _, d in giant:GetDescendants() do
		if d:IsA("BasePart") then
			if d ~= giant.PrimaryPart then
				d.Anchored = false
			end
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

-- Builds a giant founder, `scale` times normal size, standing on `ground`
-- (feet at that point) facing `lookAt`. The root is anchored and every other
-- part is welded to it, so moving the root moves the whole giant.
-- `eventOutfitId`: build them in their special event look (see the top of
-- this file) instead of their normal avatar.
function Founders.CreateGiant(founderId: string, scale: number, parent: Instance, eventOutfitId: number?): Model?
	local founder = Config.GetFounder(founderId)
	if not founder then
		return nil
	end
	local special = eventOutfitId ~= nil
	local model: Model? = nil
	local desc: HumanoidDescription? = nil
	if special then
		desc = savedLooks[founder.Id]
		if not desc and eventOutfitId and eventOutfitId > 0 then
			desc = outfitDescription(eventOutfitId)
		end
		desc = desc or liveDescription(founder)
	end
	if not desc then
		local userId = resolveUserId(founder)
		desc = if userId then description(userId) else nil
	end
	if desc then
		-- One giant at a time, each from its own fresh copy of the
		-- description: two giants built at once from one shared description
		-- came out without their heads and clothing.
		while building do
			task.wait(0.1)
		end
		building = true
		local copy = desc:Clone()
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(copy, Enum.HumanoidRigType.R15)
		end)
		building = false
		if ok and result then
			model = result
		end
	end
	if not model and not (special and founder.Id == "Corny") then
		return nil
	end
	local giant = model or cornyLookAlike()
	giant.Name = founder.Name .. "Giant"
	prepareGiantParts(giant)
	local root = giant:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		giant:Destroy()
		return nil
	end
	root.Anchored = true
	giant.PrimaryPart = root
	local humanoid = giant:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Leave Roblox's avatar system alone as much as possible: it's what
		-- puts the head, face and clothing on (switching off its health,
		-- state machine or auto-scaling left giants headless and unclothed).
		-- The giant can't move anyway: its root is anchored and its limbs
		-- are held rigid (above).
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	-- Send the giant to players all in one go, so a late part can't be missing.
	pcall(function()
		giant.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	-- Built out of sight below the map, then moved into place by the caller.
	giant:PivotTo(CFrame.new(0, -300, 0))
	giant.Parent = parent

	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		-- Real avatars: grow them the way Roblox grows any avatar, through the
		-- Humanoid's own body scale values. Roblox then rebuilds the whole
		-- avatar at that size itself, head, face, clothing and accessories
		-- included.
		-- Measured on the upper torso, a body part Roblox always resizes.
		local measure = (giant:FindFirstChild("UpperTorso") or root) :: BasePart
		local startHeight = measure.Size.Y
		for _, name in { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" } do
			local value = humanoid:FindFirstChild(name)
			if value and value:IsA("NumberValue") then
				value.Value *= scale
			end
		end
		-- Wait for Roblox to finish resizing it.
		local deadline = os.clock() + 3
		while os.clock() < deadline and measure.Size.Y < startHeight * scale * 0.9 do
			task.wait(0.1)
		end
		task.wait(0.3)
		-- If Roblox wouldn't make it that big, scale up the rest of the way.
		local reached = measure.Size.Y / startHeight
		if reached < scale * 0.9 then
			local originals = recordSizes(giant)
			local extra = scale / math.max(reached, 0.01)
			giant:ScaleTo(giant:GetScale() * extra)
			scaleInfo[giant] = { Originals = originals, Scale = extra }
			Founders.FixScale(giant)
		end
	else
		-- Look-alikes are plain welded parts: ScaleTo handles them perfectly.
		giant:ScaleTo(scale)
	end
	-- Resizing can add or rebuild parts, so set them up again.
	prepareGiantParts(giant)
	root.Anchored = true

	-- A line in the Output window describing what was built, to help track
	-- down any problem with how a giant looks.
	do
		local head = giant:FindFirstChild("Head")
		local headInfo = if head and head:IsA("BasePart")
			then string.format("head %s (size %.0f, see-through %.1f)", head.ClassName, head.Size.Y, head.Transparency)
			else "NO HEAD"
		local torso = giant:FindFirstChild("UpperTorso") or giant:FindFirstChild("Torso")
		print(string.format(
			"[Founders] %s giant: %s, shirt %s, pants %s, %d accessories, torso height %.0f (wanted scale %s)",
			founder.Name,
			headInfo,
			if giant:FindFirstChildOfClass("Shirt") then "yes" else "no",
			if giant:FindFirstChildOfClass("Pants") then "yes" else "no",
			#humanoidAccessories(giant),
			if torso and torso:IsA("BasePart") then torso.Size.Y else 0,
			tostring(scale)
		))
	end

	-- Name tag over their head
	local tag = Instance.new("BillboardGui")
	tag.Name = "FounderTag"
	tag.Size = UDim2.fromScale(5 * scale, 1.3 * scale)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	tag.LightInfluence = 0
	tag.MaxDistance = 1500
	local _, size = giant:GetBoundingBox()
	tag.StudsOffsetWorldSpace = Vector3.new(0, size.Y * 0.6 + scale * 1.6, 0) -- well clear of their head (and hat)
	tag.Adornee = root
	tag.Parent = root
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = string.upper(founder.Name) .. "\nFOUNDER"
	label.TextColor3 = Color3.fromRGB(255, 215, 70)
	label.TextStrokeTransparency = 0
	label.Parent = tag
	return giant
end

-- Where every part of a giant sits, worked out from its joints starting at
-- the root (not from where physics happens to have put the parts), with an
-- optional pose's turns added. Handles both kinds of avatar joints: classic
-- Motor6Ds and the newer AnimationConstraints (named the same, e.g.
-- "RightShoulder"), plus the welds and constraints accessories hang on.
local function solveRig(giant: Model, pose: { [string]: { number } }?): { [BasePart]: CFrame }
	local root = giant.PrimaryPart :: BasePart
	local placed: { [BasePart]: CFrame } = { [root] = root.CFrame }
	local links: { { P0: BasePart, P1: BasePart, A: CFrame, B: CFrame, Name: string, Turns: boolean } } = {}
	for _, d in giant:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Weld") then
			if d.Part0 and d.Part1 and d.Enabled then
				table.insert(links, { P0 = d.Part0, P1 = d.Part1, A = d.C0, B = d.C1, Name = d.Name, Turns = d:IsA("Motor6D") })
			end
		elseif d:IsA("AnimationConstraint") or d:IsA("RigidConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if d.Enabled and a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				table.insert(links, { P0 = p0, P1 = p1, A = a0.CFrame, B = a1.CFrame, Name = d.Name, Turns = d:IsA("AnimationConstraint") })
			end
		elseif d:IsA("WeldConstraint") then
			local p0, p1 = d.Part0, d.Part1
			if p0 and p1 then
				table.insert(links, { P0 = p0, P1 = p1, A = p0.CFrame:ToObjectSpace(p1.CFrame), B = CFrame.identity, Name = d.Name, Turns = false })
			end
		end
	end
	local changed = true
	while changed do
		changed = false
		for _, link in links do
			local angles = if pose and link.Turns then pose[link.Name] else nil
			local turn = if angles then CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3])) else CFrame.identity
			if placed[link.P0] and not placed[link.P1] then
				placed[link.P1] = placed[link.P0] * link.A * turn * link.B:Inverse()
				changed = true
			elseif placed[link.P1] and not placed[link.P0] then
				placed[link.P0] = placed[link.P1] * link.B * turn:Inverse() * link.A:Inverse()
				changed = true
			end
		end
	end
	return placed
end

-- How far the giant's root sits above its feet, standing straight, worked
-- out from its joints (its limbs may not be in place yet right after it's
-- built). Look-alikes are welded, so their parts are exact.
function Founders.RootHeight(giant: Model): number
	local root = giant.PrimaryPart :: BasePart
	local lowest = math.huge
	for part, cf in solveRig(giant, nil) do
		-- Body parts only (not hats, wings and other accessories)
		if part ~= root and not part:FindFirstAncestorOfClass("Accessory") then
			local size = part.Size
			local extent = math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
			lowest = math.min(lowest, cf.Position.Y - extent)
		end
	end
	if lowest < math.huge then
		return root.Position.Y - lowest
	end
	local cf, size = giant:GetBoundingBox()
	return root.Position.Y - (cf.Position.Y - size.Y / 2)
end

-- Loops one of Roblox's default emotes on the giant (wave, dance...).
-- Look-alikes have no joints, so this does nothing for them.
-- `weight` below 1 mixes it with whatever plays underneath (calmer); `speed`
-- below 1 slows it down.
function Founders.Play(giant: Model, animationId: string, looped: boolean, weight: number?, speed: number?, priority: Enum.AnimationPriority?): AnimationTrack?
	local humanoid = giant:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = looped
		if priority then
			track.Priority = priority
		end
		track:Play(0.5, weight or 1, speed or 1)
		return track
	end
	return nil
end

Founders.Idle = "rbxassetid://507766388" -- Roblox's normal standing idle

-- Poses ----------------------------------------------------------------------
-- A held pose made by turning the avatar's joints (degrees around X, Y, Z of
-- each joint). Facing -Z: +X on a hip/shoulder swings a limb forward, -X on a
-- knee folds the lower leg back.

export type Pose = { [string]: { number } }

-- Floating like a wise sage: knees bent with the legs folded back, hands
-- brought together in front of the chest.
Founders.SagePose = {
	RightHip = { 30, 0, 0 },
	LeftHip = { 30, 0, 0 },
	RightKnee = { -115, 0, 0 },
	LeftKnee = { -115, 0, 0 },
	RightAnkle = { 45, 0, 0 },
	LeftAnkle = { 45, 0, 0 },
	RightShoulder = { 20, 0, -6 },
	LeftShoulder = { 20, 0, 6 },
	RightElbow = { 90, 0, -55 },
	LeftElbow = { 90, 0, 55 },
} :: Pose

-- Puts a giant (a real avatar) into `pose` by turning the joints where each
-- limb connects: the C0 of classic joints (Motor6D), or the joint's
-- attachment on the parent part for newer avatars (AnimationConstraint).
-- Nothing is anchored or rebuilt, so Roblox keeps drawing the avatar's head
-- and clothing normally. Safe to call again: it always starts from each
-- joint's original setting.
local originalC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local originalAttachment: { [Attachment]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

function Founders.ApplyPose(giant: Model, pose: Pose)
	for _, joint in giant:GetDescendants() do
		local angles = pose[joint.Name]
		if angles then
			local turn = CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
			if joint:IsA("Motor6D") then
				local original = originalC0[joint] or joint.C0
				originalC0[joint] = original
				joint.C0 = original * turn
			elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
				local attachment = joint.Attachment0 :: Attachment
				local original = originalAttachment[attachment] or attachment.CFrame
				originalAttachment[attachment] = original
				attachment.CFrame = original * turn
			end
		end
	end
end

-- A glowing aura around a giant: a soft glow and outline (its OutlineColor
-- can be cycled), and energy rising off its body. Returns the Highlight.
-- `sparkles`: false for just the glowing outline (Corny's UFO event).
function Founders.AddAura(giant: Model, sparkles: boolean?): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "Aura"
	highlight.FillColor = Color3.fromRGB(255, 160, 230)
	highlight.FillTransparency = 0.94
	highlight.OutlineColor = Color3.fromRGB(255, 120, 220)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = giant
	if sparkles == false then
		return highlight
	end
	local root = giant.PrimaryPart :: BasePart
	local _, size = giant:GetBoundingBox()
	local holder = Instance.new("Part")
	holder.Name = "AuraVolume"
	holder.Anchored = true -- moved along with the giant by PivotTo
	holder.Massless = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(size.X * 0.5, size.Y * 0.8, size.Z * 0.5)
	holder.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = holder
	weld.Parent = holder
	holder.Parent = giant
	local energy = Instance.new("ParticleEmitter")
	energy.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	energy.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 220)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 220, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 140)),
	})
	energy.LightEmission = 1
	energy.Rate = 50
	energy.Lifetime = NumberRange.new(1, 2)
	energy.Speed = NumberRange.new(size.Y * 0.05, size.Y * 0.12)
	energy.EmissionDirection = Enum.NormalId.Top
	energy.SpreadAngle = Vector2.new(15, 15)
	energy.Shape = Enum.ParticleEmitterShape.Box
	energy.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	energy.Size = NumberSequence.new(size.Y * 0.025, 0)
	energy.Parent = holder
	return highlight
end

-- UFO ------------------------------------------------------------------------
-- A flying saucer for founder entrances, built around its center (facing
-- doesn't matter, it's round). Every part is anchored; move it with PivotTo.

local function ufoPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, egg: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if egg then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = model
	return p
end

function Founders.CreateUfo(diameter: number): Model
	local d = diameter
	local model = Instance.new("Model")
	model.Name = "FounderUFO"
	local hull = ufoPart(model, "Hull", Vector3.new(d, d * 0.2, d), CFrame.new(), Color3.fromRGB(175, 180, 195), Enum.Material.Metal, true)
	hull.Reflectance = 0.25
	model.PrimaryPart = hull
	ufoPart(model, "Belly", Vector3.new(d * 0.62, d * 0.17, d * 0.62), CFrame.new(0, -d * 0.06, 0), Color3.fromRGB(110, 115, 130), Enum.Material.Metal, true)
	local rim = ufoPart(model, "Rim", Vector3.new(d * 0.035, d * 1.02, d * 1.02), CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 75, 90), Enum.Material.Metal)
	rim.Shape = Enum.PartType.Cylinder
	local dome = ufoPart(model, "Dome", Vector3.new(d * 0.38, d * 0.3, d * 0.38), CFrame.new(0, d * 0.09, 0), Color3.fromRGB(120, 230, 255), Enum.Material.Glass, true)
	dome.Transparency = 0.3
	-- A ring of colored lights around the rim
	local lights = 16
	for i = 1, lights do
		local angle = i / lights * math.pi * 2
		local light = ufoPart(model, "RimLight", Vector3.new(d * 0.045, d * 0.045, d * 0.045), CFrame.new(math.cos(angle) * d * 0.49, 0, math.sin(angle) * d * 0.49), Color3.fromHSV(i / lights, 0.7, 1), Enum.Material.Neon)
		light.Shape = Enum.PartType.Ball
	end
	-- The glowing hatch the beam comes out of
	local hatch = ufoPart(model, "Hatch", Vector3.new(0.6, d * 0.3, d * 0.3), CFrame.new(0, -d * 0.145, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(200, 255, 235), Enum.Material.Neon)
	hatch.Shape = Enum.PartType.Cylinder
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Left -- the cylinder is turned on its side, so "Left" points down
	spot.Angle = 70
	spot.Range = 60
	spot.Brightness = 4
	spot.Color = Color3.fromRGB(190, 255, 235)
	spot.Parent = hatch
	return model
end

-- The UFO's light beam: glowing see-through rings stacked into a cone from
-- `top` down to `bottom` (both points on its center line), widening as it
-- goes down, with sparkles drifting up inside. Starts invisible; fade it in
-- by tweening each part's Transparency to `Founders.BeamTransparency`.
Founders.BeamTransparency = 0.9

function Founders.CreateBeam(top: Vector3, bottom: Vector3, topWidth: number, bottomWidth: number): Model
	local model = Instance.new("Model")
	model.Name = "UFOBeam"
	local segments = 8
	local height = top.Y - bottom.Y
	for i = 0, segments - 1 do
		local t = (i + 0.5) / segments
		local width = topWidth + (bottomWidth - topWidth) * t
		local center = top:Lerp(bottom, t)
		local ring = ufoPart(model, "Beam", Vector3.new(height / segments, width, width), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 255, 225), Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.CastShadow = false
		ring.Transparency = 1
	end
	-- Glow on the ground where the beam lands
	local glow = ufoPart(model, "BeamGlow", Vector3.new(0.4, bottomWidth * 1.1, bottomWidth * 1.1), CFrame.new(bottom + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(190, 255, 235), Enum.Material.Neon)
	glow.Shape = Enum.PartType.Cylinder
	glow.Transparency = 1
	return model
end
Founders.Wave = "rbxassetid://507770239"
Founders.Dance = "rbxassetid://507771019"
Founders.Cheer = "rbxassetid://507770677"

return Founders

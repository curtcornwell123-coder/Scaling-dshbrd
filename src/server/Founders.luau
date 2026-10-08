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

-- The founder's character right now, if they're in this server.
local function liveDescription(founder: Config.Founder): HumanoidDescription?
	for _, player in Players:GetPlayers() do
		local matches = (founder.UserId > 0 and player.UserId == founder.UserId)
			or (founder.Username ~= "" and string.lower(player.Name) == string.lower(founder.Username))
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

-- Giants --------------------------------------------------------------------

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
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if ok and result then
			model = result
		end
	end
	if not model and not (special and founder.Id == "Corny") then
		return nil
	end
	local giant = model or cornyLookAlike()
	giant.Name = founder.Name .. "Giant"
	for _, d in giant:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = giant:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		giant:Destroy()
		return nil
	end
	root.Anchored = true
	giant.PrimaryPart = root
	local humanoid = giant:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		-- A giant is a statue that dances: no walking, falling, ragdolling or
		-- dying (that's what knocked them over and into the ground). Emotes
		-- still play through the Animator.
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge
		for _, state in { Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Physics } do
			humanoid:SetStateEnabled(state, false)
		end
		humanoid.EvaluateStateMachine = false
	end
	giant.Parent = parent
	giant:ScaleTo(scale)

	-- Name tag over their head
	local tag = Instance.new("BillboardGui")
	tag.Name = "FounderTag"
	tag.Size = UDim2.fromScale(5 * scale, 1.3 * scale)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	tag.LightInfluence = 0
	tag.MaxDistance = 1500
	local _, size = giant:GetBoundingBox()
	tag.StudsOffsetWorldSpace = Vector3.new(0, size.Y * 0.55 + scale * 0.6, 0)
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

-- How far the giant's root sits above its feet. Real avatars are measured
-- through their joints, standing straight (their limbs aren't moved into
-- place until physics runs, so measuring the parts themselves would sink the
-- giant into the ground). Look-alikes are welded, so their parts are exact.
function Founders.RootHeight(giant: Model): number
	local root = giant.PrimaryPart :: BasePart
	local placed: { [BasePart]: CFrame } = { [root] = root.CFrame }
	local joints = {}
	for _, d in giant:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Weld") then
			table.insert(joints, d)
		end
	end
	local changed = true
	while changed do
		changed = false
		for _, joint in joints do
			local p0, p1 = joint.Part0, joint.Part1
			if p0 and p1 then
				if placed[p0] and not placed[p1] then
					placed[p1] = placed[p0] * joint.C0 * joint.C1:Inverse()
					changed = true
				elseif placed[p1] and not placed[p0] then
					placed[p0] = placed[p1] * joint.C1 * joint.C0:Inverse()
					changed = true
				end
			end
		end
	end
	local lowest = math.huge
	for part, cf in placed do
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

-- Puts a giant (a real avatar) into `pose` and freezes it there: every body
-- part and accessory is placed directly from the avatar's joints, with the
-- pose's turns added, and then anchored. Nothing is left to the physics
-- engine, so the pose always shows and the body can't droop, fall or sink.
-- Move it afterwards with PivotTo.
function Founders.FreezePose(giant: Model, pose: Pose)
	local root = giant.PrimaryPart
	if not root then
		return
	end
	local placed: { [BasePart]: CFrame } = { [root] = root.CFrame }
	local joints: { JointInstance } = {}
	local rigid: { RigidConstraint } = {}
	for _, d in giant:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Weld") then
			table.insert(joints, d)
		elseif d:IsA("RigidConstraint") then
			table.insert(rigid, d)
		end
	end
	local function turn(joint: JointInstance): CFrame
		local angles = if joint:IsA("Motor6D") then pose[joint.Name] else nil
		return if angles then CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3])) else CFrame.identity
	end
	local changed = true
	while changed do
		changed = false
		for _, joint in joints do
			local p0, p1 = joint.Part0, joint.Part1
			if p0 and p1 then
				if placed[p0] and not placed[p1] then
					placed[p1] = placed[p0] * joint.C0 * turn(joint) * joint.C1:Inverse()
					changed = true
				elseif placed[p1] and not placed[p0] then
					placed[p0] = placed[p1] * joint.C1 * turn(joint):Inverse() * joint.C0:Inverse()
					changed = true
				end
			end
		end
		-- Accessories held on by attachments instead of welds
		for _, constraint in rigid do
			local a0, a1 = constraint.Attachment0, constraint.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				if placed[p0] and not placed[p1] then
					placed[p1] = placed[p0] * a0.CFrame * a1.CFrame:Inverse()
					changed = true
				elseif placed[p1] and not placed[p0] then
					placed[p0] = placed[p1] * a1.CFrame * a0.CFrame:Inverse()
					changed = true
				end
			end
		end
	end
	for _, part in giant:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			local cf = placed[part]
			if cf then
				part.CFrame = cf
			end
		end
	end
end

-- A glowing aura around a giant: a soft glow and outline (its OutlineColor
-- can be cycled), and energy rising off its body. Returns the Highlight.
function Founders.AddAura(giant: Model): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "Aura"
	highlight.FillColor = Color3.fromRGB(255, 160, 230)
	highlight.FillTransparency = 0.94
	highlight.OutlineColor = Color3.fromRGB(255, 120, 220)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = giant
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
	-- Sparkles rising up the beam
	local volume = ufoPart(model, "BeamSparkles", Vector3.new(bottomWidth * 0.6, height, bottomWidth * 0.6), CFrame.new(top:Lerp(bottom, 0.5)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	volume.Transparency = 1
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(200, 255, 240), Color3.fromRGB(255, 255, 200))
	sparkles.LightEmission = 1
	sparkles.Rate = 60
	sparkles.Lifetime = NumberRange.new(2, 4)
	sparkles.Speed = NumberRange.new(height * 0.08, height * 0.15)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.SpreadAngle = Vector2.new(10, 10)
	sparkles.Shape = Enum.ParticleEmitterShape.Box
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkles.Size = NumberSequence.new(bottomWidth * 0.03, 0)
	sparkles.Parent = volume
	return model
end
Founders.Wave = "rbxassetid://507770239"
Founders.Dance = "rbxassetid://507771019"
Founders.Cheer = "rbxassetid://507770677"

return Founders

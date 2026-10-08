--!strict
-- Giant founders, scaled up into giants the server can move around.
--  * Admin abuse: each founder's normal Roblox avatar (from the UserId or
--    Username in Config.Founders). Founders without one don't appear.
--  * Their own events: a special outfit. That's the outfit's id (OutfitId in
--    Config.FounderEvents) if set, otherwise for Corny a look-alike of the
--    event outfit from his screenshots.

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
-- `eventOutfitId`: build them in their special event outfit instead of their
-- normal avatar (0 = no outfit id; Corny then gets his look-alike).
function Founders.CreateGiant(founderId: string, scale: number, parent: Instance, eventOutfitId: number?): Model?
	local founder = Config.GetFounder(founderId)
	if not founder then
		return nil
	end
	local special = eventOutfitId ~= nil
	local model: Model? = nil
	local desc: HumanoidDescription? = nil
	if eventOutfitId and eventOutfitId > 0 then
		desc = outfitDescription(eventOutfitId)
	elseif not special then
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

-- How far the giant's root sits above its feet.
function Founders.RootHeight(giant: Model): number
	local root = giant.PrimaryPart :: BasePart
	local cf, size = giant:GetBoundingBox()
	return root.Position.Y - (cf.Position.Y - size.Y / 2)
end

-- Loops one of Roblox's default emotes on the giant (wave, dance...).
-- Look-alikes have no joints, so this does nothing for them.
function Founders.Play(giant: Model, animationId: string, looped: boolean): AnimationTrack?
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
		track:Play()
		return track
	end
	return nil
end

Founders.Wave = "rbxassetid://507770239"
Founders.Dance = "rbxassetid://507771019"
Founders.Cheer = "rbxassetid://507770677"

return Founders

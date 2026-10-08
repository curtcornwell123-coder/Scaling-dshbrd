--!strict
-- Builds a brainrot character out of simple parts, with a name tag and
-- rarity effects. Swap this for real meshes later; the rest of the game
-- only relies on the "Root" part and the "Tag" billboard.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BrainrotModel = {}

local function part(props: { [string]: any }): BasePart
	local shape = props.Shape
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	for key, value in props do
		if key ~= "Shape" then
			(p :: any)[key] = value
		end
	end
	return p
end

local function attach(root: BasePart, child: BasePart, offset: CFrame)
	child.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = child
	weld.Parent = child
	child.Parent = root.Parent
end

local function label(parent: Instance, name: string, text: string, color: Color3, size: number, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

-- Creates the model at `cframe` (feet on the ground). `priceTag` shows the buy price.
function BrainrotModel.Create(brainrot: Config.Brainrot, cframe: CFrame, priceTag: boolean): Model
	local rarity = Config.Rarities[brainrot.Rarity]
	local s = rarity.Scale

	local model = Instance.new("Model")
	model.Name = brainrot.Id
	model:SetAttribute("BrainrotId", brainrot.Id)

	local root = part({
		Name = "Root",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		Anchored = true,
		CFrame = cframe * CFrame.new(0, 0.5, 0),
	})
	root.Parent = model
	model.PrimaryPart = root

	local bodyHeight = 3 * s
	local legHeight = 1 * s

	-- Legs
	for _, x in { -0.7, 0.7 } do
		attach(root, part({
			Name = "Leg",
			Size = Vector3.new(0.5 * s, legHeight, 0.5 * s),
			Color = brainrot.Accent,
		}), CFrame.new(x * s, legHeight / 2 - 0.5, 0))
	end

	-- Body
	local bodyY = legHeight + bodyHeight / 2 - 0.5
	attach(root, part({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(bodyHeight, bodyHeight, bodyHeight),
		Color = brainrot.Color,
		Material = Enum.Material.SmoothPlastic,
	}), CFrame.new(0, bodyY, 0))

	-- Eyes (front is -Z)
	for _, x in { -0.45, 0.45 } do
		attach(root, part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9) * s,
			Color = Color3.new(1, 1, 1),
		}), CFrame.new(x * s, bodyY + 0.35 * s, -bodyHeight * 0.4))
		attach(root, part({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.4, 0.4, 0.4) * s,
			Color = Color3.new(0, 0, 0),
		}), CFrame.new(x * s, bodyY + 0.35 * s, -bodyHeight * 0.4 - 0.35 * s))
	end

	-- Hat in the accent color
	attach(root, part({
		Name = "Hat",
		Size = Vector3.new(1.6, 0.8, 1.6) * s,
		Color = brainrot.Accent,
		Material = Enum.Material.SmoothPlastic,
	}), CFrame.new(0, bodyY + bodyHeight / 2, 0) * CFrame.Angles(0, math.rad(15), math.rad(-10)))

	-- Rarity effects
	if rarity.Order >= 4 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 10 * s
		light.Brightness = 2
		light.Parent = root
	end
	if rarity.Order >= 5 then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(rarity.Color)
		sparkles.Rate = 12
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(2, 4)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new(0.4)
		sparkles.Parent = root
	end
	if brainrot.Rarity == "Secret" then
		local rainbow = Instance.new("Highlight")
		rainbow.FillTransparency = 0.6
		rainbow.OutlineColor = Color3.fromRGB(255, 120, 255)
		rainbow.FillColor = Color3.fromRGB(120, 60, 255)
		rainbow.Parent = model
	end

	-- Name tag
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(200, priceTag and 92 or 72)
	tag.StudsOffsetWorldSpace = Vector3.new(0, legHeight + bodyHeight + 1.5, 0)
	tag.MaxDistance = 80
	tag.Adornee = root
	tag.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = tag

	local rarityColor = brainrot.Rarity == "Secret" and Color3.fromRGB(255, 120, 255) or rarity.Color
	label(tag, "Rarity", string.upper(brainrot.Rarity), rarityColor, 18, 1)
	label(tag, "Name", brainrot.DisplayName, Color3.new(1, 1, 1), 26, 2)
	label(tag, "Income", Config.FormatCash(brainrot.Income) .. "/s", Color3.fromRGB(120, 255, 120), 20, 3)
	if priceTag then
		label(tag, "Price", Config.FormatCash(brainrot.Price), Color3.fromRGB(255, 220, 80), 22, 4)
	end

	return model
end

-- Height of the model above its feet, for placing things over its head.
function BrainrotModel.Height(brainrot: Config.Brainrot): number
	return 4 * Config.Rarities[brainrot.Rarity].Scale
end

return BrainrotModel

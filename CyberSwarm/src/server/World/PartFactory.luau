--!strict
--[[
	PartFactory
	Helpers for building the world out of Parts at runtime. Centralising the defaults (anchored,
	no shadows on neon, no touch/query on decoration) keeps physics and raycasts cheap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)

export type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	shape: Enum.PartType?,
	canCollide: boolean?,
	parent: Instance?,
}

local PartFactory = {}

function PartFactory.part(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.name or "Part"
	part.Anchored = true
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Transparency = props.transparency or 0
	part.Shape = props.shape or Enum.PartType.Block
	part.CanCollide = if props.canCollide == nil then true else props.canCollide
	-- Decoration never needs touch events; skipping them saves physics work.
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if part.Material == Enum.Material.Neon then
		part.CastShadow = false
	end
	if props.parent then
		part.Parent = props.parent
	end
	return part
end

function PartFactory.neon(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance?): Part
	return PartFactory.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		material = Enum.Material.Neon,
		canCollide = false,
		parent = parent,
	})
end

-- Marker parts (waypoints, slots, spawns) are invisible and inert.
function PartFactory.marker(name: string, cframe: CFrame, size: Vector3, parent: Instance): Part
	local part = PartFactory.part({
		name = name,
		size = size,
		cframe = cframe,
		color = Theme.Colors.Primary,
		transparency = 1,
		canCollide = false,
		parent = parent,
	})
	part.CanQuery = false
	return part
end

-- Units move as one assembly: the root stays anchored and every other part is welded to it.
-- Moving only the root (via BulkMoveTo) then carries the whole model with a single CFrame write.
function PartFactory.weldToRoot(model: Model, root: BasePart)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= root then
				descendant.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	root.Anchored = true
end

-- A billboard label that always faces the camera. Size is in studs.
function PartFactory.billboard(
	adornee: BasePart,
	text: string,
	color: Color3,
	studsSize: Vector2,
	offsetY: number,
	maxDistance: number
): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(studsSize.X, studsSize.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Theme.Colors.PanelDark
	label.Text = text
	label.Parent = gui

	gui.Parent = adornee
	return gui, label
end

-- A world-space health bar; returns the fill frame so callers resize it on damage.
function PartFactory.healthBar(adornee: BasePart, widthStuds: number, offsetY: number, fillColor: Color3): Frame
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(widthStuds, 0.45)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 260

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Theme.Colors.PanelDark
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = back

	gui.Parent = adornee
	return fill
end

return PartFactory

--!strict
-- Geometry helpers for the code-built world ("Rivals" look: smooth plastic,
-- rounded corners, neon trims, gradient panels). Everything is anchored unless
-- stated otherwise.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local Parts = {}

export type Props = {
	Name: string?,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Anchored: boolean?,
	Shape: Enum.PartType?,
}

local function applyProps(part: BasePart, props: Props?)
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if not props then
		return
	end
	if props.Name then
		part.Name = props.Name
	end
	if props.Color then
		part.Color = props.Color
	end
	if props.Material then
		part.Material = props.Material
	end
	if props.Transparency then
		part.Transparency = props.Transparency
	end
	if props.Reflectance then
		part.Reflectance = props.Reflectance
	end
	if props.CanCollide ~= nil then
		part.CanCollide = props.CanCollide
	end
	if props.CanQuery ~= nil then
		part.CanQuery = props.CanQuery
	end
	if props.CanTouch ~= nil then
		part.CanTouch = props.CanTouch
	end
	if props.CastShadow ~= nil then
		part.CastShadow = props.CastShadow
	end
	if props.Anchored ~= nil then
		part.Anchored = props.Anchored
	end
	if props.Material == Enum.Material.Neon then
		part.CastShadow = false
	end
end

-- Plain block.
function Parts.block(parent: Instance, cf: CFrame, size: Vector3, props: Props?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	applyProps(p, props)
	if props and props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = parent
	return p
end

-- Block spanning from a to b (centre line), with the given cross-section.
-- `up` orients the cross-section (defaults to world up, or X if the span is vertical).
function Parts.beam(parent: Instance, a: Vector3, b: Vector3, width: number, height: number, props: Props?, up: Vector3?): Part
	local dir = b - a
	local len = dir.Magnitude
	local look = dir.Unit
	local upVec = up or Vector3.yAxis
	if math.abs(look:Dot(upVec)) > 0.99 then
		upVec = Vector3.xAxis
	end
	local cf = CFrame.lookAt((a + b) / 2, b, upVec)
	return Parts.block(parent, cf, Vector3.new(width, height, len), props)
end

-- Cylinder whose axis runs along the CFrame's Y axis (Roblox cylinders run along X).
function Parts.cylinder(parent: Instance, cf: CFrame, height: number, diameter: number, props: Props?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	applyProps(p, props)
	p.Parent = parent
	return p
end

-- Upright disc centred at `center` (top face at center.Y + thickness/2).
function Parts.disc(parent: Instance, center: Vector3, diameter: number, thickness: number, props: Props?): Part
	return Parts.cylinder(parent, CFrame.new(center), thickness, diameter, props)
end

-- Cylinder rod between two points.
function Parts.rod(parent: Instance, a: Vector3, b: Vector3, diameter: number, props: Props?): Part
	local dir = b - a
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(dir.Magnitude, diameter, diameter)
	-- Cylinder axis is local X: build a CFrame whose RightVector is the rod direction.
	local x = dir.Unit
	local y = if math.abs(x.Y) < 0.99 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(y).Unit
	y = z:Cross(x).Unit
	p.CFrame = CFrame.fromMatrix((a + b) / 2, x, y, z)
	applyProps(p, props)
	p.Parent = parent
	return p
end

function Parts.ball(parent: Instance, center: Vector3, diameter: number, props: Props?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * diameter
	p.CFrame = CFrame.new(center)
	applyProps(p, props)
	p.Parent = parent
	return p
end

-- Box with rounded vertical edges (2 crossed blocks + 4 corner cylinders).
-- Returns the main (largest) block, which is safe to put SurfaceGuis on (Front/Back).
function Parts.roundedBox(parent: Instance, cf: CFrame, size: Vector3, radius: number, props: Props?): Part
	local r = math.min(radius, size.X / 2, size.Z / 2)
	local model = Instance.new("Model")
	model.Name = (props and props.Name) or "RoundedBox"
	local main = Parts.block(model, cf, Vector3.new(size.X - 2 * r, size.Y, size.Z), props)
	main.Name = "Main"
	if r > 0.05 then
		Parts.block(model, cf, Vector3.new(size.X, size.Y, size.Z - 2 * r), props).Name = "Cross"
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = cf * CFrame.new(sx * (size.X / 2 - r), 0, sz * (size.Z / 2 - r))
				Parts.cylinder(model, corner, size.Y, r * 2, props).Name = "Corner"
			end
		end
	end
	model.Parent = parent
	return main
end

-- Bevelled slab: rounded box plus a thin neon trim line around its top edge.
function Parts.trimmedSlab(parent: Instance, cf: CFrame, size: Vector3, radius: number, color: Color3, trim: Color3, props: Props?): Part
	local p: Props = props and table.clone(props) or {}
	p.Color = color
	local main = Parts.roundedBox(parent, cf, size, radius, p)
	local top = cf * CFrame.new(0, size.Y / 2, 0)
	local t = 0.18
	local inset = 0.02
	local hx, hz = size.X / 2 - inset, size.Z / 2 - inset
	local trimProps: Props = { Color = trim, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Name = "Trim" }
	local container = main.Parent :: Instance
	Parts.block(container, top * CFrame.new(0, 0, -hz), Vector3.new(size.X - 2 * radius, t, t), trimProps)
	Parts.block(container, top * CFrame.new(0, 0, hz), Vector3.new(size.X - 2 * radius, t, t), trimProps)
	Parts.block(container, top * CFrame.new(-hx, 0, 0), Vector3.new(t, t, size.Z - 2 * radius), trimProps)
	Parts.block(container, top * CFrame.new(hx, 0, 0), Vector3.new(t, t, size.Z - 2 * radius), trimProps)
	return main
end

-- Exact triangle between three points using two WedgeParts.
function Parts.triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, props: Props?): { WedgePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make a-b the longest edge... we want the longest edge opposite the right-angle split.
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local out = {}
	local w1 = Instance.new("WedgePart")
	w1.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	applyProps(w1, props)
	w1.Parent = parent
	table.insert(out, w1)

	local w2 = Instance.new("WedgePart")
	w2.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	applyProps(w2, props)
	w2.Parent = parent
	table.insert(out, w2)
	return out
end

-- Gradient panel: a SurfaceGui frame with a UIGradient on one face.
function Parts.gradientFace(part: BasePart, face: Enum.NormalId, c0: Color3, c1: Color3, rotation: number?, transparency: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gradient" .. face.Name
	gui.Face = face
	gui.LightInfluence = 0.6
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 4
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = transparency or 0
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(c0, c1)
	grad.Rotation = rotation or 90
	grad.Parent = frame
	frame.Parent = gui
	gui.Parent = part
	return gui
end

export type LabelOpts = {
	TextColor: Color3?,
	Stroke: Color3?,
	Font: Enum.Font?,
	PixelsPerStud: number?,
	Background: Color3?,
	BackgroundTransparency: number?,
	Glow: boolean?, -- LightInfluence 0 (reads as emissive)
	Name: string?,
}

-- Big single text label on a face. Returns the TextLabel.
function Parts.label(part: BasePart, face: Enum.NormalId, text: string, opts: LabelOpts?): TextLabel
	local o: LabelOpts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.Name or "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 30
	gui.LightInfluence = if o.Glow == false then 1 else 0
	gui.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = o.Background or Color3.new(0, 0, 0)
	label.BackgroundTransparency = o.BackgroundTransparency or 1
	label.Text = text
	label.TextScaled = true
	label.Font = o.Font or Config.Font
	label.TextColor3 = o.TextColor or Config.Colors.Text
	label.BorderSizePixel = 0
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	if o.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = o.Stroke
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end
	label.Parent = gui
	gui.Parent = part
	return label
end

function Parts.light(part: BasePart, color: Color3, range: number, brightness: number, kind: string?): Light
	local l: Light
	if kind == "Surface" then
		local s = Instance.new("SurfaceLight")
		s.Face = Enum.NormalId.Bottom
		s.Angle = 120
		l = s
	elseif kind == "Spot" then
		local s = Instance.new("SpotLight")
		s.Face = Enum.NormalId.Bottom
		s.Angle = 80
		l = s
	else
		l = Instance.new("PointLight")
	end
	l.Color = color
	l.Brightness = brightness
	l.Shadows = false;
	(l :: any).Range = range
	l.Parent = part
	return l
end

export type PromptOpts = { Hold: number?, Distance: number?, Key: Enum.KeyCode?, Name: string?, RequiresLineOfSight: boolean? }

function Parts.prompt(part: BasePart, action: string, object: string, opts: PromptOpts?): ProximityPrompt
	local o: PromptOpts = opts or {}
	local p = Instance.new("ProximityPrompt")
	p.Name = o.Name or "Prompt"
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = o.Hold or 0
	p.MaxActivationDistance = o.Distance or 10
	p.KeyboardKeyCode = o.Key or Enum.KeyCode.E
	p.RequiresLineOfSight = o.RequiresLineOfSight == true
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = part
	return p
end

function Parts.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Parts.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Ring of `segments` blocks approximating a torus-like hoop (portal frames, cup rims).
-- The ring lies in the plane of cf's X/Y axes, centred on cf.
function Parts.hoop(parent: Instance, cf: CFrame, radius: number, thickness: number, depth: number, segments: number, props: Props?): Model
	local m = Instance.new("Model")
	m.Name = (props and props.Name) or "Hoop"
	local seg = 2 * math.pi * radius / segments * 1.04
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local pos = cf * CFrame.Angles(0, 0, a) * CFrame.new(0, radius, 0)
		Parts.block(m, pos, Vector3.new(seg, thickness, depth), props)
	end
	m.Parent = parent
	return m
end

-- Horizontal ring (lying flat, around a Y axis) of blocks: bowl rims, floor rings.
function Parts.flatRing(parent: Instance, center: Vector3, radius: number, width: number, height: number, segments: number, props: Props?): Model
	local m = Instance.new("Model")
	m.Name = (props and props.Name) or "Ring"
	local seg = 2 * math.pi * radius / segments * 1.06
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local cf = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
		Parts.block(m, cf, Vector3.new(seg, height, width), props)
	end
	m.Parent = parent
	return m
end

return Parts

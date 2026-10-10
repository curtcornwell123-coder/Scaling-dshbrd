--!strict
--[[
	Kit
	Building blocks for the lobby facility: low-poly concrete and steel shapes, rounded arches,
	hazard stripes, signs, client-rendered screens, terminals, and props. Every piece is original
	geometry made from Parts. Signs with fixed text are drawn here; live screens are blank parts
	tagged WorldScreen that each client draws for its own player (WorldScreensController).

	Frames: functions take a CFrame whose -Z (LookVector) faces the viewer / walkway and whose
	position is the base centre on the floor, unless noted.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PartFactory = require(script.Parent.Parent.PartFactory)

local World = Theme.World
local LIE_FLAT = CFrame.Angles(0, 0, math.rad(90))
local SIGN_PIXELS_PER_STUD = 24

local Kit = {}

function Kit.block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	return PartFactory.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		material = material or Enum.Material.SmoothPlastic,
		canCollide = if collide == nil then true else collide,
		parent = parent,
	})
end

function Kit.glow(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	return PartFactory.neon(name, size, cframe, color, parent)
end

-- Upright cylinder; `cframe` is the centre.
function Kit.disc(
	parent: Instance,
	name: string,
	radius: number,
	height: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = PartFactory.part({
		name = name,
		size = Vector3.new(height, radius * 2, radius * 2),
		cframe = cframe * LIE_FLAT,
		color = color,
		material = material or Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
	return part
end

function Kit.wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Anchored = true
	wedge.CanTouch = false
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = Enum.Material.SmoothPlastic
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

-- A flat ring of `segments` blocks lying on the floor. Returns the segments in order.
function Kit.ring(
	parent: Instance,
	name: string,
	center: CFrame,
	radius: number,
	width: number,
	height: number,
	segments: number,
	color: Color3,
	material: Enum.Material?
): { Part }
	local list: { Part } = {}
	local arc = 2 * math.pi * radius / segments
	for index = 1, segments do
		local angle = (index - 0.5) / segments * math.pi * 2
		local cframe = center * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -radius)
		local part = Kit.block(
			parent,
			`{name}_{index}`,
			Vector3.new(arc * 1.04, height, width),
			cframe,
			color,
			material,
			false
		)
		table.insert(list, part)
	end
	return list
end

-- Rounded concrete arch. `cframe` is the floor centre of the opening; the arch spans local X.
function Kit.arch(parent: Instance, name: string, cframe: CFrame, width: number, height: number, depth: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	local pillarWidth = 3
	local springHeight = height - width * 0.5
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"Pillar",
			Vector3.new(pillarWidth, springHeight, depth),
			cframe * CFrame.new(side * (width * 0.5 + pillarWidth * 0.5), springHeight * 0.5, 0),
			color
		)
	end
	-- Semicircle from short blocks; each one sits on the arc and is rotated to follow it.
	local pieces = 9
	local radius = width * 0.5 + pillarWidth * 0.5
	for index = 0, pieces - 1 do
		local angle = (index + 0.5) / pieces * math.pi
		local x = math.cos(angle) * radius
		local y = springHeight + math.sin(angle) * radius
		local length = math.pi * radius / pieces * 1.12
		Kit.block(
			model,
			"ArchStone",
			Vector3.new(length, pillarWidth, depth),
			cframe * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, angle - math.pi * 0.5),
			color
		)
	end
	-- Fill above the curve so the arch reads as part of a solid wall.
	Kit.block(
		model,
		"Spandrel",
		Vector3.new(width + pillarWidth * 2, 3, depth),
		cframe * CFrame.new(0, height + 1.5, 0),
		color
	)
	model.Parent = parent
	return model
end

-- Yellow/black diagonal-look stripe along local X (alternating blocks).
function Kit.hazardStripe(parent: Instance, cframe: CFrame, length: number, width: number, height: number)
	local step = 1.6
	local count = math.max(1, math.floor(length / step))
	local actual = length / count
	for index = 1, count do
		local x = -length * 0.5 + (index - 0.5) * actual
		Kit.block(
			parent,
			"Hazard",
			Vector3.new(actual, height, width),
			cframe * CFrame.new(x, 0, 0),
			if index % 2 == 0 then World.HazardBlack else World.Hazard,
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

-- Floor guide line from `from` to `to` (both on the floor surface).
function Kit.floorLine(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3)
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.1 then
		return
	end
	Kit.block(
		parent,
		"FloorGuide",
		Vector3.new(width, 0.06, length),
		CFrame.lookAt(from + delta * 0.5 + Vector3.new(0, 0.03, 0), to + Vector3.new(0, 0.03, 0)),
		color,
		Enum.Material.SmoothPlastic,
		false
	)
end

-- A text sign: a slab with fixed text on its front face. `glow` adds a soft light.
function Kit.sign(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector2,
	text: string,
	textColor: Color3,
	backColor: Color3?,
	glow: Color3?,
	font: Enum.Font?,
	strokeColor: Color3?
): Part
	local slab = Kit.block(
		parent,
		name,
		Vector3.new(size.X, size.Y, 0.4),
		cframe,
		backColor or World.Steel,
		Enum.Material.SmoothPlastic,
		false
	)
	if backColor == nil then
		slab.Transparency = 1
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PIXELS_PER_STUD
	gui.LightInfluence = if glow ~= nil then 0 else 1
	gui.Adornee = slab
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Theme.Fonts.Title
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = textColor
	if strokeColor ~= nil then
		label.TextStrokeColor3 = strokeColor
		label.TextStrokeTransparency = 0
	end
	label.Parent = gui
	gui.Parent = slab
	if glow ~= nil then
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Brightness = 0.8
		light.Range = 14
		light.Parent = slab
	end
	return slab
end

-- A blank screen the clients draw on. Extra attributes describe what it shows.
function Kit.screen(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector2,
	kind: string,
	attributes: { [string]: any }?
): Part
	local frame = Kit.block(
		parent,
		name .. "Bezel",
		Vector3.new(size.X + 0.8, size.Y + 0.8, 0.5),
		cframe * CFrame.new(0, 0, 0.3),
		World.Steel,
		Enum.Material.Metal,
		false
	)
	frame.CanQuery = false
	local screen = Kit.block(parent, name, Vector3.new(size.X, size.Y, 0.2), cframe, World.Screen, Enum.Material.SmoothPlastic, false)
	screen:SetAttribute(Constants.Attributes.Screen, kind)
	if attributes ~= nil then
		for key, value in attributes do
			screen:SetAttribute(key, value)
		end
	end
	CollectionService:AddTag(screen, Constants.Tags.WorldScreen)
	return screen
end

-- Screen tilted back slightly on a short stand, angled toward the walkway.
function Kit.angledScreen(
	parent: Instance,
	name: string,
	floorCFrame: CFrame,
	size: Vector2,
	kind: string,
	attributes: { [string]: any }?
): Part
	local postHeight = 3
	Kit.block(parent, name .. "Post", Vector3.new(1.2, postHeight, 1.2), floorCFrame * CFrame.new(0, postHeight * 0.5, 0.8), World.Steel, Enum.Material.Metal)
	local center = floorCFrame * CFrame.new(0, postHeight + size.Y * 0.5, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	return Kit.screen(parent, name, center, size, kind, attributes)
end

-- Console with a ProximityPrompt. The client opens the panel named by `terminal`.
function Kit.terminal(parent: Instance, name: string, floorCFrame: CFrame, terminal: string, actionText: string, objectText: string, accent: Color3): Part
	local model = Instance.new("Model")
	model.Name = name
	Kit.block(model, "Base", Vector3.new(3.4, 3.2, 2), floorCFrame * CFrame.new(0, 1.6, 0), World.Steel, Enum.Material.Metal)
	local top = Kit.block(
		model,
		"Console",
		Vector3.new(3.6, 0.4, 2.4),
		floorCFrame * CFrame.new(0, 3.4, -0.2) * CFrame.Angles(math.rad(20), 0, 0),
		World.SteelLight,
		Enum.Material.Metal
	)
	Kit.glow(model, "Accent", Vector3.new(3, 0.12, 0.12), floorCFrame * CFrame.new(0, 3.1, -1.05), accent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = top
	top:SetAttribute(Constants.Attributes.Terminal, terminal)
	CollectionService:AddTag(top, Constants.Tags.Terminal)
	model.Parent = parent
	return top
end

-- Steel truss beam between two points with hanging spotlights.
function Kit.truss(parent: Instance, from: Vector3, to: Vector3, lights: number, lightColor: Color3?)
	local delta = to - from
	local length = delta.Magnitude
	local frame = CFrame.lookAt(from + delta * 0.5, to)
	for _, offset in { Vector3.new(-0.8, 0.8, 0), Vector3.new(0.8, 0.8, 0), Vector3.new(0, -0.6, 0) } do
		Kit.block(parent, "TrussRail", Vector3.new(0.35, 0.35, length), frame * CFrame.new(offset), World.Steel, Enum.Material.Metal, false)
	end
	local braces = math.max(2, math.floor(length / 3))
	for index = 0, braces do
		local z = -length * 0.5 + index * length / braces
		Kit.block(parent, "TrussBrace", Vector3.new(1.7, 1.5, 0.2), frame * CFrame.new(0, 0.1, z), World.SteelLight, Enum.Material.Metal, false).Transparency = 0.2
	end
	for index = 1, lights do
		local z = -length * 0.5 + (index - 0.5) * length / lights
		local can = Kit.block(parent, "Spotlight", Vector3.new(1, 1.2, 1), frame * CFrame.new(0, -1.4, z), World.HazardBlack, Enum.Material.Metal, false)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 60
		light.Range = 40
		light.Brightness = 1.4
		light.Color = lightColor or Color3.fromRGB(255, 244, 222)
		light.Shadows = false
		light.Parent = can
	end
end

-- Props ---------------------------------------------------------------------------------------

function Kit.crate(parent: Instance, floorCFrame: CFrame, size: number)
	local body = Kit.block(parent, "Crate", Vector3.one * size, floorCFrame * CFrame.new(0, size * 0.5, 0), Color3.fromRGB(132, 108, 70))
	body.Material = Enum.Material.WoodPlanks
	for _, y in { 0.15, 0.85 } do
		Kit.block(parent, "CrateBand", Vector3.new(size + 0.1, 0.25, size + 0.1), floorCFrame * CFrame.new(0, size * y, 0), World.Steel, Enum.Material.Metal, false)
	end
end

function Kit.sandbags(parent: Instance, floorCFrame: CFrame, length: number)
	local count = math.max(2, math.floor(length / 2.2))
	for row = 0, 1 do
		for index = 1, count - row do
			local x = -length * 0.5 + (index - 0.5 + row * 0.5) * (length / count)
			local bag = Kit.block(
				parent,
				"Sandbag",
				Vector3.new(length / count * 0.95, 1, 1.6),
				floorCFrame * CFrame.new(x, 0.5 + row * 0.9, 0),
				Color3.fromRGB(176, 158, 112),
				Enum.Material.Fabric
			)
			bag.Shape = Enum.PartType.Block
		end
	end
end

function Kit.container(parent: Instance, floorCFrame: CFrame, color: Color3)
	local size = Vector3.new(8, 8.5, 20)
	Kit.block(parent, "Container", size, floorCFrame * CFrame.new(0, size.Y * 0.5, 0), color, Enum.Material.CorrodedMetal)
	for index = -4, 4 do
		Kit.block(parent, "Rib", Vector3.new(size.X + 0.2, size.Y - 0.6, 0.3), floorCFrame * CFrame.new(0, size.Y * 0.5, index * 2.2), color, Enum.Material.Metal, false)
	end
end

function Kit.cable(parent: Instance, from: Vector3, to: Vector3)
	local mid = (from + to) * 0.5
	Kit.floorLine(parent, from, mid + Vector3.new(0.6, 0, 0), 0.4, World.HazardBlack)
	Kit.floorLine(parent, mid + Vector3.new(0.6, 0, 0), to, 0.4, World.HazardBlack)
end

return Kit

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
		local part =
			Kit.block(parent, `{name}_{index}`, Vector3.new(arc * 1.04, height, width), cframe, color, material, false)
		table.insert(list, part)
	end
	return list
end

-- Rounded concrete arch. `cframe` is the floor centre of the opening; the arch spans local X.
function Kit.arch(
	parent: Instance,
	name: string,
	cframe: CFrame,
	width: number,
	height: number,
	depth: number,
	color: Color3
): Model
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
	local screen = Kit.block(
		parent,
		name,
		Vector3.new(size.X, size.Y, 0.2),
		cframe,
		World.Screen,
		Enum.Material.SmoothPlastic,
		false
	)
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
	Kit.block(
		parent,
		name .. "Post",
		Vector3.new(1.2, postHeight, 1.2),
		floorCFrame * CFrame.new(0, postHeight * 0.5, 0.8),
		World.Steel,
		Enum.Material.Metal
	)
	local center = floorCFrame * CFrame.new(0, postHeight + size.Y * 0.5, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	return Kit.screen(parent, name, center, size, kind, attributes)
end

-- Console with a ProximityPrompt. The client opens the panel named by `terminal`.
function Kit.terminal(
	parent: Instance,
	name: string,
	floorCFrame: CFrame,
	terminal: string,
	actionText: string,
	objectText: string,
	accent: Color3
): Part
	local model = Instance.new("Model")
	model.Name = name
	Kit.block(
		model,
		"Base",
		Vector3.new(3.4, 3.2, 2),
		floorCFrame * CFrame.new(0, 1.6, 0),
		World.Steel,
		Enum.Material.Metal
	)
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
		Kit.block(
			parent,
			"TrussRail",
			Vector3.new(0.35, 0.35, length),
			frame * CFrame.new(offset),
			World.Steel,
			Enum.Material.Metal,
			false
		)
	end
	local braces = math.max(2, math.floor(length / 3))
	for index = 0, braces do
		local z = -length * 0.5 + index * length / braces
		Kit.block(
			parent,
			"TrussBrace",
			Vector3.new(1.7, 1.5, 0.2),
			frame * CFrame.new(0, 0.1, z),
			World.SteelLight,
			Enum.Material.Metal,
			false
		).Transparency =
			0.2
	end
	for index = 1, lights do
		local z = -length * 0.5 + (index - 0.5) * length / lights
		local can = Kit.block(
			parent,
			"Spotlight",
			Vector3.new(1, 1.2, 1),
			frame * CFrame.new(0, -1.4, z),
			World.HazardBlack,
			Enum.Material.Metal,
			false
		)
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

-- Flat concrete roof over a rectangular area with a framed glass skylight in the middle.
-- `frame` is the floor centre; width runs along local X, depth along local Z.
function Kit.roof(parent: Instance, frame: CFrame, width: number, depth: number, height: number, skylight: Vector2?)
	local thickness = 1.4
	local y = height + thickness * 0.5
	local window = skylight or Vector2.zero
	if window.X <= 0 or window.Y <= 0 then
		Kit.block(
			parent,
			"Roof",
			Vector3.new(width, thickness, depth),
			frame * CFrame.new(0, y, 0),
			World.ConcreteMid,
			Enum.Material.Concrete
		)
	else
		local sideWidth = (width - window.X) * 0.5
		local endDepth = (depth - window.Y) * 0.5
		for _, sign in { -1, 1 } do
			Kit.block(
				parent,
				"Roof",
				Vector3.new(sideWidth, thickness, depth),
				frame * CFrame.new(sign * (window.X * 0.5 + sideWidth * 0.5), y, 0),
				World.ConcreteMid,
				Enum.Material.Concrete
			)
			Kit.block(
				parent,
				"Roof",
				Vector3.new(window.X, thickness, endDepth),
				frame * CFrame.new(0, y, sign * (window.Y * 0.5 + endDepth * 0.5)),
				World.ConcreteMid,
				Enum.Material.Concrete
			)
		end
		local glass = Kit.block(
			parent,
			"Skylight",
			Vector3.new(window.X, 0.3, window.Y),
			frame * CFrame.new(0, y, 0),
			Color3.fromRGB(170, 214, 240),
			Enum.Material.Glass
		)
		glass.Transparency = 0.65
		glass.CastShadow = false
		local mullions = math.max(1, math.floor(window.X / 8))
		for index = 1, mullions - 1 do
			Kit.block(
				parent,
				"Mullion",
				Vector3.new(0.5, 0.6, window.Y),
				frame * CFrame.new(-window.X * 0.5 + index * window.X / mullions, y + 0.2, 0),
				World.Steel,
				Enum.Material.Metal,
				false
			)
		end
		Kit.block(
			parent,
			"Mullion",
			Vector3.new(window.X, 0.6, 0.5),
			frame * CFrame.new(0, y + 0.2, 0),
			World.Steel,
			Enum.Material.Metal,
			false
		)
	end
	-- Warm ceiling lights so covered rooms never go dark.
	for _, offset in { Vector3.new(-width * 0.3, 0, 0), Vector3.new(width * 0.3, 0, 0) } do
		local lamp = Kit.block(
			parent,
			"CeilingLamp",
			Vector3.new(2.4, 0.4, 2.4),
			frame * CFrame.new(offset + Vector3.new(0, height - 0.3, 0)),
			World.Steel,
			Enum.Material.Metal,
			false
		)
		local light = Instance.new("PointLight")
		light.Range = math.max(width, depth) * 0.6
		light.Brightness = 1
		light.Color = Color3.fromRGB(255, 240, 220)
		light.Parent = lamp
		Kit.glow(
			parent,
			"LampGlow",
			Vector3.new(2, 0.08, 2),
			frame * CFrame.new(offset + Vector3.new(0, height - 0.55, 0)),
			Color3.fromRGB(255, 244, 228)
		)
	end
end

-- Ring roof on a round hall with a round glass skylight in the centre.
function Kit.roundRoof(parent: Instance, center: CFrame, outer: number, skylightRadius: number, height: number)
	local segments = 32
	local width = outer - skylightRadius
	for index = 0, segments - 1 do
		local angle = (index + 0.5) / segments * math.pi * 2
		local frame = center
			* CFrame.Angles(0, -angle, 0)
			* CFrame.new(0, height + 0.7, -(skylightRadius + width * 0.5))
		Kit.block(
			parent,
			"Roof",
			Vector3.new(2 * math.pi * outer / segments * 1.05, 1.4, width),
			frame,
			World.ConcreteMid,
			Enum.Material.Concrete
		)
		if index % 4 == 0 then
			local lamp = Kit.block(
				parent,
				"CeilingLamp",
				Vector3.new(2.4, 0.4, 2.4),
				frame * CFrame.new(0, -1, -width * 0.2),
				World.Steel,
				Enum.Material.Metal,
				false
			)
			local light = Instance.new("PointLight")
			light.Range = 30
			light.Brightness = 1.1
			light.Color = Color3.fromRGB(255, 240, 220)
			light.Parent = lamp
		end
	end
	local glass = Kit.disc(
		parent,
		"Skylight",
		skylightRadius + 0.5,
		0.3,
		center * CFrame.new(0, height + 0.7, 0),
		Color3.fromRGB(170, 214, 240),
		Enum.Material.Glass
	)
	glass.Transparency = 0.65
	glass.CastShadow = false
	Kit.ring(
		parent,
		"SkylightFrame",
		center * CFrame.new(0, height + 0.7, 0),
		skylightRadius,
		1,
		1.5,
		28,
		World.Steel,
		Enum.Material.Metal
	)
end

-- Props ---------------------------------------------------------------------------------------

local WOOD = Color3.fromRGB(150, 118, 76)
local WOOD_DARK = Color3.fromRGB(104, 78, 48)
local CRATE_LABELS = { "FRAGILE", "PARTS", "AMMO", "HANDLE WITH CARE", "SUPPLY", "SERVO UNITS" }

-- Text painted on a part face (stencils, labels).
function Kit.stencil(part: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Adornee = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.86, 0.36)
	label.Position = UDim2.fromScale(0.07, 0.32)
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = color
	label.TextTransparency = 0.15
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

-- A wooden shipping crate: planked body, darker edge battens, cross braces, and a stencil.
function Kit.crate(parent: Instance, floorCFrame: CFrame, size: number, seed: number?)
	local model = Instance.new("Model")
	model.Name = "Crate"
	local center = floorCFrame * CFrame.new(0, size * 0.5, 0)
	local body = Kit.block(model, "Body", Vector3.one * (size - 0.08), center, WOOD, Enum.Material.WoodPlanks)
	local half = size * 0.5
	local batten = math.max(0.18, size * 0.09)
	-- Twelve edge battens.
	for _, axis in { "X", "Y", "Z" } do
		for _, a in { -1, 1 } do
			for _, b in { -1, 1 } do
				local offset: Vector3
				local blockSize: Vector3
				if axis == "X" then
					offset = Vector3.new(0, a * (half - batten * 0.5), b * (half - batten * 0.5))
					blockSize = Vector3.new(size, batten, batten)
				elseif axis == "Y" then
					offset = Vector3.new(a * (half - batten * 0.5), 0, b * (half - batten * 0.5))
					blockSize = Vector3.new(batten, size, batten)
				else
					offset = Vector3.new(a * (half - batten * 0.5), b * (half - batten * 0.5), 0)
					blockSize = Vector3.new(batten, batten, size)
				end
				Kit.block(model, "Batten", blockSize, center * CFrame.new(offset), WOOD_DARK, Enum.Material.Wood, false)
			end
		end
	end
	-- Diagonal braces on the front and back faces.
	for _, z in { -1, 1 } do
		Kit.block(
			model,
			"Brace",
			Vector3.new(size * 1.25, batten * 0.8, batten * 0.5),
			center * CFrame.new(0, 0, z * (half + 0.02)) * CFrame.Angles(0, 0, math.rad(45)),
			WOOD_DARK,
			Enum.Material.Wood,
			false
		)
	end
	local label = CRATE_LABELS[((seed or 1) % #CRATE_LABELS) + 1]
	Kit.stencil(body, Enum.NormalId.Right, label, Color3.fromRGB(40, 30, 20))
	model.Parent = parent
end

-- Oil drum with rims and a painted band.
function Kit.barrel(parent: Instance, floorCFrame: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Barrel"
	Kit.disc(model, "Drum", 1.4, 4, floorCFrame * CFrame.new(0, 2, 0), color, Enum.Material.Metal)
	for _, y in { 0.15, 2, 3.85 } do
		Kit.disc(
			model,
			"Rim",
			1.48,
			0.18,
			floorCFrame * CFrame.new(0, y, 0),
			color:Lerp(Color3.new(0, 0, 0), 0.35),
			Enum.Material.Metal
		)
	end
	Kit.disc(
		model,
		"Cap",
		0.25,
		0.1,
		floorCFrame * CFrame.new(0.6, 4.02, 0.4),
		Color3.fromRGB(40, 40, 44),
		Enum.Material.Metal
	)
	model.Parent = parent
end

-- Wooden pallet, optionally stacked with sacks.
function Kit.pallet(parent: Instance, floorCFrame: CFrame, loaded: boolean)
	local model = Instance.new("Model")
	model.Name = "Pallet"
	for _, x in { -1.8, 0, 1.8 } do
		Kit.block(
			model,
			"Stringer",
			Vector3.new(0.5, 0.5, 4.4),
			floorCFrame * CFrame.new(x, 0.25, 0),
			WOOD_DARK,
			Enum.Material.Wood
		)
	end
	for index = -2, 2 do
		Kit.block(
			model,
			"Deck",
			Vector3.new(4.4, 0.18, 0.7),
			floorCFrame * CFrame.new(0, 0.59, index * 0.9),
			WOOD,
			Enum.Material.WoodPlanks
		)
	end
	if loaded then
		for row = 0, 1 do
			for index = -1, 1 do
				local sack = Kit.block(
					model,
					"Sack",
					Vector3.new(1.3, 0.8, 3.6),
					floorCFrame
						* CFrame.new(index * 1.35, 1.1 + row * 0.8, 0)
						* CFrame.Angles(0, math.rad((index + row) * 4), 0),
					Color3.fromRGB(196, 178, 140),
					Enum.Material.Fabric
				)
				sack.Shape = Enum.PartType.Block
			end
		end
	end
	model.Parent = parent
end

-- Red rolling toolbox with drawers.
function Kit.toolbox(parent: Instance, floorCFrame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Toolbox"
	local red = Color3.fromRGB(176, 40, 40)
	Kit.block(model, "Cabinet", Vector3.new(3.2, 3.2, 1.8), floorCFrame * CFrame.new(0, 2, 0), red, Enum.Material.Metal)
	for index = 0, 3 do
		Kit.block(
			model,
			"Handle",
			Vector3.new(2.2, 0.12, 0.12),
			floorCFrame * CFrame.new(0, 1.0 + index * 0.75, -0.96),
			Color3.fromRGB(200, 200, 205),
			Enum.Material.Metal,
			false
		)
	end
	for _, x in { -1.3, 1.3 } do
		for _, z in { -0.6, 0.6 } do
			Kit.disc(
				model,
				"Caster",
				0.2,
				0.2,
				floorCFrame * CFrame.new(x, 0.2, z) * CFrame.Angles(math.rad(90), 0, 0),
				Color3.fromRGB(30, 30, 32),
				Enum.Material.SmoothPlastic
			)
		end
	end
	Kit.block(
		model,
		"Wrench",
		Vector3.new(1.6, 0.12, 0.35),
		floorCFrame * CFrame.new(0.2, 3.66, 0.1) * CFrame.Angles(0, math.rad(25), 0),
		Color3.fromRGB(170, 170, 176),
		Enum.Material.Metal,
		false
	)
	model.Parent = parent
end

-- Traffic cone with reflective bands.
function Kit.cone(parent: Instance, floorCFrame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Cone"
	local orange = Color3.fromRGB(240, 110, 30)
	Kit.block(
		model,
		"Base",
		Vector3.new(1.4, 0.15, 1.4),
		floorCFrame * CFrame.new(0, 0.08, 0),
		Color3.fromRGB(30, 30, 32),
		Enum.Material.SmoothPlastic
	)
	for index, radius in { 0.55, 0.45, 0.35, 0.25 } do
		Kit.disc(
			model,
			"Cone",
			radius,
			0.5,
			floorCFrame * CFrame.new(0, 0.15 + (index - 0.5) * 0.5, 0),
			if index == 2 then Color3.fromRGB(235, 235, 235) else orange,
			Enum.Material.SmoothPlastic
		)
	end
	model.Parent = parent
end

-- Row of steel lockers.
function Kit.lockers(parent: Instance, floorCFrame: CFrame, count: number)
	local model = Instance.new("Model")
	model.Name = "Lockers"
	for index = 1, count do
		local x = (index - (count + 1) * 0.5) * 1.9
		local door = Kit.block(
			model,
			"Locker",
			Vector3.new(1.8, 6, 1.8),
			floorCFrame * CFrame.new(x, 3, 0),
			Color3.fromRGB(70, 96, 112),
			Enum.Material.Metal
		)
		for row = 0, 2 do
			Kit.block(
				model,
				"Vent",
				Vector3.new(1, 0.08, 0.05),
				floorCFrame * CFrame.new(x, 5.1 + row * 0.2, -0.92),
				Color3.fromRGB(40, 54, 64),
				Enum.Material.Metal,
				false
			)
		end
		Kit.block(
			model,
			"Latch",
			Vector3.new(0.12, 0.6, 0.1),
			floorCFrame * CFrame.new(x + 0.6, 3.2, -0.95),
			Color3.fromRGB(190, 190, 196),
			Enum.Material.Metal,
			false
		)
		door.Name = `Locker_{index}`
	end
	model.Parent = parent
end

-- Gas cylinders chained to a frame.
function Kit.gasCylinders(parent: Instance, floorCFrame: CFrame)
	local model = Instance.new("Model")
	model.Name = "GasCylinders"
	for index, color in { Color3.fromRGB(60, 150, 70), Color3.fromRGB(200, 200, 205), Color3.fromRGB(60, 90, 170) } do
		local x = (index - 2) * 1.1
		Kit.disc(model, "Cylinder", 0.5, 4.2, floorCFrame * CFrame.new(x, 2.1, 0), color, Enum.Material.Metal)
		Kit.disc(
			model,
			"Valve",
			0.22,
			0.5,
			floorCFrame * CFrame.new(x, 4.45, 0),
			Color3.fromRGB(170, 150, 60),
			Enum.Material.Metal
		)
	end
	Kit.block(
		model,
		"Chain",
		Vector3.new(3.6, 0.15, 0.15),
		floorCFrame * CFrame.new(0, 3, -0.55),
		Color3.fromRGB(150, 150, 156),
		Enum.Material.Metal,
		false
	)
	Kit.block(
		model,
		"Rack",
		Vector3.new(3.8, 4.6, 0.3),
		floorCFrame * CFrame.new(0, 2.3, 0.7),
		World.Steel,
		Enum.Material.Metal
	)
	model.Parent = parent
end

-- Stack covered by a tarp with ropes.
function Kit.tarpStack(parent: Instance, floorCFrame: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "TarpStack"
	local tarp = Kit.block(
		model,
		"Tarp",
		Vector3.new(6, 3.6, 4.4),
		floorCFrame * CFrame.new(0, 1.8, 0),
		color,
		Enum.Material.Fabric
	)
	tarp.Shape = Enum.PartType.Block
	Kit.wedge(
		model,
		"TarpPeak",
		Vector3.new(6, 0.8, 2.2),
		floorCFrame * CFrame.new(0, 4, -1.1) * CFrame.Angles(0, math.pi, 0),
		color
	)
	Kit.wedge(model, "TarpPeak", Vector3.new(6, 0.8, 2.2), floorCFrame * CFrame.new(0, 4, 1.1), color)
	for _, x in { -1.8, 1.8 } do
		Kit.block(
			model,
			"Rope",
			Vector3.new(0.12, 0.12, 4.6),
			floorCFrame * CFrame.new(x, 3.62, 0),
			Color3.fromRGB(196, 170, 120),
			Enum.Material.Fabric,
			false
		)
	end
	model.Parent = parent
end

-- Cable spool on its side.
function Kit.spool(parent: Instance, floorCFrame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Spool"
	local axis = floorCFrame * CFrame.new(0, 1.6, 0)
	for _, z in { -0.9, 0.9 } do
		Kit.disc(
			model,
			"Flange",
			1.6,
			0.2,
			axis * CFrame.new(0, 0, z) * CFrame.Angles(math.rad(90), 0, 0),
			WOOD,
			Enum.Material.WoodPlanks
		)
	end
	Kit.disc(
		model,
		"Core",
		1.05,
		1.6,
		axis * CFrame.Angles(math.rad(90), 0, 0),
		Color3.fromRGB(30, 30, 34),
		Enum.Material.Fabric
	)
	model.Parent = parent
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
	Kit.block(
		parent,
		"Container",
		size,
		floorCFrame * CFrame.new(0, size.Y * 0.5, 0),
		color,
		Enum.Material.CorrodedMetal
	)
	for index = -4, 4 do
		Kit.block(
			parent,
			"Rib",
			Vector3.new(size.X + 0.2, size.Y - 0.6, 0.3),
			floorCFrame * CFrame.new(0, size.Y * 0.5, index * 2.2),
			color,
			Enum.Material.Metal,
			false
		)
	end
end

function Kit.cable(parent: Instance, from: Vector3, to: Vector3)
	local mid = (from + to) * 0.5
	Kit.floorLine(parent, from, mid + Vector3.new(0.6, 0, 0), 0.4, World.HazardBlack)
	Kit.floorLine(parent, mid + Vector3.new(0.6, 0, 0), to, 0.4, World.HazardBlack)
end

return Kit

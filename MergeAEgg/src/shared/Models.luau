-- Merge A Egg: every 3D model in the game, built from parts in a clean blocky style.
-- Pets, guardians, eggs, nests, the bat, treadmills, the Fuse Machine, stalls and props.
-- All builders return anchored models centred on the ground at the origin, facing -Z.

local Config = require(script.Parent:WaitForChild("Config"))

local Models = {}

local c = Color3.fromRGB
local rad = math.rad
local WHITE = c(255, 255, 255)
local BLACK = c(20, 20, 25)
local GOLD = c(255, 200, 40)
local BEAK = c(255, 170, 40)

---------------------------------------------------------------------------
-- Part helpers
---------------------------------------------------------------------------

local function applyProps(instance, props)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Models.part(props): BasePart
	local className = props.ClassName or "Part"
	props.ClassName = nil
	local p = Instance.new(className)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	return applyProps(p, props)
end

local part = Models.part

-- Cylinder whose round faces point up (Roblox cylinders run along X).
local function upCylinder(parent, name, diameter, height, cf, color, extra)
	local props = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = cf * CFrame.Angles(0, 0, rad(90)),
		Color = color,
		Parent = parent,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end
Models.upCylinder = upCylinder

local function ball(parent, name, diameter, position, color, extra)
	local props = {
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(position),
		Color = color,
		Parent = parent,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end
Models.ball = ball

local function box(parent, name, size, cf, color, extra)
	local props = {
		Name = name,
		Size = size,
		CFrame = if typeof(cf) == "Vector3" then CFrame.new(cf) else cf,
		Color = color,
		Parent = parent,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end
Models.box = box

local function wedge(parent, name, size, cf, color, extra)
	local props = {
		ClassName = "WedgePart",
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Parent = parent,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end

local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	return model
end

local function setRoot(model: Model, size: Vector3, cf: CFrame?): BasePart
	local root = part({
		Name = "Root",
		Size = size,
		CFrame = cf or CFrame.new(0, size.Y / 2, 0),
		Transparency = 1,
		Parent = model,
	})
	model.PrimaryPart = root
	return root
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function billboard(parent, text, color, size, offset, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = size or UDim2.fromScale(8, 2)
	gui.StudsOffsetWorldSpace = offset or Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 200
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or WHITE
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = BLACK
	stroke.Parent = label
	gui.Parent = parent
	return gui, label
end
Models.billboard = billboard

---------------------------------------------------------------------------
-- Pets: templates
---------------------------------------------------------------------------

-- Each template builds the body and returns anchors that features attach to.
-- heads: list of { cf = CFrame, size = Vector3 } (empty when headless).

local function addEyes(model, head, s, opts)
	local front = head.cf * CFrame.new(0, 0, -head.size.Z / 2 - 0.02 * s)
	local eyeSize = if opts.big then Vector3.new(0.38, 0.46, 0.06) else Vector3.new(0.24, 0.32, 0.06)
	local spread = head.size.X * 0.24
	for _, side in { -1, 1 } do
		local eyeCf = front * CFrame.new(side * spread, head.size.Y * 0.12, 0)
		box(model, "Eye", eyeSize * s, eyeCf, opts.color or BLACK, opts.neon and { Material = Enum.Material.Neon } or nil)
		box(model, "EyeShine", Vector3.new(0.09, 0.11, 0.02) * s, eyeCf * CFrame.new(-0.05 * s, 0.07 * s, -0.04 * s), WHITE)
	end
end

local function legs4(model, s, color, paw, spreadX, spreadZ, height)
	for _, x in { -spreadX, spreadX } do
		for _, z in { -spreadZ, spreadZ } do
			box(model, "Leg", Vector3.new(0.55, height, 0.55) * s, Vector3.new(x * s, height / 2 * s, z * s), color)
			box(model, "Paw", Vector3.new(0.62, 0.22, 0.66) * s, Vector3.new(x * s, 0.11 * s, (z - 0.03) * s), paw)
		end
	end
end

local templates = {}

function templates.quad(model, def, s, flags)
	local primary, secondary = def.primary, def.secondary
	legs4(model, s, primary, darken(secondary, 0.1), 0.72, 1.05, 1)
	local body = box(model, "Body", Vector3.new(2.2, 1.5, 3) * s, Vector3.new(0, 1.75 * s, 0), primary)
	box(model, "Belly", Vector3.new(1.7, 0.1, 2.3) * s, Vector3.new(0, 1.0 * s, 0), secondary)
	local heads = {}
	if not flags.headless then
		local headY, headZ = 2.55, -1.8
		if flags.long_neck then
			box(model, "Neck", Vector3.new(0.8, 1.6, 0.8) * s, CFrame.new(0, 2.65 * s, -1.35 * s) * CFrame.Angles(rad(-20), 0, 0), primary)
			headY, headZ = 3.45, -1.8
		end
		local xs = if flags.two_heads then { -0.75, 0.75 } else { 0 }
		for _, x in xs do
			local cf = CFrame.new(x * s, headY * s, headZ * s)
			local size = Vector3.new(1.5, 1.4, 1.4) * s
			box(model, "Head", size, cf, flags.headColor or primary)
			local snout = box(model, "Snout", Vector3.new(0.8, 0.5, 0.35) * s, cf * CFrame.new(0, -0.32 * s, -0.85 * s), secondary)
			box(model, "Nose", Vector3.new(0.3, 0.18, 0.06) * s, snout.CFrame * CFrame.new(0, 0.12 * s, -0.19 * s), BLACK)
			table.insert(heads, { cf = cf, size = size })
		end
	end
	return {
		heads = heads,
		body = body,
		back = Vector3.new(0, 2.5 * s, 0.6 * s),
		rear = Vector3.new(0, 2.0 * s, 1.55 * s),
		side = 1.1,
		top = 2.5,
	}
end

function templates.bird(model, def, s, flags)
	local primary = def.primary
	for _, x in { -0.4, 0.4 } do
		box(model, "Leg", Vector3.new(0.18, 0.7, 0.18) * s, Vector3.new(x * s, 0.35 * s, 0), BEAK)
		box(model, "Foot", Vector3.new(0.45, 0.1, 0.55) * s, Vector3.new(x * s, 0.05 * s, -0.12 * s), BEAK)
	end
	local body = ball(model, "Body", 2.1 * s, Vector3.new(0, 1.65 * s, 0), primary)
	ball(model, "Chest", 1.5 * s, Vector3.new(0, 1.5 * s, -0.42 * s), lighten(primary, 0.25))
	local heads = {}
	if not flags.headless then
		local cf = CFrame.new(0, 2.85 * s, -0.55 * s)
		ball(model, "Head", 1.4 * s, cf.Position, flags.headColor or primary)
		table.insert(heads, { cf = cf, size = Vector3.one * 1.4 * s })
	end
	return {
		heads = heads,
		body = body,
		back = Vector3.new(0, 2.6 * s, 0.4 * s),
		rear = Vector3.new(0, 1.8 * s, 1.0 * s),
		side = 1.0,
		top = 3.5,
		isBird = true,
	}
end

function templates.biped(model, def, s, flags)
	local primary, secondary = def.primary, def.secondary
	for _, x in { -0.48, 0.48 } do
		box(model, "Leg", Vector3.new(0.72, 1.2, 0.75) * s, Vector3.new(x * s, 0.6 * s, 0), darken(primary, 0.12))
		box(model, "Foot", Vector3.new(0.8, 0.25, 0.95) * s, Vector3.new(x * s, 0.125 * s, -0.1 * s), darken(primary, 0.3))
	end
	local body = box(model, "Body", Vector3.new(1.95, 1.9, 1.25) * s, Vector3.new(0, 2.15 * s, 0), primary)
	box(model, "Belly", Vector3.new(1.25, 1.2, 0.05) * s, Vector3.new(0, 2.05 * s, -0.64 * s), secondary)
	for _, x in { -1.3, 1.3 } do
		box(model, "Arm", Vector3.new(0.62, 1.7, 0.62) * s, CFrame.new(x * s, 2.05 * s, 0) * CFrame.Angles(0, 0, rad(x > 0 and 8 or -8)), primary)
		box(model, "Hand", Vector3.new(0.7, 0.45, 0.7) * s, Vector3.new(x * 1.06 * s, 1.15 * s, 0), darken(primary, 0.15))
	end
	local heads = {}
	if not flags.headless then
		local cf = CFrame.new(0, 3.85 * s, 0)
		local size = Vector3.new(1.55, 1.45, 1.4) * s
		box(model, "Head", size, cf, flags.headColor or primary)
		table.insert(heads, { cf = cf, size = size })
	end
	return {
		heads = heads,
		body = body,
		back = Vector3.new(0, 2.6 * s, 0.7 * s),
		rear = Vector3.new(0, 1.6 * s, 0.65 * s),
		side = 1.0,
		top = 4.6,
	}
end

function templates.slime(model, def, s, flags)
	local primary = def.primary
	local body = ball(model, "Body", 2.5 * s, Vector3.new(0, 1.25 * s, 0), primary)
	upCylinder(model, "Base", 2.4 * s, 0.3 * s, CFrame.new(0, 0.15 * s, 0), darken(primary, 0.1))
	box(model, "Mouth", Vector3.new(0.5, 0.12, 0.05) * s, Vector3.new(0, 0.95 * s, -1.2 * s), darken(primary, 0.6))
	local head = { cf = CFrame.new(0, 1.45 * s, 0), size = Vector3.new(2.2, 1.6, 2.3) * s }
	return {
		heads = { head },
		body = body,
		back = Vector3.new(0, 2.3 * s, 0.4 * s),
		rear = Vector3.new(0, 1.2 * s, 1.2 * s),
		side = 1.2,
		top = 2.5,
	}
end

function templates.serpent(model, def, s, flags)
	local primary, secondary = def.primary, def.secondary
	local segments = {
		{ 1.15, Vector3.new(0, 0.6, 0.3) },
		{ 1.05, Vector3.new(0, 0.55, 1.1) },
		{ 0.9, Vector3.new(0, 0.48, 1.8) },
		{ 0.7, Vector3.new(0, 0.4, 2.4) },
		{ 0.5, Vector3.new(0, 0.32, 2.85) },
	}
	for i, seg in segments do
		local color = if flags.stripes and i % 2 == 0 then secondary else primary
		ball(model, "Segment", seg[1] * s, seg[2] * s, color)
	end
	local body = ball(model, "Body", 1.15 * s, Vector3.new(0, 1.05 * s, -0.5 * s), primary)
	local heads = {}
	local headXs = if flags.three_heads then { -1.0, 0, 1.0 } else { 0 }
	for _, x in headXs do
		local neckTop = Vector3.new(x * s, 1.75 * s, -1.0 * s)
		box(model, "Neck", Vector3.new(0.6, 1.3, 0.6) * s, CFrame.lookAt(Vector3.new(0, 1.05 * s, -0.5 * s):Lerp(neckTop, 0.5), neckTop) * CFrame.Angles(rad(90), 0, 0), primary)
		local cf = CFrame.new(x * s, 2.05 * s, -1.25 * s)
		local size = Vector3.new(1.2, 0.95, 1.4) * s
		box(model, "Head", size, cf, primary)
		box(model, "Jaw", Vector3.new(1.0, 0.25, 1.1) * s, cf * CFrame.new(0, -0.55 * s, -0.1 * s), secondary)
		table.insert(heads, { cf = cf, size = size })
	end
	return {
		heads = heads,
		body = body,
		back = Vector3.new(0, 1.2 * s, 1.0 * s),
		rear = Vector3.new(0, 0.5 * s, 3.0 * s),
		side = 0.6,
		top = 2.6,
	}
end

function templates.bug(model, def, s, flags)
	local primary, secondary = def.primary, def.secondary
	ball(model, "Thorax", 1.3 * s, Vector3.new(0, 0.95 * s, 0), primary)
	local body = ball(model, "Abdomen", 1.75 * s, Vector3.new(0, 1.05 * s, 1.3 * s), darken(primary, 0.1))
	ball(model, "Marking", 0.7 * s, Vector3.new(0, 1.75 * s, 1.35 * s), secondary)
	for _, side in { -1, 1 } do
		for _, z in { -0.45, 0.05, 0.55 } do
			box(model, "Leg", Vector3.new(1.3, 0.16, 0.16) * s, CFrame.new(side * 0.8 * s, 0.55 * s, z * s) * CFrame.Angles(0, 0, rad(side * -30)), darken(primary, 0.35))
		end
	end
	local cf = CFrame.new(0, 1.05 * s, -0.95 * s)
	ball(model, "Head", 1.0 * s, cf.Position, primary)
	return {
		heads = { { cf = cf, size = Vector3.one * 1.0 * s } },
		body = body,
		back = Vector3.new(0, 1.9 * s, 1.2 * s),
		rear = Vector3.new(0, 1.1 * s, 2.15 * s),
		side = 0.9,
		top = 2.0,
		isBug = true,
	}
end

function templates.fish(model, def, s, flags)
	local primary, secondary = def.primary, def.secondary
	local body = ball(model, "Body", 1.9 * s, Vector3.new(0, 1.7 * s, 0), primary)
	wedge(model, "Tail", Vector3.new(0.15, 1.2, 0.9) * s, CFrame.new(0, 1.7 * s, 1.25 * s) * CFrame.Angles(0, 0, 0), secondary)
	wedge(model, "Fin", Vector3.new(0.12, 0.6, 0.8) * s, CFrame.new(0, 2.65 * s, 0.1 * s), secondary)
	for _, side in { -1, 1 } do
		box(model, "SideFin", Vector3.new(0.6, 0.1, 0.5) * s, CFrame.new(side * 0.95 * s, 1.5 * s, -0.1 * s) * CFrame.Angles(0, 0, rad(side * 25)), secondary)
	end
	return {
		heads = { { cf = CFrame.new(0, 1.75 * s, -0.25 * s), size = Vector3.new(1.6, 1.4, 1.4) * s } },
		body = body,
		back = Vector3.new(0, 2.6 * s, 0),
		rear = Vector3.new(0, 1.7 * s, 1.0 * s),
		side = 0.95,
		top = 2.7,
	}
end

---------------------------------------------------------------------------
-- Pets: features
---------------------------------------------------------------------------

local features = {}

local function eachHead(a, fn)
	for _, head in a.heads do
		fn(head)
	end
end

local function headTop(head, y)
	return head.cf * CFrame.new(0, head.size.Y / 2 + (y or 0), 0)
end

function features.ears_pointy(model, a, def, s, big)
	local scale = big and 1.8 or 1
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local cf = headTop(head, 0.28 * s * scale) * CFrame.new(side * head.size.X * 0.3, 0, 0) * CFrame.Angles(0, rad(side * 90), rad(side * -10))
			wedge(model, "Ear", Vector3.new(0.22, 0.6 * scale, 0.42 * scale) * s, cf, def.primary)
			wedge(model, "EarInner", Vector3.new(0.05, 0.38 * scale, 0.24 * scale) * s, cf * CFrame.new(side * -0.12 * s, -0.06 * s, 0), def.secondary)
		end
	end)
end

function features.ears_big(model, a, def, s)
	features.ears_pointy(model, a, def, s, true)
end

function features.ears_long(model, a, def, s)
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local cf = headTop(head, 0.55 * s) * CFrame.new(side * head.size.X * 0.22, 0, 0.1 * s) * CFrame.Angles(rad(-8), 0, rad(side * -8))
			box(model, "Ear", Vector3.new(0.32, 1.15, 0.2) * s, cf, def.primary)
			box(model, "EarInner", Vector3.new(0.17, 0.85, 0.03) * s, cf * CFrame.new(0, 0, -0.11 * s), def.secondary)
		end
	end)
end

function features.ears_round(model, a, def, s)
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local cf = headTop(head, 0.1 * s) * CFrame.new(side * head.size.X * 0.38, 0, 0)
			ball(model, "Ear", 0.55 * s, cf.Position, def.primary)
			ball(model, "EarInner", 0.3 * s, (cf * CFrame.new(0, 0, -0.18 * s)).Position, def.secondary)
		end
	end)
end

function features.tail(model, a, def, s)
	box(model, "Tail", Vector3.new(0.25, 0.25, 1.1) * s, CFrame.new(a.rear + Vector3.new(0, 0.2 * s, 0.35 * s)) * CFrame.Angles(rad(30), 0, 0), def.primary)
end

function features.tail_fluffy(model, a, def, s)
	ball(model, "Tail", 0.95 * s, a.rear + Vector3.new(0, 0.35 * s, 0.3 * s), def.primary)
	ball(model, "TailTip", 0.55 * s, a.rear + Vector3.new(0, 0.75 * s, 0.6 * s), def.secondary)
end

function features.tail_flat(model, a, def, s)
	box(model, "Tail", Vector3.new(0.95, 0.16, 1.2) * s, CFrame.new(a.rear + Vector3.new(0, -0.6 * s, 0.6 * s)) * CFrame.Angles(rad(-10), 0, 0), darken(def.primary, 0.35))
end

function features.tail_curl(model, a, def, s)
	ball(model, "Tail", 0.35 * s, a.rear + Vector3.new(0, 0.2 * s, 0.2 * s), def.secondary)
	ball(model, "Tail", 0.3 * s, a.rear + Vector3.new(0.15 * s, 0.45 * s, 0.32 * s), def.secondary)
end

function features.horns(model, a, def, s)
	local color = c(240, 230, 205)
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local base = headTop(head, 0.1 * s) * CFrame.new(side * head.size.X * 0.32, 0, 0.1 * s)
			box(model, "Horn", Vector3.new(0.28, 0.6, 0.28) * s, base * CFrame.Angles(0, 0, rad(side * -35)), color)
			box(model, "HornTip", Vector3.new(0.18, 0.4, 0.18) * s, base * CFrame.new(side * 0.32 * s, 0.4 * s, 0) * CFrame.Angles(0, 0, rad(side * -5)), color)
		end
	end)
end

function features.horn(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0) * CFrame.new(0, 0, -head.size.Z * 0.2)
		upCylinder(model, "Horn", 0.36 * s, 0.4 * s, base * CFrame.new(0, 0.2 * s, 0), GOLD, { Material = Enum.Material.Neon })
		upCylinder(model, "Horn", 0.24 * s, 0.4 * s, base * CFrame.new(0, 0.55 * s, 0), GOLD, { Material = Enum.Material.Neon })
		upCylinder(model, "Horn", 0.12 * s, 0.35 * s, base * CFrame.new(0, 0.9 * s, 0), GOLD, { Material = Enum.Material.Neon })
	end)
end

function features.antlers(model, a, def, s)
	local color = if def.secondary == GOLD or def.primary.R > 0.9 then c(255, 235, 160) else c(150, 105, 60)
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local base = headTop(head, 0) * CFrame.new(side * head.size.X * 0.3, 0, 0.1 * s)
			box(model, "Antler", Vector3.new(0.18, 1.2, 0.18) * s, base * CFrame.new(side * 0.2 * s, 0.55 * s, 0) * CFrame.Angles(0, 0, rad(side * -25)), color)
			box(model, "Antler", Vector3.new(0.15, 0.6, 0.15) * s, base * CFrame.new(side * 0.65 * s, 0.95 * s, 0) * CFrame.Angles(0, 0, rad(side * -70)), color)
			box(model, "Antler", Vector3.new(0.15, 0.55, 0.15) * s, base * CFrame.new(side * 0.35 * s, 1.15 * s, -0.1 * s) * CFrame.Angles(rad(-20), 0, rad(side * 15)), color)
		end
	end)
end

function features.wings(model, a, def, s)
	local color = if a.isBird then darken(def.primary, 0.12) else def.secondary
	local transparent = a.isBug
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * (a.side + 0.15) * s, a.back.Y - 0.2 * s, a.back.Z) * CFrame.Angles(rad(10), rad(side * 15), rad(side * 25))
		box(model, "Wing", Vector3.new(0.15, 1.1, 1.6) * s, cf, color, transparent and { Transparency = 0.35, Material = Enum.Material.Glass } or nil)
		box(model, "WingTip", Vector3.new(0.12, 0.7, 1.0) * s, cf * CFrame.new(side * 0.1 * s, 0.6 * s, 0.4 * s), lighten(color, 0.15), transparent and { Transparency = 0.35, Material = Enum.Material.Glass } or nil)
	end
end

function features.beak(model, a, def, s)
	eachHead(a, function(head)
		local front = head.cf * CFrame.new(0, -0.1 * s, -head.size.Z / 2 - 0.2 * s)
		box(model, "Beak", Vector3.new(0.5, 0.25, 0.45) * s, front, BEAK)
		box(model, "BeakLow", Vector3.new(0.38, 0.15, 0.32) * s, front * CFrame.new(0, -0.18 * s, 0.03 * s), darken(BEAK, 0.15))
	end)
end

function features.crest(model, a, def, s)
	eachHead(a, function(head)
		for i, z in { -0.25, 0, 0.25 } do
			box(model, "Crest", Vector3.new(0.18, 0.35 + (i == 2 and 0.15 or 0), 0.25) * s, headTop(head, 0.15 * s) * CFrame.new(0, 0, z * s), def.secondary)
		end
	end)
end

function features.mane(model, a, def, s)
	eachHead(a, function(head)
		box(model, "Mane", head.size + Vector3.new(0.5, 0.5, -0.4) * s, head.cf * CFrame.new(0, 0.1 * s, 0.45 * s), def.secondary)
		box(model, "ManeBack", Vector3.new(0.5, 0.9, 1.6) * s, CFrame.new(a.back + Vector3.new(0, 0.1 * s, -1.0 * s)), def.secondary)
	end)
end

function features.shell(model, a, def, s)
	ball(model, "Shell", 2.0 * s, a.back + Vector3.new(0, -0.2 * s, 0), def.secondary)
	ball(model, "ShellTop", 1.3 * s, a.back + Vector3.new(0, 0.35 * s, 0), lighten(def.secondary, 0.2))
end

function features.spikes(model, a, def, s)
	local color = lighten(def.secondary, 0.1)
	for i = -1, 2 do
		local pos = a.back + Vector3.new(0, 0.15 * s, (i * 0.5 - 0.3) * s)
		wedge(model, "Spike", Vector3.new(0.2, 0.5, 0.45) * s, CFrame.new(pos) * CFrame.Angles(0, rad(180), 0), color)
	end
end

function features.crown(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0.15 * s)
		box(model, "Crown", Vector3.new(head.size.X * 0.75, 0.3 * s, head.size.Z * 0.75), base, GOLD, { Material = Enum.Material.Metal, Reflectance = 0.2 })
		for _, offset in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1), Vector3.new(0, 0, -1) } do
			local pos = base * CFrame.new(offset.X * head.size.X * 0.3, 0.3 * s, offset.Z * head.size.Z * 0.3)
			box(model, "CrownPoint", Vector3.new(0.2, 0.35, 0.2) * s, pos, GOLD, { Material = Enum.Material.Metal })
		end
		ball(model, "Gem", 0.25 * s, (base * CFrame.new(0, 0.05 * s, -head.size.Z * 0.38)).Position, c(255, 40, 80), { Material = Enum.Material.Neon })
	end)
end

function features.glow(model, a, def, s)
	local light = Instance.new("PointLight")
	light.Color = def.secondary
	light.Range = 10 * s
	light.Brightness = 1.5
	light.Parent = a.body
	for _, child in model:GetChildren() do
		if child.Name == "Eye" and child:IsA("BasePart") then
			child.Material = Enum.Material.Neon
			child.Color = def.secondary
		end
	end
end

function features.sparkle(model, a, def, s)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = def.secondary
	sparkles.Parent = a.body
end

function features.claws(model, a, def, s)
	for _, side in { -1, 1 } do
		local pos = Vector3.new(side * 0.85 * s, 0.75 * s, -1.6 * s)
		box(model, "Claw", Vector3.new(0.5, 0.35, 0.6) * s, pos, def.secondary)
		box(model, "Pincer", Vector3.new(0.18, 0.3, 0.45) * s, pos + Vector3.new(side * 0.15 * s, 0.05 * s, -0.45 * s), def.secondary)
	end
end

function features.stinger(model, a, def, s)
	local points = { Vector3.new(0, 1.6, 2.2), Vector3.new(0, 2.3, 2.3), Vector3.new(0, 2.85, 1.9), Vector3.new(0, 3.05, 1.35) }
	for i, p in points do
		ball(model, "Tail", (0.6 - i * 0.07) * s, p * s, def.primary)
	end
	wedge(model, "Stinger", Vector3.new(0.18, 0.45, 0.35) * s, CFrame.new(Vector3.new(0, 2.85, 0.95) * s) * CFrame.Angles(rad(180), 0, 0), def.secondary, { Material = Enum.Material.Neon })
end

function features.hump(model, a, def, s)
	ball(model, "Hump", 1.3 * s, a.back + Vector3.new(0, -0.1 * s, 0.1 * s), def.primary)
end

function features.antenna(model, a, def, s)
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local base = headTop(head, 0) * CFrame.new(side * head.size.X * 0.2, 0, -head.size.Z * 0.1)
			box(model, "Antenna", Vector3.new(0.08, 0.7, 0.08) * s, base * CFrame.new(side * 0.1 * s, 0.3 * s, 0) * CFrame.Angles(0, 0, rad(side * -18)), darken(def.primary, 0.4))
			ball(model, "AntennaTip", 0.22 * s, (base * CFrame.new(side * 0.22 * s, 0.68 * s, 0)).Position, def.secondary)
		end
	end)
end

function features.fangs(model, a, def, s)
	eachHead(a, function(head)
		for _, side in { -1, 1 } do
			local pos = head.cf * CFrame.new(side * 0.18 * s, -head.size.Y * 0.32, -head.size.Z / 2 - 0.05 * s) * CFrame.Angles(rad(180), 0, 0)
			wedge(model, "Fang", Vector3.new(0.1, 0.25, 0.08) * s, pos, WHITE)
		end
	end)
end

function features.teeth(model, a, def, s)
	eachHead(a, function(head)
		box(model, "Teeth", Vector3.new(head.size.X * 0.7, 0.14 * s, 0.05 * s), head.cf * CFrame.new(0, -head.size.Y * 0.3, -head.size.Z / 2 - 0.05 * s), WHITE)
	end)
end

function features.snout(model, a, def, s)
	eachHead(a, function(head)
		local cf = head.cf * CFrame.new(0, -0.15 * s, -head.size.Z / 2 - 0.2 * s)
		box(model, "Snout", Vector3.new(0.7, 0.5, 0.35) * s, cf, lighten(def.secondary, 0.1))
		for _, side in { -1, 1 } do
			box(model, "Nostril", Vector3.new(0.1, 0.15, 0.04) * s, cf * CFrame.new(side * 0.15 * s, 0, -0.18 * s), darken(def.secondary, 0.5))
		end
	end)
end

function features.wool(model, a, def, s)
	local positions = {
		Vector3.new(-0.7, 2.2, -0.8), Vector3.new(0.7, 2.2, -0.8), Vector3.new(-0.75, 2.25, 0.2),
		Vector3.new(0.75, 2.25, 0.2), Vector3.new(0, 2.5, -0.3), Vector3.new(0, 2.45, 0.8),
		Vector3.new(-0.7, 2.1, 1.0), Vector3.new(0.7, 2.1, 1.0),
	}
	for _, p in positions do
		ball(model, "Wool", 1.05 * s, p * s, def.primary)
	end
end

function features.spots(model, a, def, s)
	for _, p in { Vector3.new(1.11, 1.9, -0.6), Vector3.new(1.11, 1.6, 0.7), Vector3.new(-1.11, 1.8, 0.1), Vector3.new(0.3, 2.51, 0.5) } do
		local size = if math.abs(p.X) > 1 then Vector3.new(0.04, 0.6, 0.75) else Vector3.new(0.7, 0.04, 0.6)
		box(model, "Spot", size * s, p * s, def.secondary)
	end
end

function features.stripes(model, a, def, s)
	if not a.body or a.body.Shape == Enum.PartType.Ball then
		return
	end
	local size = a.body.Size
	for i = -1, 1 do
		box(model, "Stripe", Vector3.new(size.X + 0.06 * s, size.Y + 0.06 * s, 0.25 * s), a.body.CFrame * CFrame.new(0, 0, i * size.Z * 0.3), def.secondary)
	end
end

function features.mask(model, a, def, s)
	eachHead(a, function(head)
		box(model, "Mask", Vector3.new(head.size.X + 0.04 * s, 0.4 * s, 0.05 * s), head.cf * CFrame.new(0, head.size.Y * 0.12, -head.size.Z / 2 - 0.01 * s), def.secondary)
	end)
end

function features.crystal(model, a, def, s)
	local offsets = { Vector3.new(0, 0.3, 0), Vector3.new(-0.45, 0.1, 0.4), Vector3.new(0.45, 0.05, -0.3) }
	for i, o in offsets do
		local height = (0.9 - i * 0.15) * s
		box(model, "Crystal", Vector3.new(0.35 * s, height, 0.35 * s), CFrame.new(a.back + o * s + Vector3.new(0, height / 2, 0)) * CFrame.Angles(rad(i * 12), rad(45), rad(-i * 10)), def.secondary, { Material = Enum.Material.Neon, Transparency = 0.1 })
	end
end

function features.drip(model, a, def, s)
	for _, p in { Vector3.new(-0.7, 0.5, -0.6), Vector3.new(0.8, 0.4, 0.3), Vector3.new(0.1, 0.35, 1.0) } do
		ball(model, "Drip", 0.4 * s, p * s, def.secondary, { Material = Enum.Material.Glass, Transparency = 0.15 })
	end
end

function features.toxic_spots(model, a, def, s)
	for _, p in { Vector3.new(0.9, 0.3, -0.4), Vector3.new(-0.9, 0.1, 0.5), Vector3.new(0.4, 0.75, 0.6), Vector3.new(-0.3, 0.7, -0.6) } do
		ball(model, "ToxicSpot", 0.35 * s, a.body.Position + p * s, def.secondary, { Material = Enum.Material.Neon })
	end
end

function features.gasmask(model, a, def, s)
	eachHead(a, function(head)
		local cf = head.cf * CFrame.new(0, -0.2 * s, -head.size.Z / 2 - 0.2 * s)
		box(model, "Mask", Vector3.new(0.95, 0.65, 0.35) * s, cf, c(60, 60, 65))
		for _, side in { -1, 1 } do
			upCylinder(model, "Filter", 0.35 * s, 0.35 * s, cf * CFrame.new(side * 0.45 * s, -0.15 * s, -0.1 * s) * CFrame.Angles(rad(90), 0, 0), c(250, 210, 40))
		end
		box(model, "Goggles", Vector3.new(1.0, 0.3, 0.06) * s, head.cf * CFrame.new(0, head.size.Y * 0.15, -head.size.Z / 2 - 0.05 * s), c(130, 255, 80), { Material = Enum.Material.Neon })
	end)
end

function features.beard(model, a, def, s)
	eachHead(a, function(head)
		box(model, "Beard", Vector3.new(0.4, 0.55, 0.3) * s, head.cf * CFrame.new(0, -head.size.Y * 0.62, -head.size.Z * 0.35), def.secondary)
	end)
end

function features.fan_tail(model, a, def, s)
	for i = -2, 2 do
		local color = if i % 2 == 0 then def.secondary else c(240, 170, 60)
		box(model, "Feather", Vector3.new(0.4, 1.6, 0.12) * s, CFrame.new(a.rear + Vector3.new(0, 0.5 * s, 0.3 * s)) * CFrame.Angles(0, 0, rad(i * 22)) * CFrame.new(0, 0.6 * s, 0), color)
	end
end

function features.nose_ring(model, a, def, s)
	eachHead(a, function(head)
		upCylinder(model, "NoseRing", 0.45 * s, 0.08 * s, head.cf * CFrame.new(0, -0.55 * s, -head.size.Z / 2 - 0.42 * s) * CFrame.Angles(rad(90), 0, 0), GOLD, { Material = Enum.Material.Metal })
	end)
end

function features.straw_hat(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0.05 * s)
		upCylinder(model, "HatBrim", 2.0 * s, 0.1 * s, base, c(225, 190, 100))
		upCylinder(model, "HatTop", 1.0 * s, 0.55 * s, base * CFrame.new(0, 0.3 * s, 0), c(225, 190, 100))
		upCylinder(model, "HatBand", 1.04 * s, 0.14 * s, base * CFrame.new(0, 0.12 * s, 0), c(200, 50, 40))
	end)
end

function features.wheels(model, a, def, s)
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.0, 1.0 } do
			part({
				Name = "Wheel",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 1.2, 1.2) * s,
				CFrame = CFrame.new(x * s, 0.6 * s, z * s),
				Color = BLACK,
				Parent = model,
			})
			part({
				Name = "Hubcap",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.42, 0.5, 0.5) * s,
				CFrame = CFrame.new(x * s, 0.6 * s, z * s),
				Color = def.secondary,
				Parent = model,
			})
		end
	end
	box(model, "Seat", Vector3.new(1.4, 0.5, 1.0) * s, Vector3.new(0, 2.65 * s, 0.5 * s), def.secondary)
end

function features.mushroom_cap(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0.15 * s)
		ball(model, "Cap", 1.9 * s, base.Position + Vector3.new(0, 0.1 * s, 0), def.secondary)
		for _, o in { Vector3.new(-0.5, 0.75, -0.2), Vector3.new(0.45, 0.8, 0.25), Vector3.new(0, 0.95, 0.1) } do
			ball(model, "CapDot", 0.35 * s, base.Position + o * s, WHITE)
		end
	end)
end

function features.leaf_hair(model, a, def, s)
	eachHead(a, function(head)
		for _, o in { Vector3.new(-0.4, 0.35, 0), Vector3.new(0.4, 0.35, 0), Vector3.new(0, 0.55, 0.1), Vector3.new(0, 0.3, 0.45) } do
			ball(model, "Leaf", 0.75 * s, headTop(head).Position + o * s, def.secondary)
		end
	end)
end

function features.fire(model, a, def, s)
	local fire = Instance.new("Fire")
	fire.Color = c(255, 140, 30)
	fire.SecondaryColor = c(255, 230, 80)
	fire.Size = 3 * s
	fire.Heat = 6
	fire.Parent = a.body
	for _, side in { -1, 1 } do
		wedge(model, "Flame", Vector3.new(0.15, 0.8, 0.5) * s, CFrame.new(a.back + Vector3.new(side * 0.3 * s, 0.3 * s, 0)), c(255, 160, 40), { Material = Enum.Material.Neon })
	end
end

function features.ghost(model, a, def, s)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Root" and child.Name ~= "Eye" and child.Name ~= "EyeShine" then
			child.Transparency = 0.35
			child.Material = Enum.Material.Glass
		end
	end
end

function features.halo(model, a, def, s)
	local center = Vector3.new(0, a.top * s + 0.7 * s, 0)
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		ball(model, "Halo", 0.25 * s, center + Vector3.new(math.cos(angle) * 0.6 * s, 0, math.sin(angle) * 0.6 * s), GOLD, { Material = Enum.Material.Neon })
	end
end

function features.translucent(model, a, def, s)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Root" and child.Name ~= "Eye" and child.Name ~= "EyeShine" then
			child.Material = Enum.Material.Glass
			child.Transparency = 0.2
		end
	end
end

function features.shiny(model, a, def, s)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Root" then
			child.Reflectance = 0.2
		end
	end
end

function features.cherry(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0)
		upCylinder(model, "Frosting", head.size.X * 0.9, 0.35 * s, base * CFrame.new(0, 0.15 * s, 0), WHITE)
		ball(model, "Cherry", 0.45 * s, (base * CFrame.new(0, 0.55 * s, 0)).Position, c(220, 20, 40))
	end)
end

function features.donut(model, a, def, s)
	eachHead(a, function(head)
		local center = head.cf * CFrame.new(0, -head.size.Y * 0.45, head.size.Z * 0.35)
		for i = 0, 9 do
			local angle = i / 10 * math.pi * 2
			ball(model, "Donut", 0.45 * s, (center * CFrame.new(math.cos(angle) * 0.75 * s, 0, math.sin(angle) * 0.75 * s)).Position, def.secondary)
		end
	end)
end

function features.lollipop(model, a, def, s)
	local base = a.back + Vector3.new(0, 0, 0.3 * s)
	box(model, "Stick", Vector3.new(0.12, 1.6, 0.12) * s, base + Vector3.new(0, 0.8 * s, 0), WHITE)
	part({
		Name = "Candy",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 1.3, 1.3) * s,
		CFrame = CFrame.new(base + Vector3.new(0, 1.85 * s, 0)) * CFrame.Angles(0, rad(90), 0),
		Color = def.secondary,
		Parent = model,
	})
	part({
		Name = "CandySwirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.27, 0.7, 0.7) * s,
		CFrame = CFrame.new(base + Vector3.new(0, 1.85 * s, 0)) * CFrame.Angles(0, rad(90), 0),
		Color = WHITE,
		Parent = model,
	})
end

function features.cloud(model, a, def, s)
	for _, o in { Vector3.new(-1.1, 1.2, 0), Vector3.new(1.1, 1.2, 0), Vector3.new(0, 1.3, 1.0), Vector3.new(0, 2.2, 0.2) } do
		ball(model, "Puff", 1.3 * s, o * s, def.secondary)
	end
end

function features.ice_cream(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0.1 * s)
		ball(model, "Scoop", 0.9 * s, (base * CFrame.new(0, 0.3 * s, 0)).Position, def.secondary)
		ball(model, "Scoop", 0.75 * s, (base * CFrame.new(0, 0.85 * s, 0)).Position, c(140, 80, 50))
		ball(model, "Cherry", 0.3 * s, (base * CFrame.new(0, 1.3 * s, 0)).Position, c(220, 20, 40))
	end)
end

function features.icing(model, a, def, s)
	for _, y in { 2.95, 1.35 } do
		box(model, "Icing", Vector3.new(2.0, 0.12, 1.3) * s, Vector3.new(0, y * s, 0), def.secondary)
	end
	for _, y in { 2.5, 2.05, 1.6 } do
		ball(model, "Button", 0.3 * s, Vector3.new(0, y * s, -0.65 * s), c(230, 40, 60))
	end
end

function features.pumpkin_head(model, a, def, s)
	eachHead(a, function(head)
		for _, child in model:GetChildren() do
			if child.Name == "Head" and child:IsA("BasePart") then
				child.Color = def.secondary
			end
		end
		box(model, "Stem", Vector3.new(0.2, 0.35, 0.2) * s, headTop(head, 0.15 * s), c(70, 130, 40))
		box(model, "Mouth", Vector3.new(0.7, 0.18, 0.05) * s, head.cf * CFrame.new(0, -head.size.Y * 0.25, -head.size.Z / 2 - 0.02 * s), c(255, 230, 60), { Material = Enum.Material.Neon })
	end)
end

function features.skeleton(model, a, def, s)
	if not a.body or a.body.Shape == Enum.PartType.Ball then
		return
	end
	local size = a.body.Size
	for i = -2, 2 do
		box(model, "Rib", Vector3.new(size.X + 0.04 * s, 0.14 * s, 0.14 * s), a.body.CFrame * CFrame.new(0, 0, i * size.Z * 0.18), def.secondary)
	end
end

function features.witch_hat(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0.05 * s)
		upCylinder(model, "HatBrim", 2.0 * s, 0.1 * s, base, def.secondary)
		upCylinder(model, "Hat", 1.0 * s, 0.6 * s, base * CFrame.new(0, 0.35 * s, 0), def.secondary)
		upCylinder(model, "Hat", 0.6 * s, 0.6 * s, base * CFrame.new(0, 0.9 * s, 0.05 * s), def.secondary)
		box(model, "HatTip", Vector3.new(0.3, 0.5, 0.3) * s, base * CFrame.new(0, 1.35 * s, 0.25 * s) * CFrame.Angles(rad(30), 0, 0), def.secondary)
		upCylinder(model, "HatBand", 1.04 * s, 0.14 * s, base * CFrame.new(0, 0.15 * s, 0), c(255, 140, 20))
	end)
end

function features.headless(model, a, def, s)
	-- The body template skips the head; this adds a ghostly flame at the neck.
	local neck = a.back + Vector3.new(0, 0.6 * s, -1.5 * s)
	ball(model, "NeckFlame", 0.9 * s, neck, c(255, 140, 30), { Material = Enum.Material.Neon, Transparency = 0.2 })
end

function features.clown(model, a, def, s)
	eachHead(a, function(head)
		ball(model, "Nose", 0.5 * s, (head.cf * CFrame.new(0, -0.05 * s, -head.size.Z / 2 - 0.15 * s)).Position, c(230, 30, 40))
		local hairColors = { c(230, 30, 40), c(60, 140, 255), c(255, 210, 40) }
		for i, side in { -1, 1 } do
			for j = 0, 1 do
				ball(model, "Hair", 0.75 * s, (head.cf * CFrame.new(side * (head.size.X / 2 + 0.15 * s), 0.25 * s - j * 0.45 * s, 0.1 * s)).Position, hairColors[(i + j) % 3 + 1])
			end
		end
		box(model, "Smile", Vector3.new(0.8, 0.14, 0.05) * s, head.cf * CFrame.new(0, -head.size.Y * 0.3, -head.size.Z / 2 - 0.02 * s), c(230, 30, 40))
		local collar = head.cf * CFrame.new(0, -head.size.Y / 2 - 0.1 * s, 0)
		for i = 0, 9 do
			local angle = i / 10 * math.pi * 2
			ball(model, "Ruffle", 0.5 * s, (collar * CFrame.new(math.cos(angle) * 0.85 * s, 0, math.sin(angle) * 0.7 * s)).Position, hairColors[i % 3 + 1])
		end
	end)
	for _, y in { 2.6, 2.1, 1.6 } do
		ball(model, "Pompom", 0.35 * s, Vector3.new(0, y * s, -0.65 * s), c(60, 140, 255))
	end
end

function features.pharaoh(model, a, def, s)
	eachHead(a, function(head)
		box(model, "Headdress", head.size + Vector3.new(0.2, 0.15, -0.3) * s, head.cf * CFrame.new(0, 0.12 * s, 0.25 * s), GOLD, { Material = Enum.Material.Metal })
		for _, side in { -1, 1 } do
			for i = 0, 2 do
				box(model, "HeaddressStripe", Vector3.new(0.4, 0.22, 0.6) * s, head.cf * CFrame.new(side * (head.size.X / 2 + 0.1 * s), -0.3 * s - i * 0.32 * s, 0.25 * s), if i % 2 == 0 then def.secondary else GOLD)
			end
		end
		box(model, "Cobra", Vector3.new(0.22, 0.4, 0.15) * s, headTop(head, 0.15 * s) * CFrame.new(0, 0, -head.size.Z * 0.45), GOLD, { Material = Enum.Material.Neon })
	end)
end

function features.eyes_many(model, a, def, s)
	eachHead(a, function(head)
		for _, o in { Vector3.new(-0.18, 0.32, 0), Vector3.new(0.18, 0.32, 0), Vector3.new(-0.32, 0.1, 0.05), Vector3.new(0.32, 0.1, 0.05) } do
			ball(model, "ExtraEye", 0.17 * s, (head.cf * CFrame.new(o.X * s, o.Y * s, -head.size.Z / 2 + o.Z * s)).Position, def.secondary, { Material = Enum.Material.Neon })
		end
	end)
end

function features.candy_corn(model, a, def, s)
	eachHead(a, function(head)
		local base = headTop(head, 0)
		upCylinder(model, "CandyCorn", 0.9 * s, 0.3 * s, base * CFrame.new(0, 0.15 * s, 0), c(255, 210, 40))
		upCylinder(model, "CandyCorn", 0.62 * s, 0.3 * s, base * CFrame.new(0, 0.45 * s, 0), c(255, 130, 30))
		upCylinder(model, "CandyCorn", 0.34 * s, 0.3 * s, base * CFrame.new(0, 0.75 * s, 0), WHITE)
	end)
end

function features.eyes_big() end -- handled while drawing eyes
function features.long_neck() end -- handled by the quad template
function features.two_heads() end -- handled by the quad template
function features.three_heads() end -- handled by the serpent template

---------------------------------------------------------------------------
-- Pets: public builder
---------------------------------------------------------------------------

-- def: a Config pet entry. opts: { scale = number, rarityFx = boolean }
function Models.pet(def, opts): Model
	opts = opts or {}
	local s = (def.scale or 1) * (opts.scale or 1)
	local model = newModel(def.name)
	local flags = {}
	for _, feature in def.features do
		flags[feature] = true
	end
	if flags.wool then
		flags.headColor = def.secondary
	end

	local builder = templates[def.template] or templates.quad
	local anchors = builder(model, def, s, flags)
	for _, head in anchors.heads do
		addEyes(model, head, s, { big = flags.eyes_big })
	end

	for _, feature in def.features do
		local fn = features[feature]
		if fn then
			fn(model, anchors, def, s)
		else
			warn(`[Models] Unknown pet feature "{feature}" on {def.name}`)
		end
	end

	local rarity = def.rarityIndex or 1
	if opts.rarityFx ~= false then
		if rarity >= 6 and not flags.glow then
			features.glow(model, anchors, def, s)
		end
		if rarity >= 7 then
			features.sparkle(model, anchors, def, s)
		end
	end

	local height = (anchors.top + 0.5) * s
	setRoot(model, Vector3.new(2.5 * s, height, 3 * s))
	model:SetAttribute("Height", height)
	return model
end

---------------------------------------------------------------------------
-- Eggs and nests
---------------------------------------------------------------------------

-- variant: nil | "clown" | "pumpkin" | "boss"
function Models.egg(biomeKey: string, rarity: number, opts): Model
	opts = opts or {}
	local biome = Config.Biomes[Config.BiomeIndex[biomeKey]]
	local s = (opts.big and 1.6 or 1) * (opts.scale or 1)
	local model = newModel("Egg")
	local shellColor, spotColor = biome.egg, biome.eggSpots
	if opts.variant == "clown" then
		shellColor, spotColor = biome.altEgg, biome.altEggSpots
	elseif opts.variant == "boss" then
		shellColor, spotColor = c(80, 50, 120), GOLD
	end

	local size = Vector3.new(1.6, 2.05, 1.6) * s
	local shell = part({
		Name = "Shell",
		Size = size,
		CFrame = CFrame.new(0, size.Y / 2, 0),
		Color = shellColor,
		Parent = model,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell

	-- Spots sit on the ellipsoid surface.
	local spotCount = if opts.variant == "clown" then 9 else 6
	local clownColors = { c(230, 30, 40), c(60, 140, 255), c(255, 210, 40) }
	for i = 1, spotCount do
		local theta = (i / spotCount) * math.pi * 2 + (i % 2) * 0.6
		local phi = 0.45 + (i % 3) * 0.55
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
		local pos = Vector3.new(dir.X * size.X / 2, size.Y / 2 + dir.Y * size.Y / 2, dir.Z * size.Z / 2) * 0.97
		local color = if opts.variant == "clown" then clownColors[i % 3 + 1] else spotColor
		ball(model, "Spot", 0.38 * s, pos, color)
	end

	if opts.variant == "pumpkin" then
		for i = 0, 5 do
			local angle = i / 6 * math.pi * 2
			box(model, "Ridge", Vector3.new(0.12, size.Y * 0.8, 0.12) * Vector3.new(s, 1, s), CFrame.new(math.cos(angle) * size.X * 0.47, size.Y / 2, math.sin(angle) * size.Z * 0.47), darken(shellColor, 0.2))
		end
		box(model, "Stem", Vector3.new(0.25, 0.45, 0.25) * s, CFrame.new(0, size.Y + 0.15 * s, 0) * CFrame.Angles(0, 0, rad(12)), c(80, 140, 40))
		box(model, "Face", Vector3.new(0.7, 0.18, 0.05) * s, CFrame.new(0, size.Y * 0.4, -size.Z / 2 - 0.02), c(255, 230, 60), { Material = Enum.Material.Neon })
	elseif opts.variant == "boss" then
		features.crown(model, { heads = { { cf = CFrame.new(0, size.Y * 0.8, 0), size = Vector3.new(1.2, 0.6, 1.2) * s } } }, {}, s)
	end

	-- Rarity effects get stronger as rarity rises.
	local rarityColor = Config.Rarities[rarity].color
	if rarity >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rarityColor
		light.Range = 6 + rarity * 1.5
		light.Brightness = 1 + rarity * 0.3
		light.Parent = shell
	end
	if rarity >= 4 then
		upCylinder(model, "Band", size.X * 1.02, 0.18 * s, CFrame.new(0, size.Y * 0.5, 0), rarityColor, { Material = Enum.Material.Neon })
	end
	if rarity >= 5 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = rarityColor
		sparkles.Parent = shell
	end
	if rarity >= 7 then
		shell.Material = Enum.Material.Neon
	end

	setRoot(model, size, CFrame.new(0, size.Y / 2, 0))
	model:SetAttribute("Height", size.Y)
	return model
end

function Models.nest(): Model
	local model = newModel("Nest")
	upCylinder(model, "Hay", 3.6, 0.4, CFrame.new(0, 0.2, 0), c(225, 190, 95), { Material = Enum.Material.Grass })
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		box(model, "Twig", Vector3.new(1.4, 0.45, 0.5), CFrame.new(math.cos(angle) * 1.75, 0.45, math.sin(angle) * 1.75) * CFrame.Angles(0, -angle + rad(90), rad(i % 2 == 0 and 8 or -8)), if i % 2 == 0 then c(140, 95, 50) else c(120, 80, 40), { Material = Enum.Material.Wood })
	end
	setRoot(model, Vector3.new(4, 0.6, 4))
	return model
end

---------------------------------------------------------------------------
-- Bat (the Tool everyone holds)
---------------------------------------------------------------------------

local function weldTo(handle: BasePart, p: BasePart)
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = p
	weld.Parent = p
end

function Models.bat(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bat"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Bonk thieves to make them drop eggs!"

	local wood = c(205, 150, 90)
	local woodDark = c(150, 100, 55)
	-- The bat runs along the Handle's +X axis; Handle is the grip section.
	local handle = part({
		Name = "Handle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.5, 0.3, 0.3),
		Color = c(35, 35, 40),
		Material = Enum.Material.Fabric,
		Anchored = false,
		CanCollide = false,
		Parent = tool,
	})
	local origin = handle.CFrame
	local function section(name, length, diameter, x, color, material, shape)
		local p = part({
			Name = name,
			Shape = shape or Enum.PartType.Cylinder,
			Size = if shape == Enum.PartType.Ball then Vector3.one * diameter else Vector3.new(length, diameter, diameter),
			CFrame = origin * CFrame.new(x, 0, 0),
			Color = color,
			Material = material or Enum.Material.Wood,
			Parent = tool,
		})
		weldTo(handle, p)
		return p
	end
	section("Knob", 0.18, 0.5, -0.83, woodDark)
	for i = 0, 3 do
		section("Wrap", 0.07, 0.34, -0.55 + i * 0.35, c(220, 40, 40), Enum.Material.Fabric)
	end
	section("Taper1", 0.9, 0.36, 1.18, wood)
	section("Taper2", 0.9, 0.46, 2.02, wood)
	section("Barrel", 1.1, 0.58, 2.95, wood)
	section("Ring", 0.1, 0.6, 2.45, c(220, 40, 40), Enum.Material.SmoothPlastic)
	section("Ring", 0.1, 0.6, 2.62, WHITE, Enum.Material.SmoothPlastic)
	section("Cap", 0, 0.58, 3.5, wood, Enum.Material.Wood, Enum.PartType.Ball)
	section("Logo", 0.4, 0.59, 3.05, woodDark)

	tool.Grip = CFrame.Angles(0, rad(90), 0) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
	tool:SetAttribute("BaseGrip", tool.Grip)

	local trail0 = Instance.new("Attachment")
	trail0.Name = "TrailTop"
	trail0.Position = Vector3.new(3.4, 0, 0)
	trail0.Parent = handle
	local trail1 = Instance.new("Attachment")
	trail1.Name = "TrailBottom"
	trail1.Position = Vector3.new(1.4, 0, 0)
	trail1.Parent = handle
	local swoosh = Instance.new("Trail")
	swoosh.Name = "Swoosh"
	swoosh.Attachment0 = trail0
	swoosh.Attachment1 = trail1
	swoosh.Lifetime = 0.18
	swoosh.Color = ColorSequence.new(WHITE)
	swoosh.Transparency = NumberSequence.new(0.3, 1)
	swoosh.LightEmission = 0.6
	swoosh.Enabled = false
	swoosh.Parent = handle
	return tool
end

---------------------------------------------------------------------------
-- Treadmills
---------------------------------------------------------------------------

local TREADMILL_THEMES = {
	Wood = { frame = c(150, 100, 58), accent = c(95, 65, 35), belt = c(45, 40, 38), neon = c(255, 200, 90), material = Enum.Material.Wood },
	Stone = { frame = c(125, 125, 130), accent = c(85, 85, 92), belt = c(40, 40, 45), neon = c(90, 220, 255), material = Enum.Material.Slate },
	Sand = { frame = c(235, 205, 145), accent = c(200, 145, 75), belt = c(70, 55, 40), neon = c(255, 160, 60), material = Enum.Material.Sandstone },
	Toxic = { frame = c(60, 66, 60), accent = c(250, 210, 40), belt = c(30, 32, 30), neon = c(130, 255, 80), material = Enum.Material.DiamondPlate },
	Hay = { frame = c(205, 55, 45), accent = c(255, 210, 60), belt = c(45, 40, 35), neon = c(255, 230, 120), material = Enum.Material.Metal },
	Fairy = { frame = c(135, 95, 205), accent = c(255, 150, 230), belt = c(50, 35, 75), neon = c(150, 255, 240), material = Enum.Material.SmoothPlastic },
	Candy = { frame = c(255, 255, 255), accent = c(255, 90, 160), belt = c(255, 170, 210), neon = c(120, 220, 255), material = Enum.Material.SmoothPlastic },
	Pumpkin = { frame = c(255, 130, 20), accent = c(60, 30, 70), belt = c(35, 25, 40), neon = c(255, 220, 60), material = Enum.Material.SmoothPlastic },
	Neon = { frame = c(25, 25, 32), accent = c(45, 45, 55), belt = c(15, 15, 20), neon = c(60, 230, 255), material = Enum.Material.Metal },
	TopHat = { frame = c(250, 250, 255), accent = c(220, 30, 45), belt = c(30, 30, 35), neon = GOLD, material = Enum.Material.Foil },
}

local PEN_TRIM = {
	Wood = { color = c(120, 80, 45), material = Enum.Material.Wood },
	Stone = { color = c(150, 150, 155), material = Enum.Material.Cobblestone },
	Gold = { color = GOLD, material = Enum.Material.Metal },
	Neon = { color = c(60, 230, 255), material = Enum.Material.Neon },
}
Models.PenTrim = PEN_TRIM

-- Belt runs along local Z. The runner faces the console at -Z.
function Models.treadmill(themeName: string, penStyle: string): Model
	local theme = TREADMILL_THEMES[themeName] or TREADMILL_THEMES.Wood
	local trim = PEN_TRIM[penStyle] or PEN_TRIM.Wood
	local model = newModel("Treadmill")

	box(model, "Plinth", Vector3.new(8, 0.5, 15), Vector3.new(0, 0.25, 0.5), trim.color, { Material = trim.material, CanCollide = true })
	box(model, "Frame", Vector3.new(7, 0.7, 13), Vector3.new(0, 0.85, 0.5), theme.frame, { Material = theme.material, CanCollide = true })
	local belt = box(model, "Belt", Vector3.new(5, 0.3, 12), Vector3.new(0, 1.3, 0.5), theme.belt, { CanCollide = true, CanQuery = true, Material = Enum.Material.Rubber })
	for _, x in { -2.8, 2.8 } do
		box(model, "Rail", Vector3.new(0.7, 0.5, 13), Vector3.new(x, 1.45, 0.5), theme.accent, { CanCollide = true })
		box(model, "RailLight", Vector3.new(0.12, 0.12, 12.6), Vector3.new(x + (x > 0 and -0.36 or 0.36), 1.6, 0.5), theme.neon, { Material = Enum.Material.Neon })
		box(model, "Post", Vector3.new(0.4, 3.8, 0.4), Vector3.new(x, 3.0, -5.4), theme.accent, { CanCollide = true })
		box(model, "Handle", Vector3.new(0.3, 0.3, 3.5), Vector3.new(x, 4.1, -3.9), theme.accent)
	end
	box(model, "Console", Vector3.new(6, 2.2, 0.6), CFrame.new(0, 4.5, -5.5) * CFrame.Angles(rad(-20), 0, 0), theme.frame, { Material = theme.material, CanCollide = true })
	box(model, "Barrier", Vector3.new(5.6, 3.2, 0.4), Vector3.new(0, 2.9, -5.7), theme.accent, { CanCollide = true, Transparency = 0.6 })
	local screen = box(model, "Screen", Vector3.new(4.6, 1.4, 0.1), CFrame.new(0, 4.6, -5.18) * CFrame.Angles(rad(-20), 0, 0), BLACK)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Back
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = screen
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = theme.neon
	label.Text = "+1/step"
	label.Parent = gui

	-- Theme decoration
	if themeName == "Wood" then
		for _, x in { -3.3, 3.3 } do
			ball(model, "Leaves", 1.4, Vector3.new(x, 5.2, -5.4), c(90, 175, 60), { Material = Enum.Material.Grass })
		end
	elseif themeName == "Stone" then
		for i, x in { -3.4, 3.4 } do
			box(model, "Crystal", Vector3.new(0.6, 1.8, 0.6), CFrame.new(x, 2.2, 6.3) * CFrame.Angles(rad(i * 10), rad(45), 0), theme.neon, { Material = Enum.Material.Neon })
		end
	elseif themeName == "Sand" then
		box(model, "Cactus", Vector3.new(0.7, 3, 0.7), Vector3.new(3.8, 2, 6.2), c(80, 160, 70))
		box(model, "CactusArm", Vector3.new(0.5, 1.2, 0.5), Vector3.new(4.4, 2.6, 6.2), c(80, 160, 70))
	elseif themeName == "Toxic" then
		upCylinder(model, "Barrel", 1.6, 2.2, CFrame.new(3.9, 1.6, 6), c(250, 210, 40), { Material = Enum.Material.Metal })
		upCylinder(model, "Goo", 1.4, 0.1, CFrame.new(3.9, 2.75, 6), theme.neon, { Material = Enum.Material.Neon })
		for _, x in { -2.8, 2.8 } do
			upCylinder(model, "Tube", 0.5, 3.6, CFrame.new(x, 3.0, -4.6), theme.neon, { Material = Enum.Material.Neon, Transparency = 0.2 })
		end
	elseif themeName == "Hay" then
		for _, z in { -4.2, 5.4 } do
			for _, x in { -3.9, 3.9 } do
				part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2.2, 2.2), CFrame = CFrame.new(x, 1.1, z), Color = BLACK, Parent = model })
				part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.62, 1.0, 1.0), CFrame = CFrame.new(x, 1.1, z), Color = theme.accent, Parent = model })
			end
		end
		part({ Name = "HayBale", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 2.4, 2.4), CFrame = CFrame.new(0, 1.7, 8.3), Color = c(230, 195, 95), Material = Enum.Material.Grass, Parent = model })
	elseif themeName == "Fairy" then
		for i = 0, 3 do
			ball(model, "Rune", 0.6, Vector3.new(math.cos(i * 1.57) * 4.2, 3 + (i % 2), -2 + math.sin(i * 1.57) * 4.2), theme.neon, { Material = Enum.Material.Neon })
		end
	elseif themeName == "Candy" then
		for _, x in { -2.8, 2.8 } do
			for i = 0, 4 do
				box(model, "CandyStripe", Vector3.new(0.46, 0.3, 0.46), Vector3.new(x, 1.5 + i * 0.75, -5.4), if i % 2 == 0 then theme.accent else WHITE)
			end
			part({ Name = "Lollipop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.8, 1.8), CFrame = CFrame.new(x, 5.6, -5.4) * CFrame.Angles(0, rad(90), 0), Color = theme.accent, Parent = model })
		end
	elseif themeName == "Pumpkin" then
		local pumpkin = ball(model, "Pumpkin", 3, Vector3.new(0, 6.6, -5.6), theme.frame)
		box(model, "PumpkinFace", Vector3.new(1.6, 0.4, 0.1), CFrame.new(0, 6.3, -7.08), theme.neon, { Material = Enum.Material.Neon })
		for _, x in { -0.6, 0.6 } do
			box(model, "PumpkinEye", Vector3.new(0.45, 0.45, 0.1), CFrame.new(x, 7.0, -7.05), theme.neon, { Material = Enum.Material.Neon })
		end
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Color = c(255, 140, 30)
		fire.SecondaryColor = c(255, 220, 60)
		fire.Parent = pumpkin
	elseif themeName == "Neon" then
		for _, x in { -3.55, 3.55 } do
			box(model, "NeonEdge", Vector3.new(0.12, 0.12, 15), Vector3.new(x, 0.55, 0.5), theme.neon, { Material = Enum.Material.Neon })
		end
		box(model, "NeonBar", Vector3.new(6, 0.15, 0.15), Vector3.new(0, 5.65, -5.5), theme.neon, { Material = Enum.Material.Neon })
	elseif themeName == "TopHat" then
		-- Giant top hat arch over the belt, matching corny's avatar.
		for _, x in { -3.9, 3.9 } do
			box(model, "ArchPost", Vector3.new(0.8, 9, 0.8), Vector3.new(x, 4.5, 0.5), GOLD, { Material = Enum.Material.Metal, CanCollide = true })
		end
		box(model, "ArchBeam", Vector3.new(8.6, 0.8, 0.8), Vector3.new(0, 9.2, 0.5), GOLD, { Material = Enum.Material.Metal })
		upCylinder(model, "HatBrim", 7.5, 0.5, CFrame.new(0, 9.85, 0.5), WHITE, { Material = Enum.Material.Foil })
		upCylinder(model, "HatCrown", 5, 5, CFrame.new(0, 12.6, 0.5), WHITE, { Material = Enum.Material.Foil })
		upCylinder(model, "HatBand", 5.1, 1, CFrame.new(0, 10.6, 0.5), theme.accent)
		upCylinder(model, "HatTop", 5.05, 0.15, CFrame.new(0, 15.15, 0.5), c(240, 240, 250), { Material = Enum.Material.Foil })
		local hat = model:FindFirstChild("HatCrown") :: BasePart
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = GOLD
		sparkles.Parent = hat
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 18
		light.Brightness = 2
		light.Parent = hat
		billboard(hat, "👑 CORNY", GOLD, UDim2.fromScale(10, 2.5), Vector3.new(0, 4.5, 0), 300)
	end

	setRoot(model, Vector3.new(8, 1, 15), CFrame.new(0, 0.5, 0.5))
	model:SetAttribute("BeltSize", belt.Size)
	return model
end

---------------------------------------------------------------------------
-- Fuse Machine
---------------------------------------------------------------------------

function Models.fuseMachine(): Model
	local model = newModel("FuseMachine")
	local metal = c(55, 60, 72)
	local metalLight = c(95, 102, 118)
	local cyan = c(70, 220, 255)
	local core = CFrame.new(0, 0, 1.8)

	upCylinder(model, "Base", 13, 1, CFrame.new(0, 0.5, 0.6), metal, { Material = Enum.Material.DiamondPlate, CanCollide = true })
	upCylinder(model, "BaseGlow", 13.2, 0.15, CFrame.new(0, 1.05, 0.6), cyan, { Material = Enum.Material.Neon })
	for i = 0, 15 do
		local angle = i / 16 * math.pi * 2
		box(model, "Hazard", Vector3.new(1.2, 0.5, 0.4), CFrame.new(math.cos(angle) * 6.3, 0.6, 0.6 + math.sin(angle) * 6.3) * CFrame.Angles(0, -angle, 0), if i % 2 == 0 then c(250, 210, 40) else BLACK)
	end

	-- Central chamber
	upCylinder(model, "ChamberBase", 5.6, 1.4, core * CFrame.new(0, 1.7, 0), metalLight, { Material = Enum.Material.Metal, CanCollide = true })
	upCylinder(model, "Chamber", 4.6, 6, core * CFrame.new(0, 5.4, 0), c(160, 230, 255), { Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = true })
	for _, y in { 3.2, 5.4, 7.6 } do
		upCylinder(model, "Ring", 5.2, 0.35, core * CFrame.new(0, y, 0), metal, { Material = Enum.Material.Metal })
		upCylinder(model, "RingGlow", 5.25, 0.1, core * CFrame.new(0, y, 0), cyan, { Material = Enum.Material.Neon })
	end
	local coreBall = ball(model, "Core", 1.4, (core * CFrame.new(0, 5.4, 0)).Position, cyan, { Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Name = "CoreLight"
	light.Color = cyan
	light.Range = 16
	light.Brightness = 2
	light.Parent = coreBall
	upCylinder(model, "Cap", 5.6, 1.2, core * CFrame.new(0, 9, 0), metalLight, { Material = Enum.Material.Metal })
	ball(model, "Dome", 4, (core * CFrame.new(0, 9.6, 0)).Position, metal, { Material = Enum.Material.Metal })
	box(model, "Antenna", Vector3.new(0.2, 2.5, 0.2), core * CFrame.new(0, 12.4, 0), metalLight)
	ball(model, "AntennaTip", 0.6, (core * CFrame.new(0, 13.8, 0)).Position, c(255, 60, 90), { Material = Enum.Material.Neon })

	-- Three input pods in a front arc, piped into the chamber.
	for i, angleDeg in { -42, 0, 42 } do
		local angle = rad(angleDeg)
		local pos = Vector3.new(math.sin(angle) * 4.8, 0, 1.8 - math.cos(angle) * 4.8)
		local podCf = CFrame.new(pos)
		upCylinder(model, "PodBase", 2.4, 1.6, podCf * CFrame.new(0, 1.8, 0), metalLight, { Material = Enum.Material.Metal, CanCollide = true })
		upCylinder(model, "PodRim", 2.5, 0.15, podCf * CFrame.new(0, 2.65, 0), cyan, { Material = Enum.Material.Neon })
		upCylinder(model, "PodGlass", 2.0, 2.6, podCf * CFrame.new(0, 3.95, 0), c(170, 235, 255), { Material = Enum.Material.Glass, Transparency = 0.7 })
		upCylinder(model, "PodCap", 2.3, 0.3, podCf * CFrame.new(0, 5.35, 0), metal, { Material = Enum.Material.Metal })
		local slot = part({ Name = "Pod" .. i, Size = Vector3.one * 0.2, CFrame = podCf * CFrame.new(0, 2.75, 0), Transparency = 1, Parent = model })
		slot:SetAttribute("Slot", i)
		local from = pos + Vector3.new(0, 4.6, 0)
		local to = (core * CFrame.new(0, 6.6, 0)).Position
		local mid = (from + to) / 2
		part({
			Name = "Pipe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((to - from).Magnitude, 0.55, 0.55),
			CFrame = CFrame.lookAt(mid, to) * CFrame.Angles(0, rad(90), 0),
			Color = metalLight,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		part({
			Name = "PipeGlow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((to - from).Magnitude * 0.9, 0.6, 0.6),
			CFrame = CFrame.lookAt(mid, to) * CFrame.Angles(0, rad(90), 0),
			Color = cyan,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			Parent = model,
		})
	end

	-- Output chute on the side.
	box(model, "Chute", Vector3.new(2.4, 0.4, 3.4), CFrame.new(4.6, 2.2, 3.4) * CFrame.Angles(0, 0, rad(-18)), metalLight, { Material = Enum.Material.Metal })
	box(model, "ChuteGlow", Vector3.new(2.5, 0.1, 0.2), CFrame.new(4.6, 2.45, 1.75) * CFrame.Angles(0, 0, rad(-18)), cyan, { Material = Enum.Material.Neon })
	part({ Name = "Output", Size = Vector3.one * 0.2, CFrame = CFrame.new(6.2, 1.6, 3.4), Transparency = 1, Parent = model })

	local display = part({ Name = "Display", Size = Vector3.new(1, 1, 1), CFrame = core * CFrame.new(0, 11, 0), Transparency = 1, Parent = model })
	local gui = Instance.new("BillboardGui")
	gui.Name = "Counter"
	gui.Size = UDim2.fromScale(12, 4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 150
	gui.LightInfluence = 0
	gui.Parent = display
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "Fuse Machine"
	title.TextColor3 = WHITE
	title.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(c(120, 230, 255), c(40, 110, 255))
	gradient.Rotation = 90
	gradient.Parent = title
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = c(10, 30, 70)
	titleStroke.Parent = title
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.fromScale(1, 0.45)
	count.Position = UDim2.fromScale(0, 0.55)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.FredokaOne
	count.TextScaled = true
	count.Text = "0/3"
	count.TextColor3 = WHITE
	count.Parent = gui
	local countStroke = Instance.new("UIStroke")
	countStroke.Thickness = 3
	countStroke.Color = BLACK
	countStroke.Parent = count

	setRoot(model, Vector3.new(13, 1, 13), CFrame.new(0, 0.5, 0.6))
	return model
end

---------------------------------------------------------------------------
-- Stalls, shops and lobby machines
---------------------------------------------------------------------------

local function glowCircle(model, diameter, color)
	upCylinder(model, "Circle", diameter, 0.12, CFrame.new(0, 0.08, 0), color, { Material = Enum.Material.Neon, Transparency = 0.45 })
	upCylinder(model, "CircleRim", diameter + 0.6, 0.1, CFrame.new(0, 0.06, 0), lighten(color, 0.3), { Material = Enum.Material.Neon, Transparency = 0.2 })
end

-- A striped-awning stall (used for SELL, TRAILS SHOP, TREADMILL SHOP).
function Models.stall(title: string, stripe: Color3, textColor: Color3): (Model, BasePart)
	local model = newModel("Stall")
	local wood = c(130, 120, 125)
	glowCircle(model, 16, stripe:Lerp(c(60, 255, 140), 0.5))
	box(model, "Counter", Vector3.new(10, 3, 2.5), Vector3.new(0, 1.5, -1.5), c(110, 100, 110), { Material = Enum.Material.Wood, CanCollide = true })
	box(model, "CounterTop", Vector3.new(10.6, 0.4, 3), Vector3.new(0, 3.2, -1.5), wood, { Material = Enum.Material.Wood })
	for _, x in { -4.8, 4.8 } do
		for _, z in { -2.6, 2.6 } do
			box(model, "Post", Vector3.new(0.6, 8, 0.6), CFrame.new(x, 4, z) * CFrame.Angles(rad(z > 0 and 6 or -6), 0, 0), wood, { Material = Enum.Material.Wood, CanCollide = true })
		end
	end
	for i = 0, 7 do
		local x = -4.9 + i * 1.4 + 0.7
		local color = if i % 2 == 0 then stripe else WHITE
		box(model, "Awning", Vector3.new(1.4, 0.4, 6.6), CFrame.new(x, 8.6, 0) * CFrame.Angles(rad(-12), 0, 0), color)
		box(model, "AwningFlap", Vector3.new(1.4, 1.2, 0.3), CFrame.new(x, 7.9, -3.35), color)
	end
	local sign = part({ Name = "Sign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 10, 0), Transparency = 1, Parent = model })
	billboard(sign, title, textColor, UDim2.fromScale(14, 3.5), Vector3.new(0, 2.2, 0), 260)
	local prompt = part({ Name = "PromptPart", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, 2.5), Transparency = 1, Parent = model })
	setRoot(model, Vector3.new(11, 1, 7))
	return model, prompt
end

function Models.chest(): (Model, BasePart)
	local model = newModel("FreeChest")
	glowCircle(model, 10, c(60, 255, 100))
	local red = c(220, 40, 40)
	box(model, "ChestBase", Vector3.new(4.5, 2.4, 3), Vector3.new(0, 1.4, 0), red, { CanCollide = true })
	box(model, "ChestLid", Vector3.new(4.6, 1.2, 3.1), Vector3.new(0, 3.2, 0), darken(red, 0.1))
	part({ Name = "LidTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.6, 3.1, 3.1), CFrame = CFrame.new(0, 3.75, 0), Color = darken(red, 0.1), Parent = model })
	for _, x in { -2.0, 0, 2.0 } do
		box(model, "Band", Vector3.new(0.35, 3.8, 3.2), Vector3.new(x, 2.3, 0), GOLD, { Material = Enum.Material.Metal })
	end
	box(model, "Lock", Vector3.new(0.9, 1.1, 0.3), Vector3.new(0, 2.6, -1.65), GOLD, { Material = Enum.Material.Metal })
	box(model, "Gem", Vector3.new(0.4, 0.4, 0.1), Vector3.new(0, 2.7, -1.82), c(60, 255, 100), { Material = Enum.Material.Neon })
	local sign = part({ Name = "Sign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 6.5, 0), Transparency = 1, Parent = model })
	billboard(sign, "FREE!", c(80, 255, 80), UDim2.fromScale(8, 2.5), Vector3.new(0, 1, 0), 200)
	local prompt = part({ Name = "PromptPart", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 2, -2), Transparency = 1, Parent = model })
	setRoot(model, Vector3.new(5, 1, 4))
	return model, prompt
end

-- The chained rebirth machine. Parts named "Chain" let the client hide them when affordable.
function Models.rebirthMachine(): (Model, BasePart)
	local model = newModel("RebirthMachine")
	local stone = c(55, 58, 65)
	local green = c(120, 255, 90)
	box(model, "Base", Vector3.new(16, 2, 12), Vector3.new(0, 1, 0), stone, { Material = Enum.Material.Slate, CanCollide = true })
	for i = 0, 3 do
		box(model, "Step", Vector3.new(4, 0.5, 1.2), Vector3.new(0, 0.25 + i * 0.5, -6.6 + i * 0.6), if i % 2 == 0 then c(250, 210, 40) else BLACK, { CanCollide = true })
	end
	box(model, "Body", Vector3.new(9, 7, 7), Vector3.new(0, 5.5, 1), stone, { Material = Enum.Material.Slate, CanCollide = true })
	for _, x in { -6, 6 } do
		upCylinder(model, "TankBase", 3.6, 1.2, CFrame.new(x, 2.6, 1), c(35, 38, 45), { Material = Enum.Material.Metal })
		upCylinder(model, "Tank", 3, 6, CFrame.new(x, 6.2, 1), c(170, 255, 150), { Material = Enum.Material.Glass, Transparency = 0.5 })
		upCylinder(model, "Liquid", 2.6, 5, CFrame.new(x, 5.8, 1), green, { Material = Enum.Material.Neon, Transparency = 0.15 })
		upCylinder(model, "TankCap", 3.6, 1, CFrame.new(x, 9.6, 1), c(35, 38, 45), { Material = Enum.Material.Metal })
	end
	upCylinder(model, "TopTank", 5, 3, CFrame.new(0, 10.5, 1), c(170, 255, 150), { Material = Enum.Material.Glass, Transparency = 0.5 })
	upCylinder(model, "TopLiquid", 4.4, 2.4, CFrame.new(0, 10.4, 1), green, { Material = Enum.Material.Neon, Transparency = 0.15 })
	upCylinder(model, "TopCap", 5.6, 0.8, CFrame.new(0, 12.3, 1), c(35, 38, 45), { Material = Enum.Material.Metal })
	local lock = box(model, "Lock", Vector3.new(3.2, 3.6, 0.6), Vector3.new(0, 5.4, -2.7), c(40, 44, 50), { Material = Enum.Material.Metal })
	box(model, "Keyhole", Vector3.new(0.7, 1.4, 0.1), Vector3.new(0, 5.2, -3.05), green, { Material = Enum.Material.Neon })
	ball(model, "KeyholeTop", 1.0, Vector3.new(0, 6.0, -3.0), green, { Material = Enum.Material.Neon })
	for _, dir in { -1, 1 } do
		for i = -5, 5 do
			local link = box(model, "Chain", Vector3.new(0.9, 0.35, 0.2), CFrame.new(i * 0.85, 5.4 + i * 0.55 * dir, -3.0) * CFrame.Angles(0, 0, rad(dir * 33 + (i % 2) * 90)), c(150, 155, 165), { Material = Enum.Material.Metal })
			link:SetAttribute("Chain", true)
		end
	end
	local light = Instance.new("PointLight")
	light.Color = green
	light.Range = 18
	light.Parent = lock
	local sign = part({ Name = "Sign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 14.5, 1), Transparency = 1, Parent = model })
	billboard(sign, "REBIRTH", green, UDim2.fromScale(12, 3), Vector3.new(0, 1, 0), 260)
	local prompt = part({ Name = "PromptPart", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 3, -5), Transparency = 1, Parent = model })
	setRoot(model, Vector3.new(16, 1, 12))
	return model, prompt
end

-- A leaderboard portal. Returns the model and the list Frame to fill.
function Models.leaderboard(title: string, accent: Color3): (Model, Frame)
	local model = newModel("Leaderboard")
	local frameColor = c(70, 200, 255)
	box(model, "Base", Vector3.new(16, 1, 4), Vector3.new(0, 0.5, 0), c(200, 230, 255), { CanCollide = true })
	for _, x in { -7.4, 7.4 } do
		box(model, "Pillar", Vector3.new(1.2, 20, 1.6), Vector3.new(x, 11, 0), frameColor, { CanCollide = true })
	end
	box(model, "Top", Vector3.new(17, 1.6, 1.8), Vector3.new(0, 21.6, 0), frameColor)
	local screen = box(model, "Screen", Vector3.new(13.6, 18.4, 0.3), Vector3.new(0, 11.4, 0), BLACK)
	local header = box(model, "Header", Vector3.new(15, 2.6, 0.5), CFrame.new(0, 23.4, 0) * CFrame.Angles(rad(-8), 0, 0), frameColor)

	local headerGui = Instance.new("SurfaceGui")
	headerGui.Face = Enum.NormalId.Front
	headerGui.PixelsPerStud = 30
	headerGui.LightInfluence = 0
	headerGui.Parent = header
	local headerText = Instance.new("TextLabel")
	headerText.Size = UDim2.fromScale(1, 1)
	headerText.BackgroundTransparency = 1
	headerText.Font = Enum.Font.FredokaOne
	headerText.TextScaled = true
	headerText.Text = title
	headerText.TextColor3 = accent
	headerText.Parent = headerGui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = c(10, 40, 80)
	stroke.Parent = headerText

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = screen
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, -20, 1, -20)
	list.Position = UDim2.fromOffset(10, 10)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	setRoot(model, Vector3.new(16, 1, 4))
	return model, list
end

---------------------------------------------------------------------------
-- Boss: the Golem King
---------------------------------------------------------------------------

function Models.golemKing(): Model
	local def = {
		name = Config.Boss.name,
		template = "biped",
		primary = c(105, 100, 98),
		secondary = c(255, 120, 40),
		features = { "crown", "crystal", "glow", "spikes" },
		scale = 4,
		rarityIndex = 6,
	}
	local model = Models.pet(def, { rarityFx = false })
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Material == Enum.Material.SmoothPlastic and child.Name ~= "Root" then
			child.Material = Enum.Material.Slate
		end
	end
	return model
end

---------------------------------------------------------------------------
-- Props for biome decoration
---------------------------------------------------------------------------

local props = {}

function props.tree(model, rng)
	local height = rng:NextNumber(10, 16)
	box(model, "Trunk", Vector3.new(2, height, 2), Vector3.new(0, height / 2, 0), c(115, 75, 45), { Material = Enum.Material.Wood, CanCollide = true })
	for i = 0, 2 do
		local size = 9 - i * 2.5
		box(model, "Leaves", Vector3.new(size, 3, size), Vector3.new(0, height + i * 2.6, 0), if i % 2 == 0 then c(80, 170, 55) else c(95, 190, 65), { Material = Enum.Material.Grass })
	end
end

function props.bush(model, rng)
	local w = rng:NextNumber(5, 9)
	box(model, "Bush", Vector3.new(w, 3, w * 0.7), Vector3.new(0, 1.5, 0), c(70, 160, 50), { Material = Enum.Material.Grass })
	box(model, "BushTop", Vector3.new(w * 0.6, 1.6, w * 0.45), Vector3.new(rng:NextNumber(-1, 1), 3.6, 0), c(80, 175, 55), { Material = Enum.Material.Grass })
end

function props.reeds(model, rng)
	for i = 1, 4 do
		local h = rng:NextNumber(2, 4.5)
		box(model, "Reed", Vector3.new(0.3, h, 0.3), CFrame.new(rng:NextNumber(-0.8, 0.8), h / 2, rng:NextNumber(-0.8, 0.8)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), c(60, 150, 50))
	end
	upCylinder(model, "Puddle", 3, 0.1, CFrame.new(0, 0.05, 0), c(80, 180, 230), { Material = Enum.Material.Glass, Transparency = 0.3 })
end

function props.rock(model, rng, color)
	local size = rng:NextNumber(3, 7)
	box(model, "Rock", Vector3.new(size, size * 0.6, size * 0.8), CFrame.new(0, size * 0.25, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2)), color or c(120, 115, 110), { Material = Enum.Material.Slate, CanCollide = true })
end

function props.crystal(model, rng, color)
	color = color or c(120, 220, 255)
	for i = 1, 3 do
		local h = rng:NextNumber(2, 6)
		box(model, "Crystal", Vector3.new(1, h, 1), CFrame.new(rng:NextNumber(-1, 1), h / 2, rng:NextNumber(-1, 1)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), color, { Material = Enum.Material.Neon, Transparency = 0.1 })
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = model:FindFirstChild("Crystal")
end

function props.cactus(model, rng)
	local h = rng:NextNumber(5, 9)
	local green = c(80, 160, 70)
	box(model, "Cactus", Vector3.new(1.4, h, 1.4), Vector3.new(0, h / 2, 0), green, { CanCollide = true })
	box(model, "ArmL", Vector3.new(1, 2.5, 1), Vector3.new(-1.3, h * 0.6, 0), green)
	box(model, "ArmLJoin", Vector3.new(1.2, 0.9, 0.9), Vector3.new(-0.8, h * 0.6 - 0.9, 0), green)
	box(model, "ArmR", Vector3.new(1, 2, 1), Vector3.new(1.3, h * 0.45, 0), green)
	box(model, "ArmRJoin", Vector3.new(1.2, 0.9, 0.9), Vector3.new(0.8, h * 0.45 - 0.7, 0), green)
	ball(model, "Flower", 0.7, Vector3.new(0, h + 0.2, 0), c(255, 110, 160))
end

function props.dune(model, rng)
	local w = rng:NextNumber(12, 22)
	box(model, "Dune", Vector3.new(w, 3, w * 0.6), CFrame.new(0, 0.8, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), c(232, 205, 135), { Material = Enum.Material.Sand })
end

function props.skull(model, rng)
	box(model, "Skull", Vector3.new(2, 1.8, 2.2), Vector3.new(0, 0.9, 0), c(240, 235, 220))
	for _, x in { -0.45, 0.45 } do
		box(model, "Socket", Vector3.new(0.5, 0.5, 0.1), Vector3.new(x, 1.1, -1.11), BLACK)
	end
end

function props.pyramid(model, rng)
	for i = 0, 4 do
		local size = 16 - i * 3.2
		box(model, "Tier", Vector3.new(size, 2.4, size), Vector3.new(0, 1.2 + i * 2.4, 0), if i % 2 == 0 then c(225, 190, 120) else c(215, 180, 110), { Material = Enum.Material.Sandstone, CanCollide = true })
	end
end

function props.barrel(model, rng)
	upCylinder(model, "Barrel", 2.4, 3.2, CFrame.new(0, 1.6, 0), c(250, 210, 40), { Material = Enum.Material.Metal, CanCollide = true })
	upCylinder(model, "Stripe", 2.45, 0.4, CFrame.new(0, 1.6, 0), BLACK)
	upCylinder(model, "Goo", 2.1, 0.12, CFrame.new(0, 3.25, 0), c(130, 255, 80), { Material = Enum.Material.Neon })
end

function props.sludge(model, rng)
	local d = rng:NextNumber(8, 14)
	upCylinder(model, "Sludge", d, 0.2, CFrame.new(0, 0.1, 0), c(110, 240, 60), { Material = Enum.Material.Neon, Transparency = 0.25 })
	for i = 1, 3 do
		ball(model, "Bubble", rng:NextNumber(0.6, 1.2), Vector3.new(rng:NextNumber(-d / 3, d / 3), 0.3, rng:NextNumber(-d / 3, d / 3)), c(160, 255, 110), { Material = Enum.Material.Neon })
	end
end

function props.deadtree(model, rng, color)
	color = color or c(80, 65, 55)
	local h = rng:NextNumber(8, 13)
	box(model, "Trunk", Vector3.new(1.4, h, 1.4), CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.08, 0.08)), color, { Material = Enum.Material.Wood, CanCollide = true })
	for i = 1, 3 do
		local y = h * (0.5 + i * 0.13)
		local side = if i % 2 == 0 then 1 else -1
		box(model, "Branch", Vector3.new(4, 0.6, 0.6), CFrame.new(side * 1.6, y, 0) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), side * 0.5), color, { Material = Enum.Material.Wood })
	end
end

function props.pipe(model, rng)
	part({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 2.4, 2.4), CFrame = CFrame.new(0, 1.2, 0), Color = c(110, 115, 110), Material = Enum.Material.CorrodedMetal, Parent = model })
	upCylinder(model, "Leak", 4, 0.15, CFrame.new(7.5, 0.08, 0), c(130, 255, 80), { Material = Enum.Material.Neon, Transparency = 0.3 })
end

function props.haybale(model, rng)
	part({ Name = "HayBale", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 4, 4), CFrame = CFrame.new(0, 2, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = c(230, 195, 95), Material = Enum.Material.Grass, CanCollide = true, Parent = model })
end

function props.fence(model, rng)
	local wood = c(150, 100, 60)
	for _, x in { -5, 0, 5 } do
		box(model, "Post", Vector3.new(0.6, 3.2, 0.6), Vector3.new(x, 1.6, 0), wood, { Material = Enum.Material.Wood })
	end
	for _, y in { 1.2, 2.4 } do
		box(model, "Rail", Vector3.new(10.6, 0.4, 0.3), Vector3.new(0, y, 0), wood, { Material = Enum.Material.Wood })
	end
end

function props.barn(model, rng)
	local red = c(200, 50, 45)
	box(model, "Walls", Vector3.new(18, 12, 14), Vector3.new(0, 6, 0), red, { Material = Enum.Material.WoodPlanks, CanCollide = true })
	for _, side in { -1, 1 } do
		box(model, "Roof", Vector3.new(10.5, 0.8, 15), CFrame.new(side * 4.6, 14.5, 0) * CFrame.Angles(0, 0, side * -0.62), c(90, 85, 85), { CanCollide = true })
	end
	wedge(model, "Gable", Vector3.new(0.5, 4.6, 9), CFrame.new(0, 14.3, -6.9) * CFrame.Angles(0, rad(90), 0), red)
	box(model, "Door", Vector3.new(7, 8, 0.3), Vector3.new(0, 4, -7.1), WHITE)
	box(model, "DoorX1", Vector3.new(0.5, 10.5, 0.2), CFrame.new(0, 4, -7.3) * CFrame.Angles(0, 0, 0.72), red)
	box(model, "DoorX2", Vector3.new(0.5, 10.5, 0.2), CFrame.new(0, 4, -7.3) * CFrame.Angles(0, 0, -0.72), red)
end

function props.crops(model, rng)
	for row = -2, 2 do
		box(model, "Soil", Vector3.new(14, 0.4, 1.4), Vector3.new(0, 0.2, row * 2.2), c(120, 80, 50))
		for i = -3, 3 do
			box(model, "Crop", Vector3.new(0.8, 1.6, 0.8), Vector3.new(i * 2, 1.1, row * 2.2), if row % 2 == 0 then c(250, 210, 60) else c(90, 180, 60), { Material = Enum.Material.Grass })
		end
	end
end

function props.mushroom(model, rng, color)
	local h = rng:NextNumber(5, 10)
	color = color or c(220, 60, 200)
	upCylinder(model, "Stem", 1.6, h, CFrame.new(0, h / 2, 0), c(240, 230, 220), { CanCollide = true })
	ball(model, "Cap", h * 0.9, Vector3.new(0, h, 0), color)
	for i = 1, 4 do
		local angle = i * 1.57 + 0.4
		ball(model, "Dot", 0.9, Vector3.new(math.cos(angle) * h * 0.3, h + h * 0.33, math.sin(angle) * h * 0.3), WHITE, { Material = Enum.Material.Neon })
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Parent = model:FindFirstChild("Cap")
end

function props.fairytree(model, rng)
	local h = rng:NextNumber(10, 15)
	box(model, "Trunk", Vector3.new(1.8, h, 1.8), Vector3.new(0, h / 2, 0), c(90, 70, 110), { Material = Enum.Material.Wood, CanCollide = true })
	for i = 0, 2 do
		ball(model, "Canopy", 7 - i * 1.5, Vector3.new(rng:NextNumber(-1.5, 1.5), h + i * 2.2, rng:NextNumber(-1.5, 1.5)), if i % 2 == 0 then c(200, 120, 255) else c(255, 150, 230), { Material = Enum.Material.Grass })
	end
	for i = 1, 3 do
		ball(model, "Firefly", 0.4, Vector3.new(rng:NextNumber(-4, 4), h + rng:NextNumber(-3, 3), rng:NextNumber(-4, 4)), c(255, 255, 150), { Material = Enum.Material.Neon })
	end
end

function props.candycane(model, rng)
	local h = rng:NextNumber(8, 12)
	for i = 0, math.floor(h) - 1 do
		box(model, "Cane", Vector3.new(1.2, 1, 1.2), Vector3.new(0, i + 0.5, 0), if i % 2 == 0 then c(230, 30, 40) else WHITE, { CanCollide = true })
	end
	for i = 0, 3 do
		box(model, "Hook", Vector3.new(1.2, 1.2, 1.2), CFrame.new(math.sin(i * 0.9) * 1.6, h + math.cos(i * 0.9) * 1.2 - 0.6, 0), if i % 2 == 0 then WHITE else c(230, 30, 40))
	end
end

function props.lollipop(model, rng)
	local h = rng:NextNumber(7, 11)
	box(model, "Stick", Vector3.new(0.6, h, 0.6), Vector3.new(0, h / 2, 0), WHITE, { CanCollide = true })
	local color = ({ c(255, 90, 160), c(120, 220, 255), c(255, 210, 60), c(150, 255, 120) })[rng:NextInteger(1, 4)]
	part({ Name = "Candy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 6, 6), CFrame = CFrame.new(0, h + 2.5, 0) * CFrame.Angles(0, rad(90), 0), Color = color, Parent = model })
	part({ Name = "Swirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.05, 3.4, 3.4), CFrame = CFrame.new(0, h + 2.5, 0) * CFrame.Angles(0, rad(90), 0), Color = WHITE, Parent = model })
end

function props.gumdrop(model, rng)
	local color = ({ c(255, 80, 80), c(80, 200, 90), c(255, 200, 40), c(170, 90, 255) })[rng:NextInteger(1, 4)]
	ball(model, "Gumdrop", rng:NextNumber(3, 5), Vector3.new(0, 1.2, 0), color, { Material = Enum.Material.Glass, Transparency = 0.15 })
end

function props.pumpkin(model, rng)
	local d = rng:NextNumber(2.5, 4.5)
	local p = ball(model, "Pumpkin", d, Vector3.new(0, d * 0.42, 0), c(255, 130, 20))
	box(model, "Stem", Vector3.new(0.4, 0.8, 0.4), Vector3.new(0, d * 0.9, 0), c(80, 130, 40))
	box(model, "Face", Vector3.new(d * 0.4, d * 0.12, 0.1), Vector3.new(0, d * 0.32, -d * 0.48), c(255, 230, 60), { Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = c(255, 150, 40)
	light.Range = 12
	light.Parent = p
end

function props.grave(model, rng)
	local stone = c(130, 130, 140)
	box(model, "Stone", Vector3.new(3, 4, 0.8), CFrame.new(0, 2, 0) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), stone, { Material = Enum.Material.Slate, CanCollide = true })
	part({ Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3, 3), CFrame = CFrame.new(0, 4, 0) * CFrame.Angles(0, rad(90), 0), Color = stone, Material = Enum.Material.Slate, Parent = model })
	box(model, "Dirt", Vector3.new(3.4, 0.4, 5), Vector3.new(0, 0.2, -2.6), c(70, 50, 40))
end

function props.clowntent(model, rng)
	local colors = { c(230, 30, 40), WHITE }
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		box(model, "TentWall", Vector3.new(5.4, 12, 0.6), CFrame.new(math.cos(angle) * 10, 6, math.sin(angle) * 10) * CFrame.Angles(0, -angle + rad(90), 0), colors[i % 2 + 1], { CanCollide = true })
		wedge(model, "TentRoof", Vector3.new(0.6, 8, 10.4), CFrame.new(math.cos(angle) * 5, 16, math.sin(angle) * 5) * CFrame.Angles(0, -angle - rad(90), 0), colors[(i + 1) % 2 + 1])
	end
	box(model, "Flag", Vector3.new(0.3, 5, 0.3), Vector3.new(0, 22, 0), c(80, 80, 85))
	box(model, "FlagCloth", Vector3.new(0.1, 1.6, 2.4), Vector3.new(0, 23.6, 1.2), c(255, 210, 40))
end

-- kind: a key of props. color: optional tint for props that take one.
function Models.prop(kind: string, rng: Random, color: Color3?): Model
	local model = newModel(kind)
	local builder = props[kind]
	if builder then
		builder(model, rng, color)
	else
		warn(`[Models] Unknown prop "{kind}"`)
	end
	return model
end

---------------------------------------------------------------------------
-- Physics rig: turns an anchored model into one welded assembly on Root.
---------------------------------------------------------------------------

function Models.rigForPhysics(model: Model): BasePart
	local root = model.PrimaryPart :: BasePart
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") and child ~= root then
			child.Anchored = false
			child.Massless = true
			child.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = child
			weld.Parent = child
		end
	end
	root.Anchored = false
	root.CanCollide = false
	return root
end

return Models

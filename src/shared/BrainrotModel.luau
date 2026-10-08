--!strict
-- Builds brainrot characters. Each brainrot has its own hand-made design out
-- of parts. To use a real 3D model instead, put a Model named after the
-- brainrot's Id (e.g. "BananitoBandito") in ReplicatedStorage > BrainrotModels.
-- It's scaled and positioned automatically. Shared so clients can build the
-- mini followers too.
--
-- Mutations recolor every part except ones marked with the "Keep" attribute
-- (eyes, glowing bits), and add effects.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BrainrotModel = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(15, 15, 20)
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad

-- Builder ------------------------------------------------------------------

type Builder = {
	add: (name: string, kind: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, keep: boolean?) -> BasePart,
}

-- Positions are in studs from the feet (y = up, -z = front), at scale 1.
local function newBuilder(model: Model, root: BasePart, scale: number): Builder
	local feet = root.CFrame * CF(0, -0.5, 0)
	local b = {} :: Builder

	function b.add(name, kind, size, offset, color, material, keep)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if kind == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif kind == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif kind == "Wedge" then
			p.Shape = Enum.PartType.Wedge
		elseif kind == "Egg" then
			-- Stretchy sphere: a block with a sphere mesh fills any size.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Size = size * scale
		p.CFrame = feet * CF(offset.Position * scale) * offset.Rotation
		if keep then
			p:SetAttribute("Keep", true)
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end

	return b
end

local function ball(b: Builder, name: string, d: number, pos: Vector3, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return b.add(name, "Ball", V(d, d, d), CF(pos), color, material, keep)
end

local function egg(b: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return b.add(name, "Egg", size, offset, color, material, keep)
end

local function box(b: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return b.add(name, "Block", size, offset, color, material, keep)
end

-- Cylinder along the X axis (left-right).
local function cyl(b: Builder, name: string, length: number, d: number, offset: CFrame, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return b.add(name, "Cylinder", V(length, d, d), offset, color, material, keep)
end

-- Upright cylinder.
local function vcyl(b: Builder, name: string, height: number, d: number, pos: Vector3, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return b.add(name, "Cylinder", V(height, d, d), CF(pos) * ANG(0, 0, rad(90)), color, material, keep)
end

-- Cylinder pointing forward (along Z), like a disc facing the camera.
local function zcyl(b: Builder, name: string, length: number, d: number, pos: Vector3, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return b.add(name, "Cylinder", V(length, d, d), CF(pos) * ANG(0, rad(90), 0), color, material, keep)
end

-- Rounded tube from `a` to `b` (a cylinder with ball ends): smooth limbs.
local function capsule(b: Builder, name: string, from: Vector3, to: Vector3, d: number, color: Color3, material: Enum.Material?, keep: boolean?)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local up = if math.abs((to - from).Unit.Y) > 0.99 then V(0, 0, 1) else V(0, 1, 0)
	-- Cylinders run along X; turn the look direction into the X axis.
	local frame = CFrame.lookAt(mid, to, up) * ANG(0, rad(90), 0)
	b.add(name, "Cylinder", V(length, d, d), frame, color, material, keep)
	ball(b, name .. "End", d, from, color, material, keep)
	ball(b, name .. "End", d, to, color, material, keep)
end

-- Cartoon eyes: white, pupil, a little shine dot, and optional angry brows.
local function eyes(b: Builder, cx: number, y: number, z: number, spacing: number, size: number, angry: boolean?)
	for _, side in { -1, 1 } do
		local x = cx + side * spacing
		ball(b, "Eye", size, V(x, y, z), WHITE, nil, true)
		ball(b, "Pupil", size * 0.52, V(x, y - size * 0.04, z - size * 0.3), BLACK, nil, true)
		ball(b, "Shine", size * 0.16, V(x - size * 0.1, y + size * 0.1, z - size * 0.52), WHITE, Enum.Material.Neon, true)
		if angry then
			egg(b, "Brow", V(size * 1.2, size * 0.22, size * 0.3), CF(x, y + size * 0.62, z - size * 0.25) * ANG(0, 0, side * rad(-22)), BLACK, nil, true)
		end
	end
end

-- A small curved smile made of overlapping dots.
local function smile(b: Builder, cx: number, y: number, z: number, width: number, color: Color3?)
	for i = -2, 2 do
		local t = i / 2
		ball(b, "Smile", width * 0.22, V(cx + t * width / 2, y - (1 - t * t) * width * 0.18, z), color or BLACK, nil, true)
	end
end

local function legs(b: Builder, color: Color3, height: number, spacing: number)
	for _, side in { -1, 1 } do
		capsule(b, "Leg", V(side * spacing, height, 0), V(side * spacing, 0.35, 0), 0.45, color)
		egg(b, "Foot", V(0.7, 0.45, 1.05), CF(side * spacing, 0.22, -0.18), color)
	end
end

local function arms(b: Builder, y: number, x: number, color: Color3, length: number)
	for _, side in { -1, 1 } do
		local shoulder = V(side * x, y, 0)
		local hand = V(side * (x + length * 0.8), y - length * 0.45, -0.1)
		capsule(b, "Arm", shoulder, hand, 0.36, color)
		ball(b, "Hand", 0.52, hand, color)
	end
end

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

-- Designs ------------------------------------------------------------------
-- Each returns the height of its top, for placing the name tag.

type Design = (b: Builder, c: Color3, a: Color3) -> number

local designs: { [string]: Design } = {}

designs.NoodloDoodlo = function(b, c, a)
	legs(b, darker(a, 0.3), 0.8, 0.6)
	vcyl(b, "Bowl", 1.4, 2.8, V(0, 1.5, 0), WHITE)
	vcyl(b, "BowlStripe", 0.3, 2.85, V(0, 1.95, 0), a)
	egg(b, "Noodles", V(2.6, 1.4, 2.6), CF(0, 2.4, 0), c)
	for i = 1, 6 do
		local angle = rad(i * 60)
		cyl(b, "Noodle", 1.2, 0.18, CF(0, 2.3, 0) * ANG(0, angle, 0) * CF(1.25, -0.15, 0) * ANG(0, 0, rad(-60)), c)
	end
	eyes(b, 0, 2.75, -1.1, 0.5, 0.6)
	local chopstick = Color3.fromRGB(150, 100, 60)
	box(b, "Chopstick", V(0.12, 2.4, 0.12), CF(0.45, 3.3, 0.4) * ANG(rad(15), 0, rad(-20)), chopstick)
	box(b, "Chopstick", V(0.12, 2.4, 0.12), CF(0.75, 3.3, 0.3) * ANG(rad(10), 0, rad(-25)), chopstick)
	return 4.5
end

designs.PizzarinoPizzaroni = function(b, c, a)
	local crust = Color3.fromRGB(200, 130, 65)
	legs(b, crust, 1.0, 0.3)
	-- Upside-down triangle slice: two mirrored wedges meeting in the middle.
	local top, bottom, width, thick = 4.0, 0.9, 3.2, 0.45
	local h = top - bottom
	for _, side in { -1, 1 } do
		-- The wedge's right angle goes at the top-center so the halves meet.
		local frame = CFrame.fromMatrix(V(side * width / 4, bottom + h / 2, 0), V(0, 0, -side), V(0, -1, 0), V(-side, 0, 0))
		b.add("Slice", "Wedge", V(thick, h, width / 2), frame, c)
	end
	capsule(b, "Crust", V(-1.75, 4.1, 0), V(1.75, 4.1, 0), 0.7, crust)
	-- Melty cheese drips
	for _, drip in { { -0.7, 3.2 }, { 0.5, 2.3 }, { -0.15, 1.5 } } do
		egg(b, "Drip", V(0.35, 0.7, 0.3), CF(drip[1], drip[2], -0.15), c:Lerp(WHITE, 0.15))
	end
	for _, pos in { V(-0.85, 3.6, -0.24), V(0.65, 3.0, -0.24), V(0.05, 2.0, -0.24), V(0.95, 3.75, -0.24) } do
		zcyl(b, "Pepperoni", 0.08, 0.62, pos, a)
	end
	eyes(b, 0, 3.2, -0.32, 0.5, 0.55)
	smile(b, 0, 2.65, -0.3, 0.5)
	arms(b, 3.3, 1.2, crust, 1.0)
	return 4.6
end

designs.SockGobblino = function(b, c, a)
	vcyl(b, "Tube", 2.5, 1.6, V(0, 2.55, 0), c)
	vcyl(b, "Cuff", 0.45, 1.75, V(0, 3.75, 0), a)
	egg(b, "CuffTop", V(1.75, 0.3, 1.75), CF(0, 3.98, 0), a)
	for _, y in { 2.7, 3.15 } do
		vcyl(b, "Stripe", 0.2, 1.64, V(0, y, 0), a)
	end
	egg(b, "Heel", V(1.65, 1.5, 1.6), CF(0, 0.95, 0.15), c)
	egg(b, "Foot", V(1.6, 1.25, 2.9), CF(0, 0.65, -0.65), c)
	egg(b, "Toe", V(1.5, 1.1, 0.9), CF(0, 0.65, -1.85), a)
	egg(b, "Mouth", V(1.1, 0.3, 0.2), CF(0, 0.62, -2.25), BLACK, nil, true)
	for _, x in { -0.32, 0, 0.32 } do
		egg(b, "Tooth", V(0.2, 0.24, 0.12), CF(x, 0.78, -2.3), WHITE, nil, true)
	end
	eyes(b, 0, 2.5, -0.78, 0.4, 0.62)
	return 4.1
end

designs.FrigoBurrito = function(b, c, a)
	legs(b, darker(c, 0.5), 0.8, 0.55)
	vcyl(b, "Burrito", 2.6, 2.2, V(0, 2.3, 0), c)
	egg(b, "BurritoEnd", V(2.2, 0.8, 2.2), CF(0, 1.0, 0), c)
	box(b, "Fold", V(2.25, 0.3, 2.25), CF(0, 1.7, 0) * ANG(0, 0, rad(18)), darker(c, 0.15))
	egg(b, "Filling", V(2.0, 0.9, 2.0), CF(0, 3.6, 0), Color3.fromRGB(245, 240, 225))
	ball(b, "Bean", 0.35, V(-0.4, 3.95, -0.3), Color3.fromRGB(110, 50, 30))
	ball(b, "Tomato", 0.35, V(0.4, 3.9, 0.2), Color3.fromRGB(220, 50, 40))
	egg(b, "Frost", V(1.6, 0.5, 1.6), CF(0, 4.05, 0), a, Enum.Material.Ice)
	vcyl(b, "Scarf", 0.35, 2.3, V(0, 2.95, 0), a)
	eyes(b, 0, 2.45, -1.05, 0.48, 0.6)
	arms(b, 2.5, 1.0, c, 0.9)
	return 4.3
end

designs.BananitoBandito = function(b, c, a)
	local brown = Color3.fromRGB(110, 70, 30)
	legs(b, brown, 0.8, 0.45)
	local function curveX(t: number): number
		return 0.6 * math.sin(t * math.pi)
	end
	for i = 0, 10 do
		local t = i / 10
		local d = 1.0 + 0.5 * math.sin(t * math.pi)
		egg(b, "Banana", V(d, 0.8, d), CF(curveX(t), 1.1 + t * 2.9, 0), c)
	end
	ball(b, "Tip", 0.4, V(0, 0.85, 0), brown)
	local maskX = curveX(0.7)
	egg(b, "Mask", V(1.55, 0.4, 1.55), CF(maskX, 3.1, 0), a, nil, true)
	eyes(b, maskX, 3.1, -0.72, 0.36, 0.42)
	vcyl(b, "Brim", 0.15, 2.3, V(0, 4.25, 0), brown)
	vcyl(b, "HatTop", 0.7, 1.1, V(0, 4.6, 0), brown)
	arms(b, 2.5, 0.9, c, 0.9)
	return 5.0
end

designs.CroissantoFurioso = function(b, c, a)
	legs(b, darker(c, 0.3), 1.3, 0.6)
	for i = -2, 2 do
		local angle = i * 0.5
		local d = 1.9 - math.abs(i) * 0.35
		local x = math.sin(angle) * 1.6
		local y = 2.75 - (1 - math.cos(angle)) * 1.4
		egg(b, "Croissant", V(d * 0.8, d, d), CF(x, y, 0) * ANG(0, 0, -angle), if i % 2 == 0 then c else darker(c, 0.12))
	end
	eyes(b, 0, 3.0, -0.85, 0.42, 0.55, true)
	for _, side in { -1, 1 } do
		zcyl(b, "Blush", 0.05, 0.45, V(side * 0.75, 2.5, -0.9), a, nil, true)
	end
	box(b, "Mouth", V(0.6, 0.12, 0.1), CF(0, 2.4, -0.93), BLACK, nil, true)
	return 3.8
end

designs.TostinoTurbino = function(b, c, a)
	local crust = darker(c, 0.35)
	local bread = Color3.fromRGB(235, 200, 140)
	legs(b, crust, 0.8, 0.6)
	box(b, "Crust", V(2.6, 2.4, 0.8), CF(0, 2.0, 0), crust)
	box(b, "Bread", V(2.2, 2.2, 0.85), CF(0, 2.0, 0), bread)
	zcyl(b, "CrustTop", 0.8, 2.6, V(0, 3.3, 0), crust)
	zcyl(b, "BreadTop", 0.85, 2.2, V(0, 3.3, 0), bread)
	for _, side in { -1, 1 } do
		zcyl(b, "Jet", 1.4, 0.8, V(side * 1.6, 2.2, 0.2), a, Enum.Material.Metal)
		ball(b, "Flame", 0.65, V(side * 1.6, 2.2, 1.0), Color3.fromRGB(255, 140, 30), Enum.Material.Neon, true)
	end
	for _, side in { -1, 1 } do
		zcyl(b, "Goggle", 0.2, 0.75, V(side * 0.5, 2.85, -0.45), a, Enum.Material.Metal)
	end
	box(b, "Strap", V(2.65, 0.2, 0.9), CF(0, 2.85, 0), BLACK)
	eyes(b, 0, 2.85, -0.5, 0.5, 0.5)
	return 4.4
end

designs.CactussoBossino = function(b, c, a)
	local clay = Color3.fromRGB(200, 100, 60)
	vcyl(b, "Pot", 1.2, 2.2, V(0, 0.6, 0), clay)
	vcyl(b, "Rim", 0.3, 2.5, V(0, 1.25, 0), darker(clay, 0.15))
	vcyl(b, "Body", 2.8, 1.6, V(0, 2.6, 0), c)
	ball(b, "Top", 1.6, V(0, 4.0, 0), c)
	for _, side in { -1, 1 } do
		cyl(b, "ArmOut", 0.8, 0.6, CF(side * 1.1, 2.5 + (side + 1) * 0.2, 0), c)
		vcyl(b, "ArmUp", 1.0, 0.6, V(side * 1.5, 3.0 + (side + 1) * 0.2, 0), c)
		ball(b, "ArmTip", 0.6, V(side * 1.5, 3.5 + (side + 1) * 0.2, 0), c)
	end
	for i = 1, 5 do
		local angle = rad(i * 72)
		ball(b, "Petal", 0.45, V(math.cos(angle) * 0.35, 4.85, math.sin(angle) * 0.35), a)
	end
	ball(b, "FlowerCenter", 0.35, V(0, 4.95, 0), Color3.fromRGB(255, 220, 60))
	for _, side in { -1, 1 } do
		box(b, "Shades", V(0.6, 0.35, 0.15), CF(side * 0.33, 3.45, -0.78), BLACK, nil, true)
	end
	box(b, "Bridge", V(0.3, 0.08, 0.1), CF(0, 3.5, -0.8), BLACK, nil, true)
	box(b, "Smirk", V(0.5, 0.1, 0.1), CF(0.1, 2.95, -0.8) * ANG(0, 0, rad(10)), BLACK, nil, true)
	return 5.1
end

designs.WaffelinoWizardo = function(b, c, a)
	legs(b, darker(a, 0.4), 0.8, 0.5)
	vcyl(b, "Robe", 1.6, 2.4, V(0, 1.6, 0), a)
	box(b, "Waffle", V(2.4, 2.4, 0.7), CF(0, 3.4, 0), c)
	local grid = darker(c, 0.25)
	for _, x in { -0.4, 0.4 } do
		box(b, "Grid", V(0.15, 2.4, 0.05), CF(x, 3.4, -0.37), grid)
	end
	for _, y in { 3.0, 3.8 } do
		box(b, "Grid", V(2.4, 0.15, 0.05), CF(0, y, -0.37), grid)
	end
	eyes(b, 0, 3.75, -0.42, 0.55, 0.5)
	egg(b, "Beard", V(1.4, 1.1, 0.4), CF(0, 2.75, -0.4), WHITE)
	vcyl(b, "HatBrim", 0.25, 2.1, V(0, 4.7, 0), a)
	vcyl(b, "Hat1", 0.5, 1.4, V(0, 5.05, 0), a)
	vcyl(b, "Hat2", 0.5, 1.0, V(0, 5.5, 0), a)
	vcyl(b, "Hat3", 0.5, 0.6, V(0, 5.95, 0), a)
	ball(b, "HatStar", 0.45, V(0, 6.3, 0), Color3.fromRGB(255, 230, 80), Enum.Material.Neon, true)
	arms(b, 2.7, 1.0, a, 0.8)
	vcyl(b, "Staff", 3.6, 0.2, V(1.6, 1.9, -0.2), Color3.fromRGB(120, 80, 40))
	local orb = ball(b, "Orb", 0.65, V(1.6, 3.85, -0.2), Color3.fromRGB(80, 220, 255), Enum.Material.Neon, true)
	local glow = Instance.new("PointLight")
	glow.Color = orb.Color
	glow.Range = 8
	glow.Parent = orb
	return 6.4
end

designs.GnocchiNinjaro = function(b, c, a)
	legs(b, a, 0.7, 0.5)
	egg(b, "Body", V(2.6, 2.4, 2.2), CF(0, 1.9, 0), c)
	for _, y in { 1.2, 1.9 } do
		local k = math.sqrt(1 - ((y - 1.9) / 1.2) ^ 2)
		egg(b, "Ridge", V(2.65 * k, 0.15, 2.25 * k), CF(0, y, 0), darker(c, 0.12))
	end
	local bandK = math.sqrt(1 - (0.75 / 1.2) ^ 2)
	egg(b, "Headband", V(2.7 * bandK, 0.35, 2.3 * bandK), CF(0, 2.65, 0), a)
	for _, side in { -1, 1 } do
		box(b, "BandTail", V(0.2, 0.9, 0.15), CF(side * 0.25, 2.3, 1.0) * ANG(rad(30), 0, side * rad(25)), a)
	end
	eyes(b, 0, 2.2, -1.0, 0.45, 0.5, true)
	box(b, "Blade", V(0.15, 2.6, 0.3), CF(0.3, 2.3, 1.15) * ANG(0, 0, rad(35)), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
	box(b, "Hilt", V(0.25, 0.7, 0.35), CF(-0.6, 1.0, 1.15) * ANG(0, 0, rad(35)), BLACK)
	return 3.4
end

designs.PinguinoHackerino = function(b, c, a)
	local orange = Color3.fromRGB(255, 150, 40)
	for _, side in { -1, 1 } do
		box(b, "Foot", V(0.7, 0.25, 1.0), CF(side * 0.5, 0.12, -0.3), orange)
	end
	egg(b, "Body", V(2.4, 3.2, 2.2), CF(0, 1.8, 0), c)
	egg(b, "Belly", V(1.8, 2.4, 0.6), CF(0, 1.7, -0.85), WHITE)
	egg(b, "Head", V(1.8, 1.6, 1.7), CF(0, 3.75, 0), c)
	egg(b, "FaceWhite", V(1.3, 1.0, 0.3), CF(0, 3.7, -0.75), WHITE)
	box(b, "Beak", V(0.5, 0.25, 0.5), CF(0, 3.45, -0.95), orange)
	eyes(b, 0, 3.95, -0.78, 0.33, 0.4)
	box(b, "Visor", V(1.4, 0.3, 0.08), CF(0, 3.95, -0.95), a, Enum.Material.Neon, true).Transparency = 0.45
	for _, side in { -1, 1 } do
		egg(b, "Flipper", V(0.35, 1.6, 0.9), CF(side * 1.2, 2.1, -0.3) * ANG(rad(-30), 0, side * rad(20)), c)
	end
	-- Laptop tucked under one flipper, screen glowing.
	box(b, "Laptop", V(1.1, 0.1, 0.8), CF(1.15, 1.35, -1.0) * ANG(0, rad(-25), 0), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	box(b, "Screen", V(1.1, 0.75, 0.08), CF(1.3, 1.75, -1.3) * ANG(rad(-15), rad(-25), 0), a, Enum.Material.Neon, true)
	return 4.6
end

designs.LasagnaLightningo = function(b, c, a)
	legs(b, darker(c, 0.4), 0.8, 0.7)
	local pasta = Color3.fromRGB(255, 225, 160)
	local cheese = Color3.fromRGB(255, 215, 90)
	local layers = { pasta, c, cheese, pasta, c, cheese }
	for i, color in layers do
		box(b, "Layer", V(2.8, 0.42, 1.8), CF(0, 0.8 + (i - 0.5) * 0.4, 0), color)
	end
	egg(b, "Melt", V(2.9, 0.45, 1.9), CF(0, 3.25, 0), cheese)
	for _, side in { -1, 1 } do
		local x = side * 0.8
		box(b, "Bolt", V(0.25, 0.8, 0.2), CF(x, 3.85, 0) * ANG(0, 0, rad(-25)), a, Enum.Material.Neon, true)
		box(b, "Bolt", V(0.6, 0.2, 0.2), CF(x + 0.1, 4.2, 0), a, Enum.Material.Neon, true)
		box(b, "Bolt", V(0.25, 0.8, 0.2), CF(x + 0.3, 4.55, 0) * ANG(0, 0, rad(-25)), a, Enum.Material.Neon, true)
	end
	eyes(b, 0, 2.4, -0.95, 0.6, 0.6)
	box(b, "Grin", V(0.9, 0.15, 0.1), CF(0, 1.75, -0.92), BLACK, nil, true)
	arms(b, 2.2, 1.4, pasta, 0.9)
	return 5.0
end

designs.DragoniSpaghettoni = function(b, c, a)
	legs(b, c, 1.0, 0.7)
	egg(b, "Body", V(2.6, 2.4, 3.0), CF(0, 2.0, 0.2), c)
	egg(b, "Belly", V(1.8, 1.8, 0.6), CF(0, 1.9, -1.0), a)
	egg(b, "Head", V(1.8, 1.6, 1.8), CF(0, 3.4, -1.4), c)
	egg(b, "Snout", V(1.05, 0.75, 1.1), CF(0, 3.2, -2.25), c)
	for _, side in { -1, 1 } do
		ball(b, "Nostril", 0.14, V(side * 0.22, 3.35, -2.78), darker(c, 0.5), nil, true)
	end
	for _, side in { -1, 1 } do
		box(b, "Horn", V(0.25, 0.8, 0.25), CF(side * 0.5, 4.3, -1.2) * ANG(rad(-20), 0, side * rad(-20)), a)
		box(b, "Wing", V(2.2, 0.12, 1.4), CF(side * 2.0, 3.1, 0.4) * ANG(0, 0, side * rad(30)), darker(c, 0.3))
	end
	eyes(b, 0, 3.65, -2.25, 0.4, 0.42, true)
	for i = 0, 6 do
		local t = i / 6
		ball(b, "Tail", 0.45, V(math.sin(t * math.pi * 1.5) * 0.6, 1.6 + t * 0.6, 1.6 + t * 1.6), a)
	end
	for i = 1, 5 do
		local x = -0.6 + i * 0.2
		cyl(b, "Noodle", 1.0, 0.14, CF(x, 4.1, -1.3) * ANG(0, rad(90), rad(-60 + i * 20)), a)
	end
	return 4.6
end

designs.MeatballoSupremo = function(b, c, a)
	legs(b, darker(c, 0.3), 0.8, 0.7)
	ball(b, "Meatball", 3.2, V(0, 2.4, 0), c)
	for i = 1, 8 do
		local angle = rad(i * 45)
		ball(b, "Bump", 0.6, V(math.cos(angle) * 1.45, 2.4 + math.sin(angle * 2) * 0.6, math.sin(angle) * 1.45), darker(c, 0.15))
	end
	egg(b, "Sauce", V(2.6, 0.8, 2.6), CF(0, 3.8, 0), Color3.fromRGB(200, 30, 30))
	for _, pos in { V(-0.4, 4.15, 0.2), V(0.5, 4.1, -0.3) } do
		box(b, "Basil", V(0.5, 0.08, 0.3), CF(pos) * ANG(0, rad(30), 0), Color3.fromRGB(60, 160, 60))
	end
	local gold = Color3.fromRGB(255, 200, 50)
	vcyl(b, "Crown", 0.5, 1.4, V(0, 4.4, 0), gold, Enum.Material.Foil, true)
	for i = 1, 5 do
		local angle = rad(i * 72)
		box(b, "CrownSpike", V(0.25, 0.5, 0.25), CF(math.cos(angle) * 0.55, 4.85, math.sin(angle) * 0.55), gold, Enum.Material.Foil, true)
	end
	egg(b, "Mustache", V(1.5, 0.35, 0.4), CF(0, 2.2, -1.55), a)
	eyes(b, 0, 2.9, -1.42, 0.55, 0.6)
	box(b, "Cape", V(2.6, 2.6, 0.15), CF(0, 2.2, 1.6), Color3.fromRGB(130, 20, 50), nil, true)
	return 5.1
end

designs.IlCosmicoCannolo = function(b, c, a)
	local shell = Color3.fromRGB(215, 150, 70)
	cyl(b, "Shell", 3.4, 1.5, CF(0, 2.6, 0), shell)
	for _, side in { -1, 1 } do
		ball(b, "Cream", 1.4, V(side * 1.75, 2.6, 0), WHITE)
		for i = 1, 4 do
			local angle = rad(i * 90 + 45)
			ball(b, "Chip", 0.2, V(side * 2.3, 2.6 + math.sin(angle) * 0.4, math.cos(angle) * 0.4), Color3.fromRGB(60, 30, 20))
		end
	end
	eyes(b, 0, 2.8, -0.72, 0.5, 0.5)
	for i = 1, 12 do
		local angle = rad(i * 30)
		local p = CF(0, 2.6, 0) * ANG(rad(20), 0, rad(15)) * CF(math.cos(angle) * 2.6, 0, math.sin(angle) * 2.6)
		ball(b, "Orbit", 0.25, p.Position, a, Enum.Material.Neon, true)
	end
	egg(b, "Aura", V(4.2, 2.4, 2.4), CF(0, 2.6, 0), c, Enum.Material.ForceField, true)
	return 4.0
end

designs.CignaGlamourina = function(b, c, a)
	local cream = Color3.fromRGB(252, 245, 232)
	local hotPink = a
	local dressPink = c
	local frill = Color3.fromRGB(255, 232, 243)
	local blonde = Color3.fromRGB(250, 226, 135)
	local blondeLight = Color3.fromRGB(255, 240, 175)
	local beak = Color3.fromRGB(242, 172, 118)
	local GLOSS = Enum.Material.SmoothPlastic

	-- Giant platform heels with bows -------------------------------------
	for _, side in { -1, 1 } do
		local x = side * 0.32
		egg(b, "Platform", V(0.66, 0.42, 1.0), CF(x, 0.2, -0.1), hotPink)
		capsule(b, "Heel", V(x, 0.15, 0.32), V(x, 0.75, 0.3), 0.36, hotPink)
		egg(b, "Shoe", V(0.62, 0.48, 0.82), CF(x, 0.58, -0.12), hotPink)
		for _, bowSide in { -1, 1 } do
			egg(b, "ShoeBow", V(0.3, 0.2, 0.12), CF(x + bowSide * 0.16, 0.74, -0.5) * ANG(0, 0, bowSide * rad(-20)), hotPink)
		end
		ball(b, "ShoeBowKnot", 0.13, V(x, 0.74, -0.53), hotPink)
		-- Long thin legs
		capsule(b, "Leg", V(x, 0.75, 0), V(side * 0.22, 2.55, 0.02), 0.22, cream)
	end

	-- Dress: flared skirt, ruffled hem and a train ------------------------
	for i = 0, 4 do
		local t = i / 4
		local width = 2.2 - t * 0.7
		egg(b, "Skirt", V(width, 0.5, width * 0.9), CF(0, 2.55 + t * 0.6, 0.05), if i % 2 == 0 then frill else frill:Lerp(dressPink, 0.15))
	end
	for i = 1, 14 do
		local angle = rad(i * (360 / 14))
		ball(b, "Ruffle", 0.42, V(math.cos(angle) * 1.0, 2.42, 0.05 + math.sin(angle) * 0.9), frill)
	end
	for i = 0, 4 do
		local t = i / 4
		egg(b, "Train", V(1.4 - t * 0.5, 0.35, 0.8), CF(0, 2.45 - t * 0.35, 0.6 + t * 0.55), frill)
	end
	-- Fitted top, narrower than the tutu, flaring a little at the chest
	egg(b, "Bodice", V(1.15, 1.45, 0.95), CF(0, 3.5, 0), dressPink)
	egg(b, "Chest", V(1.25, 0.6, 1.0), CF(0, 3.85, -0.02), dressPink)
	egg(b, "Waist", V(1.2, 0.3, 1.0), CF(0, 2.95, 0), dressPink)

	-- Swan wings: three layers of fanned feathers --------------------------
	for _, side in { -1, 1 } do
		for layer = 0, 2 do
			for f = 0, 4 do
				local spread = rad(-10 + f * 9 + layer * 4)
				local length = 1.9 - layer * 0.35 - f * 0.12
				local color = if layer == 0 then Color3.fromRGB(255, 222, 230) elseif layer == 1 then Color3.fromRGB(255, 236, 240) else WHITE
				egg(b, "Feather", V(0.16, length, 0.42),
					CF(side * (0.8 + layer * 0.06), 3.55 - layer * 0.25, 0.25 + layer * 0.12)
						* ANG(spread, 0, side * rad(-12 - layer * 4))
						* CF(0, -length / 2, 0.2 + f * 0.05),
					color)
			end
		end
	end

	-- Long, gently curved neck with a pink bow ------------------------------
	local neck = { V(0, 4.0, 0), V(0, 4.45, -0.06), V(0, 4.9, -0.1), V(0, 5.35, -0.08), V(0, 5.65, -0.04) }
	for i = 1, #neck - 1 do
		capsule(b, "Neck", neck[i], neck[i + 1], 0.48, cream)
	end
	for _, side in { -1, 1 } do
		egg(b, "NeckBow", V(0.48, 0.34, 0.18), CF(side * 0.26, 4.42, -0.33) * ANG(0, 0, side * rad(-15)), hotPink)
		egg(b, "BowTail", V(0.14, 0.42, 0.08), CF(side * 0.12, 4.15, -0.32) * ANG(0, 0, side * rad(18)), hotPink)
	end
	ball(b, "NeckBowKnot", 0.18, V(0, 4.42, -0.35), hotPink)

	-- Head ------------------------------------------------------------------
	egg(b, "Head", V(1.0, 0.98, 1.08), CF(0, 5.88, -0.05), cream)
	for _, side in { -1, 1 } do
		egg(b, "Blush", V(0.05, 0.16, 0.26), CF(side * 0.5, 5.68, -0.32), Color3.fromRGB(255, 150, 190), nil, true)
	end

	-- Big lashed eyes on the sides, with heart-pink irises -------------------
	for _, side in { -1, 1 } do
		local eye = V(side * 0.43, 5.98, -0.2)
		local look = V(side * 0.55, 0, -0.84)
		egg(b, "Eye", V(0.62, 0.68, 0.62), CF(eye), WHITE, nil, true)
		ball(b, "Iris", 0.4, eye + look * 0.16, Color3.fromRGB(235, 70, 160), nil, true)
		ball(b, "IrisRing", 0.3, eye + look * 0.21, Color3.fromRGB(180, 30, 110), nil, true)
		ball(b, "Pupil", 0.18, eye + look * 0.27, BLACK, nil, true)
		ball(b, "Shine", 0.09, eye + look * 0.31 + V(0, 0.08, 0), WHITE, Enum.Material.Neon, true)
		ball(b, "Shine2", 0.05, eye + look * 0.3 + V(0, -0.06, 0), WHITE, Enum.Material.Neon, true)
		-- Upper lid and curled lashes
		egg(b, "Lid", V(0.66, 0.24, 0.66), CF(eye + V(0, 0.26, 0)), cream)
		for i = -1, 1 do
			local base = eye + V(side * 0.14, 0.34, -0.06 + i * 0.13)
			capsule(b, "Lash", base, base + V(side * 0.16, 0.16, i * 0.05 - 0.03), 0.05, BLACK, nil, true)
		end
	end

	-- Tapered beak with big glossy pink lips ---------------------------------
	for i = 0, 3 do
		local t = i / 3
		egg(b, "Beak", V(0.46 - t * 0.2, 0.4 - t * 0.16, 0.42), CF(0, 5.74 - t * 0.04, -0.55 - t * 0.28), beak)
	end
	local lips = egg(b, "LipTop", V(0.34, 0.16, 0.32), CF(0, 5.74, -1.48), hotPink, GLOSS, true)
	lips.Reflectance = 0.2
	local lower = egg(b, "LipBottom", V(0.3, 0.14, 0.28), CF(0, 5.6, -1.44), hotPink, GLOSS, true)
	lower.Reflectance = 0.2

	-- Big blonde hair: a smooth mass at the back plus spiral ringlet curls --
	egg(b, "HairBack", V(1.25, 1.35, 0.95), CF(0, 5.75, 0.38), blonde, GLOSS)
	egg(b, "HairTop", V(1.3, 0.75, 1.25), CF(0, 6.3, 0.12), blonde, GLOSS)
	for _, side in { -1, 1 } do
		egg(b, "HairSide", V(0.55, 1.0, 0.9), CF(side * 0.55, 5.85, 0.25), blonde, GLOSS)
	end
	local ringlets = {
		{ x = -0.55, z = 0.3, top = 5.55, turns = 7 },
		{ x = 0.55, z = 0.3, top = 5.55, turns = 7 },
		{ x = -0.3, z = 0.6, top = 5.4, turns = 8 },
		{ x = 0.3, z = 0.6, top = 5.4, turns = 8 },
		{ x = 0, z = 0.72, top = 5.3, turns = 9 },
	}
	for r, curl in ringlets do
		for i = 0, curl.turns - 1 do
			local angle = i * 1.4 + r
			local size = 0.48 - i * 0.025
			local y = curl.top - i * 0.21
			local pos = V(curl.x + math.cos(angle) * 0.12, y, curl.z + math.sin(angle) * 0.1)
			egg(b, "Curl", V(size, size * 0.85, size), CF(pos) * ANG(0, angle, rad(20)), if i % 2 == 0 then blonde else blondeLight, GLOSS)
		end
	end

	-- Pink party-hat crown: smooth cone, scalloped frill, cloud prints -------
	local hatBase = CF(0, 6.42, 0.05) * ANG(rad(-12), 0, 0)
	for i = 0, 13 do
		local t = i / 13
		local d = 1.12 - t * 0.98
		b.add("Hat", "Cylinder", V(0.15, d, d), hatBase * CF(0, 0.08 + t * 1.5, 0) * ANG(0, 0, rad(90)), dressPink)
	end
	b.add("HatTip", "Ball", V(0.2, 0.2, 0.2), hatBase * CF(0, 1.66, 0), dressPink)
	for i = 1, 14 do
		local angle = rad(i * (360 / 14))
		b.add("HatFrill", "Ball", V(0.22, 0.22, 0.22), hatBase * CF(math.cos(angle) * 0.58, 0, math.sin(angle) * 0.58), frill)
	end
	for _, spot in { { 0.25, 0.45 }, { -0.18, 0.85 } } do
		b.add("HatCloud", "Egg", V(0.04, 0.2, 0.3), hatBase * CF(-0.48 + spot[2] * 0.25, spot[2], -0.12 + spot[1]) * ANG(0, rad(90), 0), hotPink:Lerp(WHITE, 0.3))
	end
	return 8.2
end

-- Fallback for brainrots without a design yet.
local function blob(b: Builder, c: Color3, a: Color3): number
	legs(b, a, 1.0, 0.7)
	ball(b, "Body", 3, V(0, 2.5, 0), c)
	eyes(b, 0, 2.85, -1.25, 0.45, 0.9)
	box(b, "Hat", V(1.6, 0.8, 1.6), CF(0, 4.1, 0) * ANG(0, rad(15), rad(-10)), a)
	return 4.5
end

-- Custom 3D models -----------------------------------------------------------

local function useCustomModel(model: Model, root: BasePart, brainrot: Config.Brainrot, scale: number): number?
	-- ReplicatedStorage so followers (built on clients) can use it too;
	-- ServerStorage still works for the server-side models.
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not folder and RunService:IsServer() then
		folder = game:GetService("ServerStorage"):FindFirstChild("BrainrotModels")
	end
	local template = folder and folder:FindFirstChild(brainrot.Id)
	if not template or not template:IsA("Model") then
		return nil
	end

	local clone = template:Clone()
	-- Toolbox models sometimes hide scripts inside; never run them.
	for _, d in clone:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end

	local targetHeight = 4.5 * scale
	local _, size = clone:GetBoundingBox()
	if size.Y > 0 then
		clone:ScaleTo(clone:GetScale() * targetHeight / size.Y)
	end

	local feet = root.CFrame * CF(0, -0.5, 0)
	clone:PivotTo(feet)
	local boxCFrame, boxSize = clone:GetBoundingBox()
	local bottom = boxCFrame.Position - V(0, boxSize.Y / 2, 0)
	clone:PivotTo(clone:GetPivot() + (feet.Position - bottom))

	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
	for _, child in clone:GetChildren() do
		child.Parent = model
	end
	clone:Destroy()
	return targetHeight / scale
end

-- Mutations ----------------------------------------------------------------

local function applyMutation(model: Model, root: BasePart, mutation: Config.Mutation, scale: number)
	local i = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and not d:GetAttribute("Keep") then
			i += 1
			if mutation.Id == "Gold" then
				d.Color = Color3.fromRGB(255, 196, 50)
				d.Material = Enum.Material.Foil
			elseif mutation.Id == "Diamond" then
				d.Color = Color3.fromRGB(150, 230, 255)
				d.Material = Enum.Material.Glass
				d.Transparency = 0.15
				d.Reflectance = 0.25
			elseif mutation.Id == "Sparkle" then
				-- Keeps its own colors, just brighter and glossy.
				d.Color = d.Color:Lerp(Color3.new(1, 1, 1), 0.3)
				d.Reflectance = 0.25
			elseif mutation.Id == "Lava" then
				d.Color = Color3.fromRGB(80, 35, 25)
				d.Material = Enum.Material.CrackedLava
			elseif mutation.Id == "Rainbow" then
				d.Color = Color3.fromHSV((i * 0.09) % 1, 0.75, 1)
			end
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		end
	end

	if mutation.Id == "Lava" then
		local fire = Instance.new("Fire")
		fire.Size = 4 * scale
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 110, 20)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 60)
		fire.Parent = root
	end
	if mutation.Id == "Rainbow" then
		CollectionService:AddTag(model, "RainbowBrainrot")
	end
	if mutation.Id == "Sparkle" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 245, 160)
		sparkles.Parent = root
		local stars = Instance.new("ParticleEmitter")
		stars.Name = "SparkleStars"
		stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		stars.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 230, 120))
		stars.LightEmission = 1
		stars.Rate = 25
		stars.Lifetime = NumberRange.new(0.5, 1)
		stars.Speed = NumberRange.new(0.5, 2)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0) })
		stars.Parent = root
	end

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "MutationSparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(mutation.Color)
	sparkles.Rate = 8
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.35)
	sparkles.Parent = root

	local light = Instance.new("PointLight")
	light.Color = mutation.Color
	light.Range = 8 * scale
	light.Brightness = 1.5
	light.Parent = root
end

-- Name tag -----------------------------------------------------------------

-- Name tags are sized in studs (not pixels), so they shrink with distance
-- like real signs instead of covering the screen when you zoom out.
local TAG_STUDS_PER_ROW_UNIT = 0.03 -- a 26-unit name row is ~0.8 studs tall
local TAG_WIDTH = 6

-- Re-fits the tag to its visible rows (rows store their height as "Units").
local function relayout(tag: BillboardGui)
	local total = 0
	for _, row in tag:GetChildren() do
		if row:IsA("TextLabel") then
			total += row:GetAttribute("Units") :: number
		end
	end
	local scale = tag:GetAttribute("Scale") :: number? or 1
	tag.Size = UDim2.fromScale(TAG_WIDTH * scale, math.max(total, 1) * TAG_STUDS_PER_ROW_UNIT * scale)
	for _, row in tag:GetChildren() do
		if row:IsA("TextLabel") then
			row.Size = UDim2.fromScale(1, (row:GetAttribute("Units") :: number) / math.max(total, 1))
		end
	end
end

local function label(parent: Instance, name: string, text: string, color: Color3, size: number, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l:SetAttribute("Units", size)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

-- Public -------------------------------------------------------------------

-- Updates the "$X/s" line, e.g. when the owner's rebirths change it.
function BrainrotModel.SetIncomeText(model: Model, income: number)
	local root = model.PrimaryPart
	local tag = root and root:FindFirstChild("Tag")
	local incomeLabel = tag and tag:FindFirstChild("Income")
	if incomeLabel and incomeLabel:IsA("TextLabel") then
		incomeLabel.Text = Config.FormatCash(income) .. "/s"
	end
end

-- Creates the model at `cframe` (feet on the ground). `priceTag` shows the buy price.
-- `mini` builds a small follower version: no name tag or lights.
function BrainrotModel.Create(brainrot: Config.Brainrot, mutationId: string?, cframe: CFrame, priceTag: boolean, serial: number?, mini: boolean?): Model
	local rarity = Config.Rarities[brainrot.Rarity]
	local mutation = Config.GetMutation(mutationId)
	local s = if mini then 0.4 else rarity.Scale

	local model = Instance.new("Model")
	model.Name = brainrot.Id
	model:SetAttribute("BrainrotId", brainrot.Id)
	model:SetAttribute("Mutation", if mutation then mutation.Id else nil)
	-- Limited (Robux) brainrots can't be stolen or sold.
	model:SetAttribute("Protected", brainrot.Limited == true)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = V(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CFrame = cframe * CF(0, 0.5, 0)
	root.Parent = model
	model.PrimaryPart = root

	local height = useCustomModel(model, root, brainrot, s)
	if not height then
		local design: Design = designs[brainrot.Id] or blob
		height = design(newBuilder(model, root, s), brainrot.Color, brainrot.Accent)
	end
	local topY = (height :: number) * s

	if mini then
		if mutation then
			applyMutation(model, root, mutation, s)
			-- Followers stay light: drop the extra glow.
			for _, light in root:GetChildren() do
				if light:IsA("PointLight") or light:IsA("Fire") then
					light:Destroy()
				end
			end
		end
		return model
	end

	-- Rarity effects
	if rarity.Order >= 4 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 10 * s
		-- Event Specials keep their sparkle but glow softer.
		light.Brightness = if brainrot.Rarity == "EventSpecial" then 0.6 else 2
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
	if mutation then
		applyMutation(model, root, mutation, s)
	end

	-- Name tag (world-sized; a bit bigger for bigger brainrots)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag:SetAttribute("Scale", math.sqrt(s))
	tag.StudsOffsetWorldSpace = V(0, topY + 1.2, 0)
	tag.MaxDistance = 150
	tag.LightInfluence = 0
	tag.Adornee = root
	tag.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = tag

	if mutation then
		label(tag, "Mutation", string.upper(mutation.DisplayName), mutation.Color, 22, 0)
	end
	local rarityColor = if brainrot.Rarity == "Secret" then Color3.fromRGB(255, 120, 255) else rarity.Color
	label(tag, "Rarity", string.upper(rarity.DisplayName), rarityColor, 18, 1)
	label(tag, "Name", brainrot.DisplayName, WHITE, 26, 2)
	label(tag, "Income", Config.FormatCash(Config.IncomeOf(brainrot, mutationId)) .. "/s", Color3.fromRGB(120, 255, 120), 20, 3)
	if priceTag then
		label(tag, "Price", Config.FormatCash(Config.PriceOf(brainrot, mutationId)), Color3.fromRGB(255, 220, 80), 22, 4)
	end
	local limited = Config.LimitedItems[brainrot.Id]
	if serial and limited then
		label(tag, "Serial", string.format("#%d of %d", serial, limited.Stock + limited.Reserved), Color3.fromRGB(255, 215, 90), 22, 5)
	end
	relayout(tag)

	return model
end

-- Removes the price row once a brainrot is bought.
function BrainrotModel.RemovePrice(model: Model)
	local root = model.PrimaryPart
	local tag = root and root:FindFirstChild("Tag")
	local price = tag and tag:FindFirstChild("Price")
	if tag and price and tag:IsA("BillboardGui") then
		price:Destroy()
		relayout(tag)
	end
end

return BrainrotModel

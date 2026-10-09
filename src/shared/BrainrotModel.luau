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
	mirror: boolean?, -- flip left/right (designs are drawn as seen from behind)
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
		if b.mirror then
			-- Reflect across the YZ plane: negate X and the matching rotation terms.
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = offset:GetComponents()
			offset = CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
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

-- Boxes are rounded so nothing looks blocky: chunky ones become a rounded
-- box (three crossing slabs, edge tubes and corner balls), thinner ones
-- (layers, signs, screens, wings) a plate with rounded corners. Tiny ones
-- stay plain blocks.
local function box(b: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	local x, y, z = size.X, size.Y, size.Z
	local thin = math.min(x, y, z)
	local big = math.max(x, y, z)
	local mid = x + y + z - thin - big
	local function piece(pieceName: string, kind: string, pieceSize: Vector3, at: CFrame): BasePart
		return b.add(pieceName, kind, pieceSize, offset * at, color, material, keep)
	end
	if thin >= 0.5 then
		local r = math.min(thin * 0.3, 0.35)
		local d = r * 2
		local core = piece(name, "Block", V(x, y - d, z - d), CF())
		piece(name, "Block", V(x - d, y, z - d), CF())
		piece(name, "Block", V(x - d, y - d, z), CF())
		local hx, hy, hz = x / 2 - r, y / 2 - r, z / 2 - r
		for _, s1 in { -1, 1 } do
			for _, s2 in { -1, 1 } do
				piece(name .. "Edge", "Cylinder", V(x - d, d, d), CF(0, s1 * hy, s2 * hz))
				piece(name .. "Edge", "Cylinder", V(y - d, d, d), CF(s1 * hx, 0, s2 * hz) * ANG(0, 0, rad(90)))
				piece(name .. "Edge", "Cylinder", V(z - d, d, d), CF(s1 * hx, s2 * hy, 0) * ANG(0, rad(90), 0))
				for _, s3 in { -1, 1 } do
					piece(name .. "Corner", "Ball", V(d, d, d), CF(s1 * hx, s2 * hy, s3 * hz))
				end
			end
		end
		return core
	elseif mid >= 0.5 then
		-- A plate: round the corners in its two long directions.
		local r = math.min(mid * 0.22, 0.3)
		local d = r * 2
		local axis = if thin == x then "X" elseif thin == y then "Y" else "Z"
		local core: BasePart
		if axis == "X" then
			core = piece(name, "Block", V(x, y - d, z), CF())
			piece(name, "Block", V(x, y, z - d), CF())
		elseif axis == "Y" then
			core = piece(name, "Block", V(x - d, y, z), CF())
			piece(name, "Block", V(x, y, z - d), CF())
		else
			core = piece(name, "Block", V(x - d, y, z), CF())
			piece(name, "Block", V(x, y - d, z), CF())
		end
		for _, s1 in { -1, 1 } do
			for _, s2 in { -1, 1 } do
				if axis == "X" then
					piece(name .. "Corner", "Cylinder", V(x, d, d), CF(0, s1 * (y / 2 - r), s2 * (z / 2 - r)))
				elseif axis == "Y" then
					piece(name .. "Corner", "Cylinder", V(y, d, d), CF(s1 * (x / 2 - r), 0, s2 * (z / 2 - r)) * ANG(0, 0, rad(90)))
				else
					piece(name .. "Corner", "Cylinder", V(z, d, d), CF(s1 * (x / 2 - r), s2 * (y / 2 - r), 0) * ANG(0, rad(90), 0))
				end
			end
		end
		return core
	end
	return b.add(name, "Block", size, offset, color, material, keep)
end

-- Cylinder along the X axis (left-right). Chunky ones get softly domed
-- ends instead of a sharp rim.
local function cyl(b: Builder, name: string, length: number, d: number, offset: CFrame, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	if d >= 0.7 and length >= d * 0.3 then
		local bevel = math.min(d * 0.12, length * 0.25)
		local core = b.add(name, "Cylinder", V(length - bevel * 2, d, d), offset, color, material, keep)
		for _, side in { -1, 1 } do
			b.add(name .. "Rim", "Egg", V(bevel * 2, d, d), offset * CF(side * (length / 2 - bevel), 0, 0), color, material, keep)
		end
		return core
	end
	return b.add(name, "Cylinder", V(length, d, d), offset, color, material, keep)
end

-- Upright cylinder.
local function vcyl(b: Builder, name: string, height: number, d: number, pos: Vector3, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return cyl(b, name, height, d, CF(pos) * ANG(0, 0, rad(90)), color, material, keep)
end

-- Cylinder pointing forward (along Z), like a disc facing the camera.
local function zcyl(b: Builder, name: string, length: number, d: number, pos: Vector3, color: Color3, material: Enum.Material?, keep: boolean?): BasePart
	return cyl(b, name, length, d, CF(pos) * ANG(0, rad(90), 0), color, material, keep)
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

-- A smooth upright cone (hats, ice-cream cones, horns), stacked from thin
-- discs. `base` is the center of its bottom. `stripe` alternates a second
-- color every few discs (waffle cone lines).
local function cone(b: Builder, name: string, base: Vector3, height: number, bottomD: number, topD: number, color: Color3, material: Enum.Material?, keep: boolean?, stripe: Color3?)
	local slices = math.max(3, math.ceil(height / 0.14))
	local step = height / slices
	for i = 0, slices - 1 do
		local t = (i + 0.5) / slices
		local d = bottomD + (topD - bottomD) * t
		local shade = if stripe and (i // 2) % 2 == 1 then stripe else color
		b.add(name, "Cylinder", V(step * 1.02, d, d), CF(base + V(0, (i + 0.5) * step, 0)) * ANG(0, 0, rad(90)), shade, material, keep)
	end
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

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(WHITE, amount)
end

-- An open cartoon mouth (dark oval with a pink tongue) facing front.
local function mouth(b: Builder, cx: number, y: number, z: number, width: number, height: number)
	egg(b, "Mouth", V(width, height, 0.2), CF(cx, y, z), Color3.fromRGB(70, 20, 25), nil, true)
	egg(b, "Tongue", V(width * 0.55, height * 0.4, 0.12), CF(cx, y - height * 0.22, z - 0.06), Color3.fromRGB(255, 120, 140), nil, true)
end

-- Rosy cheeks on both sides of a face.
local function blush(b: Builder, cx: number, y: number, z: number, spacing: number, size: number?)
	local d = size or 0.38
	for _, side in { -1, 1 } do
		egg(b, "Blush", V(d, d * 0.6, 0.08), CF(cx + side * spacing, y, z), Color3.fromRGB(255, 140, 150), nil, true)
	end
end

-- Thin lines running top to bottom over an egg-shaped body (onion layers,
-- zucchini stripes): flat ellipses a hair bigger than the body.
local function meridians(b: Builder, center: Vector3, size: Vector3, count: number, color: Color3)
	for k = 0, count - 1 do
		egg(b, "Stripe", V(0.08, size.Y * 1.01, size.Z * 1.02), CF(center) * ANG(0, rad(k * 180 / count), 0), color)
	end
end

-- A smooth tube through a list of points. Thick tubes are overlapping balls
-- (soft and lumpy, like dough); thinner ones are rods with a ball at each bend.
local function tube(b: Builder, name: string, points: { Vector3 }, d: number, color: Color3, material: Enum.Material?)
	if d < 0.5 then
		for i = 1, #points - 1 do
			local from, to = points[i], points[i + 1]
			local up = if math.abs((to - from).Unit.Y) > 0.99 then V(0, 0, 1) else V(0, 1, 0)
			b.add(name, "Cylinder", V((to - from).Magnitude, d, d), CFrame.lookAt((from + to) / 2, to, up) * ANG(0, rad(90), 0), color, material)
		end
		for _, p in points do
			ball(b, name, d, p, color, material)
		end
		return
	end
	for i = 1, #points - 1 do
		local from, to = points[i], points[i + 1]
		local steps = math.max(1, math.ceil((to - from).Magnitude / (d * 0.5)))
		for k = 0, steps - 1 do
			ball(b, name, d, from + (to - from) * (k / steps), color, material)
		end
	end
	ball(b, name, d, points[#points], color, material)
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
	capsule(b, "Chopstick", V(0.05, 2.2, 0.08), V(0.85, 4.35, 0.68), 0.13, chopstick)
	capsule(b, "Chopstick", V(0.3, 2.2, 0.05), V(1.24, 4.27, 0.5), 0.13, chopstick)
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
	egg(b, "Mouth", V(0.62, 0.16, 0.12), CF(0, 2.4, -0.93), BLACK, nil, true)
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
		egg(b, "Shades", V(0.62, 0.42, 0.18), CF(side * 0.33, 3.45, -0.78), BLACK, Enum.Material.Glass, true)
		egg(b, "ShadesShine", V(0.18, 0.08, 0.05), CF(side * 0.33 - 0.12, 3.55, -0.88) * ANG(0, 0, rad(20)), WHITE, Enum.Material.Neon, true)
	end
	capsule(b, "Bridge", V(-0.06, 3.5, -0.82), V(0.06, 3.5, -0.82), 0.07, BLACK, nil, true)
	capsule(b, "Smirk", V(-0.12, 2.92, -0.8), V(0.32, 3.0, -0.78), 0.1, BLACK, nil, true)
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
	egg(b, "HatBrim", V(2.3, 0.28, 2.3), CF(0, 4.68, 0), a)
	cone(b, "Hat", V(0, 4.7, 0), 1.65, 1.45, 0.25, a)
	vcyl(b, "HatBand", 0.18, 1.33, V(0, 4.9, 0), Color3.fromRGB(255, 230, 80))
	ball(b, "HatStar", 0.45, V(0, 6.38, 0), Color3.fromRGB(255, 230, 80), Enum.Material.Neon, true)
	arms(b, 2.7, 1.0, a, 0.8)
	vcyl(b, "Staff", 3.6, 0.2, V(1.6, 1.9, -0.2), Color3.fromRGB(120, 80, 40))
	local orb = ball(b, "Orb", 0.65, V(1.6, 3.85, -0.2), Color3.fromRGB(80, 220, 255), Enum.Material.Neon, true)
	local glow = Instance.new("PointLight")
	glow.Color = orb.Color
	glow.Range = 8
	glow.Parent = orb
	return 6.5
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
		egg(b, "BandTail", V(0.3, 1.0, 0.16), CF(side * 0.25, 2.3, 1.05) * ANG(rad(30), 0, side * rad(25)), a)
	end
	eyes(b, 0, 2.2, -1.0, 0.45, 0.5, true)
	box(b, "Blade", V(0.15, 2.6, 0.3), CF(0.3, 2.3, 1.15) * ANG(0, 0, rad(35)), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
	box(b, "Hilt", V(0.25, 0.7, 0.35), CF(-0.6, 1.0, 1.15) * ANG(0, 0, rad(35)), BLACK)
	return 3.4
end

designs.PinguinoHackerino = function(b, c, a)
	local orange = Color3.fromRGB(255, 150, 40)
	for _, side in { -1, 1 } do
		egg(b, "Foot", V(0.75, 0.28, 1.1), CF(side * 0.5, 0.14, -0.3), orange)
	end
	egg(b, "Body", V(2.4, 3.2, 2.2), CF(0, 1.8, 0), c)
	egg(b, "Belly", V(1.8, 2.4, 0.6), CF(0, 1.7, -0.85), WHITE)
	egg(b, "Head", V(1.8, 1.6, 1.7), CF(0, 3.75, 0), c)
	egg(b, "FaceWhite", V(1.3, 1.0, 0.3), CF(0, 3.7, -0.75), WHITE)
	egg(b, "Beak", V(0.55, 0.3, 0.6), CF(0, 3.45, -0.98) * ANG(rad(-10), 0, 0), orange)
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
	smile(b, 0, 1.9, -0.94, 0.9)
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
		capsule(b, "Horn", V(side * 0.42, 4.0, -1.2), V(side * 0.6, 4.55, -1.05), 0.26, a)
		ball(b, "HornTip", 0.18, V(side * 0.64, 4.7, -1.0), a)
		-- Wing: a bony arm with three rounded membrane panels fanning out.
		local shoulder = V(side * 0.9, 3.0, 0.4)
		local elbow = V(side * 2.1, 3.9, 0.6)
		capsule(b, "WingArm", shoulder, elbow, 0.22, c)
		for k = 0, 2 do
			local tip = elbow + V(side * (0.4 + k * 0.35), -0.6 - k * 0.65, 0.1)
			capsule(b, "WingFinger", elbow, tip, 0.12, c)
			local mid = (shoulder + elbow + tip) / 3
			egg(b, "Wing", V(0.08, 1.3, 1.0), CF(mid) * ANG(0, 0, side * rad(55 + k * 18)) * ANG(0, rad(90), 0), darker(c, 0.3))
		end
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
		egg(b, "Basil", V(0.55, 0.1, 0.32), CF(pos) * ANG(0, rad(30), 0), Color3.fromRGB(60, 160, 60))
	end
	local gold = Color3.fromRGB(255, 200, 50)
	vcyl(b, "Crown", 0.5, 1.4, V(0, 4.4, 0), gold, Enum.Material.Foil, true)
	for i = 1, 5 do
		local angle = rad(i * 72)
		cone(b, "CrownSpike", V(math.cos(angle) * 0.55, 4.6, math.sin(angle) * 0.55), 0.5, 0.32, 0.08, gold, Enum.Material.Foil, true)
		ball(b, "CrownGem", 0.18, V(math.cos(angle) * 0.6, 4.62, math.sin(angle) * 0.6) * V(1.18, 1, 1.18), if i % 2 == 0 then Color3.fromRGB(230, 40, 60) else Color3.fromRGB(60, 140, 255), Enum.Material.Neon, true)
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

-- The free starter: a happy little potato with a sprout.
designs.PatatinoPiccolino = function(b, c, a)
	legs(b, darker(c, 0.35), 0.6, 0.45)
	egg(b, "Potato", V(2.2, 2.4, 1.9), CF(0, 1.85, 0) * ANG(0, 0, rad(8)), c)
	for _, spot in { { -0.65, 2.55, -0.8 }, { 0.72, 1.35, -0.75 }, { -0.35, 1.15, -0.85 }, { 0.85, 2.65, -0.55 } } do
		ball(b, "Spot", 0.22, V(spot[1], spot[2], spot[3]), darker(c, 0.3), nil, true)
	end
	eyes(b, 0, 2.2, -0.82, 0.42, 0.5)
	smile(b, 0, 1.62, -0.92, 0.5)
	for _, side in { -1, 1 } do
		zcyl(b, "Blush", 0.05, 0.38, V(side * 0.72, 1.82, -0.88), Color3.fromRGB(255, 150, 150), nil, true)
	end
	vcyl(b, "Stem", 0.6, 0.14, V(0.05, 3.3, 0), a)
	for _, side in { -1, 1 } do
		egg(b, "Leaf", V(0.75, 0.18, 0.42), CF(side * 0.36, 3.58, 0) * ANG(0, 0, side * rad(25)), a)
	end
	arms(b, 1.9, 0.95, c, 0.6)
	return 3.9
end

-- A stretchy bubblegum blob blowing a big bubble.
designs.BubblegummoBlobbo = function(b, c, a)
	legs(b, darker(c, 0.25), 0.6, 0.55)
	egg(b, "Blob", V(2.4, 2.0, 2.2), CF(0, 1.6, 0), c)
	egg(b, "BlobTop", V(1.6, 1.2, 1.5), CF(0.2, 2.6, 0.1), c)
	for _, drip in { { -1.0, 0.95 }, { 0.95, 1.05 }, { 0.25, 0.8 } } do
		egg(b, "Drip", V(0.4, 0.8, 0.4), CF(drip[1], drip[2], -0.72), c)
	end
	eyes(b, 0, 2.15, -0.98, 0.45, 0.5)
	local bubble = ball(b, "Bubble", 1.6, V(0, 1.45, -1.85), a, Enum.Material.Glass, true)
	bubble.Transparency = 0.25
	ball(b, "BubbleShine", 0.3, V(-0.35, 1.8, -2.55), WHITE, Enum.Material.Neon, true)
	arms(b, 1.7, 1.1, c, 0.7)
	return 3.4
end

-- A tall ice-cream cone with two scoops, sprinkles and a cherry.
designs.GelatinoGigante = function(b, c, a)
	local waffle = Color3.fromRGB(215, 160, 80)
	legs(b, darker(waffle, 0.3), 0.7, 0.4)
	cone(b, "Cone", V(0, 0.7, 0), 2.5, 0.45, 2.05, waffle, nil, nil, darker(waffle, 0.12))
	ball(b, "Scoop", 2.3, V(0, 3.45, 0), c)
	ball(b, "Scoop2", 1.9, V(0, 4.75, 0), a)
	egg(b, "Drizzle", V(1.9, 0.45, 1.9), CF(0, 5.35, 0), Color3.fromRGB(80, 40, 25))
	ball(b, "Cherry", 0.55, V(0, 5.8, 0), Color3.fromRGB(220, 30, 40))
	capsule(b, "CherryStem", V(0, 5.95, 0), V(0.2, 6.4, 0), 0.07, Color3.fromRGB(60, 120, 40))
	local sprinkle = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 160, 255), WHITE }
	for i = 1, 10 do
		local angle = rad(i * 36)
		local p = V(math.cos(angle) * 0.9, 4.75 + math.sin(i * 1.7) * 0.5, math.sin(angle) * 0.9)
		egg(b, "Sprinkle", V(0.24, 0.09, 0.09), CF(p) * ANG(0, angle, rad(i * 40)), sprinkle[i % 4 + 1], nil, true)
	end
	eyes(b, 0, 3.55, -1.05, 0.45, 0.5)
	smile(b, 0, 3.0, -1.12, 0.5)
	arms(b, 3.0, 1.05, c, 0.8)
	return 6.3
end

-- A frosted donut on its edge, crackling with electricity.
designs.DonuttoDynamo = function(b, c, a)
	local dough = Color3.fromRGB(215, 160, 90)
	legs(b, darker(dough, 0.3), 0.9, 0.6)
	local center = V(0, 2.95, 0)
	for i = 0, 15 do
		local angle = rad(i * 22.5)
		local p = center + V(math.cos(angle) * 1.35, math.sin(angle) * 1.35, 0)
		ball(b, "Dough", 1.25, p, dough)
		ball(b, "Frosting", 1.05, p + V(0, 0, -0.3), c)
	end
	local sprinkle = { WHITE, Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 160, 255), Color3.fromRGB(120, 230, 120) }
	for i = 0, 13 do
		local angle = rad(i * 25.7 + 10)
		local p = center + V(math.cos(angle) * 1.35, math.sin(angle) * 1.35, -0.85)
		egg(b, "Sprinkle", V(0.26, 0.1, 0.1), CF(p) * ANG(0, 0, rad(i * 47)), sprinkle[i % 4 + 1], nil, true)
	end
	eyes(b, 0, 4.2, -0.85, 0.48, 0.48)
	smile(b, 0, 1.75, -0.85, 0.6)
	for _, side in { -1, 1 } do
		local x = side * 2.35
		box(b, "Bolt", V(0.22, 0.7, 0.2), CF(x, 3.6, 0) * ANG(0, 0, rad(-25 * side)), a, Enum.Material.Neon, true)
		box(b, "Bolt", V(0.5, 0.18, 0.2), CF(x + side * 0.12, 3.25, 0), a, Enum.Material.Neon, true)
		box(b, "Bolt", V(0.22, 0.7, 0.2), CF(x + side * 0.25, 2.9, 0) * ANG(0, 0, rad(-25 * side)), a, Enum.Material.Neon, true)
	end
	arms(b, 2.9, 1.95, dough, 0.6)
	return 4.8
end

-- Tung Tung Tung Sahur: a tall wooden log with a big grin and a baseball bat.
designs.TungTungSahur = function(b, c, a)
	local grain = darker(c, 0.18)
	legs(b, c, 1.0, 0.55)
	vcyl(b, "Log", 4.2, 1.9, V(0, 3.1, 0), c, Enum.Material.Wood)
	ball(b, "LogTop", 1.9, V(0, 5.2, 0), c, Enum.Material.Wood)
	-- Wood grain rings and a knot
	for _, y in { 1.6, 2.6, 4.3 } do
		vcyl(b, "Grain", 0.08, 1.94, V(0, y, 0), grain, Enum.Material.Wood)
	end
	zcyl(b, "Knot", 0.1, 0.4, V(0.55, 1.9, -0.93), a, Enum.Material.Wood, true)
	-- Big round eyes, eyebrows and a wide grin
	eyes(b, 0, 4.35, -0.85, 0.42, 0.62)
	for _, side in { -1, 1 } do
		egg(b, "Brow", V(0.66, 0.18, 0.16), CF(side * 0.42, 4.95, -0.92) * ANG(0, 0, side * rad(-12)), darker(a, 0.4), nil, true)
	end
	egg(b, "Mouth", V(1.1, 0.42, 0.2), CF(0, 3.55, -0.92), Color3.fromRGB(60, 20, 20), nil, true)
	egg(b, "Teeth", V(0.9, 0.14, 0.1), CF(0, 3.66, -1.0), WHITE, nil, true)
	-- Thin wooden arms; one holds a baseball bat
	for _, side in { -1, 1 } do
		local shoulder = V(side * 0.95, 3.4, 0)
		local hand = V(side * 1.7, 2.6, -0.4)
		capsule(b, "Arm", shoulder, hand, 0.28, c, Enum.Material.Wood)
		ball(b, "Hand", 0.42, hand, c, Enum.Material.Wood)
	end
	local bat = Color3.fromRGB(215, 175, 110)
	capsule(b, "Bat", V(1.7, 2.55, -0.45), V(2.2, 5.1, -0.6), 0.32, bat, Enum.Material.Wood)
	ball(b, "BatEnd", 0.55, V(2.25, 5.25, -0.62), bat, Enum.Material.Wood)
	return 6.3
end

-- A salmon sushi roll in a samurai helmet, katana ready.
designs.SushitoSamurai = function(b, c, a)
	local rice = Color3.fromRGB(245, 245, 240)
	local nori = Color3.fromRGB(25, 45, 30)
	local gold = Color3.fromRGB(255, 200, 60)
	legs(b, nori, 0.8, 0.6)
	vcyl(b, "Nori", 2.4, 2.5, V(0, 2.05, 0), nori)
	vcyl(b, "RiceTop", 0.12, 2.25, V(0, 3.28, 0), rice)
	for i = 1, 8 do
		local angle = rad(i * 45)
		ball(b, "Grain", 0.3, V(math.cos(angle) * 0.75, 3.36, math.sin(angle) * 0.75), rice)
	end
	egg(b, "Salmon", V(2.3, 0.7, 1.6), CF(0, 3.6, 0) * ANG(0, rad(15), 0), c)
	for i = -1, 1 do
		egg(b, "SalmonStripe", V(0.16, 0.1, 1.4), CF(i * 0.55, 3.92, 0) * ANG(0, rad(15), 0), WHITE, nil, true)
	end
	-- Kabuto helmet with golden horns
	egg(b, "Helmet", V(2.2, 0.85, 1.9), CF(0, 4.25, 0), a, Enum.Material.Metal)
	box(b, "HelmetBrim", V(2.6, 0.15, 0.5), CF(0, 4.0, -0.85), darker(a, 0.3), Enum.Material.Metal)
	for _, side in { -1, 1 } do
		capsule(b, "Horn", V(side * 0.1, 4.45, -0.9), V(side * 0.62, 5.35, -0.95), 0.16, gold, Enum.Material.Foil, true)
	end
	eyes(b, 0, 2.45, -1.22, 0.5, 0.55, true)
	egg(b, "Mouth", V(0.62, 0.14, 0.12), CF(0, 1.85, -1.25), WHITE, nil, true)
	-- Katana
	box(b, "Blade", V(0.12, 2.6, 0.3), CF(1.75, 2.9, -0.4) * ANG(0, 0, rad(-20)), Color3.fromRGB(220, 225, 235), Enum.Material.Metal, true)
	box(b, "Guard", V(0.5, 0.12, 0.5), CF(1.35, 1.75, -0.4), gold, Enum.Material.Foil, true)
	box(b, "Handle", V(0.16, 0.7, 0.16), CF(1.25, 1.4, -0.4) * ANG(0, 0, rad(-20)), Color3.fromRGB(40, 20, 20), nil, true)
	arms(b, 2.3, 1.25, nori, 0.8)
	return 5.3
end

-- A taco with a dinosaur poking out of it, crowned and roaring.
designs.TacoraptorSupremo = function(b, c, a)
	local dino = darker(a, 0.1)
	local meat = Color3.fromRGB(120, 60, 35)
	legs(b, dino, 2.1, 0.7)
	-- The shell: a thin U, open at the top
	for i = 0, 12 do
		local angle = rad(180 + 15 * i)
		local p = V(math.cos(angle) * 1.5, 3.4 + math.sin(angle) * 1.4, 0)
		egg(b, "Shell", V(0.5, 0.55, 1.9), CF(p) * ANG(0, 0, angle + rad(90)), c)
	end
	egg(b, "Meat", V(2.8, 0.7, 1.7), CF(0, 3.2, 0), meat)
	for i = -3, 3 do
		ball(b, "Lettuce", 0.62, V(i * 0.48, 3.7, if i % 2 == 0 then -0.35 else 0.3), a)
	end
	for _, x in { -1.0, 0.1, 0.9 } do
		ball(b, "Tomato", 0.42, V(x, 3.85, 0.05), Color3.fromRGB(220, 40, 40))
	end
	for i = 1, 6 do
		egg(b, "Cheese", V(0.5, 0.1, 0.12), CF(-1.2 + i * 0.38, 3.95, -0.2) * ANG(0, rad(i * 30), 0), Color3.fromRGB(255, 210, 60))
	end
	-- Dinosaur head out the front, tail out the back
	egg(b, "Neck", V(0.9, 1.3, 0.9), CF(0, 4.15, -1.25) * ANG(rad(-30), 0, 0), dino)
	egg(b, "Head", V(1.4, 1.1, 1.7), CF(0, 4.75, -1.85), dino)
	egg(b, "Jaw", V(1.1, 0.4, 1.2), CF(0, 4.3, -2.2), dino)
	for i = -2, 2 do
		cone(b, "Tooth", V(i * 0.18, 4.42, -2.72), 0.2, 0.13, 0.03, WHITE, nil, true)
	end
	eyes(b, 0, 5.05, -2.35, 0.38, 0.42, true)
	for i = 0, 5 do
		local t = i / 5
		ball(b, "Tail", 0.75 - t * 0.4, V(0.3 * math.sin(t * 3), 3.4 + t * 0.3, 1.2 + t * 1.5), dino)
	end
	local gold = Color3.fromRGB(255, 200, 50)
	vcyl(b, "Crown", 0.35, 0.9, V(0, 5.4, -1.75), gold, Enum.Material.Foil, true)
	for i = 1, 5 do
		local angle = rad(i * 72)
		cone(b, "CrownSpike", V(math.cos(angle) * 0.35, 5.55, -1.75 + math.sin(angle) * 0.35), 0.38, 0.22, 0.05, gold, Enum.Material.Foil, true)
	end
	arms(b, 3.3, 1.65, dino, 0.5)
	return 6.0
end

-- A sandwich astronaut in a glass helmet, with a jetpack and orbiting stars.
designs.AstronautoPanino = function(b, c, a)
	local metal = Color3.fromRGB(180, 180, 195)
	local bread = Color3.fromRGB(230, 180, 100)
	legs(b, c, 1.0, 0.6)
	egg(b, "Suit", V(2.4, 2.2, 2.0), CF(0, 2.0, 0), c)
	box(b, "Panel", V(1.0, 0.6, 0.15), CF(0, 2.2, -1.0), a, Enum.Material.Neon, true)
	for i = -1, 1 do
		ball(b, "Button", 0.18, V(i * 0.3, 1.75, -0.98), if i == 0 then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(255, 220, 60), Enum.Material.Neon, true)
	end
	vcyl(b, "Collar", 0.3, 2.0, V(0, 2.95, 0), metal, Enum.Material.Metal)
	-- The sandwich head
	box(b, "BreadBottom", V(1.6, 0.35, 1.4), CF(0, 3.4, 0), bread)
	box(b, "Lettuce", V(1.75, 0.15, 1.55), CF(0, 3.62, 0), Color3.fromRGB(90, 200, 70))
	box(b, "Ham", V(1.65, 0.18, 1.45), CF(0, 3.77, 0), Color3.fromRGB(240, 140, 150))
	box(b, "Cheese", V(1.7, 0.12, 1.5), CF(0, 3.91, 0) * ANG(0, rad(10), 0), Color3.fromRGB(255, 210, 60))
	egg(b, "BreadTop", V(1.65, 0.65, 1.45), CF(0, 4.2, 0), bread)
	eyes(b, 0, 4.2, -0.68, 0.35, 0.4)
	local helmet = ball(b, "Helmet", 2.9, V(0, 3.85, 0), a, Enum.Material.Glass, true)
	helmet.Transparency = 0.72
	-- Jetpack
	for _, side in { -1, 1 } do
		vcyl(b, "Tank", 1.4, 0.6, V(side * 0.45, 2.2, 1.15), metal, Enum.Material.Metal)
		ball(b, "Flame", 0.5, V(side * 0.45, 1.3, 1.15), Color3.fromRGB(255, 140, 30), Enum.Material.Neon, true)
	end
	capsule(b, "Antenna", V(0.5, 5.2, 0), V(0.5, 5.95, 0), 0.09, metal, Enum.Material.Metal, true)
	ball(b, "AntennaTip", 0.3, V(0.5, 6.05, 0), a, Enum.Material.Neon, true)
	for i = 1, 8 do
		local angle = rad(i * 45)
		local p = CF(0, 3.6, 0) * ANG(rad(15), 0, rad(-10)) * CF(math.cos(angle) * 2.3, 0, math.sin(angle) * 2.3)
		ball(b, "Star", 0.22, p.Position, Color3.fromRGB(255, 240, 150), Enum.Material.Neon, true)
	end
	arms(b, 2.4, 1.2, c, 0.9)
	return 6.2
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

-- The 67 Nights Deer: a skinny forest deer with a huge round head, staring
-- saucer eyes, a gaping mouth and freakishly long arms ending in claws.
designs.SixtySevenNights = function(b, c, a)
	local fur = c
	local belly = lighter(c, 0.12)
	local muzzle = Color3.fromRGB(225, 150, 140)
	local antler = Color3.fromRGB(48, 38, 38)
	local claw = Color3.fromRGB(125, 96, 70)

	-- Thin backward-bending legs with little hooves --------------------------
	for _, side in { -1, 1 } do
		local hip = V(side * 0.32, 2.15, 0.05)
		local knee = V(side * 0.38, 1.2, -0.22)
		local ankle = V(side * 0.36, 0.45, 0.12)
		capsule(b, "Thigh", hip, knee, 0.34, fur)
		capsule(b, "Shin", knee, ankle, 0.24, fur)
		egg(b, "Hoof", V(0.36, 0.34, 0.48), CF(side * 0.36, 0.17, 0.02), antler)
	end

	-- Skinny body with a lighter chest ---------------------------------------
	egg(b, "Body", V(1.05, 1.6, 0.85), CF(0, 2.75, 0.02), fur)
	egg(b, "Chest", V(0.7, 1.0, 0.3), CF(0, 2.95, -0.32), belly)
	egg(b, "Tail", V(0.3, 0.38, 0.3), CF(0, 2.35, 0.45), belly)
	capsule(b, "Neck", V(0, 3.35, 0), V(0, 3.8, -0.05), 0.5, fur)

	-- Long spindly arms, held out wide, with drooping claw fingers -----------
	for _, side in { -1, 1 } do
		local shoulder = V(side * 0.45, 3.3, 0)
		local elbow = V(side * 1.45, 3.65, -0.15)
		local wrist = V(side * 2.35, 3.35, -0.35)
		capsule(b, "UpperArm", shoulder, elbow, 0.26, fur)
		capsule(b, "Forearm", elbow, wrist, 0.22, fur)
		ball(b, "Palm", 0.32, wrist, fur)
		-- Four fingers fanned out front to back and inward to outward.
		for k = -1.5, 1.5 do
			local fan = (k + 1.5) / 3
			local knuckle = wrist + V(side * 0.2, -0.06, k * 0.15)
			local bend = knuckle + V(side * (0.12 + fan * 0.3), -0.6, k * 0.2 - 0.05)
			local tip = bend + V(side * (fan * 0.22 - 0.06), -0.8 + math.abs(k) * 0.1, k * 0.14 - 0.12)
			tube(b, "Finger", { knuckle, bend }, 0.14, claw)
			capsule(b, "Claw", bend, tip, 0.1, darker(claw, 0.3))
		end
	end

	-- Big round head ---------------------------------------------------------
	local headY = 4.7
	egg(b, "Head", V(1.9, 1.85, 1.65), CF(0, headY, 0), fur)
	egg(b, "Cheeks", V(1.45, 0.95, 1.2), CF(0, headY - 0.55, -0.22), fur)

	-- Saucer eyes: big white ovals with small black pupils --------------------
	for _, side in { -1, 1 } do
		local eye = V(side * 0.42, headY + 0.22, -0.7)
		egg(b, "Eye", V(0.66, 0.74, 0.34), CF(eye) * ANG(0, side * rad(-12), 0), WHITE, nil, true)
		egg(b, "EyeRim", V(0.74, 0.82, 0.26), CF(eye + V(0, 0, 0.05)) * ANG(0, side * rad(-12), 0), darker(fur, 0.45), nil, true)
		ball(b, "Pupil", 0.36, eye + V(-side * 0.02, -0.02, -0.12), BLACK, nil, true)
		ball(b, "Shine", 0.1, eye + V(side * 0.06, 0.1, -0.27), WHITE, Enum.Material.Neon, true)
	end

	-- Pink muzzle, shiny black nose and a gaping mouth ----------------------
	egg(b, "Muzzle", V(0.82, 0.62, 0.62), CF(0, headY - 0.38, -0.82), muzzle)
	local nose = egg(b, "Nose", V(0.34, 0.26, 0.24), CF(0, headY - 0.24, -1.12), Color3.fromRGB(30, 22, 24), nil, true)
	nose.Reflectance = 0.15
	egg(b, "MouthRim", V(0.6, 0.72, 0.3), CF(0, headY - 0.86, -0.82), muzzle, nil, true)
	egg(b, "Mouth", V(0.46, 0.6, 0.2), CF(0, headY - 0.86, -0.92), Color3.fromRGB(45, 14, 20), nil, true)
	egg(b, "Tongue", V(0.28, 0.16, 0.12), CF(0, headY - 1.06, -0.96), Color3.fromRGB(235, 110, 130), nil, true)

	-- Big ears with pink insides ----------------------------------------------
	for _, side in { -1, 1 } do
		local ear = CF(side * 1.0, headY + 0.55, 0.05) * ANG(0, side * rad(-15), side * rad(-58))
		egg(b, "Ear", V(0.5, 1.0, 0.24), ear, fur)
		egg(b, "EarInside", V(0.34, 0.78, 0.12), ear * CF(0, 0.02, -0.08), a, nil, true)
	end

	-- Dark branching antlers -------------------------------------------------
	for _, side in { -1, 1 } do
		local function at(x: number, y: number, z: number): Vector3
			return V(side * x, y, z)
		end
		tube(b, "Antler", { at(0.32, headY + 0.75, 0.05), at(0.42, headY + 1.3, 0.02), at(0.62, headY + 1.85, 0.08), at(0.58, headY + 2.35, 0.15) }, 0.16, antler)
		tube(b, "Tine", { at(0.42, headY + 1.3, 0.02), at(0.18, headY + 1.75, -0.06), at(0.14, headY + 2.0, -0.04) }, 0.12, antler)
		tube(b, "Tine", { at(0.62, headY + 1.85, 0.08), at(0.92, headY + 2.2, 0.06), at(1.0, headY + 2.45, 0.08) }, 0.12, antler)
	end
	return headY + 2.6
end

-- Flat 5-pointed star lying on a surface (`frame` faces outward along -Z).
local function star(b: Builder, name: string, frame: CFrame, size: number, color: Color3)
	for k = 0, 4 do
		local angle = rad(k * 72)
		b.add(name, "Egg", V(size * 0.32, size * 0.62, 0.06), frame * ANG(0, 0, angle) * CF(0, size * 0.3, 0), color, nil, true)
	end
	b.add(name, "Ball", V(size * 0.42, size * 0.42, 0.07), frame, color, nil, true)
end

designs.ScarpinoStellino = function(b, c, a)
	local blue = c
	local lightBlue = Color3.fromRGB(165, 180, 230)
	local cream = a
	local dark = Color3.fromRGB(50, 48, 60)

	-- Chunky platform sole (toe points forward, -Z)
	egg(b, "Outsole", V(1.75, 0.22, 2.7), CF(0, 0.11, -0.15), blue)
	egg(b, "Sole", V(1.85, 0.5, 2.8), CF(0, 0.32, -0.15), cream)
	egg(b, "SoleStripe", V(1.88, 0.1, 2.83), CF(0, 0.5, -0.15), blue)

	-- High-top upper: ankle shaft at the back, toe box in front
	egg(b, "Shaft", V(1.5, 1.7, 1.45), CF(0, 1.25, 0.35), cream)
	egg(b, "ToeBox", V(1.45, 0.75, 1.55), CF(0, 0.82, -0.6), cream)
	egg(b, "ToeCap", V(1.3, 0.55, 0.75), CF(0, 0.72, -1.2), blue)
	egg(b, "HeelCounter", V(1.4, 0.9, 0.6), CF(0, 0.95, 0.95), blue)
	for _, side in { -1, 1 } do
		egg(b, "SidePanel", V(0.1, 0.85, 1.5), CF(side * 0.74, 1.05, 0.05) * ANG(rad(-12), 0, 0), blue)
		star(b, "SideStar", CF(side * 0.8, 1.05, 0.15) * ANG(0, side * rad(90), 0), 0.55, lightBlue)
	end
	-- Tongue and criss-cross laces
	egg(b, "Tongue", V(0.62, 1.0, 0.3), CF(0, 1.35, -0.5) * ANG(rad(-15), 0, 0), lightBlue)
	for i = 0, 3 do
		local y = 0.95 + i * 0.2
		capsule(b, "Lace", V(-0.42, y, -0.66 + i * 0.05), V(0.42, y + 0.08, -0.66 + i * 0.05), 0.09, cream)
	end
	star(b, "HeelStar", CF(0, 1.15, 1.25) * ANG(0, rad(180), 0), 0.4, cream)

	-- Hoodie collar around the top of the shoe, with drawstrings + star charm
	for k = 0, 9 do
		local angle = rad(k * 36)
		egg(b, "Hood", V(0.55, 0.45, 0.55), CF(math.cos(angle) * 0.6, 2.12, 0.3 + math.sin(angle) * 0.55), cream, Enum.Material.Fabric)
	end
	for _, side in { -1, 1 } do
		capsule(b, "Drawstring", V(side * 0.22, 2.0, -0.28), V(side * 0.28, 1.45, -0.42), 0.07, cream)
	end
	star(b, "Charm", CF(0.28, 1.35, -0.48), 0.32, blue)

	-- Short neck post
	vcyl(b, "Neck", 0.45, 0.42, V(0, 2.4, 0.3), dark)

	-- Head: cream with blue camo patches and a pointed blue beak
	egg(b, "Head", V(1.15, 1.2, 1.25), CF(0, 3.0, 0.25), cream)
	for _, patch in { { -0.45, 3.2, 0.5 }, { 0.5, 2.85, 0.45 }, { 0.2, 3.35, 0.75 }, { -0.35, 2.75, 0.05 } } do
		egg(b, "Camo", V(0.5, 0.42, 0.5), CF(patch[1], patch[2], patch[3]), lightBlue)
	end
	for i = 0, 3 do
		local t = i / 3
		egg(b, "Beak", V(0.42 - t * 0.28, 0.4 - t * 0.26, 0.4), CF(0, 2.9 - t * 0.04, -0.3 - t * 0.27), blue)
	end

	-- Big sleepy eyes on the sides of the head
	for _, side in { -1, 1 } do
		local eye = V(side * 0.47, 3.05, 0.12)
		local look = V(side * 0.55, 0, -0.84)
		egg(b, "Eye", V(0.6, 0.66, 0.6), CF(eye), WHITE, nil, true)
		ball(b, "Iris", 0.4, eye + look * 0.15, Color3.fromRGB(95, 125, 205), nil, true)
		ball(b, "Pupil", 0.2, eye + look * 0.26, BLACK, nil, true)
		ball(b, "Shine", 0.08, eye + look * 0.3 + V(0, 0.06, 0), WHITE, Enum.Material.Neon, true)
		-- Heavy lid gives the chill, half-closed look
		egg(b, "Lid", V(0.66, 0.3, 0.66), CF(eye + V(0, 0.22, 0)), blue)
		for i = -1, 1 do
			local base = eye + V(side * 0.12, 0.3, -0.05 + i * 0.12)
			capsule(b, "Lash", base, base + V(side * 0.14, 0.08, i * 0.04 - 0.02), 0.04, BLACK, nil, true)
		end
	end

	-- Backwards blue cap with a star and a strap
	egg(b, "Cap", V(1.25, 0.75, 1.3), CF(0, 3.55, 0.28), blue)
	egg(b, "CapBrim", V(1.0, 0.12, 0.9), CF(0, 3.32, 0.95) * ANG(rad(-8), 0, 0), blue)
	capsule(b, "CapStrap", V(-0.35, 3.35, -0.32), V(0.35, 3.35, -0.32), 0.1, cream)
	star(b, "CapStar", CF(0, 3.62, -0.34) * ANG(rad(-20), 0, 0), 0.42, cream)
	ball(b, "CapButton", 0.16, V(0, 3.93, 0.28), blue)

	-- Shoelace "hair": thick cream laces draping down from under the cap
	local strands = {
		{ -0.62, 0.05, 1.0 }, { -0.66, 0.45, 1.15 }, { -0.5, 0.8, 1.05 },
		{ 0.62, 0.05, 1.0 }, { 0.66, 0.45, 1.15 }, { 0.5, 0.8, 1.05 },
		{ -0.2, 0.9, 1.25 }, { 0.2, 0.9, 1.25 },
	}
	for i, strand in strands do
		local x, z, drop = strand[1], strand[2], strand[3]
		local top = V(x * 0.85, 3.35, z)
		local mid = V(x * 1.15, 3.35 - drop * 0.5, z + 0.05)
		local bottom = V(x * 1.05 + (if i % 2 == 0 then 0.08 else -0.08), 3.35 - drop, z + 0.12)
		capsule(b, "LaceHair", top, mid, 0.13, cream)
		capsule(b, "LaceHair", mid, bottom, 0.12, cream)
	end
	return 4.1
end

-- Draws a thick rounded stroke through a list of points (for letters/digits).
local function stroke(b: Builder, name: string, points: { Vector3 }, d: number, color: Color3)
	for i = 1, #points - 1 do
		capsule(b, name, points[i], points[i + 1], d, color)
	end
end

designs.TireinaFrogiva = function(b, c, a)
	local green = c
	local yellow = a
	local rubber = Color3.fromRGB(32, 32, 35)
	-- Walking yellow legs (one stepping forward, one back)
	capsule(b, "Thigh", V(-0.3, 1.45, 0.1), V(-0.35, 0.85, -0.3), 0.32, yellow)
	capsule(b, "Shin", V(-0.35, 0.85, -0.3), V(-0.32, 0.22, -0.1), 0.28, yellow)
	capsule(b, "Thigh", V(0.3, 1.45, 0.1), V(0.35, 0.85, 0.3), 0.32, yellow)
	capsule(b, "Shin", V(0.35, 0.85, 0.3), V(0.36, 0.28, 0.5), 0.28, yellow)
	egg(b, "Foot", V(0.42, 0.18, 0.8), CF(-0.32, 0.1, -0.35), yellow)
	egg(b, "Foot", V(0.42, 0.18, 0.8), CF(0.36, 0.16, 0.25) * ANG(rad(15), 0, 0), yellow)
	-- Green body peeking through the tire
	egg(b, "Body", V(0.75, 1.15, 0.7), CF(0, 2.05, 0), green)
	-- The tire: two rubber rings side by side, with tread blocks around it
	local center = V(0, 2.05, 0)
	local radius = 0.82
	for _, x in { -0.24, 0.24 } do
		local points = {}
		for k = 0, 12 do
			local angle = rad(k * 30)
			table.insert(points, center + V(x, math.cos(angle) * radius, math.sin(angle) * radius))
		end
		stroke(b, "Tire", points, 0.55, rubber)
	end
	for k = 0, 11 do
		local angle = rad(k * 30 + 15)
		local outward = V(0, math.cos(angle), math.sin(angle))
		b.add("Tread", "Block", V(0.62, 0.14, 0.22), CFrame.lookAt(center + outward * (radius + 0.27), center) * ANG(0, 0, 0), Color3.fromRGB(55, 55, 60))
	end
	-- Green arms with yellow hands
	capsule(b, "Arm", V(-0.5, 2.45, 0), V(-0.62, 1.6, -0.2), 0.26, green)
	capsule(b, "Arm", V(0.5, 2.45, 0), V(0.6, 1.65, 0.25), 0.26, green)
	ball(b, "Hand", 0.36, V(-0.62, 1.52, -0.22), yellow)
	ball(b, "Hand", 0.36, V(0.6, 1.57, 0.27), yellow)
	-- Frog head: wide and flat, pale jaw, bulging yellow eyes on top
	egg(b, "Head", V(1.35, 0.85, 1.25), CF(0, 3.2, -0.05), green)
	egg(b, "Jaw", V(1.15, 0.38, 1.05), CF(0, 2.98, -0.12), Color3.fromRGB(190, 215, 90))
	egg(b, "Mouth", V(1.0, 0.05, 0.1), CF(0, 3.06, -0.66), Color3.fromRGB(40, 70, 30), nil, true)
	for _, side in { -1, 1 } do
		ball(b, "EyeBump", 0.6, V(side * 0.38, 3.58, -0.15), green)
		ball(b, "Eye", 0.46, V(side * 0.38, 3.62, -0.3), Color3.fromRGB(250, 220, 60), nil, true)
		egg(b, "Pupil", V(0.26, 0.18, 0.1), CF(side * 0.38, 3.62, -0.53), BLACK, nil, true)
		ball(b, "Shine", 0.07, V(side * 0.33, 3.68, -0.55), WHITE, Enum.Material.Neon, true)
		ball(b, "Nostril", 0.06, V(side * 0.1, 3.3, -0.65), Color3.fromRGB(40, 70, 30), nil, true)
	end
	return 3.9
end

designs.SixSeven = function(b, c, a)
	local blue = c
	local glove = a
	local d = 0.62
	-- The "6": a round bottom loop with a stem curling up and over
	local six = {}
	for k = 0, 12 do
		local angle = rad(180 + k * 30)
		table.insert(six, V(-0.55 + math.cos(angle) * 0.45, 1.8 + math.sin(angle) * 0.45, 0))
	end
	table.insert(six, V(-1.0, 2.3, 0))
	table.insert(six, V(-0.88, 2.75, 0))
	table.insert(six, V(-0.58, 3.0, 0))
	table.insert(six, V(-0.22, 2.95, 0))
	stroke(b, "Six", six, d, blue)
	egg(b, "SixFill", V(0.5, 0.5, 0.4), CF(-0.55, 1.8, 0.05), blue:Lerp(BLACK, 0.2))
	-- The "7": a top bar and a slanted leg
	stroke(b, "Seven", { V(0.05, 3.0, 0), V(1.1, 3.0, 0), V(0.55, 1.35, 0) }, d, blue)
	-- Face across the 6: big eyes, brows and a wide grin
	eyes(b, -0.35, 2.4, -0.3, 0.22, 0.44)
	for _, side in { -1, 1 } do
		capsule(b, "Brow", V(-0.35 + side * 0.22 - 0.12, 2.75, -0.32), V(-0.35 + side * 0.22 + 0.12, 2.78 + side * 0.03, -0.32), 0.06, BLACK, nil, true)
	end
	egg(b, "Grin", V(0.62, 0.3, 0.12), CF(-0.5, 1.95, -0.33), WHITE, nil, true)
	egg(b, "GrinLine", V(0.66, 0.06, 0.12), CF(-0.5, 2.05, -0.35), BLACK, nil, true)
	-- Skinny arms with big white cartoon gloves
	capsule(b, "Arm", V(-1.0, 2.05, 0), V(-1.5, 1.75, -0.1), 0.16, blue)
	capsule(b, "Arm", V(0.9, 2.55, 0), V(1.45, 2.75, -0.1), 0.16, blue)
	for _, hand in { V(-1.62, 1.72, -0.12), V(1.58, 2.8, -0.12) } do
		ball(b, "Glove", 0.48, hand, glove)
		egg(b, "Thumb", V(0.18, 0.28, 0.18), CF(hand + V(0, 0.22, -0.12)), glove)
	end
	-- Legs and big white shoes
	capsule(b, "Leg", V(-0.55, 1.35, 0), V(-0.6, 0.45, 0), 0.2, blue)
	capsule(b, "Leg", V(0.55, 1.35, 0), V(0.6, 0.45, 0), 0.2, blue)
	for _, x in { -0.62, 0.62 } do
		egg(b, "Shoe", V(0.62, 0.45, 1.0), CF(x, 0.22, -0.15), glove)
	end
	return 3.4
end

designs.BallerinaCapuchina = function(b, c, a)
	local skin = Color3.fromRGB(242, 205, 178)
	local peach = c
	local coffee = a
	local cup = Color3.fromRGB(246, 240, 228)
	-- Legs on pointe: one straight, one crossed in front
	capsule(b, "Leg", V(-0.15, 1.95, 0.05), V(-0.12, 0.45, 0.05), 0.24, skin)
	capsule(b, "Leg", V(0.15, 1.95, 0.05), V(-0.02, 0.6, -0.15), 0.24, skin)
	for _, foot in { V(-0.12, 0.22, 0.05), V(-0.02, 0.38, -0.17) } do
		egg(b, "PointeShoe", V(0.2, 0.45, 0.24), CF(foot), peach)
		capsule(b, "Ribbon", foot + V(-0.1, 0.25, 0), foot + V(0.1, 0.3, 0), 0.04, peach)
	end
	-- Tutu: layered ruffle discs
	egg(b, "TutuBase", V(1.8, 0.3, 1.8), CF(0, 2.0, 0.05), peach)
	for layer = 0, 1 do
		for k = 0, 13 do
			local angle = rad(k * (360 / 14) + layer * 12)
			local r = 0.85 - layer * 0.18
			egg(b, "Ruffle", V(0.5, 0.26, 0.5), CF(math.cos(angle) * r, 2.0 + layer * 0.12, 0.05 + math.sin(angle) * r), peach:Lerp(WHITE, layer * 0.15))
		end
	end
	-- Leotard bodice with thin straps, then shoulders and neck
	egg(b, "Bodice", V(0.7, 0.85, 0.5), CF(0, 2.5, 0.05), peach)
	egg(b, "Chest", V(0.72, 0.5, 0.48), CF(0, 2.95, 0.05), skin)
	for _, side in { -1, 1 } do
		capsule(b, "Strap", V(side * 0.16, 2.8, -0.2), V(side * 0.2, 3.12, -0.08), 0.04, peach)
	end
	capsule(b, "Neck", V(0, 3.1, 0.05), V(0, 3.4, 0.05), 0.24, skin)
	-- Arms: one raised high with a pointing hand, one held out to the side
	capsule(b, "Arm", V(0.32, 3.05, 0.05), V(0.62, 3.6, 0), 0.17, skin)
	capsule(b, "Arm", V(0.62, 3.6, 0), V(0.72, 4.3, -0.05), 0.15, skin)
	ball(b, "Hand", 0.22, V(0.74, 4.42, -0.05), skin)
	capsule(b, "Arm", V(-0.32, 3.05, 0.05), V(-0.82, 3.15, 0), 0.17, skin)
	capsule(b, "Arm", V(-0.82, 3.15, 0), V(-1.22, 3.42, -0.05), 0.15, skin)
	ball(b, "Hand", 0.22, V(-1.3, 3.48, -0.05), skin)

	-- Head: a cappuccino cup, wider at the top
	local rings = { { 1.25, 3.42 }, { 1.45, 3.62 }, { 1.6, 3.82 }, { 1.72, 4.02 }, { 1.8, 4.2 } }
	for _, ring in rings do
		vcyl(b, "Cup", 0.24, ring[1], V(0, ring[2], 0.05), cup, Enum.Material.SmoothPlastic)
	end
	vcyl(b, "Coffee", 0.06, 1.66, V(0, 4.32, 0.05), coffee)
	-- Latte-art leaf on the foam
	capsule(b, "LatteStem", V(0, 4.36, -0.45), V(0, 4.36, 0.55), 0.06, cup)
	for k = 0, 4 do
		local z = -0.35 + k * 0.2
		local width = 0.55 - math.abs(k - 2) * 0.12
		for _, side in { -1, 1 } do
			b.add("LatteLeaf", "Egg", V(width, 0.03, 0.1), CF(side * width * 0.45, 4.36, z) * ANG(0, side * rad(25), 0), cup)
		end
	end
	-- Cup handle on the left
	local handle = {}
	for k = 0, 6 do
		local angle = rad(-90 + k * 30)
		table.insert(handle, V(-0.88 - math.cos(angle) * 0.32, 3.78 + math.sin(angle) * 0.3, 0.05))
	end
	stroke(b, "Handle", handle, 0.12, cup)
	-- Cute face on the front of the cup
	for _, side in { -1, 1 } do
		local eye = V(side * 0.3, 3.85, -0.72)
		egg(b, "Eye", V(0.36, 0.42, 0.18), CF(eye), WHITE, nil, true)
		ball(b, "Iris", 0.28, eye + V(0, -0.02, -0.07), Color3.fromRGB(150, 90, 50), nil, true)
		ball(b, "Pupil", 0.14, eye + V(0, -0.02, -0.12), BLACK, nil, true)
		ball(b, "Shine", 0.06, eye + V(-0.05, 0.05, -0.15), WHITE, Enum.Material.Neon, true)
		capsule(b, "Lash", eye + V(side * 0.14, 0.18, -0.06), eye + V(side * 0.24, 0.26, -0.06), 0.04, BLACK, nil, true)
		capsule(b, "Brow", eye + V(-0.12, 0.3, -0.04), eye + V(0.12, 0.33, -0.04), 0.05, Color3.fromRGB(150, 100, 70), nil, true)
		egg(b, "Blush", V(0.22, 0.12, 0.05), CF(side * 0.48, 3.62, -0.74), Color3.fromRGB(255, 160, 160), nil, true)
	end
	ball(b, "Nose", 0.1, V(0, 3.68, -0.82), Color3.fromRGB(235, 200, 175))
	egg(b, "Smile", V(0.36, 0.14, 0.08), CF(0, 3.52, -0.74), Color3.fromRGB(190, 70, 80), nil, true)
	egg(b, "Teeth", V(0.26, 0.06, 0.08), CF(0, 3.55, -0.77), WHITE, nil, true)
	return 4.6
end

-- Designs drawn mirrored (left/right swapped) so text and poses read
-- correctly from the front.
-- More brainrots -------------------------------------------------------------

-- A teary onion with a sprout on top.
designs.CipollinoPiangino = function(b, c, a)
	legs(b, darker(c, 0.3), 0.7, 0.45)
	egg(b, "Bulb", V(2.3, 2.4, 2.3), CF(0, 2.0, 0), c)
	meridians(b, V(0, 2.0, 0), V(2.3, 2.4, 2.3), 4, darker(c, 0.18))
	cone(b, "Neck", V(0, 3.05, 0), 0.8, 0.6, 0.15, c)
	for _, tip in { V(-0.45, 4.35, 0.05), V(0.05, 4.6, 0), V(0.5, 4.3, -0.05) } do
		capsule(b, "Sprout", V(0, 3.7, 0), tip, 0.18, a)
	end
	eyes(b, 0, 2.3, -1.05, 0.42, 0.55)
	for _, side in { -1, 1 } do
		egg(b, "Tear", V(0.2, 0.4, 0.14), CF(side * 0.48, 1.85, -1.06), Color3.fromRGB(130, 200, 255), Enum.Material.Glass, true)
	end
	mouth(b, 0, 1.55, -1.08, 0.5, 0.3)
	arms(b, 1.9, 1.0, c, 0.6)
	return 4.6
end

-- A carrot in a headband, mid-sprint.
designs.CarotinoCorridore = function(b, c, a)
	local shoe = Color3.fromRGB(240, 240, 245)
	for _, leg in { { -0.25, -0.45 }, { 0.25, 0.45 } } do
		local foot = V(leg[1] * 1.2, 0.3, leg[2])
		capsule(b, "Leg", V(leg[1], 1.05, 0), foot, 0.28, darker(c, 0.35))
		egg(b, "Shoe", V(0.5, 0.35, 0.8), CF(foot.X, 0.18, foot.Z - 0.15), shoe)
		egg(b, "ShoeStripe", V(0.52, 0.12, 0.5), CF(foot.X, 0.22, foot.Z - 0.1), Color3.fromRGB(230, 40, 40))
	end
	cone(b, "Carrot", V(0, 0.85, 0), 2.7, 0.3, 1.55, c)
	egg(b, "CarrotTop", V(1.55, 0.5, 1.55), CF(0, 3.55, 0), c)
	for _, y in { 1.6, 2.25, 2.9 } do
		local d = 0.3 + 1.25 * (y - 0.85) / 2.7
		egg(b, "Ridge", V(d + 0.06, 0.08, d + 0.06), CF(0, y, 0), darker(c, 0.15))
	end
	for _, tip in { V(-0.5, 4.6, 0.1), V(0, 4.85, 0), V(0.5, 4.55, -0.1) } do
		capsule(b, "Leaf", V(0, 3.65, 0), tip, 0.24, a)
	end
	egg(b, "Headband", V(1.42, 0.2, 1.42), CF(0, 3.28, 0), Color3.fromRGB(230, 40, 40))
	eyes(b, 0, 2.95, -0.62, 0.3, 0.42)
	smile(b, 0, 2.45, -0.56, 0.42)
	for _, arm in { { -1, -0.35 }, { 1, 0.35 } } do
		local hand = V(arm[1] * 1.15, 1.9, arm[2])
		capsule(b, "Arm", V(arm[1] * 0.6, 2.45, 0), hand, 0.2, c)
		ball(b, "Hand", 0.34, hand, c)
	end
	return 5.0
end

-- A bouncy cherry tomato with a leafy crown.
designs.PomodorinoRimbalzo = function(b, c, a)
	legs(b, darker(c, 0.35), 0.55, 0.45)
	egg(b, "Tomato", V(2.6, 2.2, 2.6), CF(0, 1.85, 0), c)
	for k = 0, 4 do
		local angle = rad(k * 72)
		egg(b, "Calyx", V(0.85, 0.12, 0.32), CF(0, 2.95, 0) * ANG(0, angle, 0) * CF(0.38, 0, 0) * ANG(0, 0, rad(-12)), a)
	end
	vcyl(b, "Stem", 0.45, 0.16, V(0, 3.15, 0), darker(a, 0.2))
	egg(b, "Shine", V(0.45, 0.25, 0.1), CF(-0.62, 2.45, -1.08) * ANG(0, 0, rad(30)), WHITE, Enum.Material.Neon, true)
	eyes(b, 0, 2.05, -1.2, 0.48, 0.55)
	smile(b, 0, 1.5, -1.24, 0.55)
	blush(b, 0, 1.72, -1.2, 0.82)
	arms(b, 1.8, 1.25, c, 0.6)
	return 3.6
end

-- A choc-chip cookie dancer in a bow tie.
designs.BiscottinoBallerino = function(b, c, a)
	local shoe = WHITE
	capsule(b, "Leg", V(-0.4, 1.45, 0), V(-0.45, 0.35, 0), 0.28, a)
	capsule(b, "Leg", V(0.4, 1.45, 0), V(1.0, 1.05, -0.2), 0.28, a)
	egg(b, "Shoe", V(0.45, 0.3, 0.75), CF(-0.45, 0.18, -0.1), shoe)
	egg(b, "Shoe", V(0.45, 0.3, 0.7), CF(1.15, 1.0, -0.25) * ANG(0, 0, rad(-20)), shoe)
	egg(b, "Cookie", V(2.8, 2.8, 0.65), CF(0, 2.6, 0), c)
	for _, chip in { { -0.7, 3.3 }, { 0.6, 3.4 }, { -0.95, 2.3 }, { 0.95, 2.1 }, { 0.15, 1.6 }, { -0.4, 1.75 }, { 0.75, 2.85 } } do
		egg(b, "Chip", V(0.32, 0.28, 0.2), CF(chip[1], chip[2], -0.28), a)
	end
	eyes(b, 0, 2.9, -0.34, 0.45, 0.5)
	smile(b, 0, 2.3, -0.33, 0.5)
	for _, side in { -1, 1 } do
		egg(b, "BowTie", V(0.4, 0.28, 0.14), CF(side * 0.2, 1.68, -0.32) * ANG(0, 0, side * rad(-12)), Color3.fromRGB(220, 40, 60))
	end
	ball(b, "BowKnot", 0.16, V(0, 1.68, -0.38), Color3.fromRGB(180, 20, 40))
	for _, side in { -1, 1 } do
		local hand = V(side * 1.95, 3.85, 0)
		capsule(b, "Arm", V(side * 1.3, 2.85, 0), hand, 0.24, a)
		ball(b, "Glove", 0.4, hand, shoe)
	end
	return 4.4
end

-- A spotty mushroom with a cream stem.
designs.FungoFunghetto = function(b, c, a)
	legs(b, darker(a, 0.25), 0.5, 0.4)
	egg(b, "Stem", V(1.4, 1.9, 1.4), CF(0, 1.5, 0), a)
	egg(b, "Gills", V(3.0, 0.32, 3.0), CF(0, 2.38, 0), darker(a, 0.12))
	egg(b, "Cap", V(3.2, 1.7, 3.2), CF(0, 2.9, 0), c)
	ball(b, "Spot", 0.5, V(0, 3.72, 0), WHITE)
	for k = 0, 5 do
		local phi = rad(k * 60 + 30)
		local theta = rad(55)
		ball(b, "Spot", 0.45, V(1.6 * math.sin(theta) * math.cos(phi), 2.9 + 0.85 * math.cos(theta), 1.6 * math.sin(theta) * math.sin(phi)), WHITE)
	end
	eyes(b, 0, 1.75, -0.62, 0.3, 0.42)
	smile(b, 0, 1.3, -0.68, 0.35)
	blush(b, 0, 1.48, -0.63, 0.48, 0.25)
	arms(b, 1.5, 0.65, a, 0.5)
	return 4.0
end

-- A sleepy egg in a nightcap, mid-yawn.
designs.UovoSbadiglio = function(b, c, a)
	legs(b, Color3.fromRGB(255, 160, 60), 0.55, 0.4)
	egg(b, "Egg", V(2.0, 2.7, 2.0), CF(0, 2.1, 0), c)
	-- A zigzag crack across the front
	local crack = {}
	for i = 0, 6 do
		local t = rad(-70 + i * 23)
		local y = if i % 2 == 0 then 2.85 else 3.08
		local r = 1.0 * math.sqrt(1 - ((y - 2.1) / 1.35) ^ 2) + 0.01
		table.insert(crack, V(r * math.sin(t), y, -r * math.cos(t)))
	end
	tube(b, "Crack", crack, 0.08, darker(c, 0.45))
	eyes(b, 0, 2.3, -0.88, 0.36, 0.5)
	for _, side in { -1, 1 } do
		egg(b, "Eyelid", V(0.6, 0.32, 0.42), CF(side * 0.36, 2.44, -0.92), c, nil, true)
	end
	mouth(b, 0, 1.68, -0.95, 0.55, 0.55)
	local cap = Color3.fromRGB(90, 120, 220)
	egg(b, "CapBrim", V(1.3, 0.3, 1.3), CF(0, 3.32, 0), WHITE)
	cone(b, "Nightcap", V(0, 3.35, 0), 1.3, 1.15, 0.2, cap)
	ball(b, "Pompom", 0.45, V(0, 4.75, 0), WHITE)
	arms(b, 1.9, 0.9, c, 0.55)
	return 4.9
end

-- A hot chili pepper with a little fire on its head.
designs.PeperonePiccante = function(b, c, a)
	legs(b, darker(a, 0.1), 1.1, 0.3)
	for i = 0, 10 do
		local t = i / 10
		local d = 0.35 + 1.25 * t ^ 0.7
		local x = 0.45 * (1 - t) ^ 2
		egg(b, "Chili", V(d, 0.75, d), CF(x, 0.95 + t * 2.75, 0), c)
	end
	egg(b, "Cap", V(1.45, 0.38, 1.45), CF(0, 3.82, 0), a)
	capsule(b, "Stem", V(0, 3.9, 0), V(0.28, 4.45, 0), 0.25, a)
	for _, flame in { { -0.4, 4.25, 0.3, 0.9 }, { 0.42, 4.2, 0.35, 0.8 }, { 0, 4.45, 0.45, 1.0 } } do
		egg(b, "Flame", V(0.42, flame[4], 0.42), CF(flame[1], flame[2], flame[3]), Color3.fromRGB(255, 140, 30), Enum.Material.Neon, true)
		egg(b, "FlameCore", V(0.22, flame[4] * 0.55, 0.22), CF(flame[1], flame[2] - 0.1, flame[3] - 0.12), Color3.fromRGB(255, 230, 90), Enum.Material.Neon, true)
	end
	eyes(b, 0, 3.1, -0.68, 0.33, 0.44, true)
	mouth(b, 0, 2.55, -0.55, 0.42, 0.28)
	arms(b, 2.7, 0.75, c, 0.6)
	return 4.8
end

-- A fluffy pillow fast asleep, blowing a bubble.
designs.CuscinettoRonfone = function(b, c, a)
	legs(b, darker(c, 0.3), 0.8, 0.7)
	box(b, "Pillow", V(2.9, 2.0, 1.1), CF(0, 2.0, 0), c)
	for _, x in { -1.45, 1.45 } do
		for _, y in { 1.0, 3.0 } do
			ball(b, "Tassel", 0.32, V(x, y, 0), a)
		end
	end
	-- Closed, sleepy eyes (little arcs) and a tiny "o" mouth
	for _, side in { -1, 1 } do
		local arc = {}
		for i = -2, 2 do
			local t = i / 2
			table.insert(arc, V(side * 0.45 + t * 0.22, 2.25 - (1 - t * t) * 0.07, -0.58))
		end
		tube(b, "SleepyEye", arc, 0.07, BLACK)
	end
	egg(b, "Mouth", V(0.22, 0.26, 0.1), CF(0, 1.75, -0.58), Color3.fromRGB(70, 20, 25), nil, true)
	blush(b, 0, 1.95, -0.57, 0.8, 0.32)
	local bubble = ball(b, "SleepBubble", 0.55, V(0.32, 1.95, -0.85), a, Enum.Material.Glass, true)
	bubble.Transparency = 0.35
	arms(b, 2.2, 1.4, c, 0.5)
	return 3.6
end

-- A salty pretzel twisted around its own little face.
designs.PretzelinoAnnodato = function(b, c, a)
	legs(b, darker(c, 0.3), 1.0, 0.45)
	local center = V(0, 2.6, 0)
	local loop = {}
	for i = 0, 26 do
		local angle = rad(-40 + i * 10)
		table.insert(loop, center + V(math.cos(angle) * 1.35, math.sin(angle) * 1.35, 0))
	end
	tube(b, "Dough", loop, 0.6, c)
	tube(b, "Dough", { center + V(-1.03, -0.87, 0.1), V(0.55, 1.15, 0.12) }, 0.6, c)
	tube(b, "Dough", { center + V(1.03, -0.87, -0.1), V(-0.55, 1.15, -0.12) }, 0.6, c)
	egg(b, "Face", V(1.25, 1.05, 0.8), CF(0, 2.75, 0), lighter(c, 0.15))
	for _, salt in { V(-0.9, 3.7, -0.25), V(0.2, 4.0, -0.28), V(1.1, 3.45, -0.25), V(-1.35, 2.7, -0.25), V(1.4, 2.4, -0.25), V(0.25, 1.35, -0.3) } do
		egg(b, "Salt", V(0.14, 0.1, 0.1), CF(salt) * ANG(0, 0, salt.X), a, nil, true)
	end
	eyes(b, 0, 2.9, -0.42, 0.28, 0.36)
	smile(b, 0, 2.48, -0.42, 0.34)
	arms(b, 2.3, 1.5, c, 0.5)
	return 4.4
end

-- A tough eggplant in a fedora and a gold chain.
designs.MelanzanaMafiosa = function(b, c, a)
	local suit = Color3.fromRGB(40, 40, 46)
	local gold = Color3.fromRGB(255, 200, 60)
	legs(b, suit, 0.8, 0.45)
	egg(b, "Belly", V(2.3, 2.0, 2.2), CF(0, 1.8, 0), c)
	egg(b, "Body", V(1.95, 3.0, 1.85), CF(0, 2.45, 0), c)
	for k = 0, 4 do
		egg(b, "Leaf", V(0.9, 0.12, 0.38), CF(0, 3.72, 0) * ANG(0, rad(k * 72), 0) * CF(0.55, 0, 0) * ANG(0, 0, rad(-25)), Color3.fromRGB(70, 140, 60))
	end
	egg(b, "HatBrim", V(2.3, 0.18, 2.1), CF(0, 3.9, 0), a)
	vcyl(b, "HatCrown", 0.75, 1.35, V(0, 4.3, 0), a)
	vcyl(b, "HatBand", 0.18, 1.38, V(0, 4.05, 0), Color3.fromRGB(150, 20, 30))
	eyes(b, 0, 3.0, -0.84, 0.36, 0.42, true)
	egg(b, "Mustache", V(1.05, 0.24, 0.3), CF(0, 2.5, -0.9), a)
	for i = -4, 4 do
		local t = i / 4
		ball(b, "Chain", 0.15, V(t * 0.62, 2.0 - (1 - t * t) * 0.28, -1.0), gold, Enum.Material.Foil, true)
	end
	arms(b, 2.2, 0.95, suit, 0.8)
	return 5.0
end

-- A buff avocado flexing both arms.
designs.AvocadinoPalestrato = function(b, c, a)
	legs(b, darker(c, 0.2), 0.9, 0.55)
	egg(b, "Skin", V(2.4, 3.0, 1.9), CF(0, 2.4, 0), c)
	egg(b, "Flesh", V(2.0, 2.6, 0.6), CF(0, 2.35, -0.72), a)
	ball(b, "Pit", 1.0, V(0, 1.95, -0.92), Color3.fromRGB(140, 90, 50))
	egg(b, "Headband", V(1.75, 0.24, 1.45), CF(0, 3.55, 0), Color3.fromRGB(230, 40, 40))
	for _, side in { -1, 1 } do
		local shoulder = V(side * 1.2, 3.0, 0)
		local elbow = V(side * 1.95, 2.6, -0.1)
		local fist = V(side * 1.9, 3.5, -0.3)
		ball(b, "Shoulder", 0.9, shoulder, c)
		capsule(b, "UpperArm", shoulder, elbow, 0.68, c)
		egg(b, "Bicep", V(0.85, 0.65, 0.75), CF((shoulder + elbow) / 2 + V(0, 0.28, 0)), c)
		capsule(b, "Forearm", elbow, fist, 0.55, c)
		ball(b, "Fist", 0.72, fist, c)
	end
	eyes(b, 0, 3.05, -0.95, 0.34, 0.44, true)
	smile(b, 0, 2.62, -1.0, 0.5)
	return 4.6
end

-- A pineapple on a surfboard, sunglasses on, lei around its neck.
designs.AnanassoSurfista = function(b, c, a)
	egg(b, "Surfboard", V(1.4, 0.18, 4.2), CF(0, 0.12, 0), a)
	egg(b, "BoardStripe", V(0.3, 0.2, 4.0), CF(0, 0.14, 0), WHITE)
	legs(b, darker(c, 0.45), 0.95, 0.45)
	egg(b, "Body", V(2.0, 2.6, 2.0), CF(0, 2.35, 0), c)
	for row = 0, 3 do
		for k = -2, 2 do
			local theta = rad(55 + row * 22)
			local phi = rad(-90 + k * 28 + (row % 2) * 14)
			ball(b, "Scale", 0.16, V(1.0 * math.sin(theta) * math.cos(phi), 2.35 + 1.3 * math.cos(theta), 1.0 * math.sin(theta) * math.sin(phi)), darker(c, 0.35))
		end
	end
	for k = 0, 6 do
		local angle = rad(k * 51)
		egg(b, "Crown", V(0.3, 1.25, 0.16), CF(0, 3.65, 0) * ANG(0, angle, 0) * CF(0, 0.45, 0.25) * ANG(rad(25), 0, 0), Color3.fromRGB(60, 160, 70))
	end
	for _, side in { -1, 1 } do
		egg(b, "Shades", V(0.56, 0.38, 0.16), CF(side * 0.32, 2.75, -0.96), BLACK, Enum.Material.Glass, true)
	end
	capsule(b, "Bridge", V(-0.05, 2.8, -0.98), V(0.05, 2.8, -0.98), 0.06, BLACK, nil, true)
	smile(b, 0, 2.18, -1.0, 0.5)
	local leiColors = { Color3.fromRGB(255, 100, 170), Color3.fromRGB(255, 230, 80), Color3.fromRGB(90, 200, 255) }
	for k = 0, 13 do
		local angle = rad(k * 360 / 14)
		ball(b, "Lei", 0.3, V(math.cos(angle) * 0.92, 1.6, math.sin(angle) * 0.92), leiColors[k % 3 + 1])
	end
	arms(b, 2.3, 0.95, c, 0.7)
	return 4.7
end

-- A snail with a turbo shell and racing exhausts.
designs.LumaconeTurbo = function(b, c, a)
	egg(b, "Foot", V(1.25, 0.8, 3.7), CF(0, 0.45, 0.2), c)
	capsule(b, "Neck", V(0, 0.6, -1.2), V(0, 1.9, -1.5), 1.0, c)
	ball(b, "Head", 1.2, V(0, 2.1, -1.5), c)
	for _, side in { -1, 1 } do
		capsule(b, "Stalk", V(side * 0.25, 2.5, -1.5), V(side * 0.42, 3.15, -1.55), 0.16, c)
		ball(b, "Eye", 0.46, V(side * 0.42, 3.3, -1.58), WHITE, nil, true)
		ball(b, "Pupil", 0.22, V(side * 0.42, 3.28, -1.8), BLACK, nil, true)
	end
	smile(b, 0, 1.95, -2.08, 0.4)
	ball(b, "Shell", 2.4, V(0, 1.75, 0.6), a)
	-- Spiral on both sides of the shell
	for _, side in { -1, 1 } do
		local spiral = {}
		for i = 0, 11 do
			local t = i / 11
			local r = 1.0 * (1 - t) + 0.08
			local angle = t * math.pi * 3
			table.insert(spiral, V(side * math.sqrt(math.max(0, 1.2 ^ 2 - r ^ 2)), 1.75 + math.sin(angle) * r, 0.6 + math.cos(angle) * r))
		end
		tube(b, "Spiral", spiral, 0.14, darker(a, 0.35))
	end
	for _, side in { -1, 1 } do
		capsule(b, "Exhaust", V(side * 0.4, 1.5, 1.6), V(side * 0.45, 1.45, 2.35), 0.32, Color3.fromRGB(170, 170, 180), Enum.Material.Metal)
		ball(b, "ExhaustFlame", 0.38, V(side * 0.45, 1.45, 2.6), Color3.fromRGB(255, 140, 30), Enum.Material.Neon, true)
	end
	return 3.6
end

-- An octopus with curly tentacles.
designs.PolpettoOttopodo = function(b, c, a)
	egg(b, "Head", V(2.4, 2.5, 2.2), CF(0, 2.95, 0), c)
	for k = 0, 7 do
		local angle = rad(k * 45 + 22.5)
		local points = {}
		for i = 0, 6 do
			local t = i / 6
			local r = 0.75 + t * 1.15
			local y = 1.85 - t * 1.5 + (if t > 0.7 then (t - 0.7) * 1.6 else 0)
			table.insert(points, V(math.cos(angle) * r, math.max(0.25, y), math.sin(angle) * r))
		end
		for i, p in points do
			ball(b, "Tentacle", 0.62 * (1 - (i - 1) / 9), p, c)
		end
	end
	for _, spot in { V(-0.7, 3.7, -0.6), V(0.8, 3.5, -0.55), V(0.2, 4.0, -0.5) } do
		ball(b, "Spot", 0.3, spot, a, nil, true)
	end
	eyes(b, 0, 3.0, -1.02, 0.45, 0.6)
	smile(b, 0, 2.35, -1.02, 0.45)
	blush(b, 0, 2.55, -0.98, 0.78)
	return 4.3
end

-- A zucchini zombie, arms out, stitched mouth and bandages.
designs.ZucchinoZombie = function(b, c, a)
	legs(b, darker(c, 0.35), 0.85, 0.45)
	capsule(b, "Zucchini", V(0, 1.7, 0), V(0, 3.4, 0), 1.6, c)
	meridians(b, V(0, 2.55, 0), V(1.6, 3.3, 1.6), 4, lighter(c, 0.25))
	capsule(b, "Stem", V(0, 4.15, 0), V(0.18, 4.55, 0), 0.35, Color3.fromRGB(110, 80, 50))
	egg(b, "Bandage", V(1.72, 0.26, 1.72), CF(0, 2.3, 0) * ANG(0, 0, rad(-6)), a)
	egg(b, "Bandage", V(1.7, 0.22, 1.7), CF(0, 3.55, 0) * ANG(0, 0, rad(10)), a)
	ball(b, "Eye", 0.6, V(-0.32, 3.12, -0.66), WHITE, nil, true)
	ball(b, "Pupil", 0.24, V(-0.3, 3.1, -0.95), BLACK, nil, true)
	ball(b, "Eye", 0.4, V(0.35, 3.05, -0.72), WHITE, nil, true)
	ball(b, "Pupil", 0.16, V(0.37, 3.02, -0.9), BLACK, nil, true)
	capsule(b, "Stitches", V(-0.35, 2.6, -0.8), V(0.35, 2.6, -0.8), 0.07, BLACK, nil, true)
	for _, x in { -0.22, 0, 0.22 } do
		capsule(b, "Stitch", V(x, 2.5, -0.81), V(x, 2.7, -0.81), 0.05, BLACK, nil, true)
	end
	for _, side in { -1, 1 } do
		local hand = V(side * 0.7, 2.75, -1.35)
		capsule(b, "Arm", V(side * 0.75, 2.9, 0), hand, 0.34, c)
		ball(b, "Hand", 0.45, hand, c)
	end
	return 4.6
end

-- A strawberry ninja with a mask and a sword on its back.
designs.FragolinaNinja = function(b, c, a)
	legs(b, a, 0.75, 0.45)
	egg(b, "Tip", V(1.5, 1.6, 1.4), CF(0, 1.45, 0), c)
	egg(b, "Berry", V(2.2, 2.6, 2.1), CF(0, 2.25, 0), c)
	for row = 0, 2 do
		for k = -2, 2 do
			local theta = rad(85 + row * 22)
			local phi = rad(-90 + k * 30 + (row % 2) * 15)
			egg(b, "Seed", V(0.1, 0.16, 0.1), CF(1.1 * math.sin(theta) * math.cos(phi), 2.25 + 1.3 * math.cos(theta), 1.05 * math.sin(theta) * math.sin(phi)), Color3.fromRGB(255, 225, 90), nil, true)
		end
	end
	for k = 0, 5 do
		egg(b, "Leaf", V(0.85, 0.12, 0.34), CF(0, 3.45, 0) * ANG(0, rad(k * 60), 0) * CF(0.45, 0, 0) * ANG(0, 0, rad(-15)), Color3.fromRGB(60, 160, 70))
	end
	capsule(b, "Stem", V(0, 3.5, 0), V(0.1, 3.9, 0), 0.18, Color3.fromRGB(60, 140, 60))
	egg(b, "Mask", V(2.14, 0.55, 2.04), CF(0, 2.62, 0), a)
	eyes(b, 0, 2.64, -1.05, 0.38, 0.42, true)
	for _, side in { -1, 1 } do
		egg(b, "MaskTail", V(0.26, 0.95, 0.15), CF(side * 0.22, 2.3, 1.12) * ANG(rad(20), 0, side * rad(20)), a)
	end
	capsule(b, "Sword", V(-0.85, 1.55, 0.95), V(0.85, 3.65, 0.95), 0.12, Color3.fromRGB(210, 215, 225), Enum.Material.Metal, true)
	capsule(b, "SwordHandle", V(0.85, 3.65, 0.95), V(1.15, 4.05, 0.95), 0.18, a, nil, true)
	arms(b, 2.1, 1.0, a, 0.65)
	return 4.3
end

-- A chocolate gelato volcano erupting strawberry lava.
designs.GelatoVulcano = function(b, c, a)
	local lava = Color3.fromRGB(255, 90, 140)
	legs(b, darker(c, 0.3), 0.45, 0.7)
	cone(b, "Mountain", V(0, 0.35, 0), 3.2, 3.4, 1.25, c, nil, nil, darker(c, 0.1))
	egg(b, "Crater", V(1.35, 0.4, 1.35), CF(0, 3.55, 0), lava, Enum.Material.Neon, true)
	for k = 0, 5 do
		local angle = rad(k * 60 + 15)
		local length = 0.8 + (k % 3) * 0.35
		local r = 0.68 + length * 0.33
		egg(b, "LavaDrip", V(0.42, length, 0.42), CF(math.cos(angle) * r, 3.35 - length / 2, math.sin(angle) * r) * ANG(math.sin(angle) * 0.35, 0, -math.cos(angle) * 0.35), lava)
	end
	for _, blob in { V(0, 4.3, 0), V(-0.4, 4.85, 0.2), V(0.35, 5.25, -0.1), V(0.05, 5.7, 0.15) } do
		ball(b, "Eruption", 0.55 - (blob.Y - 4.3) * 0.15, blob, lava, Enum.Material.Neon, true)
	end
	for _, sprinkle in { V(-0.9, 2.2, -1.0), V(0.95, 1.6, -1.15), V(-0.35, 2.85, -0.75), V(0.6, 2.55, -0.85), V(-1.2, 1.2, -1.2) } do
		egg(b, "Sprinkle", V(0.24, 0.09, 0.09), CF(sprinkle) * ANG(0, 0, sprinkle.X * 2), Color3.fromRGB(255, 230, 90), nil, true)
	end
	eyes(b, 0, 1.7, -1.22, 0.45, 0.55)
	mouth(b, 0, 1.15, -1.38, 0.55, 0.32)
	arms(b, 1.6, 1.45, c, 0.6)
	return 6.0
end

-- A panda munching bamboo.
designs.PandaBambucco = function(b, c, a)
	local bamboo = Color3.fromRGB(110, 180, 70)
	legs(b, a, 0.8, 0.6)
	egg(b, "Body", V(2.6, 2.6, 2.3), CF(0, 1.95, 0), c)
	egg(b, "Belly", V(1.7, 1.8, 0.5), CF(0, 1.85, -0.95), lighter(c, 0.4))
	ball(b, "Head", 2.15, V(0, 3.65, -0.05), c)
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.72, V(side * 0.78, 4.55, 0.1), a)
		egg(b, "EyePatch", V(0.62, 0.78, 0.22), CF(side * 0.4, 3.68, -0.92) * ANG(0, 0, side * rad(-25)), a, nil, true)
	end
	eyes(b, 0, 3.7, -1.02, 0.4, 0.38)
	egg(b, "Nose", V(0.32, 0.22, 0.2), CF(0, 3.32, -1.05), a, nil, true)
	smile(b, 0, 3.05, -1.0, 0.32)
	capsule(b, "Bamboo", V(0.95, 0.9, -1.05), V(1.25, 4.4, -1.05), 0.32, bamboo)
	for _, y in { 1.8, 2.8, 3.8 } do
		egg(b, "BambooNode", V(0.42, 0.14, 0.42), CF(0.95 + (y - 0.9) * 0.086, y, -1.05), darker(bamboo, 0.25))
	end
	for _, leaf in { -1, 1 } do
		egg(b, "BambooLeaf", V(0.18, 0.8, 0.3), CF(1.3 + leaf * 0.25, 4.6, -1.05) * ANG(0, 0, leaf * rad(-40)), bamboo)
	end
	for _, side in { -1, 1 } do
		local hand = V(if side > 0 then 1.05 else 0.95, if side > 0 then 2.9 else 2.3, -1.1)
		capsule(b, "Arm", V(side * 1.1, 2.6, -0.2), hand, 0.5, a)
		ball(b, "Paw", 0.55, hand, a)
	end
	return 4.8
end

-- A moka-pot robot with a glowing visor, steaming away.
designs.RoboMoka = function(b, c, a)
	local metal = Enum.Material.Metal
	legs(b, darker(c, 0.25), 0.8, 0.5)
	vcyl(b, "Boiler", 1.4, 1.8, V(0, 1.5, 0), c, metal)
	vcyl(b, "Waist", 0.32, 1.2, V(0, 2.32, 0), darker(c, 0.2), metal)
	cone(b, "Jug", V(0, 2.45, 0), 1.3, 1.3, 1.8, c, metal)
	egg(b, "Lid", V(1.85, 0.45, 1.85), CF(0, 3.8, 0), c, metal)
	ball(b, "Knob", 0.4, V(0, 4.05, 0), a)
	tube(b, "Handle", { V(0.85, 3.5, 0.3), V(1.45, 3.3, 0.4), V(1.35, 2.65, 0.4), V(0.85, 2.55, 0.3) }, 0.26, a)
	cone(b, "Spout", V(0, 3.15, -0.8), 0.55, 0.32, 0.12, c, metal)
	egg(b, "Visor", V(1.25, 0.55, 0.25), CF(0, 3.15, -0.85), Color3.fromRGB(20, 25, 35), Enum.Material.Glass, true)
	for _, side in { -1, 1 } do
		ball(b, "EyeLight", 0.28, V(side * 0.28, 3.17, -0.98), Color3.fromRGB(80, 230, 255), Enum.Material.Neon, true)
	end
	for _, puff in { V(0.1, 4.6, 0), V(-0.3, 5.05, 0.1), V(0.25, 5.45, 0.05) } do
		local p = ball(b, "Steam", 0.5 + (puff.Y - 4.6) * 0.35, puff, WHITE, nil, true)
		p.Transparency = 0.4
	end
	for _, side in { -1, 1 } do
		local hand = V(side * 1.55, 1.75, -0.2)
		capsule(b, "Arm", V(side * 0.95, 2.0, 0), hand, 0.26, darker(c, 0.15), metal)
		for _, finger in { -1, 1 } do
			capsule(b, "Claw", hand, hand + V(side * 0.15, -0.3, finger * 0.18), 0.12, a)
		end
	end
	return 5.6
end

-- A cool coconut with shades, a straw and a hibiscus.
designs.CoccoBello = function(b, c, a)
	legs(b, darker(c, 0.25), 0.7, 0.55)
	ball(b, "Coconut", 2.6, V(0, 2.1, 0), c)
	for k = 0, 11 do
		local angle = rad(k * 30)
		egg(b, "Fiber", V(0.08, 1.8, 0.08), CF(math.cos(angle) * 1.28, 2.0, math.sin(angle) * 1.28) * ANG(0, -angle, rad(8)), darker(c, 0.25))
	end
	egg(b, "Flesh", V(2.1, 0.35, 2.1), CF(0, 3.25, 0), a)
	egg(b, "Milk", V(1.6, 0.36, 1.6), CF(0, 3.3, 0), lighter(a, 0.3))
	tube(b, "Straw", { V(0.25, 3.2, 0.1), V(0.6, 4.2, 0.25), V(0.95, 4.45, 0.3) }, 0.14, Color3.fromRGB(240, 60, 80))
	cone(b, "Umbrella", V(-0.5, 4.0, 0.2), 0.45, 1.1, 0.06, Color3.fromRGB(80, 200, 255))
	capsule(b, "UmbrellaStick", V(-0.5, 3.25, 0.2), V(-0.5, 4.0, 0.2), 0.06, Color3.fromRGB(240, 220, 160))
	for _, side in { -1, 1 } do
		egg(b, "Shades", V(0.6, 0.4, 0.16), CF(side * 0.34, 2.45, -1.2), BLACK, Enum.Material.Glass, true)
	end
	capsule(b, "Bridge", V(-0.06, 2.5, -1.25), V(0.06, 2.5, -1.25), 0.07, BLACK, nil, true)
	smile(b, 0, 1.85, -1.25, 0.55)
	for k = 0, 4 do
		egg(b, "Petal", V(0.42, 0.12, 0.26), CF(-1.05, 2.9, -0.55) * ANG(0, 0, rad(70)) * ANG(0, rad(k * 72), 0) * CF(0.22, 0, 0), Color3.fromRGB(255, 80, 120))
	end
	ball(b, "PetalCenter", 0.16, V(-1.12, 2.9, -0.6), Color3.fromRGB(255, 220, 80), nil, true)
	arms(b, 1.9, 1.25, c, 0.7)
	return 4.8
end

-- A spaghetti dinosaur with a long noodle neck and meatballs on its back.
designs.Spaghettosauro = function(b, c, a)
	local meat = Color3.fromRGB(130, 65, 40)
	for _, leg in { V(-0.7, 0, -0.6), V(0.7, 0, -0.6), V(-0.7, 0, 1.2), V(0.7, 0, 1.2) } do
		capsule(b, "Leg", leg + V(0, 1.6, 0), leg + V(0, 0.4, 0), 0.6, c)
		egg(b, "Foot", V(0.7, 0.4, 0.85), CF(leg.X, 0.2, leg.Z - 0.15), c)
	end
	egg(b, "Body", V(2.4, 1.9, 3.3), CF(0, 2.3, 0.3), c)
	tube(b, "Neck", { V(0, 2.8, -1.0), V(0, 3.6, -1.5), V(0, 4.3, -1.75), V(0, 4.6, -2.0) }, 0.7, c)
	egg(b, "Head", V(1.05, 0.85, 1.45), CF(0, 4.75, -2.35), c)
	tube(b, "Tail", { V(0, 2.3, 1.9), V(0.2, 1.9, 2.8), V(0.5, 1.4, 3.5) }, 0.55, c)
	for _, side in { -1, 1 } do
		ball(b, "Eye", 0.36, V(side * 0.42, 4.95, -2.55), WHITE, nil, true)
		ball(b, "Pupil", 0.18, V(side * 0.48, 4.95, -2.68), BLACK, nil, true)
	end
	smile(b, 0, 4.55, -3.02, 0.35)
	egg(b, "Sauce", V(1.9, 0.5, 2.5), CF(0, 3.15, 0.3), a)
	for _, m in { V(-0.3, 3.45, -0.35), V(0.35, 3.5, 0.45), V(-0.2, 3.4, 1.15) } do
		ball(b, "Meatball", 0.65, m, meat)
	end
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			local z = -0.6 + k * 0.85
			tube(b, "Noodle", { V(side * 1.05, 2.9, z), V(side * 1.25, 2.3, z + 0.15), V(side * 1.15, 1.75, z - 0.05) }, 0.12, lighter(c, 0.1))
		end
	end
	return 5.4
end

-- A flamingo flamenco dancer in a ruffled red dress.
designs.FenicotteroFlamenco = function(b, c, a)
	capsule(b, "Leg", V(0.2, 2.5, 0.2), V(0.2, 0.35, 0.2), 0.16, darker(c, 0.15))
	egg(b, "Foot", V(0.35, 0.18, 0.6), CF(0.2, 0.1, 0.05), darker(c, 0.15))
	tube(b, "BentLeg", { V(-0.2, 2.5, 0.2), V(-0.35, 1.7, -0.25), V(-0.15, 2.0, 0.35) }, 0.16, darker(c, 0.15))
	for layer = 0, 2 do
		local y = 2.55 + layer * 0.22
		local r = 1.05 - layer * 0.2
		for k = 0, 11 do
			local angle = rad(k * 30 + layer * 15)
			egg(b, "Ruffle", V(0.55, 0.3, 0.55), CF(math.cos(angle) * r, y, 0.2 + math.sin(angle) * r), if layer % 2 == 0 then a else darker(a, 0.2))
		end
	end
	egg(b, "Body", V(1.6, 1.7, 2.1), CF(0, 3.25, 0.2), c)
	for _, side in { -1, 1 } do
		egg(b, "Wing", V(0.4, 1.2, 1.5), CF(side * 0.85, 3.4, 0.35) * ANG(0, 0, side * rad(-15)), darker(c, 0.1))
	end
	tube(b, "Neck", { V(0, 3.8, -0.6), V(0, 4.3, -0.35), V(0, 4.8, -0.65), V(0, 5.25, -0.9) }, 0.35, c)
	ball(b, "Head", 0.85, V(0, 5.4, -0.95), c)
	tube(b, "Beak", { V(0, 5.35, -1.3), V(0, 5.2, -1.55), V(0, 4.95, -1.65) }, 0.22, WHITE)
	ball(b, "BeakTip", 0.22, V(0, 4.92, -1.66), BLACK)
	for _, side in { -1, 1 } do
		ball(b, "Eye", 0.24, V(side * 0.36, 5.5, -1.05), WHITE, nil, true)
		ball(b, "Pupil", 0.12, V(side * 0.41, 5.5, -1.14), BLACK, nil, true)
	end
	for k = 0, 4 do
		egg(b, "RosePetal", V(0.2, 0.2, 0.12), CF(-0.25, 5.75, -0.85) * ANG(0, rad(k * 72), 0) * CF(0.1, 0, 0), a)
	end
	return 6.0
end

-- A wise owl professor in a graduation cap, book in wing.
designs.GufoProfessore = function(b, c, a)
	local orange = Color3.fromRGB(255, 170, 50)
	for _, side in { -1, 1 } do
		egg(b, "Foot", V(0.5, 0.25, 0.65), CF(side * 0.45, 0.13, -0.3), orange)
	end
	egg(b, "Body", V(2.4, 3.0, 2.2), CF(0, 2.0, 0), c)
	egg(b, "Belly", V(1.6, 2.0, 0.5), CF(0, 1.75, -0.85), a)
	for row = 0, 2 do
		for k = -1, 1 do
			egg(b, "Chevron", V(0.3, 0.12, 0.1), CF(k * 0.38, 1.2 + row * 0.42, -1.08), darker(a, 0.25), nil, true)
		end
	end
	for _, side in { -1, 1 } do
		egg(b, "Wing", V(0.45, 1.8, 1.5), CF(side * 1.15, 2.1, 0.1) * ANG(0, 0, side * rad(-8)), darker(c, 0.15))
		cone(b, "EarTuft", V(side * 0.75, 3.25, 0), 0.75, 0.45, 0.08, darker(c, 0.15))
		zcyl(b, "EyeRing", 0.1, 1.0, V(side * 0.42, 2.75, -0.92), orange, nil, true)
		zcyl(b, "Glasses", 0.06, 1.1, V(side * 0.42, 2.75, -1.03), Color3.fromRGB(60, 40, 30), nil, true)
	end
	eyes(b, 0, 2.75, -0.98, 0.42, 0.72)
	egg(b, "Beak", V(0.3, 0.45, 0.3), CF(0, 2.3, -1.08), orange)
	-- Graduation cap
	vcyl(b, "CapBase", 0.45, 1.4, V(0, 3.6, 0), BLACK)
	box(b, "CapBoard", V(2.0, 0.12, 2.0), CF(0, 3.88, 0) * ANG(0, rad(45), 0), BLACK)
	tube(b, "Tassel", { V(0, 3.98, 0), V(0.75, 3.95, -0.75), V(0.78, 3.4, -0.78) }, 0.07, Color3.fromRGB(255, 210, 60))
	ball(b, "TasselEnd", 0.2, V(0.78, 3.35, -0.78), Color3.fromRGB(255, 210, 60))
	box(b, "Book", V(0.25, 1.1, 0.85), CF(-1.35, 1.6, -0.5) * ANG(0, rad(-20), 0), Color3.fromRGB(180, 40, 50))
	return 5.2
end

-- A lion whose mane is ruffled lasagna noodles.
designs.LeoneLasagnone = function(b, c, a)
	local fur = Color3.fromRGB(235, 170, 80)
	for _, leg in { V(-0.65, 0, -0.5), V(0.65, 0, -0.5), V(-0.65, 0, 0.9), V(0.65, 0, 0.9) } do
		capsule(b, "Leg", leg + V(0, 1.4, 0), leg + V(0, 0.4, 0), 0.55, fur)
		egg(b, "Paw", V(0.65, 0.4, 0.75), CF(leg.X, 0.2, leg.Z - 0.1), fur)
	end
	-- The body: lasagna layers
	for i, color in { c, a, Color3.fromRGB(255, 240, 200), c } do
		box(b, "Layer", V(2.2, 0.38, 2.4), CF(0, 1.55 + (i - 1) * 0.36, 0.25), color)
	end
	tube(b, "Tail", { V(0, 2.3, 1.45), V(0.3, 2.9, 2.0), V(0.2, 3.3, 2.3) }, 0.22, fur)
	ball(b, "TailTuft", 0.55, V(0.2, 3.45, 2.35), a)
	-- Mane: wavy noodle ruffles around the face
	local headCenter = V(0, 3.55, -0.95)
	for k = 0, 13 do
		local angle = rad(k * 360 / 14)
		egg(b, "Mane", V(0.75, 0.75, 0.4), CF(headCenter + V(math.cos(angle) * 1.15, math.sin(angle) * 1.15, 0.2)) * ANG(0, 0, angle), if k % 2 == 0 then c else lighter(c, 0.15))
	end
	ball(b, "Head", 1.9, headCenter, fur)
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.55, headCenter + V(side * 0.75, 0.8, 0.1), fur)
	end
	egg(b, "Muzzle", V(1.0, 0.65, 0.45), CF(headCenter + V(0, -0.35, -0.8)), lighter(fur, 0.45))
	egg(b, "Nose", V(0.38, 0.25, 0.2), CF(headCenter + V(0, -0.15, -1.0)), Color3.fromRGB(90, 50, 40), nil, true)
	eyes(b, 0, headCenter.Y + 0.25, headCenter.Z - 0.85, 0.38, 0.45, true)
	smile(b, 0, headCenter.Y - 0.5, headCenter.Z - 0.98, 0.4)
	for _, sauce in { V(-0.6, 3.05, -0.4), V(0.7, 3.0, 0.6), V(0, 3.05, 1.1) } do
		egg(b, "Sauce", V(0.6, 0.18, 0.5), CF(sauce), a)
	end
	return 4.8
end

-- A shark strutting on three legs in fresh sneakers.
designs.SqualoScarpone = function(b, c, a)
	local shoe = WHITE
	local swoosh = Color3.fromRGB(40, 120, 255)
	for _, leg in { V(-0.55, 0, -0.6), V(0.55, 0, -0.6), V(0, 0, 0.9) } do
		capsule(b, "Leg", leg + V(0, 2.0, 0), leg + V(0, 0.45, 0), 0.36, c)
		egg(b, "Sneaker", V(0.55, 0.42, 1.0), CF(leg.X, 0.21, leg.Z - 0.2), shoe)
		egg(b, "Sole", V(0.58, 0.14, 1.04), CF(leg.X, 0.06, leg.Z - 0.2), Color3.fromRGB(40, 40, 45))
		egg(b, "Swoosh", V(0.6, 0.12, 0.45), CF(leg.X, 0.25, leg.Z - 0.1) * ANG(rad(-20), 0, 0), swoosh, nil, true)
	end
	egg(b, "Body", V(1.85, 1.9, 4.3), CF(0, 2.75, 0), c)
	egg(b, "Belly", V(1.5, 1.3, 3.6), CF(0, 2.45, -0.15), a)
	egg(b, "DorsalFin", V(0.25, 1.5, 1.1), CF(0, 3.85, 0.35) * ANG(rad(-25), 0, 0), c)
	for _, side in { -1, 1 } do
		egg(b, "TailFin", V(0.2, 1.1, 0.6), CF(0, 2.85 + side * 0.4, 2.55) * ANG(rad(side * 62), 0, 0), c)
		egg(b, "SideFin", V(1.1, 0.18, 0.7), CF(side * 1.0, 2.4, -0.4) * ANG(0, side * rad(-20), side * rad(-30)), c)
		ball(b, "Eye", 0.42, V(side * 0.72, 3.05, -1.45), WHITE, nil, true)
		ball(b, "Pupil", 0.22, V(side * 0.86, 3.05, -1.52), BLACK, nil, true)
	end
	egg(b, "Mouth", V(1.0, 0.4, 0.3), CF(0, 2.5, -1.95), Color3.fromRGB(70, 20, 25), nil, true)
	for k = -2, 2 do
		cone(b, "Tooth", V(k * 0.18, 2.55, -2.05), 0.22, 0.14, 0.03, WHITE, nil, true)
	end
	return 4.0
end

-- A crab knight: armored shell, plume and huge claws.
designs.GranchioCorazzato = function(b, c, a)
	local metal = Enum.Material.Metal
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			local z = -0.5 + k * 0.6
			tube(b, "Leg", { V(side * 1.2, 1.6, z), V(side * 2.0, 1.3, z), V(side * 2.3, 0.15, z + 0.1) }, 0.22, c)
		end
	end
	egg(b, "Body", V(3.2, 1.5, 2.4), CF(0, 1.9, 0), c)
	egg(b, "Armor", V(2.9, 0.85, 2.1), CF(0, 2.45, 0.05), a, metal)
	egg(b, "ArmorRidge", V(0.3, 0.35, 2.0), CF(0, 2.85, 0.05), lighter(a, 0.2), metal)
	for k = 0, 4 do
		capsule(b, "Plume", V(0, 2.95, 0.3), V((k - 2) * 0.22, 3.75 + math.abs(k - 2) * -0.15, 0.6 + k * 0.05), 0.18, Color3.fromRGB(230, 40, 60))
	end
	for _, side in { -1, 1 } do
		capsule(b, "Stalk", V(side * 0.4, 2.3, -0.9), V(side * 0.5, 2.95, -1.0), 0.14, c)
		ball(b, "Eye", 0.42, V(side * 0.5, 3.05, -1.02), WHITE, nil, true)
		ball(b, "Pupil", 0.2, V(side * 0.5, 3.05, -1.22), BLACK, nil, true)
		local wrist = V(side * 2.05, 2.3, -1.2)
		tube(b, "Arm", { V(side * 1.4, 1.95, -0.6), V(side * 1.9, 2.1, -0.95), wrist }, 0.36, c)
		egg(b, "ClawTop", V(0.7, 0.45, 1.25), CF(wrist + V(side * 0.1, 0.25, -0.6)) * ANG(rad(-15), 0, 0), c)
		egg(b, "ClawBottom", V(0.55, 0.35, 1.0), CF(wrist + V(side * 0.1, -0.2, -0.5)) * ANG(rad(15), 0, 0), c)
	end
	smile(b, 0, 1.75, -1.15, 0.45)
	return 3.9
end

-- A rainbow unicorn with a golden horn.
designs.UnicorninoArcobaleno = function(b, c, a)
	local gold = Color3.fromRGB(255, 205, 70)
	local rainbow = { Color3.fromRGB(255, 90, 110), Color3.fromRGB(255, 170, 70), Color3.fromRGB(255, 230, 90), Color3.fromRGB(110, 220, 120), Color3.fromRGB(90, 170, 255), Color3.fromRGB(180, 120, 255) }
	for _, leg in { V(-0.5, 0, -0.75), V(0.5, 0, -0.75), V(-0.5, 0, 1.0), V(0.5, 0, 1.0) } do
		capsule(b, "Leg", leg + V(0, 1.7, 0), leg + V(0, 0.4, 0), 0.42, c)
		egg(b, "Hoof", V(0.45, 0.3, 0.5), CF(leg.X, 0.15, leg.Z), gold, Enum.Material.Foil)
	end
	egg(b, "Body", V(1.8, 1.7, 3.0), CF(0, 2.45, 0.15), c)
	tube(b, "Neck", { V(0, 2.9, -1.0), V(0, 3.5, -1.3) }, 0.85, c)
	egg(b, "Head", V(1.05, 1.15, 1.55), CF(0, 3.95, -1.45) * ANG(rad(-15), 0, 0), c)
	egg(b, "Snout", V(0.85, 0.7, 0.7), CF(0, 3.6, -2.05), lighter(a, 0.6))
	cone(b, "Horn", V(0, 4.4, -1.6), 1.0, 0.32, 0.04, gold, Enum.Material.Foil, nil, lighter(gold, 0.35))
	for _, side in { -1, 1 } do
		cone(b, "Ear", V(side * 0.32, 4.35, -1.25), 0.4, 0.28, 0.05, c)
		ball(b, "Eye", 0.32, V(side * 0.42, 4.05, -1.95), BLACK, nil, true)
		ball(b, "Shine", 0.1, V(side * 0.42 - 0.05, 4.12, -2.08), WHITE, Enum.Material.Neon, true)
	end
	blush(b, 0, 3.75, -2.02, 0.42, 0.26)
	for i = 0, 7 do
		local t = i / 7
		ball(b, "Mane", 0.5, V(0, 4.45 - t * 1.6, -1.15 + t * 1.0), rainbow[i % #rainbow + 1])
	end
	for i = 0, 6 do
		local t = i / 6
		ball(b, "Tail", 0.55 - t * 0.15, V(math.sin(t * 3) * 0.2, 2.6 - t * 1.0, 1.75 + t * 0.6), rainbow[i % #rainbow + 1])
	end
	return 5.0
end

-- A penguin pilot: leather cap, goggles, scarf and little plane wings.
designs.PinguinoPilota = function(b, c, a)
	local orange = Color3.fromRGB(255, 150, 40)
	local leather = Color3.fromRGB(130, 80, 45)
	for _, side in { -1, 1 } do
		egg(b, "Foot", V(0.75, 0.28, 1.1), CF(side * 0.5, 0.14, -0.3), orange)
	end
	egg(b, "Body", V(2.4, 3.2, 2.2), CF(0, 1.85, 0), c)
	egg(b, "Belly", V(1.8, 2.4, 0.6), CF(0, 1.75, -0.85), a)
	egg(b, "Head", V(1.8, 1.6, 1.7), CF(0, 3.75, 0), c)
	egg(b, "Face", V(1.3, 1.0, 0.3), CF(0, 3.65, -0.75), a)
	egg(b, "Cap", V(1.9, 0.95, 1.8), CF(0, 4.1, 0.05), leather)
	for _, side in { -1, 1 } do
		egg(b, "EarFlap", V(0.3, 0.7, 0.5), CF(side * 0.88, 3.7, 0.05), leather)
		zcyl(b, "GoggleRim", 0.18, 0.6, V(side * 0.32, 4.25, -0.7), Color3.fromRGB(180, 150, 90), Enum.Material.Metal, true)
		zcyl(b, "GoggleGlass", 0.2, 0.45, V(side * 0.32, 4.25, -0.72), Color3.fromRGB(120, 200, 255), Enum.Material.Glass, true)
	end
	eyes(b, 0, 3.75, -0.82, 0.3, 0.38)
	egg(b, "Beak", V(0.55, 0.3, 0.6), CF(0, 3.42, -0.98) * ANG(rad(-10), 0, 0), orange)
	egg(b, "Scarf", V(1.85, 0.4, 1.75), CF(0, 3.1, 0), Color3.fromRGB(230, 40, 50))
	tube(b, "ScarfTail", { V(0.3, 3.1, 0.8), V(0.7, 3.0, 1.4), V(1.2, 3.2, 1.8) }, 0.35, Color3.fromRGB(230, 40, 50))
	for _, side in { -1, 1 } do
		box(b, "Wing", V(1.9, 0.16, 0.9), CF(side * 1.95, 2.3, 0.1) * ANG(0, 0, side * rad(8)), Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
		egg(b, "WingTip", V(0.5, 0.2, 0.92), CF(side * 2.85, 2.42, 0.1), Color3.fromRGB(230, 40, 50))
	end
	for k = 0, 1 do
		egg(b, "Propeller", V(1.3, 0.08, 0.2), CF(0, 4.62, 0.05) * ANG(0, rad(k * 90 + 20), 0), Color3.fromRGB(120, 120, 130), Enum.Material.Metal)
	end
	ball(b, "PropHub", 0.25, V(0, 4.64, 0.05), Color3.fromRGB(230, 40, 50))
	return 4.9
end

-- An octopus in a top hat playing a little grand piano.
designs.PolipoPianista = function(b, c, a)
	-- Piano in front (black with white and black keys)
	box(b, "Piano", V(3.0, 0.9, 1.3), CF(0, 1.75, -1.35), a)
	for _, x in { -1.2, 1.2 } do
		capsule(b, "PianoLeg", V(x, 1.3, -1.6), V(x, 0.15, -1.6), 0.18, a)
	end
	box(b, "Keys", V(2.6, 0.14, 0.5), CF(0, 2.24, -1.82), WHITE, nil, true)
	for k = -5, 5 do
		if k % 3 ~= 0 then
			egg(b, "BlackKey", V(0.12, 0.12, 0.28), CF(k * 0.22, 2.33, -1.72), BLACK, nil, true)
		end
	end
	egg(b, "Head", V(2.4, 2.4, 2.2), CF(0, 3.55, 0.45), c)
	for k = 0, 7 do
		local angle = rad(k * 45)
		local base = V(math.cos(angle) * 0.8, 2.5, 0.45 + math.sin(angle) * 0.8)
		if k == 5 or k == 6 then
			-- These two play the keys
			tube(b, "Tentacle", { base, V(base.X * 1.4, 2.6, -0.6), V(base.X * 0.9, 2.42, -1.7) }, 0.38, c)
		else
			tube(b, "Tentacle", { base, base + V(math.cos(angle) * 0.6, -1.2, math.sin(angle) * 0.6), base + V(math.cos(angle) * 1.1, -2.2, math.sin(angle) * 1.1) }, 0.36, c)
		end
	end
	eyes(b, 0, 3.75, -0.6, 0.45, 0.55)
	smile(b, 0, 3.1, -0.62, 0.45)
	egg(b, "HatBrim", V(1.7, 0.16, 1.6), CF(0, 4.7, 0.45) * ANG(0, 0, rad(-8)), BLACK)
	vcyl(b, "TopHat", 1.0, 1.1, V(-0.07, 5.25, 0.45), BLACK)
	vcyl(b, "HatBand", 0.2, 1.13, V(-0.05, 4.88, 0.45), Color3.fromRGB(200, 40, 60))
	return 5.8
end

-- A tiger made of tiramisu: cream and ladyfinger layers, cocoa stripes.
designs.TigreTiramisu = function(b, c, a)
	local sponge = Color3.fromRGB(215, 160, 90)
	for _, leg in { V(-0.6, 0, -0.55), V(0.6, 0, -0.55), V(-0.6, 0, 0.95), V(0.6, 0, 0.95) } do
		capsule(b, "Leg", leg + V(0, 1.4, 0), leg + V(0, 0.4, 0), 0.55, c)
		egg(b, "Paw", V(0.62, 0.38, 0.72), CF(leg.X, 0.19, leg.Z - 0.1), c)
		egg(b, "LegStripe", V(0.6, 0.12, 0.6), CF(leg.X, 0.95, leg.Z), a)
	end
	for i, color in { sponge, c, sponge, c } do
		box(b, "Layer", V(2.1, 0.4, 2.5), CF(0, 1.55 + (i - 1) * 0.38, 0.2), color)
	end
	egg(b, "Cocoa", V(2.0, 0.2, 2.4), CF(0, 3.0, 0.2), a)
	tube(b, "Tail", { V(0, 2.4, 1.45), V(0.4, 2.9, 1.9), V(0.3, 3.5, 2.1) }, 0.3, c)
	for k = 0, 2 do
		egg(b, "TailStripe", V(0.36, 0.12, 0.36), CF(0.1 + k * 0.12, 2.55 + k * 0.35, 1.6 + k * 0.17), a)
	end
	local head = V(0, 3.6, -1.0)
	ball(b, "Head", 1.9, head, c)
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.55, head + V(side * 0.72, 0.8, 0.15), c)
		ball(b, "EarInner", 0.3, head + V(side * 0.72, 0.8, -0.05), Color3.fromRGB(255, 170, 170))
		for k = 0, 1 do
			egg(b, "FaceStripe", V(0.45, 0.1, 0.12), CF(head + V(side * 0.75, 0.25 - k * 0.3, -0.62)) * ANG(0, side * rad(40), side * rad(-15)), a, nil, true)
		end
		for k = -1, 1 do
			capsule(b, "Whisker", head + V(side * 0.35, -0.35 + k * 0.1, -0.88), head + V(side * 1.05, -0.3 + k * 0.18, -0.82), 0.04, BLACK, nil, true)
		end
	end
	for k = -1, 1 do
		egg(b, "HeadStripe", V(0.12, 0.45, 0.1), CF(head + V(k * 0.28, 0.7, -0.6)), a, nil, true)
	end
	egg(b, "Muzzle", V(0.95, 0.6, 0.4), CF(head + V(0, -0.35, -0.82)), lighter(c, 0.5))
	egg(b, "Nose", V(0.32, 0.22, 0.18), CF(head + V(0, -0.15, -1.0)), Color3.fromRGB(255, 120, 150), nil, true)
	eyes(b, 0, head.Y + 0.25, head.Z - 0.85, 0.36, 0.42)
	smile(b, 0, head.Y - 0.48, head.Z - 0.96, 0.36)
	return 4.8
end

-- A phoenix of golden focaccia with blazing wings.
designs.FeniceFocaccia = function(b, c, a)
	local flame = { a, Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 230, 90) }
	for _, side in { -1, 1 } do
		tube(b, "Leg", { V(side * 0.35, 1.7, 0), V(side * 0.4, 0.9, -0.1), V(side * 0.4, 0.3, -0.2) }, 0.2, Color3.fromRGB(255, 170, 40))
		egg(b, "Talon", V(0.5, 0.2, 0.6), CF(side * 0.4, 0.12, -0.35), Color3.fromRGB(255, 170, 40))
	end
	egg(b, "Body", V(2.0, 2.3, 2.2), CF(0, 2.55, 0.1), c)
	for _, olive in { V(-0.5, 2.9, -0.98), V(0.55, 2.4, -1.0), V(0.1, 2.0, -1.05), V(-0.6, 2.1, -0.9) } do
		egg(b, "Olive", V(0.28, 0.24, 0.16), CF(olive), Color3.fromRGB(60, 50, 40), nil, true)
	end
	for _, sprig in { { V(0.2, 3.1, -0.95), V(0.65, 3.3, -0.8) }, { V(-0.2, 1.75, -0.95), V(-0.65, 1.95, -0.8) } } do
		capsule(b, "Rosemary", sprig[1], sprig[2], 0.08, Color3.fromRGB(60, 140, 60), nil, true)
	end
	-- Wings: fans of flame feathers
	for _, side in { -1, 1 } do
		for k = 0, 4 do
			local angle = rad(10 + k * 22)
			local length = 2.4 - math.abs(k - 2) * 0.3
			local root = V(side * 0.85, 3.0, 0.3)
			egg(b, "Feather", V(length, 0.5, 0.25), CF(root) * ANG(0, 0, side * angle) * CF(side * length / 2, 0, 0), flame[k % 3 + 1], Enum.Material.Neon, true)
		end
	end
	for k = -1, 1 do
		egg(b, "TailFeather", V(0.4, 1.8, 0.25), CF(k * 0.35, 1.6, 1.25) * ANG(rad(40), 0, k * rad(-15)), flame[(k + 1) % 3 + 1], Enum.Material.Neon, true)
	end
	local head = V(0, 4.2, -0.35)
	ball(b, "Head", 1.35, head, c)
	for k = -1, 1 do
		egg(b, "Crest", V(0.25, 1.0, 0.25), CF(head + V(k * 0.22, 0.8, 0.25)) * ANG(rad(-25), 0, k * rad(-20)), flame[k + 2], Enum.Material.Neon, true)
	end
	cone(b, "Beak", head + V(0, -0.4, -0.75), 0.35, 0.3, 0.05, Color3.fromRGB(255, 170, 40))
	eyes(b, 0, head.Y + 0.1, head.Z - 0.58, 0.3, 0.38, true)
	return 5.4
end

-- A kraken made of carbonara: creamy noodle tentacles, bacon and a yolk crown.
designs.KrakenCarbonara = function(b, c, a)
	local pepper = Color3.fromRGB(40, 35, 30)
	for k = 0, 5 do
		local angle = rad(k * 60 + 30)
		local dir = V(math.cos(angle), 0, math.sin(angle))
		local base = V(0, 2.2, 0) + dir * 1.0
		tube(b, "Tentacle", { base, base + dir * 0.9 + V(0, -1.4, 0), base + dir * 1.8 + V(0, -1.8, 0), base + dir * 2.3 + V(0, -1.2, 0), base + dir * 2.2 + V(0, -0.6, 0) }, 0.45, c)
		ball(b, "Pepper", 0.12, base + dir * 1.8 + V(0, -1.55, 0), pepper, nil, true)
	end
	egg(b, "Head", V(3.0, 3.2, 2.8), CF(0, 3.6, 0.1), c)
	for _, bit in { V(-0.9, 4.3, -1.05), V(0.8, 3.9, -1.15), V(-0.3, 4.9, -0.8), V(1.0, 4.7, -0.7), V(-1.15, 3.3, -0.95) } do
		box(b, "Bacon", V(0.5, 0.22, 0.2), CF(bit) * ANG(0, 0, bit.X), a)
	end
	for _, dot in { V(0.3, 4.5, -1.15), V(-0.6, 3.75, -1.25), V(0.55, 3.2, -1.3), V(-0.1, 5.1, -0.7) } do
		ball(b, "Pepper", 0.12, dot, pepper, nil, true)
	end
	ball(b, "Yolk", 1.0, V(0, 5.25, 0.15), Color3.fromRGB(255, 200, 40))
	egg(b, "YolkShine", V(0.3, 0.18, 0.1), CF(-0.2, 5.5, -0.25), WHITE, Enum.Material.Neon, true)
	eyes(b, 0, 3.95, -1.25, 0.5, 0.65, true)
	egg(b, "Mouth", V(1.3, 0.45, 0.3), CF(0, 3.05, -1.3), Color3.fromRGB(70, 20, 25), nil, true)
	for k = -2, 2 do
		cone(b, "Fang", V(k * 0.24, 2.92, -1.42), 0.28, 0.16, 0.03, WHITE, nil, true)
	end
	return 5.9
end

-- A golem carved from blue-veined gorgonzola, glowing eyes.
designs.GolemGorgonzola = function(b, c, a)
	local vein = a
	for _, side in { -1, 1 } do
		capsule(b, "Leg", V(side * 0.6, 1.5, 0), V(side * 0.6, 0.5, 0), 1.0, c)
		egg(b, "Foot", V(1.05, 0.5, 1.25), CF(side * 0.6, 0.25, -0.1), darker(c, 0.08))
	end
	box(b, "Torso", V(2.6, 2.2, 1.7), CF(0, 2.6, 0), c)
	box(b, "Head", V(1.5, 1.2, 1.3), CF(0, 4.25, -0.05), c)
	for _, side in { -1, 1 } do
		ball(b, "Shoulder", 1.15, V(side * 1.6, 3.25, 0), c)
		capsule(b, "Arm", V(side * 1.7, 3.0, 0), V(side * 1.85, 1.6, -0.1), 0.85, c)
		ball(b, "Fist", 1.0, V(side * 1.88, 1.15, -0.1), c)
		ball(b, "Eye", 0.32, V(side * 0.33, 4.35, -0.72), Color3.fromRGB(90, 200, 255), Enum.Material.Neon, true)
	end
	-- Blue veins over the front
	for _, path in {
		{ V(-1.1, 3.4, -0.87), V(-0.5, 3.0, -0.87), V(-0.6, 2.4, -0.87), V(0.1, 2.0, -0.87) },
		{ V(0.9, 3.5, -0.87), V(0.5, 2.9, -0.87), V(0.95, 2.2, -0.87) },
		{ V(-0.5, 4.7, -0.67), V(0.0, 4.55, -0.67), V(0.4, 4.75, -0.67) },
		{ V(-1.85, 2.6, -0.48), V(-1.7, 2.0, -0.48) },
	} do
		tube(b, "Vein", path, 0.1, vein)
	end
	for _, hole in { V(0.4, 3.35, -0.86), V(-0.8, 2.2, -0.86), V(0.75, 1.85, -0.86) } do
		egg(b, "Hole", V(0.3, 0.3, 0.1), CF(hole), darker(c, 0.2), nil, true)
	end
	egg(b, "Mouth", V(0.6, 0.12, 0.08), CF(0, 3.95, -0.7), darker(c, 0.5), nil, true)
	return 5.0
end

-- A three-headed calzone hound.
designs.CerberoCalzone = function(b, c, a)
	local spike = Color3.fromRGB(150, 150, 160)
	for _, leg in { V(-0.7, 0, -0.6), V(0.7, 0, -0.6), V(-0.7, 0, 1.0), V(0.7, 0, 1.0) } do
		capsule(b, "Leg", leg + V(0, 1.4, 0), leg + V(0, 0.4, 0), 0.5, c)
		egg(b, "Paw", V(0.6, 0.38, 0.7), CF(leg.X, 0.19, leg.Z - 0.1), c)
	end
	egg(b, "Calzone", V(2.4, 1.9, 3.0), CF(0, 2.2, 0.2), c)
	for k = 0, 10 do
		local t = k / 10
		ball(b, "Crimp", 0.38, V(0, 3.12 - math.sin(t * math.pi) * 0.05, -1.25 + t * 2.9), darker(c, 0.1))
	end
	for _, burn in { V(0.7, 2.6, -0.4), V(-0.75, 2.2, 0.8), V(0.65, 1.8, 0.9) } do
		egg(b, "Char", V(0.3, 0.2, 0.3), CF(burn), darker(c, 0.35), nil, true)
	end
	egg(b, "Collar", V(1.6, 0.35, 1.3), CF(0, 2.9, -0.95), Color3.fromRGB(40, 40, 45))
	for k = -2, 2 do
		cone(b, "Spike", V(k * 0.32, 3.05, -1.55 + math.abs(k) * 0.12), 0.3, 0.16, 0.03, spike, Enum.Material.Metal)
	end
	for k = -1, 1 do
		local head = V(k * 0.95, 3.75 - math.abs(k) * 0.2, -1.2 - (1 - math.abs(k)) * 0.15)
		capsule(b, "Neck", V(k * 0.35, 2.9, -0.9), head, 0.55, c)
		ball(b, "Head", 1.05, head, c)
		egg(b, "Snout", V(0.55, 0.42, 0.55), CF(head + V(0, -0.15, -0.5)), lighter(c, 0.15))
		ball(b, "Nose", 0.18, head + V(0, -0.05, -0.78), BLACK, nil, true)
		for _, side in { -1, 1 } do
			egg(b, "Ear", V(0.22, 0.55, 0.32), CF(head + V(side * 0.35, 0.5, 0.05)) * ANG(0, 0, side * rad(-20)), darker(c, 0.25))
			ball(b, "Eye", 0.24, head + V(side * 0.2, 0.15, -0.44), Color3.fromRGB(255, 70, 40), Enum.Material.Neon, true)
		end
		egg(b, "Sauce", V(0.3, 0.2, 0.15), CF(head + V(0.1, -0.38, -0.62)), a, nil, true)
	end
	tube(b, "Tail", { V(0, 2.5, 1.65), V(0.2, 3.0, 2.1), V(0.1, 3.4, 2.3) }, 0.3, c)
	return 4.7
end

-- A linguine sea serpent rising from a pool of sauce.
designs.LeviatanoLinguine = function(b, c, a)
	local sauce = Color3.fromRGB(200, 45, 35)
	egg(b, "Pool", V(4.6, 0.3, 4.6), CF(0, 0.15, 0.3), sauce)
	local body = {}
	for i = 0, 8 do
		local t = i / 8
		table.insert(body, V(math.sin(t * 2.2) * 0.5, 0.4 + math.sin(t * math.pi * 1.6) * 1.0 + t * 2.4, 1.8 - t * 3.0))
	end
	tube(b, "Body", body, 1.0, c)
	for i = 2, 7 do
		local p = body[i]
		egg(b, "Fin", V(0.15, 0.7, 0.6), CF(p + V(0, 0.55, 0.1)) * ANG(rad(-30), 0, 0), lighter(c, 0.25))
	end
	local head = body[#body] + V(0, 0.6, -0.4)
	egg(b, "Head", V(1.5, 1.2, 1.9), CF(head), c)
	egg(b, "Jaw", V(1.2, 0.45, 1.4), CF(head + V(0, -0.5, -0.35)), darker(c, 0.15))
	for _, side in { -1, 1 } do
		cone(b, "Horn", head + V(side * 0.4, 0.45, 0.35), 0.8, 0.3, 0.05, lighter(c, 0.4))
		egg(b, "Frill", V(0.15, 1.1, 0.9), CF(head + V(side * 0.75, 0.1, 0.3)) * ANG(0, 0, side * rad(-35)), lighter(c, 0.25))
	end
	eyes(b, head.X, head.Y + 0.15, head.Z - 0.85, 0.36, 0.42, true)
	for k = -2, 2 do
		tube(b, "Linguine", { head + V(k * 0.18, -0.65, -0.75), head + V(k * 0.22, -1.25, -0.85), head + V(k * 0.2, -1.7, -0.7) }, 0.12, a)
	end
	return 6.2
end

-- The ravioli king: crown, ermine cape and a golden scepter.
designs.ReRavioliSupremo = function(b, c, a)
	local gold = Color3.fromRGB(255, 200, 50)
	legs(b, darker(c, 0.3), 0.9, 0.55)
	-- Royal cape behind the ravioli
	box(b, "Cape", V(3.0, 3.2, 0.2), CF(0, 2.6, 0.55) * ANG(rad(6), 0, 0), a)
	for k = 0, 8 do
		ball(b, "Ermine", 0.36, V(-1.4 + k * 0.35, 1.05, 0.72), WHITE)
	end
	box(b, "Ravioli", V(2.8, 2.8, 0.7), CF(0, 2.65, 0), c)
	for k = 0, 6 do
		local t = k / 6
		for _, edge in { V(-1.42 + t * 2.84, 4.08, 0), V(-1.42 + t * 2.84, 1.22, 0), V(-1.42, 1.22 + t * 2.86, 0), V(1.42, 1.22 + t * 2.86, 0) } do
			ball(b, "Crimp", 0.3, edge, darker(c, 0.08))
		end
	end
	egg(b, "Filling", V(1.9, 1.9, 0.3), CF(0, 2.65, -0.3), lighter(c, 0.2))
	eyes(b, 0, 2.95, -0.48, 0.42, 0.5)
	smile(b, 0, 2.35, -0.47, 0.5)
	blush(b, 0, 2.55, -0.45, 0.78)
	-- Crown
	vcyl(b, "CrownBand", 0.45, 1.6, V(0, 4.5, 0), gold, Enum.Material.Foil, true)
	for k = 0, 4 do
		local angle = rad(k * 72)
		cone(b, "CrownPoint", V(math.cos(angle) * 0.62, 4.7, math.sin(angle) * 0.62), 0.6, 0.38, 0.06, gold, Enum.Material.Foil, true)
		ball(b, "CrownGem", 0.2, V(math.cos(angle) * 0.82, 4.52, math.sin(angle) * 0.82), if k % 2 == 0 then Color3.fromRGB(230, 40, 60) else Color3.fromRGB(80, 160, 255), Enum.Material.Neon, true)
	end
	-- Scepter
	capsule(b, "Scepter", V(1.75, 1.3, -0.4), V(1.95, 4.0, -0.4), 0.16, gold, Enum.Material.Foil, true)
	ball(b, "ScepterOrb", 0.55, V(1.97, 4.25, -0.4), a, Enum.Material.Neon, true)
	arms(b, 2.4, 1.45, c, 0.5)
	return 5.6
end

-- A ghost of fettuccine ribbons, glowing eyes, drifting above the ground.
designs.FantasmaFettuccine = function(b, c, a)
	local glow = Color3.fromRGB(110, 240, 255)
	local body = egg(b, "Ghost", V(2.4, 2.8, 2.2), CF(0, 3.3, 0), c)
	body.Transparency = 0.2
	for k = 0, 9 do
		local angle = rad(k * 36)
		local r = 0.95
		local length = 1.4 + (k % 3) * 0.35
		local ribbon = egg(b, "Ribbon", V(0.42, length, 0.12), CF(math.cos(angle) * r, 2.0 - length * 0.3, math.sin(angle) * r) * ANG(0, -angle + rad(90), rad(math.sin(k) * 15)), a)
		ribbon.Transparency = 0.15
	end
	for _, side in { -1, 1 } do
		egg(b, "Eye", V(0.45, 0.6, 0.2), CF(side * 0.42, 3.55, -1.02), glow, Enum.Material.Neon, true)
		local arm = egg(b, "Arm", V(1.2, 0.45, 0.45), CF(side * 1.3, 3.2, -0.2) * ANG(0, 0, side * rad(25)), c)
		arm.Transparency = 0.2
	end
	egg(b, "Mouth", V(0.55, 0.65, 0.2), CF(0, 2.85, -1.0), Color3.fromRGB(30, 40, 60), nil, true)
	for k = 0, 2 do
		local wisp = ball(b, "Wisp", 0.3 - k * 0.06, V(-0.6 + k * 0.6, 4.95 + k * 0.25, 0.3), glow, Enum.Material.Neon, true)
		wisp.Transparency = 0.3
	end
	return 5.3
end

-- A galaxy gnocchi with a glowing ring and little gnocchi planets.
designs.GalassiaGnocchi = function(b, c, a)
	local starWhite = Color3.fromRGB(255, 255, 255)
	egg(b, "Gnocchi", V(2.8, 2.6, 2.4), CF(0, 2.9, 0), c, Enum.Material.Glass)
	for _, y in { 2.2, 2.75, 3.3, 3.85 } do
		local k = math.sqrt(math.max(0, 1 - ((y - 2.9) / 1.3) ^ 2))
		egg(b, "Ridge", V(2.85 * k, 0.12, 2.45 * k), CF(0, y, 0), lighter(c, 0.2))
	end
	for _, star in { V(-0.8, 3.6, -1.0), V(0.9, 3.3, -0.95), V(0.2, 4.0, -0.8), V(-1.1, 2.5, -0.75), V(0.7, 2.2, -1.05), V(-0.3, 1.95, -1.0) } do
		ball(b, "Star", 0.14, star, starWhite, Enum.Material.Neon, true)
	end
	local ringCenter = CF(0, 2.8, 0) * ANG(rad(12), 0, rad(-14))
	for k = 0, 23 do
		local angle = rad(k * 15)
		local seg = egg(b, "Ring", V(0.62, 0.08, 0.32), ringCenter * ANG(0, -angle, 0) * CF(0, 0, -2.35), a, Enum.Material.Neon, true)
		seg.Transparency = 0.35
	end
	local planets = { Color3.fromRGB(255, 150, 90), Color3.fromRGB(120, 230, 160), Color3.fromRGB(255, 120, 200) }
	for k = 0, 2 do
		local angle = rad(40 + k * 120)
		local p = (ringCenter * CF(math.sin(angle) * 2.35, 0.15, -math.cos(angle) * 2.35)).Position
		egg(b, "Planet", V(0.6, 0.5, 0.5), CF(p), planets[k + 1])
		egg(b, "PlanetRidge", V(0.62, 0.07, 0.52), CF(p), darker(planets[k + 1], 0.2))
	end
	eyes(b, 0, 3.15, -1.1, 0.45, 0.55)
	smile(b, 0, 2.55, -1.15, 0.5)
	blush(b, 0, 2.75, -1.1, 0.85)
	-- Floats: a little cosmic cloud underneath instead of legs
	for k = 0, 5 do
		local angle = rad(k * 60)
		local puff = ball(b, "Nebula", 0.75, V(math.cos(angle) * 0.6, 1.2, math.sin(angle) * 0.6), lighter(c, 0.35), Enum.Material.Neon, true)
		puff.Transparency = 0.5
	end
	return 5.2
end

-- The pizza emperor: laurel wreath, purple sash and a golden staff.
designs.ImperatorePizzone = function(b, c, a)
	local gold = Color3.fromRGB(255, 200, 50)
	local cheese = Color3.fromRGB(255, 215, 110)
	legs(b, darker(c, 0.3), 1.0, 0.65)
	egg(b, "Crust", V(3.7, 3.7, 0.75), CF(0, 3.0, 0), c)
	egg(b, "Sauce", V(3.2, 3.2, 0.3), CF(0, 3.0, -0.25), a)
	for _, blob in { V(-0.8, 3.7, -0.38), V(0.7, 3.9, -0.38), V(-1.0, 2.5, -0.38), V(0.9, 2.3, -0.38), V(0.1, 1.8, -0.38) } do
		egg(b, "Cheese", V(0.7, 0.5, 0.14), CF(blob) * ANG(0, 0, blob.X), cheese)
	end
	for _, pep in { V(-0.95, 3.1, -0.42), V(1.0, 3.15, -0.42), V(-0.35, 2.05, -0.42), V(0.55, 1.85, -0.42), V(0.0, 4.15, -0.42) } do
		zcyl(b, "Pepperoni", 0.08, 0.5, pep, Color3.fromRGB(190, 40, 35))
	end
	eyes(b, 0, 3.3, -0.5, 0.48, 0.55, true)
	egg(b, "Mustache", V(1.0, 0.25, 0.15), CF(0, 2.75, -0.5), Color3.fromRGB(80, 50, 30), nil, true)
	-- Laurel wreath around the top
	for k = 0, 10 do
		local angle = rad(-170 + k * 16)
		local p = V(math.cos(angle) * 1.75, 3.0 - math.sin(angle) * 1.75, -0.35)
		egg(b, "Laurel", V(0.45, 0.2, 0.15), CF(p) * ANG(0, 0, angle + rad(90)), gold, Enum.Material.Foil, true)
	end
	box(b, "Sash", V(0.5, 3.6, 0.2), CF(0, 2.85, -0.45) * ANG(0, 0, rad(35)), Color3.fromRGB(120, 40, 160))
	capsule(b, "Staff", V(-2.0, 0.3, -0.4), V(-2.15, 4.8, -0.4), 0.2, gold, Enum.Material.Foil, true)
	cone(b, "StaffEagle", V(-2.15, 4.8, -0.4), 0.55, 0.6, 0.1, gold, Enum.Material.Foil, true)
	arms(b, 2.7, 1.75, c, 0.55)
	return 5.6
end

-- The ultimate brainrot: a glowing brain with a third eye and a crown of energy.
designs.OmegaBrainrotto = function(b, c, a)
	local fold = darker(c, 0.18)
	-- Spine and floating ring underneath
	tube(b, "Stem", { V(0, 1.6, 0.2), V(0, 2.3, 0.15) }, 0.6, darker(c, 0.1))
	for k = 0, 17 do
		local angle = rad(k * 20)
		local seg = egg(b, "Halo", V(0.55, 0.1, 0.25), CF(0, 1.2, 0) * ANG(0, -angle, 0) * CF(0, 0, -1.4), a, Enum.Material.Neon, true)
		seg.Transparency = 0.2
	end
	for _, side in { -1, 1 } do
		egg(b, "Hemisphere", V(1.7, 2.3, 3.0), CF(side * 0.82, 3.3, 0), c)
		-- Wrinkles: wavy folds over each half
		for row = 0, 2 do
			local y = 2.75 + row * 0.55
			local path = {}
			for i = 0, 4 do
				local t = i / 4
				local z = -1.35 + t * 2.7
				local r = 1.48 * math.sqrt(math.max(0, 1 - ((y - 3.3) / 1.15) ^ 2 - (z / 1.5) ^ 2 * 0.6))
				table.insert(path, V(side * (0.82 + r * 0.55), y + math.sin(t * math.pi * 3) * 0.12, z))
			end
			tube(b, "Fold", path, 0.12, fold)
		end
	end
	egg(b, "Split", V(0.12, 2.0, 2.8), CF(0, 3.45, 0), fold)
	-- Face, with a glowing third eye
	eyes(b, 0, 3.05, -1.42, 0.5, 0.55, true)
	ball(b, "ThirdEye", 0.45, V(0, 3.75, -1.38), a, Enum.Material.Neon, true)
	ball(b, "ThirdPupil", 0.2, V(0, 3.75, -1.58), BLACK, nil, true)
	mouth(b, 0, 2.45, -1.35, 0.6, 0.3)
	-- Crown of energy
	for k = 0, 6 do
		local angle = rad(k * 360 / 7)
		local height = 0.9 + (k % 2) * 0.35
		egg(b, "EnergySpike", V(0.26, height, 0.26), CF(math.cos(angle) * 0.8, 4.3 + height / 2, math.sin(angle) * 0.9) * ANG(math.sin(angle) * 0.25, 0, -math.cos(angle) * 0.25), a, Enum.Material.Neon, true)
	end
	-- Neural tendrils
	for _, side in { -1, 1 } do
		tube(b, "Nerve", { V(side * 1.4, 2.6, 0.2), V(side * 2.0, 2.2, 0.0), V(side * 2.3, 2.6, -0.4), V(side * 2.25, 3.1, -0.6) }, 0.16, a, Enum.Material.Neon)
		ball(b, "NerveTip", 0.32, V(side * 2.25, 3.15, -0.62), lighter(a, 0.4), Enum.Material.Neon, true)
	end
	return 5.6
end

-- Meme classics ----------------------------------------------------------------

-- Lirilì Larilà: an elephant head on a cactus body, in sandals.
designs.LiriliLarila = function(b, c, a)
	local strap = Color3.fromRGB(150, 95, 50)
	for _, side in { -1, 1 } do
		capsule(b, "Leg", V(side * 0.45, 1.3, 0), V(side * 0.5, 0.45, 0), 0.6, a)
		egg(b, "Sandal", V(0.7, 0.14, 1.05), CF(side * 0.5, 0.08, -0.15), strap)
		egg(b, "Strap", V(0.72, 0.16, 0.22), CF(side * 0.5, 0.3, -0.35), strap)
	end
	capsule(b, "Cactus", V(0, 1.7, 0), V(0, 2.9, 0), 1.7, c)
	meridians(b, V(0, 2.3, 0), V(1.7, 2.9, 1.7), 3, darker(c, 0.15))
	for _, spine in { V(-0.8, 2.6, -0.3), V(0.82, 2.2, -0.25), V(-0.7, 1.7, -0.45), V(0.6, 3.0, -0.55), V(0.15, 1.9, -0.85), V(-0.3, 2.85, -0.78) } do
		ball(b, "Spine", 0.12, spine, Color3.fromRGB(250, 240, 200), nil, true)
	end
	for _, side in { -1, 1 } do
		capsule(b, "CactusArm", V(side * 0.8, 2.3, 0), V(side * 1.3, 2.4, 0), 0.5, c)
		capsule(b, "CactusArmUp", V(side * 1.3, 2.4, 0), V(side * 1.3, 3.0, 0), 0.5, c)
	end
	local head = V(0, 4.15, -0.1)
	ball(b, "Head", 1.7, head, a)
	for _, side in { -1, 1 } do
		egg(b, "Ear", V(0.25, 1.5, 1.2), CF(head + V(side * 0.95, 0, 0.2)) * ANG(0, side * rad(-20), 0), a)
		egg(b, "EarInner", V(0.1, 1.1, 0.85), CF(head + V(side * 0.93, 0, 0.05)) * ANG(0, side * rad(-20), 0), Color3.fromRGB(240, 170, 180))
	end
	tube(b, "Trunk", { head + V(0, -0.3, -0.8), head + V(0, -0.85, -1.0), head + V(0.05, -1.35, -0.9), head + V(0.2, -1.55, -0.65) }, 0.42, a)
	for _, side in { -1, 1 } do
		cone(b, "Tusk", head + V(side * 0.35, -0.75, -0.65), 0.4, 0.16, 0.03, WHITE)
	end
	eyes(b, 0, head.Y + 0.2, head.Z - 0.72, 0.38, 0.42)
	return 5.0
end

-- Tim Cheese: a mouse made of cheese.
designs.TimCheese = function(b, c, a)
	legs(b, darker(c, 0.25), 0.65, 0.45)
	egg(b, "Body", V(2.1, 2.2, 2.0), CF(0, 1.85, 0), c)
	for _, hole in { V(-0.6, 2.3, -0.85), V(0.55, 1.6, -0.9), V(0.75, 2.45, -0.7), V(-0.4, 1.3, -0.88), V(-0.95, 1.8, -0.5) } do
		egg(b, "Hole", V(0.3, 0.3, 0.12), CF(hole), darker(c, 0.2), nil, true)
	end
	local head = V(0, 3.25, -0.2)
	ball(b, "Head", 1.5, head, c)
	for _, side in { -1, 1 } do
		zcyl(b, "Ear", 0.15, 0.95, head + V(side * 0.62, 0.62, 0.1), c)
		zcyl(b, "EarInner", 0.16, 0.6, head + V(side * 0.62, 0.62, 0.05), a)
		for k = -1, 1 do
			capsule(b, "Whisker", head + V(side * 0.2, -0.2 + k * 0.08, -0.72), head + V(side * 0.85, -0.15 + k * 0.15, -0.68), 0.035, BLACK, nil, true)
		end
	end
	ball(b, "Nose", 0.26, head + V(0, -0.15, -0.76), a, nil, true)
	eyes(b, 0, head.Y + 0.15, head.Z - 0.62, 0.3, 0.38)
	smile(b, 0, head.Y - 0.38, head.Z - 0.68, 0.3)
	tube(b, "Tail", { V(0, 1.4, 0.95), V(0.4, 1.0, 1.4), V(0.75, 1.3, 1.75), V(0.7, 1.85, 1.9) }, 0.12, a)
	arms(b, 2.1, 0.9, c, 0.55)
	return 4.2
end

-- Pipi Kiwi: a kiwi bird made of kiwi fruit.
designs.PipiKiwi = function(b, c, a)
	local beak = Color3.fromRGB(230, 200, 150)
	for _, side in { -1, 1 } do
		tube(b, "Leg", { V(side * 0.35, 1.2, 0.1), V(side * 0.4, 0.6, 0), V(side * 0.4, 0.15, -0.1) }, 0.16, beak)
		egg(b, "Toes", V(0.45, 0.12, 0.55), CF(side * 0.4, 0.07, -0.25), beak)
	end
	egg(b, "Body", V(2.2, 2.0, 2.4), CF(0, 2.0, 0.1), c)
	egg(b, "Slice", V(1.6, 1.6, 0.3), CF(0, 1.95, -1.05), a)
	egg(b, "SliceCore", V(0.55, 0.55, 0.32), CF(0, 1.95, -1.08), Color3.fromRGB(250, 250, 220))
	for k = 0, 9 do
		local angle = rad(k * 36)
		egg(b, "Seed", V(0.08, 0.16, 0.1), CF(math.cos(angle) * 0.42, 1.95 + math.sin(angle) * 0.42, -1.2) * ANG(0, 0, angle + rad(90)), BLACK, nil, true)
	end
	local head = V(0, 3.1, -0.55)
	ball(b, "Head", 1.15, head, c)
	tube(b, "Beak", { head + V(0, -0.1, -0.5), head + V(0, -0.3, -1.1), head + V(0, -0.5, -1.55) }, 0.18, beak)
	eyes(b, 0, head.Y + 0.15, head.Z - 0.45, 0.28, 0.32)
	return 3.8
end

-- Talpa di Ferro: an iron mole with a drill nose and a miner's helmet.
designs.TalpaDiFerro = function(b, c, a)
	local metal = Enum.Material.Metal
	legs(b, darker(c, 0.2), 0.6, 0.55)
	egg(b, "Body", V(2.3, 2.1, 2.4), CF(0, 1.9, 0.1), c, metal)
	for _, rivet in { V(-0.95, 2.2, -0.6), V(0.95, 2.2, -0.6), V(-0.8, 1.4, -0.8), V(0.8, 1.4, -0.8), V(0, 2.75, -0.85) } do
		ball(b, "Rivet", 0.16, rivet, lighter(c, 0.3), metal, true)
	end
	for k = 0, 4 do
		local d = 0.9 - k * 0.17
		egg(b, "Drill", V(d, d, 0.35), CF(0, 2.0, -1.15 - k * 0.28) * ANG(0, 0, k * 0.6), if k % 2 == 0 then Color3.fromRGB(200, 200, 210) else Color3.fromRGB(150, 150, 160), metal)
	end
	eyes(b, 0, 2.55, -0.95, 0.38, 0.38)
	egg(b, "Helmet", V(1.9, 0.9, 1.9), CF(0, 2.95, 0.05), a)
	egg(b, "HelmetBrim", V(2.1, 0.12, 2.1), CF(0, 2.7, 0.05), darker(a, 0.15))
	ball(b, "Lamp", 0.45, V(0, 3.1, -0.85), Color3.fromRGB(255, 245, 180), Enum.Material.Neon, true)
	for _, side in { -1, 1 } do
		local hand = V(side * 1.35, 1.6, -0.5)
		capsule(b, "Arm", V(side * 0.95, 2.0, -0.2), hand, 0.32, c, metal)
		egg(b, "Claw", V(0.7, 0.18, 0.6), CF(hand) * ANG(0, 0, side * rad(30)), lighter(c, 0.2), metal)
	end
	return 3.6
end

-- Svinino Bombondino: a round black bomb with a pig face and a lit fuse.
designs.SvininoBombondino = function(b, c, a)
	for _, side in { -1, 1 } do
		capsule(b, "Leg", V(side * 0.5, 0.9, 0), V(side * 0.55, 0.35, 0), 0.42, a)
		egg(b, "Trotter", V(0.45, 0.28, 0.5), CF(side * 0.55, 0.14, -0.05), darker(a, 0.35))
	end
	ball(b, "Bomb", 2.5, V(0, 2.1, 0), c)
	egg(b, "Shine", V(0.5, 0.3, 0.12), CF(-0.65, 2.75, -0.95) * ANG(0, 0, rad(30)), WHITE, Enum.Material.Neon, true)
	egg(b, "Snout", V(0.75, 0.55, 0.3), CF(0, 1.9, -1.2), a)
	for _, side in { -1, 1 } do
		ball(b, "Nostril", 0.14, V(side * 0.14, 1.9, -1.35), darker(a, 0.45), nil, true)
		egg(b, "Ear", V(0.45, 0.55, 0.15), CF(side * 0.75, 3.05, -0.35) * ANG(rad(-20), 0, side * rad(-25)), a)
	end
	eyes(b, 0, 2.45, -1.05, 0.42, 0.42)
	blush(b, 0, 2.05, -1.12, 0.78)
	vcyl(b, "FuseCap", 0.3, 0.6, V(0, 3.4, 0), Color3.fromRGB(120, 120, 130), Enum.Material.Metal)
	tube(b, "Fuse", { V(0, 3.55, 0), V(0.15, 3.85, 0.05), V(0.05, 4.1, 0.1) }, 0.1, Color3.fromRGB(200, 170, 120))
	ball(b, "Spark", 0.35, V(0.05, 4.2, 0.1), Color3.fromRGB(255, 200, 60), Enum.Material.Neon, true)
	tube(b, "Tail", { V(0, 1.9, 1.2), V(0.25, 2.05, 1.4), V(0.1, 2.25, 1.45) }, 0.1, a)
	return 4.4
end

-- Trippi Troppi: a shrimp with a cat's head.
designs.TrippiTroppi = function(b, c, a)
	for k = 0, 6 do
		local angle = rad(200 - k * 26)
		local d = 1.2 - k * 0.08
		egg(b, "Segment", V(d, d * 0.9, 0.85), CF(math.cos(angle) * 1.05, 1.6 + math.sin(angle) * 1.05 + 0.4, 0.4) * ANG(0, 0, angle), if k % 2 == 0 then c else lighter(c, 0.15))
	end
	for _, side in { -1, 1 } do
		egg(b, "TailFan", V(0.5, 0.9, 0.2), CF(-1.15 + side * 0.25, 0.85, 0.4) * ANG(0, 0, side * rad(35)), c)
	end
	for k = 0, 1 do
		for _, side in { -1, 1 } do
			local x = -0.2 + k * 0.55
			tube(b, "Leg", { V(x, 1.05, 0.4 + side * 0.3), V(x - 0.1, 0.5, 0.4 + side * 0.6), V(x - 0.05, 0.08, 0.4 + side * 0.65) }, 0.16, darker(c, 0.15))
		end
	end
	local head = V(1.05, 2.55, 0)
	ball(b, "Head", 1.45, head, a)
	for _, side in { -1, 1 } do
		cone(b, "Ear", head + V(side * 0.42, 0.45, 0.1), 0.55, 0.42, 0.05, a)
		for k = -1, 1 do
			capsule(b, "Whisker", head + V(side * 0.2, -0.2 + k * 0.08, -0.68), head + V(side * 0.85, -0.12 + k * 0.15, -0.6), 0.035, WHITE, nil, true)
		end
		capsule(b, "Antenna", head + V(side * 0.2, 0.55, -0.2), head + V(side * 0.6, 1.4, -0.8), 0.07, c)
	end
	egg(b, "Nose", V(0.18, 0.13, 0.1), CF(head + V(0, -0.1, -0.72)), Color3.fromRGB(255, 130, 150), nil, true)
	eyes(b, head.X, head.Y + 0.15, head.Z - 0.6, 0.28, 0.36)
	smile(b, head.X, head.Y - 0.35, head.Z - 0.66, 0.3)
	return 4.4
end

-- Bandito Bobritto: a beaver bandit with a fedora and a water blaster.
designs.BanditoBobritto = function(b, c, a)
	legs(b, darker(c, 0.25), 0.75, 0.5)
	egg(b, "Body", V(2.2, 2.5, 2.0), CF(0, 2.0, 0), c)
	egg(b, "Belly", V(1.4, 1.7, 0.5), CF(0, 1.85, -0.8), lighter(c, 0.35))
	egg(b, "Tail", V(1.1, 0.3, 1.9), CF(0, 0.6, 1.3) * ANG(rad(-25), 0, 0), darker(c, 0.35))
	local head = V(0, 3.55, -0.15)
	ball(b, "Head", 1.6, head, c)
	egg(b, "Mask", V(1.65, 0.38, 1.4), CF(head + V(0, 0.15, -0.05)), BLACK)
	eyes(b, 0, head.Y + 0.15, head.Z - 0.68, 0.32, 0.36, true)
	egg(b, "Muzzle", V(0.8, 0.5, 0.4), CF(head + V(0, -0.3, -0.62)), lighter(c, 0.35))
	ball(b, "Nose", 0.22, head + V(0, -0.15, -0.82), BLACK, nil, true)
	for _, side in { -1, 1 } do
		egg(b, "Tooth", V(0.16, 0.3, 0.1), CF(head + V(side * 0.09, -0.62, -0.72)), WHITE, nil, true)
		ball(b, "Ear", 0.4, head + V(side * 0.62, 0.55, 0.1), darker(c, 0.15))
	end
	egg(b, "HatBrim", V(1.9, 0.14, 1.7), CF(head + V(0, 0.65, 0)), a)
	vcyl(b, "HatCrown", 0.6, 1.15, head + V(0, 0.95, 0), a)
	vcyl(b, "HatBand", 0.14, 1.18, head + V(0, 0.75, 0), Color3.fromRGB(200, 40, 50))
	box(b, "Blaster", V(0.4, 0.45, 1.3), CF(1.2, 1.9, -0.8), Color3.fromRGB(90, 200, 255))
	egg(b, "Tank", V(0.5, 0.5, 0.5), CF(1.2, 2.25, -0.55), Color3.fromRGB(255, 200, 60), Enum.Material.Glass)
	capsule(b, "Nozzle", V(1.2, 1.95, -1.45), V(1.2, 1.95, -1.75), 0.18, Color3.fromRGB(255, 120, 40))
	arms(b, 2.5, 0.95, c, 0.6)
	return 5.0
end

-- Cacto Hipopotamo: a cactus hippo with a flower on its head.
designs.CactoHipopotamo = function(b, c, a)
	for _, leg in { V(-0.75, 0, -0.6), V(0.75, 0, -0.6), V(-0.75, 0, 0.8), V(0.75, 0, 0.8) } do
		capsule(b, "Leg", leg + V(0, 1.1, 0), leg + V(0, 0.4, 0), 0.7, c)
	end
	egg(b, "Body", V(2.5, 2.0, 3.0), CF(0, 1.9, 0.15), c)
	meridians(b, V(0, 1.9, 0.15), V(2.5, 2.0, 3.0), 3, darker(c, 0.15))
	egg(b, "Head", V(2.0, 1.5, 1.6), CF(0, 2.35, -1.45), c)
	egg(b, "Snout", V(1.9, 1.0, 0.9), CF(0, 2.0, -2.0), lighter(c, 0.15))
	for _, side in { -1, 1 } do
		ball(b, "Nostril", 0.18, V(side * 0.35, 2.3, -2.42), darker(c, 0.45), nil, true)
		ball(b, "Ear", 0.4, V(side * 0.7, 3.1, -1.3), c)
		ball(b, "Eye", 0.4, V(side * 0.48, 2.95, -1.95), WHITE, nil, true)
		ball(b, "Pupil", 0.2, V(side * 0.48, 2.93, -2.13), BLACK, nil, true)
	end
	smile(b, 0, 1.75, -2.42, 0.6)
	for _, spine in { V(-0.9, 2.5, 0.4), V(0.9, 2.3, -0.2), V(0, 2.85, 0.6), V(-0.6, 2.0, 1.2), V(0.7, 2.6, 1.0) } do
		ball(b, "Spine", 0.13, spine, Color3.fromRGB(250, 240, 200), nil, true)
	end
	for k = 0, 4 do
		egg(b, "Petal", V(0.4, 0.12, 0.25), CF(0, 3.2, -1.35) * ANG(0, rad(k * 72), 0) * CF(0.22, 0, 0), a)
	end
	ball(b, "FlowerCenter", 0.22, V(0, 3.24, -1.35), Color3.fromRGB(255, 220, 60))
	return 3.4
end

-- Ta Ta Ta Sahur: a kettle with a drumstick, ready to wake everyone up.
designs.TaTaTaSahur = function(b, c, a)
	local metal = Enum.Material.Metal
	legs(b, darker(c, 0.3), 0.8, 0.5)
	vcyl(b, "Kettle", 2.0, 2.1, V(0, 1.9, 0), c, metal)
	egg(b, "KettleTop", V(2.1, 0.8, 2.1), CF(0, 2.9, 0), c, metal)
	vcyl(b, "Lid", 0.25, 1.1, V(0, 3.3, 0), darker(c, 0.15), metal)
	ball(b, "LidKnob", 0.42, V(0, 3.55, 0), a)
	tube(b, "Spout", { V(0.9, 2.1, -0.4), V(1.45, 2.6, -0.65), V(1.75, 3.0, -0.75) }, 0.38, c, metal)
	tube(b, "Handle", { V(-0.65, 3.2, 0.3), V(0, 3.75, 0.35), V(0.65, 3.2, 0.3) }, 0.2, a)
	eyes(b, 0, 2.45, -1.0, 0.38, 0.5)
	mouth(b, 0, 1.75, -1.05, 0.6, 0.35)
	for _, side in { -1, 1 } do
		local hand = V(side * 1.55, 1.9, -0.4)
		capsule(b, "Arm", V(side * 1.0, 2.2, 0), hand, 0.24, darker(c, 0.3))
		ball(b, "Hand", 0.38, hand, darker(c, 0.3))
	end
	capsule(b, "Drumstick", V(-1.55, 1.85, -0.45), V(-1.9, 3.3, -0.6), 0.2, Color3.fromRGB(210, 170, 110), Enum.Material.Wood)
	ball(b, "DrumstickEnd", 0.36, V(-1.95, 3.45, -0.62), Color3.fromRGB(210, 170, 110), Enum.Material.Wood)
	return 4.0
end

-- Perochello Lemonchello: a lemon parrot with green wings.
designs.PerochelloLemonchello = function(b, c, a)
	local beak = Color3.fromRGB(230, 70, 40)
	for _, side in { -1, 1 } do
		tube(b, "Leg", { V(side * 0.3, 1.0, 0), V(side * 0.32, 0.2, -0.05) }, 0.14, Color3.fromRGB(120, 100, 80))
		egg(b, "Toes", V(0.4, 0.12, 0.5), CF(side * 0.32, 0.07, -0.2), Color3.fromRGB(120, 100, 80))
	end
	egg(b, "Lemon", V(1.9, 2.5, 1.8), CF(0, 2.15, 0) * ANG(0, 0, rad(10)), c)
	ball(b, "LemonTip", 0.45, V(0.25, 0.95, 0), c)
	for _, side in { -1, 1 } do
		egg(b, "Wing", V(0.4, 1.6, 1.2), CF(side * 0.95, 2.2, 0.2) * ANG(0, 0, side * rad(-12)), a)
		egg(b, "WingTip", V(0.3, 0.7, 0.6), CF(side * 1.05, 1.5, 0.45), Color3.fromRGB(60, 140, 230))
	end
	for k = -1, 1 do
		egg(b, "TailFeather", V(0.3, 1.3, 0.15), CF(k * 0.22, 1.0, 0.9) * ANG(rad(35), 0, k * rad(-15)), if k == 0 then Color3.fromRGB(230, 60, 60) else a)
	end
	local head = V(-0.15, 3.65, -0.1)
	ball(b, "Head", 1.25, head, a)
	egg(b, "Crest", V(0.25, 0.7, 0.4), CF(head + V(0, 0.65, 0.15)) * ANG(rad(-25), 0, 0), Color3.fromRGB(230, 60, 60))
	egg(b, "Beak", V(0.45, 0.6, 0.55), CF(head + V(0, -0.2, -0.62)) * ANG(rad(25), 0, 0), beak)
	egg(b, "Face", V(0.7, 0.55, 0.3), CF(head + V(0, 0.1, -0.45)), WHITE)
	eyes(b, head.X, head.Y + 0.15, head.Z - 0.55, 0.22, 0.3)
	return 4.6
end

-- Brr Brr Patapim: a forest guardian, half tree trunk, with giant feet.
designs.BrrBrrPatapim = function(b, c, a)
	for _, side in { -1, 1 } do
		capsule(b, "Leg", V(side * 0.5, 1.8, 0), V(side * 0.6, 0.6, -0.1), 0.45, c, Enum.Material.Wood)
		egg(b, "BigFoot", V(1.0, 0.6, 1.8), CF(side * 0.65, 0.3, -0.5), lighter(c, 0.25))
		for k = -1, 1 do
			ball(b, "Toe", 0.32, V(side * 0.65 + k * 0.28, 0.35, -1.35), lighter(c, 0.25))
		end
	end
	capsule(b, "Trunk", V(0, 2.0, 0), V(0, 3.4, 0), 1.6, c, Enum.Material.Wood)
	for _, y in { 2.2, 2.9 } do
		egg(b, "Bark", V(1.66, 0.1, 1.66), CF(0, y, 0), darker(c, 0.2), Enum.Material.Wood)
	end
	egg(b, "Face", V(1.2, 1.1, 0.4), CF(0, 3.35, -0.7), Color3.fromRGB(230, 190, 150))
	eyes(b, 0, 3.5, -0.88, 0.3, 0.38)
	tube(b, "Nose", { V(0, 3.3, -0.9), V(0, 3.15, -1.35), V(0, 2.85, -1.5) }, 0.3, Color3.fromRGB(230, 170, 130))
	smile(b, 0, 2.95, -0.92, 0.35)
	for k = 0, 6 do
		local angle = rad(k * 51)
		ball(b, "Leaves", 0.9, V(math.cos(angle) * 0.6, 4.35 + (k % 2) * 0.25, math.sin(angle) * 0.6), if k % 2 == 0 then a else darker(a, 0.15))
	end
	ball(b, "LeavesTop", 1.1, V(0, 4.8, 0), a)
	for _, side in { -1, 1 } do
		tube(b, "Branch", { V(side * 0.75, 3.0, 0), V(side * 1.4, 3.3, -0.1), V(side * 1.7, 3.9, -0.2) }, 0.22, c)
		ball(b, "BranchLeaf", 0.45, V(side * 1.75, 4.05, -0.2), a)
	end
	return 5.4
end

-- Cappuccino Assassino: a cappuccino cup on a ninja's body, two katanas.
designs.CappuccinoAssassino = function(b, c, a)
	local suit = Color3.fromRGB(30, 30, 38)
	legs(b, suit, 1.4, 0.4)
	egg(b, "Body", V(1.4, 1.9, 1.2), CF(0, 2.35, 0), suit)
	egg(b, "Belt", V(1.45, 0.25, 1.25), CF(0, 1.75, 0), Color3.fromRGB(180, 30, 40))
	-- The cup head
	vcyl(b, "Cup", 1.2, 1.9, V(0, 3.85, 0), c)
	egg(b, "CupBase", V(1.7, 0.35, 1.7), CF(0, 3.25, 0), c)
	egg(b, "Foam", V(1.75, 0.4, 1.75), CF(0, 4.48, 0), Color3.fromRGB(245, 230, 210))
	for k = 0, 2 do
		egg(b, "LatteArt", V(0.5 - k * 0.12, 0.08, 0.4 - k * 0.1), CF(0, 4.69, 0.1 - k * 0.18), a, nil, true)
	end
	tube(b, "CupHandle", { V(0.95, 4.2, 0), V(1.35, 3.95, 0), V(1.0, 3.55, 0) }, 0.2, c)
	egg(b, "Mask", V(1.95, 0.42, 1.95), CF(0, 3.9, 0), suit)
	eyes(b, 0, 3.92, -0.98, 0.32, 0.36, true)
	for _, side in { -1, 1 } do
		local hand = V(side * 1.1, 2.0, -0.5)
		capsule(b, "Arm", V(side * 0.65, 2.8, 0), hand, 0.26, suit)
		ball(b, "Hand", 0.36, hand, suit)
		capsule(b, "Katana", hand + V(0, 0.15, 0), hand + V(side * 0.6, 1.9, -0.6), 0.1, Color3.fromRGB(215, 220, 230), Enum.Material.Metal, true)
		capsule(b, "KatanaGrip", hand + V(0, -0.1, 0), hand + V(0, 0.15, 0), 0.16, Color3.fromRGB(180, 30, 40), nil, true)
	end
	return 5.0
end

-- Brri Brri Bicus Dicus Bombicus: a little bird legionary with sword and shield.
designs.BrriBrriBicus = function(b, c, a)
	local gold = Color3.fromRGB(240, 190, 60)
	for _, side in { -1, 1 } do
		tube(b, "Leg", { V(side * 0.3, 1.1, 0), V(side * 0.32, 0.2, -0.05) }, 0.16, Color3.fromRGB(255, 170, 60))
		egg(b, "Toes", V(0.4, 0.12, 0.55), CF(side * 0.32, 0.07, -0.2), Color3.fromRGB(255, 170, 60))
	end
	egg(b, "Body", V(1.8, 2.0, 1.7), CF(0, 2.0, 0), c)
	egg(b, "Armor", V(1.85, 1.0, 1.75), CF(0, 2.15, 0), gold, Enum.Material.Metal)
	egg(b, "Skirt", V(1.9, 0.5, 1.8), CF(0, 1.35, 0), Color3.fromRGB(180, 30, 40))
	local head = V(0, 3.4, -0.05)
	ball(b, "Head", 1.35, head, c)
	egg(b, "Helmet", V(1.45, 0.75, 1.45), CF(head + V(0, 0.32, 0)), gold, Enum.Material.Metal)
	for k = 0, 6 do
		local t = k / 6
		ball(b, "Plume", 0.35, head + V(0, 0.85 + math.sin(t * math.pi) * 0.35, -0.5 + t * 1.0), Color3.fromRGB(220, 40, 50))
	end
	cone(b, "Beak", head + V(0, -0.2, -0.75), 0.3, 0.32, 0.04, Color3.fromRGB(255, 170, 60))
	eyes(b, 0, head.Y + 0.05, head.Z - 0.55, 0.26, 0.34, true)
	egg(b, "Shield", V(1.3, 1.6, 0.25), CF(-1.15, 2.0, -0.4) * ANG(0, rad(25), 0), Color3.fromRGB(180, 30, 40))
	egg(b, "ShieldBoss", V(0.4, 0.4, 0.2), CF(-1.22, 2.0, -0.55) * ANG(0, rad(25), 0), gold, Enum.Material.Metal)
	capsule(b, "Sword", V(1.05, 1.8, -0.5), V(1.4, 3.3, -0.8), 0.12, Color3.fromRGB(210, 215, 225), Enum.Material.Metal, true)
	egg(b, "SwordGuard", V(0.45, 0.12, 0.2), CF(1.05, 1.85, -0.5), gold, Enum.Material.Metal)
	ball(b, "Hand", 0.32, V(1.0, 1.7, -0.48), c)
	return 4.6
end

-- Trulimero Trulicina: a fish with a cat's face, standing on two legs.
designs.TrulimeroTrulicina = function(b, c, a)
	legs(b, darker(c, 0.25), 0.8, 0.4)
	egg(b, "Body", V(1.6, 2.0, 2.8), CF(0, 2.0, 0.2), c)
	egg(b, "Belly", V(1.2, 1.3, 2.2), CF(0, 1.75, 0.1), lighter(c, 0.4))
	for _, side in { -1, 1 } do
		egg(b, "TailFin", V(0.15, 1.0, 0.8), CF(0, 2.0 + side * 0.4, 1.75) * ANG(rad(side * 50), 0, 0), a)
		egg(b, "SideFin", V(0.9, 0.15, 0.55), CF(side * 0.85, 1.8, -0.1) * ANG(0, 0, side * rad(-30)), a)
	end
	egg(b, "DorsalFin", V(0.15, 0.8, 1.2), CF(0, 3.0, 0.35), a)
	for k = 0, 3 do
		egg(b, "Scale", V(0.4, 0.4, 0.1), CF(0.82, 2.0 + (k % 2) * 0.3, -0.3 + k * 0.35) * ANG(0, rad(90), 0), lighter(c, 0.2), nil, true)
	end
	local head = V(0, 2.55, -1.05)
	ball(b, "CatFace", 1.35, head, Color3.fromRGB(240, 200, 150))
	for _, side in { -1, 1 } do
		cone(b, "Ear", head + V(side * 0.4, 0.42, 0.1), 0.5, 0.38, 0.05, Color3.fromRGB(240, 200, 150))
		for k = -1, 1 do
			capsule(b, "Whisker", head + V(side * 0.2, -0.2 + k * 0.08, -0.62), head + V(side * 0.8, -0.12 + k * 0.15, -0.55), 0.035, BLACK, nil, true)
		end
	end
	egg(b, "Nose", V(0.18, 0.13, 0.1), CF(head + V(0, -0.1, -0.65)), Color3.fromRGB(255, 130, 150), nil, true)
	eyes(b, 0, head.Y + 0.15, head.Z - 0.55, 0.28, 0.36)
	smile(b, 0, head.Y - 0.35, head.Z - 0.6, 0.3)
	return 3.8
end

-- Chimpanzini Bananini: a chimp peeking out of a peeled banana.
designs.ChimpanziniBananini = function(b, c, a)
	legs(b, darker(a, 0.25), 0.7, 0.45)
	capsule(b, "Banana", V(0, 1.4, 0), V(0, 3.0, 0), 1.6, c)
	for k = 0, 3 do
		local angle = rad(k * 90 + 45)
		local dir = V(math.cos(angle), 0, math.sin(angle))
		egg(b, "Peel", V(0.75, 1.6, 0.2), CF(dir * 0.95 + V(0, 3.55, 0)) * CFrame.lookAt(Vector3.zero, dir).Rotation * ANG(rad(-35), 0, 0), c)
	end
	local head = V(0, 3.75, -0.05)
	ball(b, "Head", 1.45, head, a)
	egg(b, "Face", V(1.05, 0.95, 0.4), CF(head + V(0, -0.12, -0.55)), Color3.fromRGB(240, 210, 170))
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.48, head + V(side * 0.72, 0.05, 0.05), a)
		ball(b, "EarInner", 0.28, head + V(side * 0.74, 0.05, -0.1), Color3.fromRGB(240, 210, 170))
	end
	eyes(b, 0, head.Y + 0.08, head.Z - 0.68, 0.24, 0.32)
	smile(b, 0, head.Y - 0.38, head.Z - 0.72, 0.36)
	for _, spot in { V(-0.5, 2.0, -0.75), V(0.45, 2.6, -0.7), V(0.2, 1.6, -0.8) } do
		egg(b, "BananaSpot", V(0.16, 0.12, 0.08), CF(spot), darker(c, 0.5), nil, true)
	end
	arms(b, 2.6, 0.8, a, 0.6)
	return 4.7
end

-- Salamino Penguino: a penguin made of salami.
designs.SalaminoPenguino = function(b, c, a)
	local orange = Color3.fromRGB(255, 150, 40)
	for _, side in { -1, 1 } do
		egg(b, "Foot", V(0.7, 0.26, 1.0), CF(side * 0.45, 0.13, -0.3), orange)
	end
	egg(b, "Body", V(2.2, 3.0, 2.0), CF(0, 1.75, 0), c)
	for _, fat in { V(-0.6, 2.4, -0.9), V(0.5, 1.6, -0.95), V(0.65, 2.75, -0.75), V(-0.45, 1.2, -0.9), V(-0.9, 1.9, -0.6), V(0.1, 2.05, -1.0) } do
		egg(b, "Fat", V(0.2, 0.16, 0.08), CF(fat), a, nil, true)
	end
	for k = 0, 2 do
		zcyl(b, "Slice", 0.08, 0.75, V(-0.35 + k * 0.35, 1.25 + k * 0.45, -1.02), lighter(c, 0.2))
	end
	egg(b, "Head", V(1.6, 1.4, 1.5), CF(0, 3.55, 0), c)
	egg(b, "Face", V(1.1, 0.85, 0.3), CF(0, 3.48, -0.65), a)
	eyes(b, 0, 3.6, -0.75, 0.28, 0.36)
	egg(b, "Beak", V(0.45, 0.25, 0.5), CF(0, 3.28, -0.88), orange)
	for _, side in { -1, 1 } do
		egg(b, "Flipper", V(0.32, 1.4, 0.8), CF(side * 1.1, 2.0, -0.2) * ANG(rad(-25), 0, side * rad(20)), darker(c, 0.15))
	end
	tube(b, "String", { V(-0.3, 4.2, 0.1), V(0, 4.45, 0.1), V(0.3, 4.2, 0.1) }, 0.08, Color3.fromRGB(240, 230, 210))
	return 4.5
end

-- Zibra Zubra Zibralini: a zebra in sneakers.
designs.ZibraZubra = function(b, c, a)
	local shoe = Color3.fromRGB(240, 60, 70)
	for _, leg in { V(-0.5, 0, -0.65), V(0.5, 0, -0.65), V(-0.5, 0, 0.9), V(0.5, 0, 0.9) } do
		capsule(b, "Leg", leg + V(0, 1.7, 0), leg + V(0, 0.4, 0), 0.42, c)
		egg(b, "LegStripe", V(0.46, 0.14, 0.46), CF(leg.X, 1.1, leg.Z), a)
		egg(b, "Sneaker", V(0.5, 0.35, 0.75), CF(leg.X, 0.18, leg.Z - 0.12), shoe)
	end
	egg(b, "Body", V(1.7, 1.6, 2.8), CF(0, 2.35, 0.15), c)
	for k = 0, 4 do
		egg(b, "Stripe", V(1.74, 1.62, 0.22), CF(0, 2.35, -0.85 + k * 0.5), a)
	end
	tube(b, "Neck", { V(0, 2.8, -0.95), V(0, 3.4, -1.25) }, 0.8, c)
	egg(b, "Head", V(0.95, 1.05, 1.55), CF(0, 3.75, -1.5) * ANG(rad(-20), 0, 0), c)
	egg(b, "Snout", V(0.8, 0.65, 0.6), CF(0, 3.35, -2.1), Color3.fromRGB(70, 70, 75))
	for _, side in { -1, 1 } do
		cone(b, "Ear", V(side * 0.3, 4.15, -1.25), 0.45, 0.28, 0.05, c)
		ball(b, "Eye", 0.32, V(side * 0.4, 3.9, -1.98), BLACK, nil, true)
		ball(b, "Shine", 0.1, V(side * 0.4 - 0.05, 3.97, -2.1), WHITE, Enum.Material.Neon, true)
	end
	for k = 0, 6 do
		local t = k / 6
		ball(b, "Mane", 0.32, V(0, 4.3 - t * 1.4, -1.25 + t * 0.85), a)
	end
	tube(b, "Tail", { V(0, 2.6, 1.55), V(0.1, 2.0, 1.8) }, 0.12, c)
	ball(b, "TailTuft", 0.3, V(0.1, 1.85, 1.85), a)
	return 4.5
end

-- Burbaloni Loliloli: a capybara chilling in half a coconut, orange on its head.
designs.BurbaloniLoliloli = function(b, c, a)
	egg(b, "Shell", V(2.7, 1.7, 2.7), CF(0, 0.85, 0), a)
	for k = 0, 9 do
		local angle = rad(k * 36)
		egg(b, "Fiber", V(0.08, 0.9, 0.08), CF(math.cos(angle) * 1.33, 0.95, math.sin(angle) * 1.33) * ANG(0, -angle, rad(10)), darker(a, 0.25))
	end
	egg(b, "Flesh", V(2.55, 0.3, 2.55), CF(0, 1.62, 0), Color3.fromRGB(250, 248, 240))
	egg(b, "Body", V(1.9, 1.5, 2.3), CF(0, 2.1, 0.25), c)
	egg(b, "Head", V(1.35, 1.25, 1.7), CF(0, 2.85, -0.85), c)
	egg(b, "Snout", V(1.1, 0.75, 0.6), CF(0, 2.65, -1.5), darker(c, 0.1))
	egg(b, "Nose", V(0.6, 0.25, 0.15), CF(0, 2.8, -1.78), darker(c, 0.55), nil, true)
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.32, V(side * 0.5, 3.45, -0.55), darker(c, 0.15))
		egg(b, "SleepyEye", V(0.3, 0.12, 0.1), CF(side * 0.42, 3.1, -1.48), BLACK, nil, true)
		ball(b, "Paw", 0.45, V(side * 0.75, 1.75, -0.95), c)
	end
	ball(b, "Orange", 0.75, V(0, 3.75, -0.75), Color3.fromRGB(255, 150, 30))
	egg(b, "OrangeLeaf", V(0.4, 0.1, 0.22), CF(0.15, 4.15, -0.75) * ANG(0, 0, rad(-20)), Color3.fromRGB(70, 160, 60))
	return 4.3
end

-- Chef Crabracadabra: a crab chef with a toque, a spoon and a magic wand.
designs.ChefCrabracadabra = function(b, c, a)
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			local z = -0.4 + k * 0.5
			tube(b, "Leg", { V(side * 1.1, 1.3, z), V(side * 1.75, 1.05, z), V(side * 2.0, 0.12, z + 0.1) }, 0.2, c)
		end
	end
	egg(b, "Body", V(2.9, 1.5, 2.2), CF(0, 1.7, 0), c)
	for _, side in { -1, 1 } do
		capsule(b, "Stalk", V(side * 0.35, 2.2, -0.75), V(side * 0.45, 2.8, -0.85), 0.14, c)
		ball(b, "Eye", 0.42, V(side * 0.45, 2.92, -0.88), WHITE, nil, true)
		ball(b, "Pupil", 0.2, V(side * 0.45, 2.92, -1.08), BLACK, nil, true)
	end
	egg(b, "Mustache", V(1.0, 0.25, 0.3), CF(0, 1.85, -1.08), Color3.fromRGB(60, 40, 30))
	smile(b, 0, 1.55, -1.08, 0.4)
	-- Chef's toque
	vcyl(b, "ToqueBand", 0.45, 1.3, V(0, 2.55, 0.1), a)
	for k = 0, 5 do
		local angle = rad(k * 60)
		ball(b, "ToquePuff", 0.75, V(math.cos(angle) * 0.4, 3.15, 0.1 + math.sin(angle) * 0.4), a)
	end
	ball(b, "ToqueTop", 0.85, V(0, 3.4, 0.1), a)
	for _, side in { -1, 1 } do
		local wrist = V(side * 1.75, 2.0, -0.95)
		tube(b, "Arm", { V(side * 1.2, 1.7, -0.5), wrist }, 0.3, c)
		egg(b, "ClawTop", V(0.55, 0.35, 0.9), CF(wrist + V(0, 0.18, -0.4)), c)
		egg(b, "ClawBottom", V(0.45, 0.28, 0.75), CF(wrist + V(0, -0.15, -0.35)), c)
	end
	capsule(b, "Spoon", V(-1.75, 1.9, -1.25), V(-1.95, 3.0, -1.4), 0.12, Color3.fromRGB(200, 150, 90), Enum.Material.Wood)
	egg(b, "SpoonHead", V(0.4, 0.55, 0.15), CF(-1.97, 3.15, -1.42), Color3.fromRGB(200, 150, 90), Enum.Material.Wood)
	capsule(b, "Wand", V(1.75, 1.9, -1.25), V(2.0, 3.0, -1.4), 0.1, BLACK)
	ball(b, "WandStar", 0.4, V(2.03, 3.12, -1.42), Color3.fromRGB(255, 230, 90), Enum.Material.Neon, true)
	return 4.0
end

-- Glorbo Fruttodrillo: a crocodile whose body is a watermelon.
designs.GlorboFruttodrillo = function(b, c, a)
	local flesh = Color3.fromRGB(240, 70, 80)
	for _, leg in { V(-0.85, 0, -0.7), V(0.85, 0, -0.7), V(-0.85, 0, 0.9), V(0.85, 0, 0.9) } do
		capsule(b, "Leg", leg + V(0, 0.9, 0), leg + V(0, 0.3, 0), 0.5, a)
		egg(b, "Foot", V(0.6, 0.25, 0.75), CF(leg.X, 0.12, leg.Z - 0.15), a)
	end
	egg(b, "Melon", V(2.5, 2.0, 3.0), CF(0, 1.75, 0.2), c)
	for k = 0, 3 do
		egg(b, "MelonStripe", V(0.2, 2.02, 3.02), CF(0, 1.75, 0.2) * ANG(0, 0, rad(-60 + k * 40)), darker(c, 0.35))
	end
	egg(b, "Cut", V(1.8, 0.25, 2.3), CF(0, 2.7, 0.25), flesh)
	for _, seed in { V(-0.5, 2.83, -0.3), V(0.4, 2.83, 0.2), V(-0.2, 2.83, 0.75), V(0.55, 2.83, -0.5), V(-0.6, 2.83, 0.6) } do
		egg(b, "Seed", V(0.12, 0.08, 0.18), CF(seed), BLACK, nil, true)
	end
	egg(b, "Head", V(1.4, 1.0, 1.4), CF(0, 2.15, -1.6), a)
	egg(b, "Jaw", V(1.1, 0.4, 1.6), CF(0, 1.6, -2.2), a)
	egg(b, "Snout", V(1.05, 0.5, 1.6), CF(0, 2.0, -2.35), a)
	for k = -3, 3 do
		cone(b, "Tooth", V(k * 0.15, 1.75, -2.6 + math.abs(k) * 0.12), 0.18, 0.11, 0.02, WHITE, nil, true)
	end
	for _, side in { -1, 1 } do
		ball(b, "Eye", 0.42, V(side * 0.42, 2.7, -1.55), WHITE, nil, true)
		ball(b, "Pupil", 0.2, V(side * 0.45, 2.7, -1.75), BLACK, nil, true)
		ball(b, "Nostril", 0.12, V(side * 0.18, 2.25, -3.1), darker(a, 0.5), nil, true)
	end
	tube(b, "Tail", { V(0, 1.6, 1.7), V(0.3, 1.2, 2.5), V(0.6, 0.6, 3.1) }, 0.5, a)
	return 3.3
end

-- Blueberrinni Octopusini: a blueberry with a little star crown and tentacles.
designs.BlueberrinniOctopusini = function(b, c, a)
	for k = 0, 7 do
		local angle = rad(k * 45 + 22.5)
		local dir = V(math.cos(angle), 0, math.sin(angle))
		tube(b, "Tentacle", { dir * 0.8 + V(0, 1.6, 0), dir * 1.4 + V(0, 0.8, 0), dir * 1.9 + V(0, 0.25, 0), dir * 2.2 + V(0, 0.45, 0) }, 0.34, a)
	end
	ball(b, "Berry", 2.6, V(0, 2.6, 0), c)
	egg(b, "Bloom", V(1.5, 0.5, 1.5), CF(-0.7, 3.4, -0.6) * ANG(0, 0, rad(30)), lighter(c, 0.35))
	for k = 0, 4 do
		local angle = rad(k * 72)
		cone(b, "Crown", V(math.cos(angle) * 0.35, 3.75, math.sin(angle) * 0.35), 0.45, 0.25, 0.04, darker(c, 0.3))
	end
	eyes(b, 0, 2.75, -1.2, 0.48, 0.58)
	smile(b, 0, 2.1, -1.25, 0.5)
	blush(b, 0, 2.35, -1.2, 0.85)
	return 4.3
end

-- Orangutini Ananassini: an orangutan with a pineapple body.
designs.OrangutiniAnanassini = function(b, c, a)
	local face = Color3.fromRGB(230, 185, 140)
	legs(b, a, 0.7, 0.5)
	egg(b, "Pineapple", V(2.0, 2.4, 1.9), CF(0, 2.0, 0), c)
	for row = 0, 3 do
		for k = -2, 2 do
			local theta = rad(55 + row * 22)
			local phi = rad(-90 + k * 28 + (row % 2) * 14)
			ball(b, "Scale", 0.15, V(1.0 * math.sin(theta) * math.cos(phi), 2.0 + 1.2 * math.cos(theta), 0.95 * math.sin(theta) * math.sin(phi)), darker(c, 0.35))
		end
	end
	local head = V(0, 3.75, -0.1)
	ball(b, "Head", 1.7, head, a)
	egg(b, "Face", V(1.3, 1.15, 0.5), CF(head + V(0, -0.1, -0.6)), face)
	for _, side in { -1, 1 } do
		zcyl(b, "Cheek", 0.3, 0.95, head + V(side * 0.85, -0.05, -0.2), face)
	end
	eyes(b, 0, head.Y + 0.1, head.Z - 0.8, 0.26, 0.32)
	smile(b, 0, head.Y - 0.42, head.Z - 0.85, 0.4)
	for k = 0, 6 do
		local angle = rad(k * 51)
		egg(b, "Crown", V(0.25, 1.0, 0.13), CF(head + V(0, 0.7, 0)) * ANG(0, angle, 0) * CF(0, 0.35, 0.18) * ANG(rad(25), 0, 0), Color3.fromRGB(60, 160, 70))
	end
	for _, side in { -1, 1 } do
		tube(b, "Arm", { V(side * 0.95, 2.6, 0), V(side * 1.5, 1.6, -0.1), V(side * 1.55, 0.6, -0.2) }, 0.42, a)
		ball(b, "Hand", 0.55, V(side * 1.55, 0.45, -0.2), face)
	end
	return 4.7
end

-- Lionel Cactuseli: a cactus lion with a mane of golden spikes.
designs.LionelCactuseli = function(b, c, a)
	legs(b, darker(c, 0.2), 0.8, 0.5)
	capsule(b, "Body", V(0, 1.7, 0), V(0, 2.7, 0), 1.8, c)
	meridians(b, V(0, 2.2, 0), V(1.8, 2.8, 1.8), 3, darker(c, 0.15))
	local head = V(0, 3.75, -0.2)
	for k = 0, 15 do
		local angle = rad(k * 22.5)
		egg(b, "Mane", V(0.5, 0.95, 0.35), CF(head + V(math.cos(angle) * 0.95, math.sin(angle) * 0.95, 0.25)) * ANG(0, 0, angle - rad(90)), if k % 2 == 0 then a else darker(a, 0.15))
	end
	ball(b, "Head", 1.6, head, c)
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.45, head + V(side * 0.6, 0.65, 0.05), c)
	end
	egg(b, "Muzzle", V(0.9, 0.55, 0.4), CF(head + V(0, -0.35, -0.68)), lighter(c, 0.35))
	egg(b, "Nose", V(0.32, 0.2, 0.15), CF(head + V(0, -0.15, -0.85)), Color3.fromRGB(80, 50, 40), nil, true)
	eyes(b, 0, head.Y + 0.2, head.Z - 0.7, 0.32, 0.4, true)
	for _, spine in { V(-0.8, 2.2, -0.4), V(0.85, 2.0, -0.3), V(0.3, 2.6, -0.8), V(-0.4, 1.7, -0.8) } do
		ball(b, "Spine", 0.12, spine, Color3.fromRGB(250, 240, 200), nil, true)
	end
	tube(b, "Tail", { V(0, 1.9, 0.85), V(0.4, 2.4, 1.3), V(0.3, 3.0, 1.5) }, 0.22, c)
	ball(b, "TailTuft", 0.5, V(0.3, 3.15, 1.52), a)
	arms(b, 2.4, 0.95, c, 0.6)
	return 4.8
end

-- Bombardiro Crocodilo: a crocodile that is also a bomber plane.
designs.BombardiroCrocodilo = function(b, c, a)
	local metal = Enum.Material.Metal
	local grey = Color3.fromRGB(150, 155, 165)
	for _, side in { -1, 1 } do
		capsule(b, "Strut", V(side * 0.6, 1.7, -0.6), V(side * 0.7, 0.45, -0.6), 0.14, grey, metal)
		zcyl(b, "Wheel", 0.25, 0.6, V(side * 0.7, 0.3, -0.6) , BLACK)
	end
	capsule(b, "Strut", V(0, 1.7, 1.6), V(0, 0.4, 1.6), 0.14, grey, metal)
	ball(b, "TailWheel", 0.4, V(0, 0.2, 1.6), BLACK)
	egg(b, "Fuselage", V(1.6, 1.5, 4.6), CF(0, 2.4, 0.3), c)
	egg(b, "Belly", V(1.2, 0.8, 4.0), CF(0, 1.9, 0.3), lighter(c, 0.3))
	for k = 0, 5 do
		egg(b, "Scute", V(0.35, 0.3, 0.45), CF(0, 3.15, -0.9 + k * 0.5), darker(c, 0.2))
	end
	for _, side in { -1, 1 } do
		box(b, "Wing", V(2.6, 0.18, 1.3), CF(side * 2.0, 2.3, 0.0) * ANG(0, side * rad(-8), side * rad(4)), grey, metal)
		egg(b, "Engine", V(0.6, 0.6, 1.0), CF(side * 1.6, 2.15, -0.45), grey, metal)
		for k = 0, 1 do
			egg(b, "Propeller", V(1.1, 0.1, 0.12), CF(side * 1.6, 2.15, -1.0) * ANG(0, 0, rad(k * 90 + 30)), Color3.fromRGB(60, 60, 65))
		end
		egg(b, "Bomb", V(0.4, 0.4, 0.9), CF(side * 2.3, 1.95, 0.0), Color3.fromRGB(50, 55, 50), metal)
		egg(b, "TailWing", V(1.2, 0.12, 0.6), CF(side * 0.75, 2.5, 2.4), grey, metal)
		ball(b, "Eye", 0.38, V(side * 0.42, 2.95, -1.65), WHITE, nil, true)
		ball(b, "Pupil", 0.18, V(side * 0.45, 2.95, -1.82), BLACK, nil, true)
	end
	egg(b, "TailFin", V(0.12, 1.1, 0.8), CF(0, 3.1, 2.45), grey, metal)
	egg(b, "Snout", V(1.0, 0.5, 1.5), CF(0, 2.35, -2.3), c)
	egg(b, "Jaw", V(0.9, 0.3, 1.3), CF(0, 1.98, -2.2), lighter(c, 0.2))
	for k = -2, 2 do
		cone(b, "Tooth", V(k * 0.16, 2.08, -2.6 + math.abs(k) * 0.12), 0.18, 0.11, 0.02, WHITE, nil, true)
	end
	egg(b, "Cockpit", V(0.8, 0.5, 0.9), CF(0, 3.15, -0.9), Color3.fromRGB(120, 200, 255), Enum.Material.Glass, true)
	return 3.6
end

-- Bombombini Gusini: a goose bomber with goggles and propellers.
designs.BombombiniGusini = function(b, c, a)
	local metal = Enum.Material.Metal
	local grey = Color3.fromRGB(150, 155, 165)
	for _, side in { -1, 1 } do
		tube(b, "Leg", { V(side * 0.35, 1.5, 0.2), V(side * 0.4, 0.6, 0.1), V(side * 0.4, 0.15, 0.0) }, 0.18, a)
		egg(b, "Foot", V(0.55, 0.12, 0.7), CF(side * 0.4, 0.07, -0.25), a)
	end
	egg(b, "Body", V(1.9, 1.8, 2.8), CF(0, 2.3, 0.2), c)
	tube(b, "Neck", { V(0, 2.8, -0.9), V(0, 3.5, -1.0), V(0, 4.1, -0.85) }, 0.6, c)
	ball(b, "Head", 1.0, V(0, 4.4, -0.95), c)
	egg(b, "Beak", V(0.45, 0.3, 0.8), CF(0, 4.25, -1.6), a)
	for _, side in { -1, 1 } do
		zcyl(b, "Goggle", 0.18, 0.42, V(side * 0.25, 4.55, -1.38), Color3.fromRGB(120, 200, 255), Enum.Material.Glass, true)
		box(b, "Wing", V(2.0, 0.16, 1.1), CF(side * 1.75, 2.45, 0.2) * ANG(0, 0, side * rad(6)), grey, metal)
		egg(b, "Engine", V(0.5, 0.5, 0.85), CF(side * 1.4, 2.3, -0.3), grey, metal)
		for k = 0, 1 do
			egg(b, "Propeller", V(0.95, 0.09, 0.1), CF(side * 1.4, 2.3, -0.78) * ANG(0, 0, rad(k * 90 + 20)), Color3.fromRGB(60, 60, 65))
		end
		egg(b, "Bomb", V(0.38, 0.38, 0.8), CF(side * 1.9, 2.1, 0.25), Color3.fromRGB(50, 55, 50), metal)
	end
	egg(b, "GoggleStrap", V(1.05, 0.15, 1.05), CF(0, 4.55, -0.95), Color3.fromRGB(120, 80, 50))
	egg(b, "TailFeathers", V(1.2, 0.6, 0.6), CF(0, 2.6, 1.55) * ANG(rad(-25), 0, 0), lighter(c, 0.1))
	return 5.1
end

-- Frigo Camelo: a camel whose body is a fridge.
designs.FrigoCamelo = function(b, c, a)
	for _, leg in { V(-0.6, 0, -0.7), V(0.6, 0, -0.7), V(-0.6, 0, 0.8), V(0.6, 0, 0.8) } do
		capsule(b, "Leg", leg + V(0, 1.7, 0), leg + V(0, 0.35, 0), 0.38, a)
		egg(b, "Hoof", V(0.45, 0.25, 0.55), CF(leg.X, 0.12, leg.Z), darker(a, 0.4))
	end
	box(b, "Fridge", V(1.8, 2.0, 2.4), CF(0, 2.8, 0.05), c)
	box(b, "FridgeDoor", V(1.86, 1.0, 0.12), CF(0, 3.1, -1.22), lighter(c, 0.1))
	capsule(b, "Handle", V(0.65, 2.7, -1.32), V(0.65, 3.45, -1.32), 0.12, Color3.fromRGB(170, 175, 185), Enum.Material.Metal)
	for _, magnet in { { At = V(-0.4, 3.35, -1.3), Color = Color3.fromRGB(255, 90, 90) }, { At = V(0.1, 2.85, -1.3), Color = Color3.fromRGB(90, 180, 255) }, { At = V(-0.2, 2.45, -1.3), Color = Color3.fromRGB(255, 220, 70) } } do
		ball(b, "Magnet", 0.22, magnet.At, magnet.Color, nil, true)
	end
	egg(b, "Hump", V(1.3, 0.9, 1.3), CF(0, 4.0, 0.3), a)
	tube(b, "Neck", { V(0, 3.4, -1.05), V(0, 4.1, -1.55), V(0, 4.65, -1.7) }, 0.6, a)
	egg(b, "Head", V(0.8, 0.75, 1.35), CF(0, 4.85, -2.0), a)
	egg(b, "Lips", V(0.65, 0.4, 0.45), CF(0, 4.6, -2.6), darker(a, 0.1))
	for _, side in { -1, 1 } do
		ball(b, "Ear", 0.28, V(side * 0.35, 5.2, -1.75), a)
		ball(b, "Eye", 0.3, V(side * 0.33, 5.0, -2.35), WHITE, nil, true)
		ball(b, "Pupil", 0.15, V(side * 0.35, 5.0, -2.5), BLACK, nil, true)
	end
	tube(b, "Tail", { V(0, 2.6, 1.3), V(0.1, 2.0, 1.45) }, 0.12, a)
	return 5.4
end

-- Rhino Toasterino: a rhino whose body is a shiny toaster popping toast.
designs.RhinoToasterino = function(b, c, a)
	local metal = Enum.Material.Metal
	local toast = Color3.fromRGB(215, 160, 90)
	for _, leg in { V(-0.7, 0, -0.5), V(0.7, 0, -0.5), V(-0.7, 0, 0.9), V(0.7, 0, 0.9) } do
		capsule(b, "Leg", leg + V(0, 1.0, 0), leg + V(0, 0.35, 0), 0.65, a)
	end
	box(b, "Toaster", V(2.0, 1.8, 2.6), CF(0, 2.0, 0.2), c, metal)
	for _, x in { -0.4, 0.4 } do
		box(b, "Slot", V(0.25, 0.1, 1.9), CF(x, 2.92, 0.2), darker(c, 0.6), metal)
		box(b, "Toast", V(0.18, 1.0, 1.6), CF(x, 3.3, 0.2), toast)
		box(b, "Crust", V(0.2, 0.2, 1.65), CF(x, 3.78, 0.2), darker(toast, 0.3))
	end
	box(b, "Lever", V(0.12, 0.25, 0.4), CF(1.06, 2.3, 0.6), BLACK)
	egg(b, "Head", V(1.4, 1.25, 1.5), CF(0, 2.25, -1.4), a)
	egg(b, "Snout", V(1.1, 0.85, 0.9), CF(0, 2.0, -1.95), a)
	cone(b, "Horn", V(0, 2.35, -2.2), 0.85, 0.5, 0.06, Color3.fromRGB(240, 235, 220))
	cone(b, "SmallHorn", V(0, 2.65, -1.75), 0.45, 0.32, 0.05, Color3.fromRGB(240, 235, 220))
	for _, side in { -1, 1 } do
		ball(b, "Eye", 0.34, V(side * 0.5, 2.55, -1.85), WHITE, nil, true)
		ball(b, "Pupil", 0.16, V(side * 0.54, 2.55, -2.0), BLACK, nil, true)
		cone(b, "Ear", V(side * 0.45, 2.8, -1.1), 0.4, 0.3, 0.05, a)
	end
	return 4.0
end

-- Cocofanto Elefanto: a coconut elephant with palm leaves on top.
designs.CocofantoElefanto = function(b, c, a)
	for _, leg in { V(-0.7, 0, -0.5), V(0.7, 0, -0.5), V(-0.7, 0, 0.8), V(0.7, 0, 0.8) } do
		capsule(b, "Leg", leg + V(0, 1.2, 0), leg + V(0, 0.4, 0), 0.7, a)
		egg(b, "Toenails", V(0.6, 0.2, 0.3), CF(leg.X, 0.2, leg.Z - 0.32), Color3.fromRGB(240, 235, 220))
	end
	ball(b, "Coconut", 2.8, V(0, 2.35, 0.15), c)
	for k = 0, 11 do
		local angle = rad(k * 30)
		egg(b, "Fiber", V(0.08, 2.0, 0.08), CF(math.cos(angle) * 1.38, 2.3, 0.15 + math.sin(angle) * 1.38) * ANG(0, -angle, rad(8)), darker(c, 0.25))
	end
	local head = V(0, 3.0, -1.35)
	ball(b, "Head", 1.5, head, a)
	for _, side in { -1, 1 } do
		egg(b, "Ear", V(0.22, 1.6, 1.3), CF(head + V(side * 0.85, 0, 0.3)) * ANG(0, side * rad(-25), 0), a)
		egg(b, "EarInner", V(0.1, 1.15, 0.9), CF(head + V(side * 0.83, 0, 0.15)) * ANG(0, side * rad(-25), 0), Color3.fromRGB(240, 170, 180))
		cone(b, "Tusk", head + V(side * 0.32, -0.7, -0.55), 0.45, 0.17, 0.03, WHITE)
	end
	tube(b, "Trunk", { head + V(0, -0.25, -0.7), head + V(0, -0.85, -0.9), head + V(0.1, -1.45, -0.85), head + V(0.35, -1.65, -0.6) }, 0.45, a)
	eyes(b, 0, head.Y + 0.2, head.Z - 0.62, 0.34, 0.4)
	for k = 0, 4 do
		local angle = rad(k * 72)
		egg(b, "PalmLeaf", V(0.4, 0.1, 1.5), CF(0, 3.75, 0.2) * ANG(0, angle, 0) * CF(0, 0, -0.65) * ANG(rad(25), 0, 0), Color3.fromRGB(60, 170, 70))
	end
	return 4.4
end

-- La Vacca Saturno Saturnita: a cosmic cow planet with Saturn's rings.
designs.LaVaccaSaturnita = function(b, c, a)
	local spot = Color3.fromRGB(30, 30, 35)
	for _, leg in { V(-0.6, 0, -0.5), V(0.6, 0, -0.5), V(-0.6, 0, 0.6), V(0.6, 0, 0.6) } do
		capsule(b, "Leg", leg + V(0, 1.3, 0), leg + V(0, 0.4, 0), 0.4, c)
		egg(b, "Hoof", V(0.45, 0.25, 0.5), CF(leg.X, 0.12, leg.Z), spot)
	end
	ball(b, "Planet", 3.0, V(0, 2.8, 0), c)
	for _, s in { V(-0.9, 3.6, -0.95), V(1.0, 2.4, -0.9), V(0.3, 3.9, 0.9), V(-1.1, 2.1, 0.6), V(0.7, 3.2, -1.2) } do
		egg(b, "Spot", V(0.75, 0.6, 0.2), CF(s) * CFrame.lookAt(Vector3.zero, s - V(0, 2.8, 0)).Rotation, spot, nil, true)
	end
	local ring = CF(0, 2.8, 0) * ANG(rad(15), 0, rad(-18))
	for k = 0, 23 do
		local angle = rad(k * 15)
		egg(b, "Ring", V(0.66, 0.08, 0.5), ring * ANG(0, -angle, 0) * CF(0, 0, -2.35), if k % 2 == 0 then a else lighter(a, 0.25))
	end
	local head = V(0, 3.0, -1.55)
	egg(b, "Head", V(1.4, 1.3, 1.2), CF(head), c)
	egg(b, "Muzzle", V(1.1, 0.65, 0.5), CF(head + V(0, -0.35, -0.5)), Color3.fromRGB(255, 180, 190))
	for _, side in { -1, 1 } do
		ball(b, "Nostril", 0.14, head + V(side * 0.22, -0.32, -0.75), darker(Color3.fromRGB(255, 180, 190), 0.4), nil, true)
		cone(b, "Horn", head + V(side * 0.45, 0.5, 0.1), 0.45, 0.2, 0.04, Color3.fromRGB(240, 230, 200))
		egg(b, "Ear", V(0.55, 0.22, 0.3), CF(head + V(side * 0.8, 0.25, 0.1)) * ANG(0, 0, side * rad(-20)), c)
	end
	eyes(b, 0, head.Y + 0.15, head.Z - 0.5, 0.3, 0.38)
	vcyl(b, "Bell", 0.4, 0.4, head + V(0, -0.9, -0.2), Color3.fromRGB(255, 200, 60), Enum.Material.Foil)
	for _, star in { V(-1.9, 4.5, 0), V(1.8, 4.8, 0.4), V(2.2, 1.6, -0.5), V(-2.1, 1.8, 0.6) } do
		ball(b, "Star", 0.22, star, Color3.fromRGB(255, 245, 180), Enum.Material.Neon, true)
	end
	return 5.0
end

-- Trenostruzzo Turbo 3000: an ostrich-locomotive hybrid.
designs.TrenostruzzoTurbo = function(b, c, a)
	local metal = Enum.Material.Metal
	for _, side in { -1, 1 } do
		for _, z in { -0.6, 0.6, 1.6 } do
			zcyl(b, "Wheel", 0.3, 1.0, V(side * 0.95, 0.5, z), BLACK)
			zcyl(b, "WheelHub", 0.32, 0.4, V(side * 1.0, 0.5, z), Color3.fromRGB(230, 40, 40))
		end
		capsule(b, "Rod", V(side * 1.05, 0.5, -0.6), V(side * 1.05, 0.5, 1.6), 0.1, Color3.fromRGB(190, 190, 200), metal)
	end
	box(b, "Chassis", V(1.8, 0.5, 3.2), CF(0, 1.05, 0.5), darker(c, 0.4))
	cyl(b, "Boiler", 2.4, 1.6, CF(0, 2.0, -0.1) * ANG(0, rad(90), 0), c, metal)
	box(b, "Cab", V(1.9, 1.8, 1.3), CF(0, 2.2, 1.6), a)
	box(b, "CabRoof", V(2.1, 0.2, 1.5), CF(0, 3.2, 1.6), darker(a, 0.3))
	box(b, "CabWindow", V(1.95, 0.6, 0.6), CF(0, 2.6, 1.6), Color3.fromRGB(150, 210, 255), Enum.Material.Glass)
	vcyl(b, "Chimney", 0.9, 0.5, V(0, 3.0, -0.6), BLACK)
	for k = 0, 2 do
		local puff = ball(b, "Smoke", 0.6 + k * 0.2, V(0.1 * k, 3.75 + k * 0.45, -0.6 + k * 0.3), Color3.fromRGB(230, 230, 235), nil, true)
		puff.Transparency = 0.35
	end
	-- The ostrich part: neck and head out the front
	tube(b, "Neck", { V(0, 2.4, -1.35), V(0, 3.3, -1.6), V(0, 4.1, -1.7) }, 0.4, Color3.fromRGB(240, 200, 190))
	ball(b, "Head", 0.75, V(0, 4.35, -1.75), Color3.fromRGB(240, 200, 190))
	egg(b, "Beak", V(0.35, 0.22, 0.6), CF(0, 4.25, -2.2), Color3.fromRGB(240, 180, 90))
	for _, side in { -1, 1 } do
		ball(b, "Eye", 0.28, V(side * 0.27, 4.45, -2.0), WHITE, nil, true)
		ball(b, "Pupil", 0.14, V(side * 0.3, 4.45, -2.12), BLACK, nil, true)
	end
	for k = 0, 4 do
		egg(b, "Feather", V(0.3, 0.9, 0.2), CF((k - 2) * 0.32, 3.4, 2.35) * ANG(rad(-30), 0, (k - 2) * rad(-14)), Color3.fromRGB(40, 40, 45))
	end
	cone(b, "Headlight", V(0, 1.65, -1.35), 0.3, 0.55, 0.35, Color3.fromRGB(255, 240, 160), Enum.Material.Neon, true)
	return 4.8
end

-- Graipuss Medussi: a jellyfish whose bell is a bunch of grapes.
designs.GraipussMedussi = function(b, c, a)
	local float = 1.6
	for row = 0, 3 do
		local r = 1.3 - row * 0.3
		local count = 10 - row * 2
		for k = 0, count - 1 do
			local angle = rad(k * 360 / count + row * 15)
			ball(b, "Grape", 0.75, V(math.cos(angle) * r, float + 1.6 + row * 0.45, math.sin(angle) * r), if (k + row) % 3 == 0 then lighter(c, 0.2) else c)
		end
	end
	ball(b, "GrapeTop", 0.8, V(0, float + 3.4, 0), c)
	capsule(b, "Stem", V(0, float + 3.75, 0), V(0.15, float + 4.2, 0.05), 0.15, Color3.fromRGB(110, 80, 50))
	egg(b, "VineLeaf", V(0.8, 0.1, 0.6), CF(0.45, float + 4.1, 0.1) * ANG(0, 0, rad(-20)), Color3.fromRGB(80, 170, 70))
	egg(b, "Bell", V(2.4, 1.5, 2.4), CF(0, float + 2.1, 0), lighter(c, 0.1))
	for k = 0, 7 do
		local angle = rad(k * 45)
		local base = V(math.cos(angle) * 0.85, float + 1.4, math.sin(angle) * 0.85)
		tube(b, "Tentacle", { base, base + V(math.cos(angle) * 0.2, -0.8, math.sin(angle) * 0.2), base + V(math.cos(angle) * 0.05, -1.5, math.sin(angle) * 0.05) }, 0.14, a, Enum.Material.Neon)
	end
	eyes(b, 0, float + 2.25, -1.15, 0.4, 0.5)
	smile(b, 0, float + 1.75, -1.15, 0.4)
	blush(b, 0, float + 1.95, -1.12, 0.75)
	return float + 4.4
end

-- La Grande Combinasion: the grand combination, a totem of legends.
designs.LaGrandeCombinasion = function(b, c, a)
	local gold = Color3.fromRGB(255, 200, 50)
	local wood = Color3.fromRGB(176, 120, 72)
	local shark = Color3.fromRGB(110, 140, 180)
	local croc = Color3.fromRGB(80, 150, 70)
	-- Bottom: the wooden log, legs and a bat
	legs(b, wood, 1.0, 0.6)
	vcyl(b, "Log", 1.8, 2.0, V(0, 1.9, 0), wood, Enum.Material.Wood)
	eyes(b, 0, 2.2, -0.95, 0.4, 0.48)
	egg(b, "Grin", V(0.9, 0.3, 0.2), CF(0, 1.6, -1.0), Color3.fromRGB(60, 20, 20), nil, true)
	capsule(b, "Bat", V(1.3, 1.2, -0.3), V(1.6, 3.0, -0.4), 0.28, Color3.fromRGB(215, 175, 110), Enum.Material.Wood)
	-- Middle: the shark with fins
	egg(b, "Shark", V(2.2, 1.6, 2.3), CF(0, 3.55, 0), shark)
	egg(b, "SharkBelly", V(1.6, 1.0, 0.6), CF(0, 3.4, -0.9), WHITE)
	for _, side in { -1, 1 } do
		egg(b, "Fin", V(1.0, 0.18, 0.6), CF(side * 1.15, 3.4, -0.1) * ANG(0, 0, side * rad(-30)), shark)
	end
	for k = -2, 2 do
		cone(b, "SharkTooth", V(k * 0.2, 3.1, -1.1), 0.2, 0.13, 0.02, WHITE, nil, true)
	end
	-- Top: the crocodile bomber head with wings
	egg(b, "Croc", V(1.6, 1.1, 1.8), CF(0, 4.85, -0.1), croc)
	egg(b, "CrocSnout", V(1.0, 0.5, 1.2), CF(0, 4.7, -1.0), croc)
	for _, side in { -1, 1 } do
		box(b, "Wing", V(1.8, 0.14, 0.9), CF(side * 1.6, 4.8, 0.1) * ANG(0, 0, side * rad(10)), Color3.fromRGB(150, 155, 165), Enum.Material.Metal)
		ball(b, "CrocEye", 0.32, V(side * 0.35, 5.35, -0.55), WHITE, nil, true)
		ball(b, "CrocPupil", 0.15, V(side * 0.37, 5.35, -0.7), BLACK, nil, true)
	end
	-- Crown and golden aura
	vcyl(b, "CrownBand", 0.35, 1.2, V(0, 5.55, 0), gold, Enum.Material.Foil, true)
	for k = 0, 4 do
		local angle = rad(k * 72)
		cone(b, "CrownPoint", V(math.cos(angle) * 0.47, 5.7, math.sin(angle) * 0.47), 0.5, 0.3, 0.05, gold, Enum.Material.Foil, true)
	end
	ball(b, "CrownGem", 0.3, V(0, 5.6, -0.6), Color3.fromRGB(230, 40, 60), Enum.Material.Neon, true)
	for k = 0, 11 do
		local angle = rad(k * 30)
		local sparkle = ball(b, "Aura", 0.25, V(math.cos(angle) * 1.9, 1.0 + (k % 4) * 1.3, math.sin(angle) * 1.9), gold, Enum.Material.Neon, true)
		sparkle.Transparency = 0.2
	end
	return 6.3
end

local MIRRORED = { SixSeven = true, BallerinaCapuchina = true }

-- Fallback for brainrots without a design yet.
local function blob(b: Builder, c: Color3, a: Color3): number
	legs(b, a, 1.0, 0.7)
	ball(b, "Body", 3, V(0, 2.5, 0), c)
	eyes(b, 0, 2.85, -1.25, 0.45, 0.9)
	egg(b, "HatBrim", V(2.0, 0.22, 2.0), CF(0, 3.95, 0), a)
	vcyl(b, "Hat", 0.8, 1.3, V(0, 4.35, 0), a)
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

-- `secondary`: one of the commoner mutations in a stack. Only the rarest
-- recolors the brainrot and gets the big rarity effects; the others add
-- their particles and sparkles on top.
local function applyMutation(model: Model, root: BasePart, mutation: Config.Mutation, scale: number, mini: boolean?, secondary: boolean?)
	local i = 0
	local recolor: { Instance } = if secondary then {} else model:GetDescendants()
	for _, d in recolor do
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
			elseif mutation.Id == "Candy" then
				-- Pastel candy colors, alternating part by part.
				local candy = { Color3.fromRGB(255, 170, 210), Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 225, 255), Color3.fromRGB(255, 230, 150) }
				d.Color = candy[(i - 1) % #candy + 1]
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0.1
			elseif mutation.Id == "Frozen" then
				d.Color = d.Color:Lerp(Color3.fromRGB(175, 225, 255), 0.6)
				d.Material = Enum.Material.Ice
			elseif mutation.Id == "Electric" then
				d.Color = d.Color:Lerp(Color3.fromRGB(255, 225, 70), 0.45)
				d.Reflectance = 0.2
			elseif mutation.Id == "Smiley" then
				-- Sunny smiley-face yellow over its own colors.
				d.Color = d.Color:Lerp(Color3.fromRGB(255, 215, 50), 0.5)
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0.1
			elseif mutation.Id == "Radioactive" then
				d.Color = d.Color:Lerp(Color3.fromRGB(110, 255, 80), 0.55)
				-- A few glowing spots, not the whole body (keeps it easy on the eyes).
				d.Material = if i % 5 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
			elseif mutation.Id == "Galaxy" then
				d.Color = d.Color:Lerp(Color3.fromRGB(35, 20, 85), 0.75)
				d.Material = Enum.Material.Glass
				d.Reflectance = 0.3
			elseif mutation.Id == "Cursed" then
				d.Color = d.Color:Lerp(Color3.fromRGB(55, 8, 15), 0.7)
				d.Material = Enum.Material.Slate
			elseif mutation.Id == "Void" then
				d.Color = Color3.fromRGB(12, 8, 20)
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0.05
			elseif mutation.Id == "Divine" then
				d.Color = d.Color:Lerp(Color3.fromRGB(255, 250, 232), 0.6)
				d.Material = Enum.Material.Marble
				d.Reflectance = 0.15
			elseif mutation.Id == "Magic" then
				-- Keeps its look, tinted purple; Effects.client shimmers it to teal.
				d:SetAttribute("BaseColor", d.Color)
				d.Color = d.Color:Lerp(Color3.fromRGB(170, 110, 255), 0.35)
				d.Reflectance = 0.15
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
	if mutation.Id == "Rainbow" and not secondary then
		CollectionService:AddTag(model, "RainbowBrainrot")
	end

	-- Particle looks for the newer mutations.
	local function emitter(name: string, colors: { Color3 }, rate: number, speed: number, size: number, lifetime: number, accel: Vector3?): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		local keys = {}
		for k, c in colors do
			table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (k - 1) / (#colors - 1), c))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
		end
		e.Color = ColorSequence.new(keys)
		e.Rate = rate
		e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
		-- (Roblox errors if min > max, e.g. for the Void mist's inward speed.)
		e.Speed = NumberRange.new(math.min(speed * 0.5, speed), math.max(speed * 0.5, speed))
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		e.Acceleration = accel or Vector3.zero
		e.Parent = root
		return e
	end
	local function smoke(color: Color3, opacity: number)
		local sm = Instance.new("Smoke")
		sm.Color = color
		sm.Opacity = opacity
		sm.RiseVelocity = 1.5
		sm.Size = 1.5 * scale
		sm.Parent = root
	end
	if mutation.Id == "Candy" then
		emitter("Sprinkles", { Color3.fromRGB(255, 120, 180), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 230, 90) }, 10, 2, 0.35, 1.2)
	elseif mutation.Id == "Frozen" then
		emitter("Snowflakes", { Color3.new(1, 1, 1), Color3.fromRGB(190, 230, 255) }, 10, 0.6, 0.35, 2.5, Vector3.new(0, -1.5, 0))
	elseif mutation.Id == "Electric" then
		emitter("Sparks", { Color3.fromRGB(255, 250, 160), Color3.fromRGB(120, 200, 255) }, 30, 8, 0.3, 0.25).LightEmission = 1
	elseif mutation.Id == "Radioactive" then
		smoke(Color3.fromRGB(110, 255, 80), 0.08)
		emitter("Glow", { Color3.fromRGB(150, 255, 100) }, 8, 1, 0.4, 1.5, Vector3.new(0, 1, 0))
	elseif mutation.Id == "Galaxy" then
		emitter("Stars", { Color3.new(1, 1, 1), Color3.fromRGB(170, 130, 255), Color3.fromRGB(110, 190, 255) }, 18, 0.5, 0.3, 3).LightEmission = 1
	elseif mutation.Id == "Cursed" then
		smoke(Color3.fromRGB(40, 0, 5), 0.25)
		emitter("Embers", { Color3.fromRGB(255, 40, 40), Color3.fromRGB(80, 0, 0) }, 8, 1.5, 0.3, 1.5, Vector3.new(0, 1.5, 0))
	elseif mutation.Id == "Void" then
		-- Dark matter drifting in, with a faint purple outline.
		emitter("VoidMist", { Color3.fromRGB(120, 60, 220), Color3.fromRGB(10, 5, 20) }, 25, -2, 0.6, 1.5)
		local outline = Instance.new("Highlight")
		outline.FillTransparency = 1
		outline.OutlineColor = Color3.fromRGB(140, 80, 255)
		outline.Parent = model
	elseif mutation.Id == "Divine" then
		emitter("HolyLight", { Color3.fromRGB(255, 245, 200), Color3.fromRGB(255, 215, 120) }, 14, 1.2, 0.4, 2, Vector3.new(0, 2, 0)).LightEmission = 1
		-- A golden halo floating above its head.
		local _, size = model:GetBoundingBox()
		local halo = Instance.new("Part")
		halo.Name = "Halo"
		halo.Shape = Enum.PartType.Cylinder
		halo.Size = V(0.15, 1.6 * scale, 1.6 * scale)
		halo.Color = Color3.fromRGB(255, 215, 90)
		halo.Material = Enum.Material.Neon
		halo.Anchored = false
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CanTouch = false
		halo.Massless = true
		halo.CFrame = root.CFrame * CF(0, size.Y - 0.2 * scale, 0) * ANG(0, 0, rad(90))
		halo:SetAttribute("Keep", true)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = halo
		weld.Parent = halo
		halo.Parent = model
	end
	if mutation.Id == "Magic" then
		CollectionService:AddTag(model, "MagicBrainrot")
		-- Swirling magic stars and a ring of floating orbs.
		local swirl = Instance.new("ParticleEmitter")
		swirl.Name = "MagicSwirl"
		swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		swirl.Color = ColorSequence.new(Color3.fromRGB(190, 130, 255), Color3.fromRGB(90, 230, 255))
		swirl.LightEmission = 0.6
		swirl.Rate = 22
		swirl.Lifetime = NumberRange.new(1, 1.8)
		swirl.Speed = NumberRange.new(0.5, 1.5)
		swirl.RotSpeed = NumberRange.new(-180, 180)
		swirl.SpreadAngle = Vector2.new(180, 180)
		swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 0) })
		swirl.Parent = root
		for k = 1, 6 do
			local angle = k * math.pi / 3
			local orb = Instance.new("Part")
			orb.Name = "MagicOrb"
			orb.Shape = Enum.PartType.Ball
			orb.Size = V(0.35, 0.35, 0.35) * scale
			orb.Material = Enum.Material.Neon
			orb.Color = if k % 2 == 0 then Color3.fromRGB(190, 130, 255) else Color3.fromRGB(110, 230, 255)
			orb.Anchored = false
			orb.CanCollide = false
			orb.CanQuery = false
			orb.CanTouch = false
			orb.Massless = true
			orb.CFrame = root.CFrame * CF(math.cos(angle) * 2.2 * scale, 2.5 * scale + math.sin(angle * 2) * 0.4, math.sin(angle) * 2.2 * scale)
			orb:SetAttribute("Keep", true)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = orb
			weld.Parent = orb
			orb.Parent = model
		end
	end
	if mutation.Id == "Smiley" then
		-- Little yellow smiley faces floating around it, and more drifting up.
		local face = "rbxasset://textures/face.png"
		local floaters = Instance.new("ParticleEmitter")
		floaters.Name = "SmileyFaces"
		floaters.Texture = face
		floaters.Rate = 3
		floaters.Lifetime = NumberRange.new(1.5, 2.5)
		floaters.Speed = NumberRange.new(1, 2)
		floaters.SpreadAngle = Vector2.new(40, 40)
		floaters.EmissionDirection = Enum.NormalId.Top
		floaters.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.7 * scale), NumberSequenceKeypoint.new(1, 0) })
		floaters.Parent = root
		local _, size = model:GetBoundingBox()
		for k = 1, 4 do
			local angle = k * math.pi / 2 + math.pi / 4
			local ball = Instance.new("Part")
			ball.Name = "SmileyBall"
			ball.Shape = Enum.PartType.Ball
			ball.Size = V(0.9, 0.9, 0.9) * scale
			ball.Color = Color3.fromRGB(255, 215, 50)
			ball.Material = Enum.Material.SmoothPlastic
			ball.Anchored = false
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.Massless = true
			-- Each one faces outward so its smile shows.
			local position = Vector3.new(math.cos(angle) * 2 * scale, size.Y * 0.6 + (k % 2) * 0.5 * scale, math.sin(angle) * 2 * scale)
			ball.CFrame = root.CFrame * CFrame.lookAt(position, position * 2 - Vector3.new(0, position.Y, 0))
			ball:SetAttribute("Keep", true)
			local decal = Instance.new("Decal")
			decal.Texture = face
			decal.Face = Enum.NormalId.Front
			decal.Parent = ball
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = ball
			weld.Parent = ball
			ball.Parent = model
		end
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

	-- The rarer the mutation, the bigger the show: 1 = common (Gold..Smiley),
	-- 2 = rare (Radioactive..Cursed), 3 = ultra rare (Rainbow, Void, Divine),
	-- 4 = Magic (Cigna Glamourina only). Mini followers keep it simple.
	local tier = if mini or secondary then 1 elseif mutation.Chance <= 0 then 4 elseif mutation.Chance <= 0.3 then 3 elseif mutation.Chance <= 0.9 then 2 else 1
	local _, bounds = model:GetBoundingBox()
	local height = bounds.Y

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "MutationSparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(mutation.Color)
	sparkles.Rate = 8 * tier
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.3 + 0.08 * tier)
	sparkles.Parent = root

	if not secondary then
		local light = Instance.new("PointLight")
		light.Color = mutation.Color
		light.Range = 8 * scale * (1 + 0.3 * (tier - 1))
		light.Brightness = 1.5 + 0.4 * (tier - 1)
		light.Parent = root
	end

	-- A glowing (non-colliding) decoration welded to the model; mutations
	-- don't recolor it.
	local function glow(name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, transparency: number): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Neon
		p.Transparency = transparency
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = root.CFrame * CF(0, -0.5, 0) * offset
		p:SetAttribute("Keep", true)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
	-- A flat ring on the ground, built from short neon segments.
	local function groundRing(name: string, radius: number, color: Color3, transparency: number, y: number?)
		local segments = 24
		for k = 0, segments - 1 do
			local angle = k / segments * math.pi * 2
			local length = radius * 2 * math.pi / segments * 1.08
			glow(name, Enum.PartType.Block, V(length, 0.06, 0.16 * scale), CF(0, y or 0.05, 0) * ANG(0, -angle, 0) * CF(0, 0, -radius), color, transparency)
		end
	end

	-- Rare and up: a glowing aura ring on the ground and motes drifting up.
	if tier >= 2 then
		groundRing("AuraRing", 2.2 * scale, mutation.Color, 0.35)
		local motes = emitter("AuraMotes", { mutation.Color, Color3.new(1, 1, 1) }, 6 * tier, 1.5, 0.25, 2, Vector3.new(0, 2.5, 0))
		motes.EmissionDirection = Enum.NormalId.Top
		motes.SpreadAngle = Vector2.new(25, 25)
		motes.LightEmission = 0.8
	end
	-- Ultra rare and up: a second ring, a column of light rising through it
	-- and a beam of sparkles shooting out of the top.
	if tier >= 3 then
		groundRing("AuraRing", 2.9 * scale, mutation.Color:Lerp(Color3.new(1, 1, 1), 0.4), 0.55)
		local column = Instance.new("ParticleEmitter")
		column.Name = "AuraColumn"
		column.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		column.Color = ColorSequence.new(mutation.Color, Color3.new(1, 1, 1))
		column.LightEmission = 1
		column.Rate = 20
		column.Lifetime = NumberRange.new(1.2, 1.8)
		column.Speed = NumberRange.new(height * 0.7, height)
		column.SpreadAngle = Vector2.new(6, 6)
		column.EmissionDirection = Enum.NormalId.Top
		column.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		column.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(1, 0) })
		column.Parent = root
		local crown = emitter("AuraCrown", { mutation.Color, Color3.new(1, 1, 1) }, 18, 4, 0.35, 0.8)
		crown.LightEmission = 1
		crown.EmissionDirection = Enum.NormalId.Top
		crown.SpreadAngle = Vector2.new(35, 35)
		local attachment = Instance.new("Attachment")
		attachment.Position = V(0, height, 0)
		attachment.Parent = root
		crown.Parent = attachment
	end
	-- Magic (Cigna Glamourina only): the full spell. A two-ring magic circle
	-- with glowing runes, drifting pink glitter, a fountain of pink and teal stars
	-- and a second, higher ring of orbs.
	if tier >= 4 then
		local pink = Color3.fromRGB(255, 120, 220)
		local teal = Color3.fromRGB(90, 230, 255)
		local radius = 3.4 * scale
		groundRing("MagicCircle", radius, pink, 0.2, 0.08)
		groundRing("MagicCircle", radius * 0.72, teal, 0.3, 0.08)
		for k = 0, 7 do
			local angle = k / 8 * math.pi * 2
			glow("MagicRune", Enum.PartType.Block, V(0.35, 0.08, 0.35) * scale, CF(math.cos(angle) * radius * 0.86, 0.1, math.sin(angle) * radius * 0.86) * ANG(0, angle + math.pi / 4, 0), if k % 2 == 0 then pink else teal, 0.1)
		end
		-- A star in the middle of the circle: two crossing squares.
		for _, turn in { 0, 45 } do
			glow("MagicStar", Enum.PartType.Block, V(radius * 0.7, 0.05, radius * 0.7), CF(0, 0.07, 0) * ANG(0, rad(turn), 0), pink:Lerp(teal, 0.5), 0.75)
		end
		for k = 1, 6 do
			local angle = k * math.pi / 3 + math.pi / 6
			glow("MagicOrb", Enum.PartType.Ball, V(0.28, 0.28, 0.28) * scale, CF(math.cos(angle) * 1.6 * scale, height * 0.95, math.sin(angle) * 1.6 * scale), if k % 2 == 0 then pink else teal, 0)
		end
		local glitter = Instance.new("ParticleEmitter")
		glitter.Name = "MagicGlitter"
		glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		glitter.Color = ColorSequence.new(pink, Color3.fromRGB(255, 200, 240))
		glitter.LightEmission = 0.7
		glitter.Rate = 6
		glitter.Lifetime = NumberRange.new(2, 3)
		glitter.Speed = NumberRange.new(1, 2)
		glitter.SpreadAngle = Vector2.new(30, 30)
		glitter.EmissionDirection = Enum.NormalId.Top
		glitter.RotSpeed = NumberRange.new(-60, 60)
		glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.8 * scale), NumberSequenceKeypoint.new(1, 0) })
		glitter.Parent = root
		local fountain = emitter("MagicFountain", { pink, Color3.new(1, 1, 1), teal }, 30, 9, 0.3, 1.6, Vector3.new(0, -9, 0))
		fountain.LightEmission = 1
		fountain.EmissionDirection = Enum.NormalId.Top
		fountain.SpreadAngle = Vector2.new(30, 30)
	end
end

-- Name tag -----------------------------------------------------------------

-- Name tags are sized in studs (not pixels), so they shrink with distance
-- like real signs instead of covering the screen when you zoom out.
-- (A little bigger than strictly needed, so they stay readable zoomed all the way out.)
local TAG_STUDS_PER_ROW_UNIT = 0.036 -- a 26-unit name row is ~0.95 studs tall
local TAG_WIDTH = 7.2

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
function BrainrotModel.Create(brainrot: Config.Brainrot, mutationId: string?, cframe: CFrame, priceTag: boolean, serial: number?, mini: boolean?, scaleOverride: number?): Model
	local rarity = Config.Rarities[brainrot.Rarity]
	local mutation = Config.GetMutation(mutationId)
	local s = scaleOverride or (if mini then 0.4 else (brainrot.Scale or rarity.Scale))

	local model = Instance.new("Model")
	model.Name = brainrot.Id
	model:SetAttribute("BrainrotId", brainrot.Id)
	model:SetAttribute("Mutation", Config.JoinMutations(if mutationId then { mutationId } else {}))
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
		local builder = newBuilder(model, root, s)
		builder.mirror = MIRRORED[brainrot.Id]
		height = design(builder, brainrot.Color, brainrot.Accent)
	end
	local topY = (height :: number) * s

	if mini then
		for _, m in Config.SplitMutations(mutationId) do
			applyMutation(model, root, m, s, true, m ~= mutation)
		end
		if mutation then
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
	-- Celestial: a ring of golden stars over the head, and drifting starlight.
	if brainrot.Rarity == "Celestial" then
		local halo = newBuilder(model, root, 1)
		local radius = 0.45 * s
		for k = 0, 11 do
			local angle = k * math.pi / 6
			local d = if k % 2 == 0 then 0.28 * s else 0.16 * s
			ball(halo, "Halo", d, V(math.cos(angle) * radius, topY + 0.35 * s, math.sin(angle) * radius), Color3.fromRGB(255, 220, 110), Enum.Material.Neon, true)
		end
		local starlight = Instance.new("ParticleEmitter")
		starlight.Name = "Starlight"
		starlight.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		starlight.Color = ColorSequence.new(Color3.fromRGB(255, 225, 130), rarity.Color)
		starlight.LightEmission = 1
		starlight.Rate = 8
		starlight.Lifetime = NumberRange.new(1.5, 2.5)
		starlight.Speed = NumberRange.new(0.5, 1.5)
		starlight.SpreadAngle = Vector2.new(180, 180)
		starlight.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 0) })
		starlight.Parent = root
	end
	-- Commoner mutations of a stack first, so the rarest one leads the look.
	for _, m in Config.SplitMutations(mutationId) do
		applyMutation(model, root, m, s, false, m ~= mutation)
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
		local bonus = 0
		for _, m in Config.SplitMutations(mutationId) do
			bonus += Config.MutationBonus(m)
		end
		label(tag, "Mutation", string.format("%s  +%d%%", string.upper(Config.MutationLabel(mutationId)), bonus), mutation.Color, 22, 0)
	end
	local rarityColor = if brainrot.Rarity == "Secret" then Color3.fromRGB(255, 120, 255) else rarity.Color
	label(tag, "Rarity", string.upper(rarity.DisplayName), rarityColor, 18, 1)
	label(tag, "Name", brainrot.DisplayName, WHITE, 26, 2)
	label(tag, "Income", Config.FormatCash(Config.IncomeOf(brainrot, mutationId)) .. "/s", Color3.fromRGB(120, 255, 120), 20, 3)
	if priceTag then
		local price = Config.PriceOf(brainrot, mutationId)
		label(tag, "Price", if price <= 0 then "FREE" else Config.FormatCash(price), Color3.fromRGB(255, 220, 80), 22, 4)
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

--!strict
-- Natural scenery for courses: the terrain landscape under and around the holes
-- (ground, dirt paths, ponds, rolling hills) and crafted props per biome (trees,
-- bushes, flowers, rocks, windmills, cacti, snowmen, palms, ruins...). Props are
-- decoration only: never collide, never hit by raycasts. Every terrain fill is
-- recorded so the course can clear exactly what it made.

local Parts = require(script.Parent:WaitForChild("Parts"))

local CourseNature = {}

export type Region = { CFrame: CFrame, Size: Vector3 }
export type Biome = {
	Ground: Enum.Material,
	GroundAlt: Enum.Material,
	Hill: Enum.Material,
	Rock: Enum.Material,
	Water: boolean, -- ponds / lagoon
	Path: Enum.Material?, -- dirt path along the course
}
export type Kind = { Name: string, Weight: number, Radius: number }

local WHITE = Color3.new(1, 1, 1)
local BARK = Color3.fromRGB(110, 76, 48)

CourseNature.Biomes = {
	Meadow = { Ground = Enum.Material.Grass, GroundAlt = Enum.Material.LeafyGrass, Hill = Enum.Material.Grass, Rock = Enum.Material.Rock, Water = true, Path = Enum.Material.Ground },
	Canyon = { Ground = Enum.Material.Sandstone, GroundAlt = Enum.Material.Sand, Hill = Enum.Material.Sandstone, Rock = Enum.Material.Sandstone, Water = false, Path = Enum.Material.Sand },
	Snow = { Ground = Enum.Material.Snow, GroundAlt = Enum.Material.Glacier, Hill = Enum.Material.Snow, Rock = Enum.Material.Rock, Water = false, Path = nil },
	Volcano = { Ground = Enum.Material.Basalt, GroundAlt = Enum.Material.CrackedLava, Hill = Enum.Material.Basalt, Rock = Enum.Material.Basalt, Water = false, Path = Enum.Material.Ground },
	Jungle = { Ground = Enum.Material.LeafyGrass, GroundAlt = Enum.Material.Mud, Hill = Enum.Material.LeafyGrass, Rock = Enum.Material.Slate, Water = true, Path = Enum.Material.Mud },
	Tropical = { Ground = Enum.Material.Sand, GroundAlt = Enum.Material.Grass, Hill = Enum.Material.Grass, Rock = Enum.Material.Rock, Water = true, Path = Enum.Material.Sand },
	Ocean = { Ground = Enum.Material.Sand, GroundAlt = Enum.Material.Sand, Hill = Enum.Material.Sand, Rock = Enum.Material.Rock, Water = true, Path = nil },
} :: { [string]: Biome }

CourseNature.Kinds = {
	Meadow = { { Name = "Oak", Weight = 4, Radius = 6 }, { Name = "Bush", Weight = 3, Radius = 3 }, { Name = "Flowers", Weight = 3, Radius = 3 }, { Name = "Rock", Weight = 1, Radius = 3 }, { Name = "Windmill", Weight = 1, Radius = 6 } },
	Canyon = { { Name = "Cactus", Weight = 4, Radius = 3 }, { Name = "Spire", Weight = 2, Radius = 6 }, { Name = "Rock", Weight = 2, Radius = 4 }, { Name = "DryBush", Weight = 2, Radius = 3 } },
	Snow = { { Name = "Pine", Weight = 5, Radius = 5 }, { Name = "Snowman", Weight = 1, Radius = 3 }, { Name = "Rock", Weight = 2, Radius = 3 }, { Name = "Crystal", Weight = 1, Radius = 3 } },
	Volcano = { { Name = "Basalt", Weight = 3, Radius = 5 }, { Name = "DeadTree", Weight = 2, Radius = 4 }, { Name = "LavaPool", Weight = 1, Radius = 6 }, { Name = "Vent", Weight = 1, Radius = 4 }, { Name = "Rock", Weight = 2, Radius = 3 } },
	Jungle = { { Name = "JungleTree", Weight = 4, Radius = 6 }, { Name = "Ruin", Weight = 2, Radius = 4 }, { Name = "Fern", Weight = 3, Radius = 3 }, { Name = "Idol", Weight = 1, Radius = 4 } },
	Tropical = { { Name = "Palm", Weight = 5, Radius = 4 }, { Name = "Umbrella", Weight = 1, Radius = 3 }, { Name = "Torch", Weight = 1, Radius = 2 }, { Name = "Rock", Weight = 1, Radius = 3 }, { Name = "Bush", Weight = 1, Radius = 3 } },
	Ocean = { { Name = "PalmIsle", Weight = 3, Radius = 7 }, { Name = "Buoy", Weight = 3, Radius = 2 }, { Name = "Boat", Weight = 2, Radius = 6 }, { Name = "SeaStack", Weight = 2, Radius = 4 }, { Name = "Lighthouse", Weight = 1, Radius = 7 } },
} :: { [string]: { Kind } }

-- Small props planted around the foot of every green.
CourseNature.Small = {
	Meadow = { "Bush", "Flowers", "Flowers", "Rock" },
	Canyon = { "DryBush", "Rock", "Cactus" },
	Snow = { "Rock", "Crystal", "Bush" },
	Volcano = { "Rock", "Basalt" },
	Jungle = { "Fern", "Fern", "Bush" },
	Tropical = { "Bush", "Rock", "Fern" },
	Ocean = { "Buoy", "Rock", "Buoy" },
} :: { [string]: { string } }

-- Trees used for the backdrop ring around each course.
CourseNature.Backdrop = { Meadow = "Oak", Canyon = "Spire", Snow = "Pine", Volcano = "Basalt", Jungle = "JungleTree", Tropical = "Palm", Ocean = "PalmIsle" } :: { [string]: string }

local function deco(color: Color3, material: Enum.Material?, transparency: number?): Parts.Props
	return { Name = "Decor", Color = color, Material = material, Transparency = transparency, CanCollide = false, CanQuery = false, CanTouch = false }
end

local function vary(c: Color3, rng: Random, amount: number): Color3
	local k = rng:NextNumber(-amount, amount)
	return c:Lerp(if k > 0 then WHITE else Color3.new(0, 0, 0), math.abs(k))
end

local function up(y: number): Vector3
	return Vector3.new(0, y, 0)
end

-- Terrain ----------------------------------------------------------------------------

local function fill(regions: { Region }, cf: CFrame, size: Vector3, material: Enum.Material)
	workspace.Terrain:FillBlock(cf, size, material)
	table.insert(regions, { CFrame = cf, Size = size })
end

local function fillBall(regions: { Region }, center: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(center, radius, material)
	table.insert(regions, { CFrame = CFrame.new(center), Size = Vector3.one * (radius * 2 + 4) })
end

local function fillCylinder(regions: { Region }, cf: CFrame, height: number, radius: number, material: Enum.Material)
	workspace.Terrain:FillCylinder(cf, height, radius, material)
	table.insert(regions, { CFrame = cf, Size = Vector3.new(radius * 2 + 4, height + 4, radius * 2 + 4) })
end

export type Area = { X0: number, X1: number, Z0: number, Z1: number, GroundY: number }

-- Ground slab under the whole course (top = GroundY), dirt path, patches, ponds and a
-- ring of hills beyond the play area. `avoid(x, z, r)` says if a spot is clear of holes.
function CourseNature.landscape(biomeId: string, area: Area, rng: Random, avoid: (number, number, number) -> boolean, keepClear: { Region }): { Region }
	local b = CourseNature.Biomes[biomeId] or CourseNature.Biomes.Meadow
	local regions: { Region } = {}
	local mx, mz = (area.X0 + area.X1) / 2, (area.Z0 + area.Z1) / 2
	local w, d = area.X1 - area.X0, area.Z1 - area.Z0
	local gy = area.GroundY
	local margin = 70
	if biomeId == "Ocean" then
		-- Open sea at the course's feet: a sand sea floor and water lapping just below the
		-- turf (the course lies on sand banks laid under every tile, see CourseBuilder),
		-- sand bars in clear spots and rocky islands on the horizon.
		fill(regions, CFrame.new(mx, gy - 9.5, mz), Vector3.new(w + margin * 2, 6, d + margin * 2), Enum.Material.Sand)
		fill(regions, CFrame.new(mx, gy - 3.5, mz), Vector3.new(w + margin * 2, 6, d + margin * 2), Enum.Material.Water)
		for _ = 1, 40 do
			local r = rng:NextNumber(5, 9)
			local x, z = rng:NextNumber(area.X0 - 30, area.X1 + 30), rng:NextNumber(area.Z0 - 30, area.Z1 + 30)
			if avoid(x, z, r + 6) and rng:NextNumber() < 0.3 then
				fillBall(regions, Vector3.new(x, gy - r * 0.82, z), r, Enum.Material.Sand)
			end
		end
		for x = area.X0 - 40, area.X1 + 40, 46 do
			for _, z in { area.Z0 - rng:NextNumber(40, 60), area.Z1 + rng:NextNumber(40, 60) } do
				if rng:NextNumber() < 0.6 then
					local r = rng:NextNumber(10, 18)
					fillBall(regions, Vector3.new(x + rng:NextNumber(-10, 10), gy - r * 0.4, z), r, Enum.Material.Rock)
					fillBall(regions, Vector3.new(x + rng:NextNumber(-6, 6), gy - r * 0.55, z + rng:NextNumber(-4, 4)), r * 0.8, Enum.Material.Grass)
				end
			end
		end
		for _, r in keepClear do
			workspace.Terrain:FillBlock(r.CFrame, r.Size, Enum.Material.Air)
		end
		return regions
	end
	fill(regions, CFrame.new(mx, gy - 3, mz), Vector3.new(w + margin * 2, 6, d + margin * 2), b.Ground)
	-- Patches of the second material break up the ground.
	for _ = 1, 14 do
		local sx, sz = rng:NextNumber(10, 26), rng:NextNumber(10, 26)
		local x, z = rng:NextNumber(area.X0 - 20, area.X1 + 20), rng:NextNumber(area.Z0 - 20, area.Z1 + 20)
		fill(regions, CFrame.new(x, gy - 0.9, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(sx, 1.4, sz), b.GroundAlt)
	end
	if b.Path then
		fill(regions, CFrame.new(mx, gy - 0.8, mz), Vector3.new(w + 20, 1.4, 7), b.Path)
	end
	-- Water: a lagoon along one side (tropical) or a few ponds in clear spots.
	if b.Water then
		if biomeId == "Tropical" then
			fill(regions, CFrame.new(mx, gy - 2.2, area.Z1 + 34), Vector3.new(w + margin * 2, 4, 44), Enum.Material.Water)
		else
			local made = 0
			for _ = 1, 30 do
				if made >= 3 then
					break
				end
				local r = rng:NextNumber(6, 10)
				local x, z = rng:NextNumber(area.X0 + r, area.X1 - r), rng:NextNumber(area.Z0 + r, area.Z1 - r)
				if avoid(x, z, r + 2) then
					fillCylinder(regions, CFrame.new(x, gy - 2, z), 3.4, r, Enum.Material.Water)
					made += 1
				end
			end
		end
	end
	-- Rolling hills (and the odd rock outcrop) in a ring beyond the play area.
	local step = 34
	for x = area.X0 - 40, area.X1 + 40, step do
		for _, z in { area.Z0 - rng:NextNumber(30, 55), area.Z1 + rng:NextNumber(30, 55) } do
			if not (biomeId == "Tropical" and z > mz) then
				local r = rng:NextNumber(18, 34)
				fillBall(regions, Vector3.new(x + rng:NextNumber(-8, 8), gy - r * 0.55, z), r, b.Hill)
				if rng:NextNumber() < 0.35 then
					fillBall(regions, Vector3.new(x + rng:NextNumber(-10, 10), gy + r * 0.25, z + rng:NextNumber(-6, 6)), rng:NextNumber(5, 9), b.Rock)
				end
			end
		end
	end
	for _, z in { mz - d * 0.3, mz + d * 0.3 } do
		for _, x in { area.X0 - rng:NextNumber(35, 55), area.X1 + rng:NextNumber(35, 55) } do
			local r = rng:NextNumber(22, 36)
			fillBall(regions, Vector3.new(x, gy - r * 0.55, z), r, b.Hill)
		end
	end
	if biomeId == "Volcano" then
		-- A smoking volcano on the horizon.
		for k = 0, 5 do
			local r = 46 - k * 7
			fillCylinder(regions, CFrame.new(area.X1 + 110, gy + k * 9, mz), 10, r, Enum.Material.Basalt)
		end
		fillCylinder(regions, CFrame.new(area.X1 + 110, gy + 50, mz), 4, 8, Enum.Material.CrackedLava)
	end
	-- Pockets that must stay free of terrain (e.g. the parking booth).
	for _, r in keepClear do
		workspace.Terrain:FillBlock(r.CFrame, r.Size, Enum.Material.Air)
	end
	return regions
end

-- What lies right under the turf: the biome's ground, but never grass (its blades would
-- grow up through the floor).
function CourseNature.underTurf(biomeId: string): Enum.Material
	local b = CourseNature.Biomes[biomeId] or CourseNature.Biomes.Meadow
	return if b.Ground == Enum.Material.Grass or b.Ground == Enum.Material.LeafyGrass then Enum.Material.Ground else b.Ground
end

function CourseNature.clear(regions: { Region })
	for _, r in regions do
		workspace.Terrain:FillBlock(r.CFrame, r.Size, Enum.Material.Air)
	end
end

-- Props ------------------------------------------------------------------------------

local function foliage(parent: Instance, center: Vector3, size: number, color: Color3, rng: Random, count: number)
	for _ = 1, count do
		local off = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.4, 0.8), rng:NextNumber(-1, 1)) * size * 0.45
		Parts.ball(parent, center + off, size * rng:NextNumber(0.55, 0.85), deco(vary(color, rng, 0.12), Enum.Material.Grass))
	end
end

local function trunk(parent: Instance, base: Vector3, height: number, dia: number, color: Color3)
	Parts.cylinder(parent, CFrame.new(base + up(height / 2)), height, dia, deco(color, Enum.Material.Wood))
	Parts.cylinder(parent, CFrame.new(base + up(0.25)), 0.5, dia * 1.5, deco(color:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Wood))
end

local function rock(parent: Instance, base: Vector3, size: number, color: Color3, material: Enum.Material, rng: Random)
	for k = 1, 3 do
		local s = size * (1 - k * 0.22)
		local cf = CFrame.new(base + Vector3.new(rng:NextNumber(-0.6, 0.6) * size, s * 0.3, rng:NextNumber(-0.6, 0.6) * size))
			* CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi))
		Parts.block(parent, cf, Vector3.new(s, s * 0.7, s * 0.85), deco(vary(color, rng, 0.08), material))
	end
end

export type Palette = { Foliage: Color3, Accent: Color3, Rock: Color3, Trim: Color3, Water: Color3 }

-- Cheap stand-ins (3-5 parts) for trees and spires only ever seen from far away.
local function farProp(parent: Instance, kind: string, base: Vector3, rng: Random, pal: Palette)
	if kind == "PalmIsle" then
		local dia = rng:NextNumber(8, 12)
		Parts.cylinder(parent, CFrame.new(base + up(0.2)), 1, dia, deco(Color3.fromRGB(236, 214, 160), Enum.Material.Sand))
		Parts.cylinder(parent, CFrame.new(base + up(0.75)), 0.6, dia * 0.6, deco(Color3.fromRGB(226, 202, 146), Enum.Material.Sand))
		farProp(parent, "Palm", base + up(1), rng, pal)
	elseif kind == "Pine" then
		local h = rng:NextNumber(10, 15)
		Parts.cylinder(parent, CFrame.new(base + up(h * 0.2)), h * 0.4, 1, deco(BARK, Enum.Material.Wood))
		for k = 0, 2 do
			Parts.cylinder(parent, CFrame.new(base + up(h * (0.35 + k * 0.25))), h * 0.22, (7 - k * 2) * rng:NextNumber(0.9, 1.1), deco(vary(pal.Foliage, rng, 0.06), Enum.Material.Grass))
		end
	elseif kind == "Palm" then
		local h = rng:NextNumber(10, 14)
		Parts.cylinder(parent, CFrame.new(base + up(h / 2)), h, 0.9, deco(Color3.fromRGB(150, 116, 74), Enum.Material.Wood))
		for k = 1, 3 do
			local a = k / 3 * math.pi * 2
			local dir = Vector3.new(math.cos(a), -0.3, math.sin(a)).Unit
			Parts.block(parent, CFrame.lookAt(base + up(h) + dir * 2.2, base + up(h) + dir * 5), Vector3.new(1.6, 0.2, 5), deco(vary(pal.Foliage, rng, 0.1), Enum.Material.Grass))
		end
	elseif kind == "Spire" or kind == "Basalt" then
		local h = rng:NextNumber(9, 16)
		local col = if kind == "Spire" then Color3.fromRGB(196, 120, 72) else Color3.fromRGB(52, 48, 50)
		local mat = if kind == "Spire" then Enum.Material.Sandstone else Enum.Material.Basalt
		Parts.block(parent, CFrame.new(base + up(h / 2)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), Vector3.new(6, h, 5), deco(vary(col, rng, 0.08), mat))
		Parts.block(parent, CFrame.new(base + up(h + 1)), Vector3.new(4, 2, 3.5), deco(vary(col, rng, 0.08), mat))
	else
		local h = rng:NextNumber(7, 10)
		Parts.cylinder(parent, CFrame.new(base + up(h / 2)), h, 1.5, deco(BARK, Enum.Material.Wood))
		foliage(parent, base + up(h + 1.5), rng:NextNumber(6, 8), pal.Foliage, rng, 3)
	end
end

function CourseNature.prop(parent: Instance, kind: string, base: Vector3, face: Vector3, rng: Random, pal: Palette, far: boolean?)
	if far then
		farProp(parent, kind, base, rng, pal)
		return
	end
	local facing = CFrame.lookAt(base, base + face)
	if kind == "Oak" or kind == "JungleTree" then
		local h = rng:NextNumber(7, 11)
		local jungle = kind == "JungleTree"
		trunk(parent, base, h, rng:NextNumber(1.3, 1.9), if jungle then Color3.fromRGB(92, 70, 46) else BARK)
		for _, a in { 0.6, 2.7, 4.6 } do
			local dir = Vector3.new(math.cos(a), 0.9, math.sin(a)).Unit
			Parts.rod(parent, base + up(h * 0.65), base + up(h * 0.65) + dir * 3.2, 0.6, deco(BARK, Enum.Material.Wood))
		end
		foliage(parent, base + up(h + 1.5), rng:NextNumber(6, 8), pal.Foliage, rng, if jungle then 7 else 6)
		if jungle then
			for _ = 1, 3 do
				local a = rng:NextNumber(0, math.pi * 2)
				local top = base + up(h + 0.5) + Vector3.new(math.cos(a), 0, math.sin(a)) * 3
				Parts.rod(parent, top, top - up(rng:NextNumber(4, 7)), 0.18, deco(pal.Foliage:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Grass))
			end
		end
	elseif kind == "Pine" then
		local h = rng:NextNumber(10, 15)
		trunk(parent, base, h * 0.35, 1.1, BARK)
		local tiers = 6
		for k = 0, tiers - 1 do
			local t = k / (tiers - 1)
			local dia = (1 - t * 0.82) * rng:NextNumber(6.5, 8)
			local y = h * 0.28 + t * h * 0.7
			Parts.cylinder(parent, CFrame.new(base + up(y)) * CFrame.Angles(0, k * 0.5, 0), 1.6, dia, deco(vary(pal.Foliage, rng, 0.06), Enum.Material.Grass))
			Parts.cylinder(parent, CFrame.new(base + up(y + 0.85)), 0.25, dia * 0.8, deco(Color3.fromRGB(240, 245, 250), Enum.Material.Snow))
		end
	elseif kind == "Palm" then
		local h = rng:NextNumber(10, 14)
		local lean = Vector3.new(face.X, 0, face.Z).Unit * rng:NextNumber(0.15, 0.3)
		local prev = base
		for k = 1, 6 do
			local p = base + up(h * k / 6) + lean * (h * (k / 6) ^ 2)
			Parts.rod(parent, prev, p, 1.1 - k * 0.06, deco(Color3.fromRGB(150, 116, 74), Enum.Material.Wood))
			prev = p
		end
		for k = 1, 7 do
			local a = k / 7 * math.pi * 2
			local dir = Vector3.new(math.cos(a), -0.35, math.sin(a)).Unit
			local mid = prev + dir * 2.4
			Parts.block(parent, CFrame.lookAt(mid, prev + dir * 5), Vector3.new(1.4, 0.15, 5), deco(vary(pal.Foliage, rng, 0.1), Enum.Material.Grass))
		end
		for k = 1, 3 do
			local a = k * 2.1
			Parts.ball(parent, prev + Vector3.new(math.cos(a) * 0.5, -0.5, math.sin(a) * 0.5), 0.6, deco(Color3.fromRGB(92, 64, 36), Enum.Material.Wood))
		end
	elseif kind == "Bush" or kind == "DryBush" then
		local dry = kind == "DryBush"
		foliage(parent, base + up(1.2), rng:NextNumber(2.6, 3.6), if dry then Color3.fromRGB(150, 140, 80) else pal.Foliage, rng, 4)
	elseif kind == "Fern" then
		for k = 1, 5 do
			local a = k / 5 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local dir = Vector3.new(math.cos(a), 0.6, math.sin(a)).Unit
			local mid = base + dir * 1.4 + up(0.4)
			Parts.block(parent, CFrame.lookAt(mid, base + dir * 3 + up(1.2)), Vector3.new(0.9, 0.12, 3.2), deco(vary(pal.Foliage, rng, 0.1), Enum.Material.Grass))
		end
	elseif kind == "Flowers" then
		Parts.cylinder(parent, CFrame.new(base + up(0.15)), 0.3, 5, deco(Color3.fromRGB(92, 64, 40), Enum.Material.Ground))
		local colors = { Color3.fromRGB(235, 64, 80), Color3.fromRGB(255, 205, 60), WHITE, Color3.fromRGB(170, 110, 230), Color3.fromRGB(255, 140, 190) }
		Parts.cylinder(parent, CFrame.new(base + up(0.45)), 0.35, 4.2, deco(Color3.fromRGB(70, 130, 60), Enum.Material.Grass))
		for _ = 1, 6 do
			local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.3, 1.8)
			local p = base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			Parts.ball(parent, p + up(rng:NextNumber(0.75, 1)), rng:NextNumber(0.55, 0.75), deco(colors[rng:NextInteger(1, #colors)]))
		end
	elseif kind == "Rock" then
		rock(parent, base, rng:NextNumber(2.2, 3.6), pal.Rock, Enum.Material.Rock, rng)
	elseif kind == "Windmill" then
		local wood = Color3.fromRGB(196, 96, 70)
		for k = 0, 3 do
			local dia = 6 - k * 0.7
			Parts.cylinder(parent, CFrame.new(base + up(1.5 + k * 2.6)), 2.7, dia, deco(if k % 2 == 0 then wood else wood:Lerp(WHITE, 0.15), Enum.Material.WoodPlanks))
		end
		for k = 0, 3 do
			Parts.cylinder(parent, CFrame.new(base + up(11.4 + k * 0.7)), 0.7, 4.6 - k * 1.1, deco(Color3.fromRGB(70, 60, 58), Enum.Material.Slate))
		end
		local hub = facing * CFrame.new(0, 9.6, -2.9)
		Parts.cylinder(parent, hub * CFrame.Angles(math.pi / 2, 0, 0), 0.8, 1.1, deco(Color3.fromRGB(60, 50, 44), Enum.Material.Wood))
		for k = 0, 3 do
			local blade = hub * CFrame.Angles(0, 0, k * math.pi / 2 + 0.4) * CFrame.new(0, 3.2, -0.3)
			Parts.block(parent, blade, Vector3.new(1.6, 5.6, 0.12), deco(Color3.fromRGB(245, 240, 228), Enum.Material.Fabric))
			Parts.block(parent, blade * CFrame.new(0, 0, -0.1), Vector3.new(0.25, 6, 0.2), deco(Color3.fromRGB(110, 80, 56), Enum.Material.Wood))
		end
		Parts.block(parent, facing * CFrame.new(0, 1.6, -2.95), Vector3.new(1.8, 3, 0.2), deco(Color3.fromRGB(80, 54, 36), Enum.Material.Wood))
	elseif kind == "Cactus" then
		local h = rng:NextNumber(5, 8)
		local green = vary(Color3.fromRGB(86, 140, 70), rng, 0.08)
		Parts.cylinder(parent, CFrame.new(base + up(h / 2)), h, 1.3, deco(green))
		Parts.ball(parent, base + up(h), 1.3, deco(green))
		for _, s in { -1, 1 } do
			local y = h * rng:NextNumber(0.35, 0.6)
			local elbow = base + up(y) + facing.RightVector * (s * 1.4)
			Parts.rod(parent, base + up(y), elbow, 0.85, deco(green))
			Parts.cylinder(parent, CFrame.new(elbow + up(1.1)), 2.2, 0.85, deco(green))
			Parts.ball(parent, elbow + up(2.2), 0.85, deco(green))
		end
	elseif kind == "Spire" then
		local h = rng:NextNumber(10, 18)
		local sand = Color3.fromRGB(196, 120, 72)
		local layers = 5
		for k = 0, layers - 1 do
			local s = (1 - k * 0.14) * rng:NextNumber(7, 9)
			local lh = h / layers
			Parts.block(parent, CFrame.new(base + up(lh * (k + 0.5))) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), Vector3.new(s, lh, s * 0.85),
				deco(if k % 2 == 0 then sand else sand:Lerp(Color3.fromRGB(240, 200, 150), 0.25), Enum.Material.Sandstone))
		end
	elseif kind == "Snowman" then
		local snow = Color3.fromRGB(244, 247, 252)
		Parts.ball(parent, base + up(1.4), 2.8, deco(snow, Enum.Material.Snow))
		Parts.ball(parent, base + up(3.4), 2, deco(snow, Enum.Material.Snow))
		Parts.ball(parent, base + up(4.9), 1.4, deco(snow, Enum.Material.Snow))
		local nose = (facing * CFrame.new(0, 4.9, -0.8)).Position
		Parts.rod(parent, nose, nose + facing.LookVector * 0.6, 0.18, deco(Color3.fromRGB(255, 140, 40)))
		Parts.cylinder(parent, CFrame.new(base + up(5.75)), 0.2, 1.6, deco(Color3.fromRGB(30, 30, 34)))
		Parts.cylinder(parent, CFrame.new(base + up(6.3)), 1, 1, deco(Color3.fromRGB(30, 30, 34)))
		Parts.cylinder(parent, CFrame.new(base + up(4.25)), 0.35, 1.9, deco(pal.Accent, Enum.Material.Fabric))
	elseif kind == "Crystal" then
		for _ = 1, 4 do
			local h = rng:NextNumber(2, 4.5)
			local cf = CFrame.new(base + up(h / 2 - 0.3)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4))
			Parts.block(parent, cf, Vector3.new(0.9, h, 0.9), deco(Color3.fromRGB(190, 232, 255), Enum.Material.Ice, 0.15))
		end
	elseif kind == "Basalt" then
		for _ = 1, 5 do
			local h = rng:NextNumber(4, 11)
			local off = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			Parts.cylinder(parent, CFrame.new(base + off + up(h / 2)), h, rng:NextNumber(1.6, 2.4), deco(vary(Color3.fromRGB(52, 48, 50), rng, 0.08), Enum.Material.Basalt))
		end
	elseif kind == "DeadTree" then
		local h = rng:NextNumber(6, 9)
		local wood = Color3.fromRGB(58, 48, 44)
		trunk(parent, base, h, 1.1, wood)
		for _ = 1, 4 do
			local a = rng:NextNumber(0, math.pi * 2)
			local from = base + up(h * rng:NextNumber(0.55, 0.95))
			Parts.rod(parent, from, from + Vector3.new(math.cos(a), rng:NextNumber(0.3, 0.9), math.sin(a)).Unit * rng:NextNumber(2, 3.5), 0.35, deco(wood, Enum.Material.Wood))
		end
	elseif kind == "LavaPool" then
		local dia = rng:NextNumber(7, 10)
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			rock(parent, base + Vector3.new(math.cos(a), 0, math.sin(a)) * (dia / 2), 1.6, Color3.fromRGB(56, 50, 50), Enum.Material.Basalt, rng)
		end
		local lava = Parts.cylinder(parent, CFrame.new(base + up(0.2)), 0.3, dia, deco(Color3.fromRGB(255, 96, 24), Enum.Material.Neon))
		Parts.light(lava, Color3.fromRGB(255, 120, 50), 18, 1.6)
	elseif kind == "Vent" then
		rock(parent, base, 3, Color3.fromRGB(56, 50, 50), Enum.Material.Basalt, rng)
		local smoke = Parts.block(parent, CFrame.new(base + up(2.5)), Vector3.one * 0.5, deco(WHITE, nil, 1))
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Color3.fromRGB(120, 112, 108))
		e.Size = NumberSequence.new(1.5, 5)
		e.Transparency = NumberSequence.new(0.4, 1)
		e.Lifetime = NumberRange.new(3, 5)
		e.Rate = 4
		e.Speed = NumberRange.new(2, 4)
		e.SpreadAngle = Vector2.new(15, 15)
		e.Parent = smoke
	elseif kind == "Ruin" then
		local stone = Color3.fromRGB(150, 156, 138)
		local h = rng:NextNumber(4, 9)
		for k = 0, math.floor(h / 1.6) do
			Parts.cylinder(parent, CFrame.new(base + up(0.8 + k * 1.6)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.03, 0.03)), 1.5, 2.6, deco(vary(stone, rng, 0.06), Enum.Material.Slate))
		end
		Parts.ball(parent, base + up(h * 0.7) + facing.RightVector * 1.1, 1.4, deco(Color3.fromRGB(80, 130, 60), Enum.Material.Grass))
		rock(parent, base + facing.LookVector * 3, 1.6, stone, Enum.Material.Slate, rng)
	elseif kind == "Idol" then
		local stone = Color3.fromRGB(140, 146, 128)
		Parts.block(parent, facing * CFrame.new(0, 1, 0), Vector3.new(4, 2, 4), deco(stone, Enum.Material.Slate))
		Parts.block(parent, facing * CFrame.new(0, 4, 0), Vector3.new(2.8, 4, 2.4), deco(stone:Lerp(Color3.new(1, 1, 1), 0.06), Enum.Material.Slate))
		Parts.block(parent, facing * CFrame.new(0, 6.8, 0), Vector3.new(3.4, 1.6, 2.8), deco(stone, Enum.Material.Slate))
		for _, s in { -1, 1 } do
			Parts.block(parent, facing * CFrame.new(s * 0.65, 4.8, -1.22), Vector3.new(0.6, 0.4, 0.05), deco(pal.Accent))
		end
	elseif kind == "Buoy" then
		local red, white = Color3.fromRGB(214, 48, 49), Color3.fromRGB(245, 245, 245)
		local tilt = CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
		Parts.cylinder(parent, CFrame.new(base + up(0.1)) * tilt, 1.2, 2.4, deco(red))
		Parts.cylinder(parent, CFrame.new(base + up(1.1)) * tilt, 0.8, 1.6, deco(white))
		Parts.cylinder(parent, CFrame.new(base + up(1.9)) * tilt, 0.8, 1.2, deco(red))
		local lamp = Parts.ball(parent, base + up(2.6), 0.6, deco(Color3.fromRGB(255, 220, 120), Enum.Material.Neon))
		lamp.CastShadow = false
	elseif kind == "Boat" then
		local hullCF = facing * CFrame.Angles(0, rng:NextNumber(0.4, 1.2), rng:NextNumber(-0.05, 0.05)) + up(0.3)
		local hull = Color3.fromRGB(245, 242, 235)
		Parts.block(parent, hullCF, Vector3.new(2.8, 1.2, 6.5), deco(hull, Enum.Material.WoodPlanks))
		Parts.block(parent, hullCF * CFrame.new(0, 0.66, 0), Vector3.new(2.4, 0.12, 6), deco(Color3.fromRGB(176, 128, 82), Enum.Material.WoodPlanks))
		Parts.block(parent, hullCF * CFrame.new(0, -0.1, 0), Vector3.new(2.9, 0.25, 6.6), deco(pal.Accent))
		Parts.ball(parent, (hullCF * CFrame.new(0, 0, -3.2)).Position, 1.6, deco(hull, Enum.Material.WoodPlanks))
		local mastBase = (hullCF * CFrame.new(0, 0.7, -0.6)).Position
		Parts.rod(parent, mastBase, mastBase + up(7.5), 0.22, deco(Color3.fromRGB(120, 90, 60), Enum.Material.Wood))
		Parts.block(parent, hullCF * CFrame.new(0, 4.6, 0.9), Vector3.new(0.08, 5.6, 2.6), deco(WHITE, Enum.Material.Fabric))
	elseif kind == "PalmIsle" then
		local dia = rng:NextNumber(9, 13)
		Parts.cylinder(parent, CFrame.new(base + up(0.2)), 1, dia, deco(Color3.fromRGB(236, 214, 160), Enum.Material.Sand))
		Parts.cylinder(parent, CFrame.new(base + up(0.8)), 0.7, dia * 0.62, deco(Color3.fromRGB(226, 202, 146), Enum.Material.Sand))
		Parts.cylinder(parent, CFrame.new(base + up(-0.05)), 0.3, dia + 1.6, deco(Color3.fromRGB(150, 210, 220), Enum.Material.Glass, 0.45))
		CourseNature.prop(parent, "Palm", base + up(1.15), face, rng, pal)
		if rng:NextNumber() < 0.5 then
			rock(parent, base + facing.RightVector * 3 + up(0.4), 1.6, pal.Rock, Enum.Material.Rock, rng)
		end
	elseif kind == "SeaStack" then
		local col = Color3.fromRGB(118, 112, 104)
		local h = rng:NextNumber(7, 13)
		for k = 0, 3 do
			local s = (1 - k * 0.18) * rng:NextNumber(4, 5.5)
			Parts.block(parent, CFrame.new(base + up(h * (k + 0.5) / 4)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.08, 0.08)), Vector3.new(s, h / 4 + 0.4, s * 0.85), deco(vary(col, rng, 0.08), Enum.Material.Rock))
		end
		Parts.ball(parent, base + up(h + 0.2), 2.6, deco(pal.Foliage, Enum.Material.Grass))
	elseif kind == "Lighthouse" then
		rock(parent, base, 5, Color3.fromRGB(118, 112, 104), Enum.Material.Rock, rng)
		local h = 16
		for k = 0, 3 do
			Parts.cylinder(parent, CFrame.new(base + up(2.5 + h * (k + 0.5) / 4)), h / 4, 4.2 - k * 0.35, deco(if k % 2 == 0 then WHITE else Color3.fromRGB(214, 48, 49)))
		end
		Parts.cylinder(parent, CFrame.new(base + up(h + 2.8)), 0.4, 4.4, deco(Color3.fromRGB(40, 44, 52), Enum.Material.Metal))
		local lantern = Parts.cylinder(parent, CFrame.new(base + up(h + 4)), 2, 2.6, deco(Color3.fromRGB(255, 236, 170), Enum.Material.Neon))
		lantern.CastShadow = false
		Parts.light(lantern, Color3.fromRGB(255, 236, 170), 30, 1.4)
		Parts.cylinder(parent, CFrame.new(base + up(h + 5.4)), 0.8, 3.2, deco(Color3.fromRGB(214, 48, 49)))
	elseif kind == "Umbrella" then
		Parts.cylinder(parent, CFrame.new(base + up(2.5)), 5, 0.2, deco(WHITE))
		for k = 0, 3 do
			Parts.cylinder(parent, CFrame.new(base + up(5 + k * 0.3)), 0.3, 5.4 - k * 1.3, deco(if k % 2 == 0 then pal.Accent else WHITE, Enum.Material.Fabric))
		end
	elseif kind == "Torch" then
		Parts.cylinder(parent, CFrame.new(base + up(2.2)), 4.4, 0.4, deco(Color3.fromRGB(120, 86, 50), Enum.Material.Wood))
		local bowl = Parts.cylinder(parent, CFrame.new(base + up(4.6)), 0.6, 0.9, deco(Color3.fromRGB(80, 60, 40), Enum.Material.Wood))
		local fire = Instance.new("Fire")
		fire.Size = 2
		fire.Heat = 4
		fire.Parent = bowl
		Parts.light(bowl, Color3.fromRGB(255, 170, 90), 12, 1.2)
	end
end

return CourseNature

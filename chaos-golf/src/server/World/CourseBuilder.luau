--!strict
-- CourseBuilder: builds a map's holes (or the 3-hole tutorial) inside one enclosed
-- hall far away from the lobby. Several courses can exist at once; each is a Model
-- under workspace.Courses.
--
-- Generation is deterministic: hole h of a map uses Random.new(map.Seed * 31 + h) for
-- its path, elevation and features, so a map always plays identically. Chaos boxes are
-- rolled even when disabled, so toggling them never changes a layout. Decor has its
-- own RNG.
--
-- Conventions for the services
--  * Tiles are 12x12 studs; level 0 = origin.Y; floor parts are 1 stud thick.
--  * Floor parts (CanQuery = true) carry attribute Surface = "Sand" | "Ice" | "Boost"
--    (Boost floors also carry BoostDir: Vector3). Plain floors have no Surface attribute.
--  * Rails and rail posts carry attribute Rail = true; bumpers carry Bumper = true.
--  * Decoration is CanQuery = false, and CanCollide = false wherever a ball could reach it.
--  * The hall floor sits below every hole's FloorY - Config.Physics.OOBDepth, so a ball
--    that leaves a lane always ends up out of bounds instead of resting somewhere.
--  * Tutorial holes have a direct child part "InstructionSign"; its SurfaceGui "Label"
--    holds a blank TextLabel "Text" that the tutorial service fills.

local CollectionService = game:GetService("CollectionService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Maps = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Maps"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local CourseNature = require(script.Parent:WaitForChild("CourseNature"))

local CourseBuilder = {}

export type Hole = {
	Index: number,
	Par: number,
	Tee: Vector3, -- ball centre spawn position
	TeeLook: Vector3, -- unit horizontal direction from the tee toward the next tile
	Cup: Vector3, -- cup centre on the floor top surface
	FloorY: number, -- lowest floor-top Y of the hole
	Overview: CFrame, -- camera looking at the whole hole from above/behind the tee
	ChaosBoxes: { BasePart },
	Model: Model,
	Tutorial: boolean,
}

export type Course = {
	Model: Model,
	Map: Maps.MapDef?,
	Holes: { Hole },
	Booth: CFrame, -- HumanoidRootPart CFrame inside the sealed parking booth
	Destroy: () -> (),
}

export type BuildOpts = { ChaosBoxes: boolean }

-- Dimensions -------------------------------------------------------------

local TILE = 12
local HALF = TILE / 2
local SLOT = 130 -- hole spacing along +X
local HALL_END = 26 -- hall margin beyond the first/last slot
local HALL_HALF_Z = 92
local CEILING = 140 -- open sky: only caps how high hole overview cameras may sit
local RAIL_W = 1
local RAIL_BODY = 1.1 -- rail block height; the 1-stud rod on top makes the rail ~1.6 tall
local RAIL_IN = HALF - RAIL_W / 2 -- rail centre line offset from the tile centre
local BRIDGE_W = 4
local PIT_DEPTH = 6 -- bridge side walls reach this far below the bridge
local PUSH_W, PUSH_H, PUSH_D = 6.5, 2.2, 2.4
local PUSH_OFFSET = 1.65 -- pusher centre travels between -OFFSET and +OFFSET across the lane
local PUSH_PERIOD = 2
local BALL_R = Config.Ball.Diameter / 2
local CUP_R = Config.Physics.CupRadius
local NEON = Enum.Material.Neon -- only for things that really glow (lava)
local TURF = Enum.Material.Fabric
local WOOD = Enum.Material.Wood
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local FLOOR_PHYS = PhysicalProperties.new(0.7, 0.3, 0.2, 1, 1)
local RAIL_PHYS = PhysicalProperties.new(2, 0.2, 0.55, 1, 1)
local BUMPER_PHYS = PhysicalProperties.new(2, 0.1, 0.9, 1, 20)
local SPINNER_PHYS = PhysicalProperties.new(50, 0.3, 0.6, 1, 1)
local PUSHER_PHYS = PhysicalProperties.new(50, 0.05, 0.5, 1, 1)

-- PLAN (pure: plain tables + Random only) ------------------------------------

local DIRS: { { number } } = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } -- E(+X) S(+Z) W(-X) N(-Z)
local MAX_SPAN = 8 -- max cells per hole along each axis
local MIN_LEVEL, MAX_LEVEL, RAMP_STEP = -8, 12, 4
local STRAIGHT_BIAS = 0.6
local WALK_ATTEMPTS, STRICT_ATTEMPTS = 160, 100
-- Major features are rolled in this order; the first eligible hit claims the tile.
local FEATURE_ORDER = { "Spinner", "Pusher", "Bridge", "Boost", "Bumper", "Sand", "Ice" }
local NEEDS_STRAIGHT_FLAT: { [string]: boolean } = { Spinner = true, Pusher = true, Bridge = true, Boost = true }

export type TilePlan = {
	X: number, -- cell coordinates
	Z: number,
	In: number, -- travel direction entering the tile (DIRS index; tee: = Out)
	Out: number, -- travel direction leaving the tile (cup: = In)
	Entry: number, -- floor level at the entry edge
	Exit: number, -- floor level at the exit edge (differs from Entry on ramps)
	Straight: boolean,
	Ramp: boolean,
	Feature: string?,
	ChaosBox: boolean,
	Bumpers: { { number } }, -- {dx, dz} stud offsets from the tile centre
	Phase: number, -- spinner direction / pusher start side
}

export type HolePlan = {
	Tiles: { TilePlan },
	Turns: number,
	Hazards: number,
	Par: number,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	MinLevel: number,
	MaxLevel: number,
	Fallback: boolean,
}

local function opposite(d: number): number
	return (d + 1) % 4 + 1
end

local function cellKey(x: number, z: number): number
	return (x + 100) * 1000 + (z + 100)
end

-- Self-avoiding walk inside an 8x8 box. `strict` also forbids touching earlier tiles
-- (no non-consecutive neighbours), which keeps lanes readable.
local function tryWalk(rng: Random, len: number, strict: boolean): ({ { number } }?, { number }?)
	local cells: { { number } } = { { 0, 0 } }
	local moves: { number } = {}
	local visited: { [number]: boolean } = { [cellKey(0, 0)] = true }
	local minX, maxX, minZ, maxZ = 0, 0, 0, 0
	local dir = rng:NextInteger(1, 4)
	for i = 2, len do
		local cur = cells[i - 1]
		local turnA = if rng:NextNumber() < 0.5 then dir % 4 + 1 else (dir + 2) % 4 + 1
		local turnB = opposite(turnA)
		local order: { number } = if i == 2 or rng:NextNumber() < STRAIGHT_BIAS then { dir, turnA, turnB } else { turnA, turnB, dir }
		local pick = 0
		for _, d in order do
			local nx, nz = cur[1] + DIRS[d][1], cur[2] + DIRS[d][2]
			local fits = not visited[cellKey(nx, nz)]
				and math.max(maxX, nx) - math.min(minX, nx) < MAX_SPAN
				and math.max(maxZ, nz) - math.min(minZ, nz) < MAX_SPAN
			if fits and strict then
				for _, o in DIRS do
					local ax, az = nx + o[1], nz + o[2]
					if (ax ~= cur[1] or az ~= cur[2]) and visited[cellKey(ax, az)] then
						fits = false
						break
					end
				end
			end
			if fits then
				pick = d
				break
			end
		end
		if pick == 0 then
			return nil, nil
		end
		local nx, nz = cur[1] + DIRS[pick][1], cur[2] + DIRS[pick][2]
		table.insert(cells, { nx, nz })
		table.insert(moves, pick)
		visited[cellKey(nx, nz)] = true
		minX, maxX = math.min(minX, nx), math.max(maxX, nx)
		minZ, maxZ = math.min(minZ, nz), math.max(maxZ, nz)
		dir = pick
	end
	return cells, moves
end

-- Straight line, bending into an L once it reaches the box size.
local function fallbackWalk(len: number): ({ { number } }, { number })
	local cells: { { number } } = { { 0, 0 } }
	local moves: { number } = {}
	local x, z = 0, 0
	for i = 2, len do
		local d = if i <= MAX_SPAN then 1 else 2
		x += DIRS[d][1]
		z += DIRS[d][2]
		table.insert(cells, { x, z })
		table.insert(moves, d)
	end
	return cells, moves
end

local function tilesFromCells(cells: { { number } }, moves: { number }): { TilePlan }
	local n = #cells
	local tiles: { TilePlan } = {}
	for i, c in cells do
		local inDir = if i > 1 then moves[i - 1] else moves[1]
		local outDir = if i < n then moves[i] else moves[n - 1]
		table.insert(tiles, {
			X = c[1],
			Z = c[2],
			In = inDir,
			Out = outDir,
			Entry = 0,
			Exit = 0,
			Straight = inDir == outDir,
			Ramp = false,
			Feature = nil,
			ChaosBox = false,
			Bumpers = {},
			Phase = 0,
		})
	end
	return tiles
end

local function assignElevation(rng: Random, tiles: { TilePlan }, rampChance: number)
	local n = #tiles
	local level = 0
	for i, t in tiles do
		local roll, upRoll = rng:NextNumber(), rng:NextNumber()
		t.Entry = level
		if i > 1 and i < n and t.Straight and not tiles[i - 1].Ramp and roll < rampChance then
			local up = upRoll < 0.55
			if up and level + RAMP_STEP > MAX_LEVEL then
				up = false
			elseif not up and level - RAMP_STEP < MIN_LEVEL then
				up = true
			end
			level += if up then RAMP_STEP else -RAMP_STEP
			t.Ramp = true
		end
		t.Exit = level
	end
end

local function bumperLayout(t: TilePlan, a: number, b: number, c: number): { { number } }
	if not t.Straight then
		-- One post toward the outer corner of the bend; the inside line stays open.
		local i, o = DIRS[t.In], DIRS[t.Out]
		return { { (i[1] - o[1]) * 1.8, (i[2] - o[2]) * 1.8 } }
	end
	local f = DIRS[t.Out]
	local lx, lz = -f[2], f[1]
	local side = if b < 0.5 then -1 else 1
	local function at(lat: number, along: number): { number }
		return { lx * lat + f[1] * along, lz * lat + f[2] * along }
	end
	if a < 0.5 then
		return { at(side * 2.25, (c - 0.5) * 5) }
	end
	return { at(side * 2.25, -2.6), at(-side * 2.25, 2.6) }
end

local function assignFeatures(rng: Random, tiles: { TilePlan }, hazards: { [string]: number })
	local n = #tiles
	local phase = 0
	for i = 2, n - 1 do
		local t = tiles[i]
		local chosen: string? = nil
		for _, name in FEATURE_ORDER do
			local roll = rng:NextNumber()
			if chosen == nil and roll < (hazards[name] or 0) then
				local eligible = if NEEDS_STRAIGHT_FLAT[name]
					then t.Straight and not t.Ramp
					elseif name == "Bumper" then not t.Ramp
					else true
				if eligible then
					chosen = name
				end
			end
		end
		local boxRoll, a, b, c = rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber()
		t.Feature = chosen
		t.ChaosBox = boxRoll < (hazards.ChaosBox or 0) and (chosen == nil or chosen == "Sand" or chosen == "Ice")
		if chosen == "Bumper" then
			t.Bumpers = bumperLayout(t, a, b, c)
		elseif chosen == "Spinner" or chosen == "Pusher" then
			t.Phase = phase
			phase = 1 - phase
		end
	end
end

local function computePar(turns: number, len: number, hazards: number): number
	return math.clamp(2 + math.floor(turns / 2) + (if len >= 8 then 1 else 0) + (if hazards >= 3 then 1 else 0), 2, 5)
end

local function finishPlan(tiles: { TilePlan }, fallback: boolean): HolePlan
	local turns, hazards = 0, 0
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local minL, maxL = math.huge, -math.huge
	for _, t in tiles do
		if not t.Straight then
			turns += 1
		end
		if t.Feature then
			hazards += 1
		end
		minX, maxX = math.min(minX, t.X), math.max(maxX, t.X)
		minZ, maxZ = math.min(minZ, t.Z), math.max(maxZ, t.Z)
		minL, maxL = math.min(minL, t.Entry, t.Exit), math.max(maxL, t.Entry, t.Exit)
	end
	return {
		Tiles = tiles,
		Turns = turns,
		Hazards = hazards,
		Par = computePar(turns, #tiles, hazards),
		MinX = minX,
		MaxX = maxX,
		MinZ = minZ,
		MaxZ = maxZ,
		MinLevel = minL,
		MaxLevel = maxL,
		Fallback = fallback,
	}
end

local function planHole(map: Maps.MapDef, holeIndex: number): HolePlan
	local rng = Random.new(map.Seed * 31 + holeIndex)
	local lo, hi = map.Length[1], map.Length[2]
	local len = math.max(2, rng:NextInteger(math.min(lo, hi), math.max(lo, hi)))
	local cells: { { number } }? = nil
	local moves: { number }? = nil
	for attempt = 1, WALK_ATTEMPTS do
		cells, moves = tryWalk(rng, len, attempt <= STRICT_ATTEMPTS)
		if cells then
			break
		end
	end
	local fallback = false
	local finalCells: { { number } }, finalMoves: { number }
	if cells and moves then
		finalCells, finalMoves = cells, moves
	else
		finalCells, finalMoves = fallbackWalk(len)
		fallback = true
	end
	local tiles = tilesFromCells(finalCells, finalMoves)
	assignElevation(rng, tiles, map.RampChance)
	assignFeatures(rng, tiles, map.Hazards)
	return finishPlan(tiles, fallback)
end

local function tutorialPlans(): { HolePlan }
	local function path(moves: { number }): { TilePlan }
		local cells: { { number } } = { { 0, 0 } }
		for _, d in moves do
			local last = cells[#cells]
			table.insert(cells, { last[1] + DIRS[d][1], last[2] + DIRS[d][2] })
		end
		return tilesFromCells(cells, moves)
	end
	local N, E = 4, 1
	-- 1) straight, 4 tiles: aim + power
	local p1 = finishPlan(path({ N, N, N }), false)
	p1.Par = 2
	-- 2) L: 3 straight, turn, 2 more: banking off rails
	local p2 = finishPlan(path({ N, N, E, E }), false)
	p2.Par = 3
	-- 3) straight 5 with a chaos box on tile 2 and a bumper on tile 4: abilities
	local t3 = path({ N, N, N, N })
	t3[2].ChaosBox = true
	t3[4].Feature = "Bumper"
	t3[4].Bumpers = { { 0, 0 } }
	local p3 = finishPlan(t3, false)
	p3.Par = 3
	return { p1, p2, p3 }
end

-- BUILD ----------------------------------------------------------------------

type Pusher = { Constraint: PrismaticConstraint, Side: number }

type Ctx = {
	Theme: Maps.Theme,
	Origin: Vector3,
	HallFloorY: number, -- world Y of the hall floor top
	CeilingY: number, -- world Y of the ceiling underside
	X0: number, -- hall interior bounds (world)
	X1: number,
	Z0: number,
	Z1: number,
	ChaosBoxes: boolean,
	Tutorial: boolean,
	LightBoost: number,
	Unanchored: { BasePart },
	Pushers: { Pusher },
	Terrain: { CourseNature.Region },
}

type HoleInfo = {
	SlotX: number,
	Centre: Vector3, -- footprint centre at level 0
	HalfX: number,
	HalfZ: number,
	Rects: { { number } }, -- {x0, x1, z0, z1} areas decor must stay out of
	Camera: Vector3,
}

local TUTORIAL_THEME: Maps.Theme = table.clone(Maps.Themes.Arcade)
TUTORIAL_THEME.Id = "Tutorial"
TUTORIAL_THEME.Name = "Tutorial"

local function dirVec(d: number): Vector3
	return Vector3.new(DIRS[d][1], 0, DIRS[d][2])
end

local function up(y: number): Vector3
	return Vector3.new(0, y, 0)
end

-- Axis-aligned size whose `along` extent runs along direction d.
local function alignedSize(d: number, along: number, height: number, across: number): Vector3
	if DIRS[d][1] ~= 0 then
		return Vector3.new(along, height, across)
	end
	return Vector3.new(across, height, along)
end

local function wedge(parent: Instance, cf: CFrame, size: Vector3, props: Parts.Props, reflectance: number?): WedgePart
	local w = Instance.new("WedgePart")
	w.Size = size
	w.CFrame = cf
	w.Anchored = true
	w.Material = props.Material or Enum.Material.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Name = props.Name or "Wedge"
	if props.Color then
		w.Color = props.Color
	end
	if props.Transparency then
		w.Transparency = props.Transparency
	end
	if reflectance then
		w.Reflectance = reflectance
	end
	if props.CanCollide ~= nil then
		w.CanCollide = props.CanCollide
	end
	if props.CanQuery ~= nil then
		w.CanQuery = props.CanQuery
	end
	if props.Material == NEON then
		w.CastShadow = false
	end
	w.Parent = parent
	return w
end

-- Wedge whose tall end points along `hiDir` (horizontal unit vector).
local function slopeWedge(parent: Instance, centre: Vector3, hiDir: Vector3, across: number, height: number, length: number, props: Parts.Props): WedgePart
	local right = Vector3.yAxis:Cross(hiDir)
	return wedge(parent, CFrame.fromMatrix(centre, right, Vector3.yAxis, hiDir), Vector3.new(across, height, length), props)
end

local function weld(part: BasePart, to: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local function railLike(part: BasePart)
	part.CustomPhysicalProperties = RAIL_PHYS
	part:SetAttribute("Rail", true)
end

local function coursesFolder(): Instance
	local existing = workspace:FindFirstChild("Courses")
	if existing then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "Courses"
	f.Parent = workspace
	return f
end

-- Track ------------------------------------------------------------------

local function buildFloor(ctx: Ctx, parent: Instance, t: TilePlan, c: Vector3): BasePart
	local theme = ctx.Theme
	local color = if (t.X + t.Z) % 2 == 0 then theme.Floor else theme.FloorAlt
	if t.Feature == "Sand" then
		color = theme.Sand
	elseif t.Feature == "Ice" then
		color = theme.Ice
	end
	local props: Parts.Props = { Name = "Floor", Color = color, Material = TURF }
	if t.Feature == "Ice" then
		props.Material = Enum.Material.Ice
		props.Reflectance = 0.12
	elseif t.Feature == "Sand" then
		props.Material = Enum.Material.Sand
	elseif t.Feature == "Bridge" then
		props.Material = Enum.Material.WoodPlanks
		props.Color = theme.Rail:Lerp(Color3.new(1, 1, 1), 0.12)
	end
	local floor: Part
	if t.Ramp then
		local f = dirVec(t.Out)
		local a = c - f * HALF + up(t.Entry)
		local b = c + f * HALF + up(t.Exit)
		floor = Parts.block(parent, CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.5, 0), Vector3.new(TILE, 1, (b - a).Magnitude), props)
	elseif t.Feature == "Bridge" then
		floor = Parts.block(parent, CFrame.new(c + up(t.Entry - 0.5)), alignedSize(t.Out, TILE, 1, BRIDGE_W), props)
	else
		floor = Parts.block(parent, CFrame.new(c + up(t.Entry - 0.5)), Vector3.new(TILE, 1, TILE), props)
	end
	floor.CustomPhysicalProperties = FLOOR_PHYS
	if t.Feature == "Sand" then
		floor:SetAttribute("Surface", "Sand")
	elseif t.Feature == "Ice" then
		floor:SetAttribute("Surface", "Ice")
	elseif t.Feature == "Boost" then
		floor:SetAttribute("Surface", "Boost")
		floor:SetAttribute("BoostDir", dirVec(t.Out))
	end
	return floor
end

-- Rail on edge `d` of a tile, inset inside the tile (so two adjacent but
-- non-consecutive tiles each get their own rail and nothing overlaps).
local function buildRail(ctx: Ctx, parent: Instance, t: TilePlan, c: Vector3, d: number)
	local theme = ctx.Theme
	local e = dirVec(d)
	local edge = c + e * RAIL_IN
	local body: Parts.Props = { Name = "Rail", Color = theme.Rail, Material = WOOD }
	local rodProps: Parts.Props = { Name = "Rail", Color = theme.Trim }
	if not t.Ramp then
		local level = t.Entry
		local bottom = if t.Feature == "Bridge" then level - PIT_DEPTH else level
		local top = level + RAIL_BODY
		railLike(Parts.block(parent, CFrame.new(edge + up((bottom + top) / 2)), alignedSize(d, RAIL_W, top - bottom, TILE), body))
		local p = Vector3.new(-e.Z, 0, e.X)
		local a = edge - p * HALF + up(top)
		local b = edge + p * HALF + up(top)
		railLike(Parts.rod(parent, a, b, RAIL_W, rodProps))
	else
		-- Side rail of a ramp: block up to the low level + wedge up to the high level,
		-- so both ends are vertical and line up exactly with the neighbouring rails.
		local lo, hi = math.min(t.Entry, t.Exit), math.max(t.Entry, t.Exit)
		local f = dirVec(t.Out)
		local hiDir = if t.Exit > t.Entry then f else -f
		railLike(Parts.block(parent, CFrame.new(edge + up(lo - 1 + (RAIL_BODY + 1) / 2)), alignedSize(d, RAIL_W, RAIL_BODY + 1, TILE), body))
		railLike(slopeWedge(parent, edge + up(lo + RAIL_BODY + (hi - lo) / 2), hiDir, RAIL_W, hi - lo, TILE, body))
		local a = edge - f * HALF + up(t.Entry + RAIL_BODY)
		local b = edge + f * HALF + up(t.Exit + RAIL_BODY)
		railLike(Parts.rod(parent, a, b, RAIL_W, rodProps))
	end
end

local function buildPost(ctx: Ctx, parent: Instance, x: number, z: number, level: number, diameter: number)
	local bottom, top = level - 0.2, level + RAIL_BODY + RAIL_W / 2
	railLike(Parts.cylinder(parent, CFrame.new(x, (bottom + top) / 2, z), top - bottom, diameter, { Name = "RailPost", Color = ctx.Theme.Rail, Material = WOOD }))
	railLike(Parts.ball(parent, Vector3.new(x, top, z), diameter + 0.25, { Name = "RailPost", Color = ctx.Theme.Trim }))
end

local function buildSupport(ctx: Ctx, parent: Instance, t: TilePlan, c: Vector3)
	local theme = ctx.Theme
	local lo, hi = math.min(t.Entry, t.Exit), math.max(t.Entry, t.Exit)
	local top = lo - 1
	local floorRel = ctx.HallFloorY - ctx.Origin.Y
	if t.Feature == "Bridge" then
		-- Wooden piles down into the water/ground.
		local f = dirVec(t.Out)
		for _, k in { -1, 1 } do
			local p = c + f * (k * HALF * 0.6)
			local h = top - floorRel + 1
			Parts.cylinder(parent, CFrame.new(p + up(top - h / 2)), h, 1.1, { Name = "Support", Color = theme.Rail:Lerp(BLACK, 0.2), Material = WOOD, CanQuery = false })
		end
		return
	end
	local span = TILE - 0.3
	local lip: Parts.Props = { Name = "Support", Color = theme.FloorAlt:Lerp(BLACK, 0.2), Material = Enum.Material.Grass, CanQuery = false }
	local dirt: Parts.Props = { Name = "Support", Color = theme.Wall, Material = Enum.Material.Ground, CanQuery = false }
	-- A grass lip right under the turf, then earth all the way down to the ground.
	Parts.block(parent, CFrame.new(c + up(top - 0.5)), alignedSize(t.Out, span, 1, span), lip)
	local h = (top - 1) - (floorRel - 1.5)
	if h > 0.2 then
		Parts.block(parent, CFrame.new(c + up(top - 1 - h / 2)), alignedSize(t.Out, span - 0.5, h, span - 0.5), dirt)
	end
	if t.Ramp then
		local f = dirVec(t.Out)
		local hiDir = if t.Exit > t.Entry then f else -f
		slopeWedge(parent, c + up(top + (hi - lo) / 2), hiDir, span, hi - lo, TILE, dirt)
	end
end

-- Features -----------------------------------------------------------------

local function buildBumpers(ctx: Ctx, parent: Instance, t: TilePlan, top: Vector3)
	local theme = ctx.Theme
	for _, off in t.Bumpers do
		local p = top + Vector3.new(off[1], 0, off[2])
		local body = Parts.cylinder(parent, CFrame.new(p + up(1.25)), 2.5, 2, { Name = "Bumper", Color = theme.Accent })
		body.CustomPhysicalProperties = BUMPER_PHYS
		body:SetAttribute("Bumper", true)
		Parts.cylinder(parent, CFrame.new(p + up(2.55)), 0.2, 1.6, { Name = "BumperCap", Color = theme.Trim, CanCollide = false, CanQuery = false })
		Parts.cylinder(parent, CFrame.new(p + up(1.25)), 0.5, 2.08, { Name = "BumperBand", Color = theme.Trim, CanCollide = false, CanQuery = false })
		Parts.cylinder(parent, CFrame.new(p + up(0.08)), 0.12, 2.6, { Name = "BumperRing", Color = theme.Rail, Material = WOOD, CanCollide = false, CanQuery = false })
	end
end

local function buildSpinner(ctx: Ctx, parent: Instance, t: TilePlan, top: Vector3)
	local theme = ctx.Theme
	local f = dirVec(t.Out)
	local hub = Parts.cylinder(parent, CFrame.new(top + up(1.1)), 2.2, 1.2, { Name = "SpinnerHub", Color = theme.Rail, Material = WOOD })
	Parts.ball(parent, top + up(2.25), 1.3, { Name = "SpinnerCap", Color = theme.Trim, CanCollide = false, CanQuery = false })

	local barPos = top + up(0.15 + 0.6)
	local barCF = CFrame.lookAt(barPos, barPos + f) -- bar length (X) runs across the lane
	local bar = Parts.block(parent, barCF, Vector3.new(9, 1.2, 0.8), { Name = "SpinnerBar", Color = theme.Accent, Anchored = false })
	bar.CustomPhysicalProperties = SPINNER_PHYS
	local stripe = Parts.block(parent, barCF * CFrame.new(0, 0.61, 0), Vector3.new(8.2, 0.08, 0.34), {
		Name = "SpinnerStripe",
		Color = theme.Trim,
		CanCollide = false,
		CanQuery = false,
		Anchored = false,
	})
	stripe.Massless = true
	weld(stripe, bar)
	for _, s in { -1, 1 } do
		local cap = Parts.cylinder(parent, barCF * CFrame.new(s * 4.5, 0, 0), 1.2, 0.8, { Name = "SpinnerEnd", Color = theme.Trim, CanCollide = false, CanQuery = false, Anchored = false })
		cap.Massless = true
		weld(cap, bar)
	end

	-- Hinge about the vertical axis (attachment primary axis = world up).
	local axis = CFrame.new(barPos) * CFrame.Angles(0, 0, math.pi / 2)
	local a0 = Instance.new("Attachment")
	a0.Name = "SpinnerAxis"
	a0.CFrame = hub.CFrame:ToObjectSpace(axis)
	a0.Parent = hub
	local a1 = Instance.new("Attachment")
	a1.Name = "SpinnerAxis"
	a1.CFrame = bar.CFrame:ToObjectSpace(axis)
	a1.Parent = bar
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = if t.Phase == 0 then 1.4 else -1.4
	hinge.MotorMaxTorque = 1e9
	hinge.MotorMaxAcceleration = math.huge
	hinge.Parent = bar
	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0 = bar
	nc.Part1 = hub
	nc.Parent = bar
	table.insert(ctx.Unanchored, bar)
end

local function buildPusher(ctx: Ctx, parent: Instance, t: TilePlan, top: Vector3)
	local theme = ctx.Theme
	local f = dirVec(t.Out)
	local lat = Vector3.new(-f.Z, 0, f.X)
	local side = if t.Phase == 0 then -1 else 1

	local trackPos = top + up(0.03)
	local trackCF = CFrame.lookAt(trackPos, trackPos + f) -- X runs across the lane
	local track = Parts.block(parent, trackCF, Vector3.new(TILE - 2, 0.06, PUSH_D + 0.8), { Name = "PusherTrack", Color = theme.WallAlt, CanCollide = false, CanQuery = false })
	for _, s in { -1, 1 } do
		Parts.block(parent, trackCF * CFrame.new(0, 0.01, s * (PUSH_D / 2 + 0.3)), Vector3.new(TILE - 2, 0.07, 0.14), { Name = "PusherTrackTrim", Color = theme.Trim, CanCollide = false, CanQuery = false })
	end

	local centre = top + up(0.12 + PUSH_H / 2)
	local start = centre + lat * (side * PUSH_OFFSET)
	local blockCF = CFrame.fromMatrix(start, lat, Vector3.yAxis)
	local block = Parts.block(parent, blockCF, Vector3.new(PUSH_W, PUSH_H, PUSH_D), { Name = "Pusher", Color = theme.Accent, Anchored = false })
	block.CustomPhysicalProperties = PUSHER_PHYS
	local stripe = Parts.block(parent, blockCF * CFrame.new(0, PUSH_H / 2 + 0.02, 0), Vector3.new(PUSH_W - 0.4, 0.08, 0.5), {
		Name = "PusherStripe",
		Color = theme.Trim,
		CanCollide = false,
		CanQuery = false,
		Anchored = false,
	})
	stripe.Massless = true
	weld(stripe, block)

	local a0 = Instance.new("Attachment")
	a0.Name = "PusherAxis"
	a0.CFrame = track.CFrame:ToObjectSpace(CFrame.fromMatrix(centre, lat, Vector3.yAxis))
	a0.Parent = track
	local a1 = Instance.new("Attachment")
	a1.Name = "PusherAxis"
	a1.Parent = block -- identity: block centre, X axis = lat
	local slider = Instance.new("PrismaticConstraint")
	slider.Attachment0 = a0
	slider.Attachment1 = a1
	slider.ActuatorType = Enum.ActuatorType.Servo
	slider.ServoMaxForce = 1e8
	slider.Speed = 9
	slider.LinearResponsiveness = 100
	slider.LimitsEnabled = true
	slider.LowerLimit = -PUSH_OFFSET - 0.05
	slider.UpperLimit = PUSH_OFFSET + 0.05
	slider.TargetPosition = side * PUSH_OFFSET
	slider.Parent = block
	table.insert(ctx.Pushers, { Constraint = slider, Side = side })
	table.insert(ctx.Unanchored, block)
end

local function buildBoost(ctx: Ctx, parent: Instance, t: TilePlan, top: Vector3)
	local f = dirVec(t.Out)
	local lat = Vector3.new(-f.Z, 0, f.X)
	local padPos = top + up(0.025)
	Parts.block(parent, CFrame.lookAt(padPos, padPos + f), Vector3.new(6.4, 0.05, 10), { Name = "BoostPad", Color = Color3.fromRGB(58, 62, 70), Material = Enum.Material.Concrete, CanCollide = false, CanQuery = false })
	local neon: Parts.Props = { Name = "BoostChevron", Color = Color3.fromRGB(255, 210, 63), CanCollide = false, CanQuery = false }
	for k = -1, 1 do
		local base = top + f * (k * 2.8) + up(0.06)
		local tip = base + f * 1.1
		Parts.beam(parent, base - f * 0.9 + lat * 2, tip, 0.6, 0.05, neon)
		Parts.beam(parent, base - f * 0.9 - lat * 2, tip, 0.6, 0.05, neon)
	end
end

local function buildBridge(ctx: Ctx, parent: Instance, t: TilePlan, c: Vector3)
	local theme = ctx.Theme
	local f = dirVec(t.Out)
	local lat = Vector3.new(-f.Z, 0, f.X)
	Parts.block(parent, CFrame.new(c + up(t.Entry - 3)), alignedSize(t.Out, TILE, 0.2, TILE - 2 * RAIL_W), {
		Name = "Water",
		Color = theme.Water,
		Material = if theme.Decor == "Volcano" then NEON else Enum.Material.Glass,
		Transparency = if theme.Decor == "Volcano" then 0 else 0.3,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	for _, s in { -1, 1 } do
		Parts.block(parent, CFrame.new(c + lat * (s * (BRIDGE_W / 2 + 0.05)) + up(t.Entry - 0.22)), alignedSize(t.Out, TILE, 0.3, 0.1), {
			Name = "BridgeTrim",
			Color = theme.Trim,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

local function buildChaosBox(ctx: Ctx, parent: Instance, top: Vector3): BasePart
	-- Golden mystery box. Matches hide it with Transparency 1 after a pickup and show it
	-- again with ShowTransparency; the "?" marks follow the box's visibility.
	local box = Parts.block(parent, CFrame.new(top + up(1.6)), Vector3.one * 2.2, {
		Name = "ChaosBox",
		Color = Color3.fromRGB(242, 178, 52),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	box.Reflectance = 0.08
	box:SetAttribute("ChaosBox", true)
	box:SetAttribute("ShowTransparency", 0)
	CollectionService:AddTag(box, "Spin")
	local marks: { SurfaceGui } = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top } do
		local label = Parts.label(box, face, "?", { TextColor = WHITE, Stroke = Color3.fromRGB(150, 90, 10), PixelsPerStud = 40 })
		local gui = label:FindFirstAncestorOfClass("SurfaceGui")
		if gui then
			table.insert(marks, gui)
		end
	end
	box:GetPropertyChangedSignal("Transparency"):Connect(function()
		for _, g in marks do
			g.Enabled = box.Transparency < 0.9
		end
	end)
	Parts.light(box, Color3.fromRGB(255, 214, 120), 9, 0.9)
	return box
end

-- Tee, signs and cup ---------------------------------------------------------

-- Board standing `dist` behind the tee centre, leaning back by `tilt` so its Front
-- face (the label face) points back along -look and up toward the camera.
local function leaningBoard(parent: Instance, teeTop: Vector3, look: Vector3, dist: number, lift: number, size: Vector2, tilt: number, props: Parts.Props): Part
	local bottom = teeTop - look * dist + up(lift)
	local upDir = Vector3.yAxis * math.cos(tilt) + look * math.sin(tilt)
	local centre = bottom + upDir * (size.Y / 2)
	local cf = CFrame.lookAt(centre, centre - look) * CFrame.Angles(tilt, 0, 0)
	local board = Parts.block(parent, cf, Vector3.new(size.X, size.Y, 0.35), props)
	local trim: Parts.Props = { Name = "SignTrim", Color = Color3.fromRGB(196, 158, 110), Material = WOOD, CanCollide = false, CanQuery = false }
	for _, s in { -1, 1 } do
		Parts.block(parent, cf * CFrame.new(0, s * size.Y / 2, 0), Vector3.new(size.X + 0.2, 0.16, 0.45), trim)
	end
	return board
end

local function signDeck(parent: Instance, teeTop: Vector3, look: Vector3, from: number, to: number, width: number, y: number, color: Color3)
	local mid = teeTop - look * ((from + to) / 2) + up(y)
	Parts.block(parent, CFrame.lookAt(mid, mid + look), Vector3.new(width, 0.6, to - from), { Name = "SignDeck", Color = color, CanCollide = false, CanQuery = false })
end

local function buildTee(ctx: Ctx, holeModel: Model, parent: Instance, teeTop: Vector3, look: Vector3, index: number, par: number, backFree: boolean)
	local theme = ctx.Theme
	local padPos = teeTop + up(0.04)
	Parts.trimmedSlab(parent, CFrame.lookAt(padPos, padPos + look), Vector3.new(4.4, 0.05, 4.4), 0.9, theme.Floor:Lerp(BLACK, 0.22), theme.Trim, {
		Name = "TeePad",
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	if not backFree then
		return
	end
	local text = string.format("HOLE %d · PAR %d", index, par)
	local labelOpts: Parts.LabelOpts = { TextColor = WHITE, Stroke = Color3.fromRGB(40, 26, 14), PixelsPerStud = 36 }
	if ctx.Tutorial then
		local tilt = math.rad(58)
		local size = Vector2.new(12, 4.4)
		local sign = leaningBoard(holeModel, teeTop, look, 11.2, -0.2, size, tilt, { Name = "InstructionSign", Color = theme.Rail, Material = WOOD, CanCollide = false, CanQuery = false })
		Parts.label(sign, Enum.NormalId.Front, "", { TextColor = WHITE, Stroke = Color3.fromRGB(40, 26, 14), PixelsPerStud = 30 })
		-- Header strip in the same plane, just above the instruction board.
		local header = Parts.block(parent, sign.CFrame * CFrame.new(0, size.Y / 2 + 0.75, 0), Vector3.new(size.X, 1.1, 0.35), {
			Name = "HoleSign",
			Color = theme.Accent:Lerp(BLACK, 0.35),
			CanCollide = false,
			CanQuery = false,
		})
		Parts.label(header, Enum.NormalId.Front, text, labelOpts)
		signDeck(parent, teeTop, look, HALF, 11.6, 12.6, -0.6, theme.Wall)
	else
		local sign = leaningBoard(parent, teeTop, look, 7.6, 0.3, Vector2.new(7, 2.4), math.rad(35), { Name = "HoleSign", Color = theme.Rail, Material = WOOD, CanCollide = false, CanQuery = false })
		Parts.label(sign, Enum.NormalId.Front, text, labelOpts)
		signDeck(parent, teeTop, look, HALF, 8.2, 8, 0, theme.Wall)
	end
end

local function buildCup(ctx: Ctx, parent: Instance, cup: Vector3, approach: Vector3)
	local theme = ctx.Theme
	local d = 2 * CUP_R + 0.2
	Parts.disc(parent, cup + up(0.04), d, 0.02, { Name = "Cup", Color = Color3.fromRGB(8, 8, 12), CanCollide = false, CanQuery = false, CastShadow = false })
	Parts.disc(parent, cup + up(0.015), d + 0.7, 0.02, { Name = "CupRing", Color = WHITE, CanCollide = false, CanQuery = false })
	local pole = cup + approach * (d / 2 + 0.15)
	local flagProps: Parts.Props = { Name = "Flag", Color = theme.Accent, Material = Enum.Material.Fabric, CanCollide = false, CanQuery = false }
	Parts.cylinder(parent, CFrame.new(pole + up(3.6)), 7.2, 0.18, { Name = "FlagPole", Color = Color3.fromRGB(240, 240, 245), CanCollide = false, CanQuery = false })
	local side = Vector3.new(-approach.Z, 0, approach.X)
	local flagPos = pole + up(6.3) + side * 1.32
	Parts.block(parent, CFrame.lookAt(flagPos, flagPos + approach), Vector3.new(2.5, 1.6, 0.08), flagProps)
	Parts.ball(parent, pole + up(7.3), 0.42, { Name = "FlagTip", Color = Color3.fromRGB(230, 190, 80), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
end

local function overviewFor(ctx: Ctx, tops: { Vector3 }, tee: Vector3, look: Vector3): CFrame
	local sum = Vector3.zero
	for _, p in tops do
		sum += p
	end
	local centre = sum / #tops
	local radius = 0
	for _, p in tops do
		radius = math.max(radius, Vector3.new(p.X - centre.X, 0, p.Z - centre.Z).Magnitude)
	end
	radius += HALF + 2
	local away = Vector3.new(tee.X - centre.X, 0, tee.Z - centre.Z)
	local back = if away.Magnitude > 1 then away.Unit - look * 0.8 else -look
	if back.Magnitude < 0.2 then
		back = -look
	end
	back = back.Unit
	local dist = math.clamp(radius * 1.25 + 16, 34, 90)
	local pos = centre + back * dist + up(dist * 0.8)
	pos = Vector3.new(math.clamp(pos.X, ctx.X0 + 4, ctx.X1 - 4), math.min(pos.Y, ctx.CeilingY - 4), math.clamp(pos.Z, ctx.Z0 + 4, ctx.Z1 - 4))
	return CFrame.lookAt(pos, centre)
end

-- Hole -------------------------------------------------------------------------

local function buildHole(ctx: Ctx, parent: Instance, index: number, plan: HolePlan, slotCentre: Vector3): (Hole, HoleInfo)
	local tiles = plan.Tiles
	local n = #tiles
	local model = Instance.new("Model")
	model.Name = "Hole" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("Par", plan.Par)
	local track = Parts.folder(model, "Track")
	local supports = Parts.folder(model, "Supports")
	local features = Parts.folder(model, "Features")
	local dressing = Parts.folder(model, "Dressing")

	local midX, midZ = (plan.MinX + plan.MaxX) / 2, (plan.MinZ + plan.MaxZ) / 2
	local centres: { Vector3 } = {}
	local tops: { Vector3 } = {}
	local byCell: { [number]: number } = {}
	local opens: { { boolean } } = {}
	for i, t in tiles do
		centres[i] = Vector3.new(slotCentre.X + (t.X - midX) * TILE, slotCentre.Y, slotCentre.Z + (t.Z - midZ) * TILE)
		tops[i] = centres[i] + up((t.Entry + t.Exit) / 2)
		byCell[cellKey(t.X, t.Z)] = i
		local o = { false, false, false, false }
		if i > 1 then
			o[opposite(t.In)] = true
		end
		if i < n then
			o[t.Out] = true
		end
		opens[i] = o
	end

	local boxes: { BasePart } = {}
	for i, t in tiles do
		local c = centres[i]
		buildFloor(ctx, track, t, c)
		buildSupport(ctx, supports, t, c)
		for d = 1, 4 do
			if not opens[i][d] then
				buildRail(ctx, track, t, c, d)
			end
		end
		if i > 1 and i < n then
			local kind = t.Feature
			if kind == "Bumper" then
				buildBumpers(ctx, features, t, tops[i])
			elseif kind == "Spinner" then
				buildSpinner(ctx, features, t, tops[i])
			elseif kind == "Pusher" then
				buildPusher(ctx, features, t, tops[i])
			elseif kind == "Boost" then
				buildBoost(ctx, features, t, tops[i])
			elseif kind == "Bridge" then
				buildBridge(ctx, features, t, c)
			end
		end
		if t.ChaosBox and ctx.ChaosBoxes then
			table.insert(boxes, buildChaosBox(ctx, features, tops[i]))
		end
	end

	-- Rail posts: outer corners, inner corners of bends (fills the notch between the
	-- two neighbours' rail ends) and joints where a rail continues into the next tile.
	local posted: { [string]: boolean } = {}
	local function post(x: number, z: number, level: number, dia: number)
		local key = string.format("%.1f,%.1f", x, z)
		if not posted[key] then
			posted[key] = true
			buildPost(ctx, track, x, z, level, dia)
		end
	end
	for i, t in tiles do
		local c = centres[i]
		local o = opens[i]
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local dX = if sx > 0 then 1 else 3
				local dZ = if sz > 0 then 2 else 4
				local railX, railZ = not o[dX], not o[dZ]
				local level = t.Entry
				if t.Ramp then
					local f = DIRS[t.Out]
					local s = if f[1] ~= 0 then sx * f[1] else sz * f[2]
					level = if s > 0 then t.Exit else t.Entry
				end
				if railX == railZ then
					post(c.X + sx * RAIL_IN, c.Z + sz * RAIL_IN, level, 1.2)
				elseif railZ then
					local j = byCell[cellKey(t.X + sx, t.Z)]
					if j and not opens[j][dZ] then
						post(c.X + sx * HALF, c.Z + sz * RAIL_IN, level, RAIL_W)
					end
				else
					local j = byCell[cellKey(t.X, t.Z + sz)]
					if j and not opens[j][dX] then
						post(c.X + sx * RAIL_IN, c.Z + sz * HALF, level, RAIL_W)
					end
				end
			end
		end
	end

	-- Tee, cup, signs.
	local first, last = tiles[1], tiles[n]
	local look = dirVec(first.Out)
	local teeTop = centres[1] + up(first.Exit)
	local tee = teeTop + up(BALL_R + 0.05)
	local cup = centres[n] + up(last.Entry)
	local backFree = byCell[cellKey(first.X - DIRS[first.Out][1], first.Z - DIRS[first.Out][2])] == nil
	buildTee(ctx, model, dressing, teeTop, look, index, plan.Par, backFree)
	buildCup(ctx, dressing, cup, dirVec(last.In))

	local overview = overviewFor(ctx, tops, tee, look)
	model.WorldPivot = CFrame.lookAt(tee, tee + look)
	model.Parent = parent

	local rects: { { number } } = {}
	for _, c in centres do
		table.insert(rects, { c.X - HALF, c.X + HALF, c.Z - HALF, c.Z + HALF })
	end
	local signArea = teeTop - look * 9
	table.insert(rects, { signArea.X - 7, signArea.X + 7, signArea.Z - 7, signArea.Z + 7 })

	local floorY = ctx.Origin.Y + plan.MinLevel
	local hole: Hole = {
		Index = index,
		Par = plan.Par,
		Tee = tee,
		TeeLook = look,
		Cup = cup,
		FloorY = floorY,
		Overview = overview,
		ChaosBoxes = boxes,
		Model = model,
		Tutorial = ctx.Tutorial,
	}
	local info: HoleInfo = {
		SlotX = slotCentre.X,
		Centre = Vector3.new(slotCentre.X, ctx.Origin.Y, slotCentre.Z),
		HalfX = (plan.MaxX - plan.MinX + 1) * HALF,
		HalfZ = (plan.MaxZ - plan.MinZ + 1) * HALF,
		Rects = rects,
		Camera = overview.Position,
	}
	return hole, info
end

-- Hall -------------------------------------------------------------------------

-- Is (x, z) at least r studs from every hole footprint and overview camera?
local function clearOfHoles(infos: { HoleInfo }, x: number, z: number, r: number): boolean
	for _, info in infos do
		for _, rc in info.Rects do
			local dx = math.max(rc[1] - x, 0, x - rc[2])
			local dz = math.max(rc[3] - z, 0, z - rc[4])
			if dx * dx + dz * dz < (r + 5) ^ 2 then
				return false
			end
		end
		local cam = info.Camera
		if (Vector3.new(cam.X - x, 0, cam.Z - z)).Magnitude < r + 12 then
			return false
		end
	end
	return true
end

-- Open-air landscape under and around the holes (terrain), instead of a hall.
local function buildLandscape(ctx: Ctx, infos: { HoleInfo }, rng: Random)
	local cx, cz = (ctx.X0 + ctx.X1) / 2, (ctx.Z0 + ctx.Z1) / 2
	local boothTop = ctx.HallFloorY - 17
	local keep = { { CFrame = CFrame.new(cx, boothTop + 4, cz), Size = Vector3.new(16, 14, 16) } }
	ctx.Terrain = CourseNature.landscape(ctx.Theme.Decor, {
		X0 = ctx.X0,
		X1 = ctx.X1,
		Z0 = ctx.Z0,
		Z1 = ctx.Z1,
		GroundY = ctx.HallFloorY - 0.5,
	}, rng, function(x, z, r)
		return clearOfHoles(infos, x, z, r)
	end, keep)
end

-- Decor ------------------------------------------------------------------------

local function buildDecor(ctx: Ctx, parent: Instance, infos: { HoleInfo }, rng: Random)
	local theme = ctx.Theme
	local kinds = CourseNature.Kinds[theme.Decor] or CourseNature.Kinds.Meadow
	local palette: CourseNature.Palette = { Foliage = theme.Foliage, Accent = theme.Accent, Rock = theme.WallAlt, Trim = theme.Trim, Water = theme.Water }
	local total = 0
	for _, k in kinds do
		total += k.Weight
	end
	local placed: { { number } } = {} -- {x, z, radius}
	local function free(x: number, z: number, r: number): boolean
		if x - r < ctx.X0 + 3 or x + r > ctx.X1 - 3 or z - r < ctx.Z0 + 3 or z + r > ctx.Z1 - 3 then
			return false
		end
		if not clearOfHoles(infos, x, z, r) then
			return false
		end
		for _, q in placed do
			if (Vector3.new(q[1] - x, 0, q[2] - z)).Magnitude < r + q[3] + 6 then
				return false
			end
		end
		return true
	end

	local groundY = ctx.HallFloorY - 0.5
	for _, info in infos do
		local count = 0
		for _ = 1, 60 do
			if count >= 12 then
				break
			end
			local roll = rng:NextNumber() * total
			local kind = kinds[#kinds]
			for _, k in kinds do
				roll -= k.Weight
				if roll <= 0 then
					kind = k
					break
				end
			end
			local x = info.SlotX + rng:NextNumber(-SLOT / 2, SLOT / 2)
			local z = rng:NextNumber(ctx.Z0 + 6, ctx.Z1 - 6)
			if free(x, z, kind.Radius) then
				table.insert(placed, { x, z, kind.Radius })
				count += 1
				local base = Vector3.new(x, groundY, z)
				local toHole = Vector3.new(info.Centre.X - x, 0, info.Centre.Z - z)
				local face = if toHole.Magnitude > 0.1 then toHole.Unit else Vector3.zAxis
				CourseNature.prop(parent, kind.Name, base, face, rng, palette)
			end
		end
	end

	-- Planting around the foot of every green: small props hugging the plateau edges.
	local small = CourseNature.Small[theme.Decor] or CourseNature.Small.Meadow
	local function insideAny(x: number, z: number, margin: number): boolean
		for _, info in infos do
			for _, rc in info.Rects do
				if x > rc[1] - margin and x < rc[2] + margin and z > rc[3] - margin and z < rc[4] + margin then
					return true
				end
			end
		end
		return false
	end
	for _, info in infos do
		for _, rc in info.Rects do
			local edges = {
				{ Vector3.new(rc[1], 0, rc[3]), Vector3.new(rc[2], 0, rc[3]), Vector3.new(0, 0, -1) },
				{ Vector3.new(rc[1], 0, rc[4]), Vector3.new(rc[2], 0, rc[4]), Vector3.new(0, 0, 1) },
				{ Vector3.new(rc[1], 0, rc[3]), Vector3.new(rc[1], 0, rc[4]), Vector3.new(-1, 0, 0) },
				{ Vector3.new(rc[2], 0, rc[3]), Vector3.new(rc[2], 0, rc[4]), Vector3.new(1, 0, 0) },
			}
			for _, e in edges do
				local a, b, out = e[1], e[2], e[3]
				do
					local p = a:Lerp(b, rng:NextNumber(0.3, 0.7)) + out * rng:NextNumber(2, 3.5)
					if rng:NextNumber() < 0.45 and not insideAny(p.X, p.Z, 1) then
						CourseNature.prop(parent, small[rng:NextInteger(1, #small)], Vector3.new(p.X, groundY, p.Z), -out, rng, palette)
					end
				end
			end
		end
	end

	-- Two loose bands of trees (or rock spires) framing the course on its long sides.
	local backdrop = CourseNature.Backdrop[theme.Decor] or "Oak"
	for band = 1, 2 do
		for x = ctx.X0 + 4, ctx.X1 - 4, 13 do
			for _, side in { -1, 1 } do
				if not (theme.Decor == "Tropical" and side > 0) and rng:NextNumber() < 0.8 then
					local z = (if side < 0 then ctx.Z0 else ctx.Z1) + side * (band * 13 + rng:NextNumber(-5, 7))
					CourseNature.prop(parent, backdrop, Vector3.new(x + rng:NextNumber(-6, 6), groundY, z), Vector3.new(0, 0, -side), rng, palette, true)
				end
			end
		end
	end
end

-- Booth ------------------------------------------------------------------------

-- Sealed 10x8x10 room under the hall floor where characters are parked.
local function buildBooth(ctx: Ctx, parent: Instance): CFrame
	local cx, cz = (ctx.X0 + ctx.X1) / 2, (ctx.Z0 + ctx.Z1) / 2
	local inner = Vector3.new(10, 8, 10)
	local floorTop = ctx.HallFloorY - 2 - 6 - 1 - inner.Y
	local mid = floorTop + inner.Y / 2
	local props: Parts.Props = { Name = "Booth", Color = ctx.Theme.WallAlt }
	Parts.block(parent, CFrame.new(cx, floorTop - 0.5, cz), Vector3.new(inner.X + 2, 1, inner.Z + 2), props)
	local ceiling = Parts.block(parent, CFrame.new(cx, floorTop + inner.Y + 0.5, cz), Vector3.new(inner.X + 2, 1, inner.Z + 2), props)
	Parts.block(parent, CFrame.new(cx - inner.X / 2 - 0.5, mid, cz), Vector3.new(1, inner.Y, inner.Z + 2), props)
	Parts.block(parent, CFrame.new(cx + inner.X / 2 + 0.5, mid, cz), Vector3.new(1, inner.Y, inner.Z + 2), props)
	Parts.block(parent, CFrame.new(cx, mid, cz - inner.Z / 2 - 0.5), Vector3.new(inner.X, inner.Y, 1), props)
	Parts.block(parent, CFrame.new(cx, mid, cz + inner.Z / 2 + 0.5), Vector3.new(inner.X, inner.Y, 1), props)
	Parts.light(ceiling, ctx.Theme.Light, 14, 1, "Surface")
	return CFrame.new(cx, floorTop + 3, cz)
end

-- Course -----------------------------------------------------------------------

local function assemble(theme: Maps.Theme, plans: { HolePlan }, origin: Vector3, chaosBoxes: boolean, tutorial: boolean, name: string, map: Maps.MapDef?, decorSeed: number): Course
	local n = #plans
	local lowest = 0
	for _, p in plans do
		lowest = math.min(lowest, p.MinLevel)
	end
	local ctx: Ctx = {
		Theme = theme,
		Origin = origin,
		-- Below every hole's out-of-bounds line, with margin for the ball radius.
		-- Ground level: just under every hole's out-of-bounds line (a ball resting on the
		-- ground is already OOB), so greens sit on low natural plateaus.
		HallFloorY = origin.Y + math.min(-10, lowest - Config.Physics.OOBDepth - 3),
		CeilingY = origin.Y + CEILING,
		X0 = origin.X - SLOT / 2 - HALL_END,
		X1 = origin.X + (n - 1) * SLOT + SLOT / 2 + HALL_END,
		Z0 = origin.Z - HALL_HALF_Z,
		Z1 = origin.Z + HALL_HALF_Z,
		ChaosBoxes = chaosBoxes,
		Tutorial = tutorial,
		LightBoost = if tutorial then 1.35 else 1,
		Unanchored = {},
		Pushers = {},
		Terrain = {},
	}

	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("MapId", if map then map.Id else "Tutorial")
	local holes: { Hole } = {}
	local infos: { HoleInfo } = {}
	for i, plan in plans do
		local hole, info = buildHole(ctx, model, i, plan, origin + Vector3.new((i - 1) * SLOT, 0, 0))
		holes[i] = hole
		infos[i] = info
	end
	buildLandscape(ctx, infos, Random.new(decorSeed + 1))
	buildDecor(ctx, Parts.model(model, "Decor"), infos, Random.new(decorSeed))
	local booth = buildBooth(ctx, Parts.model(model, "Booth"))
	model.WorldPivot = CFrame.new(origin)

	model.Parent = coursesFolder()
	for _, part in ctx.Unanchored do
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end

	local alive = true
	if #ctx.Pushers > 0 then
		task.spawn(function()
			while alive do
				task.wait(PUSH_PERIOD)
				if not alive or model.Parent == nil then
					break
				end
				for _, p in ctx.Pushers do
					p.Side = -p.Side
					p.Constraint.TargetPosition = p.Side * PUSH_OFFSET
				end
			end
		end)
	end

	return {
		Model = model,
		Map = map,
		Holes = holes,
		Booth = booth,
		Destroy = function()
			if not alive then
				return
			end
			alive = false
			model:Destroy()
			CourseNature.clear(ctx.Terrain)
		end,
	}
end

function CourseBuilder.build(map: Maps.MapDef, origin: Vector3, opts: BuildOpts): Course
	local theme = Maps.Themes[map.Theme] or Maps.Themes.Arcade
	local plans: { HolePlan } = {}
	for i = 1, map.Holes do
		plans[i] = planHole(map, i)
	end
	return assemble(theme, plans, origin, opts.ChaosBoxes, false, "Course_" .. map.Id, map, map.Seed * 17 + 5)
end

function CourseBuilder.buildTutorial(origin: Vector3): Course
	return assemble(TUTORIAL_THEME, tutorialPlans(), origin, true, true, "Tutorial", nil, 4242)
end

return CourseBuilder

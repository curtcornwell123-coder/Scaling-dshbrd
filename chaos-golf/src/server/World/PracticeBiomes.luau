--!strict
-- Practice range biomes. Whenever the live practice game changes, the range dresses itself
-- as that game's biome: the ground slab, the backdrop sky on the back wall, the lane floors,
-- rails and end walls, and themed props in the strips beside and behind the lanes.
--   Park   (Target Putting)      garden green: oaks, hedges, flower beds
--   Range  (Velocity Long-Drive) night driving range: floodlight towers, yardage boards, catch net
--   Yard   (Hazard Avoidance)    construction yard: cones, barriers, pallets, beacons, scaffold
--   Rink   (Bank Shot)           frozen rink: ice lanes (slippery), snowy pines, snow banks, ice blocks
--   Canyon (Gate Run)            desert canyon: sandstone lanes, cacti, spires, rocks
-- Props are decoration only (no collisions, no queries). Placement is seeded, so every server
-- shows the same dressing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CourseNature = require(script.Parent:WaitForChild("CourseNature"))
local LobbyTypes = require(script.Parent:WaitForChild("LobbyTypes"))
local Parts = require(script.Parent:WaitForChild("Parts"))

local PracticeBiomes = {}

type South = typeof((({} :: any) :: LobbyTypes.Lobby).South)
type Look = {
	Ground: Color3,
	GroundMat: Enum.Material,
	SkyTop: Color3,
	SkyBottom: Color3,
	Lane: Color3,
	LaneMat: Enum.Material,
	LaneSurface: string?, -- BallService surface attribute ("Ice")
	Rail: Color3,
	RailMat: Enum.Material,
	Cap: Color3,
	Back: Color3,
	Palette: CourseNature.Palette,
}

local hex = Color3.fromHex
local M = Enum.Material

local LOOKS: { [string]: Look } = {
	Park = {
		Ground = hex("#5E9E45"), GroundMat = M.Grass,
		SkyTop = hex("#6FB2E3"), SkyBottom = hex("#E8F4FA"),
		Lane = hex("#4E9A4A"), LaneMat = M.Fabric,
		Rail = hex("#F6F3ED"), RailMat = M.Marble, Cap = hex("#C8A15A"), Back = hex("#4B3324"),
		Palette = { Foliage = hex("#4F8A3C"), Accent = hex("#F4C542"), Rock = hex("#8C8A84"), Trim = hex("#FFFFFF"), Water = hex("#69B4D2") },
	},
	Range = {
		Ground = hex("#2F5A2B"), GroundMat = M.Grass,
		SkyTop = hex("#0B1530"), SkyBottom = hex("#33467A"),
		Lane = hex("#2F353C"), LaneMat = M.Fabric,
		Rail = hex("#2A2C30"), RailMat = M.Metal, Cap = hex("#F2C14E"), Back = hex("#2A2C30"),
		Palette = { Foliage = hex("#2E5A2A"), Accent = hex("#F2C14E"), Rock = hex("#5A5D63"), Trim = hex("#FFFFFF"), Water = hex("#3A6EA5") },
	},
	Yard = {
		Ground = hex("#9A9EA3"), GroundMat = M.Concrete,
		SkyTop = hex("#8E9AA6"), SkyBottom = hex("#D9C7A7"),
		Lane = hex("#A4A9AE"), LaneMat = M.Concrete,
		Rail = hex("#F2B705"), RailMat = M.SmoothPlastic, Cap = hex("#1D1E21"), Back = hex("#1D1E21"),
		Palette = { Foliage = hex("#6B7B4A"), Accent = hex("#F2B705"), Rock = hex("#7D7F84"), Trim = hex("#FFFFFF"), Water = hex("#5D7A8C") },
	},
	Rink = {
		Ground = hex("#EEF5FA"), GroundMat = M.Snow,
		SkyTop = hex("#9CC3DD"), SkyBottom = hex("#F3F8FB"),
		Lane = hex("#D6EEF8"), LaneMat = M.Ice, LaneSurface = "Ice",
		Rail = hex("#F4F7FA"), RailMat = M.SmoothPlastic, Cap = hex("#2A6F97"), Back = hex("#F4F7FA"),
		Palette = { Foliage = hex("#2F5D45"), Accent = hex("#5BC0EB"), Rock = hex("#8C99A6"), Trim = hex("#FFFFFF"), Water = hex("#9AD1F5") },
	},
	Canyon = {
		Ground = hex("#D9B382"), GroundMat = M.Sand,
		SkyTop = hex("#F08A4B"), SkyBottom = hex("#FCE3B0"),
		Lane = hex("#C99A6B"), LaneMat = M.Sandstone,
		Rail = hex("#B5542C"), RailMat = M.Sandstone, Cap = hex("#F2D0A4"), Back = hex("#8F4A2B"),
		Palette = { Foliage = hex("#6E8B3D"), Accent = hex("#E07A2F"), Rock = hex("#B87A4B"), Trim = hex("#FFFFFF"), Water = hex("#5DA9C9") },
	},
}

PracticeBiomes.Looks = LOOKS

local function deco(color: Color3, material: Enum.Material?, name: string?): Parts.Props
	return { Name = name or "Decor", Color = color, Material = material or M.SmoothPlastic, CanCollide = false, CanQuery = false, CanTouch = false }
end

-- Crafted props not in CourseNature -------------------------------------------------------

local function cone(f: Instance, base: Vector3)
	Parts.block(f, CFrame.new(base + Vector3.new(0, 0.05, 0)), Vector3.new(1.4, 0.1, 1.4), deco(hex("#1D1E21")))
	for k = 0, 3 do
		local col = if k == 2 then hex("#F4F4F4") else hex("#F26B1D")
		Parts.cylinder(f, CFrame.new(base + Vector3.new(0, 0.3 + k * 0.42, 0)), 0.42, 1.1 - k * 0.22, deco(col))
	end
end

local function barrier(f: Instance, cf: CFrame)
	Parts.block(f, cf * CFrame.new(0, 0.45, 0), Vector3.new(4, 0.9, 1.4), deco(hex("#C9CCD1"), M.Concrete))
	Parts.block(f, cf * CFrame.new(0, 1.35, 0), Vector3.new(4, 0.9, 0.7), deco(hex("#C9CCD1"), M.Concrete))
	for k = -1, 1 do
		Parts.block(f, cf * CFrame.new(k * 1.3, 1.4, -0.36), Vector3.new(0.6, 0.6, 0.02), deco(if k == 0 then hex("#F2B705") else hex("#1D1E21")))
	end
end

local function pallets(f: Instance, cf: CFrame, rng: Random)
	local n = rng:NextInteger(2, 4)
	for k = 0, n - 1 do
		local p = cf * CFrame.new(0, 0.3 + k * 0.62, 0) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0)
		for s = -1, 1 do
			Parts.block(f, p * CFrame.new(s * 1.2, -0.12, 0), Vector3.new(0.5, 0.3, 3), deco(hex("#9C7A4F"), M.Wood))
		end
		for s = -2, 2 do
			Parts.block(f, p * CFrame.new(0, 0.1, s * 0.62), Vector3.new(3, 0.12, 0.45), deco(hex("#B48E5C"), M.WoodPlanks))
		end
	end
end

local function beacon(f: Instance, base: Vector3)
	Parts.cylinder(f, CFrame.new(base + Vector3.new(0, 2, 0)), 4, 0.3, deco(hex("#2A2C30"), M.Metal))
	local lamp = Parts.ball(f, base + Vector3.new(0, 4.3, 0), 0.8, deco(hex("#FFA51F"), M.Neon, "Beacon"))
	Parts.light(lamp, hex("#FFA51F"), 12, 0.9)
end

local function scaffold(f: Instance, cf: CFrame)
	local w, d, h = 6, 3, 9
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Parts.block(f, cf * CFrame.new(sx * w / 2, h / 2, sz * d / 2), Vector3.new(0.25, h, 0.25), deco(hex("#8E9196"), M.Metal))
		end
	end
	for y = 3, h, 3 do
		Parts.block(f, cf * CFrame.new(0, y, 0), Vector3.new(w + 0.3, 0.2, d + 0.3), deco(hex("#B48E5C"), M.WoodPlanks))
		Parts.block(f, cf * CFrame.new(0, y + 1, -d / 2), Vector3.new(w, 0.12, 0.12), deco(hex("#F2B705")))
	end
	Parts.rod(f, (cf * CFrame.new(-w / 2, 0.2, -d / 2)).Position, (cf * CFrame.new(w / 2, 3, -d / 2)).Position, 0.18, deco(hex("#8E9196"), M.Metal))
	Parts.rod(f, (cf * CFrame.new(w / 2, 3, -d / 2)).Position, (cf * CFrame.new(-w / 2, 6, -d / 2)).Position, 0.18, deco(hex("#8E9196"), M.Metal))
end

local function floodTower(f: Instance, base: Vector3, aim: Vector3)
	Parts.cylinder(f, CFrame.new(base + Vector3.new(0, 8, 0)), 16, 0.6, deco(hex("#2A2C30"), M.Metal))
	local headCF = CFrame.lookAt(base + Vector3.new(0, 16.4, 0), aim)
	local head = Parts.block(f, headCF, Vector3.new(4, 1.6, 0.8), deco(hex("#2A2C30"), M.Metal))
	for k = -1, 1 do
		Parts.block(f, headCF * CFrame.new(k * 1.25, 0, -0.42), Vector3.new(1, 1, 0.05), deco(hex("#FFF4D6"), M.Neon, "Lamp"))
	end
	local spot = Parts.light(head, hex("#FFF4D6"), 40, 1.1, "Spot") :: SpotLight
	spot.Face = Enum.NormalId.Front
	spot.Angle = 60
end

local function yardage(f: Instance, cf: CFrame, n: number)
	Parts.block(f, cf * CFrame.new(0, 1.2, 0), Vector3.new(0.25, 2.4, 0.25), deco(hex("#F4F4F4")))
	local board = Parts.block(f, cf * CFrame.new(0, 3.1, 0), Vector3.new(3.4, 1.6, 0.2), deco(hex("#F2C14E")))
	Parts.label(board, Enum.NormalId.Front, tostring(n), { TextColor = hex("#1D1E21"), Font = Config.Font, PixelsPerStud = 40 })
end

local function snowMound(f: Instance, base: Vector3, rng: Random)
	for _ = 1, 3 do
		local s = rng:NextNumber(2.2, 4)
		Parts.ball(f, base + Vector3.new(rng:NextNumber(-1.5, 1.5), -s * 0.25, rng:NextNumber(-1.5, 1.5)), s, deco(hex("#F4F8FB"), M.Snow))
	end
end

local function iceBlock(f: Instance, base: Vector3, rng: Random)
	local s = rng:NextNumber(1.6, 2.6)
	local cf = CFrame.new(base + Vector3.new(0, s * 0.45, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15))
	local p = Parts.block(f, cf, Vector3.new(s, s, s * 0.9), deco(hex("#A9D8F0"), M.Glass))
	p.Transparency = 0.3
	Parts.block(f, cf * CFrame.new(0, s * 0.62, 0), Vector3.new(s * 0.9, s * 0.25, s * 0.8), deco(hex("#F4F8FB"), M.Snow))
end

local function lantern(f: Instance, base: Vector3)
	Parts.cylinder(f, CFrame.new(base + Vector3.new(0, 2.2, 0)), 4.4, 0.28, deco(hex("#2A2C30"), M.Metal))
	local glass = Parts.block(f, CFrame.new(base + Vector3.new(0, 4.8, 0)), Vector3.new(0.9, 1.1, 0.9), deco(hex("#FFE3B3"), M.Neon, "Lamp"))
	Parts.block(f, CFrame.new(base + Vector3.new(0, 5.5, 0)), Vector3.new(1.2, 0.2, 1.2), deco(hex("#2A2C30"), M.Metal))
	Parts.light(glass, hex("#FFE3B3"), 14, 0.8)
end

local function hedge(f: Instance, cf: CFrame, len: number, pal: CourseNature.Palette)
	Parts.roundedBox(f, cf * CFrame.new(0, 1.2, 0), Vector3.new(len, 2.4, 1.8), 0.6, deco(pal.Foliage, M.LeafyGrass))
end

-- Strip layout ----------------------------------------------------------------------------

type Spot = { Pos: Vector3, Face: Vector3, Tall: boolean }

-- Candidate prop spots (world), seeded: left and right strips beside the lanes and the back
-- strip behind them. Keeps clear of the token hut (left), the best-scores board (right) and
-- the broadcast TV (back centre) for tall props.
local function spots(south: South, rng: Random): { Spot }
	local R = south.Bounds
	local W, D = south.Size.X / 2, south.Size.Z / 2
	local first, last = south.Lanes[1], south.Lanes[#south.Lanes]
	local laneHalf = math.abs(R:PointToObjectSpace(last.Origin.Position).X - R:PointToObjectSpace(first.Origin.Position).X) / 2 + first.Width / 2 + 2
	local u0 = -R:PointToObjectSpace(first.Origin.Position).Z
	local laneEnd = u0 + first.Length + 2
	local out: { Spot } = {}
	local function add(x: number, d: number, tall: boolean)
		local p = R:PointToWorldSpace(Vector3.new(x, 0, -d))
		local centre = R:PointToWorldSpace(Vector3.new(0, 0, -d))
		table.insert(out, { Pos = p, Face = (centre - p).Unit, Tall = tall })
	end
	for _, side in { -1, 1 } do
		local x0, x1 = laneHalf + 2, W - 4
		local d = u0 - 3
		while d < D - 4 do
			local nearHut = side < 0 and d > -6 and d < 10
			local nearBoard = side > 0 and d > -9 and d < 13
			local x = side * rng:NextNumber(x0, x1)
			if not nearHut then
				add(x, d, not nearBoard)
			end
			d += rng:NextNumber(5.5, 8)
		end
	end
	local x = -W + 6
	while x < W - 6 do
		local tall = math.abs(x) > 14
		add(x + rng:NextNumber(-1.5, 1.5), rng:NextNumber(laneEnd + 1, D - 3), tall)
		x += rng:NextNumber(6, 9)
	end
	return out
end

local function pick(list: { string }, rng: Random): string
	return list[rng:NextInteger(1, #list)]
end

local function dress(biome: string, f: Folder, south: South, rng: Random, pal: CourseNature.Palette)
	local all = spots(south, rng)
	if biome == "Range" then
		-- Floodlight towers along both sides, yardage boards down the back, a catch net.
		local R = south.Bounds
		local W, D = south.Size.X / 2, south.Size.Z / 2
		for i, s in all do
			if s.Tall and i % 3 == 0 then
				floodTower(f, s.Pos, R:PointToWorldSpace(Vector3.new(0, 0, -(D * 0.2))))
			elseif i % 3 == 1 then
				CourseNature.prop(f, "Bush", s.Pos, s.Face, rng, pal)
			end
		end
		local yards = { 100, 150, 200, 250 }
		for k, n in yards do
			yardage(f, CFrame.lookAt(R:PointToWorldSpace(Vector3.new((k - 2.5) * 22, 0, -(D - 6))), R:PointToWorldSpace(Vector3.new((k - 2.5) * 22, 0, 0))), n)
		end
		Parts.block(f, R * CFrame.new(0, 9, -(D - 2.2)), Vector3.new(2 * W - 8, 18, 0.06), { Name = "Net", Color = hex("#1F2226"), Material = M.Fabric, Transparency = 0.82, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		for k = 0, 5 do
			Parts.rod(f, R:PointToWorldSpace(Vector3.new(-W + 4, 1 + k * 3.2, -(D - 2.2))), R:PointToWorldSpace(Vector3.new(W - 4, 1 + k * 3.2, -(D - 2.2))), 0.08, deco(hex("#2A2C30"), M.Metal))
		end
		return
	end
	for i, s in all do
		if biome == "Park" then
			if s.Tall and i % 2 == 0 then
				CourseNature.prop(f, "Oak", s.Pos, s.Face, rng, pal)
			elseif i % 3 == 0 then
				hedge(f, CFrame.lookAt(s.Pos, s.Pos + s.Face), rng:NextNumber(5, 8), pal)
			else
				CourseNature.prop(f, pick({ "Flowers", "Bush", "Flowers", "Rock" }, rng), s.Pos, s.Face, rng, pal)
			end
		elseif biome == "Yard" then
			local k = i % 6
			if k == 0 and s.Tall then
				scaffold(f, CFrame.lookAt(s.Pos, s.Pos + s.Face))
			elseif k == 1 then
				barrier(f, CFrame.lookAt(s.Pos, s.Pos + s.Face) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0))
			elseif k == 2 then
				pallets(f, CFrame.new(s.Pos), rng)
			elseif k == 3 then
				beacon(f, s.Pos)
			else
				for c = 0, 2 do
					cone(f, s.Pos + Vector3.new(c * 1.8 - 1.8, 0, rng:NextNumber(-0.6, 0.6)))
				end
			end
		elseif biome == "Rink" then
			if s.Tall and i % 2 == 0 then
				CourseNature.prop(f, "Pine", s.Pos, s.Face, rng, pal)
			elseif i % 4 == 1 then
				snowMound(f, s.Pos, rng)
			elseif i % 4 == 3 then
				lantern(f, s.Pos)
			else
				iceBlock(f, s.Pos, rng)
			end
		elseif biome == "Canyon" then
			if s.Tall and i % 3 == 0 then
				CourseNature.prop(f, "Spire", s.Pos, s.Face, rng, pal)
			else
				CourseNature.prop(f, pick({ "Cactus", "Cactus", "Rock", "DryBush" }, rng), s.Pos, s.Face, rng, pal)
			end
		end
	end
end

-- Restyles the range for `biome` (a Minigames Biome id). `seed` keeps every server alike.
function PracticeBiomes.apply(south: South, biome: string, seed: number)
	local look = LOOKS[biome] or LOOKS.Park
	local rng = Random.new(seed)
	south.Biome:ClearAllChildren()
	for _, g in south.GroundParts do
		g.Color = look.Ground
		g.Material = look.GroundMat
	end
	for _, child in south.Backdrop:GetChildren() do
		if child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end
	south.Backdrop.Color = look.SkyBottom
	Parts.gradientFace(south.Backdrop, Enum.NormalId.Front, look.SkyTop, look.SkyBottom, 90)
	for _, lane in south.Lanes do
		-- The lane floor: main stretch, end stretch and any cup-cut copy of the end (LaneFloor).
		local floors: { BasePart } = { lane.Surface, lane.End }
		for _, d in lane.Props:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("LaneFloor") then
				table.insert(floors, d)
			end
		end
		for _, f in floors do
			f.Color = look.Lane
			f.Material = look.LaneMat
			f:SetAttribute("Surface", look.LaneSurface)
		end
		for _, r in lane.Rails do
			r.Color = look.Rail
			r.Material = look.RailMat
		end
		for _, c in lane.Caps do
			c.Color = look.Cap
		end
		lane.Back.Color = look.Back
		lane.Back.Material = look.RailMat
	end
	dress(biome, south.Biome, south, rng, look.Palette)
end

return PracticeBiomes

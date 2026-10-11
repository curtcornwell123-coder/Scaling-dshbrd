--!strict
-- A real golf cup: a round hole cut into the green, lined in white with a dark bottom, so
-- the ball drops, rattles, hops the hole or lips out with real physics. The hole (radius
-- Config.Physics.CupRadius, Depth deep) is cut through every upright floor block it passes
-- through - each is rebuilt as blocks round a square plus wedge fans for the round edge
-- (a 24-sided opening) - and gets a collidable liner and bottom of its own, so it also
-- works over an open well. An invisible lid flush with the green blocks only Tiny-Cup balls
-- (BallService judges them on the flat, see CupPhysics) and characters (feet don't catch).

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Parts = require(script.Parent:WaitForChild("Parts"))

local CupHole = {}

CupHole.Depth = 1.9 -- rim to bottom: the ball (1.5) sits fully below the green
CupHole.Segments = 24
CupHole.RimInset = 0.2 -- band of turf/soil above the liner, as on a real green
CupHole.LidGroup = "GolfCupLid"

local WHITE = Color3.fromRGB(246, 246, 242)
local LINER_LOW = Color3.fromRGB(58, 60, 64)
local BOTTOM = Color3.fromRGB(30, 28, 26)
-- A plastic cup set in soil: a dead knock, little bounce.
local LINER_PHYS = PhysicalProperties.new(1.5, 0.4, 0.2, 1, 1)
local BOTTOM_PHYS = PhysicalProperties.new(1.5, 0.6, 0.1, 1, 1)

local lids: { [string]: BasePart } = {}

local function key(p: Vector3): string
	return string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
end

function CupHole.registerGroup()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CupHole.LidGroup)
	end)
end

-- The lid of the real cup at `cup` (nil = no real hole there, the cup is painted on).
function CupHole.lidAt(cup: Vector3): BasePart?
	local k = key(cup)
	local lid = lids[k]
	if lid and not lid.Parent then
		lids[k] = nil
		return nil
	end
	return lid
end

local function copyLook(from: BasePart, to: BasePart)
	to.Anchored = true
	to.Color = from.Color
	to.Material = from.Material
	to.MaterialVariant = from.MaterialVariant
	to.Reflectance = from.Reflectance
	to.Transparency = from.Transparency
	to.CanCollide = from.CanCollide
	to.CanQuery = from.CanQuery
	to.CanTouch = from.CanTouch
	to.CastShadow = from.CastShadow
	to.CollisionGroup = from.CollisionGroup
	to.CustomPhysicalProperties = from.CustomPhysicalProperties
	to.Name = from.Name
	for k, v in from:GetAttributes() do
		to:SetAttribute(k, v)
	end
end

-- True when the hole at `cup` passes through this part and it can be cut (an upright block
-- holding the whole opening).
local function crosses(part: BasePart, cup: Vector3): boolean
	if not part:IsA("Part") or part.Shape ~= Enum.PartType.Block or part.CFrame.UpVector.Y < 0.999 then
		return false
	end
	local half = part.Size / 2
	local l = part.CFrame:PointToObjectSpace(cup)
	local R = Config.Physics.CupRadius
	local top, bottom = part.Position.Y + half.Y, part.Position.Y - half.Y
	return bottom < cup.Y - 1e-3 and top > cup.Y - CupHole.Depth + 1e-3 and math.abs(l.X) + R < half.X and math.abs(l.Z) + R < half.Z
end

-- Cuts the hole through `part`: it is replaced by four blocks round a square and four wedge
-- fans filling the square's corners up to the round edge. Returns the pieces.
function CupHole.cut(part: BasePart, cup: Vector3): { BasePart }
	if not crosses(part, cup) then
		return { part }
	end
	local cf, size = part.CFrame, part.Size
	local l = cf:PointToObjectSpace(cup)
	local R = Config.Physics.CupRadius
	local hx, hz = size.X / 2, size.Z / 2
	local parent = part.Parent
	local pieces: { BasePart } = {}
	local function rect(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 < 0.01 or z1 - z0 < 0.01 then
			return
		end
		local p = part:Clone()
		p:ClearAllChildren()
		p.Size = Vector3.new(x1 - x0, size.Y, z1 - z0)
		p.CFrame = cf * CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
		p.Parent = parent
		table.insert(pieces, p)
	end
	rect(-hx, l.X - R, -hz, hz)
	rect(l.X + R, hx, -hz, hz)
	rect(l.X - R, l.X + R, -hz, l.Z - R)
	rect(l.X - R, l.X + R, l.Z + R, hz)
	local N = CupHole.Segments
	local function rim(i: number): Vector3
		local a = i / N * math.pi * 2
		return cf * Vector3.new(l.X + R * math.cos(a), 0, l.Z + R * math.sin(a))
	end
	for q = 0, 3 do
		local corner = cf * Vector3.new(l.X + (if q == 0 or q == 3 then R else -R), 0, l.Z + (if q <= 1 then R else -R))
		for i = q * N // 4, (q + 1) * N // 4 - 1 do
			for _, w in Parts.triangle(parent :: Instance, corner, rim(i), rim(i + 1), size.Y) do
				copyLook(part, w)
				table.insert(pieces, w)
			end
		end
	end
	part:Destroy()
	return pieces
end

-- Cuts the hole through every floor block under `root` that it passes through.
function CupHole.carve(root: Instance, cup: Vector3): number
	local hits: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and crosses(d, cup) then
			table.insert(hits, d)
		end
	end
	for _, p in hits do
		CupHole.cut(p, cup)
	end
	return #hits
end

export type Opening = { CFrame: CFrame, Size: Vector2 } -- a level rectangle (X by Z of its CFrame)

-- Cuts rectangular openings (wells for cups to sit in) out of an upright block: it is replaced
-- by strips covering everything else. Returns the pieces (the part itself if nothing is cut).
function CupHole.cutRects(part: BasePart, openings: { Opening }): { BasePart }
	local cf, size = part.CFrame, part.Size
	local hx, hz = size.X / 2, size.Z / 2
	type Rect = { X0: number, X1: number, Z0: number, Z1: number }
	local rects: { Rect } = {}
	for _, o in openings do
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, c in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
			local l = cf:PointToObjectSpace(o.CFrame * Vector3.new(c.X * o.Size.X / 2, 0, c.Z * o.Size.Y / 2))
			x0, x1, z0, z1 = math.min(x0, l.X), math.max(x1, l.X), math.min(z0, l.Z), math.max(z1, l.Z)
		end
		x0, x1, z0, z1 = math.max(x0, -hx), math.min(x1, hx), math.max(z0, -hz), math.min(z1, hz)
		if x1 > x0 and z1 > z0 then
			table.insert(rects, { X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 })
		end
	end
	if #rects == 0 then
		return { part }
	end
	local cuts = { -hz, hz }
	for _, r in rects do
		table.insert(cuts, r.Z0)
		table.insert(cuts, r.Z1)
	end
	table.sort(cuts)
	local pieces: { BasePart } = {}
	for i = 1, #cuts - 1 do
		local za, zb = cuts[i], cuts[i + 1]
		if zb - za > 0.01 then
			-- Covered x-intervals in this band: the whole width minus the openings across it.
			local holes = {}
			for _, r in rects do
				if r.Z0 <= za + 1e-6 and r.Z1 >= zb - 1e-6 then
					table.insert(holes, r)
				end
			end
			table.sort(holes, function(a, b)
				return a.X0 < b.X0
			end)
			local x = -hx
			local function strip(xa: number, xb: number)
				if xb - xa > 0.01 then
					local p = part:Clone()
					p:ClearAllChildren()
					p.Size = Vector3.new(xb - xa, size.Y, zb - za)
					p.CFrame = cf * CFrame.new((xa + xb) / 2, 0, (za + zb) / 2)
					p.Parent = part.Parent
					table.insert(pieces, p)
				end
			end
			for _, h in holes do
				strip(x, h.X0)
				x = math.max(x, h.X1)
			end
			strip(x, hx)
		end
	end
	part:Destroy()
	return pieces
end

-- The cup itself under a hole cut at `cup` (the rim centre, on the green's top surface):
-- white liner turning dark lower down, a dark bottom and the Tiny-Cup lid.
function CupHole.build(parent: Instance, cup: Vector3): Model
	CupHole.registerGroup()
	local m = Parts.model(parent, "CupHole")
	local R, N, D = Config.Physics.CupRadius, CupHole.Segments, CupHole.Depth
	local edge = R * math.cos(math.pi / N) -- the opening's flat sides
	local seg = 2 * R * math.sin(math.pi / N) + 0.02
	local t = 0.12
	type Band = { Top: number, Bottom: number, Color: Color3, Name: string }
	local bands: { Band } = {
		{ Top = CupHole.RimInset, Bottom = 0.75, Color = WHITE, Name = "Liner" },
		{ Top = 0.75, Bottom = D, Color = LINER_LOW, Name = "LinerLow" },
	}
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		for _, b in bands do
			-- A hair inside the cut walls so the liner covers them (no z-fighting).
			local c = cup + dir * (edge - 0.015 + t / 2) - Vector3.new(0, (b.Top + b.Bottom) / 2, 0)
			local p = Parts.block(m, CFrame.lookAt(c, c + dir), Vector3.new(seg, b.Bottom - b.Top, t), {
				Name = b.Name,
				Color = b.Color,
				Material = Enum.Material.SmoothPlastic,
				CanQuery = false,
				CastShadow = false,
			})
			p.CustomPhysicalProperties = LINER_PHYS
		end
	end
	local bottom = Parts.cylinder(m, CFrame.new(cup - Vector3.new(0, D + 0.1, 0)), 0.2, 2 * R + 0.3, { Name = "CupBottom", Color = BOTTOM, Material = Enum.Material.SmoothPlastic })
	bottom.CustomPhysicalProperties = BOTTOM_PHYS
	local lid = Parts.cylinder(m, CFrame.new(cup - Vector3.new(0, 0.1, 0)), 0.2, 2 * R + 0.1, {
		Name = "CupLid",
		Transparency = 1,
		CanCollide = true,
		CanQuery = true,
		CanTouch = false,
		CastShadow = false,
	})
	lid.CollisionGroup = CupHole.LidGroup
	lids[key(cup)] = lid
	return m
end

return CupHole

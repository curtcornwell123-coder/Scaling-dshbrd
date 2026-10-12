--!strict
-- Cup physics on the flat. Real cups are holes cut in the green (CupHole) and real physics
-- drops balls in or bounces them out; this module judges a ball rolling over a cup it can't
-- physically fall into - a Tiny-Cup ball on the cup's lid, or a cup painted on a floor that
-- couldn't be cut - from its path over the cup (flat, cup-relative x/z). Its lip pull also
-- runs on real cups (`lip`):
--   * swept: the path since the last step is tested, so a fast ball or a slow server frame
--     can't skip over the cup;
--   * how fast a ball can drop depends on its line: dead centre drops up to MaxSinkSpeed, a
--     line grazing the rim only CupEdgeSink of that (less time over the hole to fall);
--   * too fast: the ball runs over the hole and meets the far rim - it loses pace along the
--     rim, pops up (higher the harder it hits) and an off-centre ball is turned (lip-out);
--   * half on the hole: a slow ball whose centre is within the lip zone past the rim tips
--     in; one that stops right on the lip teeters for CupLipHang seconds first.
-- Pure math (numbers only) so the unit tests can roll balls through it.

local Config = require(script.Parent:WaitForChild("Config"))

local CupPhysics = {}

export type State = {
	Pass: number?, -- running over the hole too fast: how close it came to dropping (0-1)
	Hang: number, -- clock time a ball that stopped on the lip starts to drop (0 = not hanging)
}

function CupPhysics.newState(): State
	return { Pass = nil, Hang = 0 }
end

function CupPhysics.reset(s: State)
	s.Pass = nil
	s.Hang = 0
end

-- Fastest a ball can drop in when its line passes `b` studs from the centre of a cup of radius R.
function CupPhysics.captureSpeed(b: number, R: number): number
	local P = Config.Physics
	local f = math.sqrt(math.max(0, 1 - (math.min(b, R) / R) ^ 2))
	return P.MaxSinkSpeed * (P.CupEdgeSink + (1 - P.CupEdgeSink) * f)
end

-- Width of the ring past the rim where a slow ball tips in (shrinks with Tiny Cup).
function CupPhysics.lipZone(R: number): number
	return Config.Physics.CupLipZone * R / Config.Physics.CupRadius
end

-- Closest distance from the cup centre to the segment (x0, z0) -> (x1, z1).
local function segmentDistance(x0: number, z0: number, x1: number, z1: number): number
	local dx, dz = x1 - x0, z1 - z0
	local len2 = dx * dx + dz * dz
	local t = if len2 > 1e-9 then math.clamp(-(x0 * dx + z0 * dz) / len2, 0, 1) else 0
	local cx, cz = x0 + dx * t, z0 + dz * t
	return math.sqrt(cx * cx + cz * cz)
end

-- The far rim: pace lost along the rim normal (which also turns an off-centre ball) and a hop.
-- q = how close the ball came to dropping: 1 = just too fast (hits the back wall hard).
local function rimKick(x: number, z: number, vx: number, vz: number, speed: number, R: number, q: number): (number, number, number)
	-- Where the line leaves the cup: its closest point to the centre plus half the chord.
	local ux, uz = vx / speed, vz / speed
	local along = x * ux + z * uz
	local cx, cz = x - ux * along, z - uz * along
	local half = math.sqrt(math.max(0, R * R - (cx * cx + cz * cz)))
	local nx, nz = cx + ux * half, cz + uz * half
	local n = math.sqrt(nx * nx + nz * nz)
	if n < 1e-6 then
		nx, nz, n = ux, uz, 1
	end
	nx, nz = nx / n, nz / n
	local vn = math.max(0, vx * nx + vz * nz)
	local loss = 0.12 + 0.48 * q
	local hop = math.clamp(5 + 0.45 * vn * (0.4 + 0.6 * q), 6, 16)
	return vx - nx * vn * loss, vz - nz * vn * loss, hop
end

-- One step for a ball at cup level. (x0, z0) / (x1, z1): ball centre relative to the cup
-- centre at the last step and now; (vx, vz): horizontal velocity after rolling friction.
-- Returns: sink, new vx, new vz, hop (upward speed to add, 0 = none), lip (teetering or
-- being drawn in - keep it from coming to rest).
function CupPhysics.step(s: State, x0: number, z0: number, x1: number, z1: number, vx: number, vz: number, grounded: boolean, dt: number, now: number, R: number): (boolean, number, number, number, boolean)
	local speed = math.sqrt(vx * vx + vz * vz)
	local dist = math.sqrt(x1 * x1 + z1 * z1)
	-- A teleport (placing, a reset) is not a path.
	if math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) > speed * dt * 2 + 1 then
		x0, z0 = x1, z1
	end
	-- Perpendicular distance from the cup centre to the ball's line.
	local b = if speed > 0.05 then math.abs(x1 * vz - z1 * vx) / speed else dist

	local pass = s.Pass
	if pass then
		if speed <= CupPhysics.captureSpeed(b, R) then
			CupPhysics.reset(s) -- slowed enough over the hole
			return true, 0, 0, 0, false
		elseif dist >= R then
			s.Pass = nil
			local nvx, nvz, hop = rimKick(x1, z1, vx, vz, speed, R, pass)
			return false, nvx, nvz, hop, false
		end
		return false, vx, vz, 0, false
	end

	if segmentDistance(x0, z0, x1, z1) < R then
		local cap = CupPhysics.captureSpeed(b, R)
		if speed <= cap then
			CupPhysics.reset(s)
			return true, 0, 0, 0, false
		end
		local q = math.clamp((cap / speed) ^ 2, 0, 1)
		if dist < R then
			s.Pass = q -- still over the hole: the far rim decides
			return false, vx, vz, 0, false
		end
		-- Crossed the whole cup within one step.
		local nvx, nvz, hop = rimKick(x1, z1, vx, vz, speed, R, q)
		return false, nvx, nvz, hop, false
	end

	local nvx, nvz, lip = CupPhysics.lip(s, x1, z1, vx, vz, grounded, dt, now, R)
	return false, nvx, nvz, 0, lip
end

-- Round the rim, as on a real green:
--   * edge break: the turf round a hole is worn a touch low, so any rolling ball whose edge
--     hangs over the rim curls toward the hole - harder the further it hangs over, less the
--     faster it's going (a firm putt barely bends, a dying one is pulled round to the cup);
--   * half on the hole: a slow ball whose centre is within the lip zone is drawn in; one that
--     stops right on the lip teeters for CupLipHang seconds first.
-- Returns new vx, vz and whether it is on the lip (keep it from coming to rest).
function CupPhysics.lip(s: State, x: number, z: number, vx: number, vz: number, grounded: boolean, dt: number, now: number, R: number): (number, number, boolean)
	local P = Config.Physics
	local r = Config.Ball.Diameter / 2
	local speed = math.sqrt(vx * vx + vz * vz)
	local dist = math.sqrt(x * x + z * z)
	if not grounded or dist < R or dist >= R + r then
		s.Hang = 0
		return vx, vz, false
	end
	local ix, iz = -x / dist, -z / dist -- toward the cup
	local over = (R + r - dist) / r -- how far the ball hangs over the rim (0-1)
	local edge = P.CupEdgeBreak * over * over * math.clamp(1 - speed / P.CupEdgeBreakSpeed, 0, 1)
	-- A resting ball only moves if the break beats rolling resistance.
	if speed > 0.5 or edge > P.RollResistance then
		vx += ix * edge * dt
		vz += iz * edge * dt
	end
	local zone = CupPhysics.lipZone(R)
	if dist < R + zone and speed < P.CupLipSpeed then
		if s.Hang == 0 and speed < 1.2 then
			s.Hang = now + P.CupLipHang
		end
		if s.Hang > now then
			return vx * 0.5, vz * 0.5, true -- teetering on the edge
		end
		local k = 1 - (dist - R) / zone
		local pull = (30 + 40 * k) * (1 - speed / P.CupLipSpeed) * dt
		return vx + ix * pull, vz + iz * pull, true
	end
	s.Hang = 0
	return vx, vz, false
end

return CupPhysics

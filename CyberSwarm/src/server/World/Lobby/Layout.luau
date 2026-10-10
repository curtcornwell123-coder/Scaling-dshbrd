--!strict
--[[
	Layout
	Where each lobby area sits, in lobby-local studs (origin = Constants.World.LOBBY_ORIGIN, floor
	surface at Y = 0). Hub at the centre; DUELS straight ahead (+Z); TROOP DEPOT to the left (+X
	when facing the DUELS arch from the platform); MARKET to the right (-X); party alcove behind.
]]

local Layout = {}

Layout.HUB_RADIUS = 60
Layout.HUB_WALL_HEIGHT = 26
Layout.WALL_THICKNESS = 3
Layout.OPENING_HALF_ANGLE = 10
Layout.HALL_WIDTH = 20
Layout.HALL_WALL_HEIGHT = 20

-- Opening angles in degrees, clockwise from +Z when seen from above.
Layout.Openings = {
	Duels = 0,
	Troops = 90,
	Alcove = 180,
	Market = 270,
} :: { [string]: number }

Layout.DUELS_CENTER = Vector3.new(0, 0, 140)
Layout.DUELS_RADIUS = 46
Layout.DEPOT_MIN_X = 90
Layout.DEPOT_MAX_X = 160
Layout.DEPOT_HALF_Z = 32
Layout.MARKET_MIN_X = -160
Layout.MARKET_MAX_X = -90
Layout.MARKET_HALF_Z = 32
Layout.ALCOVE_NEAR_Z = -76
Layout.ALCOVE_FAR_Z = -100
Layout.ALCOVE_HALF_X = 20

-- Direction on the floor for a clockwise-from-+Z angle in degrees.
function Layout.direction(degrees: number): Vector3
	local radians = math.rad(degrees)
	return Vector3.new(math.sin(radians), 0, math.cos(radians))
end

-- Frame on the floor at `radius` along `degrees`, looking back toward the centre.
function Layout.facingCenter(center: Vector3, degrees: number, radius: number, height: number?): CFrame
	local position = center + Layout.direction(degrees) * radius + Vector3.new(0, height or 0, 0)
	return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
end

return Layout

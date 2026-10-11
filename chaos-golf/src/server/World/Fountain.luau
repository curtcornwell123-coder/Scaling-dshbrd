--!strict
-- Premium three-tier marble fountain for the lobby centre: a moulded collecting
-- pool, fluted pedestal, two turned bowls and a brass finial. Running water is
-- built from textured Beam curtains that spill over every rim, a crown jet, eight
-- arcing pool jets, splash rings and mist. Underwater spotlights light it from below.

local LobbyKit = require(script.Parent:WaitForChild("LobbyKit"))
local Parts = require(script.Parent:WaitForChild("Parts"))

type Props = Parts.Props

local Fountain = {}

export type Palette = {
	Marble: Props,
	MarbleDark: Props,
	Brass: Props,
	Mosaic: Props,
	Water: Props,
}

local PI = math.pi
local UP = Vector3.yAxis

-- Heights of the three water surfaces (shared by the geometry and the water flows).
local POOL_R, POOL_Y = 14.2, 2.35
local MID_R, MID_Y, MID_RIM = 7.4, 9.45, 9.7
local TOP_R, TOP_Y, TOP_RIM = 4.1, 14.35, 14.5

Fountain.Radius = 17 -- footprint (outer step)

local function deco(props: Props, name: string): Props
	local p = table.clone(props)
	p.Name = name
	p.CanCollide = false
	p.CanQuery = false
	return p
end

local function named(props: Props, name: string): Props
	local p = table.clone(props)
	p.Name = name
	return p
end

local function dirAt(deg: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

local function tangentAt(deg: number): Vector3
	local a = math.rad(deg)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local WATER_COLOR = ColorSequence.new(Color3.fromRGB(236, 248, 255), Color3.fromRGB(176, 220, 240))

local function curtainStyle(w0: number, w1: number): LobbyKit.WaterStyle
	return {
		Color = WATER_COLOR,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.7, 0.42),
			NumberSequenceKeypoint.new(1, 0.7),
		}),
		Width0 = w0,
		Width1 = w1,
		Speed = 1.6,
		Segments = 14,
	}
end

local JET_STYLE: LobbyKit.WaterStyle = {
	Color = WATER_COLOR,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 0.8),
	}),
	Width0 = 0.34,
	Width1 = 0.26,
	Speed = 2.4,
	FaceCamera = true,
	Segments = 16,
}

local function splash(anchor: BasePart, pos: Vector3, rate: number)
	LobbyKit.spray(anchor, CFrame.new(pos), {
		Rate = rate,
		Speed = NumberRange.new(1.5, 3),
		Lifetime = NumberRange.new(0.35, 0.6),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.3) }),
		Spread = 40,
		Gravity = 12,
		Transparency = NumberSequence.new(0.55, 1),
	})
end

-- Geometry -------------------------------------------------------------------------

local function buildPool(m: Model, c: Vector3, pal: Palette)
	-- Two-step plinth with a rounded nosing.
	Parts.cylinder(m, CFrame.new(c + UP * 0.15), 0.3, 34, named(pal.MarbleDark, "Step"))
	Parts.cylinder(m, CFrame.new(c + UP * 0.45), 0.3, 32.4, named(pal.Marble, "Step"))
	LobbyKit.torus(m, c + UP * 0.6, 16.2, 0.3, 48, deco(pal.Marble, "Nosing"), false)
	-- Basin wall: bellied outer face, inner face, rounded lip and a base moulding.
	LobbyKit.lathe(m, c, {
		Vector2.new(15.4, 0.6),
		Vector2.new(15.65, 1.05),
		Vector2.new(15.6, 1.7),
		Vector2.new(15.3, 2.3),
		Vector2.new(15.05, 2.7),
	}, 48, 0.5, named(pal.Marble, "BasinWall"))
	LobbyKit.ring(m, c, 13.9, 15.2, 0.6, 2.7, 48, named(pal.Marble, "BasinCore"))
	LobbyKit.torus(m, c + UP * 2.9, 14.6, 1.0, 48, named(pal.Marble, "Lip"))
	LobbyKit.torus(m, c + UP * 0.85, 15.65, 0.5, 48, deco(pal.Marble, "BaseMoulding"), false)
	LobbyKit.torus(m, c + UP * 2.55, 15.25, 0.22, 48, deco(pal.Brass, "BrassBand"), false)
	-- Mosaic floor and the water surface.
	Parts.cylinder(m, CFrame.new(c + UP * 0.8), 0.4, 28.2, named(pal.Mosaic, "PoolFloor"))
	for i = 0, 15 do
		local a = i / 16 * 2 * PI
		local tile = Parts.block(m, CFrame.new(c + UP * 1.02) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -9), Vector3.new(0.35, 0.04, 9), deco(pal.Brass, "MosaicRay"))
		tile.Transparency = 0.35
	end
	Parts.cylinder(m, CFrame.new(c + UP * POOL_Y), 0.12, POOL_R * 2 + 0.2, deco(pal.Water, "Water"))
end

local function buildPedestal(m: Model, c: Vector3, pal: Palette)
	Parts.cylinder(m, CFrame.new(c + UP * 1.8), 1.6, 7, named(pal.Marble, "Plinth"))
	LobbyKit.torus(m, c + UP * 2.6, 3.5, 0.5, 28, deco(pal.Marble, "PlinthTop"))
	LobbyKit.torus(m, c + UP * 1.1, 3.55, 0.45, 28, deco(pal.Marble, "PlinthBase"), false)
	LobbyKit.torus(m, c + UP * 2.2, 3.52, 0.14, 28, deco(pal.Brass, "PlinthBand"), false)
	LobbyKit.flutedColumn(m, c, 2.8, 6.8, 2.8, 20, deco(pal.Marble, "Column"))
	LobbyKit.torus(m, c + UP * 3.0, 1.55, 0.45, 24, deco(pal.Marble, "ColumnFoot"))
	LobbyKit.lathe(m, c, {
		Vector2.new(1.4, 6.7),
		Vector2.new(1.8, 6.95),
		Vector2.new(2.0, 7.15),
	}, 24, 0.3, deco(pal.Marble, "Capital"))
end

local function buildBowl(m: Model, c: Vector3, pal: Palette, profile: { Vector2 }, rimR: number, rimY: number, tube: number, waterR: number, waterY: number, n: number, gadroons: number, tag: string)
	LobbyKit.lathe(m, c, profile, n, 0.35, named(pal.Marble, tag .. "Bowl"))
	LobbyKit.torus(m, c + UP * rimY, rimR, tube, n, named(pal.Marble, tag .. "Rim"))
	-- Inner floor of the bowl (keeps the water from looking bottomless).
	Parts.cylinder(m, CFrame.new(c + UP * (waterY - 0.35)), 0.3, waterR * 2 - 0.2, deco(pal.Mosaic, tag .. "BowlFloor"))
	Parts.cylinder(m, CFrame.new(c + UP * waterY), 0.1, waterR * 2, deco(pal.Water, "Water"))
	-- Gadroons: ribs down the underside of the bowl.
	local inner, outer = profile[2], profile[#profile - 1]
	for i = 0, gadroons - 1 do
		local d = dirAt(i / gadroons * 360)
		Parts.rod(m, c + d * inner.X + UP * (inner.Y - 0.12), c + d * outer.X + UP * (outer.Y - 0.18), 0.3, deco(pal.Marble, "Gadroon"))
	end
	LobbyKit.torus(m, c + UP * (rimY - tube * 0.55), rimR - 0.05, 0.14, n, deco(pal.Brass, tag .. "BrassBand"), false)
end

local function buildUpper(m: Model, c: Vector3, pal: Palette)
	LobbyKit.torus(m, c + UP * 9.55, 0.95, 0.35, 16, deco(pal.Marble, "UpperFoot"))
	LobbyKit.flutedColumn(m, c, 9.4, 12.6, 1.6, 12, deco(pal.Marble, "UpperColumn"))
	buildBowl(m, c, pal, {
		Vector2.new(0.9, 12.5),
		Vector2.new(1.8, 12.7),
		Vector2.new(2.9, 13.2),
		Vector2.new(3.7, 13.9),
		Vector2.new(4.1, 14.4),
	}, TOP_R, TOP_RIM, 0.45, TOP_R - 0.2, TOP_Y, 36, 18, "Top")
	-- Finial: turned brass vase and a ball with the spout.
	LobbyKit.lathe(m, c, {
		Vector2.new(0.45, 14.35),
		Vector2.new(0.75, 14.85),
		Vector2.new(0.6, 15.5),
		Vector2.new(0.32, 15.95),
		Vector2.new(0.5, 16.3),
	}, 16, 0.12, deco(pal.Brass, "Finial"))
	Parts.cylinder(m, CFrame.new(c + UP * 15.1), 1.4, 1.0, deco(pal.Brass, "FinialCore"))
	Parts.ball(m, c + UP * 16.65, 0.9, deco(pal.Brass, "FinialBall"))
	Parts.cylinder(m, CFrame.new(c + UP * 17.15), 0.3, 0.22, deco(pal.Brass, "Spout"))
end

-- Water ------------------------------------------------------------------------------

local function buildWater(m: Model, c: Vector3, pal: Palette)
	local anchor = Parts.block(m, CFrame.new(c + UP * 8), Vector3.one, {
		Name = "WaterFx",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	-- Crown jet: a column of water, a spray head and a ring of droplets falling into the top bowl.
	LobbyKit.waterBeam(anchor, c + UP * 17.25, UP, c + UP * 19.6, UP, 0, 0, Vector3.xAxis, JET_STYLE)
	LobbyKit.spray(anchor, CFrame.new(c + UP * 17.3), {
		Rate = 70,
		Speed = NumberRange.new(8.5, 10.5),
		Lifetime = NumberRange.new(0.9, 1.2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.85) }),
		Spread = 7,
		Gravity = 34,
	})
	for i = 0, 11 do
		local deg = i * 30
		local out = dirAt(deg)
		LobbyKit.waterBeam(anchor, c + UP * 19.5, (out + UP * 0.8).Unit, c + out * 2.5 + UP * TOP_Y, -UP, 1.2, 1.4, tangentAt(deg), {
			Color = WATER_COLOR,
			Transparency = NumberSequence.new(0.35, 0.75),
			Width0 = 0.22,
			Width1 = 0.3,
			Speed = 2,
			FaceCamera = true,
			Segments = 12,
		})
	end
	-- Curtain from the top bowl into the middle bowl.
	local nTop = 28
	for i = 0, nTop - 1 do
		local deg = (i + 0.5) / nTop * 360
		local out = dirAt(deg)
		local w = 2 * PI * (TOP_R + 0.25) / nTop
		LobbyKit.waterBeam(anchor, c + out * (TOP_R + 0.3) + UP * (TOP_RIM + 0.05), (out - UP * 0.25).Unit, c + out * 5.6 + UP * MID_Y, -UP, 0.8, 2.2, tangentAt(deg), curtainStyle(w * 1.12, w * 1.5))
	end
	-- Curtain from the middle bowl into the pool.
	local nMid = 44
	for i = 0, nMid - 1 do
		local deg = (i + 0.5) / nMid * 360
		local out = dirAt(deg)
		local w = 2 * PI * (MID_R + 0.4) / nMid
		LobbyKit.waterBeam(anchor, c + out * (MID_R + 0.45) + UP * (MID_RIM + 0.05), (out - UP * 0.2).Unit, c + out * 10.2 + UP * POOL_Y, -UP, 1.2, 3, tangentAt(deg), curtainStyle(w * 1.12, w * 1.6))
	end
	-- Eight brass nozzles on the pool lip arc jets toward the pedestal.
	for i = 0, 7 do
		local deg = i * 45 + 22.5
		local out = dirAt(deg)
		local nozzle = c + out * 13.7 + UP * 3.35
		Parts.rod(m, nozzle + out * 0.35 - UP * 0.15, nozzle - out * 0.15 + UP * 0.12, 0.32, deco(pal.Brass, "Nozzle"))
		LobbyKit.waterBeam(anchor, nozzle, (-out * 0.55 + UP * 0.83).Unit, c + out * 4.4 + UP * POOL_Y, (-out * 0.4 - UP).Unit, 5, 4, tangentAt(deg), JET_STYLE)
		splash(anchor, c + out * 4.4 + UP * (POOL_Y + 0.1), 14)
	end
	-- Splash rings where the curtains land, and a soft mist over the pool.
	for i = 0, 7 do
		splash(anchor, c + dirAt(i * 45) * 5.6 + UP * (MID_Y + 0.1), 10)
	end
	for i = 0, 11 do
		splash(anchor, c + dirAt(i * 30 + 15) * 10.2 + UP * (POOL_Y + 0.1), 12)
	end
	LobbyKit.spray(anchor, CFrame.new(c + UP * 3), {
		Rate = 6,
		Speed = NumberRange.new(0.3, 0.8),
		Lifetime = NumberRange.new(2.5, 4),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 8) }),
		Spread = 180,
		Gravity = -0.3,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.88),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	-- Underwater spotlights aimed up at the fountain.
	for i = 0, 7 do
		local deg = i * 45
		local p = c + dirAt(deg) * 11.6 + UP * 1.1
		local housing = Parts.block(m, CFrame.lookAt(p, c + UP * 11) * CFrame.Angles(-PI / 2, 0, 0), Vector3.new(0.7, 0.3, 0.7), deco(pal.Brass, "PoolLight"))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Top
		spot.Angle = 50
		spot.Range = 22
		spot.Brightness = 1.6
		spot.Color = Color3.fromRGB(255, 236, 205)
		spot.Shadows = false
		spot.Parent = housing
	end
end

function Fountain.build(parent: Instance, center: Vector3, pal: Palette): Model
	local m = Parts.model(parent, "Fountain")
	buildPool(m, center, pal)
	buildPedestal(m, center, pal)
	buildBowl(m, center, pal, {
		Vector2.new(1.5, 6.9),
		Vector2.new(2.8, 7.1),
		Vector2.new(4.4, 7.6),
		Vector2.new(5.8, 8.3),
		Vector2.new(6.9, 9.1),
		Vector2.new(7.4, 9.6),
	}, MID_R, MID_RIM, 0.55, MID_R - 0.3, MID_Y, 48, 24, "Mid")
	buildUpper(m, center, pal)
	buildWater(m, center, pal)
	return m
end

return Fountain

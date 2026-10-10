--!strict
--[[
	RobotModels
	Builds the placeholder robot model for a troop. Shared by the server (units in a match) and
	the client (Troop Shop ViewportFrame previews, depot plinths) so a troop always looks the same.

	The silhouette comes from the troop's builderId in TroopConfig; colours and size come from the
	robot's visual in RobotConfig. -Z is the front (CFrame.lookAt convention).
	The returned model has a PrimaryPart named "Body" at the origin. Parts are anchored and
	non-colliding; the server welds them when the robot moves.
]]

local Constants = require(script.Parent.Parent.Constants)
local Theme = require(script.Parent.Parent.Theme)
local Types = require(script.Parent.Parent.Types)
local TroopConfig = require(script.Parent.Parent.Config.TroopConfig)

local LEG_HEIGHT = Constants.World.ROBOT_LEG_HEIGHT

local RobotModels = {}

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
}

local function addPart(model: Model, spec: PartSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Shape = spec.shape or Enum.PartType.Block
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if part.Material == Enum.Material.Neon then
		part.CastShadow = false
	end
	part.Parent = model
	return part
end

local function legs(model: Model, size: Vector3, height: number)
	for _, side in { -1, 1 } do
		addPart(model, {
			name = "Leg",
			size = Vector3.new(size.X * 0.24, height, size.Z * 0.34),
			cframe = CFrame.new(side * size.X * 0.25, -size.Y * 0.5 - height * 0.5, 0),
			color = Theme.Colors.MetalDark,
			material = Enum.Material.Metal,
		})
	end
end

function RobotModels.builderFor(robotId: string): string
	local troop = TroopConfig.Troops[robotId]
	return if troop ~= nil then troop.builderId else "Orb"
end

function RobotModels.build(def: Types.RobotDef): Model
	local visual = def.visual
	local size = visual.size
	local builder = RobotModels.builderFor(def.id)
	local model = Instance.new("Model")
	model.Name = def.id

	local isBall = visual.shape == "Ball"
	local body = addPart(model, {
		name = "Body",
		size = if isBall then Vector3.one * size.X else size,
		cframe = CFrame.identity,
		color = visual.color,
		shape = if isBall then Enum.PartType.Ball else Enum.PartType.Block,
	})
	model.PrimaryPart = body

	-- Visor and eye strip on the front face. Only the eye glows.
	addPart(model, {
		name = "Visor",
		size = Vector3.new(size.X * 0.72, size.Y * 0.3, 0.25),
		cframe = CFrame.new(0, size.Y * 0.12, -size.Z * 0.5),
		color = Theme.Colors.PanelDark,
	})
	addPart(model, {
		name = "Eye",
		size = Vector3.new(size.X * 0.5, size.Y * 0.08, 0.12),
		cframe = CFrame.new(0, size.Y * 0.12, -size.Z * 0.5 - 0.12),
		color = visual.accent,
		material = Enum.Material.Neon,
	})
	addPart(model, {
		name = "CoreRing",
		size = Vector3.new(size.X * 1.05, size.Y * 0.12, size.Z * 1.05),
		cframe = CFrame.new(0, -size.Y * 0.15, 0),
		color = visual.accent,
	})

	if builder == "Heavy" then
		-- Shoulder armour plates.
		for _, side in { -1, 1 } do
			addPart(model, {
				name = "Shoulder",
				size = Vector3.new(size.X * 0.3, size.Y * 0.28, size.Z * 0.8),
				cframe = CFrame.new(side * size.X * 0.62, size.Y * 0.3, 0),
				color = Theme.Colors.MetalDark,
				material = Enum.Material.Metal,
			})
		end
	elseif builder == "Lancer" then
		-- Forward spike.
		addPart(model, {
			name = "Lance",
			size = Vector3.new(size.X * 0.16, size.X * 0.16, size.Z * 0.9),
			cframe = CFrame.new(size.X * 0.42, 0, -size.Z * 0.7),
			color = visual.accent,
		})
	elseif builder == "Walker" then
		-- Antenna mast.
		addPart(model, {
			name = "Antenna",
			size = Vector3.new(0.14, size.Y * 0.6, 0.14),
			cframe = CFrame.new(size.X * 0.3, size.Y * 0.8, 0),
			color = Theme.Colors.MetalDark,
		})
	end

	if def.flying or builder == "Hover" then
		addPart(model, {
			name = "Rotor",
			size = Vector3.new(0.2, size.X * 1.5, size.Z * 1.5),
			cframe = CFrame.new(0, size.Y * 0.5 + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color = visual.accent,
			transparency = 0.35,
			shape = Enum.PartType.Cylinder,
		})
	else
		legs(model, size, if builder == "Walker" then LEG_HEIGHT * 1.6 else LEG_HEIGHT)
	end

	return model
end

return RobotModels

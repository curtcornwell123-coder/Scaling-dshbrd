--!strict
--[[
	PlaceholderModels
	Builds every unit model. If a Model exists at ServerStorage/Assets/<modelPath> it is cloned;
	otherwise a placeholder is generated from Parts so the game runs with zero external assets.
	Robots are neon cyber machines; towers and the enemy HQ use the military palette.

	Asset rules (documented in README): robots need a PrimaryPart; towers need a PrimaryPart whose
	PivotOffset sits at the bottom centre, plus an anchored part named "Head" that the turret
	rotates (parts that turn with it must be unanchored and welded to it).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local PartFactory = require(script.Parent.PartFactory)

local LEG_HEIGHT = Constants.World.ROBOT_LEG_HEIGHT
local TOWER_PAD_HEIGHT = 0.8
local TOWER_BODY_SIZE = 2.4
local HEALTH_BAR_GAP = 1.2

local PlaceholderModels = {}

export type RobotModel = {
	model: Model,
	root: BasePart,
	heightOffset: number,
	barFill: Frame,
}

export type TowerModel = {
	model: Model,
	head: BasePart,
	light: BasePart?,
	barFill: Frame,
}

export type BaseModel = {
	model: Model,
	barFill: Frame,
}

local function loadAsset(path: string): Model?
	local node: Instance? = ServerStorage:FindFirstChild(Constants.MapLayout.ASSETS_FOLDER)
	for _, segment in string.split(path, "/") do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(segment)
	end
	if node ~= nil and node:IsA("Model") then
		return node:Clone()
	end
	return nil
end

local function shapeOf(visual: Types.UnitVisual): Enum.PartType
	return if visual.shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
end

local function buildRobot(def: Types.RobotDef): Model
	local visual = def.visual
	local size = visual.size
	local model = Instance.new("Model")
	model.Name = def.id

	local body = PartFactory.part({
		name = "Body",
		size = if visual.shape == "Ball" then Vector3.one * size.X else size,
		cframe = CFrame.identity,
		color = visual.color,
		material = Enum.Material.Neon,
		transparency = 0.1,
		shape = shapeOf(visual),
		canCollide = false,
		parent = model,
	})
	body.CastShadow = false
	model.PrimaryPart = body

	-- Visor and eye strip on the front face (-Z is "forward" for CFrame.lookAt).
	PartFactory.part({
		name = "Visor",
		size = Vector3.new(size.X * 0.72, size.Y * 0.3, 0.25),
		cframe = CFrame.new(0, size.Y * 0.12, -size.Z * 0.5),
		color = Theme.Colors.PanelDark,
		canCollide = false,
		parent = model,
	})
	PartFactory.neon(
		"Eye",
		Vector3.new(size.X * 0.5, size.Y * 0.08, 0.12),
		CFrame.new(0, size.Y * 0.12, -size.Z * 0.5 - 0.12),
		visual.accent,
		model
	)
	PartFactory.neon(
		"CoreRing",
		Vector3.new(size.X * 1.05, size.Y * 0.12, size.Z * 1.05),
		CFrame.new(0, -size.Y * 0.15, 0),
		visual.accent,
		model
	)

	if def.flying then
		local rotor = PartFactory.neon(
			"Rotor",
			Vector3.new(0.2, size.X * 1.5, size.Z * 1.5),
			CFrame.new(0, size.Y * 0.5 + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
			visual.accent,
			model
		)
		rotor.Shape = Enum.PartType.Cylinder
		rotor.Transparency = 0.35
	else
		for _, side in { -1, 1 } do
			PartFactory.part({
				name = "Leg",
				size = Vector3.new(size.X * 0.24, LEG_HEIGHT, size.Z * 0.34),
				cframe = CFrame.new(side * size.X * 0.25, -size.Y * 0.5 - LEG_HEIGHT * 0.5, 0),
				color = Theme.Colors.MetalDark,
				material = Enum.Material.Metal,
				canCollide = false,
				parent = model,
			})
		end
	end

	return model
end

function PlaceholderModels.robot(def: Types.RobotDef): RobotModel
	local model = loadAsset(def.modelPath)
	if model == nil or model.PrimaryPart == nil then
		if model ~= nil then
			warn(`[PlaceholderModels] Asset for robot "{def.id}" has no PrimaryPart; using the placeholder.`)
			model:Destroy()
		end
		model = buildRobot(def)
	end
	local robotModel = model :: Model
	local root = robotModel.PrimaryPart :: BasePart
	root.CFrame = CFrame.identity
	PartFactory.weldToRoot(robotModel, root)

	-- Measure once at the origin so movement can place the model's feet exactly on the lane.
	local boxCFrame, boxSize = robotModel:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y * 0.5
	local top = boxCFrame.Position.Y + boxSize.Y * 0.5
	local heightOffset = root.Position.Y - bottom

	local barFill = PartFactory.healthBar(
		root,
		math.max(boxSize.X, 2.5),
		top - root.Position.Y + HEALTH_BAR_GAP,
		Theme.Colors.Success
	)
	robotModel:SetAttribute(Constants.Attributes.RobotId, def.id)
	CollectionService:AddTag(robotModel, Constants.Tags.Robot)

	return {
		model = robotModel,
		root = root,
		heightOffset = heightOffset,
		barFill = barFill,
	}
end

local function buildTower(def: Types.TowerDef): (Model, BasePart, BasePart)
	local visual = def.visual
	local military = Theme.Military
	local model = Instance.new("Model")
	model.Name = def.id

	local pad = PartFactory.part({
		name = "Pad",
		size = Vector3.new(5.6, TOWER_PAD_HEIGHT, 5.6),
		cframe = CFrame.new(0, TOWER_PAD_HEIGHT * 0.5, 0),
		color = military.Gunmetal,
		material = Enum.Material.DiamondPlate,
		parent = model,
	})
	pad.PivotOffset = CFrame.new(0, -TOWER_PAD_HEIGHT * 0.5, 0)
	model.PrimaryPart = pad

	-- Sandbag wall ringing the emplacement.
	local wallY = TOWER_PAD_HEIGHT + 0.5
	for _, offset in { Vector3.new(0, 0, 2.5), Vector3.new(0, 0, -2.5) } do
		PartFactory.part({
			name = "Sandbags",
			size = Vector3.new(5.6, 1, 0.9),
			cframe = CFrame.new(offset + Vector3.new(0, wallY, 0)),
			color = military.Sand,
			material = Enum.Material.Fabric,
			parent = model,
		})
	end
	for _, offset in { Vector3.new(2.5, 0, 0), Vector3.new(-2.5, 0, 0) } do
		PartFactory.part({
			name = "Sandbags",
			size = Vector3.new(0.9, 1, 3.8),
			cframe = CFrame.new(offset + Vector3.new(0, wallY, 0)),
			color = military.Sand,
			material = Enum.Material.Fabric,
			parent = model,
		})
	end

	local bodyY = TOWER_PAD_HEIGHT + TOWER_BODY_SIZE * 0.5
	PartFactory.part({
		name = "Body",
		size = Vector3.new(TOWER_BODY_SIZE, TOWER_BODY_SIZE, TOWER_BODY_SIZE),
		cframe = CFrame.new(0, bodyY, 0),
		color = visual.color,
		material = Enum.Material.Metal,
		parent = model,
	})

	local headSize = if visual.shape == "Ball" then Vector3.one * visual.size.X else visual.size
	local headY = TOWER_PAD_HEIGHT + TOWER_BODY_SIZE + headSize.Y * 0.5
	local head = PartFactory.part({
		name = "Head",
		size = headSize,
		cframe = CFrame.new(0, headY, 0),
		color = visual.color,
		material = Enum.Material.Metal,
		shape = shapeOf(visual),
		parent = model,
	})

	-- Barrel shape follows the tower's role so new towers look right without new code:
	-- splash towers get a heavy barrel, air-only towers angle theirs skyward.
	local heavy = def.splashRadius > 0
	local barrelThickness = if heavy then 0.9 else 0.45
	local barrelLength = headSize.Z * 0.6 + (if heavy then 2.6 else 2)
	local tilt = if def.targetsAir and not def.targetsGround then math.rad(30) else 0
	local barrelCFrame = CFrame.new(0, headY, 0)
		* CFrame.Angles(tilt, 0, 0)
		* CFrame.new(0, 0, -(headSize.Z * 0.35 + barrelLength * 0.5))
	local barrel = PartFactory.part({
		name = "Barrel",
		size = Vector3.new(barrelThickness, barrelThickness, barrelLength),
		cframe = barrelCFrame,
		color = military.Gunmetal,
		material = Enum.Material.Metal,
		canCollide = false,
		parent = model,
	})
	local light = PartFactory.neon(
		"TargetLight",
		Vector3.new(0.7, 0.3, 0.3),
		CFrame.new(0, headY + headSize.Y * 0.32, -headSize.Z * 0.42),
		visual.accent,
		model
	)

	for _, part in { barrel :: BasePart, light } do
		part.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
	end

	return model, head, light
end

function PlaceholderModels.tower(def: Types.TowerDef, cframe: CFrame): TowerModel
	local model = loadAsset(def.modelPath)
	local head: BasePart? = nil
	local light: BasePart? = nil
	if model ~= nil then
		local assetHead = model:FindFirstChild("Head", true)
		if model.PrimaryPart ~= nil and assetHead ~= nil and assetHead:IsA("BasePart") then
			head = assetHead
			local assetLight = model:FindFirstChild("TargetLight", true)
			if assetLight ~= nil and assetLight:IsA("BasePart") then
				light = assetLight
			end
		else
			warn(
				`[PlaceholderModels] Asset for tower "{def.id}" needs a PrimaryPart and a Head part; using the placeholder.`
			)
			model:Destroy()
			model = nil
		end
	end
	if model == nil then
		local built, builtHead, builtLight = buildTower(def)
		model = built
		head = builtHead
		light = builtLight
	end

	local towerModel = model :: Model
	local towerHead = head :: BasePart
	towerModel:PivotTo(cframe)
	local barFill =
		PartFactory.healthBar(towerHead, 4.5, towerHead.Size.Y * 0.5 + HEALTH_BAR_GAP + 0.6, Theme.Military.Amber)
	towerModel:SetAttribute(Constants.Attributes.TowerId, def.id)
	CollectionService:AddTag(towerModel, Constants.Tags.Tower)

	return {
		model = towerModel,
		head = towerHead,
		light = light,
		barFill = barFill,
	}
end

-- The enemy Command HQ bunker the swarm is trying to destroy.
function PlaceholderModels.commandHQ(cframe: CFrame): BaseModel
	local military = Theme.Military
	local model = Instance.new("Model")
	model.Name = "CommandHQ"

	local foundation = PartFactory.part({
		name = "Foundation",
		size = Vector3.new(14, 1, 12),
		cframe = CFrame.new(0, 0.5, 0),
		color = military.Gunmetal,
		material = Enum.Material.Concrete,
		parent = model,
	})
	foundation.PivotOffset = CFrame.new(0, -0.5, 0)
	model.PrimaryPart = foundation

	local bunker = PartFactory.part({
		name = "Bunker",
		size = Vector3.new(11, 5, 9),
		cframe = CFrame.new(0, 3.5, 0),
		color = military.Olive,
		material = Enum.Material.Concrete,
		parent = model,
	})
	PartFactory.part({
		name = "Roof",
		size = Vector3.new(12.5, 1, 10.5),
		cframe = CFrame.new(0, 6.5, 0),
		color = military.OliveDark,
		material = Enum.Material.Concrete,
		parent = model,
	})
	PartFactory.part({
		name = "Door",
		size = Vector3.new(3, 3.4, 0.4),
		cframe = CFrame.new(0, 2.7, -4.6),
		color = military.Gunmetal,
		material = Enum.Material.DiamondPlate,
		parent = model,
	})
	PartFactory.neon("AlertStrip", Vector3.new(9, 0.3, 0.3), CFrame.new(0, 5.6, -4.65), military.AlertRed, model)
	PartFactory.part({
		name = "Antenna",
		size = Vector3.new(0.3, 7, 0.3),
		cframe = CFrame.new(4, 10.5, 3),
		color = military.Steel,
		material = Enum.Material.Metal,
		canCollide = false,
		parent = model,
	})
	PartFactory.neon("Beacon", Vector3.new(0.8, 0.8, 0.8), CFrame.new(4, 14.3, 3), military.AlertRed, model).Shape =
		Enum.PartType.Ball
	PartFactory.part({
		name = "RadarDish",
		size = Vector3.new(0.4, 4, 4),
		cframe = CFrame.new(-3.5, 8.6, 2) * CFrame.Angles(0, math.rad(35), math.rad(20)),
		color = military.Khaki,
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		parent = model,
	})
	for _, x in { -6.5, 6.5 } do
		PartFactory.part({
			name = "Sandbags",
			size = Vector3.new(1, 1.4, 12),
			cframe = CFrame.new(x, 1.7, 0),
			color = military.Sand,
			material = Enum.Material.Fabric,
			parent = model,
		})
	end

	model:PivotTo(cframe)
	local barFill = PartFactory.healthBar(bunker, 12, 9, military.AlertRed)
	CollectionService:AddTag(model, Constants.Tags.EnemyBase)
	return {
		model = model,
		barFill = barFill,
	}
end

return PlaceholderModels

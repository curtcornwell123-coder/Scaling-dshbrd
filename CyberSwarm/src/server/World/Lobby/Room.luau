--!strict
--[[
	Room
	A rectangular concrete room with an opening in one wall, used by the Troop Depot, the Market,
	and the party alcove. `frame` is the floor centre; local -Z points from the room toward the hub
	(the entrance wall), local X runs across the room.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local World = Theme.World

local WINDOW_TOP = 17

local Room = {}

-- `backOpening` (optional) leaves a window of that width in the back wall, up to WINDOW_TOP.
function Room.build(
	model: Model,
	frame: CFrame,
	width: number,
	depth: number,
	height: number,
	openingWidth: number,
	wallColor: Color3?,
	backOpening: number?
)
	local color = wallColor or World.Concrete
	local thickness = Layout.WALL_THICKNESS
	Kit.block(
		model,
		"Floor",
		Vector3.new(width + thickness * 2, 2, depth + thickness * 2),
		frame * CFrame.new(0, -1, 0),
		World.Floor,
		Enum.Material.Concrete
	)
	-- Back wall (optionally with a window) and side walls.
	local backZ = depth * 0.5 + thickness * 0.5
	if backOpening == nil then
		Kit.block(
			model,
			"BackWall",
			Vector3.new(width + thickness * 2, height, thickness),
			frame * CFrame.new(0, height * 0.5, backZ),
			color,
			Enum.Material.Concrete
		)
	else
		local windowWidth = backOpening :: number
		local side = (width + thickness * 2 - windowWidth) * 0.5
		for _, sign in { -1, 1 } do
			Kit.block(
				model,
				"BackWall",
				Vector3.new(side, height, thickness),
				frame * CFrame.new(sign * (windowWidth * 0.5 + side * 0.5), height * 0.5, backZ),
				color,
				Enum.Material.Concrete
			)
		end
		Kit.block(
			model,
			"BackSill",
			Vector3.new(windowWidth, 1, thickness),
			frame * CFrame.new(0, 0.5, backZ),
			color,
			Enum.Material.Concrete
		)
		Kit.block(
			model,
			"BackLintel",
			Vector3.new(windowWidth, height - WINDOW_TOP, thickness),
			frame * CFrame.new(0, WINDOW_TOP + (height - WINDOW_TOP) * 0.5, backZ),
			color,
			Enum.Material.Concrete
		)
	end
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"SideWall",
			Vector3.new(thickness, height, depth),
			frame * CFrame.new(side * (width * 0.5 + thickness * 0.5), height * 0.5, 0),
			color,
			Enum.Material.Concrete
		)
	end
	-- Entrance wall in two pieces around the opening.
	local pieceWidth = (width - openingWidth) * 0.5
	for _, side in { -1, 1 } do
		Kit.block(
			model,
			"FrontWall",
			Vector3.new(pieceWidth + thickness, height, thickness),
			frame
				* CFrame.new(
					side * (openingWidth * 0.5 + (pieceWidth + thickness) * 0.5),
					height * 0.5,
					-(depth * 0.5 + thickness * 0.5)
				),
			color,
			Enum.Material.Concrete
		)
	end
	Kit.block(
		model,
		"Lintel",
		Vector3.new(openingWidth, height - 19, thickness),
		frame * CFrame.new(0, 19 + (height - 19) * 0.5, -(depth * 0.5 + thickness * 0.5)),
		color,
		Enum.Material.Concrete
	)
	-- Ceiling beams (the rooms are open to the sky between them).
	local beams = math.max(2, math.floor(depth / 10))
	for index = 0, beams do
		local z = -depth * 0.5 + index * depth / beams
		Kit.block(
			model,
			"Beam",
			Vector3.new(width, 1.2, 1),
			frame * CFrame.new(0, height - 0.6, z),
			World.Steel,
			Enum.Material.Metal
		)
	end
	local lightPart = Kit.block(
		model,
		"RoomLight",
		Vector3.new(1, 0.4, 1),
		frame * CFrame.new(0, height - 1.4, 0),
		World.Steel,
		Enum.Material.Metal,
		false
	)
	local light = Instance.new("PointLight")
	light.Range = math.max(width, depth)
	light.Brightness = 0.8
	light.Color = Color3.fromRGB(255, 244, 228)
	light.Parent = lightPart
end

return Room

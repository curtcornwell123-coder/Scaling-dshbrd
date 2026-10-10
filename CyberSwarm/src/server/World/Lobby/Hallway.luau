--!strict
--[[
	Hallway
	A straight concrete corridor from the hub wall to an area, with hazard-yellow floor guides,
	ceiling beams, and a hanging direction sign in the area's accent colour.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local World = Theme.World

local Hallway = {}

-- `degrees` is the hub opening angle; the corridor runs from `fromRadius` to `toRadius`.
function Hallway.build(parent: Instance, origin: CFrame, degrees: number, fromRadius: number, toRadius: number, accent: Color3, label: string)
	local model = Instance.new("Model")
	model.Name = "Hallway_" .. label
	local direction = Layout.direction(degrees)
	local length = toRadius - fromRadius
	local midpoint = direction * (fromRadius + length * 0.5)
	-- Local frame: -Z points away from the hub, X across the corridor.
	local frame = origin * CFrame.lookAt(midpoint, midpoint + direction)
	local width = Layout.HALL_WIDTH
	local height = Layout.HALL_WALL_HEIGHT

	Kit.block(model, "Floor", Vector3.new(width + 6, 2, length + 2), frame * CFrame.new(0, -1, 0), World.Floor, Enum.Material.Concrete)
	for _, side in { -1, 1 } do
		Kit.block(model, "Wall", Vector3.new(Layout.WALL_THICKNESS, height, length), frame * CFrame.new(side * (width * 0.5 + 1.5), height * 0.5, 0), World.Concrete, Enum.Material.Concrete)
		Kit.block(model, "Skirting", Vector3.new(0.5, 2.4, length), frame * CFrame.new(side * (width * 0.5 - 0.2), 1.2, 0), World.ConcreteMid, Enum.Material.Concrete, false)
		-- Yellow guide lines a step in from each wall.
		Kit.block(model, "Guide", Vector3.new(0.5, 0.05, length - 2), frame * CFrame.new(side * (width * 0.5 - 2.5), 0.03, 0), World.Hazard, Enum.Material.SmoothPlastic, false)
		Kit.glow(model, "WallAccent", Vector3.new(0.15, 0.3, length - 4), frame * CFrame.new(side * (width * 0.5 - 0.05), height - 3, 0), accent)
	end
	local beams = math.max(2, math.floor(length / 8))
	for index = 0, beams do
		local z = -length * 0.5 + index * length / beams
		Kit.block(model, "CeilingBeam", Vector3.new(width + 6, 1.2, 1.2), frame * CFrame.new(0, height - 0.6, z), World.Steel, Enum.Material.Metal)
	end
	-- Direction sign hanging near the hub end, readable from the hub.
	local signFrame = frame * CFrame.new(0, height - 4.5, length * 0.5 - 4) * CFrame.Angles(0, math.pi, 0)
	Kit.sign(model, "DirectionSign", signFrame, Vector2.new(12, 2.4), label, accent, World.Steel, accent, Theme.Fonts.Title)
	model.Parent = parent
	return model
end

return Hallway

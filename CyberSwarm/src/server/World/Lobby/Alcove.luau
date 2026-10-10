--!strict
--[[
	Alcove
	The small room behind the hub platform: two party pads (FORM and LEAVE; stand on them, no
	buttons), a party screen listing your party, and the Armory loadout terminal.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Room = require(script.Parent.Room)

local World = Theme.World
local Areas = Theme.Areas

local HEIGHT = 22

local Alcove = {}

local function partyPad(model: Model, floor: CFrame, action: string, label: string, color: Color3)
	local pad = Kit.block(
		model,
		"PartyPad_" .. action,
		Vector3.new(9, 0.5, 9),
		floor * CFrame.new(0, 0.25, 0),
		World.SteelLight,
		Enum.Material.DiamondPlate
	)
	pad:SetAttribute(Constants.Attributes.PartyAction, action)
	CollectionService:AddTag(pad, Constants.Tags.PartyPad)
	Kit.ring(model, "PartyPadEdge", floor * CFrame.new(0, 0.52, 0), 4.8, 0.4, 0.06, 4, color, Enum.Material.Neon)
	Kit.sign(
		model,
		"PartyPadLabel",
		floor * CFrame.new(0, 0.53, 0) * CFrame.Angles(math.rad(90), 0, 0),
		Vector2.new(7, 2),
		label,
		color,
		nil,
		nil,
		Theme.Fonts.Title
	)
end

function Alcove.build(parent: Instance, origin: CFrame)
	local model = Instance.new("Model")
	model.Name = "Alcove"
	local depth = Layout.ALCOVE_NEAR_Z - Layout.ALCOVE_FAR_Z
	local centerZ = (Layout.ALCOVE_NEAR_Z + Layout.ALCOVE_FAR_Z) * 0.5
	-- -Z faces the hub (+Z in the lobby).
	local frame = origin * CFrame.lookAt(Vector3.new(0, 0, centerZ), Vector3.new(0, 0, centerZ + 1))
	Room.build(model, frame, Layout.ALCOVE_HALF_X * 2, depth, HEIGHT, Layout.HALL_WIDTH, World.Concrete)

	partyPad(model, frame * CFrame.new(-9, 0, 0), "Form", "FORM PARTY", Areas.Party)
	partyPad(model, frame * CFrame.new(9, 0, 0), "Leave", "LEAVE PARTY", World.RingLocked)
	local back = frame * CFrame.new(0, 0, depth * 0.5 - 0.6)
	Kit.screen(model, "PartyScreen", back * CFrame.new(-9, 9, 0), Vector2.new(10, 6), Constants.ScreenKind.Party)
	Kit.sign(
		model,
		"PartySign",
		back * CFrame.new(-9, 13.4, 0),
		Vector2.new(10, 1.8),
		"PARTY",
		Areas.Party,
		World.Steel,
		Areas.Party,
		Theme.Fonts.Title
	)
	Kit.sign(
		model,
		"ArmorySign",
		back * CFrame.new(9, 13.4, 0),
		Vector2.new(10, 1.8),
		"ARMORY",
		Areas.Armory,
		World.Steel,
		Areas.Armory,
		Theme.Fonts.Title
	)
	Kit.terminal(model, "ArmoryTerminal", back * CFrame.new(9, 0, -3), "Loadout", "Loadout", "Armory", Areas.Armory)
	Kit.screen(model, "ArmoryRankCard", back * CFrame.new(9, 8.5, 0), Vector2.new(8, 5), Constants.ScreenKind.RankCard)
	model.Parent = parent
end

return Alcove

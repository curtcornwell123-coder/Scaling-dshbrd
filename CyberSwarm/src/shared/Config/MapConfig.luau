--!strict
--[[
	MapConfig
	Every arena map. MapService loads ServerStorage/Maps/<templateName>. Maps marked builtIn are
	generated from Parts at startup when no template exists, so the game runs with zero assets.
	The other maps only need a model built in Studio that follows the layout in README.md, then
	their id added to a mode's mapPool in ModeConfig.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local MapConfig = {}

local maps: { [string]: Types.MapDef } = {
	Junkyard = {
		id = "Junkyard",
		displayName = "Junkyard",
		description = "A single winding lane through scrap heaps. Perfect for learning the ropes.",
		templateName = "Junkyard",
		laneCount = 1,
		baseHealth = 600,
		builtIn = true,
	},
	FactoryFloor = {
		id = "FactoryFloor",
		displayName = "Factory Floor",
		description = "Two conveyor lanes that split the defense.",
		templateName = "FactoryFloor",
		laneCount = 2,
		baseHealth = 900,
		builtIn = true,
	},
	NeonCity = {
		id = "NeonCity",
		displayName = "Neon City",
		description = "Three lanes of glowing streets.",
		templateName = "NeonCity",
		laneCount = 3,
		baseHealth = 1200,
		builtIn = true,
	},
	FrozenLab = {
		id = "FrozenLab",
		displayName = "Frozen Lab",
		description = "Icy corridors around a cryogenic core.",
		templateName = "FrozenLab",
		laneCount = 2,
		baseHealth = 1000,
		builtIn = true,
	},
	TestYard = {
		id = "TestYard",
		displayName = "Test Yard",
		description = "Open-air training yard used by the Test Realm sandbox.",
		templateName = "TestYard",
		laneCount = 1,
		baseHealth = 1500,
		builtIn = true,
	},
	VolcanoCore = {
		id = "VolcanoCore",
		displayName = "Volcano Core",
		description = "Three molten lanes guarding a magma reactor.",
		templateName = "VolcanoCore",
		laneCount = 3,
		baseHealth = 1500,
		builtIn = true,
	},
}
MapConfig.Maps = maps

MapConfig.Order = { "Junkyard", "FactoryFloor", "NeonCity", "FrozenLab", "VolcanoCore", "TestYard" }

return TableUtil.deepFreeze(MapConfig)

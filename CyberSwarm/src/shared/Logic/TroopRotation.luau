--!strict
--[[
	TroopRotation
	Which troops sit on the Troop Depot tables today. Same answer on every server and client for a
	given UTC day, so the client can show the rotation and the server can enforce "in stock" from
	the same code.
]]

local Types = require(script.Parent.Parent.Types)
local Calendar = require(script.Parent.Calendar)

export type RotationSettings = {
	permanent: { string },
	rotatingPool: { string },
	rotatingCount: number,
	seed: number,
}

local TroopRotation = {}

function TroopRotation.forTime(unixTime: number, settings: RotationSettings): Types.TroopRotation
	local day = Calendar.dayNumber(unixTime)
	return {
		day = day,
		permanent = table.clone(settings.permanent),
		rotating = Calendar.pickDaily(settings.rotatingPool, settings.rotatingCount, settings.seed, day),
		resetsAt = Calendar.nextResetAt(unixTime),
	}
end

function TroopRotation.inStock(rotation: Types.TroopRotation, troopId: string): boolean
	return table.find(rotation.permanent, troopId) ~= nil or table.find(rotation.rotating, troopId) ~= nil
end

-- Table order: the permanent tables first, then today's rotating ones.
function TroopRotation.tables(rotation: Types.TroopRotation): { string }
	local list = table.clone(rotation.permanent)
	for _, troopId in rotation.rotating do
		table.insert(list, troopId)
	end
	return list
end

return TroopRotation

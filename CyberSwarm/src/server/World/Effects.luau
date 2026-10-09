--!strict
--[[
	Effects
	Sends cosmetic combat effects (tracers, blasts, pulses) to the players watching an arena.
	The server only describes the effect; EffectsController draws it with pooled parts, so
	gunfire never creates server instances or replication traffic beyond one small packet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local Effects = {}

function Effects.send(
	viewers: { Player },
	kind: Types.EffectKind,
	origin: Vector3,
	target: Vector3,
	color: Color3,
	radius: number
)
	if #viewers == 0 then
		return
	end
	Remotes.Effect:fireClients(viewers, {
		kind = kind,
		origin = origin,
		target = target,
		color = color,
		radius = radius,
	})
end

return Effects

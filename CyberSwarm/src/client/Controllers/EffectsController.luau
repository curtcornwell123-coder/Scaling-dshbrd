--!strict
--[[
	EffectsController
	Draws combat effects the server describes (gunfire tracers, shrapnel arcs, blasts, EMP rings,
	repair pulses, armor flashes). Every effect reuses a part from a fixed pool and is animated by
	one RenderStepped loop that only writes numbers, so heavy firefights create no new instances.
	The parts are client-only and never replicate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local MathUtil = require(ReplicatedStorage.Shared.Util.Math)

local BEAM_POOL_SIZE = 64
local BLAST_POOL_SIZE = 24
local RING_POOL_SIZE = 12
local RING_THICKNESS = 0.3
local MIN_BLAST_RADIUS = 1
local SHIELD_DIAMETER = 7
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

type Style = {
	duration: number,
	thickness: number,
	startTransparency: number,
}

local STYLES: { [Types.EffectKind]: Style } = {
	Shot = { duration = 0.09, thickness = 0.25, startTransparency = 0.05 },
	Chain = { duration = 0.18, thickness = 0.35, startTransparency = 0.05 },
	Glitch = { duration = 0.3, thickness = 0.2, startTransparency = 0.2 },
	Explosion = { duration = 0.35, thickness = 0, startTransparency = 0.25 },
	Shield = { duration = 0.35, thickness = 0, startTransparency = 0.5 },
	Pulse = { duration = 0.5, thickness = RING_THICKNESS, startTransparency = 0.4 },
	Heal = { duration = 0.4, thickness = RING_THICKNESS, startTransparency = 0.5 },
}

type Slot = {
	part: Part,
	active: boolean,
	startedAt: number,
	duration: number,
	fromSize: Vector3,
	toSize: Vector3,
	resizes: boolean,
	startTransparency: number,
}

type Pool = {
	slots: { Slot },
	nextIndex: number,
}

local EffectsController = {}

local maid = Maid.new()
local beams: Pool
local blasts: Pool
local rings: Pool

local function makePool(folder: Folder, size: number, shape: Enum.PartType): Pool
	local slots: { Slot } = {}
	for _ = 1, size do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Shape = shape
		part.Transparency = 1
		part.Size = Vector3.one
		part.Parent = folder
		table.insert(slots, {
			part = part,
			active = false,
			startedAt = 0,
			duration = 1,
			fromSize = Vector3.one,
			toSize = Vector3.one,
			resizes = false,
			startTransparency = 1,
		})
	end
	return { slots = slots, nextIndex = 1 }
end

-- Takes the next slot round-robin; under heavy load the oldest effect is simply recycled.
local function acquire(pool: Pool): Slot
	local slot = pool.slots[pool.nextIndex]
	pool.nextIndex = pool.nextIndex % #pool.slots + 1
	return slot
end

local function start(slot: Slot, style: Style, color: Color3, cframe: CFrame, fromSize: Vector3, toSize: Vector3)
	slot.active = true
	slot.startedAt = os.clock()
	slot.duration = style.duration
	slot.fromSize = fromSize
	slot.toSize = toSize
	slot.resizes = fromSize ~= toSize
	slot.startTransparency = style.startTransparency
	local part = slot.part
	part.Color = color
	part.Size = fromSize
	part.CFrame = cframe
	part.Transparency = style.startTransparency
end

local function onEffect(payload: Types.EffectPayload)
	local style = STYLES[payload.kind]
	if style == nil then
		return
	end
	local kind = payload.kind
	if kind == "Shot" or kind == "Chain" or kind == "Glitch" then
		local length = (payload.target - payload.origin).Magnitude
		if length <= 0 then
			return
		end
		local middle = (payload.origin + payload.target) * 0.5
		local size = Vector3.new(style.thickness, style.thickness, length)
		start(acquire(beams), style, payload.color, CFrame.lookAt(middle, payload.target), size, size)
	elseif kind == "Explosion" then
		local diameter = math.max(payload.radius, MIN_BLAST_RADIUS) * 2
		start(
			acquire(blasts),
			style,
			payload.color,
			CFrame.new(payload.origin),
			Vector3.one * diameter * 0.3,
			Vector3.one * diameter
		)
	elseif kind == "Shield" then
		start(
			acquire(blasts),
			style,
			payload.color,
			CFrame.new(payload.origin),
			Vector3.one * SHIELD_DIAMETER,
			Vector3.one * (SHIELD_DIAMETER + 1)
		)
	else
		local diameter = math.max(payload.radius, MIN_BLAST_RADIUS) * 2
		start(
			acquire(rings),
			style,
			payload.color,
			CFrame.new(payload.origin) * UPRIGHT,
			Vector3.new(RING_THICKNESS, 1, 1),
			Vector3.new(RING_THICKNESS, diameter, diameter)
		)
	end
end

local function animate(pool: Pool, now: number)
	for _, slot in pool.slots do
		if slot.active then
			local alpha = (now - slot.startedAt) / slot.duration
			if alpha >= 1 then
				slot.active = false
				slot.part.Transparency = 1
			else
				if slot.resizes then
					slot.part.Size = slot.fromSize:Lerp(slot.toSize, alpha)
				end
				slot.part.Transparency = MathUtil.lerp(slot.startTransparency, 1, alpha)
			end
		end
	end
end

function EffectsController.init()
	local folder = Instance.new("Folder")
	folder.Name = "CyberSwarmEffects"
	folder.Parent = workspace
	maid:give(folder)

	beams = makePool(folder, BEAM_POOL_SIZE, Enum.PartType.Block)
	blasts = makePool(folder, BLAST_POOL_SIZE, Enum.PartType.Ball)
	rings = makePool(folder, RING_POOL_SIZE, Enum.PartType.Cylinder)

	maid:give(Remotes.Effect:connect(onEffect))
	maid:give(RunService.RenderStepped:Connect(function()
		local now = os.clock()
		animate(beams, now)
		animate(blasts, now)
		animate(rings, now)
	end))
end

return EffectsController

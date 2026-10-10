--!strict
-- Chaos ability inventory (replicated as player attributes Ability1/Ability2)
-- and ability effects. The current activity binds a provider that lists the
-- player's opponents and reports sabotages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local BallService = require(script.Parent:WaitForChild("BallService"))

local AbilityService = {}

export type Provider = {
	Opponents: (Player) -> { BallService.Ball },
	CanUse: ((Player) -> boolean)?,
	OnUsed: ((Player, string, number) -> ())?, -- (player, abilityId, sabotage hits)
}

local inventories: { [Player]: { string } } = {}
local providers: { [Player]: Provider } = {}

local function sync(player: Player)
	local inv = inventories[player] or {}
	for i = 1, Config.Match.MaxAbilities do
		player:SetAttribute("Ability" .. i, inv[i])
	end
end

function AbilityService.bind(player: Player, provider: Provider)
	providers[player] = provider
end

function AbilityService.set(player: Player, list: { string })
	inventories[player] = table.clone(list)
	sync(player)
end

function AbilityService.clear(player: Player)
	inventories[player] = nil
	providers[player] = nil
	sync(player)
end

function AbilityService.give(player: Player, abilityId: string): boolean
	local inv = inventories[player]
	if not inv then
		inv = {}
		inventories[player] = inv
	end
	if #inv >= Config.Match.MaxAbilities then
		return false
	end
	table.insert(inv, abilityId)
	sync(player)
	return true
end

local function toast(player: Player, text: string, color: Color3?)
	Net.event("Toast"):FireClient(player, text, color)
end

local function liveOpponents(provider: Provider, player: Player): { BallService.Ball }
	local out = {}
	for _, b in provider.Opponents(player) do
		if b.Player ~= player and not b.Sunk and b.Part.Parent then
			table.insert(out, b)
		end
	end
	return out
end

-- Returns (consumed, sabotageHits)
local function apply(player: Player, ball: BallService.Ball, id: string, provider: Provider): (boolean, number)
	local targets: { BallService.Ball } = {}
	if id == "Shockwave" then
		local origin = ball.Part.Position
		for _, b in liveOpponents(provider, player) do
			local offset = b.Part.Position - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude <= Abilities.ShockwaveRadius then
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
				local falloff = 1 - (flat.Magnitude / Abilities.ShockwaveRadius) * 0.5
				BallService.push(b, dir * Abilities.ShockwaveForce * falloff + Vector3.new(0, 14, 0), ball)
				table.insert(targets, b)
			end
		end
		if #targets == 0 then
			toast(player, "No opponents in range", Config.Colors.Muted)
			return false, 0
		end
	elseif id == "Frost" then
		local best: BallService.Ball? = nil
		local bestScore = math.huge
		for _, b in liveOpponents(provider, player) do
			local score = if b.Cup then (b.Part.Position - (b.Cup :: Vector3)).Magnitude else b.Strokes
			if score < bestScore then
				best, bestScore = b, score
			end
		end
		if not best then
			toast(player, "No opponents to freeze", Config.Colors.Muted)
			return false, 0
		end
		local target = best :: BallService.Ball
		target.Frost = true
		BallService.refresh(target)
		table.insert(targets, target)
		toast(target.Player, "❄ " .. player.DisplayName .. " froze your next shot!", Config.Colors.Bad)
	elseif id == "Gust" then
		for _, b in liveOpponents(provider, player) do
			b.Gust = true
			BallService.refresh(b)
			table.insert(targets, b)
			toast(b.Player, "🌪 Wind incoming on your next shot!", Config.Colors.Bad)
		end
		if #targets == 0 then
			return false, 0
		end
	elseif id == "TinyCup" then
		for _, b in liveOpponents(provider, player) do
			BallService.tinyCup(b, Abilities.TinyCupSeconds, Abilities.TinyCupScale)
			table.insert(targets, b)
			toast(b.Player, "🎯 Your cup shrank for " .. Abilities.TinyCupSeconds .. "s!", Config.Colors.Bad)
		end
		if #targets == 0 then
			return false, 0
		end
	elseif id == "Magnet" then
		if ball.Magnet or ball.Sunk then
			return false, 0
		end
		ball.Magnet = true
		BallService.refresh(ball)
	elseif id == "Mulligan" then
		if not BallService.mulligan(ball) then
			toast(player, "Nothing to undo yet", Config.Colors.Muted)
			return false, 0
		end
	else
		return false, 0
	end

	local parts = {}
	for _, t in targets do
		table.insert(parts, t.Part)
	end
	Net.event("Fx"):FireAllClients("ability", { Ability = id, From = ball.Part, Targets = parts, Player = player })
	local def = Abilities.get(id)
	return true, if def and def.Sabotage then #targets else 0
end

local function onUse(player: Player, slot: any)
	if type(slot) ~= "number" then
		return
	end
	local inv = inventories[player]
	local provider = providers[player]
	local ball = BallService.get(player)
	if not inv or not provider or not ball or ball.Sunk then
		return
	end
	slot = math.floor(slot)
	local id = inv[slot]
	if not id then
		return
	end
	if provider.CanUse and not provider.CanUse(player) then
		toast(player, "Not right now", Config.Colors.Muted)
		return
	end
	local consumed, hits = apply(player, ball, id, provider)
	if consumed then
		table.remove(inv, slot)
		sync(player)
		if provider.OnUsed then
			provider.OnUsed(player, id, hits)
		end
	end
end

function AbilityService.start()
	Net.event("UseAbility").OnServerEvent:Connect(onUse)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		providers[player] = nil
	end)
end

return AbilityService

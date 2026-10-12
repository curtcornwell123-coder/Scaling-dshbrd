--!strict
-- Spatial checks for floor pads and queue bubbles (see LobbyTypes conventions).

local Players = game:GetService("Players")

local Activity = require(script.Parent:WaitForChild("Activity"))

local Zones = {}

function Zones.rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function radius(part: BasePart): number
	local r = part:GetAttribute("Radius")
	return if type(r) == "number" then r else math.max(part.Size.X, part.Size.Z) / 2
end

function Zones.onPad(pad: BasePart, pos: Vector3): boolean
	local p = pad.Position
	local dy = pos.Y - p.Y
	return dy > -1 and dy < 10 and Vector2.new(pos.X - p.X, pos.Z - p.Z).Magnitude <= radius(pad)
end

function Zones.inBubble(bubble: BasePart, pos: Vector3): boolean
	return (pos - bubble.Position).Magnitude <= radius(bubble)
end

export type Entry = { Player: Player, Root: BasePart }

-- Players standing around in the lobby (not in a match / tutorial / practice).
function Zones.freePlayers(): { Entry }
	local out = {}
	for _, player in Players:GetPlayers() do
		if Activity.isFree(player) then
			local root = Zones.rootOf(player)
			if root then
				table.insert(out, { Player = player, Root = root })
			end
		end
	end
	return out
end

return Zones

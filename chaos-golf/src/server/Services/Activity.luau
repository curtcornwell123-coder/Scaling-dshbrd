--!strict
-- What each player is doing ("Match" | "Tutorial" | "Practice" | nil = free in
-- the lobby) and character parking: while a player controls a ball their
-- character is anchored somewhere out of the way (match booth / practice lane).

local Players = game:GetService("Players")

local Activity = {}

local parked: { [Player]: CFrame } = {}
local lobbySpawn = CFrame.new(0, 3, -25)

function Activity.setLobbySpawn(cf: CFrame)
	lobbySpawn = cf
end

function Activity.get(player: Player): string?
	local a = player:GetAttribute("Activity")
	return if type(a) == "string" then a else nil
end

function Activity.isFree(player: Player): boolean
	return Activity.get(player) == nil
end

function Activity.set(player: Player, activity: string?)
	player:SetAttribute("Activity", activity)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function applyPark(player: Player)
	local cf = parked[player]
	local root = rootOf(player)
	if cf and root then
		root.Anchored = true
		root.CFrame = cf
	end
end

function Activity.park(player: Player, cf: CFrame)
	parked[player] = cf
	applyPark(player)
end

function Activity.unpark(player: Player, cf: CFrame?)
	parked[player] = nil
	local root = rootOf(player)
	if root then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		local target = cf
		if not target then
			-- Spread arrivals on the west side of spawn, clear of the direction sign (east).
			local offset = Vector3.new(math.random(-6, 0), 0, math.random(-3, 1))
			target = lobbySpawn + offset
		end
		root.CFrame = target :: CFrame
	end
end

function Activity.toLobby(player: Player)
	Activity.unpark(player, nil)
end

function Activity.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			if parked[player] then
				character:WaitForChild("HumanoidRootPart", 5)
				task.defer(applyPark, player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		parked[player] = nil
	end)
end

return Activity

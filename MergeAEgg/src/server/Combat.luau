-- Merge A Egg: the bat. Server-validated swings with knockback.
-- Bonking a carrier makes them drop their egg. Bats also stun guardians
-- for a moment and damage the cave boss.

local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")

local Combat = {}

local ctx
local Config
local Models
local Net
local Eggs
local Economy
local Guardians
local Boss

local lastSwing: { [Player]: number } = {}

local function heldBat(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool.Name == "Bat" then
		return tool
	end
	return nil
end

local function swing(player: Player)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < Config.BatCooldown then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or not heldBat(player) then
		return
	end
	lastSwing[player] = now
	Net.fxAll("Swing", player)

	task.delay(0.12, function()
		if not root.Parent then
			return
		end
		local origin = root.Position
		local forward = root.CFrame.LookVector
		local hitSomething = false

		for _, other in Players:GetPlayers() do
			local otherRoot = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local otherHumanoid = otherRoot and other.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and otherHumanoid and otherHumanoid.Health > 0 then
				local offset = otherRoot.Position - origin
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if flat.Magnitude <= Config.BatRange and math.abs(offset.Y) < 6 and (flat.Magnitude < 2 or flat.Unit:Dot(forward) > 0.2) then
					hitSomething = true
					local direction = if flat.Magnitude > 0.1 then flat.Unit else forward
					Economy.grantGrace(other, 1.5)
					Net.fx(other, "Knockback", direction * Config.BatKnockback + Vector3.new(0, 35, 0))
					Net.fxAll("BatHit", otherRoot.Position)
					if Eggs.getCarry(other) then
						Eggs.drop(other, "bonked")
						Net.notify(player, `Bonk! {other.DisplayName} dropped their egg!`, "success")
					end
				end
			end
		end

		local strikePoint = origin + forward * 4
		if Guardians.hitNear(strikePoint, 5) > 0 then
			hitSomething = true
			Net.fxAll("BatHit", strikePoint)
		end
		if Boss.hit(player, strikePoint) then
			hitSomething = true
		end
		if hitSomething then
			Net.fx(player, "HitConfirm")
		end
	end)
end

function Combat.init(context)
	ctx = context
	Config = ctx.Config
	Models = ctx.Models
	Net = ctx.Net
	Eggs = ctx.Eggs
	Economy = ctx.Economy
	Guardians = ctx.Guardians
	Boss = ctx.Boss
	Net.on("Swing", swing)
end

function Combat.start()
	for _, child in StarterPack:GetChildren() do
		if child.Name == "Bat" then
			child:Destroy()
		end
	end
	local template = Models.bat()
	template.Parent = StarterPack
	-- Characters that spawned before the bat existed get one now.
	for _, player in Players:GetPlayers() do
		local backpack = player:FindFirstChildOfClass("Backpack")
		local character = player.Character
		local hasBat = (backpack and backpack:FindFirstChild("Bat")) or (character and character:FindFirstChild("Bat"))
		if backpack and not hasBat then
			template:Clone().Parent = backpack
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

return Combat

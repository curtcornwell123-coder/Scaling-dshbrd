--!strict
-- Corny's Ban Hammer powers, while it's in his hand (only he gets the
-- hammer, and the server checks again for SLAM):
--   FLY          - toggle; fly where you move, up and down with the buttons
--   SUPER SPRINT - toggle; very fast running
--   SLAM         - the super move: a shockwave across the whole map flings
--                  every other player (server, Config.HammerSlamCooldown)
-- Controls follow the device: keyboard keys, controller buttons, or
-- on-screen buttons on phones and tablets (ContextActionService makes those
-- only on touch screens). A small hint bar shows the controls for whatever
-- you're using right now and switches when you change.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HammerPower = Remotes:WaitForChild("HammerPower") :: RemoteEvent
local Announce = Remotes:WaitForChild("Announce") :: RemoteEvent

local player = Players.LocalPlayer
local HAMMER = "Ban Hammer"

-- Controls ---------------------------------------------------------------------
-- Each power: a keyboard key, a controller button, and its touch button title.
type Control = { Action: string, Title: string, Key: Enum.KeyCode, Pad: Enum.KeyCode, KeyLabel: string, PadLabel: string, Slot: number }
local CONTROLS: { Control } = {
	{ Action = "HammerFly", Title = "FLY", Key = Enum.KeyCode.F, Pad = Enum.KeyCode.ButtonY, KeyLabel = "F", PadLabel = "Y", Slot = 1 },
	{ Action = "HammerSprint", Title = "ZOOM", Key = Enum.KeyCode.G, Pad = Enum.KeyCode.ButtonX, KeyLabel = "G", PadLabel = "X", Slot = 2 },
	{ Action = "HammerSlam", Title = "SLAM", Key = Enum.KeyCode.R, Pad = Enum.KeyCode.ButtonR1, KeyLabel = "R", PadLabel = "R1", Slot = 3 },
}
-- While flying: up and down.
local UP = { Action = "HammerUp", Title = "▲", Key = Enum.KeyCode.Space, Pad = Enum.KeyCode.ButtonA, Slot = 4 }
local DOWN = { Action = "HammerDown", Title = "▼", Key = Enum.KeyCode.Q, Pad = Enum.KeyCode.ButtonB, Slot = 5 }

local flying = false
local rising, sinking = false, false
local flyVelocity: BodyVelocity? = nil
local flyGyro: BodyGyro? = nil

-- The hint bar (keyboard / controller only; touch has its own buttons)
local gui = Instance.new("ScreenGui")
gui.Name = "HammerPowers"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -96)
hint.Size = UDim2.fromOffset(560, 30)
hint.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
hint.BackgroundTransparency = 0.2
hint.Font = Enum.Font.FredokaOne
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(255, 200, 80)
hint.Parent = gui
local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 10)
hintCorner.Parent = hint
local hintPadding = Instance.new("UIPadding")
hintPadding.PaddingTop = UDim.new(0, 4)
hintPadding.PaddingBottom = UDim.new(0, 4)
hintPadding.Parent = hint

-- Which kind of controls the player is using right now.
local function usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end
local function usingTouch(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not usingGamepad())
end

local function refreshHint()
	if usingTouch() then
		hint.Visible = false
		return
	end
	hint.Visible = true
	local pad = usingGamepad()
	local parts = {}
	for _, control in CONTROLS do
		table.insert(parts, string.format("[%s] %s", if pad then control.PadLabel else control.KeyLabel, control.Title))
	end
	if flying then
		table.insert(parts, if pad then "[A/B] UP/DOWN" else "[SPACE/Q] UP/DOWN")
	end
	hint.Text = "🔨 " .. table.concat(parts, "   ")
end

-- Powers -------------------------------------------------------------------------

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopFlying()
	flying = false
	rising, sinking = false, false
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	ContextActionService:UnbindAction(UP.Action)
	ContextActionService:UnbindAction(DOWN.Action)
	refreshHint()
end

local function bindUpDown()
	for _, control in { UP, DOWN } do
		ContextActionService:BindAction(control.Action, function(_, state: Enum.UserInputState)
			local held = state == Enum.UserInputState.Begin
			if control == UP then
				rising = held
			else
				sinking = held
			end
			return Enum.ContextActionResult.Sink
		end, true, control.Key, control.Pad)
		ContextActionService:SetTitle(control.Action, control.Title)
		ContextActionService:SetPosition(control.Action, UDim2.new(1, -230, 1, -100 - (control.Slot - 3) * 70))
	end
end

local function startFlying()
	local hrp = root()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end
	flying = true
	humanoid.PlatformStand = true
	local velocity = Instance.new("BodyVelocity")
	velocity.MaxForce = Vector3.one * 1e6
	velocity.Velocity = Vector3.zero
	velocity.Parent = hrp
	flyVelocity = velocity
	local gyro = Instance.new("BodyGyro")
	gyro.MaxTorque = Vector3.one * 1e6
	gyro.P = 2e4
	gyro.CFrame = hrp.CFrame
	gyro.Parent = hrp
	flyGyro = gyro
	bindUpDown()
	refreshHint()
end

RunService.RenderStepped:Connect(function()
	local velocity, gyro = flyVelocity, flyGyro
	if not flying or not velocity or not gyro then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not humanoid or not camera then
		return
	end
	-- MoveDirection follows WASD, the thumbstick and the touch joystick.
	local move = humanoid.MoveDirection * Config.HammerFlySpeed
	local vertical = (if rising then 1 else 0) - (if sinking then 1 else 0)
	velocity.Velocity = move + Vector3.new(0, vertical * Config.HammerFlySpeed * 0.7, 0)
	local look = camera.CFrame.LookVector
	gyro.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z))
end)

local function onPower(action: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if action == "HammerFly" then
		if flying then
			stopFlying()
		else
			startFlying()
		end
	elseif action == "HammerSprint" then
		player:SetAttribute("HammerSprint", not player:GetAttribute("HammerSprint"))
		ContextActionService:SetTitle("HammerSprint", if player:GetAttribute("HammerSprint") then "ZOOM ✓" else "ZOOM")
	elseif action == "HammerSlam" then
		HammerPower:FireServer("Slam")
	end
	return Enum.ContextActionResult.Sink
end

local function bindPowers()
	for _, control in CONTROLS do
		ContextActionService:BindAction(control.Action, onPower, true, control.Key, control.Pad)
		ContextActionService:SetTitle(control.Action, control.Title)
		-- Touch buttons in a column left of the jump button.
		ContextActionService:SetPosition(control.Action, UDim2.new(1, -160, 1, -100 - control.Slot * 70))
	end
	gui.Enabled = true
	refreshHint()
end

local function unbindPowers()
	for _, control in CONTROLS do
		ContextActionService:UnbindAction(control.Action)
	end
	stopFlying()
	player:SetAttribute("HammerSprint", nil)
	gui.Enabled = false
end

-- The powers are on only while the hammer is held.
local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == HAMMER then
			bindPowers()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == HAMMER then
			unbindPowers()
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		(humanoid :: Humanoid).Died:Connect(unbindPowers)
	end
end
if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(function(character)
	unbindPowers()
	watchCharacter(character)
end)

-- Switch the hint between keyboard and controller labels as you switch.
UserInputService.LastInputTypeChanged:Connect(function()
	if gui.Enabled then
		refreshHint()
	end
end)

-- Everyone feels the SLAM: a quick camera shake.
Announce.OnClientEvent:Connect(function(kind: string)
	if kind ~= "slam" then
		return
	end
	task.spawn(function()
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not camera or not humanoid then
			return
		end
		for i = 1, 20 do
			local strength = (1 - i / 20) * 1.2
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end)

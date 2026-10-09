--!strict
-- Sprinting: hold Shift on a keyboard, tap the SPRINT button on a phone or
-- tablet (on/off), or click the left stick on a controller (on/off).
-- Runs Config.SprintMultiplier times faster than the normal speed (which is
-- faster during admin abuse). No sprinting while carrying a stolen brainrot.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local shiftHeld = false -- keyboard: only while held
local toggled = false -- phone button / controller stick: on until pressed again

-- The SPRINT button for touch screens, just left of the jump button.
local button: TextButton? = nil
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "SprintButton"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton")
	b.Name = "Sprint"
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -150, 1, -40)
	b.Size = UDim2.fromOffset(76, 76)
	b.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	b.BackgroundTransparency = 0.3
	b.Font = Enum.Font.FredokaOne
	b.Text = "🏃\nSPRINT"
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Ring"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(150, 150, 165)
	stroke.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = b
	b.Activated:Connect(function()
		toggled = not toggled
	end)
	button = b
end

-- Keyboard Shift (held) and controller left-stick click (toggle).
ContextActionService:BindAction("BrainrotSprint", function(_, state: Enum.UserInputState, input: InputObject)
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		if state == Enum.UserInputState.Begin then
			toggled = not toggled
		end
	else
		shiftHeld = state == Enum.UserInputState.Begin
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)

local function abuseLive(): boolean
	local now = workspace:GetServerTimeNow()
	local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
	return (manualEnd ~= nil and manualEnd > now) or Config.AdminAbuseStatus(now) == "live"
end

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local carrying = player:GetAttribute("Carrying") ~= nil
	local sprinting = (shiftHeld or toggled) and not carrying
	local ring = button and button:FindFirstChild("Ring") :: UIStroke?
	if ring then
		ring.Color = if carrying then Color3.fromRGB(90, 90, 100)
			elseif sprinting then Color3.fromRGB(120, 255, 160)
			else Color3.fromRGB(150, 150, 165)
	end
	if not humanoid or carrying then
		-- The server sets the (slower) carrying speed; leave it alone.
		return
	end
	local base = if abuseLive() then Config.AdminAbuseBoosts.WalkSpeed else Config.NormalWalkSpeed
	local speed = if sprinting then base * Config.SprintMultiplier else base
	-- Corny's hammer SUPER SPRINT (set by HammerPowers.client).
	if player:GetAttribute("HammerSprint") then
		speed = Config.HammerSprintSpeed
	end
	if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
		humanoid.WalkSpeed = speed
	end
end)

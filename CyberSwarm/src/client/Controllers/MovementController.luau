--!strict
--[[
	MovementController
	Lobby movement: sprint and slide.
	- Sprint: hold Left Shift (or toggle the SPRINT button on touch screens).
	- Slide: press C or Left Ctrl (or the SLIDE button) while running on the ground. A quick press
	  is a short slide; holding it keeps sliding further, up to MAX_SLIDE seconds.
	- The Speed Boost game pass raises the base walk speed.
	Only runs outside matches (and in the Test Realm), and never when the server has frozen the
	character (match decks set WalkSpeed to 0). Characters are client-owned, so this is purely
	feel: nothing here affects gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Widgets = require(script.Parent.Parent.UI.Widgets)
local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)

local SPRINT_MULTIPLIER = 1.6
local SPEED_BOOST_MULTIPLIER = 1.3
local SLIDE_SPEED = 2.4
local SHORT_SLIDE = 0.45
local MAX_SLIDE = 1.1
local SLIDE_COOLDOWN = 0.8
local SLIDE_DIP = 1.2

local MovementController = {}

local maid = Maid.new()
local sprintHeld = false
local sprintToggled = false
local slideHeld = false
local slideStartedAt = 0
local sliding = false
local slideDirection = Vector3.zAxis
local lastSlideEnd = 0
local baseHipHeight: number? = nil
local sprintButton: TextButton? = nil

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function active(): boolean
	return ClientState.match == nil or ClientState.sandbox ~= nil
end

local function baseSpeed(): number
	local speed = StarterPlayer.CharacterWalkSpeed
	if Players.LocalPlayer:GetAttribute("Pass_SpeedBoost") == true then
		speed *= SPEED_BOOST_MULTIPLIER
	end
	return speed
end

local function endSlide(humanoid: Humanoid?)
	if not sliding then
		return
	end
	sliding = false
	lastSlideEnd = os.clock()
	if humanoid ~= nil and baseHipHeight ~= nil then
		humanoid.HipHeight = baseHipHeight
	end
end

local function startSlide()
	local humanoid, root = humanoidAndRoot()
	if humanoid == nil or root == nil or sliding or not active() then
		return
	end
	if humanoid.WalkSpeed <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	if os.clock() - lastSlideEnd < SLIDE_COOLDOWN then
		return
	end
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then
		return
	end
	sliding = true
	slideStartedAt = os.clock()
	slideDirection = Vector3.new(move.X, 0, move.Z).Unit
	baseHipHeight = baseHipHeight or humanoid.HipHeight
	humanoid.HipHeight = math.max(0, (baseHipHeight :: number) - SLIDE_DIP)
end

local function step()
	local humanoid, root = humanoidAndRoot()
	if humanoid == nil or root == nil then
		return
	end
	if not active() then
		endSlide(humanoid)
		return
	end
	-- The server froze this character (match deck): leave it alone.
	if humanoid.WalkSpeed <= 0 then
		endSlide(humanoid)
		return
	end
	local base = baseSpeed()
	local sprinting = (sprintHeld or sprintToggled) and humanoid.MoveDirection.Magnitude > 0.1
	humanoid.WalkSpeed = if sprinting then base * SPRINT_MULTIPLIER else base

	if sliding then
		local elapsed = os.clock() - slideStartedAt
		local limit = if slideHeld then MAX_SLIDE else SHORT_SLIDE
		if elapsed >= limit or humanoid.FloorMaterial == Enum.Material.Air then
			endSlide(humanoid)
			return
		end
		-- Fast at first, easing off toward the end of the slide.
		local speed = base * SLIDE_SPEED * (1 - 0.5 * elapsed / MAX_SLIDE)
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(slideDirection.X * speed, velocity.Y, slideDirection.Z * speed)
	end
end

local function onInput(input: InputObject, processed: boolean, down: boolean)
	if processed and down then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.LeftShift then
		sprintHeld = down
	elseif key == Enum.KeyCode.C or key == Enum.KeyCode.LeftControl then
		slideHeld = down
		if down then
			startSlide()
		end
	end
end

local function buildTouchButtons(layer: Frame)
	local holder = UIKit.frame({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -190),
		Size = UDim2.fromOffset(96, 210),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	UIKit.list(holder, Enum.FillDirection.Vertical, UDim.new(0, 12))
	local sprint = Widgets.button(
		holder,
		"SPRINT",
		Theme.UI.Gem,
		{ LayoutOrder = 1, Size = UDim2.fromOffset(96, 96) },
		maid,
		function()
			sprintToggled = not sprintToggled
			local button = sprintButton
			if button ~= nil then
				Widgets.setButton(button, if sprintToggled then "SPRINT ON" else "SPRINT", Theme.UI.Gem, true)
			end
		end
	)
	UIKit.corner(sprint, UDim.new(1, 0))
	sprintButton = sprint
	local slide = Widgets.button(
		holder,
		"SLIDE",
		Theme.UI.Pink,
		{ LayoutOrder = 2, Size = UDim2.fromOffset(96, 96) },
		maid,
		function() end
	)
	UIKit.corner(slide, UDim.new(1, 0))
	maid:give(slide.MouseButton1Down:Connect(function()
		slideHeld = true
		startSlide()
	end))
	maid:give(slide.MouseButton1Up:Connect(function()
		slideHeld = false
	end))
end

function MovementController.init()
	maid:give(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		onInput(input, processed, true)
	end))
	maid:give(UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
		onInput(input, processed, false)
	end))
	maid:give(RunService.Heartbeat:Connect(step))
	maid:give(Players.LocalPlayer.CharacterAdded:Connect(function()
		sliding = false
		baseHipHeight = nil
	end))
	if UserInputService.TouchEnabled then
		buildTouchButtons(UIController.getLayer("Lobby"))
	end
end

return MovementController

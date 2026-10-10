--!strict
-- You are the ball. When the server assigns you a ball: the camera orbits it,
-- the aim guide (your equipped Arrow Skin) points where the camera looks, and
-- holding Left Click / Space / R2 / the PUTT button charges an in-world power
-- meter; release to putt. Abilities on 1 / 2 (X / Y on gamepad, touch buttons
-- on mobile). X / B / the SKIP button leaves the tutorial or a practice lane.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Hud = require(script.Parent:WaitForChild("Hud"))

local GolfController = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ball: BasePart? = nil
local info: { [string]: any } = {}
local charging = false
local chargeStart = 0
local power = 0
local guide: Model? = nil
local guideStyle: string? = nil
local meter: BillboardGui? = nil
local meterFill: Frame? = nil
local strip: BillboardGui? = nil
local stripLabel: TextLabel? = nil
local spectating: BasePart? = nil

local ACTION_CHARGE = "ChaosGolfCharge"
local ACTION_ABILITY1 = "ChaosGolfAbility1"
local ACTION_ABILITY2 = "ChaosGolfAbility2"
local ACTION_LEAVE = "ChaosGolfLeave"

-- Aim guide (equipped Arrow Skin) -------------------------------------------------

local function guidePart(model: Model, color: Color3, neon: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function destroyGuide()
	if guide then
		guide:Destroy()
		guide = nil
	end
	guideStyle = nil
end

local function buildGuide(arrowId: string?)
	destroyGuide()
	local def = Cosmetics.getOrDefault("Arrows", arrowId)
	local model = Instance.new("Model")
	model.Name = "AimGuide"
	local style = def.Style or "Classic"
	local neon = def.Neon == true
	local tip = def.Tip or def.Color
	local segments = if style == "Dotted" then 8 elseif style == "Chevron" then 6 elseif style == "Rainbow" or style == "Comet" then 7 else 1
	for i = 1, segments do
		local color = def.Color:Lerp(tip, if segments > 1 then (i - 1) / (segments - 1) else 0)
		if style == "Rainbow" then
			color = Color3.fromHSV((i - 1) / segments, 0.8, 1)
		end
		local p = guidePart(model, color, neon, if style == "Dotted" or style == "Comet" then Enum.PartType.Ball else nil)
		p.Name = "Seg" .. i
		if style == "Chevron" then
			for _, side in { "L", "R" } do
				local arm = guidePart(model, color, neon)
				arm.Name = "Chev" .. side .. i
			end
			p.Transparency = 1
		end
	end
	local head = guidePart(model, tip, neon)
	head.Name = "Head"
	model:SetAttribute("Pulse", def.Pulse == true)
	model:SetAttribute("Style", style)
	model.Parent = camera
	guide = model
	guideStyle = style
end

local function updateGuide(origin: Vector3, dir: Vector3, length: number, visible: boolean)
	local model = guide
	if not model then
		return
	end
	local style = guideStyle or "Classic"
	local pulse = model:GetAttribute("Pulse") == true
	local fade = if pulse then 0.15 + (math.sin(os.clock() * 6) + 1) * 0.12 else 0.1
	local y = origin.Y - Config.Ball.Diameter / 2 + 0.12
	local start = Vector3.new(origin.X, y, origin.Z) + dir * (Config.Ball.Diameter / 2 + 0.4)
	local finish = start + dir * length
	local look = CFrame.lookAt(start, finish)
	local thickness = if style == "Laser" then 0.14 else 0.32
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = if visible then fade else 1
		end
	end
	if not visible then
		return
	end
	local segs = {}
	for _, child in model:GetChildren() do
		local idx = tonumber(string.match(child.Name, "^Seg(%d+)$"))
		if idx then
			segs[idx] = child :: BasePart
		end
	end
	local n = #segs
	if style == "Classic" or style == "Laser" then
		local shaft = segs[1]
		shaft.Size = Vector3.new(thickness, 0.12, math.max(length - 1, 0.1))
		shaft.CFrame = look * CFrame.new(0, 0, -(length - 1) / 2)
	elseif style == "Chevron" then
		for i = 1, n do
			local d = (i - 0.5) / n * (length - 1)
			for _, side in { "L", "R" } do
				local sign = if side == "L" then -1 else 1
				local arm = model:FindFirstChild("Chev" .. side .. i) :: BasePart?
				if arm then
					arm.Size = Vector3.new(0.2, 0.12, 0.75)
					arm.CFrame = look * CFrame.new(sign * 0.24, 0, -d + 0.22) * CFrame.Angles(0, sign * math.rad(40), 0)
					arm.Transparency = fade
				end
			end
			segs[i].Transparency = 1
		end
	else
		for i = 1, n do
			local d = (i - 0.5) / n * (length - 1)
			local size = if style == "Comet" then 0.18 + 0.32 * (i / n) else 0.3
			local s = segs[i]
			if style == "Rainbow" then
				s.Size = Vector3.new(thickness, 0.12, (length - 1) / n * 0.9)
			else
				s.Size = Vector3.one * size
			end
			s.CFrame = look * CFrame.new(0, 0, -d)
		end
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		head.Size = Vector3.new(0.85, 0.14, 0.85)
		head.CFrame = look * CFrame.new(0, 0, -(length - 0.6)) * CFrame.Angles(0, math.rad(45), 0)
		head.Transparency = fade
	end
end

-- Power meter + ability strip (in-world, next to the ball) -------------------------------

local function buildBallUi(target: BasePart)
	if meter then
		meter:Destroy()
	end
	if strip then
		strip:Destroy()
	end
	local m = Instance.new("BillboardGui")
	m.Name = "PowerMeter"
	m.Size = UDim2.fromOffset(18, 90)
	m.StudsOffsetWorldSpace = Vector3.new(2.2, 1.2, 0)
	m.AlwaysOnTop = true
	m.LightInfluence = 0
	m.Enabled = false
	m.Adornee = target
	local frame = UIKit.panel({ Size = UDim2.fromScale(1, 1), Parent = m })
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	UIKit.corner(fill)
	local grad = Instance.new("UIGradient")
	grad.Rotation = -90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.Primary),
		ColorSequenceKeypoint.new(0.6, T.Gold),
		ColorSequenceKeypoint.new(1, T.Danger),
	})
	grad.Parent = fill
	fill.Parent = frame
	m.Parent = player:WaitForChild("PlayerGui")
	meter = m
	meterFill = fill

	local s = Instance.new("BillboardGui")
	s.Name = "AbilityStrip"
	s.Size = UDim2.fromOffset(220, 30)
	s.StudsOffsetWorldSpace = Vector3.new(0, -1.9, 0)
	s.AlwaysOnTop = true
	s.LightInfluence = 0
	s.Adornee = target
	local label = UIKit.text({
		Text = "",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = s,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = label
	s.Parent = player:WaitForChild("PlayerGui")
	strip = s
	stripLabel = label
end

local function abilityText(): string
	local parts = {}
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	for i = 1, Config.Match.MaxAbilities do
		local id = player:GetAttribute("Ability" .. i) :: string?
		local def = Abilities.get(id)
		if def then
			table.insert(parts, (if touch then "" else "[" .. i .. "] ") .. def.Icon .. " " .. def.Name)
		end
	end
	local target = ball
	if target then
		if target:GetAttribute("Frosted") then
			table.insert(parts, "❄ frosted")
		end
		if target:GetAttribute("Gusted") then
			table.insert(parts, "🌪 wind")
		end
		if target:GetAttribute("TinyCup") then
			table.insert(parts, "🎯 tiny cup")
		end
		if target:GetAttribute("Magnet") then
			table.insert(parts, "🧲 magnet ready")
		end
	end
	return table.concat(parts, "   ")
end

-- Actions ----------------------------------------------------------------------------

local function canShoot(): boolean
	return ball ~= nil and (ball :: BasePart).Parent ~= nil and (ball :: BasePart):GetAttribute("CanShoot") == true
end

local function aimDirection(): Vector3
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function release()
	if not charging then
		return
	end
	charging = false
	if meter then
		meter.Enabled = false
	end
	if canShoot() and power > 0 then
		Net.event("Shoot"):FireServer(aimDirection(), math.max(power, Config.Physics.MinPower))
	end
	power = 0
end

local function chargeAction(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		if canShoot() then
			charging = true
			chargeStart = os.clock()
			power = 0
			if meter then
				meter.Enabled = true
			end
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		release()
	end
	return Enum.ContextActionResult.Sink
end

local function abilityAction(name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		Net.event("UseAbility"):FireServer(if name == ACTION_ABILITY1 then 1 else 2)
	end
	return Enum.ContextActionResult.Sink
end

local function leaveAction(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		Net.event("LeaveActivity"):FireServer()
	end
	return Enum.ContextActionResult.Sink
end

local function refreshAbilityButtons()
	for i, action in { ACTION_ABILITY1, ACTION_ABILITY2 } do
		local def = Abilities.get(player:GetAttribute("Ability" .. i) :: string?)
		local button = ContextActionService:GetButton(action)
		if button then
			button.Visible = def ~= nil
		end
		if def then
			ContextActionService:SetTitle(action, def.Icon)
		end
	end
	if stripLabel then
		stripLabel.Text = abilityText()
	end
end

local function bindControls(context: string)
	ContextActionService:BindActionAtPriority(ACTION_CHARGE, chargeAction, true, 2000, Enum.UserInputType.MouseButton1, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle(ACTION_CHARGE, "PUTT")
	if context ~= "Practice" then
		ContextActionService:BindAction(ACTION_ABILITY1, abilityAction, true, Enum.KeyCode.One, Enum.KeyCode.ButtonX)
		ContextActionService:BindAction(ACTION_ABILITY2, abilityAction, true, Enum.KeyCode.Two, Enum.KeyCode.ButtonY)
	end
	if context == "Tutorial" or context == "Practice" then
		ContextActionService:BindAction(ACTION_LEAVE, leaveAction, true, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
		ContextActionService:SetTitle(ACTION_LEAVE, if context == "Tutorial" then "SKIP" else "EXIT")
	end
	refreshAbilityButtons()
end

local function unbindControls()
	for _, a in { ACTION_CHARGE, ACTION_ABILITY1, ACTION_ABILITY2, ACTION_LEAVE } do
		ContextActionService:UnbindAction(a)
	end
	charging = false
end

local function setReset(enabled: boolean)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", enabled)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

local function restoreCamera()
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 40
end

local function pickSpectate(): BasePart?
	local folder = workspace:FindFirstChild("GolfBalls")
	if not folder then
		return nil
	end
	for _, b in folder:GetChildren() do
		if b:IsA("BasePart") and b:GetAttribute("Owner") ~= player.UserId then
			return b
		end
	end
	return nil
end

local function assign(newBall: BasePart?, newInfo: { [string]: any }?)
	info = newInfo or {}
	release()
	if newBall then
		ball = newBall
		spectating = nil
		Hud.ball = newBall
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = newBall
		player.CameraMinZoomDistance = 6
		player.CameraMaxZoomDistance = 70
		local look = (info.TeeLook :: Vector3?) or Vector3.new(0, 0, -1)
		camera.CFrame = CFrame.lookAt(newBall.Position - look * 16 + Vector3.new(0, 8, 0), newBall.Position)
		buildGuide(newBall:GetAttribute("Arrow") :: string?)
		buildBallUi(newBall)
		unbindControls()
		bindControls(info.Context or "Match")
		setReset(false)
		newBall:GetAttributeChangedSignal("CanShoot"):Connect(function()
			if not canShoot() then
				release()
			end
		end)
		for _, attr in { "Frosted", "Gusted", "TinyCup", "Magnet" } do
			newBall:GetAttributeChangedSignal(attr):Connect(refreshAbilityButtons)
		end
		return
	end

	ball = nil
	Hud.ball = nil
	destroyGuide()
	if meter then
		meter:Destroy()
		meter = nil
	end
	if strip then
		strip:Destroy()
		strip = nil
	end
	if info.Spectate then
		-- Our ball is done for this hole: watch someone else's.
		spectating = pickSpectate()
		if spectating then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = spectating
		elseif info.Overview then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = info.Overview
		end
		return
	end
	unbindControls()
	setReset(true)
	restoreCamera()
end

function GolfController.start()
	Net.event("BallAssigned").OnClientEvent:Connect(assign)
	player:GetAttributeChangedSignal("Ability1"):Connect(refreshAbilityButtons)
	player:GetAttributeChangedSignal("Ability2"):Connect(refreshAbilityButtons)
	player.CharacterAdded:Connect(function()
		if not ball and not spectating then
			task.defer(restoreCamera)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local target = ball
		if not target or not target.Parent then
			if spectating and not spectating.Parent then
				spectating = pickSpectate()
				if spectating then
					camera.CameraSubject = spectating
				end
			end
			return
		end
		local can = canShoot()
		if charging then
			local cycle = (info.PowerCycle :: number?) or Config.Physics.PowerCycleSeconds
			local phase = ((os.clock() - chargeStart) / cycle) % 1
			power = if phase < 0.5 then phase * 2 else 2 - phase * 2
			if meterFill then
				meterFill.Size = UDim2.fromScale(1, math.max(power, 0.02))
			end
		end
		local length = 3 + (if charging then power else 0.35) * 10
		updateGuide(target.Position, aimDirection(), length, can)
	end)
end

return GolfController

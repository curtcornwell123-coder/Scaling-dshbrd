--!strict
--[[
	UIKit
	Small helpers for building all UI in code with the shared Theme.

	Scaling: each screen has a root frame sized 1/s of the screen with a UIScale of s, where s
	follows the viewport height. Layout inside uses Scale sizing (so it fills any screen), while
	pixel details (strokes, corners, padding, text size limits) shrink and grow with s. That is what
	keeps the same layout crisp on phones and 4K monitors.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)

local REFERENCE_HEIGHT = 1080
local MIN_SCALE = 0.5
local MAX_SCALE = 1.5
local HOVER_SCALE = 1.04
local PRESS_SCALE = 0.95

type Props = { [string]: any }

local UIKit = {}

function UIKit.create(className: string, props: Props?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props ~= nil then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children ~= nil then
		for _, child in children do
			child.Parent = instance
		end
	end
	-- Parent last so the instance is fully configured before it replicates or renders.
	if parent ~= nil then
		instance.Parent = parent
	end
	return instance
end

local function withDefaults(defaults: Props, props: Props?): Props
	local merged = table.clone(defaults)
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	return merged
end

function UIKit.frame(props: Props?, children: { Instance }?): Frame
	return UIKit.create(
		"Frame",
		withDefaults({
			BackgroundColor3 = Theme.Colors.Panel,
			BorderSizePixel = 0,
		}, props),
		children
	) :: Frame
end

function UIKit.label(props: Props?, maxTextSize: number?): TextLabel
	local label = UIKit.create(
		"TextLabel",
		withDefaults({
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			TextColor3 = Theme.Colors.Text,
			TextScaled = true,
			TextWrapped = true,
			Text = "",
		}, props)
	) :: TextLabel
	UIKit.textLimit(label, maxTextSize or Theme.Text.BODY_MAX)
	return label
end

function UIKit.button(props: Props?, maxTextSize: number?): TextButton
	local button = UIKit.create(
		"TextButton",
		withDefaults({
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Colors.PanelLight,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextScaled = true,
			TextWrapped = true,
			Text = "",
		}, props)
	) :: TextButton
	UIKit.textLimit(button, maxTextSize or Theme.Text.BODY_MAX)
	UIKit.corner(button)
	return button
end

function UIKit.corner(parent: Instance, radius: UDim?): UICorner
	return UIKit.create("UICorner", {
		CornerRadius = radius or Theme.CornerRadius,
		Parent = parent,
	}) :: UICorner
end

function UIKit.stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	return UIKit.create("UIStroke", {
		Color = color,
		Thickness = thickness or Theme.StrokeThickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	}) :: UIStroke
end

function UIKit.padding(parent: Instance, scale: number): UIPadding
	local amount = UDim.new(scale, 0)
	return UIKit.create("UIPadding", {
		PaddingTop = amount,
		PaddingBottom = amount,
		PaddingLeft = amount,
		PaddingRight = amount,
		Parent = parent,
	}) :: UIPadding
end

function UIKit.list(
	parent: Instance,
	direction: Enum.FillDirection,
	spacing: UDim,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	return UIKit.create("UIListLayout", {
		FillDirection = direction,
		Padding = spacing,
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	}) :: UIListLayout
end

function UIKit.aspect(parent: Instance, ratio: number): UIAspectRatioConstraint
	return UIKit.create("UIAspectRatioConstraint", {
		AspectRatio = ratio,
		Parent = parent,
	}) :: UIAspectRatioConstraint
end

function UIKit.textLimit(parent: Instance, maxSize: number): UITextSizeConstraint
	return UIKit.create("UITextSizeConstraint", {
		MaxTextSize = maxSize,
		MinTextSize = 1,
		Parent = parent,
	}) :: UITextSizeConstraint
end

function UIKit.gradient(parent: Instance, from: Color3, to: Color3, rotation: number): UIGradient
	return UIKit.create("UIGradient", {
		Color = ColorSequence.new(from, to),
		Rotation = rotation,
		Parent = parent,
	}) :: UIGradient
end

-- Only writes when the text changed, so per-frame callers never cause needless re-layouts.
function UIKit.setText(label: TextLabel | TextButton, text: string)
	-- Both classes have Text; going through `any` keeps the union simple for the type checker.
	local target: any = label
	if target.Text ~= text then
		target.Text = text
	end
end

function UIKit.tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

-- Hover/press feedback through a UIScale, plus the click handler. All connections go to `maid`.
function UIKit.bindButton(button: GuiButton, maid: Maid.Maid, onActivated: () -> ())
	local scale = Instance.new("UIScale")
	scale.Parent = button
	maid:give(button.MouseEnter:Connect(function()
		UIKit.tween(scale, Theme.Tween.Fast, { Scale = HOVER_SCALE })
	end))
	maid:give(button.MouseLeave:Connect(function()
		UIKit.tween(scale, Theme.Tween.Fast, { Scale = 1 })
	end))
	maid:give(button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, Theme.Tween.Fast, { Scale = PRESS_SCALE })
	end))
	maid:give(button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, Theme.Tween.Fast, { Scale = 1 })
	end))
	maid:give(button.Activated:Connect(function()
		onActivated()
	end))
end

-- Creates a ScreenGui in PlayerGui and returns its auto-scaled root frame.
function UIKit.screen(name: string, displayOrder: number, maid: Maid.Maid): (ScreenGui, Frame)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = UIKit.create("ScreenGui", {
		Name = name,
		DisplayOrder = displayOrder,
		-- Keep content below Roblox's top bar so the menu and chat buttons never cover it.
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	local root = UIKit.frame({
		Name = "Root",
		BackgroundTransparency = 1,
		Parent = screen,
	})
	local uiScale = UIKit.create("UIScale", { Parent = root }) :: UIScale

	local function rescale()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local scale = math.clamp(camera.ViewportSize.Y / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
		uiScale.Scale = scale
		-- Oversize the root by 1/scale so after scaling it exactly covers the screen.
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end

	local cameraMaid = Maid.new()
	maid:give(cameraMaid)
	local function watchCamera()
		cameraMaid:cleanup()
		local camera = workspace.CurrentCamera
		if camera ~= nil then
			cameraMaid:give(camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
		end
		rescale()
	end
	maid:give(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
	watchCamera()

	screen.Parent = playerGui
	maid:give(screen)
	return screen, root
end

return UIKit

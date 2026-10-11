--!strict
--[[
	Widgets
	The lobby's visual language, built on UIKit:
	- window: a glassy side window (never the full side of the screen) with a title, accent bar,
	  close button, optional tabs, and a scrolling body that always fits its content.
	- card / button / chip / bar / viewport: the pieces every panel is made of.
	Everything uses Theme colours, 0.2 s ease-out motion, and 44 px minimum touch targets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local RobotModels = require(ReplicatedStorage.Shared.Visual.RobotModels)
local UIKit = require(script.Parent.UIKit)

local UI = Theme.UI
local TOUCH = 44

export type Side = "Left" | "Right" | "Center"

export type Window = {
	frame: Frame,
	body: ScrollingFrame,
	title: TextLabel,
	subtitle: TextLabel,
	tabs: { [string]: TextButton },
	setTab: (name: string) -> (),
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	clear: () -> (),
}

export type WindowOptions = {
	name: string,
	title: string,
	accent: Color3,
	side: Side,
	width: number,
	height: number,
	parent: Instance,
	maid: Maid.Maid,
	tabs: { string }?,
	onTab: ((string) -> ())?,
	onClose: (() -> ())?,
	-- Grid cells instead of a vertical list.
	grid: UDim2?,
}

local Widgets = {}

-- Every window; opening one closes the others so panels never stack.
local openWindows: { Window } = {}

Widgets.TOUCH = TOUCH

-- Soft drop shadow: a dark, slightly larger rounded frame behind `frame`.
function Widgets.shadow(frame: GuiObject, radius: UDim?)
	local shadow = UIKit.frame({
		Name = "Shadow",
		AnchorPoint = frame.AnchorPoint,
		Position = frame.Position + UDim2.fromOffset(0, 6),
		Size = frame.Size + UDim2.fromOffset(10, 10),
		BackgroundColor3 = UI.Shadow,
		BackgroundTransparency = 0.6,
		ZIndex = math.max(0, frame.ZIndex - 1),
		Parent = frame.Parent,
	})
	UIKit.corner(shadow, radius or UDim.new(0, 18))
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		shadow.Visible = frame.Visible
	end)
	frame:GetPropertyChangedSignal("Position"):Connect(function()
		shadow.Position = frame.Position + UDim2.fromOffset(0, 6)
	end)
	shadow.Visible = frame.Visible
end

function Widgets.label(parent: Instance, text: string, props: { [string]: any }?, maxSize: number?): TextLabel
	local merged: { [string]: any } = { Text = text, Parent = parent, TextXAlignment = Enum.TextXAlignment.Left }
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	return UIKit.label(merged, maxSize or Theme.Text.BODY_MAX)
end

-- Gradient pill button with a darker lip underneath. `enabled = false` greys it out.
function Widgets.button(
	parent: Instance,
	text: string,
	accent: Color3,
	props: { [string]: any }?,
	maid: Maid.Maid,
	onActivated: () -> ()
): TextButton
	local merged: { [string]: any } = {
		Text = text,
		BackgroundColor3 = Color3.new(1, 1, 1),
		TextColor3 = Color3.fromRGB(14, 16, 28),
		Size = UDim2.new(0.3, 0, 0, TOUCH),
		Parent = parent,
	}
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	local button = UIKit.button(merged, Theme.Text.BODY_MAX)
	UIKit.corner(button, UDim.new(0, 12))
	UIKit.gradient(button, accent:Lerp(Color3.new(1, 1, 1), 0.25), accent:Lerp(Color3.new(0, 0, 0), 0.12), 90)
	UIKit.stroke(button, accent:Lerp(Color3.new(0, 0, 0), 0.45), 2, 0.1)
	UIKit.bindButton(button, maid, onActivated)
	return button
end

-- Recolours a Widgets.button (e.g. CLAIM -> CLAIMED) without rebuilding it.
function Widgets.setButton(button: TextButton, text: string, accent: Color3, enabled: boolean)
	UIKit.setText(button, text)
	local gradient = button:FindFirstChildOfClass("UIGradient")
	local colorA = if enabled then accent:Lerp(Color3.new(1, 1, 1), 0.25) else Color3.fromRGB(70, 74, 92)
	local colorB = if enabled then accent:Lerp(Color3.new(0, 0, 0), 0.12) else Color3.fromRGB(46, 50, 66)
	if gradient ~= nil then
		gradient.Color = ColorSequence.new(colorA, colorB)
	end
	button.TextColor3 = if enabled then Color3.fromRGB(14, 16, 28) else Color3.fromRGB(150, 156, 180)
	button.AutoButtonColor = false
	button:SetAttribute("Enabled", enabled)
end

function Widgets.chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?): TextLabel
	local merged: { [string]: any } = {
		Text = text,
		Size = UDim2.fromOffset(90, 22),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.55),
		TextColor3 = color,
		Font = Theme.Fonts.Title,
		Parent = parent,
	}
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	local chip = UIKit.label(merged, Theme.Text.SMALL_MAX)
	UIKit.corner(chip, UDim.new(1, 0))
	UIKit.stroke(chip, color, 1, 0.4)
	return chip
end

-- Rounded progress bar. Returns the fill so callers can resize it.
function Widgets.bar(parent: Instance, fraction: number, color: Color3, props: { [string]: any }?): Frame
	local merged: { [string]: any } = {
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = UI.TrackBack,
		Parent = parent,
	}
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	local back = UIKit.frame(merged)
	UIKit.corner(back, UDim.new(1, 0))
	local fill = UIKit.frame({
		Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = back,
	})
	UIKit.corner(fill, UDim.new(1, 0))
	UIKit.gradient(fill, color:Lerp(Color3.new(1, 1, 1), 0.3), color, 0)
	return fill
end

-- Gradient card used for rows and tiles.
function Widgets.card(parent: Instance, accent: Color3?, props: { [string]: any }?, locked: boolean?): Frame
	local merged: { [string]: any } = {
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	local card = UIKit.frame(merged)
	UIKit.corner(card, UDim.new(0, 14))
	if locked then
		UIKit.gradient(card, UI.CardLocked, UI.CardLocked:Lerp(Color3.new(0, 0, 0), 0.3), 90)
	else
		UIKit.gradient(card, UI.Card, UI.CardBottom, 90)
	end
	UIKit.stroke(card, accent or UI.Edge, 1.5, if accent ~= nil then 0.35 else 0.88)
	return card
end

-- 3D preview of a robot in a ViewportFrame (the same model the game spawns).
function Widgets.robotViewport(parent: Instance, robot: Types.RobotDef, props: { [string]: any }?): ViewportFrame
	local merged: { [string]: any } = {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = UI.TrackBack,
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(170, 176, 200),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = parent,
	}
	if props ~= nil then
		for key, value in props do
			merged[key] = value
		end
	end
	local viewport = UIKit.create("ViewportFrame", merged) :: ViewportFrame
	UIKit.corner(viewport, UDim.new(0, 12))
	local model = RobotModels.build(robot)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	local _, size = model:GetBoundingBox()
	local distance = math.max(size.X, size.Y, size.Z) * 1.55 + 2
	camera.FieldOfView = 40
	camera.CFrame =
		CFrame.lookAt(Vector3.new(distance * 0.55, distance * 0.35, -distance), Vector3.new(0, size.Y * 0.05, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

function Widgets.window(options: WindowOptions): Window
	local anchorX = if options.side == "Left" then 0 elseif options.side == "Right" then 1 else 0.5
	local x = if options.side == "Left" then 0.035 elseif options.side == "Right" then 0.965 else 0.5
	local openPosition = UDim2.fromScale(x, 0.5)
	local slide = if options.side == "Left" then -0.03 elseif options.side == "Right" then 0.03 else 0
	local frame = UIKit.frame({
		Name = options.name,
		AnchorPoint = Vector2.new(anchorX, 0.5),
		Position = openPosition,
		Size = UDim2.fromScale(options.width, options.height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 2,
		Parent = options.parent,
	})
	UIKit.corner(frame, UDim.new(0, 18))
	UIKit.gradient(frame, UI.WindowTop, UI.WindowBottom, 90)
	UIKit.stroke(frame, options.accent, 2, 0.35)
	Widgets.shadow(frame)

	-- Accent bar along the top edge.
	local accentBar = UIKit.frame({
		Size = UDim2.new(1, -36, 0, 4),
		Position = UDim2.new(0, 18, 0, 0),
		BackgroundColor3 = options.accent,
		ZIndex = 3,
		Parent = frame,
	})
	UIKit.corner(accentBar, UDim.new(1, 0))

	local title = Widgets.label(frame, options.title, {
		Size = UDim2.new(1, -90, 0, 34),
		Position = UDim2.fromOffset(20, 14),
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
	}, 30)
	local subtitle = Widgets.label(frame, "", {
		Size = UDim2.new(1, -90, 0, 18),
		Position = UDim2.fromOffset(20, 48),
		Font = Theme.Fonts.Body,
		TextColor3 = options.accent,
		ZIndex = 3,
	}, 16)

	local window: Window
	local close = UIKit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(TOUCH, TOUCH),
		Text = "X",
		BackgroundColor3 = Color3.fromRGB(40, 46, 76),
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = frame,
	}, 22)
	UIKit.corner(close, UDim.new(1, 0))

	local top = 74
	local tabs: { [string]: TextButton } = {}
	local tabNames = options.tabs
	if tabNames ~= nil then
		local bar = UIKit.frame({
			Size = UDim2.new(1, -40, 0, 40),
			Position = UDim2.fromOffset(20, top),
			BackgroundColor3 = UI.TrackBack,
			BackgroundTransparency = 0.2,
			ZIndex = 3,
			Parent = frame,
		})
		UIKit.corner(bar, UDim.new(0, 12))
		UIKit.list(
			bar,
			Enum.FillDirection.Horizontal,
			UDim.new(0, 4),
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		for order, name in tabNames do
			local tab = UIKit.button({
				LayoutOrder = order,
				Size = UDim2.new(1 / #tabNames, -4, 1, -8),
				Text = string.upper(name),
				BackgroundColor3 = Color3.fromRGB(28, 34, 60),
				TextColor3 = Color3.fromRGB(170, 178, 210),
				ZIndex = 4,
				Parent = bar,
			}, 18)
			UIKit.corner(tab, UDim.new(0, 10))
			tabs[name] = tab
		end
		top += 50
	end

	local body = UIKit.create("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, -28, 1, -(top + 16)),
		Position = UDim2.fromOffset(16, top + 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = options.accent,
		ZIndex = 3,
		Parent = frame,
	}) :: ScrollingFrame
	UIKit.create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		Parent = body,
	})
	local function addLayout()
		local grid = options.grid
		if grid ~= nil then
			UIKit.create("UIGridLayout", {
				CellSize = grid,
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = body,
			})
		else
			UIKit.list(body, Enum.FillDirection.Vertical, UDim.new(0, 10))
		end
	end
	addLayout()

	local selected: string? = nil
	local function setTab(name: string)
		selected = name
		for tabName, tab in tabs do
			local active = tabName == name
			tab.BackgroundColor3 = if active then options.accent else Color3.fromRGB(28, 34, 60)
			tab.TextColor3 = if active then Color3.fromRGB(14, 16, 28) else Color3.fromRGB(170, 178, 210)
		end
		body.CanvasPosition = Vector2.zero
		local onTab = options.onTab
		if onTab ~= nil then
			onTab(name)
		end
	end
	for name, tab in tabs do
		UIKit.bindButton(tab, options.maid, function()
			setTab(name)
		end)
	end

	local function clear()
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	window = {
		frame = frame,
		body = body,
		title = title,
		subtitle = subtitle,
		tabs = tabs,
		setTab = setTab,
		open = function()
			if frame.Visible then
				return
			end
			for _, other in openWindows do
				if other ~= window then
					other.close()
				end
			end
			frame.Position = openPosition + UDim2.fromScale(slide, 0.02)
			frame.Visible = true
			UIKit.tween(frame, Theme.Tween.Normal, { Position = openPosition })
			if tabNames ~= nil and selected == nil then
				setTab(tabNames[1])
			end
		end,
		close = function()
			if not frame.Visible then
				return
			end
			frame.Visible = false
			local onClose = options.onClose
			if onClose ~= nil then
				onClose()
			end
		end,
		isOpen = function(): boolean
			return frame.Visible
		end,
		clear = clear,
	}
	UIKit.bindButton(close, options.maid, function()
		window.close()
	end)
	table.insert(openWindows, window)
	return window
end

function Widgets.closeAll()
	for _, window in openWindows do
		window.close()
	end
end

return Widgets

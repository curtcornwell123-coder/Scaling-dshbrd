--!strict
-- Tutorial on screen: the one-time welcome card (Play / Skip) for new players and,
-- during the tutorial, a coach card with the current lesson as a checklist that
-- ticks as the server reports progress. Wording follows the player's device (picked on
-- first join, or a controller in use). Controller friendly: A plays, B skips.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local GuideUi = require(script.Parent:WaitForChild("GuideUi"))
local Pad = require(script.Parent:WaitForChild("Pad"))

local TutorialUi = {}

local T = UIKit.Theme
local player = Players.LocalPlayer

type Device = "pc" | "touch" | "pad"
type Lines = { pc: string, touch: string?, pad: string? }

local STEP_TEXT: { [string]: Lines } = {
	aim = {
		pc = "<b>Aim:</b> hold <b>Right Click</b> and drag to turn the camera. The arrow shows your line.",
		touch = "<b>Aim:</b> drag on the screen to turn the camera. The arrow shows your line.",
		pad = "<b>Aim:</b> turn the camera with the <b>right stick</b>. The arrow shows your line.",
	},
	charge = {
		pc = "<b>Power:</b> hold <b>Left Click</b> (or <b>Space</b>) to charge.",
		touch = "<b>Power:</b> press and hold the <b>putt button</b> to charge.",
		pad = "<b>Power:</b> hold <b>R2</b> to charge.",
	},
	release = { pc = "<b>Putt:</b> let go to shoot. The longer you charge, the harder you hit." },
	sink = { pc = "<b>Sink it:</b> get the ball into the cup." },
	bank = { pc = "<b>Bank shot:</b> aim at a rail. The ball bounces off it and around the corner." },
	box = { pc = "<b>Chaos box:</b> roll through the glowing box to grab an ability." },
	ability = {
		pc = "<b>Use it:</b> press <b>1</b> before your next putt.",
		touch = "<b>Use it:</b> tap the <b>ability button</b> before your next putt.",
		pad = "<b>Use it:</b> press <b>X</b> before your next putt.",
	},
}

local gui: ScreenGui
local invite: Frame? = nil
local coach: Frame? = nil
local lastSteps: any = nil

local function device(): Device
	return Pad.device()
end

local function stepText(key: string): string
	local lines = STEP_TEXT[key]
	if not lines then
		return key
	end
	local d = device()
	return (if d == "touch" then lines.touch elseif d == "pad" then lines.pad else nil) or lines.pc
end

local function narrow(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.X < 760
end

-- Welcome card -------------------------------------------------------------------

local function closeInvite()
	local card = invite
	invite = nil
	if card and card.Parent then
		(card.Parent :: Instance):Destroy() -- the dim overlay holding the card
	end
	Pad.closed("TutorialInvite")
end

local function showInvite(payload: any)
	closeInvite()
	local coins = if type(payload) == "table" and type(payload.Coins) == "number" then payload.Coins else 200
	local overlay = Instance.new("Frame")
	overlay.Name = "TutorialInvite"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = gui
	local width = if narrow() then 320 else 440
	local card = UIKit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = overlay,
	})
	UIKit.padding(card, 20)
	UIKit.list(card, 10, false, Enum.HorizontalAlignment.Center)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = card
	UIKit.text({
		Text = "WELCOME TO ULTIMATE GOLF",
		TextSize = if narrow() then 22 else 26,
		Font = T.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = card,
	})
	UIKit.text({
		Text = "You're the ball! Learn to aim, putt and use chaos abilities in a quick 3-hole tutorial (about 2 minutes).",
		TextSize = 16,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = card,
	})
	UIKit.text({
		Text = string.format('Reward: <font color="#FFC83D"><b>%d coins</b></font> + the <b>Rookie</b> ball skin', coins),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = card,
	})
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 42)
	row.LayoutOrder = 4
	row.Parent = card
	local function choose(choice: string)
		if invite ~= card then
			return
		end
		Net.event("TutorialChoice"):FireServer(choice)
		closeInvite()
	end
	local play = UIKit.button("Play Tutorial", "Primary", {
		Size = UDim2.new(0.6, -5, 1, 0),
		TextSize = 17,
		Parent = row,
	}, function()
		choose("play")
	end)
	UIKit.button("Skip", "Secondary", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, -5, 1, 0),
		TextSize = 17,
		Parent = row,
	}, function()
		choose("skip")
	end)
	UIKit.button("📖  Read the Player Guide first", "Ghost", {
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 15,
		LayoutOrder = 5,
		Parent = card,
	}, function()
		GuideUi.open("Controls")
	end)
	UIKit.text({
		Text = "You can replay it anytime from the pad in the Practice room.",
		TextSize = 13,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 6,
		Parent = card,
	})
	invite = card
	Pad.opened("TutorialInvite", function()
		choose("skip")
	end)
	Pad.focus(play)
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(scale, info, { Scale = 1 }):Play()
end

-- Coach card ------------------------------------------------------------------------

local function closeCoach()
	local card = coach
	coach = nil
	lastSteps = nil
	if card then
		local tween = TweenService:Create(card, TweenInfo.new(0.2), { Position = card.Position - UDim2.fromOffset(card.AbsoluteSize.X + 40, 0) })
		tween.Completed:Once(function()
			card:Destroy()
		end)
		tween:Play()
	end
end

local function bullet(done: boolean, parent: Instance)
	local dot = Instance.new("TextLabel")
	dot.Size = UDim2.fromOffset(22, 22)
	dot.BackgroundColor3 = if done then T.Primary else T.SurfaceHi
	dot.BorderSizePixel = 0
	dot.Font = T.FontHeavy
	dot.TextSize = 14
	dot.TextColor3 = T.PrimaryText
	dot.Text = if done then "✓" else ""
	dot.Parent = parent
	UIKit.corner(dot, UDim.new(1, 0))
	if not done then
		UIKit.stroke(dot, T.Stroke, 1.5, 0)
	end
	return dot
end

local function renderCoach(p: any)
	lastSteps = p
	local fresh = coach == nil
	local width = if narrow() then 270 else 340
	local frame: Frame
	if coach then
		frame = coach
	else
		frame = UIKit.panel({
			Name = "TutorialCoach",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -width - 40, 0.45, 0),
			Size = UDim2.fromOffset(width, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 0.04,
			Parent = gui,
		})
		UIKit.padding(frame, 14)
		UIKit.list(frame, 8)
		coach = frame
	end
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	UIKit.tag(string.format("TUTORIAL  %d / %d", p.Hole, p.Holes), T.Primary, { LayoutOrder = 1, Parent = frame })
	UIKit.text({
		Text = p.Title,
		TextSize = 22,
		Font = T.FontHeavy,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = frame,
	})
	for i, step in p.Steps do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = 2 + i
		row.Parent = frame
		local dot = bullet(step.Done, row)
		dot.Position = UDim2.fromOffset(0, 1)
		UIKit.text({
			Text = stepText(step.Key),
			TextSize = 15,
			Font = T.FontMedium,
			TextColor3 = if step.Done then T.Muted else T.Text,
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = row,
		})
	end
	local d = device()
	local key = if d == "pad" then " (B)" elseif d == "pc" then " (X)" else ""
	UIKit.button("Skip tutorial" .. key, "Ghost", {
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 14,
		LayoutOrder = 100,
		Parent = frame,
	}, function()
		Net.event("LeaveActivity"):FireServer()
	end)
	if fresh then
		TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 16, 0.45, 0),
		}):Play()
	end
end

function TutorialUi.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "TutorialUi"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.event("Tutorial").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "invite" then
			showInvite(payload)
		elseif kind == "steps" and type(payload) == "table" and type(payload.Steps) == "table" then
			closeInvite()
			renderCoach(payload)
		elseif kind == "done" then
			closeCoach()
		end
	end)
	-- Re-word the checklist when the player switches between mouse, touch and gamepad.
	UserInputService.LastInputTypeChanged:Connect(function()
		if coach and lastSteps then
			renderCoach(lastSteps)
		end
	end)
end

return TutorialUi

--!strict
-- The only persistent screen element: the compact coin counter (top-right,
-- under the player list). Plus in-world toasts that float above your ball (or
-- your character in the lobby) instead of screen pop-ups.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local State = require(script.Parent:WaitForChild("State"))

local Hud = {}

local T = UIKit.Theme
local player = Players.LocalPlayer

local coinLabel: TextLabel
local boostTag: Frame
local shown = 0

-- Coin counter ------------------------------------------------------------------

local function coinGlyph(parent: Instance): Frame
	local outer = Instance.new("Frame")
	outer.Size = UDim2.fromOffset(22, 22)
	outer.BackgroundColor3 = T.Gold
	outer.BorderSizePixel = 0
	UIKit.corner(outer, UDim.new(1, 0))
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromOffset(12, 12)
	inner.BackgroundColor3 = T.Gold:Lerp(Color3.new(0, 0, 0), 0.25)
	inner.BorderSizePixel = 0
	UIKit.corner(inner, UDim.new(1, 0))
	inner.Parent = outer
	outer.Parent = parent
	return outer
end

local function setCoins(target: number, animate: boolean)
	if not animate then
		shown = target
		coinLabel.Text = UIKit.formatNumber(target)
		return
	end
	local value = Instance.new("NumberValue")
	value.Value = shown
	value.Changed:Connect(function(v)
		coinLabel.Text = UIKit.formatNumber(v)
	end)
	shown = target
	local tween = TweenService:Create(value, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	tween.Completed:Once(function()
		coinLabel.Text = UIKit.formatNumber(target)
		value:Destroy()
	end)
	tween:Play()
end

local function buildCounter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "UltimateGolfHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5

	local frame = UIKit.panel({
		Name = "CoinCounter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.98, 0, 0.12, 0),
		Size = UDim2.new(0, 180, 0, 42),
		ZIndex = 10,
		BackgroundTransparency = 0.05,
		Parent = gui,
	})
	UIKit.padding(frame, 0, 12)
	local layout = UIKit.list(frame, 10, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local glyph = coinGlyph(frame)
	glyph.LayoutOrder = 2
	glyph.ZIndex = 11
	coinLabel = UIKit.text({
		Name = "Amount",
		Text = "0",
		TextSize = 22,
		Font = T.FontHeavy,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -34, 1, 0),
		LayoutOrder = 1,
		ZIndex = 11,
		Parent = frame,
	})

	boostTag = UIKit.tag("+15% FRIEND BOOST", T.Primary, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.98, 0, 0.12, 48),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function refreshBoost()
	boostTag.Visible = player:GetAttribute("FriendBoost") == true
end

-- In-world toasts -----------------------------------------------------------------

local toastGui: BillboardGui? = nil
local toastCount = 0
local toastStack: Frame? = nil

local function toastAnchor(): BasePart?
	local ball = Hud.ball
	if ball and ball.Parent then
		return ball
	end
	local character = player.Character
	return character and character:FindFirstChild("Head") :: BasePart?
end

local function ensureToastGui(): Frame
	local anchor = toastAnchor()
	local gui = toastGui
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "Toasts"
		g.Size = UDim2.fromOffset(360, 150)
		g.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.ResetOnSpawn = false
		local stack = Instance.new("Frame")
		stack.BackgroundTransparency = 1
		stack.Size = UDim2.fromScale(1, 1)
		local l = UIKit.list(stack, 6, false, Enum.HorizontalAlignment.Center)
		l.VerticalAlignment = Enum.VerticalAlignment.Bottom
		stack.Parent = g
		g.Parent = player:WaitForChild("PlayerGui")
		toastGui = g
		toastStack = stack
		gui = g
	end
	(gui :: BillboardGui).Adornee = anchor :: any
	return toastStack :: Frame
end

function Hud.toast(text: string, color: Color3?)
	local stack = ensureToastGui()
	local items = {}
	for _, c in stack:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	if #items >= 3 then
		items[1]:Destroy()
	end
	toastCount += 1
	local card = UIKit.panel({
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 0.05,
		LayoutOrder = toastCount,
		Parent = stack,
	})
	UIKit.padding(card, 8, 12)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(360, 120)
	constraint.Parent = card
	local label = UIKit.text({
		Text = text,
		TextSize = 16,
		TextColor3 = color or T.Text,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = card,
	})
	local tc = Instance.new("UISizeConstraint")
	tc.MaxSize = Vector2.new(336, 110)
	tc.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = card
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(math.clamp(#text / 18, 2.6, 6), function()
		if card.Parent then
			TweenService:Create(card, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			task.wait(0.26)
			card:Destroy()
		end
	end)
end

Hud.ball = nil :: BasePart?

function Hud.start()
	buildCounter()
	State.CoinsChanged:Connect(function(coins: number, delta: number)
		setCoins(coins, delta ~= 0)
	end)
	if State.Profile then
		setCoins(State.Coins, false)
	end
	player:GetAttributeChangedSignal("FriendBoost"):Connect(refreshBoost)
	refreshBoost()
	Net.event("Toast").OnClientEvent:Connect(function(text: string, color: Color3?)
		Hud.toast(text, color)
	end)
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "shopResult" or kind == "creatorCode" then
			Hud.toast(payload.Text, if payload.Ok then T.Primary else T.Danger)
		end
	end)
end

return Hud

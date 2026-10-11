--!strict
--[[
	UIController
	Owns the single ScreenGui and its layers (Lobby, Hud, Modal, Overlay), switches between lobby
	and match screens, and shows server notices as toasts and banners. Toasts and the banner use
	fixed, pre-built frames that are recycled, so notifications never allocate new UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ClientState = require(script.Parent.Parent.ClientState)

export type LayerName = "Lobby" | "Hud" | "Modal" | "Overlay"

local TOAST_COUNT = 4
local TOAST_DURATION = 2.6
local BANNER_DURATION = 3.2
local TOAST_TOP = 0.13
local TOAST_HEIGHT = 0.05
local TOAST_GAP = 0.008

type Toast = {
	frame: Frame,
	label: TextLabel,
	stroke: UIStroke,
	hideThread: thread?,
}

local UIController = {}

local maid = Maid.new()
local layers: { [string]: Frame } = {}
local toasts: { Toast } = {}
local nextToast = 1
local banner: Frame
local bannerTitle: TextLabel
local bannerText: TextLabel
local bannerStroke: UIStroke
local bannerHideThread: thread? = nil
local celebrateFrame: Frame
local celebrateTitle: TextLabel
local celebrateText: TextLabel
local confetti: { Frame } = {}
local celebrateQueue: { { title: string, text: string } } = {}
local celebrating = false
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(96, 214, 255),
	Color3.fromRGB(255, 92, 170),
	Color3.fromRGB(86, 224, 146),
	Color3.fromRGB(176, 108, 255),
}

local function toneColor(tone: Types.NoticeTone): Color3
	if tone == "Success" then
		return Theme.Colors.Success
	elseif tone == "Error" then
		return Theme.Colors.Danger
	elseif tone == "Mutation" then
		return Theme.Military.Amber
	end
	return Theme.Colors.Primary
end

function UIController.getLayer(name: LayerName): Frame
	return layers[name]
end

function UIController.showToast(text: string, tone: Types.NoticeTone)
	local toast = toasts[nextToast]
	nextToast = nextToast % TOAST_COUNT + 1

	local hideThread = toast.hideThread
	if hideThread ~= nil and coroutine.status(hideThread) == "suspended" then
		task.cancel(hideThread)
	end

	-- Older toasts slide down a slot so the newest is always on top.
	for _, other in toasts do
		if other ~= toast and other.frame.Visible then
			local nextY = other.frame.Position.Y.Scale + TOAST_HEIGHT + TOAST_GAP
			UIKit.tween(other.frame, Theme.Tween.Fast, { Position = UDim2.fromScale(0.5, nextY) })
		end
	end

	local color = toneColor(tone)
	toast.label.Text = text
	toast.label.TextColor3 = color
	toast.stroke.Color = color
	toast.frame.Position = UDim2.fromScale(0.5, TOAST_TOP - TOAST_HEIGHT)
	toast.frame.BackgroundTransparency = 1
	toast.label.TextTransparency = 1
	toast.frame.Visible = true
	UIKit.tween(
		toast.frame,
		Theme.Tween.Normal,
		{ Position = UDim2.fromScale(0.5, TOAST_TOP), BackgroundTransparency = 0.1 }
	)
	UIKit.tween(toast.label, Theme.Tween.Normal, { TextTransparency = 0 })

	toast.hideThread = task.delay(TOAST_DURATION, function()
		UIKit.tween(toast.label, Theme.Tween.Normal, { TextTransparency = 1 })
		local fade = UIKit.tween(toast.frame, Theme.Tween.Normal, { BackgroundTransparency = 1 })
		fade.Completed:Wait()
		toast.frame.Visible = false
	end)
end

function UIController.showBanner(title: string, text: string, tone: Types.NoticeTone)
	if bannerHideThread ~= nil and coroutine.status(bannerHideThread) == "suspended" then
		task.cancel(bannerHideThread)
	end
	local color = toneColor(tone)
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerText.Text = text
	bannerStroke.Color = color
	banner.Size = UDim2.fromScale(0.42, 0)
	banner.Visible = true
	UIKit.tween(banner, Theme.Tween.Pop, { Size = UDim2.fromScale(0.42, 0.11) })

	bannerHideThread = task.delay(BANNER_DURATION, function()
		local shrink = UIKit.tween(banner, Theme.Tween.Normal, { Size = UDim2.fromScale(0.42, 0) })
		shrink.Completed:Wait()
		banner.Visible = false
	end)
end

local playNextCelebration: () -> ()

playNextCelebration = function()
	local entry = table.remove(celebrateQueue, 1)
	if entry == nil then
		celebrating = false
		return
	end
	celebrating = true
	celebrateTitle.Text = entry.title
	celebrateText.Text = entry.text
	celebrateFrame.Size = UDim2.fromScale(0.3, 0.12)
	celebrateFrame.Visible = true
	UIKit.tween(celebrateFrame, Theme.Tween.Pop, { Size = UDim2.fromScale(0.4, 0.2) })
	local random = Random.new()
	for _, piece in confetti do
		piece.Position = UDim2.fromScale(0.5, 0.5)
		piece.Rotation = 0
		piece.Visible = true
		local goal = UDim2.fromScale(random:NextNumber(-0.25, 1.25), random:NextNumber(-0.9, 1.9))
		UIKit.tween(piece, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = goal,
			Rotation = random:NextNumber(-360, 360),
		})
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/victory.wav"
	sound.Volume = 0.5
	SoundService:PlayLocalSound(sound)
	task.delay(3, function()
		sound:Destroy()
		for _, piece in confetti do
			piece.Visible = false
		end
		local shrink = UIKit.tween(celebrateFrame, Theme.Tween.Normal, { Size = UDim2.fromScale(0.3, 0) })
		shrink.Completed:Wait()
		celebrateFrame.Visible = false
		playNextCelebration()
	end)
end

-- Big centre-screen congratulations with confetti (pass tier, new troop, purchases).
function UIController.celebrate(title: string, text: string)
	table.insert(celebrateQueue, { title = title, text = text })
	if not celebrating then
		playNextCelebration()
	end
end

local function buildCelebrate(overlay: Frame)
	celebrateFrame = UIKit.frame({
		Name = "Celebrate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.4, 0.2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = overlay,
	})
	UIKit.corner(celebrateFrame, UDim.new(0, 22))
	UIKit.gradient(celebrateFrame, Theme.UI.WindowTop, Theme.UI.WindowBottom, 90)
	UIKit.stroke(celebrateFrame, Theme.UI.Gold, 3)
	celebrateTitle = UIKit.label({
		Size = UDim2.fromScale(0.92, 0.5),
		Position = UDim2.fromScale(0.04, 0.08),
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.UI.Gold,
		ZIndex = 41,
		Parent = celebrateFrame,
	}, 60)
	celebrateText = UIKit.label({
		Size = UDim2.fromScale(0.92, 0.28),
		Position = UDim2.fromScale(0.04, 0.62),
		Font = Theme.Fonts.Body,
		ZIndex = 41,
		Parent = celebrateFrame,
	}, 26)
	for index = 1, 28 do
		local piece = UIKit.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 16),
			BackgroundColor3 = CONFETTI_COLORS[(index % #CONFETTI_COLORS) + 1],
			Visible = false,
			ZIndex = 42,
			Parent = celebrateFrame,
		})
		table.insert(confetti, piece)
	end
end

-- Lobby and HUD are mutually exclusive; modals close when a match starts.
function UIController.setScreen(screen: "Lobby" | "Match")
	local inMatch = screen == "Match"
	layers.Lobby.Visible = not inMatch
	layers.Hud.Visible = inMatch
	if inMatch then
		for _, child in layers.Modal:GetChildren() do
			if child:IsA("GuiObject") then
				child.Visible = false
			end
		end
	end
end

local function buildToasts(overlay: Frame)
	for index = 1, TOAST_COUNT do
		local frame = UIKit.frame({
			Name = "Toast" .. index,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromScale(0.34, TOAST_HEIGHT),
			BackgroundColor3 = Theme.Colors.PanelDark,
			Visible = false,
			ZIndex = 20,
			Parent = overlay,
		})
		UIKit.corner(frame)
		local stroke = UIKit.stroke(frame, Theme.Colors.Primary)
		local label = UIKit.label({
			Size = UDim2.fromScale(0.94, 0.8),
			Position = UDim2.fromScale(0.03, 0.1),
			ZIndex = 21,
			Parent = frame,
		}, Theme.Text.BODY_MAX)
		table.insert(toasts, { frame = frame, label = label, stroke = stroke, hideThread = nil })
	end
end

local function buildBanner(overlay: Frame)
	banner = UIKit.frame({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.42, 0),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.08,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 30,
		Parent = overlay,
	})
	UIKit.corner(banner)
	bannerStroke = UIKit.stroke(banner, Theme.Colors.Primary, 3)
	bannerTitle = UIKit.label({
		Size = UDim2.fromScale(0.94, 0.55),
		Position = UDim2.fromScale(0.03, 0.06),
		Font = Theme.Fonts.Title,
		ZIndex = 31,
		Parent = banner,
	}, Theme.Text.TITLE_MAX)
	bannerText = UIKit.label({
		Size = UDim2.fromScale(0.94, 0.3),
		Position = UDim2.fromScale(0.03, 0.63),
		Font = Theme.Fonts.Light,
		TextColor3 = Theme.Colors.Text,
		ZIndex = 31,
		Parent = banner,
	}, Theme.Text.BODY_MAX)
end

local function onNotice(payload: Types.NoticePayload)
	local text = payload.text
	local code = payload.code
	if code ~= nil then
		text = Constants.NoticeText[code] or code
	end
	if payload.style == "Celebrate" then
		UIController.celebrate(payload.title or "", text or "")
	elseif payload.style == "Banner" then
		UIController.showBanner(payload.title or "", text or "", payload.tone)
	elseif text ~= nil then
		UIController.showToast(text, payload.tone)
	end
end

function UIController.init()
	local _, root = UIKit.screen("CyberSwarmUI", 10, maid)
	for index, name in { "Lobby", "Hud", "Modal", "Overlay" } do
		layers[name] = UIKit.frame({
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = index,
			Parent = root,
		})
	end
	layers.Hud.Visible = false

	buildToasts(layers.Overlay)
	buildBanner(layers.Overlay)
	buildCelebrate(layers.Overlay)

	maid:give(Remotes.Notify:connect(onNotice))
	maid:give(ClientState.matchChanged:connect(function()
		UIController.setScreen("Match")
	end))
	maid:give(ClientState.matchClosed:connect(function()
		UIController.setScreen("Lobby")
	end))
end

return UIController

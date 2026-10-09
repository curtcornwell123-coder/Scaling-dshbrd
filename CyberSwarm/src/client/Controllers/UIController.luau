--!strict
--[[
	UIController
	Owns the single ScreenGui and its layers (Lobby, Hud, Modal, Overlay), switches between lobby
	and match screens, and shows server notices as toasts and banners. Toasts and the banner use
	fixed, pre-built frames that are recycled, so notifications never allocate new UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local layers: { [LayerName]: Frame } = {}
local toasts: { Toast } = {}
local nextToast = 1
local banner: Frame
local bannerTitle: TextLabel
local bannerText: TextLabel
local bannerStroke: UIStroke
local bannerHideThread: thread? = nil

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
	UIKit.tween(toast.frame, Theme.Tween.Normal, { Position = UDim2.fromScale(0.5, TOAST_TOP), BackgroundTransparency = 0.1 })
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
	if payload.style == "Banner" then
		UIController.showBanner(payload.title or "", text or "", payload.tone)
	elseif text ~= nil then
		UIController.showToast(text, payload.tone)
	end
end

function UIController.init()
	local _, root = UIKit.screen("CyberSwarmUI", 10, maid)
	for index, name in { "Lobby", "Hud", "Modal", "Overlay" } :: { LayerName } do
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

	maid:give(Remotes.Notify:connect(onNotice))
	maid:give(ClientState.matchChanged:connect(function()
		UIController.setScreen("Match")
	end))
	maid:give(ClientState.matchClosed:connect(function()
		UIController.setScreen("Lobby")
	end))
end

return UIController

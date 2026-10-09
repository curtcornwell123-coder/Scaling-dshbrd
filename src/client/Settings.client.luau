--!strict
-- The settings panel: a small gear button in the corner (bottom right; top
-- right on phones and tablets). Inside:
--   * Music volume: a slider from 0% to 100% (Music.client reads it from
--     the player's "MusicVolume" attribute).
--   * VIP tag: VIPs can hide their crown and VIP tag.
-- Both are saved with the player's data, so they stick between visits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ChangeSetting = remotes:WaitForChild("ChangeSetting") :: RemoteEvent
local DataUpdated = remotes:WaitForChild("DataUpdated") :: RemoteEvent
local GetData = remotes:WaitForChild("GetData") :: RemoteFunction

local PANEL = Color3.fromRGB(25, 25, 35)
local ROW = Color3.fromRGB(40, 40, 55)
local ACCENT = Color3.fromRGB(120, 255, 160)
local OFF = Color3.fromRGB(90, 90, 105)

local volume = 1
local hideVip = false
local isVip = false
player:SetAttribute("MusicVolume", volume)

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function text(parent: Instance, value: string, position: UDim2, size: UDim2, xAlign: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.Text = value
	l.Parent = parent
	return l
end

local gui = Instance.new("ScreenGui")
gui.Name = "Settings"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

-- The gear button
local touch = UserInputService.TouchEnabled
local gear = Instance.new("TextButton")
gear.Name = "Gear"
gear.AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(1, 1)
gear.Position = if touch then UDim2.new(1, -12, 0, 8) else UDim2.new(1, -12, 1, -12)
gear.Size = UDim2.fromOffset(44, 44)
gear.BackgroundColor3 = PANEL
gear.BackgroundTransparency = 0.15
gear.Font = Enum.Font.FredokaOne
gear.TextScaled = true
gear.Text = "⚙️"
gear.TextColor3 = Color3.new(1, 1, 1)
gear.Parent = gui
round(gear, 12)
local gearStroke = Instance.new("UIStroke")
gearStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
gearStroke.Thickness = 2
gearStroke.Color = Color3.fromRGB(150, 150, 165)
gearStroke.Parent = gear
local gearPadding = Instance.new("UIPadding")
gearPadding.PaddingTop = UDim.new(0, 6)
gearPadding.PaddingBottom = UDim.new(0, 6)
gearPadding.Parent = gear

-- The panel, opening next to the gear
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = gear.AnchorPoint
panel.Position = if touch then UDim2.new(1, -12, 0, 60) else UDim2.new(1, -12, 1, -64)
panel.Size = UDim2.fromOffset(260, 150)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
round(panel, 14)
local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 2
panelStroke.Color = Color3.fromRGB(80, 80, 100)
panelStroke.Parent = panel
text(panel, "SETTINGS", UDim2.fromOffset(14, 8), UDim2.new(1, -60, 0, 24))
local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -8, 0, 8)
close.Size = UDim2.fromOffset(26, 26)
close.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
close.Font = Enum.Font.FredokaOne
close.TextScaled = true
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = panel
round(close, 8)

-- Music volume row: label + slider
local musicRow = Instance.new("Frame")
musicRow.Position = UDim2.fromOffset(10, 42)
musicRow.Size = UDim2.new(1, -20, 0, 48)
musicRow.BackgroundColor3 = ROW
musicRow.Parent = panel
round(musicRow, 10)
text(musicRow, "🎵 Music", UDim2.fromOffset(10, 4), UDim2.new(0.6, 0, 0, 18))
local percent = text(musicRow, "100%", UDim2.new(1, -60, 0, 4), UDim2.fromOffset(50, 18), Enum.TextXAlignment.Right)
local track = Instance.new("TextButton")
track.Name = "Track"
track.Text = ""
track.AutoButtonColor = false
track.Position = UDim2.fromOffset(12, 30)
track.Size = UDim2.new(1, -24, 0, 8)
track.BackgroundColor3 = OFF
track.Parent = musicRow
round(track, 4)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = ACCENT
fill.BorderSizePixel = 0
fill.Parent = track
round(fill, 4)
local knob = Instance.new("Frame")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.fromScale(1, 0.5)
knob.Size = UDim2.fromOffset(18, 18)
knob.BackgroundColor3 = Color3.new(1, 1, 1)
knob.Parent = track
round(knob, 9)

-- VIP tag row: label + ON/OFF switch
local vipRow = Instance.new("Frame")
vipRow.Position = UDim2.fromOffset(10, 96)
vipRow.Size = UDim2.new(1, -20, 0, 42)
vipRow.BackgroundColor3 = ROW
vipRow.Parent = panel
round(vipRow, 10)
local vipLabel = text(vipRow, "👑 VIP tag", UDim2.fromOffset(10, 10), UDim2.new(0.6, 0, 0, 22))
local vipSwitch = Instance.new("TextButton")
vipSwitch.AnchorPoint = Vector2.new(1, 0.5)
vipSwitch.Position = UDim2.new(1, -8, 0.5, 0)
vipSwitch.Size = UDim2.fromOffset(70, 28)
vipSwitch.Font = Enum.Font.FredokaOne
vipSwitch.TextScaled = true
vipSwitch.TextColor3 = Color3.new(1, 1, 1)
vipSwitch.Parent = vipRow
round(vipSwitch, 8)

local function refresh()
	percent.Text = string.format("%d%%", math.floor(volume * 100 + 0.5))
	fill.Size = UDim2.fromScale(volume, 1)
	knob.Position = UDim2.fromScale(volume, 0.5)
	if isVip then
		vipLabel.Text = "👑 VIP tag"
		vipSwitch.Text = if hideVip then "OFF" else "ON"
		vipSwitch.BackgroundColor3 = if hideVip then OFF else Color3.fromRGB(60, 170, 90)
		vipSwitch.AutoButtonColor = true
	else
		vipLabel.Text = "👑 VIP tag (VIP only)"
		vipSwitch.Text = "—"
		vipSwitch.BackgroundColor3 = OFF
		vipSwitch.AutoButtonColor = false
	end
end

local function setVolume(value: number)
	volume = math.clamp(value, 0, 1)
	player:SetAttribute("MusicVolume", volume)
	refresh()
end

-- Dragging the slider (mouse or finger). Saved once you let go.
local dragging = false
local function dragTo(x: number)
	local width = track.AbsoluteSize.X
	if width > 0 then
		setVolume((x - track.AbsolutePosition.X) / width)
	end
end
track.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragTo(input.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		dragTo(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		dragging = false
		ChangeSetting:FireServer("MusicVolume", volume)
	end
end)

vipSwitch.Activated:Connect(function()
	if not isVip then
		return
	end
	hideVip = not hideVip
	refresh()
	ChangeSetting:FireServer("HideVip", hideVip)
end)

gear.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
close.Activated:Connect(function()
	panel.Visible = false
end)

-- Saved settings come with the player's data.
local function apply(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	isVip = type(snapshot.Owns) == "table" and snapshot.Owns.VIP == true
	local settings = snapshot.Settings
	if type(settings) == "table" then
		hideVip = settings.HideVip == true
		if not dragging and type(settings.MusicVolume) == "number" then
			setVolume(settings.MusicVolume)
		end
	end
	refresh()
end
DataUpdated.OnClientEvent:Connect(apply)
refresh()
task.spawn(function()
	local ok, snapshot = pcall(function()
		return GetData:InvokeServer()
	end)
	if ok then
		apply(snapshot)
	end
end)

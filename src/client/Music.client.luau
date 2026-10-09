--!strict
-- Background music for normal play (Config.GameMusic). Loops the tracks
-- (shuffled if there are several), fades out while a founder event plays its
-- own theme song and back in after, and has a MUSIC ON/OFF button in the
-- bottom right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

if #Config.GameMusic == 0 then
	return -- no music set up yet
end

local player = Players.LocalPlayer

local sound = Instance.new("Sound")
sound.Name = "GameMusic"
sound.Volume = 0
sound.Looped = #Config.GameMusic == 1
sound.Parent = SoundService

local enabled = true
local order: { string } = table.clone(Config.GameMusic)
local position = 0

local function shuffle()
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
end
shuffle()

local function nextTrack()
	position += 1
	if position > #order then
		position = 1
		shuffle()
	end
	sound.SoundId = order[position]
	sound.TimePosition = 0
	sound:Play()
end

sound.Ended:Connect(function()
	if not sound.Looped then
		nextTrack()
	end
end)

-- Quiet while a founder event plays its own song.
local function eventMusicPlaying(): boolean
	local eventId = ReplicatedStorage:GetAttribute("FounderEvent") :: string? or ""
	local event = Config.FounderEvents[eventId]
	local custom = ReplicatedStorage:GetAttribute("EventMusic_" .. eventId) :: string?
	return event ~= nil and ((custom ~= nil and custom ~= "") or (event.MusicId ~= nil and event.MusicId ~= ""))
end

local function update()
	local target = if enabled and not eventMusicPlaying() then Config.GameMusicVolume else 0
	TweenService:Create(sound, TweenInfo.new(2), { Volume = target }):Play()
end

-- The MUSIC ON/OFF button
local gui = Instance.new("ScreenGui")
gui.Name = "MusicButton"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.new(1, -12, 1, -12)
-- Phones and tablets: top right, out of the way of the jump and sprint buttons.
if game:GetService("UserInputService").TouchEnabled then
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, 8)
end
button.Size = UDim2.fromOffset(140, 38)
button.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
button.BackgroundTransparency = 0.15
button.Font = Enum.Font.FredokaOne
button.TextScaled = true
button.TextColor3 = Color3.new(1, 1, 1)
button.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = button
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent = button
local stroke = Instance.new("UIStroke")
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Thickness = 2
stroke.Parent = button

local function refreshButton()
	button.Text = if enabled then "MUSIC: ON" else "MUSIC: OFF"
	stroke.Color = if enabled then Color3.fromRGB(120, 255, 160) else Color3.fromRGB(120, 120, 135)
end
button.MouseButton1Click:Connect(function()
	enabled = not enabled
	refreshButton()
	update()
end)
refreshButton()

ReplicatedStorage:GetAttributeChangedSignal("FounderEvent"):Connect(update)
nextTrack()
update()

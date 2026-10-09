--!strict
-- Background music for normal play (Config.GameMusic). Loops the tracks
-- (shuffled if there are several), fades out while a founder event plays its
-- own theme song and back in after. The volume is set in the settings panel.

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

-- The volume slider in the settings panel (Settings.client) sets the
-- player's "MusicVolume" attribute, from 0 to 1.
local function update(seconds: number?)
	local setting = (player:GetAttribute("MusicVolume") :: number?) or 1
	local target = if eventMusicPlaying() then 0 else Config.GameMusicVolume * setting
	TweenService:Create(sound, TweenInfo.new(seconds or 2), { Volume = target }):Play()
end

ReplicatedStorage:GetAttributeChangedSignal("FounderEvent"):Connect(function()
	update()
end)
player:GetAttributeChangedSignal("MusicVolume"):Connect(function()
	update(0.15)
end)
nextTrack()
update()

--!strict
--[[
	CameraController
	Switches to a fixed tactical view of the player's arena while in a match, and hands the camera
	back to the default character camera when the match closes. The view comes from the map
	(its Camera part, or a framing computed by MapService), so new maps need no camera code.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Maid = require(ReplicatedStorage.Shared.Util.Maid)
local ClientState = require(script.Parent.Parent.ClientState)

local CameraController = {}

local maid = Maid.new()
local matchMaid = Maid.new()
local activeMatchId: number? = nil
local targetCFrame: CFrame? = nil
local savedFieldOfView: number? = nil

local function applyMatchCamera(animate: boolean)
	local camera = workspace.CurrentCamera
	local goal = targetCFrame
	if camera == nil or goal == nil then
		return
	end
	if savedFieldOfView == nil then
		savedFieldOfView = camera.FieldOfView
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Constants.Camera.FIELD_OF_VIEW
	if animate then
		local info = TweenInfo.new(Constants.Camera.TWEEN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local tween = TweenService:Create(camera, info, { CFrame = goal })
		matchMaid:set("cameraTween", function()
			tween:Cancel()
		end)
		tween:Play()
	else
		camera.CFrame = goal
	end
end

local function onMatchChanged(snapshot: Types.MatchSnapshot)
	if activeMatchId == snapshot.matchId then
		return
	end
	activeMatchId = snapshot.matchId
	targetCFrame = snapshot.cameraCFrame
	matchMaid:cleanup()
	applyMatchCamera(true)

	-- Respawning resets the camera to follow the character; put the tactical view back.
	matchMaid:give(Players.LocalPlayer.CharacterAdded:Connect(function()
		task.defer(applyMatchCamera, false)
	end))
end

local function onMatchClosed()
	activeMatchId = nil
	targetCFrame = nil
	matchMaid:cleanup()

	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	if savedFieldOfView ~= nil then
		camera.FieldOfView = savedFieldOfView
		savedFieldOfView = nil
	end
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		camera.CameraSubject = humanoid
	end
end

function CameraController.init()
	maid:give(matchMaid)
	maid:give(ClientState.matchChanged:connect(onMatchChanged))
	maid:give(ClientState.matchClosed:connect(onMatchClosed))
end

return CameraController

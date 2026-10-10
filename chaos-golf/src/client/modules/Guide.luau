--!strict
-- First-join walking arrow: a solid arrow floats ahead of you pointing at the
-- direction sign in front of spawn, with glowing footprints along the way.
-- Reaching the sign clears it for good (profile.DirectoryDone).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Hud = require(script.Parent:WaitForChild("Hud"))

local Guide = {}

local T = UIKit.Theme
local player = Players.LocalPlayer

local target: Vector3? = nil
local arrow: Model? = nil
local dots: { Part } = {}
local beacon: BillboardGui? = nil
local claimed = false

local function clear()
	target = nil
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
	for _, d in dots do
		d:Destroy()
	end
	dots = {}
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
end

local function part(parent: Instance, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function build(at: Vector3)
	clear()
	target = at
	claimed = false
	local model = Instance.new("Model")
	model.Name = "GuideArrow"
	local shaft = part(model, Vector3.new(0.5, 0.5, 2.2), T.Primary)
	shaft.Name = "Shaft"
	local head = part(model, Vector3.new(1.3, 0.5, 1.3), T.Primary)
	head.Name = "Head"
	model.Parent = workspace.CurrentCamera
	arrow = model
	for i = 1, 8 do
		local d = part(workspace.CurrentCamera, Vector3.new(0.12, 0.9, 0.9), T.Primary, Enum.PartType.Cylinder)
		d.Material = Enum.Material.Neon
		d.Transparency = 0.35
		d.Name = "Step" .. i
		dots[i] = d
	end
	local anchor = part(workspace.CurrentCamera, Vector3.one * 0.2, T.Primary)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(at + Vector3.new(0, 4, 0))
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(170, 40)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Adornee = anchor
	local tag = UIKit.panel({ Size = UDim2.fromScale(1, 1), Parent = g })
	UIKit.text({ Text = "START HERE", TextSize = 18, TextColor3 = T.Primary, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = tag })
	g.Parent = player:WaitForChild("PlayerGui")
	beacon = g
	Hud.toast("Follow the arrow to the direction sign!", T.Primary)
end

function Guide.start()
	Net.event("Guide").OnClientEvent:Connect(function(at: Vector3?)
		if at then
			build(at)
		else
			clear()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local goal = target
		local model = arrow
		if not goal or not model then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local from = root.Position
		local flat = Vector3.new(goal.X - from.X, 0, goal.Z - from.Z)
		local dist = flat.Magnitude
		if dist < 6 then
			if not claimed then
				claimed = true
				Net.event("ClaimDirectory"):FireServer()
				Hud.toast("Matchmaking is behind you, Shop to your left, Leaderboards to your right, Practice ahead.", T.Text)
			end
			clear()
			return
		end
		local dir = flat.Unit
		local bob = math.sin(os.clock() * 4) * 0.25
		local base = CFrame.lookAt(from + dir * 4 + Vector3.new(0, 1.2 + bob, 0), from + dir * 5 + Vector3.new(0, 1.2 + bob, 0))
		local shaft = model:FindFirstChild("Shaft") :: BasePart
		local head = model:FindFirstChild("Head") :: BasePart
		shaft.CFrame = base * CFrame.new(0, 0, 0.4)
		head.CFrame = base * CFrame.new(0, 0, -1) * CFrame.Angles(0, math.rad(45), 0)
		local floorY = from.Y - 2.9
		for i, d in dots do
			local t = i / (#dots + 1)
			local p = from:Lerp(goal, t)
			d.CFrame = CFrame.new(p.X, floorY, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
			d.Transparency = 0.25 + 0.5 * ((os.clock() * 1.5 - t) % 1)
		end
	end)
end

return Guide

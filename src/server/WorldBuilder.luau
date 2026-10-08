--!strict
-- Builds the lobby: floor, spawn and one glowing crate per crate tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldBuilder = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function ensureFloor()
	if Workspace:FindFirstChild("Baseplate") or Workspace:FindFirstChild("CrateRushFloor") then
		return
	end
	part({
		Name = "CrateRushFloor",
		Size = Vector3.new(256, 4, 256),
		Position = Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(45, 48, 60),
		Material = Enum.Material.SmoothPlastic,
		Parent = Workspace,
	})
end

local function ensureSpawn()
	for _, child in Workspace:GetDescendants() do
		if child:IsA("SpawnLocation") then
			return
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, 30)
	spawn.Color = Color3.fromRGB(230, 230, 240)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Parent = Workspace
end

local function buildCrate(crate: Config.Crate, origin: CFrame, onOpen: (Player, string) -> ()): Model
	local model = Instance.new("Model")
	model.Name = crate.Id .. "Crate"

	local size = 7
	local body = part({
		Name = "Body",
		Size = Vector3.new(size, size, size),
		CFrame = origin * CFrame.new(0, size / 2 + 1, 0),
		Color = crate.Color,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	model.PrimaryPart = body

	-- Glowing edges
	local edge = 0.6
	local half = size / 2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part({
				Name = "Edge",
				Size = Vector3.new(edge, size + edge, edge),
				CFrame = body.CFrame * CFrame.new(x * half, 0, z * half),
				Color = crate.Color:Lerp(Color3.new(1, 1, 1), 0.35),
				Material = Enum.Material.Neon,
				Parent = model,
			})
		end
	end
	for _, y in { -1, 1 } do
		for _, axis in { "X", "Z" } do
			for _, side in { -1, 1 } do
				local offset = axis == "X" and Vector3.new(0, y * half, side * half)
					or Vector3.new(side * half, y * half, 0)
				local barSize = axis == "X" and Vector3.new(size, edge, edge) or Vector3.new(edge, edge, size)
				part({
					Name = "Edge",
					Size = barSize,
					CFrame = body.CFrame * CFrame.new(offset),
					Color = crate.Color:Lerp(Color3.new(1, 1, 1), 0.35),
					Material = Enum.Material.Neon,
					Parent = model,
				})
			end
		end
	end

	-- Pedestal
	part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, size + 4, size + 4),
		CFrame = origin * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(30, 30, 38),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local light = Instance.new("PointLight")
	light.Color = crate.Color
	light.Range = 18
	light.Brightness = 2
	light.Parent = body

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(crate.Color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.3, 0)
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Rate = 6
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = body

	-- Label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 90)
	billboard.StudsOffset = Vector3.new(0, size / 2 + 3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = body

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = crate.Color
	title.TextStrokeTransparency = 0
	title.Text = crate.DisplayName
	title.Parent = billboard

	local price = Instance.new("TextLabel")
	price.BackgroundTransparency = 1
	price.Position = UDim2.fromScale(0, 0.55)
	price.Size = UDim2.new(1, 0, 0.45, 0)
	price.Font = Enum.Font.FredokaOne
	price.TextScaled = true
	price.TextColor3 = Color3.fromRGB(255, 230, 120)
	price.TextStrokeTransparency = 0
	price.Text = "💰 " .. Config.FormatNumber(crate.Price)
	price.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = crate.DisplayName .. " (" .. Config.FormatNumber(crate.Price) .. ")"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		onOpen(player, crate.Id)
	end)

	model:SetAttribute("CrateId", crate.Id)
	return model
end

function WorldBuilder.Build(onOpen: (Player, string) -> ())
	ensureFloor()
	ensureSpawn()

	local folder = Instance.new("Folder")
	folder.Name = "Crates"

	local count = #Config.Crates
	local spacing = 16
	local startX = -spacing * (count - 1) / 2
	for i, crate in Config.Crates do
		local origin = CFrame.new(startX + (i - 1) * spacing, 0, 0)
		buildCrate(crate, origin, onOpen).Parent = folder
	end

	folder.Parent = Workspace
end

return WorldBuilder

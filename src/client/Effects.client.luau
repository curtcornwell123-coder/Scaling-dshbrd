--!strict
-- Purely visual, client-side: brainrots in bases bob and sway, and Rainbow
-- mutations cycle through colors. The server never sees these moves.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local plots = workspace:WaitForChild("BrainrotHeist"):WaitForChild("Plots")

local function phaseOf(model: Model): number
	local slot = model:GetAttribute("Slot")
	local plotIndex = model:GetAttribute("PlotIndex")
	return ((if type(slot) == "number" then slot else 0) * 1.7) + ((if type(plotIndex) == "number" then plotIndex else 0) * 0.9)
end

local rainbowTimer = 0

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()

	-- Idle bob for brainrots sitting on pedestals.
	for _, plot in plots:GetChildren() do
		for _, model in plot:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("Slot") and not model:GetAttribute("Carried") then
				local root = model.PrimaryPart
				-- Upper-floor pedestals live inside Story folders, so search deep.
				local pedestal = plot:FindFirstChild("Pedestal" .. tostring(model:GetAttribute("Slot")), true)
				if root and pedestal and pedestal:IsA("BasePart") then
					local phase = phaseOf(model)
					local base = pedestal.CFrame * CFrame.new(0, 1, 0)
					root.CFrame = base
						* CFrame.new(0, 0.2 + math.sin(t * 2.2 + phase) * 0.2, 0)
						* CFrame.Angles(0, math.sin(t * 1.3 + phase) * 0.18, math.sin(t * 2.2 + phase) * 0.04)
				end
			end
		end
	end

	-- Spinning showpieces (the Diamond Shop's giant diamond).
	for _, part in CollectionService:GetTagged("Spinner") do
		local center = part:GetAttribute("SpinCenter")
		if part:IsA("BasePart") and typeof(center) == "CFrame" then
			local speed = part:GetAttribute("SpinSpeed")
			part.CFrame = CFrame.new(center.Position + Vector3.new(0, math.sin(t * 1.5) * 0.6, 0))
				* CFrame.Angles(0, t * (if type(speed) == "number" then speed else 1.2), 0)
				* center.Rotation
		end
	end

	-- Magic mutation: a soft shimmer between purple and teal over its own colors.
	local magicTint = Color3.fromRGB(170, 110, 255):Lerp(Color3.fromRGB(90, 220, 255), (math.sin(t * 1.2) + 1) / 2)
	for _, model in CollectionService:GetTagged("MagicBrainrot") do
		for _, part in model:GetDescendants() do
			local base = part:GetAttribute("BaseColor")
			if part:IsA("BasePart") and typeof(base) == "Color3" then
				part.Color = base:Lerp(magicTint, 0.35)
			end
		end
	end

	-- Rainbow mutation: shift every part's hue, ~20 times a second.
	rainbowTimer += dt
	if rainbowTimer >= 0.05 then
		rainbowTimer = 0
		for _, model in CollectionService:GetTagged("RainbowBrainrot") do
			local i = 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "Root" and not part:GetAttribute("Keep") then
					i += 1
					part.Color = Color3.fromHSV((t * 0.25 + i * 0.09) % 1, 0.75, 1)
				end
			end
		end
	end
end)

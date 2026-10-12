--!strict
-- Tended flagsticks. Every cup has its pin standing in the middle of the hole; when a ball
-- comes up to it the pin is lifted just clear of the cup - as a caddie pulls it - and set
-- back once the green is clear. Animated here on every client (smooth, local) from the
-- replicated ball positions; the server only builds the pins (tag "CupFlag", attributes
-- Cup = rim centre, Lift = studs).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CupFlags = {}

local NEAR = 9 -- a ball this close to the cup (and level with it) gets the pin pulled
local HOLD = 1.5 -- seconds the pin stays up after the last ball leaves
local RATE = 5 -- easing speed

type Flag = { Model: Model, Parts: { [BasePart]: CFrame }, Cup: Vector3, Lift: number, Up: number, HoldUntil: number }
local flags: { [Model]: Flag } = {}

local function track(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local cup = inst:GetAttribute("Cup")
	local lift = inst:GetAttribute("Lift")
	if typeof(cup) ~= "Vector3" then
		return
	end
	local parts: { [BasePart]: CFrame } = {}
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			parts[d] = d.CFrame
		end
	end
	flags[inst] = {
		Model = inst,
		Parts = parts,
		Cup = cup,
		Lift = if type(lift) == "number" then lift else 2.4,
		Up = 0,
		HoldUntil = 0,
	}
end

local function ballNear(balls: Instance?, cup: Vector3): boolean
	if not balls then
		return false
	end
	for _, b in balls:GetChildren() do
		if b:IsA("BasePart") and b.Transparency < 1 then
			local d = b.Position - cup
			if math.abs(d.Y) < 4 and d.X * d.X + d.Z * d.Z < NEAR * NEAR then
				return true
			end
		end
	end
	return false
end

-- How far a pin is lifted right now (0 = standing in the cup).
function CupFlags.liftOf(model: Model): number
	local f = flags[model]
	return if f then f.Up else 0
end

function CupFlags.start()
	for _, m in CollectionService:GetTagged("CupFlag") do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal("CupFlag"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("CupFlag"):Connect(function(m)
		if m:IsA("Model") then
			flags[m] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local balls = workspace:FindFirstChild("GolfBalls")
		local now = os.clock()
		for m, f in flags do
			if not m.Parent then
				flags[m] = nil
				continue
			end
			if ballNear(balls, f.Cup) then
				f.HoldUntil = now + HOLD
			end
			local target = if now < f.HoldUntil then f.Lift else 0
			if f.Up ~= target then
				f.Up += (target - f.Up) * math.min(1, dt * RATE)
				if math.abs(target - f.Up) < 0.003 then
					f.Up = target
				end
				local lift = Vector3.new(0, f.Up, 0)
				for part, base in f.Parts do
					part.CFrame = base + lift
				end
			end
		end
	end)
end

return CupFlags

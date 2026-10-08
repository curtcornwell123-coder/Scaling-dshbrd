--!strict
-- The big admin abuse show. The moment admin abuse starts (the weekly one or
-- one an admin starts by hand), every player gets a full-screen intro:
-- flashes, spinning light rays, a giant rainbow "ADMIN ABUSE!" title, the
-- boosts popping in, falling confetti, a camera shake and fireworks over the
-- map. While it's live the lighting gently cycles party colors and fireworks
-- keep going off. Founder events (Corny's, Ace's...) get their own intro.
-- Purely visual and client-side; the giants themselves are built by the server.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Announce = Remotes:WaitForChild("Announce") :: RemoteEvent

local player = Players.LocalPlayer
local RED = Color3.fromRGB(255, 60, 60)
local GOLD = Color3.fromRGB(255, 205, 60)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local gui = Instance.new("ScreenGui")
gui.Name = "AdminAbuseShow"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function rainbow(offset: number): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6 + offset) % 1, 0.8, 1)))
	end
	return ColorSequence.new(keys)
end

-- The admin who started it (sent with the "abuse" announcement).
local startedBy: string? = nil
local introPlaying = false
local showGift: (string, string?, number, number) -> ()
local showAnnouncement: (string, string) -> ()
Announce.OnClientEvent:Connect(function(kind: string, who: string, brainrotId: string, extra: string?, mutationId: string?)
	if kind == "abuse" then
		startedBy = who
	elseif kind == "global" then
		task.spawn(showAnnouncement, who, extra or "")
	elseif kind == "abusegift" then
		local diamonds, shards = string.match(extra or "", "^(%d+),(%d+)$")
		task.spawn(showGift, brainrotId, mutationId, tonumber(diamonds) or 0, tonumber(shards) or 0)
	end
end)

-- Fireworks ----------------------------------------------------------------

local fireworksFolder = Instance.new("Folder")
fireworksFolder.Name = "AbuseFireworks"
fireworksFolder.Parent = workspace

-- One firework: a glowing rocket shoots up and bursts into colored sparks.
local function firework(center: Vector3)
	local hue = math.random()
	local color = Color3.fromHSV(hue, 0.85, 1)
	local from = center + Vector3.new(math.random(-70, 70), 0, math.random(-70, 70))
	local to = from + Vector3.new(math.random(-8, 8), math.random(55, 85), math.random(-8, 8))

	local rocket = Instance.new("Part")
	rocket.Name = "Rocket"
	rocket.Shape = Enum.PartType.Ball
	rocket.Size = Vector3.new(1.2, 1.2, 1.2)
	rocket.Material = Enum.Material.Neon
	rocket.Color = color
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CanTouch = false
	rocket.CastShadow = false
	rocket.Position = from
	rocket.Parent = fireworksFolder

	local trail = Instance.new("ParticleEmitter")
	trail.Texture = SPARKLE
	trail.Color = ColorSequence.new(color, GOLD)
	trail.LightEmission = 1
	trail.Rate = 80
	trail.Lifetime = NumberRange.new(0.3, 0.6)
	trail.Speed = NumberRange.new(1, 3)
	trail.SpreadAngle = Vector2.new(25, 25)
	trail.EmissionDirection = Enum.NormalId.Bottom
	trail.Size = NumberSequence.new(0.6, 0)
	trail.Parent = rocket

	local rise = tween(rocket, 0.9, { Position = to }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	rise.Completed:Connect(function()
		trail.Enabled = false
		rocket.Transparency = 1
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = SPARKLE
		burst.Color = ColorSequence.new(color, Color3.fromHSV((hue + 0.15) % 1, 0.6, 1))
		burst.LightEmission = 1
		burst.Rate = 0
		burst.Lifetime = NumberRange.new(1.4, 2.2)
		burst.Speed = NumberRange.new(28, 42)
		burst.Drag = 2.5
		burst.Acceleration = Vector3.new(0, -12, 0)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) })
		burst.Parent = rocket
		burst:Emit(90)
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 60
		flash.Brightness = 6
		flash.Parent = rocket
		tween(flash, 1, { Brightness = 0 })
		task.delay(3, function()
			rocket:Destroy()
		end)
	end)
end

local function fireworksAroundMe(count: number, spread: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if root then Vector3.new(root.Position.X, 0, root.Position.Z) else Vector3.zero
	for _ = 1, count do
		task.spawn(firework, center)
		task.wait(spread)
	end
end

-- Camera shake --------------------------------------------------------------

local function shake(seconds: number, strength: number)
	local camera = workspace.CurrentCamera
	local ends = os.clock() + seconds
	RunService:BindToRenderStep("AdminAbuseShake", Enum.RenderPriority.Camera.Value + 1, function()
		local left = ends - os.clock()
		if left <= 0 then
			RunService:UnbindFromRenderStep("AdminAbuseShake")
			return
		end
		local power = strength * (left / seconds)
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * power), math.rad((math.random() - 0.5) * power), math.rad((math.random() - 0.5) * power * 0.5))
	end)
end

-- Confetti ------------------------------------------------------------------

local function confetti(count: number, seconds: number)
	local layer = Instance.new("Frame")
	layer.Name = "Confetti"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 5
	layer.Parent = gui
	type Piece = { Frame: Frame, X: number, Y: number, VX: number, VY: number, Spin: number, Sway: number }
	local pieces: { Piece } = {}
	for _ = 1, count do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.fromHSV(math.random(), 0.8, 1)
		frame.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.ZIndex = 5
		frame.Parent = layer
		table.insert(pieces, {
			Frame = frame,
			X = math.random(),
			Y = -math.random() * 0.6 - 0.05,
			VX = (math.random() - 0.5) * 0.08,
			VY = 0.25 + math.random() * 0.3,
			Spin = (math.random() - 0.5) * 720,
			Sway = math.random() * 6,
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		for _, p in pieces do
			p.X += (p.VX + math.sin(t * 3 + p.Sway) * 0.05) * dt
			p.Y += p.VY * dt
			p.Frame.Position = UDim2.fromScale(p.X, p.Y)
			p.Frame.Rotation += p.Spin * dt
		end
		if t > seconds - 1 then
			for _, p in pieces do
				p.Frame.BackgroundTransparency = math.clamp(t - (seconds - 1), 0, 1)
			end
		end
		if t > seconds then
			connection:Disconnect()
			layer:Destroy()
		end
	end)
end

-- Rainbow sky (Corny's event) ------------------------------------------------
-- A glowing neon sky around the whole map: a ring of tall panels around the
-- horizon in rainbow colors that slowly turn through the spectrum, and a
-- neon ceiling overhead cycling through the colors. It's only on this
-- player's screen, centered on the map and big enough to fit the giant
-- founder (players can't get past the fence, so they never reach it).
-- Everything is put back when the event ends.

local SKY_RADIUS = 1400
local SKY_PANELS = 64
local SKY_BOTTOM = -200
local SKY_TOP = 1200
local SKY_TRANSPARENCY = 0.2

type SkyState = { Model: Model, Panels: { BasePart }, Ceiling: { BasePart }, Saved: { [string]: any }?, Connection: RBXScriptConnection }
local rainbowSky: SkyState? = nil

local function skyPart(model: Model, size: Vector3, cframe: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Size = size
	p.CFrame = cframe
	p.Parent = model
	return p
end

-- `style`: "Green" (Corny's: neon greens drifting between lime and mint),
-- "Pink" (Ace's: soft pinks drifting between rose and lilac) or "Rainbow".
local SKY_TINTS = {
	Green = { Hue = 0.33, Spread = 0.07, Saturation = 0.7 },
	Pink = { Hue = 0.9, Spread = 0.055, Saturation = 0.5 },
}
-- `night`: darker and more see-through, so the night sky shows through a
-- dim glow instead of a bright wall of color.
local function startRainbowSky(style: string, night: boolean?)
	if rainbowSky then
		return
	end
	local tint = SKY_TINTS[style]
	local model = Instance.new("Model")
	model.Name = "RainbowSky"
	local panels: { BasePart } = {}
	local width = 2 * math.pi * SKY_RADIUS / SKY_PANELS + 4
	local height = SKY_TOP - SKY_BOTTOM
	for i = 1, SKY_PANELS do
		local angle = (i / SKY_PANELS) * math.pi * 2
		local position = Vector3.new(math.cos(angle) * SKY_RADIUS, SKY_BOTTOM + height / 2, math.sin(angle) * SKY_RADIUS)
		table.insert(panels, skyPart(model, Vector3.new(width, height, 2), CFrame.lookAt(position, Vector3.new(0, position.Y, 0))))
	end
	-- Parts max out at 2048 studs, so the ceiling is four tiles.
	local ceiling: { BasePart } = {}
	for _, x in { -1024, 1024 } do
		for _, z in { -1024, 1024 } do
			table.insert(ceiling, skyPart(model, Vector3.new(2048, 2, 2048), CFrame.new(x, SKY_TOP, z)))
		end
	end
	model.Parent = workspace

	-- Thin out the haze so the neon colors stay bright and clear.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local saved: { [string]: any }? = nil
	if atmosphere then
		saved = { Density = atmosphere.Density, Haze = atmosphere.Haze, Glare = atmosphere.Glare }
		tween(atmosphere, 2, { Density = 0.12, Haze = 0, Glare = 0 })
	end
	for _, p in panels do
		tween(p, 2, { Transparency = if night then 0.55 else SKY_TRANSPARENCY })
	end
	for _, tile in ceiling do
		tween(tile, 2, { Transparency = if night then 0.7 else SKY_TRANSPARENCY })
	end

	local started = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		for i, p in panels do
			if tint then
				local wave = math.sin(i / SKY_PANELS * math.pi * 4 + t * 0.4)
				p.Color = Color3.fromHSV((tint.Hue + tint.Spread * wave) % 1, tint.Saturation + 0.12 * wave, if night then 0.45 + 0.1 * wave else 1)
			else
				-- The rainbow goes twice around the horizon (so you always see
				-- lots of colors), slowly turning.
				p.Color = Color3.fromHSV((i / SKY_PANELS * 2 + t * 0.05) % 1, 0.75, 0.95)
			end
		end
		local top = if tint
			then Color3.fromHSV((tint.Hue + tint.Spread * 0.7 * math.sin(t * 0.3)) % 1, tint.Saturation - 0.1, if night then 0.25 else 1)
			else Color3.fromHSV((t * 0.05) % 1, 0.6, 0.9)
		for _, tile in ceiling do
			tile.Color = top
		end
	end)
	rainbowSky = { Model = model, Panels = panels, Ceiling = ceiling, Saved = saved, Connection = connection }
end

local function stopRainbowSky()
	local state = rainbowSky
	rainbowSky = nil
	if not state then
		return
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and state.Saved then
		tween(atmosphere, 2, state.Saved)
	end
	for _, p in state.Panels do
		tween(p, 2, { Transparency = 1 })
	end
	for _, tile in state.Ceiling do
		tween(tile, 2, { Transparency = 1 })
	end
	task.delay(2.2, function()
		state.Connection:Disconnect()
		state.Model:Destroy()
	end)
end

-- Ballet scene (Ace's event) -------------------------------------------------
-- Knee-deep water flows out over the map, lily pads (some with pink
-- flowers) drop into it and bob, pink sparkly dust drifts everywhere, and the
-- theme song plays. All on this player's screen; put back when it ends.

local WATER_TOP = 2.2 -- about knee height
local WATER_RADIUS = 440 -- just past the fence

type BalletState = { Water: BasePart, Pads: { Model }, Dust: BasePart, Connection: RBXScriptConnection, Running: boolean }
local ballet: BalletState? = nil

local function lilyPad(parent: Instance, rng: Random): Model
	local pad = Instance.new("Model")
	pad.Name = "LilyPad"
	local width = rng:NextNumber(6, 11)
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Shape = Enum.PartType.Cylinder
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CanQuery = false
	leaf.CanTouch = false
	leaf.Size = Vector3.new(0.25, width, width)
	leaf.Color = Color3.fromRGB(70, 165, 75):Lerp(Color3.fromRGB(120, 200, 90), rng:NextNumber())
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	leaf.Parent = pad
	-- The pad's pivot is a level point at its center (not the leaf itself,
	-- which is a cylinder turned on its side to lie flat). Moving the pad
	-- with an upright CFrame then keeps the leaf lying perfectly flat.
	pad.WorldPivot = CFrame.identity
	-- A soft glowing aura ring around the leaf, with a few sparkles rising off it
	local aura = Instance.new("Part")
	aura.Name = "Aura"
	aura.Shape = Enum.PartType.Cylinder
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false
	aura.CastShadow = false
	aura.Size = Vector3.new(0.12, width * 1.35, width * 1.35)
	aura.Color = Color3.fromRGB(255, 170, 225)
	aura.Material = Enum.Material.Neon
	aura.Transparency = 0.65
	aura.CFrame = CFrame.new(0, -0.08, 0) * CFrame.Angles(0, 0, math.pi / 2)
	aura.Parent = pad
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = SPARKLE
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 190, 235), Color3.new(1, 1, 1))
	glow.LightEmission = 1
	glow.Rate = 4
	glow.Lifetime = NumberRange.new(1, 2)
	glow.Speed = NumberRange.new(1, 2.5)
	glow.EmissionDirection = Enum.NormalId.Right -- the leaf is turned on its side, so "Right" is up
	glow.SpreadAngle = Vector2.new(25, 25)
	glow.Size = NumberSequence.new(0.5, 0)
	glow.Parent = leaf
	if rng:NextNumber() < 0.4 then
		-- A pink water lily: petals around a yellow middle
		local function bit(size: Vector3, offset: Vector3, color: Color3)
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Size = size
			p.Color = color
			p.Material = Enum.Material.SmoothPlastic
			p.CFrame = CFrame.new(offset)
			p.Parent = pad
		end
		for k = 1, 6 do
			local a = k / 6 * math.pi * 2
			bit(Vector3.new(1.4, 1.4, 1.4), Vector3.new(math.cos(a) * 0.9, 0.5, math.sin(a) * 0.9), Color3.fromRGB(255, 150, 205))
		end
		bit(Vector3.new(1, 1, 1), Vector3.new(0, 0.7, 0), Color3.fromRGB(255, 230, 110))
	end
	pad.Parent = parent
	return pad
end

local function startBallet(event: Config.FounderEvent)
	if ballet then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "BalletScene"
	folder.Parent = workspace

	-- The water flows out from the middle and rises to knee height.
	local water = Instance.new("Part")
	water.Name = "BalletWater"
	water.Shape = Enum.PartType.Cylinder
	water.Anchored = true
	water.CanCollide = false
	water.CanQuery = false
	water.CanTouch = false
	water.CastShadow = false
	water.Material = Enum.Material.SmoothPlastic
	water.Color = Color3.fromRGB(150, 205, 255)
	water.Transparency = 0.42
	water.Reflectance = 0.25
	water.Size = Vector3.new(3, 120, 120)
	water.CFrame = CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.pi / 2)
	water.Parent = folder
	tween(water, 6, { Size = Vector3.new(3, WATER_RADIUS * 2, WATER_RADIUS * 2), CFrame = CFrame.new(0, WATER_TOP - 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2) }, Enum.EasingStyle.Sine)

	-- Pink sparkly dust and soft puffs all around the camera.
	local dust = Instance.new("Part")
	dust.Name = "BalletDust"
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.Transparency = 1
	dust.Size = Vector3.new(180, 70, 180)
	dust.Parent = folder
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = SPARKLE
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 160, 220), Color3.fromRGB(255, 225, 245))
	sparkle.LightEmission = 0.8
	sparkle.Rate = 90
	sparkle.Lifetime = NumberRange.new(3, 5)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Shape = Enum.ParticleEmitterShape.Box
	sparkle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = dust
	local puffs = Instance.new("ParticleEmitter")
	puffs.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puffs.Color = ColorSequence.new(Color3.fromRGB(255, 180, 225))
	puffs.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.6), NumberSequenceKeypoint.new(1, 1) })
	puffs.LightEmission = 0.4
	puffs.Rate = 14
	puffs.Lifetime = NumberRange.new(4, 6)
	puffs.Speed = NumberRange.new(0.5, 1.5)
	puffs.SpreadAngle = Vector2.new(180, 180)
	puffs.Shape = Enum.ParticleEmitterShape.Box
	puffs.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	puffs.Size = NumberSequence.new(1.5, 3)
	puffs.Parent = dust

	local pads: { Model } = {}
	local padPhase: { [Model]: number } = {}
	local state: BalletState
	local connection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		dust.CFrame = CFrame.new(camera.CFrame.Position)
		local t = os.clock()
		for _, pad in pads do
			local phase = padPhase[pad]
			if phase and pad:GetAttribute("Floating") then
				local base = pad:GetAttribute("Base") :: Vector3
				pad:PivotTo(CFrame.new(base + Vector3.new(0, math.sin(t * 1.3 + phase) * 0.15, 0)) * CFrame.Angles(0, phase + math.sin(t * 0.3 + phase) * 0.2, 0))
			end
		end
	end)
	state = { Water = water, Pads = pads, Dust = dust, Connection = connection, Running = true }
	ballet = state

	-- Lily pads drop in over the first half minute.
	task.spawn(function()
		local rng = Random.new()
		task.wait(3)
		for _ = 1, 70 do
			if not state.Running then
				break
			end
			local pad = lilyPad(folder, rng)
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = math.sqrt(rng:NextNumber()) * (WATER_RADIUS - 30)
			local landing = Vector3.new(math.cos(angle) * distance, WATER_TOP + 0.1, math.sin(angle) * distance)
			local phase = rng:NextNumber(0, math.pi * 2)
			-- Flat the whole way down
			pad:PivotTo(CFrame.new(landing + Vector3.new(0, rng:NextNumber(80, 140), 0)) * CFrame.Angles(0, phase, 0))
			table.insert(pads, pad)
			padPhase[pad] = phase
			-- Drop straight down, staying flat, then float
			task.spawn(function()
				local from = pad:GetPivot()
				local to = CFrame.new(landing) * CFrame.Angles(0, phase, 0)
				local started = os.clock()
				while pad.Parent do
					local k = math.min((os.clock() - started) / 2.5, 1)
					local eased = k * k
					pad:PivotTo(from:Lerp(to, eased))
					if k >= 1 then
						break
					end
					RunService.RenderStepped:Wait()
				end
				pad:SetAttribute("Base", landing)
				pad:SetAttribute("Floating", true)
			end)
			task.wait(rng:NextNumber(0.2, 0.5))
		end
	end)
end

local function stopBallet()
	local state = ballet
	ballet = nil
	if not state then
		return
	end
	state.Running = false
	for _, emitter in state.Dust:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = false
		end
	end
	tween(state.Water, 4, { Size = Vector3.new(3, 120, 120), CFrame = CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Transparency = 1 }, Enum.EasingStyle.Sine)
	for _, pad in state.Pads do
		pad:SetAttribute("Floating", false)
		for _, part in pad:GetDescendants() do
			if part:IsA("BasePart") then
				tween(part, 3, { Transparency = 1 })
			elseif part:IsA("ParticleEmitter") then
				part.Enabled = false
			end
		end
	end
	task.delay(4.2, function()
		state.Connection:Disconnect()
		local folder = state.Water.Parent
		if folder then
			folder:Destroy()
		end
	end)
end

-- Alien chaos (Corny's event) -------------------------------------------------
-- Green searchlights sweeping the map from all around it, green lights
-- pulsing (slowly, never a fast strobe), little UFOs zipping across the sky
-- and green abduction beams zapping random spots. All on this player's
-- screen; removed when the event ends.

local GREEN = Color3.fromRGB(90, 255, 120)

type ChaosState = { Folder: Folder, Connection: RBXScriptConnection, Running: boolean }
local chaos: ChaosState? = nil

local function chaosPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material, transparency: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.Parent = parent
	return p
end

local function miniUfo(parent: Instance): Model
	local ufo = Instance.new("Model")
	ufo.Name = "MiniUFO"
	local hull = chaosPart(ufo, Vector3.new(26, 5, 26), Color3.fromRGB(175, 180, 195), Enum.Material.Metal, 0)
	local hullMesh = Instance.new("SpecialMesh")
	hullMesh.MeshType = Enum.MeshType.Sphere
	hullMesh.Parent = hull
	local dome = chaosPart(ufo, Vector3.new(10, 8, 10), Color3.fromRGB(140, 255, 170), Enum.Material.Glass, 0.3)
	dome.CFrame = CFrame.new(0, 2.5, 0)
	local domeMesh = Instance.new("SpecialMesh")
	domeMesh.MeshType = Enum.MeshType.Sphere
	domeMesh.Parent = dome
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local light = chaosPart(ufo, Vector3.new(1.6, 1.6, 1.6), GREEN, Enum.Material.Neon, 0)
		light.Shape = Enum.PartType.Ball
		light.CFrame = CFrame.new(math.cos(a) * 12.5, 0, math.sin(a) * 12.5)
	end
	local glow = Instance.new("PointLight")
	glow.Color = GREEN
	glow.Range = 40
	glow.Brightness = 2
	glow.Parent = hull
	ufo.WorldPivot = CFrame.identity
	ufo.Parent = parent
	return ufo
end

local function startChaos()
	if chaos then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "AlienChaos"
	folder.Parent = workspace
	local rng = Random.new()

	-- Searchlights around the edge of the map, sweeping over it
	type Searchlight = { Base: Vector3, Beam: Part, Phase: number, Speed: number }
	local searchlights: { Searchlight } = {}
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local base = Vector3.new(math.cos(a) * 380, 2, math.sin(a) * 380)
		chaosPart(folder, Vector3.new(8, 4, 8), Color3.fromRGB(40, 45, 55), Enum.Material.Metal, 0).CFrame = CFrame.new(base)
		local beam = chaosPart(folder, Vector3.new(500, 9, 9), GREEN, Enum.Material.Neon, 0.8)
		beam.Shape = Enum.PartType.Cylinder
		table.insert(searchlights, { Base = base + Vector3.new(0, 3, 0), Beam = beam, Phase = rng:NextNumber(0, math.pi * 2), Speed = rng:NextNumber(0.25, 0.45) })
	end

	-- Green lights pulsing around the map (a slow glow, about once a second)
	type Pulser = { Light: PointLight, Orb: Part, Phase: number }
	local pulsers: { Pulser } = {}
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local orb = chaosPart(folder, Vector3.new(3, 3, 3), GREEN, Enum.Material.Neon, 0)
		orb.Shape = Enum.PartType.Ball
		orb.CFrame = CFrame.new(math.cos(a) * rng:NextNumber(150, 330), rng:NextNumber(25, 45), math.sin(a) * rng:NextNumber(150, 330))
		local light = Instance.new("PointLight")
		light.Color = GREEN
		light.Range = 45
		light.Parent = orb
		table.insert(pulsers, { Light = light, Orb = orb, Phase = rng:NextNumber(0, math.pi * 2) })
	end

	-- Mini UFOs flying loops over the map
	type Flyer = { Model: Model, Radius: number, Height: number, Speed: number, Phase: number, Wobble: number }
	local flyers: { Flyer } = {}
	for _ = 1, 6 do
		table.insert(flyers, {
			Model = miniUfo(folder),
			Radius = rng:NextNumber(120, 340),
			Height = rng:NextNumber(110, 190),
			Speed = rng:NextNumber(0.15, 0.3) * (if rng:NextNumber() < 0.5 then -1 else 1),
			Phase = rng:NextNumber(0, math.pi * 2),
			Wobble = rng:NextNumber(0.5, 1.5),
		})
	end

	local started = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		for _, light in searchlights do
			-- Sweep side to side and up and down, aimed over the map
			local inward = Vector3.new(-light.Base.X, 0, -light.Base.Z).Unit
			local side = Vector3.new(-inward.Z, 0, inward.X)
			local sweep = math.sin(t * light.Speed + light.Phase)
			local lift = 0.35 + 0.25 * math.sin(t * light.Speed * 1.7 + light.Phase)
			local direction = (inward + side * sweep * 0.9 + Vector3.new(0, lift, 0)).Unit
			local mid = light.Base + direction * 250
			light.Beam.CFrame = CFrame.lookAt(mid, mid + direction) * CFrame.Angles(0, math.pi / 2, 0)
		end
		for _, pulser in pulsers do
			local glow = (math.sin(t * 5 + pulser.Phase) + 1) / 2
			pulser.Light.Brightness = glow * 4
			pulser.Orb.Transparency = 0.6 - glow * 0.6
		end
		for _, flyer in flyers do
			local a = t * flyer.Speed + flyer.Phase
			local r = flyer.Radius * (0.8 + 0.2 * math.sin(t * 0.4 * flyer.Wobble + flyer.Phase))
			local position = Vector3.new(math.cos(a) * r, flyer.Height + math.sin(t * flyer.Wobble) * 12, math.sin(a) * r)
			flyer.Model:PivotTo(CFrame.new(position) * CFrame.Angles(math.sin(t * 2 + flyer.Phase) * 0.15, t * 2, 0))
		end
	end)
	local state: ChaosState = { Folder = folder, Connection = connection, Running = true }
	chaos = state

	-- Abduction beams zapping random spots on the map
	task.spawn(function()
		while state.Running do
			task.wait(rng:NextNumber(1.5, 3.5))
			if not state.Running then
				break
			end
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = math.sqrt(rng:NextNumber()) * 350
			local spot = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local beam = chaosPart(folder, Vector3.new(260, 14, 14), GREEN, Enum.Material.Neon, 1)
			beam.Shape = Enum.PartType.Cylinder
			beam.CFrame = CFrame.new(spot + Vector3.new(0, 130, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			local ring = chaosPart(folder, Vector3.new(0.4, 22, 22), GREEN, Enum.Material.Neon, 1)
			ring.Shape = Enum.PartType.Cylinder
			ring.CFrame = CFrame.new(spot + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Texture = SPARKLE
			sparkles.Color = ColorSequence.new(GREEN, Color3.new(1, 1, 1))
			sparkles.LightEmission = 1
			sparkles.Rate = 0
			sparkles.Lifetime = NumberRange.new(1, 1.6)
			sparkles.Speed = NumberRange.new(15, 30)
			sparkles.SpreadAngle = Vector2.new(20, 20)
			sparkles.EmissionDirection = Enum.NormalId.Right -- turned on its side, so "Right" is up
			sparkles.Size = NumberSequence.new(1.2, 0)
			sparkles.Parent = ring
			tween(beam, 0.4, { Transparency = 0.55 })
			tween(ring, 0.4, { Transparency = 0.2 })
			sparkles:Emit(40)
			task.delay(1.6, function()
				tween(beam, 0.6, { Transparency = 1 })
				tween(ring, 0.6, { Transparency = 1 })
				task.delay(0.7, function()
					beam:Destroy()
					ring:Destroy()
				end)
			end)
		end
	end)
end

local function stopChaos()
	local state = chaos
	chaos = nil
	if not state then
		return
	end
	state.Running = false
	state.Connection:Disconnect()
	state.Folder:Destroy()
end

-- Event theme songs ---------------------------------------------------------
-- Any founder event with a MusicId plays it, looping, fading in when the
-- event starts and out when it ends.

local eventMusic: Sound? = nil

local function startEventMusic(musicId: string?)
	if eventMusic or not musicId or musicId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "FounderEventMusic"
	sound.SoundId = musicId
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	tween(sound, 3, { Volume = 0.6 })
	eventMusic = sound
end

local function stopEventMusic()
	local sound = eventMusic
	eventMusic = nil
	if sound then
		tween(sound, 3, { Volume = 0 })
		task.delay(3.1, function()
			sound:Destroy()
		end)
	end
end

-- Party lighting while it's live ---------------------------------------------

local party: ColorCorrectionEffect? = nil

local function startParty()
	if party then
		return
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "AdminAbuseParty"
	effect.Saturation = 0.25
	effect.Parent = Lighting
	party = effect
	task.spawn(function()
		while party == effect do
			-- A soft wash of color that slowly cycles, not a strobe.
			effect.TintColor = Color3.fromHSV((os.clock() * 0.08) % 1, 0.12, 1)
			task.wait(0.05)
		end
	end)
end

local function stopParty()
	local effect = party
	party = nil
	if effect then
		tween(effect, 1.5, { TintColor = Color3.new(1, 1, 1), Saturation = 0 })
		task.delay(1.6, function()
			effect:Destroy()
		end)
	end
end

-- The big intro --------------------------------------------------------------

type Intro = {
	Title: string,
	Subtitle: () -> string,
	Colors: { Color3 }, -- light rays and confetti-ish accents
	Gradient: (number) -> ColorSequence, -- title colors over time
	Tint: Color3, -- the world flashes this color
	Chips: { string }, -- little boxes that pop in under the title
	Fireworks: number,
	Confetti: number,
}

local function cycle(colors: { Color3 }): (number) -> ColorSequence
	return function(offset: number): ColorSequence
		local keys = {}
		local n = #colors
		for i = 0, n do
			local c = colors[(math.floor(i + offset * n) % n) + 1]
			table.insert(keys, ColorSequenceKeypoint.new(i / n, c))
		end
		return ColorSequence.new(keys)
	end
end

local function playIntro(intro: Intro)
	introPlaying = true
	-- 1. Two white flashes, the world flashes color and the camera shakes.
	for k = 0, 1 do
		task.delay(k * 0.35, function()
			local flash = Instance.new("Frame")
			flash.BackgroundColor3 = Color3.new(1, 1, 1)
			flash.BorderSizePixel = 0
			flash.Size = UDim2.fromScale(1, 1)
			flash.ZIndex = 10
			flash.Parent = gui
			tween(flash, 0.6, { BackgroundTransparency = 1 })
			task.delay(0.7, function()
				flash:Destroy()
			end)
		end)
	end
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "AdminAbuseFlash"
	tint.TintColor = intro.Tint
	tint.Contrast = 0.25
	tint.Parent = Lighting
	tween(tint, 3, { TintColor = Color3.new(1, 1, 1), Contrast = 0 })
	task.delay(3.1, function()
		tint:Destroy()
	end)
	shake(1.6, 8)

	-- 2. Dark backdrop, a pulsing rainbow border and spinning light rays.
	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = gui
	local border = Instance.new("UIStroke")
	border.Thickness = 14
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = Color3.new(1, 1, 1)
	border.Parent = backdrop
	local borderColors = Instance.new("UIGradient")
	borderColors.Color = rainbow(0)
	borderColors.Parent = border

	local rays = Instance.new("Frame")
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.4)
	rays.Size = UDim2.fromOffset(10, 10)
	rays.ZIndex = 2
	rays.Parent = gui
	for k = 0, 11 do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = intro.Colors[k % #intro.Colors + 1]
		ray.BackgroundTransparency = 0.35
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(60, 2600)
		ray.Rotation = k * 15
		ray.ZIndex = 2
		ray.Parent = rays
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(0.6, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	local raysScale = Instance.new("UIScale")
	raysScale.Scale = 0.1
	raysScale.Parent = rays
	tween(raysScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)

	-- 3. Giant title that slams in, then a subtitle.
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.36)
	title.Size = UDim2.fromScale(0.9, 0.24)
	title.Font = Enum.Font.FredokaOne
	title.Text = intro.Title
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 6
	title.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = Color3.fromRGB(30, 0, 10)
	stroke.Parent = title
	local colors = Instance.new("UIGradient")
	colors.Color = intro.Gradient(0)
	colors.Parent = title
	local titleScale = Instance.new("UIScale")
	titleScale.Scale = 6
	titleScale.Parent = title
	tween(titleScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.53)
	subtitle.Size = UDim2.fromScale(0.75, 0.065)
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.TextScaled = true
	subtitle.TextColor3 = GOLD
	subtitle.TextTransparency = 1
	subtitle.ZIndex = 6
	subtitle.Parent = gui
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Transparency = 1
	subStroke.Parent = subtitle
	task.delay(0.5, function()
		-- Set now so anything sent alongside (like the admin's name) has arrived.
		subtitle.Text = intro.Subtitle()
		tween(subtitle, 0.4, { TextTransparency = 0 })
		tween(subStroke, 0.4, { Transparency = 0 })
	end)

	-- 4. The boosts pop in one by one, each with a little shake.
	local chipRow = Instance.new("Frame")
	chipRow.BackgroundTransparency = 1
	chipRow.AnchorPoint = Vector2.new(0.5, 0)
	chipRow.Position = UDim2.fromScale(0.5, 0.6)
	chipRow.Size = UDim2.fromScale(0.95, 0.18)
	chipRow.ZIndex = 6
	chipRow.Parent = gui
	local chipLayout = Instance.new("UIGridLayout")
	chipLayout.CellSize = UDim2.new(0, 190, 0, 50)
	chipLayout.CellPadding = UDim2.fromOffset(10, 10)
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipRow
	for i, chipText in intro.Chips do
		task.delay(0.9 + i * 0.3, function()
			local chip = Instance.new("TextLabel")
			chip.LayoutOrder = i
			chip.BackgroundColor3 = intro.Colors[(i - 1) % #intro.Colors + 1]:Lerp(Color3.new(0, 0, 0), 0.35)
			chip.Font = Enum.Font.FredokaOne
			chip.Text = chipText
			chip.TextScaled = true
			chip.TextColor3 = Color3.new(1, 1, 1)
			chip.ZIndex = 7
			chip.Parent = chipRow
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = chip
			local chipStroke = Instance.new("UIStroke")
			chipStroke.Thickness = 3
			chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			chipStroke.Color = GOLD
			chipStroke.Parent = chip
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 8)
			padding.PaddingRight = UDim.new(0, 8)
			padding.PaddingTop = UDim.new(0, 6)
			padding.PaddingBottom = UDim.new(0, 6)
			padding.Parent = chip
			local chipScale = Instance.new("UIScale")
			chipScale.Scale = 2.5
			chipScale.Parent = chip
			tween(chipScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			shake(0.25, 3)
		end)
	end

	-- 5. Confetti and fireworks.
	confetti(intro.Confetti, 7)
	task.spawn(fireworksAroundMe, intro.Fireworks, 0.25)

	-- Animate: rays spin, the border and title cycle colors, the title pulses.
	local started = os.clock()
	local animate = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		rays.Rotation = t * 45
		colors.Color = intro.Gradient(t * 0.5)
		borderColors.Rotation = (t * 120) % 360
		border.Thickness = 12 + math.sin(t * 8) * 4
		if t > 0.6 then
			titleScale.Scale = 1 + math.sin(t * 6) * 0.06
			title.Rotation = math.sin(t * 3) * 4
		end
	end)

	-- 6. After a few seconds everything flies away.
	task.wait(1.2 + #intro.Chips * 0.3 + 3.5)
	tween(titleScale, 0.4, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(raysScale, 0.5, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(subtitle, 0.3, { TextTransparency = 1 })
	tween(subStroke, 0.3, { Transparency = 1 })
	tween(backdrop, 0.6, { BackgroundTransparency = 1 })
	tween(border, 0.6, { Transparency = 1 })
	for _, chip in chipRow:GetChildren() do
		if chip:IsA("TextLabel") then
			tween(chip, 0.3, { BackgroundTransparency = 1, TextTransparency = 1 })
		end
	end
	task.wait(0.7)
	animate:Disconnect()
	for _, item: GuiObject in { title, subtitle, rays, backdrop, chipRow } :: { GuiObject } do
		item:Destroy()
	end
	introPlaying = false
end

local boosts = Config.AdminAbuseBoosts
local ABUSE_INTRO: Intro = {
	Title = "ADMIN ABUSE!",
	Subtitle = function()
		return if startedBy then startedBy .. " is abusing! The founders are here!" else "The founders are here! Grab everything!"
	end,
	Colors = { RED, GOLD, Color3.fromRGB(190, 90, 255) },
	Gradient = rainbow,
	Tint = Color3.fromRGB(255, 120, 120),
	Chips = {
		string.format("x%d CASH", boosts.Income),
		string.format("x%d LUCK", boosts.Luck),
		"SUPER SPEED",
		"SUPER JUMP",
		"FREE GIFT",
		"GIANT FOUNDERS",
	},
	Fireworks = 24,
	Confetti = 220,
}

local function founderIntro(eventId: string): Intro?
	local event = Config.FounderEvents[eventId]
	if not event then
		return nil
	end
	return {
		Title = event.Title,
		Subtitle = function()
			return event.Subtitle
		end,
		Colors = event.Colors,
		Gradient = cycle(event.Colors),
		Tint = event.Colors[1]:Lerp(Color3.new(1, 1, 1), 0.4),
		Chips = event.Chips,
		Fireworks = 16,
		Confetti = 180,
	}
end

-- The gift card: pops up after the intro showing what you got.
showGift = function(brainrotId: string, mutationId: string?, diamonds: number, shards: number)
	task.wait(0.5)
	while introPlaying do
		task.wait(0.2)
	end
	local brainrot = Config.GetBrainrot(brainrotId)
	local mutation = Config.GetMutation(mutationId)
	local brainrotName = if brainrot then brainrot.DisplayName else "a brainrot"
	if mutation then
		brainrotName = string.upper(mutation.DisplayName) .. " " .. brainrotName
	end
	local rarityColor = if brainrot then Config.Rarities[brainrot.Rarity].Color else GOLD

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.45)
	card.Size = UDim2.fromOffset(420, 250)
	card.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
	card.ZIndex = 8
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = card
	local border = Instance.new("UIStroke")
	border.Thickness = 4
	border.Color = GOLD
	border.Parent = card
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = card

	local function line(y: number, height: number, label: string, color: Color3)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.new(0, 16, 0, y)
		t.Size = UDim2.new(1, -32, 0, height)
		t.Font = Enum.Font.FredokaOne
		t.Text = label
		t.TextScaled = true
		t.TextColor3 = color
		t.ZIndex = 9
		t.Parent = card
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Parent = t
	end
	line(14, 46, "ADMIN ABUSE GIFT!", GOLD)
	line(72, 36, string.format("+%d Diamonds", diamonds), Color3.fromRGB(120, 180, 255))
	line(112, 36, string.format("+%d Shards", shards), Color3.fromRGB(140, 220, 255))
	line(152, 36, "+ " .. brainrotName, rarityColor)
	line(200, 30, string.format("x%d Cash, x%d Luck, Speed & Jump while it lasts!", boosts.Income, boosts.Luck), Color3.fromRGB(120, 255, 140))

	tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	confetti(60, 3)
	task.wait(5)
	tween(scale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(0.35)
	card:Destroy()
end

-- Announcements from admins (/announce), shown in every server: a big card
-- that drops in at the top of the screen, plus a line in chat.
local announcementShowing = false
showAnnouncement = function(from: string, message: string)
	pcall(function()
		local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(string.format("[ANNOUNCEMENT] %s: %s", from, message))
		end
	end)
	-- One card at a time
	while announcementShowing do
		task.wait(0.3)
	end
	announcementShowing = true

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -160)
	card.Size = UDim2.new(0.6, 0, 0, 120)
	card.BackgroundColor3 = Color3.fromRGB(25, 20, 40)
	card.BackgroundTransparency = 0.1
	card.ZIndex = 20
	card.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 0)
	constraint.MaxSize = Vector2.new(760, math.huge)
	constraint.Parent = card
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = card
	local border = Instance.new("UIStroke")
	border.Thickness = 4
	border.Color = GOLD
	border.Parent = card
	local glow = Instance.new("UIGradient")
	glow.Color = rainbow(0)
	glow.Parent = border

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(16, 8)
	header.Size = UDim2.new(1, -32, 0, 34)
	header.Font = Enum.Font.FredokaOne
	header.Text = "ANNOUNCEMENT FROM " .. string.upper(from)
	header.TextScaled = true
	header.TextColor3 = GOLD
	header.ZIndex = 21
	header.Parent = card
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 46)
	body.Size = UDim2.new(1, -32, 1, -56)
	body.Font = Enum.Font.FredokaOne
	body.Text = message
	body.TextScaled = true
	body.TextWrapped = true
	body.TextColor3 = Color3.new(1, 1, 1)
	body.ZIndex = 21
	body.Parent = card
	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Thickness = 2
	bodyStroke.Parent = body

	tween(card, 0.5, { Position = UDim2.new(0.5, 0, 0, 70) }, Enum.EasingStyle.Back)
	shake(0.3, 2)
	local started = os.clock()
	local spin = RunService.RenderStepped:Connect(function()
		glow.Rotation = ((os.clock() - started) * 120) % 360
	end)
	task.wait(8)
	tween(card, 0.4, { Position = UDim2.new(0.5, 0, 0, -160) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(0.45)
	spin:Disconnect()
	card:Destroy()
	announcementShowing = false
end

-- A smaller "it's over" card when it ends.
local function playOutro(text: string)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.fromScale(0.6, 0.1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = RED
	label.TextTransparency = 1
	label.ZIndex = 6
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Transparency = 1
	stroke.Parent = label
	tween(label, 0.4, { TextTransparency = 0 })
	tween(stroke, 0.4, { Transparency = 0 })
	task.wait(2.5)
	tween(label, 0.6, { TextTransparency = 1 })
	tween(stroke, 0.6, { Transparency = 1 })
	task.wait(0.7)
	label:Destroy()
end

-- Watch for it starting and ending ------------------------------------------

local function isLive(): boolean
	local now = workspace:GetServerTimeNow()
	local manualEnd = ReplicatedStorage:GetAttribute("AdminAbuseEndsAt") :: number?
	return (manualEnd ~= nil and manualEnd > now) or Config.AdminAbuseStatus(now) == "live"
end

-- Founder events (Corny's, Ace's...)
local currentFounderEvent = ""
local function onFounderEvent()
	local eventId = ReplicatedStorage:GetAttribute("FounderEvent") :: string? or ""
	if eventId == currentFounderEvent then
		return
	end
	local previous = Config.FounderEvents[currentFounderEvent]
	currentFounderEvent = eventId
	local intro = founderIntro(eventId)
	local event = Config.FounderEvents[eventId]
	if event and event.Sky then
		startRainbowSky(event.Sky, event.Night)
	else
		stopRainbowSky()
	end
	if event and event.Water then
		startBallet(event)
	else
		stopBallet()
	end
	if event and event.Chaos then
		startChaos()
	else
		stopChaos()
	end
	if event then
		startEventMusic(event.MusicId)
	else
		stopEventMusic()
	end
	if intro then
		task.spawn(playIntro, intro)
	elseif previous then
		task.spawn(playOutro, if previous.Style == "Ballet" then "THE BALLET IS OVER!" else string.upper(previous.Founder) .. " FLEW AWAY!")
	end
end
ReplicatedStorage:GetAttributeChangedSignal("FounderEvent"):Connect(onFounderEvent)
onFounderEvent()

local wasLive = false
local nextFirework = 0
while true do
	local live = isLive()
	if live and not wasLive then
		task.spawn(playIntro, ABUSE_INTRO)
		startParty()
		nextFirework = os.clock() + 10
	elseif wasLive and not live then
		startedBy = nil
		stopParty()
		task.spawn(playOutro, "ADMIN ABUSE IS OVER")
	elseif live and os.clock() >= nextFirework then
		-- Every few seconds while it's live, a couple more fireworks.
		task.spawn(fireworksAroundMe, 3, 0.4)
		nextFirework = os.clock() + math.random(4, 7)
	end
	wasLive = live
	task.wait(0.25)
end

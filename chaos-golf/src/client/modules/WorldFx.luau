--!strict
-- Client-side world effects: spinning showcase props, skin pulse/rainbow,
-- ball trails (equipped Trail cosmetic), knockout effects, sink celebrations,
-- ability visuals, coin popups and server announcements.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Hud = require(script.Parent:WaitForChild("Hud"))

local WorldFx = {}

local T = UIKit.Theme
local player = Players.LocalPlayer
local fxFolder: Folder

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- Helpers ------------------------------------------------------------------

local function anchorPart(position: Vector3, life: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(position)
	p.Parent = fxFolder
	Debris:AddItem(p, life)
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Texture = SPARKLE
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function burst(position: Vector3, color: Color3 | ColorSequence, count: number, speed: number, size: number, texture: string?, gravity: number?)
	local p = anchorPart(position, 3)
	local e = emitter(p, {
		Texture = texture or SPARKLE,
		Color = if typeof(color) == "Color3" then ColorSequence.new(color) else color,
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(0.5, 1.1),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) }),
		Acceleration = Vector3.new(0, -(gravity or 0), 0),
		Drag = 2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
	})
	e:Emit(count)
end

local function ring(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number)
	local r = Instance.new("Part")
	r.Shape = Enum.PartType.Cylinder
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.Material = Enum.Material.Neon
	r.Color = color
	r.Transparency = 0.2
	r.Size = Vector3.new(0.15, fromSize, fromSize)
	r.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	r.Parent = fxFolder
	TweenService:Create(r, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, toSize, toSize),
		Transparency = 1,
	}):Play()
	Debris:AddItem(r, duration + 0.1)
end

local function sound(id: string, position: Vector3?, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	if position then
		local p = anchorPart(position, 4)
		s.Parent = p
	else
		s.Parent = fxFolder
	end
	s:Play()
	Debris:AddItem(s, 4)
end

local function floatingText(position: Vector3, text: string, color: Color3, size: number?)
	local p = anchorPart(position, 2)
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(240, 50)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Adornee = p
	local label = UIKit.text({
		Text = text,
		TextSize = size or 28,
		Font = T.FontHeavy,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = g,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = label
	g.Parent = p
	TweenService:Create(g, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
end

-- Knockout effects (cosmetic) -----------------------------------------------------

function WorldFx.knockout(effectId: string?, position: Vector3, scale: number)
	local def = Cosmetics.getOrDefault("Knockouts", effectId)
	local s = (def.Scale or 1) * scale
	local c = def.Color
	local style = def.Style or "Burst"
	if style == "Burst" then
		burst(position, c, math.floor(24 * s), 14 * s, 0.6 * s)
	elseif style == "Stars" then
		burst(position, c, math.floor(14 * s), 10 * s, 1.1 * s, SPARKLE, 20)
	elseif style == "Ring" then
		ring(position, c, 1, 12 * s, 0.45)
		burst(position, c, math.floor(12 * s), 8 * s, 0.5 * s)
	elseif style == "Confetti" then
		local seq = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 229, 255)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(255, 225, 77)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(46, 212, 122)),
		})
		burst(position, seq, math.floor(40 * s), 18 * s, 0.45 * s, SPARKLE, 35)
	elseif style == "Shatter" then
		for _ = 1, math.floor(8 * s) do
			local shard = Instance.new("Part")
			shard.Anchored = true
			shard.CanCollide = false
			shard.CanQuery = false
			shard.Material = Enum.Material.Glass
			shard.Transparency = 0.2
			shard.Color = c
			shard.Size = Vector3.new(0.3, 0.6, 0.1) * s
			shard.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			shard.Parent = fxFolder
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
			TweenService:Create(shard, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = shard.CFrame + dir * 5 * s,
				Transparency = 1,
			}):Play()
			Debris:AddItem(shard, 0.7)
		end
		burst(position, Color3.new(1, 1, 1), 16, 10 * s, 0.4 * s)
	elseif style == "Lightning" then
		local top = position + Vector3.new(0, 14, 0)
		local prev = top
		for i = 1, 6 do
			local nextPoint = top:Lerp(position, i / 6) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2.2
			local seg = Instance.new("Part")
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.Material = Enum.Material.Neon
			seg.Color = c
			seg.Size = Vector3.new(0.25, 0.25, (nextPoint - prev).Magnitude)
			seg.CFrame = CFrame.lookAt((prev + nextPoint) / 2, nextPoint)
			seg.Parent = fxFolder
			TweenService:Create(seg, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			Debris:AddItem(seg, 0.4)
			prev = nextPoint
		end
		ring(position, c, 1, 8 * s, 0.35)
		burst(position, c, 18, 12 * s, 0.5 * s)
	elseif style == "Flames" then
		local p = anchorPart(position, 2)
		local e = emitter(p, {
			Texture = FIRE,
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 80), c),
			Speed = NumberRange.new(6 * s, 12 * s),
			SpreadAngle = Vector2.new(60, 60),
			Lifetime = NumberRange.new(0.4, 0.8),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4 * s), NumberSequenceKeypoint.new(1, 0) }),
			Acceleration = Vector3.new(0, 12, 0),
			LightEmission = 0.8,
		})
		e:Emit(math.floor(30 * s))
		ring(position, c, 1, 9 * s, 0.4)
	elseif style == "Vortex" then
		local p = anchorPart(position, 2)
		local e = emitter(p, {
			Color = ColorSequence.new(c, Color3.new(0, 0, 0)),
			Speed = NumberRange.new(-10 * s, -6 * s),
			SpreadAngle = Vector2.new(180, 180),
			Lifetime = NumberRange.new(0.6, 0.9),
			Size = NumberSequence.new(0.6 * s, 0),
			RotSpeed = NumberRange.new(360, 540),
			EmissionDirection = Enum.NormalId.Top,
		})
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		p.Size = Vector3.one * 8 * s
		e:Emit(math.floor(40 * s))
		ring(position, c, 10 * s, 0.5, 0.6)
	elseif style == "Nova" then
		local flash = Instance.new("Part")
		flash.Shape = Enum.PartType.Ball
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = c
		flash.Size = Vector3.one
		flash.CFrame = CFrame.new(position)
		flash.Parent = fxFolder
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 9 * s, Transparency = 1 }):Play()
		Debris:AddItem(flash, 0.6)
		ring(position, Color3.new(1, 1, 1), 1, 16 * s, 0.6)
		burst(position, c, 50, 24 * s, 0.7 * s)
	end
end

-- Celebrations ----------------------------------------------------------------------

local function celebrate(position: Vector3, style: string?, big: boolean)
	local n = if big then 2 else 1
	if style == "Fireworks" then
		for i = 1, 3 * n do
			task.delay(i * 0.18, function()
				local at = position + Vector3.new(math.random(-4, 4), 6 + math.random() * 4, math.random(-4, 4))
				burst(at, Color3.fromHSV(math.random(), 0.8, 1), 30, 16, 0.5, SPARKLE, 12)
			end)
		end
	elseif style == "Galaxy" then
		WorldFx.knockout("black_hole", position + Vector3.new(0, 1, 0), 0.8 * n)
		burst(position, ColorSequence.new(Color3.fromRGB(120, 60, 255), Color3.fromRGB(0, 229, 255)), 40 * n, 10, 0.5)
	elseif style == "Confetti" then
		WorldFx.knockout("confetti_blast", position + Vector3.new(0, 1, 0), 1.2 * n)
	else
		burst(position + Vector3.new(0, 0.5, 0), ColorSequence.new(T.Primary, Color3.new(1, 1, 1)), 24 * n, 10, 0.4, SPARKLE, 8)
		ring(position + Vector3.new(0, 0.1, 0), T.Primary, 1, 6 * n, 0.5)
	end
end

-- Skin pulse / rainbow and spinning props ------------------------------------------------

local spinners: { [BasePart]: CFrame } = {}
local pulsers: { [BasePart]: boolean } = {}

local function trackSpin(part: Instance)
	if part:IsA("BasePart") then
		spinners[part] = part.CFrame
	end
end

local function trackPulse(part: Instance)
	if part:IsA("BasePart") then
		pulsers[part] = true
	end
end

-- Trails ----------------------------------------------------------------------------------

type Carrier = { Part: Part, Target: BasePart, Orbit: boolean }
local carriers: { [BasePart]: Carrier } = {}

local function removeTrail(target: BasePart)
	local c = carriers[target]
	if c then
		carriers[target] = nil
		c.Part:Destroy()
	end
end

local function attachTrail(target: BasePart, trailId: string?, orbit: boolean)
	removeTrail(target)
	if not trailId or trailId == "none" then
		return
	end
	local def = Cosmetics.get("Trails", trailId)
	if not def or not def.Colors then
		return
	end
	local carrier = Instance.new("Part")
	carrier.Name = "TrailCarrier"
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.Transparency = 1
	carrier.Size = Vector3.one * 0.2
	carrier.CFrame = target.CFrame
	carrier.Parent = fxFolder
	local w = (def.Width or 0.5) * (if orbit then 0.8 else 1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, w / 2, 0)
	a0.Parent = carrier
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -w / 2, 0)
	a1.Parent = carrier
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	local keys = {}
	local colors = def.Colors :: { Color3 }
	for i, col in colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), col))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	trail.Color = ColorSequence.new(keys)
	trail.Lifetime = def.Lifetime or 0.5
	trail.LightEmission = def.Glow or 0
	trail.LightInfluence = 1 - (def.Glow or 0)
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	trail.Parent = carrier
	if def.Sparks then
		emitter(carrier, {
			Rate = 14,
			Color = ColorSequence.new(colors[1]),
			Speed = NumberRange.new(0.5, 1.5),
			Lifetime = NumberRange.new(0.3, 0.6),
			Size = NumberSequence.new(0.18, 0),
			SpreadAngle = Vector2.new(180, 180),
		})
	end
	carriers[target] = { Part = carrier, Target = target, Orbit = orbit }
end

local function watchBall(ball: Instance)
	if not ball:IsA("BasePart") then
		return
	end
	attachTrail(ball, ball:GetAttribute("Trail") :: string?, false)
	ball:GetAttributeChangedSignal("Trail"):Connect(function()
		attachTrail(ball, ball:GetAttribute("Trail") :: string?, false)
	end)
	ball.AncestryChanged:Connect(function(_, parent)
		if not parent then
			removeTrail(ball)
		end
	end)
end

local function watchShowcase(part: Instance)
	if part:IsA("BasePart") and part:GetAttribute("ShowcaseTrail") ~= nil then
		attachTrail(part, part:GetAttribute("ShowcaseTrail") :: string?, true)
		part.AncestryChanged:Connect(function(_, parent)
			if not parent then
				removeTrail(part)
			end
		end)
	end
end

-- Ability visuals -----------------------------------------------------------------------

local function abilityFx(payload: any)
	local from = payload.From :: BasePart?
	local at = if from then from.Position else nil
	local id = payload.Ability
	if id == "Shockwave" and at then
		ring(at, Color3.fromRGB(255, 120, 40), 1, 44, 0.5)
		burst(at, Color3.fromRGB(255, 160, 80), 30, 20, 0.5)
		sound(Config.Sounds.Bonk, at, 0.9)
	elseif id == "Frost" then
		for _, t in payload.Targets or {} do
			if t and t.Parent then
				burst(t.Position, Color3.fromRGB(190, 240, 255), 30, 6, 0.5)
			end
		end
	elseif id == "Gust" then
		for _, t in payload.Targets or {} do
			if t and t.Parent then
				burst(t.Position, Color3.fromRGB(220, 255, 235), 20, 12, 0.4, SMOKE)
			end
		end
	elseif id == "TinyCup" then
		for _, t in payload.Targets or {} do
			if t and t.Parent then
				ring(t.Position, Color3.fromRGB(255, 70, 160), 6, 1, 0.5)
			end
		end
	elseif id == "Magnet" and at then
		ring(at, Color3.fromRGB(255, 210, 60), 6, 1, 0.5)
	elseif id == "Mulligan" and at then
		burst(at, Color3.fromRGB(140, 255, 120), 24, 8, 0.4)
	end
	if payload.Player and payload.Player ~= player and at then
		floatingText(at + Vector3.new(0, 2, 0), string.upper(id), Color3.new(1, 1, 1), 22)
	end
end

-- Announcements ---------------------------------------------------------------------------

local function announce(text: string, color: Color3?)
	local hex = (color or T.Gold):ToHex()
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			general:DisplaySystemMessage(string.format('<font color="#%s"><b>%s</b></font>', hex, text))
		end
	end)
end

function WorldFx.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ChaosGolfFx"
	fxFolder.Parent = workspace

	for _, p in CollectionService:GetTagged("Spin") do
		trackSpin(p)
		watchShowcase(p)
	end
	CollectionService:GetInstanceAddedSignal("Spin"):Connect(function(p)
		trackSpin(p)
		task.defer(watchShowcase, p)
	end)
	CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(p)
		if p:IsA("BasePart") then
			spinners[p] = nil
		end
	end)
	for _, p in CollectionService:GetTagged("SkinFx") do
		trackPulse(p)
	end
	CollectionService:GetInstanceAddedSignal("SkinFx"):Connect(trackPulse)
	CollectionService:GetInstanceRemovedSignal("SkinFx"):Connect(function(p)
		if p:IsA("BasePart") then
			pulsers[p] = nil
		end
	end)

	task.spawn(function()
		local balls = workspace:WaitForChild("GolfBalls")
		for _, b in balls:GetChildren() do
			watchBall(b)
		end
		balls.ChildAdded:Connect(watchBall)
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for part, base in spinners do
			if not part.Parent then
				spinners[part] = nil
			else
				local speed = (part:GetAttribute("SpinSpeed") :: number?) or 1.5
				part.CFrame = CFrame.new(part.Position) * (base - base.Position) * CFrame.Angles(0, t * speed, 0)
			end
		end
		for part in pulsers do
			if not part.Parent then
				pulsers[part] = nil
			elseif part:GetAttribute("SkinRainbow") then
				part.Color = Color3.fromHSV((t * 0.15) % 1, 0.75, 1)
			else
				local a = part:GetAttribute("SkinBase") :: Color3?
				local b = part:GetAttribute("SkinPulse") :: Color3?
				if a and b then
					part.Color = a:Lerp(b, (math.sin(t * 2.4) + 1) / 2)
				end
			end
		end
		for target, c in carriers do
			if not target.Parent then
				removeTrail(target)
			elseif c.Orbit then
				local angle = t * 2.2
				c.Part.CFrame = CFrame.new(target.Position + Vector3.new(math.cos(angle) * 2.6, math.sin(t * 1.3) * 0.6, math.sin(angle) * 2.6))
			else
				c.Part.CFrame = CFrame.new(target.Position)
			end
		end
		local _ = dt
	end)

	Net.event("Fx").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "sink" then
			local who = payload.Player :: Player?
			local style = if who then who:GetAttribute("Celebration") :: string? else nil
			celebrate(payload.Position, style, payload.Strokes == 1)
			if who == player then
				sound(Config.Sounds.Sink, nil, 0.9)
			end
		elseif kind == "hit" then
			WorldFx.knockout(payload.Effect, payload.Position, 0.55)
		elseif kind == "knockout" then
			WorldFx.knockout(payload.Effect, payload.Position, 1.2)
			local attacker = payload.Attacker :: Player?
			floatingText(payload.Position + Vector3.new(0, 3, 0), "KNOCKOUT!", T.Gold, 34)
			if attacker == player then
				Hud.toast("💥 Knockout! +1 sabotage", T.Gold)
			end
		elseif kind == "splash" then
			burst(payload.Position, Color3.fromRGB(80, 180, 255), 30, 12, 0.6, SPARKLE, 30)
			sound(Config.Sounds.Splash, payload.Position, 0.5)
		elseif kind == "ability" then
			abilityFx(payload)
		elseif kind == "pickup" then
			burst(payload.Position, Color3.fromRGB(255, 255, 255), 30, 10, 0.5)
			ring(payload.Position, T.Info, 1, 6, 0.4)
		elseif kind == "gust" then
			local ball = payload.Ball :: BasePart?
			if ball then
				burst(ball.Position, Color3.fromRGB(220, 255, 235), 16, 14, 0.4, SMOKE)
			end
		elseif kind == "coins" then
			local character = player.Character
			local head = character and character:FindFirstChild("Head") :: BasePart?
			local at = if Hud.ball and Hud.ball.Parent then (Hud.ball :: BasePart).Position elseif head then head.Position else nil
			if at then
				floatingText(at + Vector3.new(0, 2.5, 0), "+" .. payload.Amount, T.Gold, 26)
			end
			sound(Config.Sounds.Coin, nil, 0.35)
		elseif kind == "announce" then
			announce(payload.Text, payload.Color)
		elseif kind == "daily" then
			Hud.toast(string.format("Day %d claimed: %s", payload.Day, payload.Label), if payload.Grand then T.Gold else T.Primary)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				celebrate(root.Position, if payload.Grand then "Fireworks" else "Confetti", payload.Grand)
			end
		elseif kind == "practice" then
			Hud.toast(string.format("%s finished · +%d %s", payload.Minigame, payload.Tokens, payload.Token), if payload.Tokens > 0 then T.Primary else T.Muted)
		end
	end)

	Net.event("CrateReveal").OnClientEvent:Connect(function(_crateId: string, category: string, itemId: string, isNew: boolean, refund: number)
		local item = Cosmetics.get(category, itemId)
		if not item then
			return
		end
		local color = Skins.Rarities[item.Rarity].Color
		if isNew then
			Hud.toast(string.format("NEW %s: %s (%s)", string.upper(Cosmetics.CategoryInfo[category].Singular), item.Name, item.Rarity), color)
		else
			Hud.toast(string.format("Duplicate %s · +%d refunded", item.Name, refund), T.Muted)
		end
	end)
end

return WorldFx

-- Merge A Egg: builds the map and runs the day/night cycle.
-- Layout (like Steal a Egg): one long rectangle. Six pens and the shops sit at the
-- back, the SAFE ZONE line runs right in front of them, then open biome stages
-- follow one after another. A small cave in the Forest's dirt wall teleports you
-- into the Golem King's circular dungeon.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local World = {}

local ctx
local Config
local Models

local c = Color3.fromRGB
local rad = math.rad

World.CORRIDOR_START = 30 -- the SAFE ZONE line
World.BIOME_LENGTH = 160
World.CORRIDOR_HALF = 75
World.WALL_HEIGHT = 50
World.LOBBY_MIN_Z = -205

local PEN_WIDTH = 50 -- local X
local PEN_DEPTH = 56 -- local Z (front at -Z faces the centre aisle)
local PEN_CENTERS = {
	{ pos = Vector3.new(-45, 0, -175), face = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(-45, 0, -120), face = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(-45, 0, -65), face = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(45, 0, -175), face = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(45, 0, -120), face = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(45, 0, -65), face = Vector3.new(-1, 0, 0) },
}
local DUNGEON_ORIGIN = Vector3.new(0, -300, 500) -- hidden far below the map
local DUNGEON_RADIUS = 62
local ARENA_RADIUS = 34

World.pens = {}
World.biomes = {}
World.stalls = {}
World.boards = {}
World.arena = nil
World.dungeon = nil

local mapFolder: Folder
local cycleEvent = Instance.new("BindableEvent")
World.CycleChanged = cycleEvent.Event
local night = false

local part = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function solid(props)
	props.CanCollide = true
	props.CanQuery = true
	return part(props)
end

local function place(model: Model, cf: CFrame, parent: Instance): Model
	model:PivotTo(cf)
	model.Parent = parent
	return model
end

local function prompt(parent: BasePart, action: string, object: string, hold: number?, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 12
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = parent
	return p
end
World.prompt = prompt

local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3, pixels: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = pixels or 25
	gui.LightInfluence = 0
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = c(20, 20, 25)
	stroke.Parent = label
	return label
end

-- Text painted flat on the floor, readable by someone walking toward +Z.
-- The part's Front face points up and its UpVector points away from the reader.
local function floorText(parent, center: Vector3, size: Vector2, text: string, color: Color3)
	local p = part({
		Name = "FloorText",
		Size = Vector3.new(size.X, size.Y, 0.1),
		CFrame = CFrame.fromMatrix(center, Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, -1, 0)),
		Transparency = 1,
		Parent = parent,
	})
	return surfaceText(p, Enum.NormalId.Front, text, color, 12)
end

-- Checkered wall: alternating coloured columns with studs, like the reference.
local function checkerWall(parent, from: Vector3, to: Vector3, height: number, colorA: Color3, colorB: Color3)
	local dir = to - from
	local length = dir.Magnitude
	local count = math.max(1, math.floor(length / 20))
	local step = length / count
	local unit = dir.Unit
	for i = 0, count - 1 do
		local center = from + unit * (step * (i + 0.5)) + Vector3.new(0, height / 2, 0)
		local wall = solid({
			Name = "Wall",
			Size = Vector3.new(4, height, step),
			CFrame = CFrame.lookAt(center, center + unit),
			Color = if i % 2 == 0 then colorA else colorB,
			Material = Enum.Material.Plastic,
			TopSurface = Enum.SurfaceType.Studs,
			LeftSurface = Enum.SurfaceType.Studs,
			RightSurface = Enum.SurfaceType.Studs,
			Parent = parent,
		})
		part({ Name = "WallGrass", Size = Vector3.new(4.4, 1.2, step + 0.2), CFrame = wall.CFrame * CFrame.new(0, height / 2 + 0.6, 0), Color = c(90, 200, 60), Material = Enum.Material.Grass, Parent = parent })
	end
end

local function floorTiles(parent, minX, maxX, minZ, maxZ, tile, colorA, colorB)
	local nx = math.max(1, math.floor((maxX - minX) / tile))
	local nz = math.max(1, math.floor((maxZ - minZ) / tile))
	local sx, sz = (maxX - minX) / nx, (maxZ - minZ) / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			solid({
				Name = "Floor",
				Size = Vector3.new(sx, 2, sz),
				CFrame = CFrame.new(minX + sx * (ix + 0.5), -1, minZ + sz * (iz + 0.5)),
				Color = if (ix + iz) % 2 == 0 then colorA else colorB,
				Material = Enum.Material.Plastic,
				TopSurface = Enum.SurfaceType.Studs,
				Parent = parent,
			})
		end
	end
end

local teleportCooldown: { [Player]: number } = {}

-- A glowing doorway; touching it moves the player to `destination`.
local function teleporter(parent, cf: CFrame, color: Color3, destination: () -> CFrame)
	local portal = part({
		Name = "Portal",
		Size = Vector3.new(9, 12, 1),
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanTouch = true,
		Parent = parent,
	})
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.6, 0)
	sparkles.Rate = 18
	sparkles.Lifetime = NumberRange.new(1, 1.6)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = portal
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 2
	light.Parent = portal
	portal.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or os.clock() < (teleportCooldown[player] or 0) then
			return
		end
		teleportCooldown[player] = os.clock() + 2
		ctx.Economy.grantGrace(player, 3)
		character:PivotTo(destination())
		ctx.Net.fx(player, "Teleport")
	end)
	return portal
end

---------------------------------------------------------------------------
-- Pens
---------------------------------------------------------------------------

local function nestSlotLocal(slot: number): Vector3
	local row = (slot - 1) // 5
	local col = (slot - 1) % 5
	return Vector3.new(-19 + col * 9.5, 0, 9 + row * 10)
end

local function buildFence(pen)
	local model = Instance.new("Model")
	model.Name = "Fence"
	local hx, hz = PEN_WIDTH / 2, PEN_DEPTH / 2
	local segments = {
		{ Vector3.new(-hx, 0, -hz), Vector3.new(-5, 0, -hz) },
		{ Vector3.new(7, 0, -hz), Vector3.new(hx, 0, -hz) },
		{ Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz) },
		{ Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz) },
		{ Vector3.new(-hx, 0, hz), Vector3.new(-hx, 0, -hz) },
	}
	pen.trimParts = {}
	for _, seg in segments do
		local a, b = seg[1], seg[2]
		local length = (b - a).Magnitude
		local posts = math.max(1, math.floor(length / 7))
		for i = 0, posts do
			local p = a:Lerp(b, i / posts)
			local post = solid({
				Name = "Post",
				Size = Vector3.new(1, 4.2, 1),
				CFrame = pen.cframe * CFrame.new(p + Vector3.new(0, 2.1, 0)),
				Color = c(90, 60, 40),
				Material = Enum.Material.Wood,
				Parent = model,
			})
			table.insert(pen.trimParts, post)
			part({ Name = "PostCap", Size = Vector3.new(1.3, 0.35, 1.3), CFrame = post.CFrame * CFrame.new(0, 2.2, 0), Color = c(70, 45, 30), Material = Enum.Material.Wood, Parent = model })
		end
		for _, y in { 1.4, 3.0 } do
			local mid = (a + b) / 2 + Vector3.new(0, y, 0)
			solid({
				Name = "Rail",
				Size = Vector3.new(0.5, 0.5, length),
				CFrame = pen.cframe * CFrame.lookAt(mid, mid + (b - a)),
				Color = c(170, 105, 55),
				Material = Enum.Material.Wood,
				Parent = model,
			})
		end
	end
	model.Parent = pen.model
end

local function buildPen(index: number, info, parent: Instance)
	local cf = CFrame.lookAt(info.pos, info.pos + info.face)
	local model = Instance.new("Model")
	model.Name = "Pen" .. index
	model:SetAttribute("PenIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model.Parent = parent

	local pen = {
		index = index,
		cframe = cf,
		model = model,
		owner = nil,
		nestSlots = {},
		treadmills = {},
	}

	solid({
		Name = "PenFloor",
		Size = Vector3.new(PEN_WIDTH, 0.4, PEN_DEPTH),
		CFrame = cf * CFrame.new(0, 0.2, 0),
		Color = c(125, 220, 85),
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
		Parent = model,
	})
	-- A dirt path from the gate to the nests.
	part({ Name = "Path", Size = Vector3.new(8, 0.1, PEN_DEPTH - 8), CFrame = cf * CFrame.new(1, 0.45, -2), Color = c(200, 160, 105), Material = Enum.Material.Ground, Parent = model })
	buildFence(pen)

	-- Nest slots (locked ones are dimmed until the pen is upgraded).
	local nests = Instance.new("Folder")
	nests.Name = "Nests"
	nests.Parent = model
	for slot = 1, Config.MaxNests do
		local slotCf = cf * CFrame.new(nestSlotLocal(slot) + Vector3.new(0, 0.4, 0))
		local nest = place(Models.nest(), slotCf, nests)
		nest.Name = "Nest" .. slot
		local anchor = part({ Name = "EggAnchor", Size = Vector3.one * 0.5, CFrame = slotCf * CFrame.new(0, 0.45, 0), Transparency = 1, Parent = nest })
		local lockGui = Models.billboard(anchor, "🔒", Color3.new(1, 1, 1), UDim2.fromScale(2.5, 2.5), Vector3.new(0, 2, 0), 80)
		lockGui.Name = "Lock"
		pen.nestSlots[slot] = { cf = slotCf * CFrame.new(0, 0.45, 0), model = nest, anchor = anchor, lock = lockGui }
	end

	-- Pet area where equipped pets wander.
	pen.petArea = { cf = cf * CFrame.new(0, 0.4, -1), size = Vector3.new(40, 0, 7) }
	local petFolder = Instance.new("Folder")
	petFolder.Name = "Pets"
	petFolder.Parent = model
	pen.petFolder = petFolder
	local eggFolder = Instance.new("Folder")
	eggFolder.Name = "Eggs"
	eggFolder.Parent = model
	pen.eggFolder = eggFolder

	-- Treadmill spots (models are swapped in by World.setPenLook).
	pen.treadmillCfs = { cf * CFrame.new(-19, 0.4, -14), cf * CFrame.new(-10.5, 0.4, -14) }

	-- Fuse Machine.
	pen.fuseCf = cf * CFrame.new(15.5, 0.4, -15)
	pen.fuse = place(Models.fuseMachine(), pen.fuseCf, model)
	local fusePromptPart = pen.fuse:FindFirstChild("Pod2") :: BasePart
	pen.fusePrompt = prompt(fusePromptPart, "Insert Egg", "Fuse Machine", 0, 12)
	pen.fuseEjectPrompt = prompt(pen.fuse.PrimaryPart :: BasePart, "Take Eggs Out", "Fuse Machine", 1, 10)
	pen.fuseEjectPrompt.KeyboardKeyCode = Enum.KeyCode.F
	pen.fuseEjectPrompt.UIOffset = Vector2.new(0, 80)

	-- Upgrade sign on the front fence.
	solid({ Name = "SignPost", Size = Vector3.new(0.6, 5, 0.6), CFrame = cf * CFrame.new(15, 2.5, -PEN_DEPTH / 2 - 0.5), Color = c(90, 60, 40), Material = Enum.Material.Wood, Parent = model })
	local sign = solid({ Name = "UpgradeSign", Size = Vector3.new(7, 3.6, 0.4), CFrame = cf * CFrame.new(15, 5.6, -PEN_DEPTH / 2 - 0.5), Color = c(30, 30, 40), Parent = model })
	part({ Name = "SignTrim", Size = Vector3.new(7.4, 4, 0.3), CFrame = sign.CFrame * CFrame.new(0, 0, 0.1), Color = c(255, 200, 60), Material = Enum.Material.Neon, Parent = model })
	pen.upgradeLabel = surfaceText(sign, Enum.NormalId.Front, "Upgrade Pen", Color3.new(1, 1, 1), 40)
	pen.upgradeLabel.RichText = true
	pen.upgradePrompt = prompt(model:FindFirstChild("SignPost") :: BasePart, "Upgrade", "Pen", 0, 12)

	-- Owner name over the entrance and the steal shield.
	local namePart = part({ Name = "NameAnchor", Size = Vector3.one, CFrame = cf * CFrame.new(1, 11, -PEN_DEPTH / 2), Transparency = 1, Parent = model })
	local _, nameLabel = Models.billboard(namePart, "Empty Pen", Color3.new(1, 1, 1), UDim2.fromScale(18, 3), Vector3.new(0, 0, 0), 250)
	pen.nameLabel = nameLabel
	pen.shield = part({
		Name = "Shield",
		Size = Vector3.new(PEN_WIDTH + 2, 24, PEN_DEPTH + 2),
		CFrame = cf * CFrame.new(0, 12, 0),
		Color = c(80, 190, 255),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		Parent = model,
	})
	local _, shieldLabel = Models.billboard(pen.shield, "", c(120, 210, 255), UDim2.fromScale(16, 3), Vector3.new(0, 15, 0), 200)
	pen.shieldLabel = shieldLabel

	pen.spawnCf = cf * CFrame.new(1, 4, -10)
	pen.nestZone = { cf = cf * CFrame.new(0, 5, 14.5), size = Vector3.new(PEN_WIDTH - 4, 14, 20) }
	pen.bounds = { cf = cf * CFrame.new(0, 10, 0), size = Vector3.new(PEN_WIDTH, 24, PEN_DEPTH) }

	World.setPenLook(pen, 1, "Wooden")
	return pen
end

local function insideBox(boxInfo, position: Vector3): boolean
	local localPos = boxInfo.cf:PointToObjectSpace(position)
	local half = boxInfo.size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z and math.abs(localPos.Y) <= math.max(half.Y, 12)
end

function World.inNestZone(pen, position: Vector3): boolean
	return insideBox(pen.nestZone, position)
end

function World.penAt(position: Vector3)
	for _, pen in World.pens do
		if insideBox(pen.bounds, position) then
			return pen
		end
	end
	return nil
end

-- Applies a pen's level (nests, fence trim, sign) and treadmill model.
function World.setPenLook(pen, level: number, treadmillKey: string)
	local levelInfo = Config.PenLevels[level]
	local trim = Models.PenTrim[levelInfo.style]
	for _, p in pen.trimParts do
		p.Color = trim.color
		p.Material = trim.material
	end
	for slot, info in pen.nestSlots do
		local unlocked = slot <= levelInfo.nests
		for _, child in info.model:GetDescendants() do
			if child:IsA("BasePart") and child.Name ~= "Root" and child.Name ~= "EggAnchor" then
				child.Transparency = if unlocked then 0 else 0.7
			end
		end
		info.lock.Enabled = not unlocked
	end

	local nextInfo = Config.PenLevels[level + 1]
	if nextInfo then
		pen.upgradeLabel.Text = `Upgrade Pen\n<font size="20">Level {level} ➜ {level + 1}</font>\n<font color="#ff5555">${Config.format(nextInfo.cost)}</font>`
		pen.upgradePrompt.Enabled = true
		pen.upgradePrompt.ObjectText = `Pen ➜ Level {level + 1}`
		pen.upgradePrompt.ActionText = `Upgrade ${Config.format(nextInfo.cost)}`
	else
		pen.upgradeLabel.Text = "Pen MAXED!"
		pen.upgradePrompt.Enabled = false
	end

	if pen.treadmillKey ~= treadmillKey or pen.penStyle ~= levelInfo.style then
		pen.treadmillKey = treadmillKey
		pen.penStyle = levelInfo.style
		for _, info in pen.treadmills do
			info.model:Destroy()
		end
		table.clear(pen.treadmills)
		local mill = Config.TreadmillsByKey[treadmillKey] or Config.TreadmillsByKey.Wooden
		for i, millCf in pen.treadmillCfs do
			local model = place(Models.treadmill(mill.theme, levelInfo.style), millCf, pen.model)
			model.Name = "Treadmill" .. i
			pen.treadmills[i] = { model = model, belt = model:FindFirstChild("Belt") :: BasePart }
		end
	end
end

function World.setTreadmillText(pen, text: string)
	for _, info in pen.treadmills do
		local screen = info.model:FindFirstChild("Screen")
		local gui = screen and screen:FindFirstChild("ScreenGui")
		local label = gui and gui:FindFirstChild("Text")
		if label then
			(label :: TextLabel).Text = text
		end
	end
end

function World.assignPen(player: Player)
	for _, pen in World.pens do
		if not pen.owner then
			pen.owner = player
			pen.model:SetAttribute("OwnerUserId", player.UserId)
			pen.nameLabel.Text = `{player.DisplayName}'s Pen`
			return pen
		end
	end
	return nil
end

function World.releasePen(player: Player)
	teleportCooldown[player] = nil
	for _, pen in World.pens do
		if pen.owner == player then
			pen.owner = nil
			pen.model:SetAttribute("OwnerUserId", 0)
			pen.nameLabel.Text = "Empty Pen"
			pen.petFolder:ClearAllChildren()
			pen.eggFolder:ClearAllChildren()
			pen.shield.Transparency = 1
			pen.shieldLabel.Text = ""
			World.setPenLook(pen, 1, "Wooden")
			return
		end
	end
end

function World.getPen(player: Player)
	for _, pen in World.pens do
		if pen.owner == player then
			return pen
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------

local function lamp(parent, position: Vector3)
	local metal = c(55, 58, 66)
	part({ Name = "LampBase", Size = Vector3.new(1.6, 0.6, 1.6), CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	solid({ Name = "LampPole", Size = Vector3.new(0.6, 11, 0.6), CFrame = CFrame.new(position + Vector3.new(0, 5.8, 0)), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	local bulb = Models.ball(parent, "LampBulb", 1.8, position + Vector3.new(0, 12, 0), c(255, 235, 170), { Material = Enum.Material.Neon })
	part({ Name = "LampCap", Size = Vector3.new(2.4, 0.4, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 13.1, 0)), Color = metal, Material = Enum.Material.Metal, Parent = parent })
	local light = Instance.new("PointLight")
	light.Color = c(255, 225, 160)
	light.Range = 26
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = bulb
end

local function flowers(parent, rng: Random, center: Vector3, count: number)
	local colors = { c(255, 110, 150), c(255, 220, 70), c(160, 120, 255), c(255, 255, 255) }
	for _ = 1, count do
		local pos = center + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
		part({ Name = "Stem", Size = Vector3.new(0.2, 1, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)), Color = c(70, 160, 60), Parent = parent })
		Models.ball(parent, "Flower", 0.6, pos + Vector3.new(0, 1.1, 0), colors[rng:NextInteger(1, #colors)])
	end
end

local function buildLobby(parent: Instance)
	local lobby = folder("Lobby", parent)
	local half = World.CORRIDOR_HALF
	local minZ, maxZ = World.LOBBY_MIN_Z, World.CORRIDOR_START
	floorTiles(lobby, -half, half, minZ, maxZ, 25, c(110, 210, 70), c(102, 200, 64))

	local wallA, wallB = c(195, 135, 85), c(178, 120, 74)
	local h = World.WALL_HEIGHT
	checkerWall(lobby, Vector3.new(-half, 0, minZ), Vector3.new(half, 0, minZ), h, wallA, wallB)
	checkerWall(lobby, Vector3.new(-half, 0, minZ), Vector3.new(-half, 0, maxZ), h, wallA, wallB)
	checkerWall(lobby, Vector3.new(half, 0, minZ), Vector3.new(half, 0, maxZ), h, wallA, wallB)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, -120)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = lobby

	-- Centre aisle path between the pens.
	part({ Name = "Aisle", Size = Vector3.new(14, 0.1, maxZ - minZ - 10), CFrame = CFrame.new(0, 0.05, (minZ + maxZ) / 2 - 5), Color = c(215, 180, 120), Material = Enum.Material.Ground, Parent = lobby })

	-- SAFE ZONE line and floor sign just in front of the bases.
	part({ Name = "SafeLine", Size = Vector3.new(half * 2, 0.15, 1.2), CFrame = CFrame.new(0, 0.08, maxZ), Color = c(255, 70, 90), Material = Enum.Material.Neon, Parent = lobby })
	floorText(lobby, Vector3.new(0, 0.12, maxZ - 7), Vector2.new(56, 9), "🛡️ SAFE ZONE 🛡️", Color3.new(1, 1, 1))

	local center = Vector3.new(0, 0, -5)
	local function face(pos: Vector3): CFrame
		return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
	end

	local sell, sellPrompt = Models.stall("SELL", c(230, 35, 45), c(255, 60, 60))
	place(sell, face(Vector3.new(-50, 0, 12)), lobby)
	World.stalls.Sell = prompt(sellPrompt, "Sell", "Egg Stall", 0, 14)

	local trails, trailsPrompt = Models.stall("TRAILS SHOP", c(255, 210, 50), c(255, 220, 60))
	place(trails, face(Vector3.new(50, 0, 12)), lobby)
	World.stalls.Trails = prompt(trailsPrompt, "Browse", "Trails Shop", 0, 14)

	local mills, millsPrompt = Models.stall("TREADMILL SHOP", c(60, 160, 255), c(110, 200, 255))
	place(mills, face(Vector3.new(50, 0, -22)), lobby)
	World.stalls.Treadmills = prompt(millsPrompt, "Browse", "Treadmill Shop", 0, 14)

	local chest, chestPrompt = Models.chest()
	place(chest, face(Vector3.new(-50, 0, -22)), lobby)
	World.stalls.Gift = prompt(chestPrompt, "Open", "Free Gift", 0, 12)

	local rebirth, rebirthPrompt = Models.rebirthMachine()
	place(rebirth, CFrame.lookAt(Vector3.new(0, 0, 2), Vector3.new(0, 0, -60)), lobby)
	World.stalls.Rebirth = prompt(rebirthPrompt, "Rebirth", "Rebirth Machine", 0, 14)
	World.rebirthModel = rebirth

	local boardInfo = {
		{ key = "MoneyPerSec", title = "MOST MONEY/s", color = c(120, 255, 120), cf = CFrame.lookAt(Vector3.new(0, 0, minZ + 4), Vector3.new(0, 0, 0)) },
		{ key = "Speed", title = "FASTEST", color = c(120, 220, 255), cf = CFrame.lookAt(Vector3.new(-half + 5, 0, -6), Vector3.new(0, 0, -6)) },
		{ key = "Steals", title = "MOST STEALS", color = c(255, 120, 120), cf = CFrame.lookAt(Vector3.new(half - 5, 0, -6), Vector3.new(0, 0, -6)) },
	}
	for _, info in boardInfo do
		local board, list = Models.leaderboard(info.title, info.color)
		place(board, info.cf, lobby)
		World.boards[info.key] = list
	end

	-- Lamps along the aisle and flower beds around the shops.
	for z = minZ + 20, -40, 30 do
		lamp(lobby, Vector3.new(-9, 0, z))
		lamp(lobby, Vector3.new(9, 0, z))
	end
	local rng = Random.new(42)
	for _, pos in { Vector3.new(-30, 0, 22), Vector3.new(30, 0, 22), Vector3.new(-25, 0, -30), Vector3.new(25, 0, -30) } do
		flowers(lobby, rng, pos, 10)
	end
	for _, pos in { Vector3.new(-68, 0, 22), Vector3.new(68, 0, 22) } do
		place(Models.prop("tree", rng), CFrame.new(pos), lobby)
	end

	for i, info in PEN_CENTERS do
		World.pens[i] = buildPen(i, info, folder("PenSlot" .. i, parent))
	end
end

---------------------------------------------------------------------------
-- Biomes
---------------------------------------------------------------------------

local PROPS = {
	Forest = { "tree", "bush", "bush", "reeds", "tree", "rock" },
	Desert = { "cactus", "dune", "skull", "cactus", "rock", "pyramid" },
	Toxic = { "barrel", "sludge", "deadtree", "pipe", "barrel" },
	Farmlands = { "haybale", "fence", "crops", "haybale", "barn", "tree" },
	Enchanted = { "mushroom", "fairytree", "crystal", "mushroom" },
	Candylands = { "candycane", "lollipop", "gumdrop", "lollipop", "gumdrop" },
	Halloween = { "pumpkin", "grave", "deadtree", "pumpkin", "grave" },
}

local PROP_TINTS = {
	Enchanted = c(200, 120, 255),
	Halloween = c(60, 50, 60),
}

-- One big nest per biome holding Config.EggsPerNest eggs, with its guardian asleep beside it.
local function buildNest(biome, parent, center: Vector3, side: number)
	local nestScale = 2.4
	local nest = Models.nest()
	nest:ScaleTo(nestScale)
	place(nest, CFrame.new(center), parent)
	nest.Name = "BiomeNest"
	local spots = {}
	local count = Config.EggsPerNest
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 + math.pi / 2
		local radius = if count == 1 then 0 else 2.3
		table.insert(spots, CFrame.new(center + Vector3.new(math.cos(angle) * radius, 0.95, math.sin(angle) * radius)))
	end
	table.insert(biome.clusters, {
		center = center,
		home = center + Vector3.new(-side * 13, 0, 2),
		nests = spots,
	})
end

local function decorate(biome, parent, rng: Random, avoid: { Vector3 })
	local list = PROPS[biome.key]
	local tint = PROP_TINTS[biome.key]
	local placed = 0
	local tries = 0
	while placed < 12 and tries < 150 do
		tries += 1
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(46, World.CORRIDOR_HALF - 8)
		local z = rng:NextNumber(biome.zStart + 18, biome.zEnd - 10)
		local pos = Vector3.new(x, 0, z)
		local clear = true
		for _, a in avoid do
			if (a - pos).Magnitude < 24 then
				clear = false
				break
			end
		end
		if clear then
			local kind = list[rng:NextInteger(1, #list)]
			if kind == "barn" or kind == "pyramid" then
				pos = Vector3.new(side * (World.CORRIDOR_HALF - 16), 0, z)
			end
			place(Models.prop(kind, rng, tint), CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), parent)
			table.insert(avoid, pos)
			placed += 1
		end
	end
end

local function biomeSign(parent, biome, zStart: number)
	solid({ Name = "SignPost", Size = Vector3.new(0.8, 6, 0.8), CFrame = CFrame.new(-58, 3, zStart + 12), Color = c(110, 70, 40), Material = Enum.Material.Wood, Parent = parent })
	local board = solid({ Name = "Sign", Size = Vector3.new(6, 3.4, 0.4), CFrame = CFrame.new(-58, 6.5, zStart + 12) * CFrame.Angles(0, rad(180), 0), Color = c(235, 130, 40), Material = Enum.Material.Wood, Parent = parent })
	local text = if biome.recommended > 0 then `⚡ {Config.format(biome.recommended)}\nrecommended` else "⚡ Start here!"
	surfaceText(board, Enum.NormalId.Front, text, Color3.new(1, 1, 1), 40)
end

local function buildBiome(parent, biome, order: number)
	local bf = folder(biome.key, parent)
	floorTiles(bf, -World.CORRIDOR_HALF, World.CORRIDOR_HALF, biome.zStart, biome.zEnd, 40, biome.def.floor, biome.def.floorAlt)
	checkerWall(bf, Vector3.new(-World.CORRIDOR_HALF, 0, biome.zStart), Vector3.new(-World.CORRIDOR_HALF, 0, biome.zEnd), World.WALL_HEIGHT, biome.def.wall, biome.def.wallAlt)
	checkerWall(bf, Vector3.new(World.CORRIDOR_HALF, 0, biome.zStart), Vector3.new(World.CORRIDOR_HALF, 0, biome.zEnd), World.WALL_HEIGHT, biome.def.wall, biome.def.wallAlt)

	if order > 1 then
		part({ Name = "Divider", Size = Vector3.new(World.CORRIDOR_HALF * 2, 0.12, 1.2), CFrame = CFrame.new(0, 0.06, biome.zStart), Color = biome.def.wallAlt:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon, Parent = bf })
	end
	local banner = part({ Name = "Banner", Size = Vector3.one, CFrame = CFrame.new(0, 22, biome.zStart + 8), Transparency = 1, Parent = bf })
	Models.billboard(banner, `{biome.def.name} {biome.def.emoji}`, Color3.new(1, 1, 1), UDim2.fromScale(40, 8), Vector3.zero, 700)
	biomeSign(bf, biome.def, biome.zStart)

	local side = if order % 2 == 0 then 1 else -1
	buildNest(biome, bf, Vector3.new(side * 26, 0, biome.zStart + 90), side)
	local avoid = {}
	for _, cl in biome.clusters do
		table.insert(avoid, cl.center)
		table.insert(avoid, cl.home)
	end
	if biome.key == "Forest" then
		table.insert(avoid, Vector3.new(-World.CORRIDOR_HALF + 8, 0, biome.zStart + 40))
	end
	if biome.key == "Halloween" then
		local tent = Models.prop("clowntent", Random.new(1))
		place(tent, CFrame.new(0, 0, biome.zEnd - 30), bf)
		table.insert(avoid, Vector3.new(0, 0, biome.zEnd - 30))
	end
	decorate(biome, bf, Random.new(biome.index * 1013), avoid)
end

---------------------------------------------------------------------------
-- The cave: a small entrance in the Forest wall, and the boss dungeon
---------------------------------------------------------------------------

local function buildCaveEntrance(parent, z: number)
	local cave = folder("CaveEntrance", parent)
	local wallX = -World.CORRIDOR_HALF + 2
	local rock, rockDark = c(110, 100, 95), c(80, 74, 72)
	local rng = Random.new(7)
	-- Rocky mound bulging out of the dirt wall around a dark opening.
	for i = 0, 10 do
		local angle = rad(-10 + i * 20)
		local size = rng:NextNumber(5, 8)
		solid({
			Name = "CaveRock",
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(wallX + 4, 0, z) * CFrame.new(0, math.sin(angle) * 11, math.cos(angle) * 11) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 1), rng:NextNumber(0, 1)),
			Color = if i % 2 == 0 then rock else rockDark,
			Material = Enum.Material.Slate,
			Parent = cave,
		})
	end
	part({ Name = "CaveDark", Size = Vector3.new(4, 13, 13), CFrame = CFrame.new(wallX + 1, 6.5, z), Color = c(15, 12, 18), Parent = cave })
	for _, dz in { -9, 9 } do
		local torch = Models.ball(cave, "Torch", 1.2, Vector3.new(wallX + 6, 9, z + dz), c(255, 150, 40), { Material = Enum.Material.Neon })
		part({ Name = "TorchStick", Size = Vector3.new(0.4, 2.5, 0.4), CFrame = CFrame.new(wallX + 6, 7.4, z + dz), Color = c(90, 60, 40), Parent = cave })
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 6
		fire.Parent = torch
		local light = Instance.new("PointLight")
		light.Color = c(255, 150, 60)
		light.Range = 16
		light.Parent = torch
	end
	local signAnchor = part({ Name = "CaveSign", Size = Vector3.one, CFrame = CFrame.new(wallX + 5, 17, z), Transparency = 1, Parent = cave })
	Models.billboard(signAnchor, "⚔️ Golem King's Cave", c(255, 150, 70), UDim2.fromScale(16, 3), Vector3.zero, 300)

	local outside = CFrame.lookAt(Vector3.new(wallX + 16, 4, z), Vector3.new(wallX + 30, 4, z))
	World.dungeon = World.dungeon or {}
	World.dungeon.outside = outside
	teleporter(cave, CFrame.new(wallX + 3.6, 6.5, z) * CFrame.Angles(0, rad(90), 0), c(170, 90, 255), function()
		return World.dungeon.inside
	end)
end

local function buildDungeon(parent)
	local d = folder("Dungeon", parent)
	local o = DUNGEON_ORIGIN
	local rock, rockDark = c(85, 80, 90), c(62, 58, 68)
	part({ Name = "DungeonFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, DUNGEON_RADIUS * 2 + 8, DUNGEON_RADIUS * 2 + 8), CFrame = CFrame.new(o + Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, rad(90)), Color = c(70, 64, 76), Material = Enum.Material.Slate, CanCollide = true, CanQuery = true, Parent = d })
	part({ Name = "DungeonCeiling", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, DUNGEON_RADIUS * 2 + 8, DUNGEON_RADIUS * 2 + 8), CFrame = CFrame.new(o + Vector3.new(0, 36, 0)) * CFrame.Angles(0, 0, rad(90)), Color = rockDark, Material = Enum.Material.Slate, CanCollide = true, Parent = d })

	-- Outer circular wall with torches.
	local segments = 28
	for i = 0, segments - 1 do
		local angle = (i + 0.5) / segments * math.pi * 2
		local pos = o + Vector3.new(math.cos(angle) * (DUNGEON_RADIUS + 2), 17, math.sin(angle) * (DUNGEON_RADIUS + 2))
		solid({ Name = "DungeonWall", Size = Vector3.new(4, 36, DUNGEON_RADIUS * 2 * math.pi / segments + 1), CFrame = CFrame.new(pos) * CFrame.Angles(0, -angle, 0), Color = if i % 2 == 0 then rock else rockDark, Material = Enum.Material.Slate, Parent = d })
		if i % 4 == 0 then
			local torchPos = o + Vector3.new(math.cos(angle) * (DUNGEON_RADIUS - 0.5), 10, math.sin(angle) * (DUNGEON_RADIUS - 0.5))
			local torch = Models.ball(d, "Torch", 1.4, torchPos, c(255, 150, 40), { Material = Enum.Material.Neon })
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Heat = 7
			fire.Parent = torch
			local light = Instance.new("PointLight")
			light.Color = c(255, 150, 60)
			light.Range = 28
			light.Brightness = 1.8
			light.Parent = torch
		end
	end

	-- Boss arena in the middle: a glowing rune circle with a low rim and four openings.
	local center = o
	World.arena = { center = center, radius = ARENA_RADIUS }
	part({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, ARENA_RADIUS * 2, ARENA_RADIUS * 2), CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, rad(90)), Color = c(60, 45, 85), Material = Enum.Material.Slate, Parent = d })
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		part({ Name = "Rune", Size = Vector3.new(2, 0.1, 7), CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * ARENA_RADIUS * 0.6, 0.3, math.sin(angle) * ARENA_RADIUS * 0.6)) * CFrame.Angles(0, -angle, 0), Color = c(255, 120, 40), Material = Enum.Material.Neon, Parent = d })
	end
	local rimSegments = 24
	for i = 0, rimSegments - 1 do
		local angle = (i + 0.5) / rimSegments * math.pi * 2
		local gap = math.abs(math.cos(angle * 2)) > 0.92
		if not gap then
			local pos = center + Vector3.new(math.cos(angle) * ARENA_RADIUS, 2.5, math.sin(angle) * ARENA_RADIUS)
			solid({ Name = "Rim", Size = Vector3.new(3, 5 + (i % 3), ARENA_RADIUS * 2 * math.pi / rimSegments + 1), CFrame = CFrame.new(pos) * CFrame.Angles(0, -angle, 0), Color = if i % 2 == 0 then rock else rockDark, Material = Enum.Material.Slate, Parent = d })
		end
	end
	local rng = Random.new(77)
	for i = 0, 11 do
		local angle = (i + 0.5) / 12 * math.pi * 2
		local r = rng:NextNumber(46, 56)
		place(Models.prop("crystal", rng, if i % 2 == 0 then c(120, 220, 255) else c(200, 120, 255)), CFrame.new(center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)), d)
	end

	-- Way in and way out.
	local exitPos = o + Vector3.new(-DUNGEON_RADIUS + 3, 0, 0)
	World.dungeon = World.dungeon or {}
	World.dungeon.inside = CFrame.lookAt(exitPos + Vector3.new(12, 4, 0), center + Vector3.new(0, 4, 0))
	teleporter(d, CFrame.new(exitPos + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, rad(90), 0), c(120, 255, 140), function()
		return World.dungeon.outside
	end)
	local exitSign = part({ Name = "ExitSign", Size = Vector3.one, CFrame = CFrame.new(exitPos + Vector3.new(2, 15, 0)), Transparency = 1, Parent = d })
	Models.billboard(exitSign, "🚪 Exit", c(140, 255, 150), UDim2.fromScale(8, 2.5), Vector3.zero, 200)
end

local function buildCorridor(parent)
	local corridor = folder("Biomes", parent)
	local z = World.CORRIDOR_START
	local order = 0
	for i, def in Config.Biomes do
		if not def.dungeon and (not def.seasonal or Config.HalloweenEnabled) then
			order += 1
			local biome = {
				index = i,
				key = def.key,
				def = def,
				zStart = z,
				zEnd = z + World.BIOME_LENGTH,
				clusters = {},
			}
			table.insert(World.biomes, biome)
			buildBiome(corridor, biome, order)
			if def.key == "Forest" then
				buildCaveEntrance(corridor, z + 40)
			end
			z += World.BIOME_LENGTH
		end
	end
	World.corridorEnd = z
	checkerWall(corridor, Vector3.new(-World.CORRIDOR_HALF, 0, z), Vector3.new(World.CORRIDOR_HALF, 0, z), World.WALL_HEIGHT, c(40, 30, 50), c(255, 120, 20))
	buildDungeon(parent)
end

function World.biomeAt(position: Vector3)
	if math.abs(position.X) > World.CORRIDOR_HALF + 2 then
		return nil
	end
	for _, biome in World.biomes do
		if position.Z >= biome.zStart and position.Z < biome.zEnd then
			return biome
		end
	end
	return nil
end

function World.getBiome(index: number)
	for _, biome in World.biomes do
		if biome.index == index then
			return biome
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Day / night
---------------------------------------------------------------------------

local DAY = { ClockTime = 14, Brightness = 2.4, Ambient = c(140, 140, 150), OutdoorAmbient = c(155, 155, 160) }
local NIGHT = { ClockTime = 0.2, Brightness = 1.2, Ambient = c(70, 70, 120), OutdoorAmbient = c(80, 85, 130) }

function World.isNight(): boolean
	return night
end

local function setNight(value: boolean, duration: number)
	night = value
	workspace:SetAttribute("IsNight", value)
	workspace:SetAttribute("CycleEnds", workspace:GetServerTimeNow() + duration)
	TweenService:Create(Lighting, TweenInfo.new(4), if value then NIGHT else DAY):Play()
	cycleEvent:Fire(value)
end

function World.forceNight()
	setNight(true, Config.NightSeconds)
	World.cycleEnds = os.clock() + Config.NightSeconds
end

local function runCycle()
	setNight(false, Config.DaySeconds)
	World.cycleEnds = os.clock() + Config.DaySeconds
	while true do
		task.wait(1)
		if os.clock() >= World.cycleEnds then
			local nextNight = not night
			local duration = if nextNight then Config.NightSeconds else Config.DaySeconds
			setNight(nextNight, duration)
			World.cycleEnds = os.clock() + duration
		end
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function World.init(context)
	ctx = context
	Config = ctx.Config
	Models = ctx.Models
	part = Models.part
end

function World.build()
	mapFolder = folder("Map", workspace)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ShadowSoftness = 0.3
	Lighting.FogEnd = 2200
	Lighting.FogStart = 700
	Lighting.FogColor = c(190, 225, 255)

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Haze = 0.5
	atmosphere.Glare = 0.2
	atmosphere.Color = c(200, 225, 255)
	atmosphere.Decay = c(110, 140, 180)
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.06
	cc.Parent = Lighting

	buildLobby(mapFolder)
	buildCorridor(mapFolder)
end

function World.start()
	task.spawn(runCycle)
	Players.PlayerRemoving:Connect(function(player)
		teleportCooldown[player] = nil
	end)
end

return World

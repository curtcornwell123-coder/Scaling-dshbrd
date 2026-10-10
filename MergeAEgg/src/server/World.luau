-- Merge A Egg: builds the map and runs the day/night cycle.
-- Layout: a lobby with 6 pens and shops, a SAFE ZONE line, then one long corridor
-- split into biome stages, ending at the Halloween clown tent.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local World = {}

local ctx
local Config
local Models

local c = Color3.fromRGB
local rad = math.rad

World.CORRIDOR_START = 120
World.BIOME_LENGTH = 320
World.CORRIDOR_HALF = 75
World.WALL_HEIGHT = 60
World.LOBBY_HALF_X = 240
World.LOBBY_MIN_Z = -190

local PEN_WIDTH = 70 -- local X
local PEN_DEPTH = 80 -- local Z (front at -Z faces the hub)
local PEN_CENTERS = {
	{ pos = Vector3.new(-170, 0, -130), face = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(-170, 0, -40), face = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(-170, 0, 50), face = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(170, 0, -130), face = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(170, 0, -40), face = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(170, 0, 50), face = Vector3.new(-1, 0, 0) },
}

World.pens = {}
World.biomes = {}
World.stalls = {}
World.boards = {}
World.arena = nil

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

-- Checkered wall: alternating coloured columns with studs, like the reference.
local function checkerWall(parent, from: Vector3, to: Vector3, height: number, colorA: Color3, colorB: Color3, thickness: number?)
	local dir = to - from
	local length = dir.Magnitude
	local count = math.max(1, math.floor(length / 20))
	local step = length / count
	local unit = dir.Unit
	for i = 0, count - 1 do
		local center = from + unit * (step * (i + 0.5)) + Vector3.new(0, height / 2, 0)
		solid({
			Name = "Wall",
			Size = Vector3.new(thickness or 4, height, step),
			CFrame = CFrame.lookAt(center, center + unit),
			Color = if i % 2 == 0 then colorA else colorB,
			Material = Enum.Material.Plastic,
			TopSurface = Enum.SurfaceType.Studs,
			LeftSurface = Enum.SurfaceType.Studs,
			RightSurface = Enum.SurfaceType.Studs,
			Parent = parent,
		})
	end
end

local function floorTiles(parent, minX, maxX, minZ, maxZ, tile, colorA, colorB, material)
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
				Material = material or Enum.Material.Plastic,
				TopSurface = Enum.SurfaceType.Studs,
				Parent = parent,
			})
		end
	end
end

---------------------------------------------------------------------------
-- Pens
---------------------------------------------------------------------------

local function nestSlotLocal(slot: number): Vector3
	local row = (slot - 1) // 5
	local col = (slot - 1) % 5
	return Vector3.new(-24 + col * 12, 0, 16 + row * 14)
end

local function buildFence(pen)
	local model = Instance.new("Model")
	model.Name = "Fence"
	local half = Vector3.new(PEN_WIDTH / 2, 0, PEN_DEPTH / 2)
	local segments = {
		{ Vector3.new(-half.X, 0, -half.Z), Vector3.new(-9, 0, -half.Z) },
		{ Vector3.new(9, 0, -half.Z), Vector3.new(half.X, 0, -half.Z) },
		{ Vector3.new(half.X, 0, -half.Z), Vector3.new(half.X, 0, half.Z) },
		{ Vector3.new(half.X, 0, half.Z), Vector3.new(-half.X, 0, half.Z) },
		{ Vector3.new(-half.X, 0, half.Z), Vector3.new(-half.X, 0, -half.Z) },
	}
	pen.trimParts = {}
	for _, seg in segments do
		local a, b = seg[1], seg[2]
		local length = (b - a).Magnitude
		local posts = math.max(1, math.floor(length / 8))
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
		end
		for _, y in { 1.4, 3.0 } do
			local mid = (a + b) / 2 + Vector3.new(0, y, 0)
			local rail = solid({
				Name = "Rail",
				Size = Vector3.new(0.5, 0.5, length),
				CFrame = pen.cframe * CFrame.lookAt(mid, mid + (b - a)),
				Color = c(170, 105, 55),
				Material = Enum.Material.Wood,
				Parent = model,
			})
			table.insert(pen.trimParts, rail)
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
		Color = c(120, 215, 80),
		Material = Enum.Material.Plastic,
		TopSurface = Enum.SurfaceType.Studs,
		Parent = model,
	})
	buildFence(pen)

	-- Nest slots (locked ones are dimmed until the pen is upgraded).
	local nests = Instance.new("Folder")
	nests.Name = "Nests"
	nests.Parent = model
	for slot = 1, Config.MaxNests do
		local slotCf = cf * CFrame.new(nestSlotLocal(slot) + Vector3.new(0, 0.4, 0))
		local nest = place(Models.nest(), slotCf, nests)
		nest.Name = "Nest" .. slot
		local anchor = part({ Name = "EggAnchor", Size = Vector3.one * 0.5, CFrame = slotCf * CFrame.new(0, 0.5, 0), Transparency = 1, Parent = nest })
		local lockGui = Models.billboard(anchor, "🔒", Color3.new(1, 1, 1), UDim2.fromScale(2.5, 2.5), Vector3.new(0, 2, 0), 80)
		lockGui.Name = "Lock"
		pen.nestSlots[slot] = { cf = slotCf * CFrame.new(0, 0.5, 0), model = nest, anchor = anchor, lock = lockGui }
	end

	-- Pet area where equipped pets wander.
	pen.petArea = { cf = cf * CFrame.new(0, 0.4, 1), size = Vector3.new(56, 0, 12) }
	local petFolder = Instance.new("Folder")
	petFolder.Name = "Pets"
	petFolder.Parent = model
	pen.petFolder = petFolder
	local eggFolder = Instance.new("Folder")
	eggFolder.Name = "Eggs"
	eggFolder.Parent = model
	pen.eggFolder = eggFolder

	-- Treadmill spots (models are swapped in by World.setPenLook).
	pen.treadmillCfs = { cf * CFrame.new(-25, 0.4, -16), cf * CFrame.new(-14.5, 0.4, -16) }

	-- Fuse Machine.
	pen.fuseCf = cf * CFrame.new(21, 0.4, -18)
	pen.fuse = place(Models.fuseMachine(), pen.fuseCf, model)
	local fusePromptPart = pen.fuse:FindFirstChild("Pod2") :: BasePart
	pen.fusePrompt = prompt(fusePromptPart, "Insert Egg", "Fuse Machine", 0, 12)
	pen.fuseEjectPrompt = prompt(pen.fuse.PrimaryPart :: BasePart, "Take Eggs Out", "Fuse Machine", 1, 10)
	pen.fuseEjectPrompt.KeyboardKeyCode = Enum.KeyCode.F
	pen.fuseEjectPrompt.UIOffset = Vector2.new(0, 80)

	-- Upgrade sign on the front fence.
	local signPost = solid({ Name = "SignPost", Size = Vector3.new(0.6, 5, 0.6), CFrame = cf * CFrame.new(16, 2.5, -PEN_DEPTH / 2 - 0.5), Color = c(90, 60, 40), Material = Enum.Material.Wood, Parent = model })
	local sign = solid({ Name = "UpgradeSign", Size = Vector3.new(7, 3.6, 0.4), CFrame = cf * CFrame.new(16, 5.6, -PEN_DEPTH / 2 - 0.5), Color = c(30, 30, 40), Parent = model })
	pen.upgradeLabel = surfaceText(sign, Enum.NormalId.Front, "Upgrade Pen", Color3.new(1, 1, 1), 40)
	pen.upgradeLabel.RichText = true
	pen.upgradePrompt = prompt(signPost, "Upgrade", "Pen", 0, 12)

	-- Owner name over the entrance and the steal shield.
	local namePart = part({ Name = "NameAnchor", Size = Vector3.one, CFrame = cf * CFrame.new(0, 12, -PEN_DEPTH / 2), Transparency = 1, Parent = model })
	local _, nameLabel = Models.billboard(namePart, "Empty Pen", Color3.new(1, 1, 1), UDim2.fromScale(18, 3), Vector3.new(0, 0, 0), 250)
	pen.nameLabel = nameLabel
	pen.shield = part({
		Name = "Shield",
		Size = Vector3.new(PEN_WIDTH + 2, 26, PEN_DEPTH + 2),
		CFrame = cf * CFrame.new(0, 13, 0),
		Color = c(80, 190, 255),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		Parent = model,
	})
	local _, shieldLabel = Models.billboard(pen.shield, "", c(120, 210, 255), UDim2.fromScale(16, 3), Vector3.new(0, 16, 0), 200)
	pen.shieldLabel = shieldLabel

	pen.spawnCf = cf * CFrame.new(0, 4, -28)
	pen.nestZone = { cf = cf * CFrame.new(0, 5, 23), size = Vector3.new(PEN_WIDTH - 4, 14, 26) }
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
		if p.Name == "Post" then
			p.Color = trim.color
			p.Material = trim.material
		end
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

local function buildLobby(parent: Instance)
	local lobby = folder("Lobby", parent)
	local minX, maxX = -World.LOBBY_HALF_X, World.LOBBY_HALF_X
	local minZ, maxZ = World.LOBBY_MIN_Z, World.CORRIDOR_START
	floorTiles(lobby, minX, maxX, minZ, maxZ, 40, c(110, 210, 70), c(100, 200, 62))

	local wallA, wallB = c(195, 135, 85), c(178, 120, 74)
	local h = World.WALL_HEIGHT
	checkerWall(lobby, Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ), h, wallA, wallB)
	checkerWall(lobby, Vector3.new(minX, 0, minZ), Vector3.new(minX, 0, maxZ), h, wallA, wallB)
	checkerWall(lobby, Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, maxZ), h, wallA, wallB)
	checkerWall(lobby, Vector3.new(minX, 0, maxZ), Vector3.new(-World.CORRIDOR_HALF, 0, maxZ), h, wallA, wallB)
	checkerWall(lobby, Vector3.new(World.CORRIDOR_HALF, 0, maxZ), Vector3.new(maxX, 0, maxZ), h, wallA, wallB)
	-- Grass trim on top of every wall, like the reference.
	for _, w in lobby:GetChildren() do
		if w.Name == "Wall" and w:IsA("BasePart") then
			part({ Name = "WallGrass", Size = Vector3.new(w.Size.X + 0.4, 1.2, w.Size.Z + 0.2), CFrame = w.CFrame * CFrame.new(0, w.Size.Y / 2 + 0.6, 0), Color = c(90, 200, 60), Material = Enum.Material.Grass, Parent = lobby })
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, -100)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = c(120, 220, 90)
	spawn.Material = Enum.Material.Plastic
	spawn.TopSurface = Enum.SurfaceType.Studs
	spawn.Parent = lobby

	-- Safe zone line and floor text.
	part({ Name = "SafeLine", Size = Vector3.new(World.CORRIDOR_HALF * 2, 0.15, 1.2), CFrame = CFrame.new(0, 0.08, World.CORRIDOR_START - 2), Color = c(255, 70, 90), Material = Enum.Material.Neon, Parent = lobby })
	local safeText = part({ Name = "SafeText", Size = Vector3.new(70, 0.1, 14), CFrame = CFrame.new(0, 0.06, World.CORRIDOR_START - 14), Transparency = 1, Parent = lobby })
	local label = surfaceText(safeText, Enum.NormalId.Top, "🛡️ SAFE ZONE 🛡️", Color3.new(1, 1, 1), 12)
	label.Rotation = 180

	local center = Vector3.new(0, 0, -30)
	local function face(pos: Vector3): CFrame
		return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
	end

	local sell, sellPrompt = Models.stall("SELL", c(230, 35, 45), c(255, 60, 60))
	place(sell, face(Vector3.new(-45, 0, 92)), lobby)
	World.stalls.Sell = prompt(sellPrompt, "Sell", "Egg Stall", 0, 14)

	local trails, trailsPrompt = Models.stall("TRAILS SHOP", c(255, 210, 50), c(255, 220, 60))
	place(trails, face(Vector3.new(45, 0, 92)), lobby)
	World.stalls.Trails = prompt(trailsPrompt, "Browse", "Trails Shop", 0, 14)

	local mills, millsPrompt = Models.stall("TREADMILL SHOP", c(60, 160, 255), c(110, 200, 255))
	place(mills, face(Vector3.new(92, 0, 30)), lobby)
	World.stalls.Treadmills = prompt(millsPrompt, "Browse", "Treadmill Shop", 0, 14)

	local chest, chestPrompt = Models.chest()
	place(chest, face(Vector3.new(-92, 0, 30)), lobby)
	World.stalls.Gift = prompt(chestPrompt, "Open", "Free Gift", 0, 12)

	local rebirth, rebirthPrompt = Models.rebirthMachine()
	place(rebirth, CFrame.lookAt(Vector3.new(0, 0, 10), Vector3.new(0, 0, -60)), lobby)
	World.stalls.Rebirth = prompt(rebirthPrompt, "Rebirth", "Rebirth Machine", 0, 14)
	World.rebirthModel = rebirth

	local boardInfo = {
		{ key = "MoneyPerSec", title = "MOST MONEY/s", color = c(120, 255, 120), x = -50 },
		{ key = "Speed", title = "FASTEST", color = c(120, 220, 255), x = 0 },
		{ key = "Steals", title = "MOST STEALS", color = c(255, 120, 120), x = 50 },
	}
	for _, info in boardInfo do
		local board, list = Models.leaderboard(info.title, info.color)
		place(board, CFrame.lookAt(Vector3.new(info.x, 0, World.LOBBY_MIN_Z + 12), Vector3.new(info.x, 0, 0)), lobby)
		World.boards[info.key] = list
	end

	-- Hint banner like the reference.
	local hint = part({ Name = "Hint", Size = Vector3.one, CFrame = CFrame.new(0, 34, -40), Transparency = 1, Parent = lobby })
	Models.billboard(hint, "Upgrade your Pen!", Color3.new(1, 1, 1), UDim2.fromScale(40, 6), Vector3.zero, 400)

	for i, info in PEN_CENTERS do
		World.pens[i] = buildPen(i, info, folder("PenSlot" .. i, parent))
	end
end

---------------------------------------------------------------------------
-- Biomes
---------------------------------------------------------------------------

local PROPS = {
	Forest = { "tree", "bush", "bush", "reeds", "tree", "rock" },
	Cave = { "rock", "crystal", "rock", "crystal" },
	Desert = { "cactus", "dune", "skull", "cactus", "rock", "pyramid" },
	Toxic = { "barrel", "sludge", "deadtree", "pipe", "barrel" },
	Farmlands = { "haybale", "fence", "crops", "haybale", "barn", "tree" },
	Enchanted = { "mushroom", "fairytree", "crystal", "mushroom" },
	Candylands = { "candycane", "lollipop", "gumdrop", "lollipop", "gumdrop" },
	Halloween = { "pumpkin", "grave", "deadtree", "pumpkin", "grave" },
}

local PROP_TINTS = {
	Cave = c(90, 85, 95),
	Enchanted = c(200, 120, 255),
	Halloween = c(60, 50, 60),
}

local function cluster(biome, center: Vector3)
	local nests = {}
	for _, offset in { Vector3.new(-7, 0, -4), Vector3.new(7, 0, -4), Vector3.new(0, 0, 6) } do
		table.insert(nests, CFrame.new(center + offset))
	end
	table.insert(biome.clusters, { center = center, home = center + Vector3.new(0, 0, -14), nests = nests })
end

local function decorate(biome, parent, rng: Random, avoid: { Vector3 })
	local list = PROPS[biome.key]
	local tint = PROP_TINTS[biome.key]
	local placed = 0
	local tries = 0
	while placed < 22 and tries < 200 do
		tries += 1
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(48, World.CORRIDOR_HALF - 8)
		local z = rng:NextNumber(biome.zStart + 20, biome.zEnd - 15)
		local pos = Vector3.new(x, 0, z)
		local clear = true
		for _, a in avoid do
			if (a - pos).Magnitude < 26 then
				clear = false
				break
			end
		end
		if clear then
			local kind = list[rng:NextInteger(1, #list)]
			if kind == "barn" or kind == "pyramid" then
				pos = Vector3.new(side * (World.CORRIDOR_HALF - 16), 0, z)
			end
			local model = Models.prop(kind, rng, tint)
			place(model, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), parent)
			table.insert(avoid, pos)
			placed += 1
		end
	end
end

local function biomeSign(parent, biome, zStart: number)
	solid({ Name = "SignPost", Size = Vector3.new(0.8, 6, 0.8), CFrame = CFrame.new(-58, 3, zStart + 14), Color = c(110, 70, 40), Material = Enum.Material.Wood, Parent = parent })
	local board = solid({ Name = "Sign", Size = Vector3.new(6, 3.4, 0.4), CFrame = CFrame.new(-58, 6.5, zStart + 14) * CFrame.Angles(0, rad(180), 0), Color = c(235, 130, 40), Material = Enum.Material.Wood, Parent = parent })
	local text = if biome.recommended > 0 then `⚡ {Config.format(biome.recommended)}\nrecommended` else "⚡ Start here!"
	surfaceText(board, Enum.NormalId.Front, text, Color3.new(1, 1, 1), 40)
end

local function buildCave(parent, biome)
	local zMid = (biome.zStart + biome.zEnd) / 2
	local rock, rockDark = c(85, 80, 90), c(65, 60, 70)
	local height = 46
	-- Mountain shell: roof and tunnelled front/back faces.
	solid({ Name = "Roof", Size = Vector3.new(World.CORRIDOR_HALF * 2 + 8, 6, World.BIOME_LENGTH), CFrame = CFrame.new(0, height + 3, zMid), Color = rockDark, Material = Enum.Material.Slate, Parent = parent })
	for _, z in { biome.zStart, biome.zEnd } do
		for _, side in { -1, 1 } do
			local width = World.CORRIDOR_HALF - 13
			solid({ Name = "Face", Size = Vector3.new(width, height, 8), CFrame = CFrame.new(side * (13 + width / 2), height / 2, z), Color = rock, Material = Enum.Material.Slate, Parent = parent })
		end
		solid({ Name = "TunnelTop", Size = Vector3.new(26, height - 18, 8), CFrame = CFrame.new(0, 18 + (height - 18) / 2, z), Color = rock, Material = Enum.Material.Slate, Parent = parent })
		for i = 0, 6 do
			local angle = i / 6 * math.pi
			part({ Name = "Arch", Size = Vector3.new(4, 4, 9), CFrame = CFrame.new(math.cos(angle) * 13, 14 + math.sin(angle) * 4, z), Color = rockDark, Material = Enum.Material.Slate, Parent = parent })
		end
		-- Peaks above the face give it a mountain silhouette from the lobby.
		for i = -3, 3 do
			local peakH = 18 - math.abs(i) * 4 + (i % 2) * 3
			local peak = Instance.new("WedgePart")
			peak.Name = "Peak"
			peak.Anchored = true
			peak.Size = Vector3.new(20, peakH, 10)
			peak.CFrame = CFrame.new(i * 20, height + peakH / 2, z) * CFrame.Angles(0, if i < 0 then rad(-90) else rad(90), 0)
			peak.Color = if i % 2 == 0 then rock else rockDark
			peak.Material = Enum.Material.Slate
			peak.TopSurface = Enum.SurfaceType.Smooth
			peak.BottomSurface = Enum.SurfaceType.Smooth
			peak.Parent = parent
		end
	end

	-- Boss arena in the middle with a rim you walk around.
	local radius = 32
	local center = Vector3.new(0, 0, zMid)
	World.arena = { center = center, radius = radius }
	part({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, radius * 2, radius * 2), CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, rad(90)), Color = c(60, 45, 85), Material = Enum.Material.Slate, Parent = parent })
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		part({ Name = "Rune", Size = Vector3.new(2, 0.1, 6), CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * radius * 0.6, 0.3, math.sin(angle) * radius * 0.6)) * CFrame.Angles(0, -angle, 0), Color = c(255, 120, 40), Material = Enum.Material.Neon, Parent = parent })
	end
	local segments = 20
	for i = 0, segments - 1 do
		local angle = (i + 0.5) / segments * math.pi * 2
		local gap = math.abs(math.cos(angle)) > 0.94 -- openings on the left and right
		if not gap then
			local pos = center + Vector3.new(math.cos(angle) * radius, 4, math.sin(angle) * radius)
			solid({ Name = "Rim", Size = Vector3.new(4, 8 + (i % 3), radius * 2 * math.pi / segments + 1), CFrame = CFrame.new(pos) * CFrame.Angles(0, -angle, 0), Color = if i % 2 == 0 then rock else rockDark, Material = Enum.Material.Slate, Parent = parent })
		end
	end
	local rng = Random.new(77)
	for i = 0, 15 do
		local angle = i / 16 * math.pi * 2
		local r = rng:NextNumber(60, 70)
		local model = Models.prop("crystal", rng, if i % 2 == 0 then c(120, 220, 255) else c(200, 120, 255))
		place(model, CFrame.new(center + Vector3.new(math.cos(angle) * r, 0, math.clamp(math.sin(angle) * r, -150, 150))), parent)
	end

	cluster(biome, Vector3.new(-56, 0, zMid - 34))
	cluster(biome, Vector3.new(56, 0, zMid + 34))
	biome.clusters[1].home = Vector3.new(-56, 0, zMid - 50)
	biome.clusters[2].home = Vector3.new(56, 0, zMid + 50)
end

local function buildBiome(parent, biome)
	local bf = folder(biome.key, parent)
	floorTiles(bf, -World.CORRIDOR_HALF, World.CORRIDOR_HALF, biome.zStart, biome.zEnd, 40, biome.def.floor, biome.def.floorAlt)
	checkerWall(bf, Vector3.new(-World.CORRIDOR_HALF, 0, biome.zStart), Vector3.new(-World.CORRIDOR_HALF, 0, biome.zEnd), World.WALL_HEIGHT, biome.def.wall, biome.def.wallAlt)
	checkerWall(bf, Vector3.new(World.CORRIDOR_HALF, 0, biome.zStart), Vector3.new(World.CORRIDOR_HALF, 0, biome.zEnd), World.WALL_HEIGHT, biome.def.wall, biome.def.wallAlt)

	part({ Name = "Divider", Size = Vector3.new(World.CORRIDOR_HALF * 2, 0.12, 1.5), CFrame = CFrame.new(0, 0.06, biome.zStart), Color = biome.def.wallAlt:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon, Parent = bf })
	local banner = part({ Name = "Banner", Size = Vector3.one, CFrame = CFrame.new(0, 26, biome.zStart + 6), Transparency = 1, Parent = bf })
	Models.billboard(banner, `{biome.def.name} {biome.def.emoji}`, Color3.new(1, 1, 1), UDim2.fromScale(46, 9), Vector3.zero, 900)
	biomeSign(bf, biome.def, biome.zStart)

	local avoid = {}
	if biome.key == "Cave" then
		buildCave(bf, biome)
		avoid = { World.arena.center }
	else
		cluster(biome, Vector3.new(-36, 0, biome.zStart + 115))
		cluster(biome, Vector3.new(36, 0, biome.zStart + 235))
	end
	for _, cl in biome.clusters do
		table.insert(avoid, cl.center)
		table.insert(avoid, cl.home)
	end

	if biome.key == "Halloween" then
		local tent = Models.prop("clowntent", Random.new(1))
		place(tent, CFrame.new(0, 0, biome.zEnd - 40), bf)
		table.insert(avoid, Vector3.new(0, 0, biome.zEnd - 40))
	end
	decorate(biome, bf, Random.new(biome.index * 1013), avoid)

	-- Nest models at every cluster spot.
	biome.nestModels = {}
	for ci, cl in biome.clusters do
		for ni, nestCf in cl.nests do
			local nest = place(Models.nest(), nestCf, bf)
			nest.Name = `Nest{ci}_{ni}`
			table.insert(biome.nestModels, nest)
		end
	end
end

local function buildCorridor(parent)
	local corridor = folder("Biomes", parent)
	local z = World.CORRIDOR_START
	for i, def in Config.Biomes do
		if not def.seasonal or Config.HalloweenEnabled then
			local biome = {
				index = i,
				key = def.key,
				def = def,
				zStart = z,
				zEnd = z + World.BIOME_LENGTH,
				clusters = {},
			}
			table.insert(World.biomes, biome)
			buildBiome(corridor, biome)
			z += World.BIOME_LENGTH
		end
	end
	World.corridorEnd = z
	checkerWall(corridor, Vector3.new(-World.CORRIDOR_HALF, 0, z), Vector3.new(World.CORRIDOR_HALF, 0, z), World.WALL_HEIGHT, c(40, 30, 50), c(255, 120, 20))
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

local DAY = { ClockTime = 14, Brightness = 2.2, Ambient = c(140, 140, 150), OutdoorAmbient = c(150, 150, 155) }
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
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.FogEnd = 2600
	Lighting.FogStart = 900
	Lighting.FogColor = c(190, 225, 255)
	workspace.Gravity = 196.2

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Haze = 0.6
	atmosphere.Color = c(200, 225, 255)
	atmosphere.Decay = c(110, 140, 180)
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 22
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.12
	cc.Contrast = 0.05
	cc.Parent = Lighting

	buildLobby(mapFolder)
	buildCorridor(mapFolder)
end

function World.start()
	task.spawn(runCycle)
end

return World

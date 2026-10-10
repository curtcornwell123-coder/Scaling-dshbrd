-- Merge A Egg: everything about eggs in the world.
-- Biome nests, stealing (from nests and other pens), carrying with weight slowdown,
-- dropping (eggs reset to their nest after 60s), growing in pen nests,
-- the in-world Fuse Machine (3 matching eggs -> next rarity), luck events,
-- night big eggs and the daily boss egg.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Eggs = {}

local ctx
local Config
local Models
local Net
local Data
local World
local Economy
local Guardians

local rng = Random.new()
local worldFolder: Folder
local carries: { [Player]: any } = {}
local dropped = {} -- list of { egg, origin, model, expires }
local biomeNests = {} -- [biomeIndex][clusterIndex][nestIndex] = state
local penEggModels = {} -- [penIndex][slot] = { id, model }
local fuseModels = {} -- [penIndex] = { models }
local shieldUntil: { [Player]: number } = {}
local fusing: { [Player]: boolean } = {}

---------------------------------------------------------------------------
-- Egg data
---------------------------------------------------------------------------

local function rollWeight(big: boolean?): number
	local r = rng:NextNumber() ^ 2 -- light eggs are common, heavy ones rare
	local weight = Config.EggWeightMin + (Config.EggWeightMax - Config.EggWeightMin) * r
	if big then
		weight *= Config.BigEggWeightMultiplier
	end
	return math.floor(weight * 10) / 10
end

local function rollRarity(weights): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return 1
end

-- Builds a fresh egg table. opts: { big, boss, variant, weight }
function Eggs.makeEgg(data, biomeKey: string, rarity: number, opts)
	opts = opts or {}
	local variant = opts.variant
	if not variant and biomeKey == "Halloween" then
		variant = if rng:NextNumber() < 0.5 then "pumpkin" else "clown"
	end
	return {
		id = if data then Data.newId(data) else nil,
		biome = biomeKey,
		rarity = rarity,
		weight = opts.weight or rollWeight(opts.big),
		big = opts.big or nil,
		boss = opts.boss or nil,
		variant = variant,
	}
end

local function eggTitle(egg): string
	local rarity = Config.Rarities[egg.rarity]
	local biome = Config.Biomes[Config.BiomeIndex[egg.biome]]
	local name = if egg.boss then "Boss Egg" elseif egg.variant == "clown" then "Clown Egg" elseif egg.variant == "pumpkin" then "Pumpkin Egg" else biome.name .. " Egg"
	return `{rarity.name} {name}`
end
Eggs.title = eggTitle

local function buildEggModel(egg, display: boolean?): Model
	local model = Models.egg(egg.biome, egg.rarity, { big = egg.big, weight = egg.weight, variant = if egg.boss then "boss" else egg.variant, display = display })
	model:SetAttribute("Rarity", egg.rarity)
	model:SetAttribute("Weight", egg.weight)
	return model
end

local function addLabel(model: Model, egg, extra: string?)
	local rarity = Config.Rarities[egg.rarity]
	local height = model:GetAttribute("Height") or 2
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggTag"
	gui.Size = UDim2.fromScale(6, 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1.4, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = rarity.color
	title.Text = (if egg.big then "BIG " else "") .. eggTitle(egg)
	title.Parent = gui
	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.Size = UDim2.fromScale(1, 0.45)
	info.Position = UDim2.fromScale(0, 0.52)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.FredokaOne
	info.TextScaled = true
	info.TextColor3 = Color3.new(1, 1, 1)
	info.Text = extra or `{egg.weight}kg`
	info.Parent = gui
	for _, label in { title, info } do
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
	end
	gui.Parent = model.PrimaryPart
	return gui
end

local function addPrompt(parent: Instance, name: string, action: string, object: string, hold: number, key: Enum.KeyCode?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	if key then
		p.KeyboardKeyCode = key
	end
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- Carrying
---------------------------------------------------------------------------

function Eggs.getCarry(player: Player)
	return carries[player]
end

function Eggs.getCarriers()
	return carries
end

local function clearCarryVisual(player: Player, carry)
	if carry.model then
		carry.model:Destroy()
		carry.model = nil
	end
	player:SetAttribute("Carrying", nil)
end

-- origin: { kind = "biome"|"pen"|"inventory"|"boss", ... }
local function startCarry(player: Player, egg, origin): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if carries[player] then
		Net.notify(player, "You're already carrying an egg!", "error")
		return false
	end
	-- The egg rests in the raised hands just above the head (clients raise the arms).
	local model = buildEggModel(egg)
	local headTop = root.CFrame:PointToObjectSpace(head.Position).Y + head.Size.Y / 2
	model:PivotTo(root.CFrame * CFrame.new(0, headTop + 0.35, 0))
	Models.rigForPhysics(model)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Name = "CarriedEgg"
	model.Parent = character

	local pen = World.getPen(player)
	carries[player] = {
		egg = egg,
		origin = origin,
		model = model,
		armed = not (pen and World.inNestZone(pen, head.Position)),
		startedAt = os.clock(),
	}
	player:SetAttribute("Carrying", `{if egg.big then "BIG " else ""}{eggTitle(egg)} • {egg.weight}kg`)
	Economy.refreshWalkSpeed(player)
	return true
end

-- Finishes a carry: applies steal stats and nest respawns. Returns the egg.
local function consumeCarry(player: Player)
	local carry = carries[player]
	if not carry then
		return nil
	end
	carries[player] = nil
	clearCarryVisual(player, carry)
	Economy.refreshWalkSpeed(player)

	local origin = carry.origin
	local data = Data.get(player)
	local egg = carry.egg
	-- Ids are per-player counters, so an egg that changes hands gets a new one.
	if data and (not egg.id or origin.ownerUserId ~= player.UserId) then
		egg.id = Data.newId(data)
	end
	if origin.kind == "biome" then
		local state = biomeNests[origin.biome][origin.cluster][origin.nest]
		state.respawnAt = os.clock() + Config.NestRespawnSeconds
		if data then
			data.steals += 1
		end
	elseif origin.kind == "pen" and origin.ownerUserId ~= player.UserId then
		if data then
			data.steals += 1
		end
		local owner = Players:GetPlayerByUserId(origin.ownerUserId)
		if owner then
			shieldUntil[owner] = os.clock() + Config.StealShieldSeconds
			Net.notify(owner, `{player.DisplayName} stole your {eggTitle(egg)}! Your pen is shielded for {Config.StealShieldSeconds}s.`, "error")
			Net.fx(owner, "Alarm")
		end
		egg.growEnd = nil
	end
	return egg
end

-- Puts an egg into the first free unlocked nest, or the egg inventory.
-- keepGrowth keeps an existing growEnd (moving your own egg around).
function Eggs.addEgg(player: Player, egg, keepGrowth: boolean?): string
	local data = Data.get(player)
	if not data then
		return "none"
	end
	if not egg.id then
		egg.id = Data.newId(data)
	end
	local nestCount = Config.PenLevels[data.penLevel].nests
	for slot = 1, nestCount do
		local key = tostring(slot)
		if not data.nests[key] then
			if not (keepGrowth and egg.growEnd) then
				local seconds = Config.growSeconds(egg.biome, egg.rarity)
				if Economy.hasPass(player, "Growth") then
					seconds = math.ceil(seconds / 2)
				end
				egg.growEnd = os.time() + seconds
			end
			data.nests[key] = egg
			Eggs.renderPen(player)
			Economy.sync(player, "nests", "eggs")
			return "nest"
		end
	end
	egg.growEnd = nil
	data.eggs[egg.id] = egg
	Net.notify(player, "Your nests are full, so the egg went to your Eggs bag!", "info")
	Economy.sync(player, "eggs")
	return "inventory"
end

local function secure(player: Player)
	local carry = carries[player]
	local fromOwnPen = carry.origin.kind == "pen" and carry.origin.ownerUserId == player.UserId
	local wasSteal = carry.origin.kind == "biome" or (carry.origin.kind == "pen" and not fromOwnPen)
	local egg = consumeCarry(player)
	if not egg then
		return
	end
	Eggs.addEgg(player, egg, fromOwnPen or carry.origin.kind == "inventory")
	if wasSteal then
		Net.notify(player, `Secured a {if egg.big then "BIG " else ""}{eggTitle(egg)}!`, "success")
		Net.fx(player, "Secured", egg.rarity)
	end
	Economy.sync(player, "steals")
end

---------------------------------------------------------------------------
-- Dropping
---------------------------------------------------------------------------

local function spawnDropped(egg, origin, position: Vector3)
	local model = buildEggModel(egg)
	model.Name = "DroppedEgg"
	local ground = position - Vector3.new(0, 2.5, 0)
	local ray = workspace:Raycast(position, Vector3.new(0, -20, 0), RaycastParams.new())
	if ray then
		ground = ray.Position
	end
	model:PivotTo(CFrame.new(ground + Vector3.new(0, 0.1, 0)))
	model.Parent = worldFolder
	local entry = { egg = egg, origin = origin, model = model, expires = os.clock() + Config.DroppedEggReturnSeconds }
	local tag = addLabel(model, egg, "")
	entry.timer = tag:FindFirstChild("Info")
	local p = addPrompt(model.PrimaryPart, "Pickup", "Pick Up", eggTitle(egg), 0.3)
	p.Triggered:Connect(function(player)
		if not entry.model or carries[player] then
			return
		end
		if startCarry(player, entry.egg, entry.origin) then
			entry.model:Destroy()
			entry.model = nil
			local index = table.find(dropped, entry)
			if index then
				table.remove(dropped, index)
			end
		end
	end)
	table.insert(dropped, entry)
end

-- Makes a carrier drop their egg on the ground (caught, bonked, died, ...).
function Eggs.drop(player: Player, reason: string?)
	local carry = carries[player]
	if not carry then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local position = if root then root.Position elseif carry.model and carry.model.PrimaryPart then carry.model.PrimaryPart.Position else nil
	carries[player] = nil
	clearCarryVisual(player, carry)
	Economy.refreshWalkSpeed(player)
	if position then
		spawnDropped(carry.egg, carry.origin, position)
	else
		Eggs.returnHome(carry.egg, carry.origin)
	end
	if reason == "caught" then
		Net.notify(player, "Caught! You dropped the egg. It returns to its nest in 60s!", "error")
	elseif reason == "bonked" then
		Net.notify(player, "Bonk! You dropped the egg!", "error")
	end
end

-- Sends an egg back where it came from.
function Eggs.returnHome(egg, origin)
	if origin.kind == "biome" then
		local state = biomeNests[origin.biome][origin.cluster][origin.nest]
		if not state.egg then
			egg.id = nil
			Eggs.fillNest(state, egg)
		end
		return
	end
	local owner = origin.ownerUserId and Players:GetPlayerByUserId(origin.ownerUserId)
	if owner and Data.get(owner) then
		Eggs.addEgg(owner, egg, true)
	end
end

---------------------------------------------------------------------------
-- Biome nests
---------------------------------------------------------------------------

function Eggs.fillNest(state, egg)
	if state.model then
		state.model:Destroy()
	end
	state.egg = egg
	state.respawnAt = nil
	local model = buildEggModel(egg)
	model.Name = "NestEgg"
	model:PivotTo(state.cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
	model.Parent = worldFolder
	addLabel(model, egg)
	local p = addPrompt(model.PrimaryPart, "Steal", "Steal", eggTitle(egg), 0.5)
	p.Triggered:Connect(function(player)
		if state.egg ~= egg then
			return
		end
		if startCarry(player, egg, { kind = "biome", biome = state.biome, cluster = state.cluster, nest = state.nest }) then
			state.egg = nil
			state.respawnAt = math.huge -- respawns once secured or returned
			if state.model then
				state.model:Destroy()
				state.model = nil
			end
			Guardians.alert(state.biome, state.cluster, player)
		end
	end)
	state.model = model
end

local function randomNestEgg(biomeKey: string, rarity: number?)
	local big = World.isNight() and rng:NextNumber() < Config.NightBigEggChance
	return Eggs.makeEgg(nil, biomeKey, rarity or rollRarity(Config.NestRarityWeights), { big = big })
end

local function setupBiomeNests()
	for _, biome in World.biomes do
		biomeNests[biome.index] = {}
		for ci, cl in biome.clusters do
			biomeNests[biome.index][ci] = {}
			for ni, nestCf in cl.nests do
				local state = { biome = biome.index, biomeKey = biome.key, cluster = ci, nest = ni, cf = nestCf }
				biomeNests[biome.index][ci][ni] = state
				Eggs.fillNest(state, randomNestEgg(biome.key))
			end
		end
	end
end

local function eachNest(fn)
	for _, clusters in biomeNests do
		for _, nests in clusters do
			for _, state in nests do
				fn(state)
			end
		end
	end
end

local function luckEvent()
	local candidates = {}
	eachNest(function(state)
		table.insert(candidates, state)
	end)
	if #candidates == 0 then
		return
	end
	local state = candidates[rng:NextInteger(1, #candidates)]
	local weights = { 0, 0, 0, 0, 0, 0, 0 }
	for rarity, w in Config.LuckEventWeights do
		weights[rarity] = w
	end
	local rarity = rollRarity(weights)
	local egg = randomNestEgg(state.biomeKey, rarity)
	Eggs.fillNest(state, egg)
	local biome = Config.Biomes[state.biome]
	Net.announce(`🍀 A {Config.Rarities[rarity].name} {biome.name} Egg spawned in {biome.name} {biome.emoji}!`, Config.Rarities[rarity].color)
end

local function onNight(isNight: boolean)
	if isNight then
		Net.announce("🌙 Night has fallen! Animals are awake and BIG eggs are spawning!", Color3.fromRGB(150, 170, 255))
		eachNest(function(state)
			if state.egg and not state.egg.big and rng:NextNumber() < Config.NightBigEggChance then
				local egg = state.egg
				egg.big = true
				egg.weight = math.floor(egg.weight * Config.BigEggWeightMultiplier * 10) / 10
				Eggs.fillNest(state, egg)
			end
		end)
	else
		Net.announce("☀️ The sun is up! Animals are sleeping again.", Color3.fromRGB(255, 220, 120))
	end
end

---------------------------------------------------------------------------
-- Pen nests (growing eggs) and the Fuse Machine
---------------------------------------------------------------------------

function Eggs.isShielded(player: Player): boolean
	return (shieldUntil[player] or 0) > os.clock()
end

local function penOwnerPrompts(pen, slot: string, model: Model)
	local root = model.PrimaryPart :: BasePart
	local hatch = addPrompt(root, "Hatch", "Hatch", "Egg", 0)
	hatch.Triggered:Connect(function(player)
		if pen.owner == player then
			Economy.hatch(player, slot)
		end
	end)
	local pickup = addPrompt(root, "PickUp", "Pick Up", "Egg", 0.3, Enum.KeyCode.F)
	pickup.UIOffset = Vector2.new(0, 70)
	pickup.Triggered:Connect(function(player)
		local data = Data.get(player)
		if pen.owner ~= player or not data then
			return
		end
		local egg = data.nests[slot]
		if egg and not carries[player] then
			data.nests[slot] = nil
			if startCarry(player, egg, { kind = "pen", ownerUserId = player.UserId }) then
				Eggs.renderPen(player)
				Economy.sync(player, "nests")
			else
				data.nests[slot] = egg
			end
		end
	end)
	local steal = addPrompt(root, "Steal", "Steal", "Egg", Config.StealHoldSeconds)
	steal.Triggered:Connect(function(thief)
		local owner = pen.owner
		local data = owner and Data.get(owner)
		if not owner or not data or thief == owner or carries[thief] then
			return
		end
		if Eggs.isShielded(owner) then
			Net.notify(thief, "This pen is shielded right now!", "error")
			return
		end
		local egg = data.nests[slot]
		if not egg then
			return
		end
		data.nests[slot] = nil
		if startCarry(thief, egg, { kind = "pen", ownerUserId = owner.UserId }) then
			Net.notify(owner, `⚠️ {thief.DisplayName} is stealing your egg! Bonk them with your bat!`, "error")
			Net.fx(owner, "Alarm")
			Eggs.renderPen(owner)
			Economy.sync(owner, "nests")
		else
			data.nests[slot] = egg
		end
	end)
end

function Eggs.renderPen(player: Player)
	local data = Data.get(player)
	local pen = World.getPen(player)
	if not data or not pen then
		return
	end
	local cache = penEggModels[pen.index] or {}
	penEggModels[pen.index] = cache
	for slot = 1, Config.MaxNests do
		local key = tostring(slot)
		local egg = data.nests[key]
		local current = cache[key]
		if current and (not egg or current.id ~= egg.id) then
			current.model:Destroy()
			cache[key] = nil
			current = nil
		end
		if egg and not current then
			local model = buildEggModel(egg)
			model.Name = "PenEgg" .. key
			model:PivotTo(pen.nestSlots[slot].cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
			model.Parent = pen.eggFolder
			addLabel(model, egg, "")
			penOwnerPrompts(pen, key, model)
			cache[key] = { id = egg.id, model = model }
			current = cache[key]
		end
		if current and egg then
			current.model:SetAttribute("GrowEnd", egg.growEnd or 0)
			current.model:SetAttribute("Slot", key)
		end
	end
	Eggs.renderFuse(player)
end

local function clearPenModels(pen)
	local cache = penEggModels[pen.index]
	if cache then
		for _, entry in cache do
			entry.model:Destroy()
		end
	end
	penEggModels[pen.index] = nil
	if fuseModels[pen.index] then
		for _, m in fuseModels[pen.index] do
			m:Destroy()
		end
	end
	fuseModels[pen.index] = nil
end

function Eggs.renderFuse(player: Player)
	local data = Data.get(player)
	local pen = World.getPen(player)
	if not data or not pen then
		return
	end
	local list = fuseModels[pen.index] or {}
	for _, m in list do
		m:Destroy()
	end
	table.clear(list)
	fuseModels[pen.index] = list
	for i, egg in data.fuse do
		local slotPart = pen.fuse:FindFirstChild("Pod" .. i) :: BasePart?
		if slotPart then
			local model = buildEggModel(egg, true)
			model:ScaleTo(0.8)
			model:PivotTo(slotPart.CFrame)
			model.Parent = pen.fuse
			table.insert(list, model)
		end
	end
	local display = pen.fuse:FindFirstChild("Display")
	local counter = display and display:FindFirstChild("Counter")
	local count = counter and counter:FindFirstChild("Count")
	if count then
		(count :: TextLabel).Text = `{#data.fuse}/3`
	end
end

local function runFuse(player: Player, pen)
	local data = Data.get(player)
	if not data or #data.fuse < 3 then
		return
	end
	fusing[player] = true
	Net.fxAll("Fuse", pen.index)
	local core = pen.fuse:FindFirstChild("Core") :: BasePart?
	if core then
		local tween = TweenService:Create(core, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true), { Size = Vector3.one * 3.2 })
		tween:Play()
	end
	task.wait(2.6)
	if not Data.get(player) then
		fusing[player] = nil
		return
	end
	local inputs = { data.fuse[1], data.fuse[2], data.fuse[3] }
	local first = inputs[1]
	local totalWeight, big = 0, false
	for _, egg in inputs do
		totalWeight += egg.weight
		big = big or egg.big == true
	end
	local result = Eggs.makeEgg(data, first.biome, math.min(first.rarity + 1, #Config.Rarities), {
		big = big,
		variant = first.variant,
		weight = math.floor(math.min(totalWeight / 3 * 1.1, Config.EggWeightMax * Config.BigEggWeightMultiplier) * 10) / 10,
	})
	local leftover = {}
	for i = 4, #data.fuse do
		table.insert(leftover, data.fuse[i])
	end
	data.fuse = leftover
	data.stats.fused += 1
	fusing[player] = nil
	Eggs.renderFuse(player)
	Eggs.addEgg(player, result)
	Net.fx(player, "FuseResult", result)
	if result.rarity >= 6 then
		local rarity = Config.Rarities[result.rarity]
		Net.announce(`⚗️ {player.DisplayName} fused a {rarity.name:upper()} {Config.Biomes[Config.BiomeIndex[result.biome]].name} Egg!`, rarity.color)
	end
	Economy.sync(player, "fuse", "nests", "eggs")
end

local function insertIntoFuse(player: Player, pen)
	local data = Data.get(player)
	local carry = carries[player]
	if not data or pen.owner ~= player then
		Net.notify(player, "Use the Fuse Machine in your own pen!", "error")
		return
	end
	if fusing[player] or #data.fuse >= 3 then
		return
	end
	if not carry then
		Net.notify(player, "Carry an egg here to fuse it! 3 matching eggs = 1 rarer egg.", "info")
		return
	end
	local egg = carry.egg
	if egg.boss then
		Net.notify(player, "Boss eggs can't be fused!", "error")
		return
	end
	if egg.rarity >= #Config.Rarities then
		Net.notify(player, "Secret eggs are already the rarest!", "error")
		return
	end
	local first = data.fuse[1]
	if first and (first.biome ~= egg.biome or first.rarity ~= egg.rarity) then
		Net.notify(player, `This machine needs {eggTitle(first)}s! Take them out (hold F) to fuse something else.`, "error")
		return
	end
	local consumed = consumeCarry(player)
	if not consumed then
		return
	end
	consumed.growEnd = nil
	table.insert(data.fuse, consumed)
	Eggs.renderFuse(player)
	Net.fx(player, "FuseInsert", #data.fuse)
	Economy.sync(player, "fuse", "steals")
	if #data.fuse >= 3 then
		task.spawn(runFuse, player, pen)
	end
end

local function ejectFuse(player: Player, pen)
	local data = Data.get(player)
	if not data or pen.owner ~= player or fusing[player] or #data.fuse == 0 then
		return
	end
	for _, egg in data.fuse do
		data.eggs[egg.id] = egg
	end
	data.fuse = {}
	Eggs.renderFuse(player)
	Net.notify(player, "Eggs moved to your Eggs bag.", "info")
	Economy.sync(player, "fuse", "eggs")
end

---------------------------------------------------------------------------
-- Boss egg
---------------------------------------------------------------------------

-- Spawns the claimable boss egg. eligible: { [Player] = true } (dealt damage).
function Eggs.spawnBossEgg(position: Vector3, eligible, lifetime: number)
	local display = Eggs.makeEgg(nil, "Cave", 5, { boss = true, weight = 2 })
	local model = buildEggModel(display)
	model:ScaleTo(1.6)
	model.Name = "BossEgg"
	model:PivotTo(CFrame.new(position))
	model.Parent = worldFolder
	addLabel(model, display, "Beat the boss? Claim it! (1 per day)")
	local p = addPrompt(model.PrimaryPart, "Claim", "Claim", "Boss Egg", 0.5)
	p.MaxActivationDistance = 14
	p.Triggered:Connect(function(player)
		local data = Data.get(player)
		if not data then
			return
		end
		if not eligible[player] then
			Net.notify(player, "Only players who fought the boss can claim this!", "error")
			return
		end
		if data.bossEggDay >= Data.today() then
			Net.notify(player, "You already claimed today's Boss Egg! Come back tomorrow.", "error")
			return
		end
		local egg = Eggs.makeEgg(data, "Cave", rollRarity(Config.Boss.eggRarityWeights), { boss = true })
		if startCarry(player, egg, { kind = "boss", ownerUserId = player.UserId }) then
			data.bossEggDay = Data.today()
			Net.notify(player, "You got the Boss Egg! Get it home before the cave animals catch you!", "success")
		end
	end)
	task.delay(lifetime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
	return model
end

---------------------------------------------------------------------------
-- Requests from the Eggs panel
---------------------------------------------------------------------------

local function holdEgg(player: Player, id)
	local data = Data.get(player)
	if not data or type(id) ~= "string" then
		return
	end
	local egg = data.eggs[id]
	if not egg or carries[player] then
		return
	end
	data.eggs[id] = nil
	if not startCarry(player, egg, { kind = "inventory", ownerUserId = player.UserId }) then
		data.eggs[id] = egg
	end
	Economy.sync(player, "eggs")
end

local function placeEgg(player: Player, id)
	local data = Data.get(player)
	if not data or type(id) ~= "string" then
		return
	end
	local egg = data.eggs[id]
	if not egg then
		return
	end
	local nestCount = Config.PenLevels[data.penLevel].nests
	local used = 0
	for _ in data.nests do
		used += 1
	end
	if used >= nestCount then
		Net.notify(player, "All your nests are full! Upgrade your pen for more.", "error")
		return
	end
	data.eggs[id] = nil
	Eggs.addEgg(player, egg)
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

function Eggs.playerAdded(player: Player)
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				Eggs.drop(player, "died")
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterRemoving:Connect(function()
		Eggs.drop(player, "died")
	end)
	Eggs.renderPen(player)

	-- A fuse interrupted by leaving finishes now.
	local data = Data.get(player)
	local pen = World.getPen(player)
	if data and pen and #data.fuse >= 3 then
		task.spawn(runFuse, player, pen)
	end
end

-- Gives back any of this player's own eggs that are in flight before saving.
function Eggs.playerRemoving(player: Player)
	local data = Data.get(player)
	local carry = carries[player]
	if carry then
		carries[player] = nil
		clearCarryVisual(player, carry)
		local origin = carry.origin
		if data and (origin.ownerUserId == player.UserId) then
			data.eggs[carry.egg.id] = carry.egg
		else
			Eggs.returnHome(carry.egg, origin)
		end
	end
	for i = #dropped, 1, -1 do
		local entry = dropped[i]
		if entry.origin.ownerUserId == player.UserId and data then
			if entry.model then
				entry.model:Destroy()
			end
			data.eggs[entry.egg.id] = entry.egg
			table.remove(dropped, i)
		end
	end
	-- Eggs stolen from this player that are still in flight go to the thief anyway.
	shieldUntil[player] = nil
	fusing[player] = nil
	local pen = World.getPen(player)
	if pen then
		clearPenModels(pen)
	end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------

local function carryTick()
	for player, carry in carries do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pen = World.getPen(player)
		if root and pen then
			local inZone = World.inNestZone(pen, root.Position)
			if not inZone then
				carry.armed = true
			elseif carry.armed then
				secure(player)
			end
		end
	end
end

local function slowTick()
	local now = os.clock()
	-- Dropped eggs count down, then go home.
	for i = #dropped, 1, -1 do
		local entry = dropped[i]
		local left = entry.expires - now
		if left <= 0 then
			table.remove(dropped, i)
			if entry.model then
				entry.model:Destroy()
				entry.model = nil
			end
			Eggs.returnHome(entry.egg, entry.origin)
		elseif entry.timer then
			entry.timer.Text = `Returns in {math.ceil(left)}s`
		end
	end
	-- Empty biome nests respawn.
	eachNest(function(state)
		if not state.egg and state.respawnAt and now >= state.respawnAt then
			Eggs.fillNest(state, randomNestEgg(state.biomeKey))
		end
	end)
	-- Steal shields.
	for _, pen in World.pens do
		local owner = pen.owner
		local left = if owner then (shieldUntil[owner] or 0) - now else 0
		if left > 0 then
			pen.shield.Transparency = 0.75
			pen.shieldLabel.Text = `🛡️ Protected {math.ceil(left)}s`
		elseif pen.shield.Transparency < 1 then
			pen.shield.Transparency = 1
			pen.shieldLabel.Text = ""
		end
	end
end

---------------------------------------------------------------------------
-- Init / start
---------------------------------------------------------------------------

function Eggs.init(context)
	ctx = context
	Config = ctx.Config
	Models = ctx.Models
	Net = ctx.Net
	Data = ctx.Data
	World = ctx.World
	Economy = ctx.Economy
	Guardians = ctx.Guardians

	Net.on("HoldEgg", holdEgg)
	Net.on("PlaceEgg", placeEgg)
end

function Eggs.start()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "WorldEggs"
	worldFolder.Parent = workspace

	setupBiomeNests()
	for _, pen in World.pens do
		pen.fusePrompt.Triggered:Connect(function(player)
			insertIntoFuse(player, pen)
		end)
		pen.fuseEjectPrompt.Triggered:Connect(function(player)
			ejectFuse(player, pen)
		end)
	end
	World.CycleChanged:Connect(onNight)

	task.spawn(function()
		while true do
			task.wait(0.15)
			carryTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			slowTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.LuckEventInterval)
			luckEvent()
		end
	end)
end

return Eggs

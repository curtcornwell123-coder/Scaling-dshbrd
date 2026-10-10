-- Merge A Egg: money, speed, treadmills, pets, hatching, pen upgrades, rebirth,
-- trails, treadmill shop, Robux passes/products (with gifting), free rewards,
-- leaderstats and global leaderboards.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Economy = {}

local ctx
local Config
local Models
local Net
local Data
local World
local Eggs

local sessions: { [Player]: any } = {}
local rng = Random.new()
local productsById = {}
local giftPassByProduct = {}
local nameCache: { [number]: string } = {}

---------------------------------------------------------------------------
-- Session helpers
---------------------------------------------------------------------------

function Economy.session(player: Player)
	return sessions[player]
end

function Economy.isOwner(player: Player): boolean
	return player.UserId == Config.OwnerUserId
end

function Economy.hasPass(player: Player, key: string): boolean
	local session = sessions[player]
	local data = Data.get(player)
	if data and data.giftedPasses and data.giftedPasses[key] then
		return true
	end
	return session ~= nil and session.passes[key] == true
end

local function today(): number
	return Data.today()
end

---------------------------------------------------------------------------
-- Multipliers
---------------------------------------------------------------------------

function Economy.rebirthMultiplier(data): number
	return 1 + data.rebirths * Config.RebirthBoost
end

function Economy.completedSets(data): number
	local count = 0
	for _, biome in Config.Biomes do
		local complete = true
		for _, p in biome.pets do
			if not data.index[p.name] then
				complete = false
				break
			end
		end
		if complete then
			count += 1
		end
	end
	return count
end

function Economy.moneyMultiplier(player: Player, data): number
	local mult = Economy.rebirthMultiplier(data) * (1 + Economy.completedSets(data) * Config.IndexSetBonus)
	if Economy.hasPass(player, "Money") then
		mult *= 2
	end
	if Economy.hasPass(player, "VIP") then
		mult *= 1.25
	end
	local session = sessions[player]
	if session and session.friendsHere > 0 then
		mult *= Config.FriendBoost
	end
	return mult
end

function Economy.incomePerSecond(player: Player): number
	local data = Data.get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, id in data.equipped do
		local p = data.pets[id]
		if p then
			total += Config.petIncome(p)
		end
	end
	return total * Economy.moneyMultiplier(player, data)
end

function Economy.maxEquipSlots(player: Player, data): number
	return data.equipSlots + (if Economy.hasPass(player, "VIP") then 1 else 0)
end

function Economy.speedPerStep(player: Player): number
	local data = Data.get(player)
	if not data then
		return 0
	end
	local level = Config.PenLevels[data.penLevel]
	local mill = Config.TreadmillsByKey[data.equippedTreadmill] or Config.TreadmillsByKey.Wooden
	local trail = Config.TrailsByKey[data.equippedTrail]
	local petBoost = 0
	for _, id in data.equipped do
		local p = data.pets[id]
		if p then
			petBoost += Config.Rarities[p.rarity].treadmill
		end
	end
	local perStep = level.perStep * mill.mult * (if trail then trail.mult else 1) * Economy.rebirthMultiplier(data) * (1 + petBoost)
	if Economy.hasPass(player, "Speed") then
		perStep *= 2
	end
	return perStep
end

function Economy.hatchLuck(player: Player): number
	return if Economy.hasPass(player, "VIP") then 1.25 else 1
end

---------------------------------------------------------------------------
-- Sync to client
---------------------------------------------------------------------------

local function ownedTreadmills(player: Player, data)
	local owned = table.clone(data.treadmills)
	if Economy.hasPass(player, "VIP") then
		owned.VIPNeon = true
	end
	if Economy.isOwner(player) then
		owned.CornyTopHat = true
	end
	return owned
end

local FIELDS = {
	money = function(_, data)
		return data.money
	end,
	speed = function(_, data)
		return data.speed
	end,
	perStep = function(player)
		return Economy.speedPerStep(player)
	end,
	income = function(player)
		return Economy.incomePerSecond(player)
	end,
	penLevel = function(_, data)
		return data.penLevel
	end,
	slots = function(player, data)
		return { used = #data.equipped, max = Economy.maxEquipSlots(player, data), bought = data.equipSlots }
	end,
	eggs = function(_, data)
		return data.eggs
	end,
	nests = function(_, data)
		return data.nests
	end,
	fuse = function(_, data)
		return data.fuse
	end,
	pets = function(_, data)
		return data.pets
	end,
	equipped = function(_, data)
		return data.equipped
	end,
	index = function(_, data)
		return data.index
	end,
	trails = function(_, data)
		return { owned = data.trails, equipped = data.equippedTrail }
	end,
	treadmills = function(player, data)
		return { owned = ownedTreadmills(player, data), equipped = data.equippedTreadmill }
	end,
	rebirths = function(_, data)
		return data.rebirths
	end,
	passes = function(player)
		local result = {}
		for key in Config.GamePasses do
			result[key] = Economy.hasPass(player, key)
		end
		return result
	end,
	daily = function(_, data)
		local canClaim = data.daily.day < today()
		local nextStreak = if data.daily.day == today() - 1 then data.daily.streak + 1 elseif canClaim then 1 else data.daily.streak
		return { streak = data.daily.streak, canClaim = canClaim, nextStreak = ((nextStreak - 1) % 7) + 1 }
	end,
	playtime = function(_, data)
		return { seconds = data.playtime.seconds, claimed = data.playtime.claimed }
	end,
	groupClaimed = function(_, data)
		return data.groupRewardClaimed
	end,
	steals = function(_, data)
		return data.steals
	end,
	maxBiome = function(_, data)
		return data.maxBiome
	end,
	friends = function(player)
		local session = sessions[player]
		return if session then session.friendsHere else 0
	end,
}

-- Sends the named fields (or everything) to the client.
function Economy.sync(player: Player, ...: string)
	local data = Data.get(player)
	if not data then
		return
	end
	local patch = { serverTime = os.time() }
	local keys = { ... }
	if #keys == 0 then
		for key, builder in FIELDS do
			patch[key] = builder(player, data)
		end
		patch.isOwner = Economy.isOwner(player)
		patch.isAdmin = player:GetAttribute("Admin") == true
	else
		for _, key in keys do
			local builder = FIELDS[key]
			if builder then
				patch[key] = builder(player, data)
			end
		end
	end
	Net.sync(player, patch)
end

---------------------------------------------------------------------------
-- Money and speed
---------------------------------------------------------------------------

function Economy.addMoney(player: Player, amount: number)
	local data = Data.get(player)
	if data then
		data.money = math.max(0, data.money + amount)
	end
end

function Economy.spend(player: Player, amount: number): boolean
	local data = Data.get(player)
	if not data or data.money < amount then
		return false
	end
	data.money -= amount
	return true
end

function Economy.addSpeed(player: Player, amount: number)
	local data = Data.get(player)
	if data then
		data.speed = math.max(0, data.speed + amount)
		Economy.refreshWalkSpeed(player)
	end
end

function Economy.refreshWalkSpeed(player: Player)
	local data = Data.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not humanoid then
		return
	end
	local walk = Config.walkSpeedFor(data.speed)
	local carry = Eggs.getCarry(player)
	if carry then
		walk *= Config.carryMultiplier(carry.egg.weight)
	end
	humanoid.WalkSpeed = walk
	if humanoid.UseJumpPower then
		humanoid.JumpPower = 55
	else
		humanoid.JumpHeight = 8
	end
end

function Economy.grantGrace(player: Player, seconds: number)
	local session = sessions[player]
	if session then
		session.graceUntil = math.max(session.graceUntil, os.clock() + seconds)
		session.lastPos = nil
	end
end

---------------------------------------------------------------------------
-- Pets in the pen
---------------------------------------------------------------------------

function Economy.renderPets(player: Player)
	local data = Data.get(player)
	local session = sessions[player]
	if not data or not session or not session.pen then
		return
	end
	local pen = session.pen
	pen.petFolder:ClearAllChildren()
	pen.petFolder:SetAttribute("AreaCF", pen.petArea.cf)
	pen.petFolder:SetAttribute("AreaSize", pen.petArea.size)
	for i, id in data.equipped do
		local p = data.pets[id]
		local def = p and Config.PetsByName[p.name]
		if def then
			local model = Models.pet(def, { scale = if p.big then 1.25 else 1, aura = true })
			local half = pen.petArea.size / 2
			local offset = Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))
			model:PivotTo(pen.petArea.cf * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			local rarity = Config.Rarities[p.rarity]
			local gui, label = Models.billboard(model.PrimaryPart, "", rarity.color, UDim2.fromScale(7, 2.4), Vector3.new(0, model:GetAttribute("Height") + 1.2, 0), 90)
			gui.Name = "PetTag"
			label.RichText = true
			label.Text = `<font size="14">{rarity.name}</font>\n{p.name}\n<font color="#7dff6b">${Config.format(Config.petIncome(p))}/s</font>`
			model.Name = "Pet" .. i
			model.Parent = pen.petFolder
		end
	end
end

---------------------------------------------------------------------------
-- Hatching
---------------------------------------------------------------------------

local function weightedPick(weights: { number }): number
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
	return #weights
end

function Economy.rollPet(player: Player, egg)
	local biome = Config.Biomes[Config.BiomeIndex[egg.biome]]
	local luck = (1 + math.max(egg.weight - 1, 0) * Config.WeightLuckPerKg) * (if egg.big then Config.BigEggLuck else 1) * Economy.hatchLuck(player)
	local chances = Config.HatchTierChances
	local offset = weightedPick({ chances[1], chances[2] * luck, chances[3] * luck }) - 1
	local rarity = math.min(egg.rarity + offset, #Config.Rarities)
	while rarity >= 1 do
		local candidates = {}
		for _, p in biome.pets do
			local bossOnly = biome.bossOnly and biome.bossOnly[p.name]
			if p.rarityIndex == rarity and (egg.boss or not bossOnly) then
				table.insert(candidates, p)
			end
		end
		if #candidates > 0 then
			return candidates[rng:NextInteger(1, #candidates)]
		end
		rarity -= 1
	end
	return biome.pets[1]
end

-- Hatches a ready egg in a nest slot. Returns the new pet record.
function Economy.hatch(player: Player, slot: string)
	local data = Data.get(player)
	if not data then
		return nil
	end
	local egg = data.nests[slot]
	if not egg then
		return nil
	end
	if egg.growEnd > os.time() then
		Net.notify(player, "That egg is still growing!", "error")
		return nil
	end
	data.nests[slot] = nil
	local def = Economy.rollPet(player, egg)
	local p = {
		id = Data.newId(data),
		name = def.name,
		biome = def.biome,
		rarity = def.rarityIndex,
		weight = egg.weight,
		big = egg.big or nil,
	}
	data.pets[p.id] = p
	local isNew = not data.index[def.name]
	data.index[def.name] = true
	data.stats.hatched += 1

	-- New pets go to the inventory; the hatch screen offers to place them down.
	if def.biome == "Halloween" then
		if not data.trails.Pumpkin and rng:NextNumber() < Config.PumpkinTrailDropChance then
			data.trails.Pumpkin = true
			Net.announce(`🎃 {player.DisplayName} found the Pumpkin Trail!`, Color3.fromRGB(255, 140, 20))
		end
		if not data.treadmills.Pumpkin and rng:NextNumber() < Config.PumpkinStomperDropChance then
			data.treadmills.Pumpkin = true
			Net.announce(`🎃 {player.DisplayName} found the Pumpkin Stomper treadmill!`, Color3.fromRGB(255, 140, 20))
		end
	end

	Net.fx(player, "Hatch", p, isNew, egg, #data.equipped < Economy.maxEquipSlots(player, data))
	if p.rarity >= 6 then
		local rarity = Config.Rarities[p.rarity]
		Net.announce(`🎉 {player.DisplayName} hatched a {rarity.name:upper()} {p.name}!`, rarity.color)
	end
	Eggs.renderPen(player)
	Economy.sync(player, "nests", "pets", "equipped", "index", "income", "perStep", "slots", "trails", "treadmills")
	return p
end

function Economy.hatchAllReady(player: Player)
	local data = Data.get(player)
	if not data then
		return
	end
	for slot, egg in data.nests do
		if egg.growEnd <= os.time() then
			Economy.hatch(player, slot)
		end
	end
end

---------------------------------------------------------------------------
-- Equipping and selling
---------------------------------------------------------------------------

local function afterTeamChange(player: Player)
	Economy.renderPets(player)
	Economy.sync(player, "equipped", "income", "perStep", "slots")
end

function Economy.equip(player: Player, id: string)
	local data = Data.get(player)
	if not data or not data.pets[id] or table.find(data.equipped, id) then
		return
	end
	if #data.equipped >= Economy.maxEquipSlots(player, data) then
		Net.notify(player, "All pet slots are full! Buy another slot.", "error")
		return
	end
	table.insert(data.equipped, id)
	afterTeamChange(player)
end

function Economy.unequip(player: Player, id: string)
	local data = Data.get(player)
	if not data then
		return
	end
	local index = table.find(data.equipped, id)
	if index then
		table.remove(data.equipped, index)
		afterTeamChange(player)
	end
end

function Economy.equipBest(player: Player)
	local data = Data.get(player)
	if not data then
		return
	end
	local list = {}
	for _, p in data.pets do
		table.insert(list, p)
	end
	table.sort(list, function(a, b)
		return Config.petIncome(a) > Config.petIncome(b)
	end)
	table.clear(data.equipped)
	for i = 1, math.min(#list, Economy.maxEquipSlots(player, data)) do
		table.insert(data.equipped, list[i].id)
	end
	afterTeamChange(player)
end

function Economy.buySlot(player: Player)
	local data = Data.get(player)
	if not data then
		return
	end
	local cost = Config.EquipSlotCosts[data.equipSlots]
	if not cost then
		Net.notify(player, "You have every slot!", "error")
		return
	end
	if not Economy.spend(player, cost) then
		Net.notify(player, `You need ${Config.format(cost)}!`, "error")
		return
	end
	data.equipSlots += 1
	Net.notify(player, "+1 pet slot!", "success")
	Economy.sync(player, "money", "slots")
end

-- request: { eggs = { id }, pets = { id } }
function Economy.sell(player: Player, request)
	local data = Data.get(player)
	if not data or type(request) ~= "table" then
		return
	end
	local total = 0
	local sold = 0
	if type(request.eggs) == "table" then
		for _, id in request.eggs do
			if type(id) == "string" then
				local egg = data.eggs[id]
				if egg then
					data.eggs[id] = nil
				else
					for slot, nestEgg in data.nests do
						if nestEgg.id == id then
							egg = nestEgg
							data.nests[slot] = nil
							break
						end
					end
				end
				if egg then
					total += Config.eggValue(egg)
					sold += 1
				end
			end
		end
	end
	if type(request.pets) == "table" then
		for _, id in request.pets do
			local p = type(id) == "string" and data.pets[id]
			if p then
				total += Config.petValue(p)
				data.pets[id] = nil
				local index = table.find(data.equipped, id)
				if index then
					table.remove(data.equipped, index)
				end
				sold += 1
			end
		end
	end
	if sold == 0 then
		return
	end
	total = math.floor(total * Economy.moneyMultiplier(player, data))
	data.money += total
	Net.notify(player, `Sold {sold} for ${Config.format(total)}!`, "success")
	Net.fx(player, "Cash", total)
	Economy.renderPets(player)
	Eggs.renderPen(player)
	Economy.sync(player, "money", "eggs", "nests", "pets", "equipped", "income", "perStep", "slots")
end

---------------------------------------------------------------------------
-- Pen, rebirth, trails, treadmills
---------------------------------------------------------------------------

function Economy.upgradePen(player: Player)
	local data = Data.get(player)
	local session = sessions[player]
	if not data or not session then
		return
	end
	local nextLevel = Config.PenLevels[data.penLevel + 1]
	if not nextLevel then
		return
	end
	if not Economy.spend(player, nextLevel.cost) then
		Net.notify(player, `Upgrade costs ${Config.format(nextLevel.cost)}!`, "error")
		return
	end
	data.penLevel += 1
	World.setPenLook(session.pen, data.penLevel, data.equippedTreadmill)
	Economy.refreshTreadmillText(player)
	Eggs.renderPen(player)
	Net.notify(player, `Pen upgraded to Level {data.penLevel}! More nests and faster treadmills!`, "success")
	Net.fx(player, "Celebrate")
	Economy.sync(player, "money", "penLevel", "perStep")
end

function Economy.rebirth(player: Player)
	local data = Data.get(player)
	local session = sessions[player]
	if not data or not session then
		return
	end
	local cost = Config.rebirthCost(data.rebirths)
	if data.money < cost then
		Net.notify(player, `Rebirth needs ${Config.format(cost)}!`, "error")
		return
	end
	data.rebirths += 1
	data.money = 0
	data.speed = 0
	data.penLevel = 1
	local nestCount = Config.PenLevels[1].nests
	for slot, egg in data.nests do
		if tonumber(slot) > nestCount then
			data.nests[slot] = nil
			egg.growEnd = nil
			data.eggs[egg.id] = egg
		end
	end
	World.setPenLook(session.pen, 1, data.equippedTreadmill)
	Economy.refreshWalkSpeed(player)
	Economy.refreshTreadmillText(player)
	Eggs.renderPen(player)
	Net.announce(`♻️ {player.DisplayName} reached Rebirth {data.rebirths}!`, Color3.fromRGB(120, 255, 90))
	Net.fx(player, "Celebrate")
	Economy.sync(player)
end

function Economy.applyTrail(player: Player)
	local data = Data.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not root then
		return
	end
	local old = root:FindFirstChild("SpeedTrail")
	if old then
		old:Destroy()
	end
	for _, name in { "TrailA", "TrailB" } do
		local a = root:FindFirstChild(name)
		if a then
			a:Destroy()
		end
	end
	local trail = Config.TrailsByKey[data.equippedTrail]
	if not trail then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 1, 0.5)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, -1.6, 0.5)
	a1.Parent = root
	local effect = Instance.new("Trail")
	effect.Name = "SpeedTrail"
	effect.Attachment0 = a0
	effect.Attachment1 = a1
	effect.Lifetime = 0.45
	effect.MinLength = 0.1
	effect.LightEmission = 0.5
	effect.Color = ColorSequence.new(trail.colors[1], trail.colors[2])
	effect.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	effect.WidthScale = NumberSequence.new(1, 0.2)
	effect.Parent = root
end

function Economy.buyTrail(player: Player, key: string)
	local data = Data.get(player)
	local trail = Config.TrailsByKey[key]
	if not data or not trail or trail.event or data.trails[key] then
		return
	end
	-- Trails must be bought in order, like the reference shop.
	local previous = Config.Trails[trail.order - 1]
	if previous and not previous.event and not data.trails[previous.key] then
		Net.notify(player, `Buy the {previous.name} first!`, "error")
		return
	end
	if not Economy.spend(player, trail.cost) then
		Net.notify(player, `You need ${Config.format(trail.cost)}!`, "error")
		return
	end
	data.trails[key] = true
	Economy.equipTrail(player, key)
	Net.notify(player, `Unlocked {trail.name}! x{trail.mult} Speed`, "success")
	Economy.sync(player, "money")
end

function Economy.equipTrail(player: Player, key: string)
	local data = Data.get(player)
	if not data or not data.trails[key] then
		return
	end
	data.equippedTrail = key
	Economy.applyTrail(player)
	Economy.refreshTreadmillText(player)
	Economy.sync(player, "trails", "perStep")
end

function Economy.buyTreadmill(player: Player, key: string)
	local data = Data.get(player)
	local mill = Config.TreadmillsByKey[key]
	if not data or not mill or mill.event or mill.vip or mill.ownerOnly or data.treadmills[key] then
		return
	end
	if not Economy.spend(player, mill.cost) then
		Net.notify(player, `You need ${Config.format(mill.cost)}!`, "error")
		return
	end
	data.treadmills[key] = true
	Net.notify(player, `Bought the {mill.name}! x{Config.format(mill.mult)} treadmill speed`, "success")
	Economy.equipTreadmill(player, key)
	Economy.sync(player, "money")
end

function Economy.equipTreadmill(player: Player, key: string)
	local data = Data.get(player)
	local session = sessions[player]
	if not data or not session or not ownedTreadmills(player, data)[key] then
		return
	end
	data.equippedTreadmill = key
	World.setPenLook(session.pen, data.penLevel, key)
	Economy.refreshTreadmillText(player)
	Economy.sync(player, "treadmills", "perStep")
end

-- Admin: equip any treadmill design on your own pen.
function Economy.adminSetTreadmill(player: Player, query: string): string
	local data = Data.get(player)
	if not data then
		return "Your data hasn't loaded yet."
	end
	local mill = Config.TreadmillsByKey[query]
	if not mill then
		for _, candidate in Config.Treadmills do
			if candidate.key:lower() == query:lower() or candidate.name:lower() == query:lower() then
				mill = candidate
				break
			end
		end
	end
	if not mill then
		return `Unknown treadmill "{query}".`
	end
	if mill.ownerOnly and not Economy.isOwner(player) then
		return `{mill.name} is exclusive to its owner.`
	end
	data.treadmills[mill.key] = true
	Economy.equipTreadmill(player, mill.key)
	return `Your pen now uses the {mill.name}!`
end

function Economy.refreshTreadmillText(player: Player)
	local session = sessions[player]
	if session and session.pen then
		World.setTreadmillText(session.pen, `+{Config.format(Economy.speedPerStep(player))}/step`)
	end
end

---------------------------------------------------------------------------
-- Free rewards
---------------------------------------------------------------------------

local function bestBiomeKey(data): string
	local biome = World.getBiome(data.maxBiome) or World.biomes[1]
	return biome.key
end

local function grantReward(player: Player, reward, label: string)
	local data = Data.get(player)
	if not data then
		return
	end
	local income = Economy.incomePerSecond(player)
	if reward.money and reward.money > 0 then
		local amount = math.floor(math.max(reward.money, income * (reward.incomeSeconds or 0)))
		data.money += amount
		Net.notify(player, `{label}: +${Config.format(amount)}!`, "success")
	end
	if reward.speed then
		local amount = math.floor(math.max(reward.speed, Economy.speedPerStep(player) * (reward.speedSteps or 0)))
		Economy.addSpeed(player, amount)
		Net.notify(player, `{label}: +{Config.format(amount)} Speed!`, "success")
	end
	if reward.egg then
		local egg = Eggs.makeEgg(data, bestBiomeKey(data), reward.egg, {})
		Eggs.addEgg(player, egg)
		Net.notify(player, `{label}: a free {Config.Rarities[reward.egg].name} egg!`, "success")
	end
	Net.fx(player, "Celebrate")
end

function Economy.claimDaily(player: Player)
	local data = Data.get(player)
	if not data or data.daily.day >= today() then
		return
	end
	local streak = if data.daily.day == today() - 1 then data.daily.streak + 1 else 1
	data.daily.day = today()
	data.daily.streak = streak
	local reward = Config.DailyRewards[((streak - 1) % 7) + 1]
	grantReward(player, reward, `Day {streak} reward`)
	Economy.sync(player, "daily", "money", "speed", "eggs", "nests")
end

function Economy.claimPlaytime(player: Player, index: number)
	local data = Data.get(player)
	local gift = type(index) == "number" and Config.PlaytimeGifts[index]
	if not data or not gift then
		return
	end
	local key = tostring(index)
	if data.playtime.claimed[key] or data.playtime.seconds < gift.minutes * 60 then
		return
	end
	data.playtime.claimed[key] = true
	grantReward(player, gift, `{gift.minutes} min gift`)
	Economy.sync(player, "playtime", "money", "speed", "eggs", "nests")
end

function Economy.claimGroup(player: Player)
	local data = Data.get(player)
	if not data or data.groupRewardClaimed then
		return
	end
	-- Mark first so spammed requests can't all pass while the group check yields.
	data.groupRewardClaimed = true
	local ok, inGroup = pcall(function()
		return player:IsInGroupAsync(Config.GroupId)
	end)
	if not ok then
		data.groupRewardClaimed = false
		Net.notify(player, "Couldn't check the group right now, try again!", "error")
		return
	end
	if not inGroup then
		data.groupRewardClaimed = false
		Net.fx(player, "Popup", "You must join the group to claim this reward!")
		return
	end
	Economy.addSpeed(player, Config.GroupRewardSpeed)
	Net.notify(player, `Thanks for joining! +{Config.formatWithCommas(Config.GroupRewardSpeed)} Speed!`, "success")
	Net.fx(player, "Celebrate")
	Economy.sync(player, "groupClaimed", "speed")
end

---------------------------------------------------------------------------
-- Robux
---------------------------------------------------------------------------

local function grantProduct(recipient: Player, product)
	local data = Data.get(recipient)
	if not data then
		return false
	end
	if product.kind == "Money" then
		data.money += product.amount
	elseif product.kind == "Speed" then
		Economy.addSpeed(recipient, product.amount)
	elseif product.kind == "FeaturedEgg" then
		local featured = Config.FeaturedEgg
		for _ = 1, product.amount do
			local egg = Eggs.makeEgg(data, featured.biome, featured.rarity, { variant = "pumpkin" })
			Eggs.addEgg(recipient, egg)
		end
	elseif product.kind == "SkipGrow" then
		for _, egg in data.nests do
			egg.growEnd = 0
		end
		Eggs.renderPen(recipient)
	elseif product.kind == "Trail" then
		data.trails[product.trail] = true
		Economy.equipTrail(recipient, product.trail)
	elseif product.kind == "GiftPass" then
		data.giftedPasses = data.giftedPasses or {}
		data.giftedPasses[product.pass] = true
		Economy.onPassesChanged(recipient)
	end
	Economy.sync(recipient)
	Net.fx(recipient, "Celebrate")
	return true
end

local function processReceipt(receipt)
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	local buyerData = buyer and Data.get(buyer)
	if not buyer or not buyerData then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(buyerData.purchases, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = productsById[receipt.ProductId]
	if not product then
		local pass = giftPassByProduct[receipt.ProductId]
		if pass then
			product = { kind = "GiftPass", pass = pass }
		end
	end
	if not product then
		warn("[Economy] Unknown product purchased:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local session = sessions[buyer]
	local recipient = buyer
	if session and session.giftTarget then
		local target = Players:GetPlayerByUserId(session.giftTarget)
		session.giftTarget = nil
		if target and target ~= buyer and Data.get(target) then
			recipient = target
		end
	elseif product.kind == "GiftPass" then
		recipient = buyer
	end

	if not grantProduct(recipient, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if recipient ~= buyer then
		Net.notify(buyer, `🎁 Gift sent to {recipient.DisplayName}!`, "success")
		Net.notify(recipient, `🎁 {buyer.DisplayName} sent you a gift!`, "success")
		Data.save(recipient)
	end
	table.insert(buyerData.purchases, receipt.PurchaseId)
	while #buyerData.purchases > 50 do
		table.remove(buyerData.purchases, 1)
	end
	if not Data.save(buyer) then
		-- Roblox retries later; the recorded PurchaseId stops a double grant.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Economy.setGiftTarget(player: Player, userId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(userId) == "number" and Players:GetPlayerByUserId(userId) and userId ~= player.UserId then
		session.giftTarget = userId
	else
		session.giftTarget = nil
	end
end

function Economy.onPassesChanged(player: Player)
	local data = Data.get(player)
	if not data then
		return
	end
	if Economy.hasPass(player, "VIP") then
		player:SetAttribute("VIP", true)
	end
	Economy.refreshTreadmillText(player)
	Economy.sync(player, "passes", "slots", "income", "perStep", "treadmills")
end

local function loadPasses(player: Player)
	local session = sessions[player]
	for key, pass in Config.GamePasses do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns and session then
				session.passes[key] = true
			end
		end
	end
	Economy.onPassesChanged(player)
end

---------------------------------------------------------------------------
-- Friends: x2 cash while a Roblox friend is in your server
---------------------------------------------------------------------------

local function isFriend(player: Player, other: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	local cached = session.friendCache[other.UserId]
	if cached == nil then
		local ok, result = pcall(function()
			return player:IsFriendsWithAsync(other.UserId)
		end)
		cached = ok and result == true
		session.friendCache[other.UserId] = cached
	end
	return cached
end

-- Recounts friends for everyone and tells players when their boost turns on.
function Economy.refreshFriends()
	-- Snapshot first: friend checks yield and players may join or leave meanwhile.
	local list = {}
	for player in sessions do
		table.insert(list, player)
	end
	for _, player in list do
		local session = sessions[player]
		if not session then
			continue
		end
		local count = 0
		local newest = nil
		for _, other in Players:GetPlayers() do
			if other ~= player and sessions[other] and isFriend(player, other) then
				count += 1
				newest = other
			end
		end
		if count ~= session.friendsHere and sessions[player] then
			local wasBoosted = session.friendsHere > 0
			session.friendsHere = count
			if count > 0 and not wasBoosted and newest then
				Net.notify(player, `👥 {newest.DisplayName} is here! Friend Boost: x{Config.FriendBoost} cash!`, "success")
			elseif count == 0 and wasBoosted then
				Net.notify(player, "Your friend left — Friend Boost ended.", "info")
			end
			Economy.sync(player, "friends", "income")
		end
	end
end

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------

local function setupLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local income = Instance.new("NumberValue")
	income.Name = "Money/s"
	income.Parent = stats
	local speed = Instance.new("NumberValue")
	speed.Name = "Speed"
	speed.Parent = stats
	stats.Parent = player
	return income, speed
end

local function onCharacter(player: Player, character: Model)
	local session = sessions[player]
	if not session then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or not session.pen then
		return
	end
	task.wait()
	Economy.grantGrace(player, 3)
	character:PivotTo(session.pen.spawnCf)
	Economy.refreshWalkSpeed(player)
	Economy.applyTrail(player)
	if Economy.hasPass(player, "VIP") then
		local head = character:FindFirstChild("Head")
		if head and not head:FindFirstChild("VIPTag") then
			local gui = Models.billboard(head, "⭐ VIP", Color3.fromRGB(255, 210, 50), UDim2.fromScale(4, 1.2), Vector3.new(0, 2.2, 0), 80)
			gui.Name = "VIPTag"
		end
	end
end

function Economy.playerAdded(player: Player, data, pen)
	local session = {
		pen = pen,
		passes = {},
		giftTarget = nil,
		graceUntil = 0,
		lastPos = nil,
		violations = 0,
		friendsHere = 0,
		friendCache = {},
	}
	sessions[player] = session
	session.incomeValue, session.speedValue = setupLeaderstats(player)

	-- Starter egg so brand-new players have something to grow right away.
	if data.stats.hatched == 0 and next(data.pets) == nil and next(data.nests) == nil and next(data.eggs) == nil then
		local egg = Eggs.makeEgg(data, "Forest", 1, {})
		data.nests["1"] = egg
		egg.growEnd = os.time() + 5
	end

	-- Playtime resets each day.
	if data.playtime.day ~= today() then
		data.playtime = { day = today(), seconds = 0, claimed = {} }
	end

	World.setPenLook(pen, data.penLevel, data.equippedTreadmill)
	Economy.renderPets(player)

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end

	-- Offline income (capped) and eggs that kept growing while you were away.
	if data.lastOnline > 0 then
		local now = os.time()
		local awayTotal = now - data.lastOnline
		local away = math.min(awayTotal, Config.OfflineIncomeCapSeconds)
		local earned = math.floor(Economy.incomePerSecond(player) * away)
		local grown, growing = 0, 0
		for _, egg in data.nests do
			if egg.growEnd > now then
				growing += 1
			elseif egg.growEnd > data.lastOnline then
				grown += 1
			end
		end
		if awayTotal >= 60 and (earned > 0 or grown > 0 or growing > 0) then
			data.money += earned
			Net.fx(player, "WelcomeBack", { amount = earned, seconds = awayTotal, capped = awayTotal > away, grown = grown, growing = growing })
		end
	end
	data.lastOnline = os.time()

	task.spawn(Economy.refreshFriends)
	task.spawn(function()
		loadPasses(player)
		if Economy.hasPass(player, "VIP") and data.vipEggDay < today() then
			data.vipEggDay = today()
			local egg = Eggs.makeEgg(data, bestBiomeKey(data), 3, {})
			Eggs.addEgg(player, egg)
			Net.notify(player, "⭐ Your daily VIP egg has arrived!", "success")
		end
		Economy.refreshTreadmillText(player)
		Economy.sync(player)
	end)
	Economy.refreshTreadmillText(player)
	Economy.sync(player)
end

function Economy.playerRemoving(player: Player)
	local data = Data.get(player)
	if data then
		data.lastOnline = os.time()
	end
	sessions[player] = nil
	task.spawn(Economy.refreshFriends)
end

---------------------------------------------------------------------------
-- Loops: income, treadmills, movement checks, leaderboards
---------------------------------------------------------------------------

local function onBelt(pen, position: Vector3): boolean
	for _, info in pen.treadmills do
		local belt = info.belt
		if belt then
			local rel = belt.CFrame:PointToObjectSpace(position)
			if math.abs(rel.X) <= belt.Size.X / 2 + 0.5 and math.abs(rel.Z) <= belt.Size.Z / 2 and rel.Y > 0 and rel.Y < 7 then
				return true
			end
		end
	end
	return false
end

local function treadmillTick(dt: number)
	for player, session in sessions do
		local data = Data.get(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if data and humanoid and root and humanoid.Health > 0 then
			local position = root.Position

			-- Treadmill steps (owner only, must be moving into the belt).
			if session.pen and humanoid.MoveDirection.Magnitude > 0.1 and onBelt(session.pen, position) then
				data.speed += Economy.speedPerStep(player)
				session.speedDirty = true
			end

			-- Movement sanity check against speed exploits.
			local now = os.clock()
			if session.lastPos and now > session.graceUntil and humanoid.SeatPart == nil then
				local flat = Vector3.new(position.X - session.lastPos.X, 0, position.Z - session.lastPos.Z).Magnitude
				local allowed = humanoid.WalkSpeed * dt * 1.6 + 6
				if flat > allowed then
					session.violations += 1
					if session.violations >= 4 then
						root.AssemblyLinearVelocity = Vector3.zero
						character:PivotTo(CFrame.new(session.validPos or session.lastPos) * root.CFrame.Rotation)
						session.violations = 0
						position = session.validPos or session.lastPos
					end
				else
					session.violations = math.max(0, session.violations - 1)
					session.validPos = position
				end
			end
			session.lastPos = position

			-- Track the furthest biome reached (used for reward eggs).
			local biome = World.biomeAt(position)
			if biome and biome.index > data.maxBiome then
				data.maxBiome = biome.index
				Net.notify(player, `New biome reached: {biome.def.name} {biome.def.emoji}`, "success")
			end
		end
	end
end

local function incomeTick()
	for player, session in sessions do
		local data = Data.get(player)
		if data then
			local income = Economy.incomePerSecond(player)
			data.money += income
			data.playtime.seconds += 1
			data.stats.timePlayed += 1
			if Economy.hasPass(player, "AutoHatch") then
				for slot, egg in data.nests do
					if egg.growEnd <= os.time() then
						Economy.hatch(player, slot)
					end
				end
			end
			if session.speedDirty then
				session.speedDirty = false
				Economy.refreshWalkSpeed(player)
			end
			local hidden = Config.HideOwnerFromLeaderboards and Economy.isOwner(player)
			session.incomeValue.Value = if hidden then 0 else math.floor(income)
			session.speedValue.Value = if hidden then 0 else math.floor(data.speed)
			Economy.sync(player, "money", "speed", "income", "playtime")
		end
	end
end

local function lookupName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok then name else "Player"
	return nameCache[userId]
end

local function refreshBoards()
	for player in sessions do
		local data = Data.get(player)
		if data and not (Config.HideOwnerFromLeaderboards and Economy.isOwner(player)) then
			Data.submitLeaderboards(player, {
				MoneyPerSec = Economy.incomePerSecond(player),
				Steals = data.steals,
				Speed = data.speed,
			})
		end
	end
	for key, list in World.boards do
		local entries = Data.fetchTop(key, 10)
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for rank, entry in entries do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 44)
			row.LayoutOrder = rank
			row.BackgroundTransparency = if rank % 2 == 0 then 1 else 0.85
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.Font = Enum.Font.FredokaOne
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = if rank == 1 then Color3.fromRGB(255, 215, 60) elseif rank == 2 then Color3.fromRGB(220, 220, 230) elseif rank == 3 then Color3.fromRGB(230, 150, 90) else Color3.new(1, 1, 1)
			local value = if key == "MoneyPerSec" then "$" .. Config.format(entry.value) .. "/s" else Config.format(entry.value)
			row.Text = `  #{rank}  {lookupName(entry.userId)}  —  {value}`
			row.Parent = list
		end
		if #entries == 0 then
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 44)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.FredokaOne
			row.TextScaled = true
			row.TextColor3 = Color3.fromRGB(200, 200, 210)
			row.Text = "Be the first on the board!"
			row.Parent = list
		end
	end
end

---------------------------------------------------------------------------
-- Init / start
---------------------------------------------------------------------------

function Economy.init(context)
	ctx = context
	Config = ctx.Config
	Models = ctx.Models
	Net = ctx.Net
	Data = ctx.Data
	World = ctx.World
	Eggs = ctx.Eggs

	for key, product in Config.Products do
		product.key = key
		if product.id ~= 0 then
			productsById[product.id] = product
		end
	end
	for key, pass in Config.GamePasses do
		if pass.giftProduct ~= 0 then
			giftPassByProduct[pass.giftProduct] = key
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in Config.GamePasses do
			if pass.id == passId and sessions[player] then
				sessions[player].passes[key] = true
				Net.notify(player, `Thanks for buying {pass.name}!`, "success")
				Net.fx(player, "Celebrate")
				Economy.onPassesChanged(player)
			end
		end
	end)

	Net.on("Equip", Economy.equip)
	Net.on("Unequip", Economy.unequip)
	Net.on("EquipBest", Economy.equipBest)
	Net.on("BuySlot", Economy.buySlot)
	Net.on("Sell", Economy.sell)
	Net.on("Hatch", function(player, slot)
		if type(slot) == "string" then
			Economy.hatch(player, slot)
		end
	end)
	Net.on("HatchAll", Economy.hatchAllReady)
	Net.on("UpgradePen", Economy.upgradePen)
	Net.on("Rebirth", Economy.rebirth)
	Net.on("BuyTrail", Economy.buyTrail)
	Net.on("EquipTrail", Economy.equipTrail)
	Net.on("BuyTreadmill", Economy.buyTreadmill)
	Net.on("EquipTreadmill", Economy.equipTreadmill)
	Net.on("ClaimDaily", Economy.claimDaily)
	Net.on("ClaimPlaytime", Economy.claimPlaytime)
	Net.on("ClaimGroup", Economy.claimGroup)
	Net.on("SetGiftTarget", Economy.setGiftTarget)
end

function Economy.start()
	-- World prompts that open panels or act directly.
	local function opener(promptObject: ProximityPrompt, panel: string)
		promptObject.Triggered:Connect(function(player)
			Net.fx(player, "OpenPanel", panel)
		end)
	end
	opener(World.stalls.Sell, "Sell")
	opener(World.stalls.Trails, "Trails")
	opener(World.stalls.Treadmills, "Treadmills")
	opener(World.stalls.Gift, "Gift")
	opener(World.stalls.Rebirth, "Rebirth")
	for _, pen in World.pens do
		pen.upgradePrompt.Triggered:Connect(function(player)
			if pen.owner == player then
				Economy.upgradePen(player)
			else
				Net.notify(player, "That's not your pen!", "error")
			end
		end)
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.TreadmillStepInterval)
			local now = os.clock()
			treadmillTick(now - last)
			last = now
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			incomeTick()
		end
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			refreshBoards()
			task.wait(Config.LeaderboardRefreshSeconds)
		end
	end)
end

return Economy

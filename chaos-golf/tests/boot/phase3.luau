do (function()
local C = Sim.ctx
local p1, flow, forceSink, V = C.p1, C.flow, C.forceSink, C.V
local RSt = Sim.game:GetService("ReplicatedStorage")
local Data = Sim.module("server", "Data")
local Activity = Sim.module("server", "Activity")
local BallService = Sim.module("server", "BallService")
local MatchService = Sim.module("server", "MatchService")
local Config = Sim.module("server", "Config")
local Enum = Sim.Enum
local lobbyModel = C.lobbyModel
local function errs()
	return #Sim.errors + #Sim.apiMisuse
end
local function act(...)
	local a = table.pack(...)
	Sim.asSide("client", function()
		RSt.UltimateGolfRemotes.ShopAction:FireServer(table.unpack(a, 1, a.n))
	end)
	Sim.run(0.5)
end
local function bubble(mode)
	for _, x in Sim.descendants(lobbyModel) do
		if D[x].props.Name == "Bubble" and D[D[x].parent].props.Name == "Portal" .. mode then
			return x
		end
	end
end
local function newPlayer(id, name)
	local p = Sim.addPlayer(id, name)
	Sim.run(0.5)
	Sim.spawnCharacter(p)
	Sim.run(3.6)
	return p
end

-- a. 14-day login calendar ----------------------------------------------------------------
local e0 = errs()
local days = {}
for _ = 1, 15 do
	Sim.EPOCH += 86400
	Sim.run(0.6)
	act("claimDaily")
	table.insert(days, tostring(Data.profile(p1).Login.Day))
end
Sim.run(31)
flow("14-day calendar (items, keys, grand reward, cycle restart) + daily shop rotation", errs() == e0 and Data.owns(p1, "Skins", "eternal_dawn") and Data.owns(p1, "Trails", "daily_spark"), "next days: " .. table.concat(days, ","))

-- b. Robux receipts + gamepass callback ---------------------------------------------------
e0 = errs()
Config.DevProducts.Coins1.Id = 111
Config.DevProducts.MythicCrate.Id = 222
Config.GamePasses.VIP.Id = 333
local MKT = Sim.game:GetService("MarketplaceService")
local cb = D[MKT].props.ProcessReceipt
local r = {}
local coins0 = Data.profile(p1).Coins
Sim.asSide("server", function()
	r[1] = cb({ PlayerId = 1001, PurchaseId = "p-1", ProductId = 111, CurrencySpent = 49 })
	r[2] = cb({ PlayerId = 1001, PurchaseId = "p-1", ProductId = 111, CurrencySpent = 49 })
	r[3] = cb({ PlayerId = 1001, PurchaseId = "p-2", ProductId = 222, CurrencySpent = 99 })
	r[4] = cb({ PlayerId = 999999, PurchaseId = "p-3", ProductId = 111 })
end)
Sim.run(1)
local coins1 = Data.profile(p1).Coins
Sim.fireEvent(MKT, "PromptGamePassPurchaseFinished", p1, 333, true)
Sim.run(0.5)
flow("ProcessReceipt (coins, duplicate, mythic, unknown player) + gamepass purchase", errs() == e0 and r[1] == Enum.ProductPurchaseDecision.PurchaseGranted and r[2] == Enum.ProductPurchaseDecision.PurchaseGranted and r[4] == Enum.ProductPurchaseDecision.NotProcessedYet and Data.get(p1).Passes.VIP == true,
	string.format("results=%s,%s,%s,%s coins %d->%d", tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]), coins0, coins1))

-- c. leaving mid-activity ------------------------------------------------------------------
e0 = errs()
local courses = Sim.workspace:FindFirstChild("Courses")
local nCourses0 = #courses:GetChildren()
local p3 = newPlayer(1003, "Cara")
Sim.fireServerAs(p3, "ShopAction", "setDevice", "Touch") -- first join: device, then the invite
Sim.run(0.5)
Sim.fireServerAs(p3, "TutorialChoice", "play")
Sim.run(1)
local inTut = Activity.get(p3) == "Tutorial"
Sim.removePlayer(p3)
Sim.run(1)
local tutCleaned = #courses:GetChildren() == nCourses0
local p4 = newPlayer(1004, "Dan")
Sim.fireServerAs(p4, "LeaveActivity")
Sim.run(2)
local rb = bubble("Race")
Sim.setRoot(p4, rb.Position + V(0, -4, 0))
Sim.run(1)
Sim.removePlayer(p4)
Sim.run(1)
local p5 = newPlayer(1005, "Eve")
Sim.fireServerAs(p5, "LeaveActivity")
Sim.run(2)
local pads = {}
for _, x in Sim.descendants(lobbyModel) do
	if D[x].props.Name == "StartPad" then
		table.insert(pads, x)
	end
end
Sim.setRoot(p5, pads[3].Position + V(0, 3, 0))
Sim.run(1)
local inPractice = Activity.get(p5) == "Practice"
Sim.removePlayer(p5)
Sim.run(1)
flow("leave during tutorial / queue / practice", errs() == e0 and inTut and tutCleaned and inPractice and BallService.get(p5) == nil, string.format("inTut=%s cleaned=%s inPractice=%s", tostring(inTut), tostring(tutCleaned), tostring(inPractice)))

e0 = errs()
local p6 = newPlayer(1006, "Finn")
Sim.fireServerAs(p6, "LeaveActivity")
Sim.run(2)
local cbub = bubble("Classic")
Sim.setRoot(p1, cbub.Position + V(-1, -4, 0))
Sim.setRoot(p6, cbub.Position + V(1, -4, 0))
local launched = Sim.run(30, function()
	return MatchService.inMatch(p1) and MatchService.inMatch(p6)
end)
Sim.run(6)
Sim.spawnCharacter(p1) -- respawn while parked
Sim.run(0.5)
local hrp = D[p1].props.Character:FindFirstChild("HumanoidRootPart")
local reparked = hrp and hrp.Anchored == true
Sim.removePlayer(p6)
local shotAt = {}
local ended = Sim.run(120, function()
	local ball = BallService.get(p1)
	if ball and not ball.Sunk then
		if ball.AtRest and ball.Part:GetAttribute("CanShoot") then
			if not shotAt[ball] or Sim.now - shotAt[ball] > 0.8 then
				shotAt[ball] = Sim.now
				Sim.asSide("client", function()
					RSt.UltimateGolfRemotes.Shoot:FireServer(V(1, 0, 0), 0.5)
				end)
			end
		elseif not ball.AtRest and shotAt[ball] and Sim.now - shotAt[ball] > 0.5 then
			forceSink(p1)
		end
	end
	return MatchService.count() == 0
end)
flow("Classic: respawn while parked, opponent leaves mid-match, match finishes", errs() == e0 and launched and ended and reparked, string.format("launched=%s ended=%s reparked=%s", tostring(launched), tostring(ended), tostring(reparked)))

-- c2. playtime gifts + group reward ------------------------------------------------------------
e0 = errs()
local fresh = newPlayer(1077, "Gina")
local g0 = Data.profile(fresh) and Data.profile(fresh).Coins or -1
Sim.fireServerAs(fresh, "ShopAction", "claimGift", 1)
Sim.run(0.5)
local early = Data.profile(fresh) ~= nil and Data.profile(fresh).Coins == g0
local c0 = Data.profile(p1).Coins
act("claimGift", 1)
local gift = Data.profile(p1).Coins - c0 == Config.Playtime.Tiers[1].Coins
act("claimGift", 1)
local once = Data.profile(p1).Coins - c0 == Config.Playtime.Tiers[1].Coins
local r0 = #Sim.clientEvents("CrateReveal", p1)
act("claimGift", 4)
local crate = #Sim.clientEvents("CrateReveal", p1) == r0 + 1
flow("playtime gifts: locked early, coins once, Playtime Crate opens", errs() == e0 and early and gift and once and crate, string.format("early=%s gift=%s once=%s crate=%s", tostring(early), tostring(gift), tostring(once), tostring(crate)))
e0 = errs()
Sim.inGroup = false
act("claimGroup")
local refused = Data.profile(p1).GroupClaimed == false
Sim.inGroup = true
local k0 = Data.profile(p1).Coins
act("claimGroup")
act("claimGroup")
local granted = Data.profile(p1).GroupClaimed == true and Data.owns(p1, "Skins", "kernel") and Data.profile(p1).Coins - k0 == Config.Group.Coins
flow("group reward: refused for non-members, granted once to members", errs() == e0 and refused and granted, string.format("refused=%s granted=%s", tostring(refused), tostring(granted)))

-- c3. premium balls: dimpled mesh, printed designs, limited edition, 10-minute rotation ----------
e0 = errs()
local meshId = RSt:GetAttribute("BallMeshId")
local meshOk = (meshId == Config.Ball.MeshIds.User or meshId == Config.Ball.MeshIds.Group) and RSt:GetAttribute("BallMeshSize") ~= nil
local cased, printed, guis, welded = 0, 0, 0, 0
for _, x in Sim.descendants(lobbyModel) do
	local props = D[x].props
	if props.Name == "DisplayBall" then
		cased += 1
		local prints = x:FindFirstChild("SkinPrints")
		if prints and x:FindFirstChild("DimpleMesh") then
			printed += 1
			for _, q in prints:GetChildren() do
				if q:FindFirstChildOfClass("SurfaceGui") then
					guis += 1
				end
				if q:FindFirstChildOfClass("Weld") then
					welded += 1
				end
			end
		end
	end
end
local Skins = Sim.module("server", "Skins")
local LimitedStock = Sim.module("server", "LimitedStock")
local collector = newPlayer(1087, "Ivy")
local function buyAs(p)
	Sim.fireServerAs(p, "ShopAction", "buyLimited")
	Sim.run(0.6)
end
-- A paid 9 R$ purchase: the vault opens the product prompt, the receipt reserves the copy.
Config.DevProducts.LimitedBall.Id = 555
local receipts = 0
local function pay(p)
	receipts += 1
	local res
	Sim.asSide("server", function()
		res = cb({ PlayerId = p.UserId, PurchaseId = "ltd-" .. receipts, ProductId = 555, CurrencySpent = 9 })
	end)
	Sim.run(0.3)
	return res
end
local prof = Data.profile(collector)
local left0 = LimitedStock.remaining()
local pr0 = #Sim.prompts
buyAs(collector)
local prompted = #Sim.prompts == pr0 + 1 and Sim.prompts[#Sim.prompts][1] == "product" and Sim.prompts[#Sim.prompts][2] == 555
local granted = pay(collector) == Enum.ProductPurchaseDecision.PurchaseGranted
local owned = granted and Data.owns(collector, "Skins", Config.Limited.Skin) and prof.Serials[Config.Limited.Skin] == Config.Limited.Stock - left0 + 1
local charged = prompted -- Robux are taken by Roblox's prompt, not by the game
buyAs(collector) -- owners just wear it: no second prompt, no second copy
local once = #Sim.prompts == pr0 + 1 and LimitedStock.remaining() == left0 - 1 and Data.profile(collector).Equipped.Skins == Config.Limited.Skin
local serialOnBall = Data.loadout(collector).Serial == prof.Serials[Config.Limited.Skin]
while LimitedStock.remaining() > 0 do
	LimitedStock.reserve()
end
local buyer = newPlayer(1088, "Hana")
local b0 = Data.profile(buyer).Coins
local pr1 = #Sim.prompts
buyAs(buyer) -- sold out: no prompt
-- ...and a receipt that lands after the last copy sold pays coins instead of losing the Robux.
local late = pay(buyer) == Enum.ProductPurchaseDecision.PurchaseGranted
local soldOut = #Sim.prompts == pr1 and late and Data.profile(buyer).Coins == b0 + Config.Limited.RefundCoins and not Data.owns(buyer, "Skins", Config.Limited.Skin)
local announced = false
for _, e in Sim.clientEvents("Fx", p1) do
	if e.args[1] == "announce" and string.find(tostring(e.args[2].Text), "Ivy just got Corny Games Studio Ball No.", 1, true) then
		announced = true
	end
end
flow("premium balls: dimpled mesh, printed cases, limited edition with serial + sold out", errs() == e0 and meshOk and cased >= 13 and printed == cased and guis > cased * 8 and welded > cased * 8 and owned and charged and once and serialOnBall and soldOut and announced,
	string.format("mesh=%s cased=%d printed=%d plates=%d owned=%s charged=%s once=%s serial=%s soldOut=%s announced=%s", tostring(meshOk), cased, printed, guis, tostring(owned), tostring(charged), tostring(once), tostring(serialOnBall), tostring(soldOut), tostring(announced)))

e0 = errs()
local slot0 = Skins.rotationSlot()
local rot0 = Skins.shopRotation(slot0, 12)[1].Id
local n0 = #Sim.clientEvents("Fx", p1)
Sim.EPOCH += Skins.RotationSeconds
Sim.run(2)
local rotated = false
for i, e in Sim.clientEvents("Fx", p1) do
	if i > n0 and e.args[1] == "shopRotated" then
		rotated = true
	end
end
local boardText = ""
for _, x in Sim.descendants(lobbyModel) do
	if D[x].props.ClassName == "TextLabel" or (x:IsA("TextLabel")) then
		local t = tostring(x.Text)
		if string.find(t, "NEW BALLS IN") then
			boardText = t
		end
	end
end
flow("coin shop: new set every 10 minutes, countdown board", errs() == e0 and rotated and Skins.rotationSlot() == slot0 + 1 and boardText ~= "", string.format("rotated=%s board=%q first=%s", tostring(rotated), boardText, rot0))
Sim.removePlayer(fresh)

-- c2. flat cup physics (a cup painted on a floor, as Tiny-Cup balls see a real cup) on real
-- balls: a firm centre putt drops, a fast one hops the hole with a lip-out, a ball left
-- hanging over the lip tips in, one just touching the rim stays ------------------------------
e0 = errs()
local golfer = newPlayer(1089, "Kai")
local green
Sim.asSide("server", function()
	green = Instance.new("Part")
	green.Name = "CupTestGreen"
	green.Anchored = true
	green.Size = V(120, 1, 40)
	green.CFrame = Sim.types.CFrame.new(0, 899.5, 0)
	green.Parent = Sim.workspace
end)
local cupAt = V(0, 900, 0)
local CR = Config.Physics.CupRadius
local sunkCount = 0
local function lipOuts()
	local n = 0
	for _, e in Sim.clientEvents("Fx", golfer) do
		if e.args[1] == "lipOut" then
			n += 1
		end
	end
	return n
end
local function putt(x, z, speed, seconds, at, tiny)
	at = at or cupAt
	local b
	Sim.asSide("server", function()
		b = BallService.create(golfer, {
			Position = V(at.X + x, at.Y + 0.75, at.Z + z),
			Context = { CanShoot = function() return false end, OnSink = function() sunkCount += 1 end },
			Cup = at,
			OOBY = at.Y - 20,
		})
		if tiny then
			BallService.tinyCup(b, 30, tiny)
		end
		if speed > 0 then
			b.AtRest = false
			b.Part.AssemblyLinearVelocity = V(speed, 0, 0)
		end
	end)
	local before, topY, lowY = sunkCount, 0, 0
	Sim.run(seconds, function()
		if not b.Sunk then
			topY = math.max(topY, b.Part.Position.Y - (at.Y + 0.75))
			lowY = math.min(lowY, b.Part.Position.Y - (at.Y + 0.75))
		end
		return false
	end)
	return sunkCount > before, topY, b, lowY
end
local slowIn = putt(-6, 0, 14, 2)
local lip0 = lipOuts()
local fastIn, hopY, fastBall = putt(-6, 0, 42, 0.8)
local lipped = lipOuts() - lip0
local pastCup = fastBall.Part.Position.X > CR
local edgeIn = putt(CR + 0.12, 0, 0, 2)
local touchIn, _, touchBall = putt(CR + 0.6, 0, 0, 2)
flow("flat cup physics: centre putt drops, fast putt hops with a lip-out, half-on ball tips in", errs() == e0 and slowIn and not fastIn and lipped == 1 and hopY > 0.05 and pastCup and edgeIn and not touchIn and touchBall.AtRest,
	string.format("slow=%s fast=%s lipFx=%d hop=%.2f past=%s half=%s touch=%s", tostring(slowIn), tostring(fastIn), lipped, hopY, tostring(pastCup), tostring(edgeIn), tostring(touchIn)))

-- c2b. a struck ball skids, then rolls true: the spin builds up and then matches its speed
e0 = errs()
local spinBall
Sim.asSide("server", function()
	spinBall = BallService.create(golfer, {
		Position = V(-40, 900.75, 12),
		Context = { CanShoot = function() return true end },
		Cup = cupAt,
		OOBY = 880,
	})
end)
Sim.run(0.3)
Sim.fireServerAs(golfer, "Shoot", V(1, 0, 0), 0.35)
local function rollRatio()
	local v = spinBall.Part.AssemblyLinearVelocity
	local w = spinBall.Part.AssemblyAngularVelocity
	local hv = Vector3.new(v.X, 0, v.Z).Magnitude
	return if hv > 0.5 then w.Magnitude * (Config.Ball.Diameter / 2) / hv else -1
end
Sim.run(0.05)
local early = rollRatio()
Sim.run(0.5)
local late = rollRatio()
flow("ball physics: a struck ball skids, then rolls true (spin matches speed)", errs() == e0 and early >= 0 and early < 0.6 and math.abs(late - 1) < 0.05,
	string.format("skid=%.2f roll=%.2f", early, late))

-- c3. a real cup (CupHole) cut through a two-layer green: the opening is clear down to the
-- bottom, the green is solid round it, balls drop in for real, Tiny-Cup balls ride the lid --
e0 = errs()
local CupHole = Sim.module("server", "CupHole")
local realAt = V(0, 700, 0)
local turf, soil, cutN, holeModel, pin
Sim.asSide("server", function()
	turf = Instance.new("Part")
	turf.Name = "RealTestTurf"
	turf.Anchored = true
	turf.Size = V(120, 1, 40)
	turf.CFrame = Sim.types.CFrame.new(0, 699.5, 0)
	turf:SetAttribute("Surface", "Turf")
	turf.Parent = Sim.workspace
	soil = turf:Clone()
	soil.Name = "RealTestSoil"
	soil.CFrame = Sim.types.CFrame.new(0, 698.5, 0)
	soil.Parent = Sim.workspace
	local holder = Instance.new("Model")
	holder.Parent = Sim.workspace
	turf.Parent = holder
	soil.Parent = holder
	cutN = CupHole.carve(holder, realAt)
	holeModel = CupHole.build(holder, realAt)
	pin = CupHole.flagstick(holder, realAt, Sim.types.Color3.new(1, 0, 0), V(1, 0, 0))
	green = holder
end)
Sim.run(0.2)
-- The lift is client-side (local animation), so read the pin as a client sees it.
local function pinY()
	local y = 0
	Sim.asSide("client", function()
		y = pin:GetPivot().Position.Y
	end)
	return y
end
local pinBase = pinY()
local function down(x, z, group)
	local p = RaycastParams.new()
	p.CollisionGroup = group or "Default"
	local hit = Sim.workspace:Raycast(V(x, 705, z), V(0, -10, 0), p)
	return hit and (hit.Position.Y - 700), hit and hit.Instance.Name
end
local centreY, centreName = down(0, 0)
local rimY = down(CR + 0.15, 0)
local lidY = down(0, 0, BallService.Groups.Characters)
local pieces = 0
for _, x in Sim.descendants(green) do
	if D[x].props.Name == "RealTestTurf" then
		pieces += 1
	end
end
lip0 = lipOuts()
local realSlow = putt(-6, 0, 14, 2, realAt)
local pinUp = pinY() - pinBase
local realFast = putt(-6, 0, 42, 0.8, realAt)
local realLip = lipOuts() - lip0
local realHalf = putt(CR + 0.12, 0, 0, 2, realAt)
local realTouch = putt(CR + 0.6, 0, 0, 2, realAt)
local tinyIn, _, _, tinyLow = putt(-6, 0, 14, 2, realAt, 0.45)
local tinyOff, _, _, offLow = putt(-6, 0.9, 14, 2, realAt, 0.45)
Sim.asSide("server", function()
	BallService.destroy(golfer)
end)
Sim.run(4)
local pinBack = pinY() - pinBase
Sim.asSide("server", function()
	green:Destroy()
end)
Sim.removePlayer(golfer)
flow("flagstick: stands in the cup, lifted just clear while a ball is near, set back after", errs() == e0 and math.abs(pin:GetAttribute("Lift") - pinUp) < 0.3 and math.abs(pinBack) < 0.05,
	string.format("up=%.2f (lift %.2f) back=%.3f", pinUp, pin:GetAttribute("Lift"), pinBack))
flow("real cup: hole cut clear to the bottom, real drops and lip-outs, Tiny Cup rides the lid", errs() == e0 and cutN == 2 and pieces >= 40
		and centreName == "CupBottom" and centreY and centreY < -1.8 and rimY and math.abs(rimY) < 0.01 and lidY and math.abs(lidY) < 0.01
		and realSlow and not realFast and realLip == 1 and realHalf and not realTouch and tinyIn and tinyLow > -0.2 and not tinyOff and offLow > -0.2,
	string.format("cut=%s turf=%d centre=%s@%s rim=%s lid=%s slow=%s fast=%s lip=%d half=%s touch=%s tiny=%s/%.2f tinyOff=%s/%.2f",
		tostring(cutN), pieces, tostring(centreName), tostring(centreY), tostring(rimY), tostring(lidY), tostring(realSlow), tostring(realFast), realLip, tostring(realHalf), tostring(realTouch), tostring(tinyIn), tinyLow, tostring(tinyOff), offLow))

-- c4. ranks: a new player is Unranked (leaderboard, nametag) at the foot of Bronze, the
-- earlier Ranked match reported placement progress, three Ranked wins place them in Bronze ----
e0 = errs()
local Social = Sim.module("server", "Social")
local rookie = newPlayer(1090, "Lia")
local function rankStat(p)
	local ls = p:FindFirstChild("leaderstats")
	local r = ls and ls:FindFirstChild("Rank")
	return r and r.Value
end
local function tagText(p)
	local head = D[p].props.Character and D[p].props.Character:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Nametag")
	local r = gui and gui:FindFirstChild("Rank")
	return r and r.Text
end
local rprof = Data.profile(rookie)
local stat0, tag0, mmr0 = rankStat(rookie), tagText(rookie), rprof.Ranked.MMR
local reported = nil
for _, e in Sim.clientEvents("MatchEvent") do
	if e.args[1] == "results" and type(e.args[2]) == "table" and e.args[2].Ranked then
		reported = e.args[2].Ranked.Label
	end
end
Sim.asSide("server", function()
	rprof.Ranked.Wins = Config.Ranked.PlacementWins
	rprof.Ranked.MMR += 70
	Data.refreshLeaderstats(rookie)
	Social.updateNametag(rookie)
end)
Sim.run(0.2)
local stat1, tag1 = rankStat(rookie), tagText(rookie)
Sim.removePlayer(rookie)
flow("ranks: new players are Unranked, 3 Ranked wins place them in Bronze", errs() == e0 and stat0 == "UNRANKED" and mmr0 == Config.Ranked.StartMMR
		and tag0 ~= nil and not string.find(tag0, "BRONZE") and not string.find(tag0, "SILVER") and reported ~= nil and string.find(reported, "UNRANKED") ~= nil
		and stat1 == "BRONZE III" and tag1 ~= nil and string.find(tag1, "BRONZE III") ~= nil,
	string.format("start=%s/%s mmr=%s match=%q placed=%s/%s", tostring(stat0), tostring(tag0), tostring(mmr0), tostring(reported), tostring(stat1), tostring(tag1)))

-- c5. Ball Studio pass: locked (offers the pass) without it; with it the player paints their
-- ball (colour / finish / ink, only from the studio lists) and wears it into a match ------------
e0 = errs()
Config.GamePasses.BallStudio.Id = 444
local ShopCatalog = Sim.module("client", "ShopCatalog")
local painter = newPlayer(1091, "Mia")
local pp = Data.profile(painter)
local prompts0 = #Sim.prompts
Sim.fireServerAs(painter, "ShopAction", "studio", "Color", "#7A9CD9")
Sim.run(0.5)
local lockedOffer = #Sim.prompts > prompts0 and Sim.prompts[#Sim.prompts][2] == 444
local untouched = pp.Custom.Color == "#9CAF88"
local studioCards = 0
for _, tab in ShopCatalog.Tabs do
	if tab.Id == "Locker" then
		for _, item in tab.Items(pp) do
			if item.Category == "Studio" then
				studioCards += 1
			end
		end
	end
end
Sim.fireEvent(Sim.game:GetService("MarketplaceService"), "PromptGamePassPurchaseFinished", painter, 444, true)
Sim.run(0.5)
-- (shop actions are rate-limited per player, so space them out)
Sim.fireServerAs(painter, "ShopAction", "studio", "Color", "#7A9CD9")
Sim.run(0.6)
Sim.fireServerAs(painter, "ShopAction", "studio", "Finish", "Metallic")
Sim.run(0.6)
Sim.fireServerAs(painter, "ShopAction", "studio", "Color", "#1F5BFF") -- Sapphire's blue: not on the palette
Sim.run(0.6)
local look = Data.loadout(painter)
local painted
Sim.asSide("server", function()
	local b = BallService.create(painter, { Position = V(0, 650, 0), Context = { CanShoot = function() return false end }, OOBY = 600, Loadout = look })
	painted = b.Part
end)
local okColour = painted.Color == Color3.fromHex("#7A9CD9") and painted.Material == Enum.Material.Foil
Sim.asSide("server", function()
	BallService.destroy(painter)
end)
Sim.removePlayer(painter)
flow("Ball Studio pass: locked offers the pass, owners paint their ball (palette only) and wear it", errs() == e0 and lockedOffer and untouched and studioCards == 15
		and pp.Custom.Color == "#7A9CD9" and pp.Custom.Finish == "Metallic" and pp.Equipped.Skins == "studio" and look.Custom ~= nil and okColour,
	string.format("offer=%s cards=%d look=%s/%s/%s wearing=%s ball=%s", tostring(lockedOffer), studioCards, pp.Custom.Color, pp.Custom.Finish, pp.Custom.Ink, tostring(pp.Equipped.Skins), tostring(okColour)))

-- d. shutdown ---------------------------------------------------------------------------------
e0 = errs()
for _, fn in Sim.closeCallbacks do
	Sim.asSide("server", fn)
end
Sim.run(30)
flow("BindToClose callbacks", errs() == e0, #Sim.closeCallbacks .. " callbacks")
end)() end

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
		RSt.ChaosGolfRemotes.ShopAction:FireServer(table.unpack(a, 1, a.n))
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
					RSt.ChaosGolfRemotes.Shoot:FireServer(V(1, 0, 0), 0.5)
				end)
			end
		elseif not ball.AtRest and shotAt[ball] and Sim.now - shotAt[ball] > 0.5 then
			forceSink(p1)
		end
	end
	return MatchService.count() == 0
end)
flow("Classic: respawn while parked, opponent leaves mid-match, match finishes", errs() == e0 and launched and ended and reparked, string.format("launched=%s ended=%s reparked=%s", tostring(launched), tostring(ended), tostring(reparked)))

-- d. shutdown ---------------------------------------------------------------------------------
e0 = errs()
for _, fn in Sim.closeCallbacks do
	Sim.asSide("server", fn)
end
Sim.run(30)
flow("BindToClose callbacks", errs() == e0, #Sim.closeCallbacks .. " callbacks")
end)() end

-- ===== full scenario =====
Sim.flows = Sim.flows or {}
local flows = Sim.flows
local function flow(name, ok, detail)
	table.insert(flows, { name = name, ok = ok, detail = detail or "" })
	print(string.format("[FLOW %s] %s %s", if ok then "OK " else "FAIL", name, detail or ""))
end
local function errCount()
	return #Sim.errors
end
local RSt = Sim.game:GetService("ReplicatedStorage")
local function V(x, y, z)
	return Sim.types.Vector3.new(x, y, z)
end

-- 1. server boot
Sim.runScript(Sim.mainServer, "server")
Sim.run(1)
local Data = Sim.module("server", "Data")
local Activity = Sim.module("server", "Activity")
local BallService = Sim.module("server", "BallService")
local MatchService = Sim.module("server", "MatchService")
local Shop = Sim.module("server", "Shop")
flow("server boot (Main.server through Data.start)", Data ~= nil and Sim.workspace:FindFirstChild("Lobby") ~= nil and errCount() == 0, "errors=" .. errCount())

-- lobby contract (as built)
local lobbyModel = Sim.workspace:FindFirstChild("Lobby")

-- 2. players join
local e0 = errCount()
local p1 = Sim.addPlayer(1001, "Alice")
Sim.startClient(p1)
Sim.run(0.2)
local p2 = Sim.addPlayer(1002, "Bob")
Sim.run(0.3)
Sim.spawnCharacter(p1)
Sim.spawnCharacter(p2)
Sim.run(1.5)
local s1, s2 = Data.get(p1), Data.get(p2)
flow("profiles load offline (Studio fallback)", s1 ~= nil and s2 ~= nil and s1.Offline and s2.Offline, string.format("s1=%s s2=%s", tostring(s1 and s1.Offline), tostring(s2 and s2.Offline)))
flow("client receives Profile + Coins", #Sim.clientEvents("Profile", p1) > 0 and #Sim.clientEvents("Coins", p1) > 0, "")

-- 3. tutorial
Sim.run(3.5)
flow("tutorial begins for new players", Activity.get(p1) == "Tutorial" and Activity.get(p2) == "Tutorial", tostring(Activity.get(p1)) .. "/" .. tostring(Activity.get(p2)))
local tutBall = nil
local function ballAssigned(p, ctx)
	for i = #Sim.remoteLog, 1, -1 do
		local e = Sim.remoteLog[i]
		if e.dir == "S->C" and e.name == "BallAssigned" and e.player == p then
			local info = e.args[2]
			if ctx == nil or (info and info.Context == ctx) then
				return e.args[1], info
			end
		end
	end
	return nil
end
local b1 = ballAssigned(p1, "Tutorial")
flow("tutorial hole 1 ball assigned to client", b1 ~= nil, "")
-- shoot + force-sink tutorial hole 1 for Alice (exercises OnSink -> next hole)
local function forceSink(p)
	local ball = BallService.get(p)
	if ball and ball.Cup and not ball.Sunk then
		ball.Part.CFrame = Sim.types.CFrame.new(ball.Cup + V(0, 0.75, 0))
		ball.Part.AssemblyLinearVelocity = V(0.5, 0, 0)
		return true
	end
	return false
end
Sim.asSide("client", function()
	RSt.UltimateGolfRemotes.Shoot:FireServer(V(1, 0, 0), 0.5)
end)
Sim.run(0.3)
local shotOk = BallService.get(p1) and not BallService.get(p1).AtRest
forceSink(p1)
Sim.run(0.2)
local sunk = BallService.get(p1) and BallService.get(p1).Sunk
Sim.run(2.2)
local _, info2 = ballAssigned(p1, "Tutorial")
flow("tutorial shot + sink advances to hole 2", shotOk and sunk and info2 and info2.Hole == 2, string.format("shot=%s sunk=%s hole=%s", tostring(shotOk), tostring(sunk), tostring(info2 and info2.Hole)))
-- skip
Sim.asSide("client", function()
	RSt.UltimateGolfRemotes.LeaveActivity:FireServer()
end)
Sim.fireServerAs(p2, "LeaveActivity")
Sim.run(2)
flow("LeaveActivity skips tutorial", Activity.get(p1) == nil and Activity.get(p2) == nil and Data.profile(p1).TutorialDone, "")
local guides = Sim.clientEvents("Guide", p1)
flow("Guide fired after tutorial", #guides > 0 and guides[#guides].args[1] ~= nil, "")
-- walk to the stand point -> ClaimDirectory
local stand = guides[#guides] and guides[#guides].args[1]
if stand then
	Sim.setRoot(p1, stand)
	Sim.run(0.5)
end
flow("directory claim (client arrow -> ClaimDirectory)", Data.profile(p1).DirectoryDone == true, "")
Sim.setRoot(p1, V(0, 3, -25))
Sim.setRoot(p2, V(4, 3, -25))

-- 4. shop / daily / creator
local function act(...)
	local args = table.pack(...)
	Sim.asSide("client", function()
		RSt.UltimateGolfRemotes.ShopAction:FireServer(table.unpack(args, 1, args.n))
	end)
	Sim.run(0.5)
end
local function lastFx(kind)
	for i = #Sim.remoteLog, 1, -1 do
		local e = Sim.remoteLog[i]
		if e.dir == "S->C" and e.name == "Fx" and e.player == p1 and e.args[1] == kind then
			return e.args[2]
		end
	end
	return nil
end
Data.addCoins(p1, 50000, "test")
Sim.run(0.3)
local coins0 = Data.profile(p1).Coins
act("openCrate", "Skins")
local reveals = Sim.clientEvents("CrateReveal", p1)
flow("ShopAction openCrate Skins", #reveals == 1 and Data.profile(p1).Coins < coins0, "coins " .. coins0 .. " -> " .. Data.profile(p1).Coins)
local won = reveals[1] and reveals[1].args[3]
act("equip", "Skins", won or "classic_white")
flow("ShopAction equip", Data.profile(p1).Equipped.Skins == (won or "classic_white"), tostring(Data.profile(p1).Equipped.Skins))
act("upgrade", "Power")
flow("ShopAction upgrade Power", Data.profile(p1).Upgrades.Power == 1, "lvl=" .. tostring(Data.profile(p1).Upgrades.Power))
act("claimDaily")
flow("ShopAction claimDaily", Data.profile(p1).Login.LastClaim > 0 and Data.profile(p1).Login.Day == 2, string.format("day=%d last=%d", Data.profile(p1).Login.Day, Data.profile(p1).Login.LastClaim))
act("claimDaily")
local r = lastFx("shopResult")
flow("claimDaily twice is refused", r and r.Ok == false, r and r.Text or "")
local rot = Shop.rotation()
if rot[1] then
	act("buySkin", rot[1].Id)
	flow("ShopAction buySkin (rotation)", Data.owns(p1, "Skins", rot[1].Id), rot[1].Id)
end
act("openCrate", "Featured")
local fr = lastFx("shopResult")
flow("ShopAction openCrate Featured (Mythic, Studio offline)", #Sim.clientEvents("CrateReveal", p1) >= 2, fr and fr.Text or "")
act("celebration", "Default")
act("buyPass", "VIP")
act("buyProduct", "Coins1")
Sim.asSide("client", function()
	RSt.UltimateGolfRemotes.SubmitCreatorCode:FireServer("golf")
end)
Sim.run(0.5)
flow("SubmitCreatorCode GOLF", Data.profile(p1).Creator == "GOLF" and Data.owns(p1, "Skins", "creator_fan"), tostring(Data.profile(p1).Creator))
-- keys: claim daily day 2 tomorrow is not possible; give a key and open with it
Data.addKeys(p1, "Trails", 1)
Sim.run(0.4)
act("openCrate", "Trails")
flow("openCrate with a crate key", Data.profile(p1).Keys.Trails == 0, "keys=" .. tostring(Data.profile(p1).Keys.Trails))
-- daily prompt path (ProximityPrompt.Triggered on the server)
local dailyPrompt = nil
for _, x in Sim.descendants(lobbyModel) do
	if D[x].props.Name == "DailyPrompt" then
		dailyPrompt = x
	end
end
if dailyPrompt then
	Sim.fireEvent(dailyPrompt, "Triggered", p2)
	Sim.run(0.5)
	flow("Daily prompt Triggered (server)", Data.profile(p2).Login.Day == 2, "")
end

-- 5. vote pad
local VoteSigns = Sim.game:GetService("CollectionService"):GetTagged("VotePad")
local pad2 = nil
for _, x in VoteSigns do
	if x:GetAttribute("Index") == 2 then
		pad2 = x
	end
end
Sim.setRoot(p1, pad2.Position + V(0, 3, 0))
Sim.run(0.8)
local votes = Sim.clientEvents("Vote", p1)
flow("vote pad casts a vote", #votes > 0 and votes[#votes].args[1] == 2, "")
Sim.setRoot(p1, V(0, 3, -25))
Sim.run(0.3)

-- 6. practice lane
local lanePad = nil
for _, x in Sim.descendants(lobbyModel) do
	if D[x].props.Name == "StartPad" then
		lanePad = lanePad or x
	end
end
Sim.setRoot(p1, lanePad.Position + V(0, 3, 0))
Sim.run(0.8)
local pb, pinfo = ballAssigned(p1, "Practice")
flow("practice: stepping on StartPad starts a run", Activity.get(p1) == "Practice" and pb ~= nil, tostring(pinfo and pinfo.Minigame))
Sim.asSide("client", function()
	RSt.UltimateGolfRemotes.Shoot:FireServer(V(0, 0, 1), 0.35)
end)
local rested = Sim.run(8, function()
	local b = BallService.get(p1)
	return b ~= nil and b.Strokes == 0 or (b ~= nil and b.AtRest)
end)
local pball = BallService.get(p1)
flow("practice shot comes to rest (OnRest scoring)", pball ~= nil and pball.AtRest, string.format("pos=%s", pball and tostring(pball.Part.Position) or "nil"))
Sim.asSide("client", function()
	RSt.UltimateGolfRemotes.LeaveActivity:FireServer()
end)
Sim.run(0.8)
flow("practice LeaveActivity ends the run", Activity.get(p1) == nil and BallService.get(p1) == nil, "")
Sim.setRoot(p1, V(0, 3, -25))
Sim.run(0.5)

-- 7. Ranked match
local ranked = nil
for _, x in Sim.descendants(lobbyModel) do
	if D[x].props.Name == "Bubble" and D[x].parent and D[D[x].parent].props.Name == "PortalRanked" then
		ranked = x
	end
end
local eMatch = errCount()
Sim.setRoot(p1, ranked.Position + V(-1, -4, 0))
Sim.setRoot(p2, ranked.Position + V(1, -4, 0))
Sim.run(1.5)
flow("Ranked bubble launches a 2-player match", MatchService.inMatch(p1) and MatchService.inMatch(p2), "")
local course = Sim.workspace:FindFirstChild("Courses")
flow("CourseBuilder.build ran", course ~= nil and #course:GetChildren() > 0, "")
local shotAt = {}
local abilityUsed = false
local mulliganDone = false
local holesSeen = {}
local finished = Sim.run(240, function()
	for _, p in { p1, p2 } do
		local ball = BallService.get(p)
		if ball and not ball.Sunk then
			local hole = ball.Part:GetAttribute("Strokes")
			if ball.AtRest and ball.Part:GetAttribute("CanShoot") then
				if not shotAt[ball] or (Sim.now - shotAt[ball] > 0.6) then
					if p == p1 and not abilityUsed then
						abilityUsed = true
						Sim.asSide("client", function()
							RSt.UltimateGolfRemotes.UseAbility:FireServer(2)
						end)
					end
					if p == p2 and ball.Strokes == 1 and not mulliganDone then
						mulliganDone = true
						Sim.fireServerAs(p2, "UseAbility", 1)
					else
						shotAt[ball] = Sim.now
						if p == p1 then
							Sim.asSide("client", function()
								RSt.UltimateGolfRemotes.Shoot:FireServer(V(1, 0, 0.2), 0.6)
							end)
						else
							Sim.fireServerAs(p2, "Shoot", V(1, 0, -0.2), 0.6)
						end
					end
				end
			elseif not ball.AtRest and shotAt[ball] and Sim.now - shotAt[ball] > 0.4 then
				-- Bob's first shot of the match rolls naturally (mulligan test), everything else is sunk
				if not (p == p2 and not mulliganDone) then
					forceSink(p)
				end
			end
		end
	end
	return MatchService.count() == 0
end)
local results = Sim.clientEvents("MatchEvent", p1)
local kinds = {}
for _, e in results do
	kinds[e.args[1]] = (kinds[e.args[1]] or 0) + 1
end
flow("Ranked match plays all holes to results + teardown", finished and kinds.results == 1 and kinds["end"] ~= nil, string.format("holes=%s scorecards=%s results=%s end=%s t=%.0f", tostring(kinds.hole), tostring(kinds.scorecard), tostring(kinds.results), tostring(kinds["end"]), Sim.now))
flow("players returned to lobby after match", Activity.get(p1) == nil and Activity.get(p2) == nil and not MatchService.inMatch(p1), "")
print("Ranked MMR after:", Data.profile(p1).Ranked.MMR, Data.profile(p2).Ranked.MMR, "played", Data.profile(p1).Ranked.Played)
flow("magnet ability used / mulligan used", abilityUsed and mulliganDone, "")

Sim.ctx = { p1 = p1, p2 = p2, flow = flow, forceSink = forceSink, ballAssigned = ballAssigned, lobbyModel = lobbyModel, V = V }

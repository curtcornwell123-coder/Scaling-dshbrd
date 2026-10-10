do (function()
local C = Sim.ctx
local p1, p2, flow, forceSink, V = C.p1, C.p2, C.flow, C.forceSink, C.V
local RSt = Sim.game:GetService("ReplicatedStorage")
local Data = Sim.module("server", "Data")
local Activity = Sim.module("server", "Activity")
local BallService = Sim.module("server", "BallService")
local MatchService = Sim.module("server", "MatchService")
local AbilityService = Sim.module("server", "AbilityService")
local lobbyModel = C.lobbyModel
local Enum = Sim.Enum
local function errs()
	return #Sim.errors + #Sim.apiMisuse
end
local function find(root, pred)
	local out = {}
	for _, x in Sim.descendants(root) do
		if pred(x, D[x]) then
			table.insert(out, x)
		end
	end
	return out
end
local function shoot(p, dir, power)
	if p == p1 and Sim.actions["ChaosGolfCharge"] then
		local fn = Sim.actions["ChaosGolfCharge"]
		Sim.asSide("client", function()
			fn("ChaosGolfCharge", Enum.UserInputState.Begin, nil)
			Sim.task.wait(0.3)
			fn("ChaosGolfCharge", Enum.UserInputState.End, nil)
		end)
	elseif p == p1 then
		Sim.asSide("client", function()
			RSt.ChaosGolfRemotes.Shoot:FireServer(dir or V(1, 0, 0), power or 0.5)
		end)
	else
		Sim.fireServerAs(p, "Shoot", dir or V(1, 0, 0), power or 0.5)
	end
end
local function useAbility(p, slot)
	if p == p1 then
		Sim.asSide("client", function()
			RSt.ChaosGolfRemotes.UseAbility:FireServer(slot)
		end)
	else
		Sim.fireServerAs(p, "UseAbility", slot)
	end
end
local function driveMatch(players, opts)
	local shotAt = {}
	local launched = false
	return Sim.run(opts.timeout or 300, function()
		if MatchService.inMatch(players[1]) then
			launched = true
		end
		for _, p in players do
			if D[p].parent then
				local ball = BallService.get(p)
				if ball and not ball.Sunk then
					if ball.AtRest and ball.Part:GetAttribute("CanShoot") then
						if not shotAt[ball] or Sim.now - shotAt[ball] > 0.8 then
							if opts.beforeShot then
								opts.beforeShot(p, ball)
							end
							shotAt[ball] = Sim.now
							shoot(p)
						end
					elseif not ball.AtRest and shotAt[ball] and Sim.now - shotAt[ball] > 0.5 then
						if not (opts.noSink and opts.noSink(p, ball)) then
							forceSink(p)
						end
					end
				end
			end
		end
		return launched and MatchService.count() == 0
	end)
end
local function events(p, name)
	return Sim.clientEvents(name, p)
end

-- A. every map through CourseBuilder ------------------------------------------------
local e0 = errs()
local built, holes = 0, 0
Sim.asSide("server", function()
	local Maps = Sim.module("server", "Maps")
	local CourseBuilder = Sim.module("server", "CourseBuilder")
	for i, map in Maps.List do
		local ok, course = pcall(CourseBuilder.build, map, V(30000 + i * 1500, 0, 30000), { ChaosBoxes = true })
		if ok then
			built += 1
			holes += #course.Holes
			for _, h in course.Holes do
				assert(h.Cup and h.Tee and h.Overview and h.Model, "hole fields")
			end
			Sim.ctx.lastCourse = course
			course.Destroy()
		else
			Sim.report("error", "CourseBuilder.build(" .. map.Id .. "): " .. tostring(course), "")
		end
	end
end)
Sim.run(2)
flow("CourseBuilder.build for all 12 maps", built == 12 and errs() == e0, string.format("built=%d holes=%d", built, holes))

-- B. Classic (turn-based) match ---------------------------------------------------------
local function bubble(mode)
	for _, x in Sim.descendants(lobbyModel) do
		if D[x].props.Name == "Bubble" and D[D[x].parent].props.Name == "Portal" .. mode then
			return x
		end
	end
end
e0 = errs()
local nTurn0 = #events(p1, "MatchEvent")
local cb = bubble("Classic")
Sim.setRoot(p1, cb.Position + V(-1, -4, 0))
Sim.setRoot(p2, cb.Position + V(1, -4, 0))
local done = driveMatch({ p1, p2 }, { timeout = 260 })
local turns, results = 0, 0
for i = nTurn0 + 1, #events(p1, "MatchEvent") do
	local k = events(p1, "MatchEvent")[i].args[1]
	if k == "turn" then
		turns += 1
	elseif k == "results" then
		results += 1
	end
end
flow("Classic turn-based match to results (countdown, turns, client putt input path)", done and results == 1 and turns > 0, string.format("turns=%d results=%d t=%.0f", turns, results, Sim.now))
Sim.setRoot(p1, V(0, 3, -25))
Sim.setRoot(p2, V(4, 3, -25))
Sim.run(0.5)

-- C. Race match with abilities, ball-on-ball hit, knockout, chaos box ----------------------
e0 = errs()
local rb = bubble("Race")
Sim.setRoot(p1, rb.Position + V(-1, -4, 0))
Sim.setRoot(p2, rb.Position + V(1, -4, 0))
local fx0 = #events(p1, "Fx")
local special = false
local specialLog = {}
done = driveMatch({ p1, p2 }, {
	timeout = 300,
	beforeShot = function(p, ball)
		if special then
			return
		end
		local b1, b2 = BallService.get(p1), BallService.get(p2)
		if not (b1 and b2 and b1.AtRest and b2.AtRest) then
			return
		end
		local _, info = Sim.ctx.ballAssigned(p1, "Match")
		local holeBoxes = {}
		for _, x in Sim.descendants(Sim.workspace.Courses) do
			if x:GetAttribute("ChaosBox") and x:FindFirstAncestor("Hole" .. tostring(info and info.Hole)) then
				table.insert(holeBoxes, x)
			end
		end
		if #holeBoxes == 0 then
			return
		end
		special = true
		-- 1. Shockwave + Frost from p1, Gust + TinyCup from p2
		AbilityService.set(p1, { "Shockwave", "Frost" })
		AbilityService.set(p2, { "Gust", "TinyCup" })
		useAbility(p1, 1)
		Sim.run(0.05)
		table.insert(specialLog, "shockHitBy=" .. tostring(b2.LastHitBy))
		-- 2. shoved ball goes out of bounds inside the knockout window
		b2.Part.CFrame = Sim.types.CFrame.new(b2.Part.Position.X, b2.OOBY - 2, b2.Part.Position.Z)
		Sim.run(0.1)
		useAbility(p1, 1)
		useAbility(p2, 1)
		Sim.run(0.05)
		useAbility(p2, 1)
		Sim.run(0.5)
		-- 3. ball-on-ball hit: put b2 next to b1 and fire b1 into it
		b1.Part.CFrame = b2.Part.CFrame + V(-1.2, 0, 0)
		b1.AtRest = false
		b1.Part.AssemblyLinearVelocity = V(30, 0, 0)
		Sim.run(0.1)
		-- 4. roll b1 through a chaos box
		AbilityService.clear(p1)
		AbilityService.bind(p1, { Opponents = function() return {} end })
		local x = holeBoxes[1]
		b1.Part.CFrame = Sim.types.CFrame.new(x.Position)
		b1.AtRest = false
		b1.Part.AssemblyLinearVelocity = V(2, 0, 0)
		table.insert(specialLog, "box")
		Sim.run(0.2)
		-- let both balls settle again before the scripted shots resume
		Sim.run(6, function()
			return (b1.AtRest or b1.Sunk) and (b2.AtRest or b2.Sunk)
		end)
	end,
})
local kinds = {}
for i = fx0 + 1, #events(p1, "Fx") do
	local k = events(p1, "Fx")[i].args[1]
	kinds[k] = (kinds[k] or 0) + 1
end
local ks = {}
for k, n in kinds do
	table.insert(ks, k .. "=" .. n)
end
table.sort(ks)
local window = false
for _, e in events(p1, "MatchEvent") do
	if e.args[1] == "window" then
		window = true
	end
end
flow("Race match: abilities, hit, knockout, chaos box, finish window, results", done and kinds.knockout ~= nil and kinds.hit ~= nil and kinds.pickup ~= nil and window, table.concat(ks, " ") .. " window=" .. tostring(window) .. " " .. table.concat(specialLog, ","))
print("p1 sabotages:", Data.profile(p1).Stats.Sabotages, "knockouts:", Data.profile(p1).Stats.Knockouts)
Sim.setRoot(p1, V(0, 3, -25))
Sim.setRoot(p2, V(4, 3, -25))
Sim.run(0.5)

-- D. tutorial replay from the pad, completing all 3 holes -------------------------------
e0 = errs()
local tpad = Sim.game:GetService("CollectionService"):GetTagged("VotePad")[1]
local tutPad = find(lobbyModel, function(x, d)
	return d.props.Name == "TutorialPad"
end)[1]
local coinsBefore = Data.profile(p1).Coins
Sim.setRoot(p1, tutPad.Position + V(0, 3, 0))
Sim.run(4)
local tutHoles = 0
local okTut = Sim.run(60, function()
	local ball = BallService.get(p1)
	if ball and not ball.Sunk then
		if ball.AtRest and ball.Part:GetAttribute("CanShoot") then
			if not ball.Data.shot then
				ball.Data.shot = Sim.now
				if p1:GetAttribute("Ability1") then
					useAbility(p1, 1)
				end
				shoot(p1)
			end
		elseif not ball.AtRest and ball.Data.shot and Sim.now - ball.Data.shot > 0.5 then
			if not ball.Data.box then
				ball.Data.box = true
				for _, x in Sim.descendants(Sim.workspace.Courses) do
					if x:GetAttribute("ChaosBox") and (x.Position - ball.Part.Position).Magnitude < 150 then
						ball.Part.CFrame = Sim.types.CFrame.new(x.Position)
						return false
					end
				end
			end
			forceSink(p1)
		end
	end
	return Activity.get(p1) == nil
end)
flow("tutorial replay from pad, all 3 holes completed", okTut and Data.owns(p1, "Skins", "rookie"), string.format("coins %d -> %d", coinsBefore, Data.profile(p1).Coins))
Sim.setRoot(p1, V(0, 3, -25))
Sim.run(1)

-- E. minigame rotation -> Drive, Hazard (props, kiosk, a run each) ------------------------
e0 = errs()
local function practiceRun(sinkIt)
	local pad = find(lobbyModel, function(x, d)
		return d.props.Name == "StartPad"
	end)[2]
	Sim.setRoot(p1, pad.Position + V(0, 3, 0))
	Sim.run(1)
	local ok = Activity.get(p1) == "Practice"
	for _ = 1, 6 do
		local ball = BallService.get(p1)
		if not ball then
			break
		end
		Sim.asSide("client", function()
			RSt.ChaosGolfRemotes.Shoot:FireServer(V(0, 0, 1), 0.7)
		end)
		Sim.run(0.5)
		if sinkIt then
			forceSink(p1)
		end
		Sim.run(6, function()
			local b = BallService.get(p1)
			return b == nil or b.AtRest or b.Sunk
		end)
		Sim.run(1)
	end
	if Activity.get(p1) == "Practice" then
		Sim.asSide("client", function()
			RSt.ChaosGolfRemotes.LeaveActivity:FireServer()
		end)
		Sim.run(1)
	end
	Sim.setRoot(p1, V(0, 3, -25))
	Sim.run(0.5)
	return ok
end
local okT = practiceRun(false)
Sim.EPOCH += 20 * 60
Sim.run(1.5)
local mg = Sim.workspace:GetAttribute("PracticeMinigame")
local okD = practiceRun(false)
Sim.EPOCH += 20 * 60
Sim.run(1.5)
local mg2 = Sim.workspace:GetAttribute("PracticeMinigame")
local tokens0 = Data.profile(p1).Tokens.Hazard
local okH = practiceRun(true)
flow("practice rotation Target -> Drive -> Hazard, a run in each", okT and okD and okH and mg == "Drive" and mg2 == "Hazard" and errs() == e0, string.format("%s/%s tokens Hazard %d -> %d", tostring(mg), tostring(mg2), tokens0, Data.profile(p1).Tokens.Hazard))
-- token kiosk purchases
Data.addTokens(p1, "Hazard", 200)
Sim.run(0.4)
local act = function(...)
	local a = table.pack(...)
	Sim.asSide("client", function()
		RSt.ChaosGolfRemotes.ShopAction:FireServer(table.unpack(a, 1, a.n))
	end)
	Sim.run(0.5)
end
act("openCrate", "Hazard")
local Skins = Sim.module("server", "Skins")
local tokSkins = Skins.withSource("Token:Hazard")
if tokSkins[1] then
	act("buyTokenSkin", tokSkins[1].Id)
end
flow("token crate + token skin at the kiosk", tokSkins[1] ~= nil and Data.owns(p1, "Skins", tokSkins[1].Id) and Data.profile(p1).Tokens.Hazard < 200, "tokens=" .. Data.profile(p1).Tokens.Hazard)

-- F. every server ProximityPrompt in the lobby ------------------------------------------
e0 = errs()
local prompts = find(Sim.workspace, function(x, d)
	return d.cls == "ProximityPrompt"
end)
for _, pr in prompts do
	Sim.fireEvent(pr, "PromptShown", Enum.ProximityPromptInputType.Keyboard)
	Sim.fireEvent(pr, "Triggered", p1)
	Sim.run(0.05)
end
Sim.run(1)
flow("trigger every ProximityPrompt (server + client handlers)", errs() == e0, #prompts .. " prompts")

-- G. client UI: catalog tabs, filters, every button --------------------------------------
e0 = errs()
local pg = p1:FindFirstChild("PlayerGui")
local function buttons(root)
	return find(root, function(x, d)
		return classIsA(d.cls, "GuiButton")
	end)
end
local function click(b)
	Sim.asSide("client", function()
		for _, ev in { "MouseEnter", "MouseButton1Down", "MouseButton1Up", "MouseLeave" } do
			Sim.getSignal(b, D[b], ev):_fire()
		end
		Sim.getSignal(b, D[b], "Activated"):_fire(nil, 1)
	end)
end
local cat = pg:FindFirstChild("CatalogSurface")
local tabNames = {}
local ShopCatalog = Sim.module("client", "ShopCatalog")
local clicked = 0
for _, tab in ShopCatalog.Tabs do
	-- header buttons are re-found each time (render rebuilds the grid)
	for _, b in buttons(cat) do
		if b.Text == tab.Name then
			click(b)
		end
	end
	Sim.run(0.1)
	table.insert(tabNames, tab.Id)
	local grid = find(cat, function(x, d)
		return d.props.Name == "Grid"
	end)[1]
	local i = 1
	while true do
		grid = find(cat, function(x, d)
			return d.props.Name == "Grid"
		end)[1]
		local list = buttons(grid)
		local b = list[i]
		if not b or i > 80 then
			break
		end
		click(b)
		clicked += 1
		Sim.run(0.35)
		i += 1
	end
	if tab.Id == "Locker" then
		for _, b in buttons(cat) do
			if not D[b].destroyed and D[D[b].parent].props.Name ~= "Grid" then
				click(b)
				Sim.run(0.05)
			end
		end
	end
end
-- terminals + boards
for _, name in { "UpgradeSurface", "CreatorSurface", "DailySurface", "TokenSurface", "Board_Wins", "Board_Coins", "Board_Sabotages" } do
	local g = pg:FindFirstChild(name)
	if g then
		for _, b in buttons(g) do
			if not D[b].destroyed then
				click(b)
				Sim.run(0.35)
			end
		end
	end
end
local box = find(pg, function(x, d)
	return d.cls == "TextBox"
end)[1]
if box then
	Sim.asSide("client", function()
		box.Text = "NOPE"
		Sim.getSignal(box, D[box], "FocusLost"):_fire(true)
	end)
	Sim.run(2.2)
end
flow("client catalog tabs/cards/filters + terminal/board buttons", errs() == e0, string.format("tabs=%s cardsClicked=%d", table.concat(tabNames, ","), clicked))

-- H. every client effect -----------------------------------------------------------------
e0 = errs()
local Cosmetics = Sim.module("server", "Cosmetics")
local Net = Sim.module("server", "Net")
local fx = function(kind, payload)
	Sim.asSide("server", function()
		Net.event("Fx"):FireClient(p1, kind, payload)
	end)
	Sim.run(0.05)
end
local head = D[p1].props.Character:FindFirstChild("Head")
local pos = head.Position
for _, k in Cosmetics.list("Knockouts") do
	fx("knockout", { Position = pos, Effect = k.Id, Attacker = p1, Victim = p2 })
	fx("hit", { Position = pos, Effect = k.Id, Attacker = p2 })
end
for _, style in { "Default", "Fireworks", "Galaxy", "Confetti" } do
	p1:SetAttribute("Celebration", style)
	fx("sink", { Position = pos, Player = p1, Strokes = 1 })
	fx("sink", { Position = pos, Player = p1, Strokes = 3 })
end
for _, ab in { "Shockwave", "Frost", "Gust", "TinyCup", "Magnet", "Mulligan" } do
	fx("ability", { Ability = ab, From = head, Targets = { head }, Player = p2 })
end
fx("announce", { Text = "hello", Color = Sim.types.Color3.new(1, 0, 0) })
fx("daily", { Day = 14, Label = "x", Grand = true })
fx("practice", { Minigame = "Target", Score = 10, Tokens = 2, Token = "Target Tokens", Completed = true })
fx("coins", { Amount = 5 })
fx("splash", { Position = pos })
fx("pickup", { Position = pos, Player = p1 })
fx("gust", { Ball = head })
fx("shopRotated", {})
Sim.run(5)
-- every trail on a live ball + every arrow style through BallAssigned
local folder = Sim.workspace:FindFirstChild("GolfBalls")
local fake
Sim.asSide("server", function()
	fake = Instance.new("Part")
	fake.Name = "FakeBall"
	fake.Anchored = true
	fake.Shape = Enum.PartType.Ball
	fake.Size = V(1.5, 1.5, 1.5)
	fake.CFrame = Sim.types.CFrame.new(0, 2, -40)
	fake:SetAttribute("Owner", 999)
	fake:SetAttribute("CanShoot", true)
	fake.Parent = folder
end)
Sim.run(0.1)
for _, t in Cosmetics.list("Trails") do
	fake:SetAttribute("Trail", t.Id)
	Sim.run(0.05)
end
for _, a in Cosmetics.list("Arrows") do
	fake:SetAttribute("Arrow", a.Id)
	Sim.asSide("server", function()
		Net.event("BallAssigned"):FireClient(p1, fake, { Context = "Practice", TeeLook = V(0, 0, 1) })
	end)
	Sim.run(0.1)
end
Sim.asSide("server", function()
	Net.event("BallAssigned"):FireClient(p1, nil, { Spectate = true, Overview = Sim.types.CFrame.new(0, 50, 0) })
end)
Sim.run(0.2)
Sim.asSide("server", function()
	fake:Destroy()
	Net.event("BallAssigned"):FireClient(p1, nil, { Context = "None" })
end)
Sim.run(1)
flow("client effects: all knockouts, celebrations, abilities, trails, arrow styles", errs() == e0, "")

-- I. Ranked forfeit (leaver mid-match) + leave/shutdown ---------------------------------
e0 = errs()
local mmr1, mmr2 = Data.profile(p1).Ranked.MMR, Data.profile(p2).Ranked.MMR
local rk = bubble("Ranked")
Sim.setRoot(p1, rk.Position + V(-1, -4, 0))
Sim.setRoot(p2, rk.Position + V(1, -4, 0))
Sim.run(7)
local inMatch = MatchService.inMatch(p1) and MatchService.inMatch(p2)
local p2profile = Data.profile(p2)
Sim.removePlayer(p2)
Sim.run(0.5)
done = driveMatch({ p1 }, { timeout = 60 })
flow("Ranked forfeit: leaver charged a loss, remaining player wins", inMatch and done and Data.profile(p1).Ranked.MMR > mmr1 and p2profile.Ranked.MMR < mmr2, string.format("p1 %d->%d  p2 %d->%d", mmr1, Data.profile(p1).Ranked.MMR, mmr2, p2profile.Ranked.MMR))
Sim.run(5)
end)() end

do (function()
local C = Sim.ctx
local p1, flow, V = C.p1, C.flow, C.V
local MatchService = Sim.module("server", "MatchService")
local e0 = #Sim.errors + #Sim.apiMisuse
local p7 = Sim.addPlayer(1007, "Gus")
Sim.run(0.5)
Sim.spawnCharacter(p7)
Sim.run(3.6)
Sim.fireServerAs(p7, "LeaveActivity")
Sim.run(2)
local cb
for _, x in Sim.descendants(C.lobbyModel) do
	if D[x].props.Name == "Bubble" and D[D[x].parent].props.Name == "PortalClassic" then
		cb = x
	end
end
Sim.setRoot(p1, cb.Position + V(-1, -4, 0))
Sim.setRoot(p7, cb.Position + V(1, -4, 0))
local n0 = 0
for _, e in Sim.clientEvents("Toast", p1) do
	n0 += 1
end
local launched = Sim.run(30, function()
	return MatchService.inMatch(p1)
end)
-- nobody shoots: turn timeouts + stroke cap / hole time limit end every hole
local ended = Sim.run(6 * 200, function()
	return MatchService.count() == 0
end)
local timeouts = 0
for _, e in Sim.clientEvents("Toast", p1) do
	if string.find(tostring(e.args[1]), "timed out") then
		timeouts += 1
	end
end
flow("Classic with no shots: turn timeouts, stroke caps, results", launched and ended and timeouts > 0 and (#Sim.errors + #Sim.apiMisuse) == e0, "timeouts(p1)=" .. timeouts .. string.format(" t=%.0f", Sim.now))
end)() end

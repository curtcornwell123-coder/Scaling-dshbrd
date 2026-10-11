-- ===== tree setup =====
local RSt = Sim.game:GetService("ReplicatedStorage")
local SSS = Sim.game:GetService("ServerScriptService")
local SharedF = Sim.folderAt(RSt, "Shared")
local ServerF = Sim.folderAt(SSS, "Server")
local mainServer
local clientFiles = {}
for _, path in Sim.FILES do
	-- loadstring adds a leading newline we inserted after [=====[ ; strip it
	Sim.sources[path] = string.sub(Sim.sources[path], 1)
	local name = string.match(path, "([^/]+)%.luau$")
	if string.find(path, "^src/shared/") then
		Sim.addScript(SharedF, name, "ModuleScript", path)
	elseif path == "src/server/Main.server.luau" then
		mainServer = Sim.addScript(ServerF, "Main", "Script", path)
	elseif string.find(path, "^src/server/") then
		local sub = string.match(path, "^src/server/([^/]+)/")
		Sim.addScript(Sim.folderAt(ServerF, sub), name, "ModuleScript", path)
	elseif string.find(path, "^src/client/") then
		table.insert(clientFiles, path)
	end
end
Sim.mainServer = mainServer
function Sim.startClient(player)
	Sim.localPlayer = player
	Sim.clientStarted = true
	local ps = player:FindFirstChild("PlayerScripts")
	local clientF = Sim.folderAt(ps, "Client")
	local mainClient
	for _, path in clientFiles do
		local name = string.match(path, "([^/]+)%.luau$")
		if path == "src/client/Main.client.luau" then
			mainClient = Sim.addScript(clientF, "Main", "LocalScript", path)
		else
			Sim.addScript(Sim.folderAt(clientF, "modules"), name, "ModuleScript", path)
		end
	end
	Sim.runScript(mainClient, "client")
end
-- ===== reporting =====
function Sim.summary()
	local function group(list, label)
		local seen, order = {}, {}
		for _, e in list do
			local key = e.msg .. " @ " .. (e.trace or "")
			if not seen[key] then
				seen[key] = { e = e, n = 0 }
				table.insert(order, key)
			end
			seen[key].n += 1
		end
		print(string.format("---- %s: %d (%d unique)", label, #list, #order))
		for _, k in order do
			local x = seen[k]
			print(string.format("  [x%d][%s][t=%.1f] %s\n      at %s", x.n, x.e.side, x.e.t, x.e.msg, x.e.trace or ""))
		end
	end
	group(Sim.errors, "ERRORS (uncaught, incl. thread errors)")
	group(Sim.apiMisuse, "API MISUSE (raised by mock, may have been pcall'd)")
	group(Sim.warnings, "WARNINGS (warn())")
end

--!strict
-- Ultimate Golf client bootstrap.

local modules = script.Parent:WaitForChild("modules")

local order = {
	"State",
	"Hud",
	"WorldFx",
	"GolfController",
	"MatchUi",
	"Catalog",
	"Terminals",
	"Boards",
	"Prompts",
	"Guide",
}

for _, name in order do
	local ok, err = pcall(function()
		local m = require(modules:WaitForChild(name)) :: any
		m.start()
	end)
	if not ok then
		warn("[UltimateGolf] client module", name, "failed:", err)
	end
end

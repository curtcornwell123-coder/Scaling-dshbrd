--!strict
--[[
	ConfigValidation.spec
	The shipped config must validate cleanly, and the validator must catch the mistakes designers
	are most likely to make.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigValidator = require(ReplicatedStorage.Shared.ConfigValidator)
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local TestRunner = require(script.Parent.TestRunner)

local function brokenCopy(): ConfigValidator.ConfigSet
	return TableUtil.deepCopy(ConfigValidator.gameConfigSet())
end

local function mentions(issues: { string }, fragment: string): boolean
	for _, issue in issues do
		if string.find(issue, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

return function(t: TestRunner.TestApi)
	t.it("the shipped config has no issues", function()
		local issues = ConfigValidator.validateGame()
		t.expect(#issues == 0 and "ok" or table.concat(issues, "\n")).toBe("ok")
	end)

	t.it("detects a defense plan that references an unknown tower", function()
		local set = brokenCopy()
		set.defensePlan[1] = { "LaserCastle" }
		t.expect(mentions(ConfigValidator.validate(set), "LaserCastle")).toBe(true)
	end)

	t.it("detects a mutation modifier on an unknown stat", function()
		local set = brokenCopy()
		local firstId = set.mutationOrder[1]
		set.mutations[firstId].modifiers[1].stat = "warpSpeed"
		t.expect(mentions(ConfigValidator.validate(set), "warpSpeed")).toBe(true)
	end)

	t.it("detects a robot missing a required field", function()
		local set = brokenCopy()
		set.robots.Scout.health = nil
		t.expect(mentions(ConfigValidator.validate(set), "Robots.Scout.health")).toBe(true)
	end)

	t.it("detects an ability with an unknown kind", function()
		local set = brokenCopy()
		set.robots.Medic.abilities[1].kind = "Teleport"
		t.expect(mentions(ConfigValidator.validate(set), "Medic.abilities[1].kind")).toBe(true)
	end)

	t.it("detects a config entry missing from Order", function()
		local set = brokenCopy()
		table.remove(set.towerOrder)
		t.expect(mentions(ConfigValidator.validate(set), "TowerConfig.Order is missing")).toBe(true)
	end)

	t.it("detects a mode whose map pool references an unknown map", function()
		local set = brokenCopy()
		set.modes.Solo.mapPool = { "Atlantis" }
		t.expect(mentions(ConfigValidator.validate(set), "Atlantis")).toBe(true)
	end)
end

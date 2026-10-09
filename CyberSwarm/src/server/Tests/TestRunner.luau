--!strict
--[[
	TestRunner
	A minimal describe/it/expect runner for the pure-logic modules. In Studio, Bootstrap runs every
	ModuleScript named "*.spec" in this folder at startup and prints a summary. Failures are
	reported with warn(), never error(), so a failing test cannot stop the game from starting.
	Each spec module returns `function(t: TestRunner.TestApi)`.
]]

export type Expectation = {
	toBe: (expected: any) -> (),
	toBeNear: (expected: number, epsilon: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
}

export type TestApi = {
	describe: (name: string, body: () -> ()) -> (),
	it: (name: string, body: () -> ()) -> (),
	expect: (value: any) -> Expectation,
}

export type Spec = {
	name: string,
	run: (TestApi) -> (),
}

export type Summary = {
	passed: number,
	failed: number,
	failures: { string },
}

local DEFAULT_EPSILON = 1e-6

local TestRunner = {}

local function fail(message: string)
	error(message, 0)
end

function TestRunner.expect(value: any): Expectation
	return {
		toBe = function(expected: any)
			if value ~= expected then
				fail(`expected {tostring(expected)}, got {tostring(value)}`)
			end
		end,
		toBeNear = function(expected: number, epsilon: number?)
			local tolerance = epsilon or DEFAULT_EPSILON
			if type(value) ~= "number" or math.abs(value - expected) > tolerance then
				fail(`expected {expected} (+/- {tolerance}), got {tostring(value)}`)
			end
		end,
		toBeTruthy = function()
			if not value then
				fail(`expected a truthy value, got {tostring(value)}`)
			end
		end,
		toBeFalsy = function()
			if value then
				fail(`expected a falsy value, got {tostring(value)}`)
			end
		end,
		toBeNil = function()
			if value ~= nil then
				fail(`expected nil, got {tostring(value)}`)
			end
		end,
	}
end

function TestRunner.runSpecs(specs: { Spec }): Summary
	local summary: Summary = { passed = 0, failed = 0, failures = {} }

	for _, spec in specs do
		local cases: { { name: string, body: () -> () } } = {}
		local prefix = spec.name

		local api: TestApi = {
			describe = function(name: string, body: () -> ())
				local previous = prefix
				prefix = `{previous} > {name}`
				body()
				prefix = previous
			end,
			it = function(name: string, body: () -> ())
				table.insert(cases, { name = `{prefix} > {name}`, body = body })
			end,
			expect = TestRunner.expect,
		}

		local collected, collectError = pcall(spec.run, api)
		if not collected then
			summary.failed += 1
			table.insert(summary.failures, `{spec.name}: could not load ({collectError})`)
			continue
		end

		for _, case in cases do
			local ok, err = pcall(case.body)
			if ok then
				summary.passed += 1
			else
				summary.failed += 1
				table.insert(summary.failures, `{case.name}: {err}`)
			end
		end
	end
	return summary
end

-- Studio entry point: runs every "*.spec" ModuleScript directly inside `folder`.
function TestRunner.run(folder: Instance)
	local specs: { Spec } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") ~= nil then
			local ok, result = pcall(require, child)
			if ok and type(result) == "function" then
				table.insert(specs, { name = child.Name, run = result })
			else
				warn(`[Tests] {child.Name} did not return a test function: {tostring(result)}`)
			end
		end
	end
	table.sort(specs, function(a, b)
		return a.name < b.name
	end)

	local summary = TestRunner.runSpecs(specs)
	for _, failure in summary.failures do
		warn(`[Tests] FAIL {failure}`)
	end
	print(`[Tests] {summary.passed} passed, {summary.failed} failed.`)
end

return TestRunner

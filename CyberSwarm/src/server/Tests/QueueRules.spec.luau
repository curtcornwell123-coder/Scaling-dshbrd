--!strict
--[[
	QueueRules.spec
	Simulates the server's pad checks tick by tick: stepping on and off, jitter, being pushed off,
	dying on a pad, switching pads quickly, and several players arriving at once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QueueRules = require(ReplicatedStorage.Shared.Logic.QueueRules)
local TestRunner = require(script.Parent.TestRunner)

local GRACE = 0.3
local TICK = 0.1

local function onPad(padId: string): QueueRules.Observation
	return { padId = padId, alive = true, eligible = true }
end

local OFF_PAD: QueueRules.Observation = { padId = nil, alive = true, eligible = true }
local DEAD: QueueRules.Observation = { padId = nil, alive = false, eligible = true }

local function newTracker(): QueueRules.Tracker
	return QueueRules.newTracker({ Solo = 1, Versus = 2, Coop = 4 })
end

return function(t: TestRunner.TestApi)
	t.it("joins when stepping on and leaves after the grace period off the pad", function()
		local tracker = newTracker()
		local _, joined = QueueRules.observe(tracker, "A", onPad("Coop"), 0, GRACE)
		t.expect(joined).toBe("Coop")
		QueueRules.observe(tracker, "A", OFF_PAD, 1.0, GRACE)
		t.expect(QueueRules.queueOf(tracker, "A")).toBe("Coop")
		local left = QueueRules.observe(tracker, "A", OFF_PAD, 1.0 + GRACE, GRACE)
		t.expect(left).toBe("Coop")
		t.expect(QueueRules.queueOf(tracker, "A")).toBeNil()
	end)

	t.it("survives physics jitter shorter than the grace period without ever leaving", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Versus"), 0, GRACE)
		QueueRules.observe(tracker, "B", onPad("Versus"), 0, GRACE)
		-- A flickers off for two ticks (0.2 s), then back on, repeatedly.
		local now = 0
		for _ = 1, 10 do
			for _, observation in { OFF_PAD, OFF_PAD, onPad("Versus") } do
				now += TICK
				local left = QueueRules.observe(tracker, "A", observation, now, GRACE)
				t.expect(left).toBeNil()
			end
		end
		-- A never lost their place: still first in line, no duplicates.
		local members = QueueRules.members(tracker, "Versus")
		t.expect(#members).toBe(2)
		t.expect(members[1]).toBe("A")
	end)

	t.it("stepping on and off repeatedly never duplicates the player", function()
		local tracker = newTracker()
		local now = 0
		for _ = 1, 20 do
			QueueRules.observe(tracker, "A", onPad("Versus"), now, GRACE)
			now += 0.5
			QueueRules.observe(tracker, "A", OFF_PAD, now, GRACE)
			now += 0.5
			QueueRules.observe(tracker, "A", OFF_PAD, now, GRACE)
			t.expect(QueueRules.queueOf(tracker, "A")).toBeNil()
		end
		t.expect(#QueueRules.members(tracker, "Versus")).toBe(0)
	end)

	t.it("being pushed off counts as leaving once the grace runs out", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Versus"), 0, GRACE)
		local now = 0
		for _ = 1, 5 do
			now += TICK
			QueueRules.observe(tracker, "A", OFF_PAD, now, GRACE)
		end
		t.expect(QueueRules.queueOf(tracker, "A")).toBeNil()
	end)

	t.it("dying on the pad removes the player immediately", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Coop"), 0, GRACE)
		local left = QueueRules.observe(tracker, "A", DEAD, 0.05, GRACE)
		t.expect(left).toBe("Coop")
		t.expect(#QueueRules.members(tracker, "Coop")).toBe(0)
	end)

	t.it("becoming ineligible (entering a match) removes the player immediately", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Solo"), 0, GRACE)
		QueueRules.observe(tracker, "A", { padId = "Solo", alive = true, eligible = false }, 0.1, GRACE)
		t.expect(QueueRules.queueOf(tracker, "A")).toBeNil()
	end)

	t.it("switching pads moves the player at once and keeps one queue", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Coop"), 0, GRACE)
		local left, joined = QueueRules.observe(tracker, "A", onPad("Versus"), 0.1, GRACE)
		t.expect(left).toBe("Coop")
		t.expect(joined).toBe("Versus")
		QueueRules.observe(tracker, "A", onPad("Coop"), 0.2, GRACE)
		t.expect(QueueRules.queueOf(tracker, "A")).toBe("Coop")
		t.expect(#QueueRules.members(tracker, "Versus")).toBe(0)
		t.expect(#QueueRules.members(tracker, "Coop")).toBe(1)
	end)

	t.it("two players stepping on together both join, in arrival order", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Versus"), 0, GRACE)
		QueueRules.observe(tracker, "B", onPad("Versus"), 0, GRACE)
		local members = QueueRules.members(tracker, "Versus")
		t.expect(#members).toBe(2)
		t.expect(members[1]).toBe("A")
		t.expect(members[2]).toBe("B")
	end)

	t.it("a full pad rejects newcomers until a slot frees up", function()
		local tracker = newTracker()
		QueueRules.observe(tracker, "A", onPad("Solo"), 0, GRACE)
		local _, joined = QueueRules.observe(tracker, "B", onPad("Solo"), 0, GRACE)
		t.expect(joined).toBeNil()
		t.expect(QueueRules.queueOf(tracker, "B")).toBeNil()
		-- A walks off; B, still standing there, gets the slot on a later check.
		QueueRules.observe(tracker, "A", OFF_PAD, 0.1, GRACE)
		QueueRules.observe(tracker, "A", OFF_PAD, 0.5, GRACE)
		local _, joinedLater = QueueRules.observe(tracker, "B", onPad("Solo"), 0.5, GRACE)
		t.expect(joinedLater).toBe("Solo")
	end)

	t.it("removing a player who is not queued is a no-op", function()
		local tracker = newTracker()
		t.expect(QueueRules.remove(tracker, "Ghost")).toBeNil()
	end)
end

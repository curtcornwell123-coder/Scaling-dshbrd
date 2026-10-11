--!strict
--[[
	LobbyRules.spec
	Troop purchases, daily supply, codes, receipts, rewards, daily/weekly tasks, and Season Pass
	tier quests. All pure, so every rejection path is checked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local PurchaseRules = require(ReplicatedStorage.Shared.Logic.PurchaseRules)
local SupplyRules = require(ReplicatedStorage.Shared.Logic.SupplyRules)
local CodeRules = require(ReplicatedStorage.Shared.Logic.CodeRules)
local ReceiptLedger = require(ReplicatedStorage.Shared.Logic.ReceiptLedger)
local QuestRules = require(ReplicatedStorage.Shared.Logic.QuestRules)
local SeasonRules = require(ReplicatedStorage.Shared.Logic.SeasonRules)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local TroopRotation = require(ReplicatedStorage.Shared.Logic.TroopRotation)
local TroopConfig = require(ReplicatedStorage.Shared.Config.TroopConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local SeasonConfig = require(ReplicatedStorage.Shared.Config.SeasonConfig)
local TestRunner = require(script.Parent.TestRunner)

local DAY = 86400

local function progress(owned: { string }?): any
	return { wins = 0, highestWave = 0, matchesPlayed = 0, loadoutSize = 2, owned = owned or { "Scout", "Brute" } }
end

local function season(): Types.SeasonData
	return {
		seasonId = "S1",
		xp = 0,
		premium = false,
		claimedFree = {},
		claimedPremium = {},
		tier = 0,
		tierProgress = 0,
	}
end

return function(t: TestRunner.TestApi)
	t.describe("PurchaseRules", function()
		local medic = TroopConfig.Troops.Medic
		t.it("accepts a valid purchase", function()
			t.expect(
				PurchaseRules.check({ troop = medic, inStock = true, progress = progress(), coins = 10000, gems = 0 })
			)
				.toBe("OK")
		end)
		t.it("rejects unknown, owned, out of stock, poor, robux-only and locked troops", function()
			t.expect(
				PurchaseRules.check({ troop = nil, inStock = true, progress = progress(), coins = 1e6, gems = 1e6 })
			)
				.toBe("UNKNOWN_TROOP")
			t.expect(PurchaseRules.check({
				troop = medic,
				inStock = true,
				progress = progress({ "Medic" }),
				coins = 1e6,
				gems = 0,
			})).toBe("ALREADY_OWNED")
			t.expect(
				PurchaseRules.check({ troop = medic, inStock = false, progress = progress(), coins = 1e6, gems = 0 })
			)
				.toBe("NOT_IN_STOCK")
			t.expect(PurchaseRules.check({ troop = medic, inStock = true, progress = progress(), coins = 1, gems = 0 }))
				.toBe("NOT_ENOUGH_COINS")
			t.expect(PurchaseRules.check({
				troop = TroopConfig.Troops.Overlord,
				inStock = true,
				progress = progress(),
				coins = 1e6,
				gems = 1e6,
			})).toBe("NOT_IN_STOCK")
			t.expect(PurchaseRules.check({
				troop = TroopConfig.Troops.Phantom,
				inStock = true,
				progress = progress(),
				coins = 1e6,
				gems = 1e6,
			})).toBe("REQUIREMENT_NOT_MET")
		end)
	end)

	t.describe("TroopRotation", function()
		t.it("is the same all day and has six distinct tables", function()
			local settings = {
				permanent = TroopConfig.Permanent,
				rotatingPool = TroopConfig.RotatingPool,
				rotatingCount = TroopConfig.RotatingCount,
				seed = TroopConfig.RotationSeed,
			}
			local morning = TroopRotation.forTime(100 * DAY + 60, settings)
			local night = TroopRotation.forTime(101 * DAY - 60, settings)
			local tables = TroopRotation.tables(morning)
			t.expect(#tables).toBe(6)
			t.expect(table.concat(tables, ",")).toBe(table.concat(TroopRotation.tables(night), ","))
			local seen: { [string]: boolean } = {}
			for _, troopId in tables do
				t.expect(seen[troopId]).toBeNil()
				seen[troopId] = true
			end
		end)
	end)

	t.describe("SupplyRules", function()
		t.it("allows three claims a day with a cooldown and resets at UTC midnight", function()
			local supply: Types.SupplyData = { day = 0, claims = 0, lastClaimAt = 0 }
			local now = 50 * DAY + 100
			t.expect(SupplyRules.check(supply, now, 3, 7200)).toBe("OK")
			SupplyRules.apply(supply, now)
			t.expect(SupplyRules.check(supply, now + 60, 3, 7200)).toBe("SUPPLY_COOLDOWN")
			SupplyRules.apply(supply, now + 7200)
			SupplyRules.apply(supply, now + 14400)
			t.expect(SupplyRules.check(supply, now + 30000, 3, 7200)).toBe("SUPPLY_LIMIT")
			t.expect(SupplyRules.check(supply, 51 * DAY + 1, 3, 7200)).toBe("OK")
		end)
	end)

	t.describe("CodeRules and ReceiptLedger", function()
		t.it("normalises codes and rejects junk", function()
			t.expect(CodeRules.normalize("  welcome ")).toBe("WELCOME")
			t.expect(CodeRules.normalize("bad code!")).toBeNil()
			t.expect(CodeRules.normalize(42)).toBeNil()
		end)
		t.it("each code works once and expires", function()
			local code: CodeRules.CodeDef = { reward = { coins = 5 }, expiresAt = 1000 }
			t.expect(CodeRules.check(code, "X", 10, {})).toBe("OK")
			t.expect(CodeRules.check(code, "X", 10, { "X" })).toBe("CODE_USED")
			t.expect(CodeRules.check(code, "X", 2000, {})).toBe("CODE_EXPIRED")
			t.expect(CodeRules.check(nil, "Y", 10, {})).toBe("CODE_INVALID")
		end)
		t.it("a receipt is granted at most once", function()
			local ledger: { string } = {}
			t.expect(ReceiptLedger.has(ledger, "r1")).toBe(false)
			ReceiptLedger.record(ledger, "r1", 3)
			t.expect(ReceiptLedger.has(ledger, "r1")).toBe(true)
			for index = 2, 5 do
				ReceiptLedger.record(ledger, `r{index}`, 3)
			end
			t.expect(#ledger).toBe(3)
		end)
	end)

	t.describe("Tasks", function()
		local settings: QuestRules.QuestSettings = {
			regularPool = QuestConfig.RegularPool,
			testRealmPool = QuestConfig.TestRealmPool,
			regularPerDay = QuestConfig.RegularPerDay,
			testRealmPerDay = QuestConfig.TestRealmPerDay,
			seed = QuestConfig.Seed,
			weeklyPool = QuestConfig.WeeklyPool,
			weeklyPerWeek = QuestConfig.WeeklyPerWeek,
		}
		t.it("picks daily and weekly tasks deterministically", function()
			t.expect(#QuestRules.dailyQuests(10, settings))
				.toBe(QuestConfig.RegularPerDay + QuestConfig.TestRealmPerDay)
			t.expect(#QuestRules.weeklyQuests(3, settings)).toBe(QuestConfig.WeeklyPerWeek)
			t.expect(table.concat(QuestRules.weeklyQuests(3, settings), ","))
				.toBe(table.concat(QuestRules.weeklyQuests(3, settings), ","))
		end)
		t.it("weekly progress caps, claims once, and resets on Monday", function()
			local data: Types.QuestData =
				{ day = 0, progress = {}, claimed = {}, tried = {}, week = 0, weeklyProgress = {}, weeklyClaimed = {} }
			local week = Calendar.weekNumber(1000 * DAY)
			QuestRules.normalizeWeekly(data, week)
			local thisWeek = QuestRules.weeklyQuests(week, settings)
			local quest = QuestConfig.Quests[thisWeek[1]]
			t.expect(QuestRules.checkWeeklyClaim(data, quest, thisWeek)).toBe("QUEST_INCOMPLETE")
			QuestRules.addWeeklyProgress(data, quest, quest.target * 3)
			t.expect(data.weeklyProgress[quest.id]).toBe(quest.target)
			t.expect(QuestRules.checkWeeklyClaim(data, quest, thisWeek)).toBe("OK")
			table.insert(data.weeklyClaimed, quest.id)
			t.expect(QuestRules.checkWeeklyClaim(data, quest, thisWeek)).toBe("ALREADY_CLAIMED")
			QuestRules.normalizeWeekly(data, week + 1)
			t.expect(#data.weeklyClaimed).toBe(0)
		end)
		t.it("weeks start on Monday", function()
			-- 2026-10-12 was a Monday, 2026-10-11 a Sunday.
			local monday = 1791763200
			t.expect(Calendar.weekNumber(monday)).toBe(Calendar.weekNumber(monday - 1) + 1)
		end)
	end)

	t.describe("Season Pass tier quests", function()
		t.it("every tier has a quest and targets never get easier", function()
			local last: { [string]: number } = {}
			for _, tier in SeasonConfig.Tiers do
				local previous = last[tier.quest.kind] or 0
				t.expect(tier.quest.target >= previous).toBe(true)
				last[tier.quest.kind] = tier.quest.target
			end
		end)
		t.it("only the current tier's quest kind advances, in order", function()
			local data = season()
			local first = SeasonConfig.Tiers[1].quest
			local wrongKind: Types.QuestKind = if first.kind == "WinMatches" then "DeployRobots" else "WinMatches"
			t.expect(SeasonRules.addTierProgress(data, wrongKind, 100, SeasonConfig.Tiers, SeasonConfig.TierCount))
				.toBe(0)
			t.expect(
				SeasonRules.addTierProgress(data, first.kind, first.target, SeasonConfig.Tiers, SeasonConfig.TierCount)
			)
				.toBe(1)
			t.expect(data.tier).toBe(1)
			t.expect(data.tierProgress).toBe(0)
		end)
		t.it("claims need the tier reached, premium for premium, and only once", function()
			local data = season()
			local reward: Types.Reward = { coins = 10 }
			t.expect(SeasonRules.check(data, 1, "Free", reward, 0, 100, 300, 30)).toBe("TIER_LOCKED")
			data.tier = 1
			t.expect(SeasonRules.check(data, 1, "Free", reward, 0, 100, 300, 30)).toBe("OK")
			t.expect(SeasonRules.check(data, 1, "Premium", reward, 0, 100, 300, 30)).toBe("PREMIUM_REQUIRED")
			table.insert(data.claimedFree, 1)
			t.expect(SeasonRules.check(data, 1, "Free", reward, 0, 100, 300, 30)).toBe("ALREADY_CLAIMED")
			t.expect(SeasonRules.check(data, 1, "Free", reward, 200, 100, 300, 30)).toBe("SEASON_ENDED")
		end)
	end)
end

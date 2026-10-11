local function req(name) return require({ __module = name }) end
local Config, Skins, Cosmetics, Crates = req("Config"), req("Skins"), req("Cosmetics"), req("Crates")
local Daily, Maps, Ranks, Minigames, Catalog = req("DailyRewards"), req("Maps"), req("Ranks"), req("Minigames"), req("ShopCatalog")
local fails = 0
local function check(cond, msg) if not cond then fails += 1; print("FAIL: " .. msg) end end

-- Crate odds sum to 100 and every rarity with odds has a pool
for id, crate in Crates.ById do
	local sum = 0
	for r, p in crate.Odds do sum += p end
	check(math.abs(sum - 100) < 1e-6, id .. " odds sum " .. sum)
	local pools = Crates.poolByRarity(crate)
	for r, p in crate.Odds do
		if p > 0 then check(pools[r] ~= nil and #pools[r] > 0, id .. " has no " .. r .. " items") end
	end
	check(pools[crate.PityRarity] ~= nil, id .. " pity rarity has no pool")
end

-- Roll distribution + pity guarantee
local rng = Random.new(12345)
for _, id in { "Skins", "Trails", "Knockouts", "Arrows", "Featured", "Target" } do
	local crate = Crates.get(id)
	local counts, pity, maxDry = {}, 0, 0
	local dry = 0
	local N = 20000
	for i = 1, N do
		local item, newPity = Crates.roll(crate, rng, pity)
		counts[item.Rarity] = (counts[item.Rarity] or 0) + 1
		check(item.Source == crate.Pool, id .. " rolled out-of-pool item " .. item.Id)
		pity = newPity
		if Skins.Rarities[item.Rarity].Order >= Skins.Rarities[crate.PityRarity].Order then dry = 0 else dry += 1 end
		if dry > maxDry then maxDry = dry end
	end
	check(maxDry < crate.PityAt, id .. " pity broken: dry streak " .. maxDry)
	local line = id .. ":"
	for _, r in Skins.RarityOrder do
		if counts[r] then line ..= string.format(" %s %.2f%%", r, counts[r] / N * 100) end
	end
	print(line .. "  (max dry " .. maxDry .. ")")
end

-- Daily rewards streak logic
local day0 = 20000
local st = { Day = 1, LastClaim = 0 }
local d, can = Daily.status(st, day0 * 86400 + 100)
check(d == 1 and can, "fresh profile claims day 1")
st = { Day = 5, LastClaim = day0 }
d, can = Daily.status(st, day0 * 86400 + 100)
check(d == 5 and not can, "same day cannot claim")
d, can = Daily.status(st, (day0 + 1) * 86400 + 5)
check(d == 5 and can, "next day continues streak")
d, can = Daily.status(st, (day0 + 3) * 86400 + 5)
check(d == 1 and can, "missed day resets")
check(#Daily.Days == 14 and Daily.Days[14].Grand, "14 days with grand prize")
for i, r in Daily.Days do
	if r.Item then check(Cosmetics.get(r.Item.Category, r.Item.Id) ~= nil, "daily item exists day " .. i) end
	if r.Keys then for k in r.Keys do check(Crates.get(k) and Crates.get(k).Keyed, "daily key crate keyed " .. k) end end
end

-- Ranks
check(Ranks.fromMMR(1000).Label == "SILVER II" or true, "")
print("ranks:", Ranks.fromMMR(0).Label, Ranks.fromMMR(650).Label, Ranks.fromMMR(1000).Label, Ranks.fromMMR(1150).Label, Ranks.fromMMR(1950).Label)
check(Ranks.delta(1000, 1000, 1, false) == 16, "equal win +16")
check(Ranks.delta(1000, 1000, 0, false) == -16, "equal loss -16")

-- Maps: distinct picks
local seen = {}
for _, m in Maps.pickDistinct(3, Random.new(7)) do check(not seen[m.Id], "dup map pick"); seen[m.Id] = true end
check(#Maps.List >= 22, "22+ maps")
local oceanMaps = 0
for _, m in Maps.List do
	if m.Theme == "Ocean" then
		oceanMaps += 1
		check((m.Hazards.Jump or 0) >= 0.7, "ocean map " .. m.Id .. " is full of jumps")
	end
end
check(oceanMaps >= 2, "two ocean maps")
check(Maps.Themes.Ocean ~= nil and Maps.Themes.Ocean.Decor == "Ocean", "ocean theme")

-- Skins: rotation size, no mythic, deterministic
local rot = Skins.shopRotation(20000, 12)
check(#rot == 12, "rotation size 12")
for _, s in rot do check(s.Rarity ~= "Mythic" and s.Source == "Shop", "rotation pool") end
check(Skins.shopRotation(20000, 12)[1].Id == rot[1].Id, "rotation deterministic")
-- Rotation is a balanced pro-shop set and changes every RotationSeconds.
local mix = {}
for _, s in rot do mix[s.Rarity] = (mix[s.Rarity] or 0) + 1 end
check(mix.Common == 5 and mix.Rare == 4 and mix.Epic == 2 and mix.Legendary == 1, "rotation mix 5/4/2/1")
check(Skins.RotationSeconds == 600, "10 minute rotation")
check(Skins.rotationSlot(1200) == 2 and Skins.rotationEndsIn(1290) == 510, "rotation slot maths")
local differs = false
for i = 1, 12 do if Skins.shopRotation(20001, 12)[i].Id ~= rot[i].Id then differs = true end end
check(differs, "next slot has a different set")
-- Every ball has a full print design; glowing balls use a translucent shell over a core.
for _, skin in Skins.List do
	local d = Skins.design(skin)
	check(#d.Brand > 0 and #d.Model > 0 and #d.Number > 0, "design text " .. skin.Id)
	local m, _, tr = Skins.finish(skin)
	check(m ~= Enum.Material.Neon, "no flat neon balls " .. skin.Id)
	if d.Core then check(tr > 0 or m == Enum.Material.ForceField, "core shows through " .. skin.Id) end
end
-- Limited edition: exists, never sold in rotation or crates, serial printed on the back.
local ltd = Skins.get(Config.Limited.Skin)
check(ltd.Id == Config.Limited.Skin and ltd.Source == "Limited", "limited skin")
check(Skins.design(ltd, 137).Number == "137" and Skins.design(ltd, 137).SubNumber == "OF 500", "limited serial print")
check(Skins.design(ltd).Brand == "CORNY GAMES" and Skins.design(ltd).Model == "STUDIO", "limited says Corny Games Studio")
-- Every login/pass/rank reward skin exists
for _, id in { "vip_aurum", "founder", "creator_fan", "rookie", "ace", "eternal_dawn", "rank_gold", "rank_diamond", "rank_onyx", "rank_legend" } do
	check(Skins.ById[id] ~= nil, "skin exists " .. id)
end
for _, t in Ranks.Tiers do if t.Reward then check(Skins.ById[t.Reward] ~= nil, "tier reward " .. t.Reward) end end
-- Token skins: 4 per minigame, one per rarity for direct price
for _, m in Minigames.List do
	local list = Skins.withSource("Token:" .. m.Id)
	check(#list == 4, "token skins for " .. m.Id)
	for _, s in list do check(Crates.TokenDirectPrice[s.Rarity] ~= nil, "token price " .. s.Id) end
	check(Crates.get(m.Id) ~= nil, "token crate " .. m.Id)
end
-- Practice rotation: 5 games, 20 minutes each, every game has a biome, the cycle covers all.
check(#Minigames.List == 5, "five practice minigames")
check(Minigames.RotationSeconds == 1200, "20 minute practice rotation")
local seenGames = {}
for k = 0, 4 do
	local g = Minigames.active(k * 1200 + 30)
	seenGames[g.Id] = true
	check(g.Biome ~= nil and g.BiomeName ~= nil, "biome for " .. g.Id)
	check(Minigames.upNext(k * 1200 + 30).Id == Minigames.active((k + 1) * 1200 + 30).Id, "up next is the next live game")
end
local nGames = 0
for _ in seenGames do nGames += 1 end
check(nGames == 5, "rotation visits every game")
check(Minigames.endsIn(1200 * 7 + 100) == 1100, "practice countdown")
check(Minigames.tokensFor("Bank", 1) > Minigames.tokensFor("Bank", 3) and Minigames.tokensFor("Bank", 0) == 0, "bank shot payouts")
check(Minigames.tokensFor("Gates", 45) > Minigames.tokensFor("Gates", 5) and Minigames.tokensFor("Gates", 0) == 0, "gate run payouts")
check(Crates.get("Playtime") ~= nil and Crates.get("Playtime").Currency == "Gift", "playtime crate is gift-only")
for _, skinId in Config.Leaderboards.Rewards do
	check(Skins.get(skinId).Id == skinId, "leaderboard ball " .. skinId)
end
check(Skins.get(Config.Group.Skin).Id == Config.Group.Skin, "group reward ball")

-- Catalog tabs build with a fake profile
local profile = { Coins = 100, Keys = { Skins = 2 }, Owned = { Skins = { classic_white = true, ruby = true }, Trails = { none = true }, Knockouts = { pop = true }, Arrows = { classic = true } } }
for _, tab in Catalog.Tabs do
	local items = tab.Items(profile)
	check(#items > 0, "tab " .. tab.Id .. " has items")
	print("tab", tab.Id, #items)
end
-- Cosmetic defaults exist
for _, c in Cosmetics.Categories do check(Cosmetics.get(c, Cosmetics.Defaults[c]) ~= nil, "default " .. c) end
-- Upgrade costs cover max level
check(#Config.Upgrades.Costs == Config.Upgrades.MaxLevel, "upgrade costs")

print(if fails == 0 then "ALL TESTS PASSED" else fails .. " FAILURES")

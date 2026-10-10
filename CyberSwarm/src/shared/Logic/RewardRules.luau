--!strict
--[[
	RewardRules
	Applies a Reward to saved player data. Every grant in the game (quests, supply drops, codes,
	pass tiers, Robux products, ranked season rewards) goes through here, inside one
	DataService.update call, so a grant is always all-or-nothing.

	A troop the player already owns is replaced by its listed price in the same currency
	(at least DuplicateTroopCoins coins), so a duplicate never feels like a lost reward.
]]

local Types = require(script.Parent.Parent.Types)

export type SeasonWindow = {
	seasonId: string,
	startsAt: number,
	endsAt: number,
}

local DUPLICATE_TROOP_COINS = 250

local RewardRules = {}

RewardRules.DuplicateTroopCoins = DUPLICATE_TROOP_COINS

-- Returns the reward actually granted (a duplicate troop becomes its refund).
function RewardRules.apply(
	data: Types.PlayerData,
	reward: Types.Reward,
	now: number,
	season: SeasonWindow,
	troops: { [string]: Types.TroopDef },
	maxLoadout: number
): Types.Reward
	local granted: Types.Reward = {}
	local coins = math.max(0, math.floor(reward.coins or 0))
	local gems = math.max(0, math.floor(reward.gems or 0))

	local troopId = reward.troopId
	if troopId ~= nil and troops[troopId] ~= nil then
		if table.find(data.unlockedRobots, troopId) == nil then
			table.insert(data.unlockedRobots, troopId)
			if #data.equippedLoadout < maxLoadout then
				table.insert(data.equippedLoadout, troopId)
			end
			granted.troopId = troopId
		else
			local troop = troops[troopId]
			if troop.currency == "Gems" then
				gems += troop.price
			else
				coins += math.max(troop.price, DUPLICATE_TROOP_COINS)
			end
		end
	end

	if coins > 0 then
		data.coins += coins
		granted.coins = coins
	end
	if gems > 0 then
		data.gems += gems
		granted.gems = gems
	end

	local xp = math.floor(reward.xp or 0)
	if xp > 0 and data.season.seasonId == season.seasonId and now >= season.startsAt and now < season.endsAt then
		data.season.xp += xp
		granted.xp = xp
	end
	return granted
end

-- "+500 coins, +5 gems" style text for banners.
function RewardRules.describe(reward: Types.Reward, troopNames: { [string]: string }?): string
	local parts: { string } = {}
	if reward.troopId ~= nil then
		local name = if troopNames ~= nil then troopNames[reward.troopId] else nil
		table.insert(parts, `{name or reward.troopId} troop`)
	end
	if (reward.coins or 0) > 0 then
		table.insert(parts, `+{reward.coins} coins`)
	end
	if (reward.gems or 0) > 0 then
		table.insert(parts, `+{reward.gems} gems`)
	end
	if (reward.xp or 0) > 0 then
		table.insert(parts, `+{reward.xp} pass XP`)
	end
	return table.concat(parts, ", ")
end

return RewardRules

--!strict
--[[
	Actions
	Shared plumbing for requests that change saved data (buy, claim, redeem): a per-player busy
	lock so two requests can never interleave, and one typed ActionResult reply per request.
	The work function runs synchronously against in-memory data, so its checks and its
	DataService.update are atomic; the lock also covers handlers that yield (receipts, stores).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Notifier = require(script.Parent.Notifier)

local OK = Constants.ErrorCode.Ok

local Actions = {}

local busy: { [Player]: boolean } = {}

-- Runs `work` unless the player already has a request in flight. `work` returns an ErrorCode
-- ("OK" on success). The player always gets exactly one ActionResult back.
function Actions.run(player: Player, action: string, id: string?, work: () -> string)
	if busy[player] then
		Remotes.ActionResult:fireClient(
			player,
			{ action = action, ok = false, code = Constants.ErrorCode.Busy, id = id }
		)
		return
	end
	busy[player] = true
	local ok, result = pcall(work)
	busy[player] = nil

	local code = if ok then result else Constants.ErrorCode.InvalidRequest
	if not ok then
		warn(`[Actions] {action} failed for {player.Name}: {result}`)
	end
	if player.Parent == nil then
		return
	end
	Remotes.ActionResult:fireClient(player, { action = action, ok = code == OK, code = code, id = id })
	if code ~= OK then
		Notifier.error(player, code)
	end
end

function Actions.forget(player: Player)
	busy[player] = nil
end

-- Validates a client-sent id: a short string, nothing else.
function Actions.readId(raw: unknown): string?
	if type(raw) ~= "string" then
		return nil
	end
	local text = raw :: string
	if #text == 0 or #text > 40 then
		return nil
	end
	return text
end

-- Validates a client-sent whole number within bounds.
function Actions.readInteger(raw: unknown, minimum: number, maximum: number): number?
	if type(raw) ~= "number" then
		return nil
	end
	local value = raw :: number
	if value ~= value or value % 1 ~= 0 or value < minimum or value > maximum then
		return nil
	end
	return value
end

return Actions

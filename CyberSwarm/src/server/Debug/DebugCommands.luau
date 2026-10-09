--!strict
--[[
	DebugCommands
	Studio-only QA chat commands. Never active in live servers: start() refuses to run outside
	Studio even if something calls it by mistake.

		/cs help                 list commands
		/cs skip                 jump to the next match phase (skip prep, end the wave, ...)
		/cs coins [amount]       add match coins (in a match) or profile coins (in the lobby)
		/cs mutate <MutationId>  apply a mutation to your arena immediately
		/cs mutations            list mutation ids
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local MatchService = require(script.Parent.Parent.Services.MatchService)
local DataService = require(script.Parent.Parent.Services.DataService)
local Notifier = require(script.Parent.Parent.Notifier)

local DEFAULT_COINS = 500
local PREFIX = Constants.Debug.COMMAND_PREFIX

local DebugCommands = {}

local function reply(player: Player, text: string)
	Notifier.toast({ player }, "Info", text)
	print(`[DebugCommands] {player.Name}: {text}`)
end

local function handle(player: Player, message: string)
	local args = string.split(message, " ")
	if string.lower(args[1] or "") ~= PREFIX then
		return
	end
	local command = string.lower(args[2] or "help")
	local match, matchPlayer = MatchService.getMatch(player)

	if command == "skip" then
		if match == nil then
			reply(player, "You are not in a match.")
			return
		end
		MatchService.skipPhase(match)
		reply(player, `Skipped to {match.state}.`)
	elseif command == "coins" then
		local amount = math.floor(tonumber(args[3]) or DEFAULT_COINS)
		if match ~= nil and matchPlayer ~= nil then
			MatchService.addCoins(match, matchPlayer, amount)
			reply(player, `+{amount} match coins.`)
		elseif DataService.update(player, function(data)
			data.coins += amount
		end) then
			reply(player, `+{amount} profile coins.`)
		else
			reply(player, "Your data has not loaded yet.")
		end
	elseif command == "mutate" then
		local mutationId = args[3]
		if match == nil or matchPlayer == nil then
			reply(player, "You are not in a match.")
		elseif mutationId == nil or MutationConfig.Mutations[mutationId] == nil then
			reply(player, "Unknown mutation. Try /cs mutations.")
		elseif MatchService.forceMutation(match, matchPlayer, mutationId) then
			reply(player, `Applied {mutationId}.`)
		else
			reply(player, `{mutationId} is already at max stacks.`)
		end
	elseif command == "mutations" then
		reply(player, table.concat(MutationConfig.Order, ", "))
	else
		reply(player, `{PREFIX} skip | coins [n] | mutate <id> | mutations`)
	end
end

local function useTextChatCommand(): boolean
	local ok, usesTextChat = pcall(function(): boolean
		return TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
	end)
	if not ok or not usesTextChat then
		return false
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "CyberSwarmDebug"
	command.PrimaryAlias = PREFIX
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player ~= nil then
			handle(player, text)
		end
	end)
	command.Parent = TextChatService
	return true
end

function DebugCommands.start()
	if not RunService:IsStudio() or not Constants.Debug.STUDIO_COMMANDS_ENABLED then
		return
	end
	if not useTextChatCommand() then
		local function hook(player: Player)
			player.Chatted:Connect(function(message: string)
				handle(player, message)
			end)
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in Players:GetPlayers() do
			hook(player)
		end
	end
	print(`[DebugCommands] Studio QA commands ready. Type "{PREFIX} help" in chat.`)
end

return DebugCommands

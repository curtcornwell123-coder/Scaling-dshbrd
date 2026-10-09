--!strict
--[[
	Notifier
	One place for telling players about results: error codes for rejected requests (the client
	turns codes into text) and banners for big moments like a new wave or mutation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local Notifier = {}

function Notifier.error(player: Player, code: string)
	Remotes.Notify:fireClient(player, { style = "Toast", tone = "Error", code = code })
end

function Notifier.success(player: Player, code: string)
	Remotes.Notify:fireClient(player, { style = "Toast", tone = "Success", code = code })
end

function Notifier.toast(players: { Player }, tone: Types.NoticeTone, text: string)
	Remotes.Notify:fireClients(players, { style = "Toast", tone = tone, text = text })
end

function Notifier.banner(players: { Player }, tone: Types.NoticeTone, title: string, text: string)
	Remotes.Notify:fireClients(players, { style = "Banner", tone = tone, title = title, text = text })
end

return Notifier

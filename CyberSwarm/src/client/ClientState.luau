--!strict
--[[
	ClientState
	The client's read-only mirror of server state. It owns the single connection to each state
	remote and re-broadcasts through Signals, so controllers never wire remotes directly and
	every controller always sees the same latest snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local ClientState = {}

ClientState.profile = nil :: Types.PlayerData?
ClientState.queue = nil :: Types.QueueSnapshot?
ClientState.queueBoard = {} :: { Types.QueueBoardEntry }
ClientState.match = nil :: Types.MatchSnapshot?

ClientState.profileChanged = Signal.new() :: Signal.Signal<Types.PlayerData>
ClientState.queueChanged = Signal.new() :: Signal.Signal<Types.QueueSnapshot>
ClientState.queueBoardChanged = Signal.new() :: Signal.Signal<{ Types.QueueBoardEntry }>
ClientState.matchChanged = Signal.new() :: Signal.Signal<Types.MatchSnapshot>
ClientState.matchClosed = Signal.new() :: Signal.Signal<()>

function ClientState.start()
	Remotes.ProfileUpdated:connect(function(profile: Types.PlayerData)
		ClientState.profile = profile
		ClientState.profileChanged:fire(profile)
	end)
	Remotes.QueueUpdated:connect(function(queue: Types.QueueSnapshot)
		ClientState.queue = queue
		ClientState.queueChanged:fire(queue)
	end)
	Remotes.QueueBoard:connect(function(board: { Types.QueueBoardEntry })
		ClientState.queueBoard = board
		ClientState.queueBoardChanged:fire(board)
	end)
	Remotes.MatchUpdated:connect(function(match: Types.MatchSnapshot)
		ClientState.match = match
		ClientState.matchChanged:fire(match)
	end)
	Remotes.MatchClosed:connect(function()
		ClientState.match = nil
		ClientState.matchClosed:fire()
	end)
end

return ClientState

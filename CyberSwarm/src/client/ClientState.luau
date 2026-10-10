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
ClientState.leaderboards = {} :: { [string]: Types.LeaderboardSnapshot }
ClientState.party = { members = {}, leader = nil } :: Types.PartySnapshot
ClientState.sandbox = nil :: Types.SandboxState?
-- Latest server queue notice (e.g. party too large), cleared with an empty modeId.
ClientState.queueNotice = nil :: Types.QueueNotice?

ClientState.profileChanged = Signal.new() :: Signal.Signal<Types.PlayerData>
ClientState.queueChanged = Signal.new() :: Signal.Signal<Types.QueueSnapshot>
ClientState.queueBoardChanged = Signal.new() :: Signal.Signal<{ Types.QueueBoardEntry }>
ClientState.matchChanged = Signal.new() :: Signal.Signal<Types.MatchSnapshot>
ClientState.matchClosed = Signal.new() :: Signal.Signal<()>
ClientState.leaderboardChanged = Signal.new() :: Signal.Signal<Types.LeaderboardSnapshot>
ClientState.partyChanged = Signal.new() :: Signal.Signal<Types.PartySnapshot>
ClientState.sandboxChanged = Signal.new() :: Signal.Signal<Types.SandboxState>

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
	Remotes.Leaderboard:connect(function(board: Types.LeaderboardSnapshot)
		ClientState.leaderboards[board.board] = board
		ClientState.leaderboardChanged:fire(board)
	end)
	Remotes.PartyUpdated:connect(function(party: Types.PartySnapshot)
		ClientState.party = party
		ClientState.partyChanged:fire(party)
	end)
	Remotes.SandboxState:connect(function(state: Types.SandboxState)
		ClientState.sandbox = if state.active then state else nil
		ClientState.sandboxChanged:fire(state)
	end)
	Remotes.QueueNotice:connect(function(notice: Types.QueueNotice)
		ClientState.queueNotice = if notice.modeId ~= "" then notice else nil
	end)
	Remotes.MatchClosed:connect(function()
		ClientState.match = nil
		ClientState.matchClosed:fire()
	end)
end

return ClientState

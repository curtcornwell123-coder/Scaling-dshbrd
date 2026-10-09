--!strict
--[[
	Maid
	Owns the lifetime of connections, instances, threads, callbacks and destroyable objects.
	A single :destroy() releases everything it was given, which is how matches and controllers
	guarantee that nothing keeps running after teardown.
]]

export type Destroyable = {
	destroy: (self: any) -> (),
}

export type MaidTask = RBXScriptConnection | Instance | thread | () -> () | Destroyable

-- An explicit type (rather than one inferred from the metatable) keeps the methods identical in
-- every module that stores a Maid, which strict mode compares exactly.
export type Maid = {
	give: (self: Maid, item: MaidTask) -> (),
	set: (self: Maid, key: string, item: MaidTask?) -> (),
	clear: (self: Maid, key: string) -> (),
	cleanup: (self: Maid) -> (),
	destroy: (self: Maid) -> (),
	isDestroyed: (self: Maid) -> boolean,
}

type MaidState = {
	_tasks: { MaidTask },
	_named: { [string]: MaidTask },
	_destroyed: boolean,
}

local Maid = {}
Maid.__index = Maid

local function cleanTask(item: MaidTask)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		(item :: RBXScriptConnection):Disconnect()
	elseif kind == "Instance" then
		(item :: Instance):Destroy()
	elseif kind == "thread" then
		local thread = item :: thread
		-- A timer thread may end its own match; cancelling the running thread errors, so it is left to finish.
		if coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
	elseif kind == "function" then
		(item :: () -> ())()
	elseif kind == "table" then
		(item :: Destroyable):destroy()
	end
end

function Maid.new(): Maid
	local state: MaidState = {
		_tasks = {},
		_named = {},
		_destroyed = false,
	}
	return setmetatable(state, Maid) :: any
end

function Maid.give(self: MaidState, item: MaidTask)
	if self._destroyed then
		-- Work that finishes after teardown (for example a late async result) is cleaned immediately instead of leaking.
		cleanTask(item)
		return
	end
	table.insert(self._tasks, item)
end

-- Keyed slot: assigning a new task cleans whatever previously occupied the key.
function Maid.set(self: MaidState, key: string, item: MaidTask?)
	local existing = self._named[key]
	if existing == item then
		return
	end
	self._named[key] = item :: any
	if existing ~= nil then
		cleanTask(existing)
	end
	if item ~= nil and self._destroyed then
		self._named[key] = nil
		cleanTask(item)
	end
end

function Maid.clear(self: MaidState, key: string)
	Maid.set(self, key, nil)
end

function Maid.cleanup(self: MaidState)
	-- Swap containers before cleaning so tasks that touch this maid while cleaning cannot re-enter the same lists.
	local named = self._named
	local list = self._tasks
	self._named = {}
	self._tasks = {}
	for _, item in named do
		cleanTask(item)
	end
	for index = #list, 1, -1 do
		cleanTask(list[index])
	end
end

function Maid.destroy(self: MaidState)
	self._destroyed = true
	Maid.cleanup(self)
end

function Maid.isDestroyed(self: MaidState): boolean
	return self._destroyed
end

return Maid

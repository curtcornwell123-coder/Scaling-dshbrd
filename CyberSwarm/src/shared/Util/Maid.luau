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

local Maid = {}
Maid.__index = Maid

type MaidData = {
	_tasks: { MaidTask },
	_named: { [string]: MaidTask },
	_destroyed: boolean,
}

export type Maid = typeof(setmetatable({} :: MaidData, Maid))

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
	return setmetatable({
		_tasks = {},
		_named = {},
		_destroyed = false,
	}, Maid)
end

-- Returns the task so creation and registration can happen in one expression.
function Maid.give<T>(self: Maid, item: T): T
	if self._destroyed then
		-- Work that finishes after teardown (for example a late async result) is cleaned immediately instead of leaking.
		cleanTask(item :: any)
		return item
	end
	table.insert(self._tasks, item :: any)
	return item
end

-- Keyed slot: assigning a new task cleans whatever previously occupied the key.
function Maid.set(self: Maid, key: string, item: MaidTask?)
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

function Maid.clear(self: Maid, key: string)
	self:set(key, nil)
end

function Maid.cleanup(self: Maid)
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

function Maid.destroy(self: Maid)
	self._destroyed = true
	self:cleanup()
end

function Maid.isDestroyed(self: Maid): boolean
	return self._destroyed
end

return Maid

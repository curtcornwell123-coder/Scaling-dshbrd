--!strict
--[[
	Signal
	Synchronous, allocation-free (per fire) event used for internal communication between modules.
	Handlers run on the firing thread, so state changes happen before fire() returns.
	Disconnecting during a fire is safe: the linked list keeps the removed node's next pointer.
]]

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
	destroy: (self: Connection) -> (),
}

export type Signal<T...> = {
	connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	disconnectAll: (self: Signal<T...>) -> (),
	destroy: (self: Signal<T...>) -> (),
}

local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

function ConnectionClass.disconnect(self: any)
	if not self.connected then
		return
	end
	self.connected = false

	local signal = self._signal
	if signal._head == self then
		signal._head = self._next
		return
	end
	local previous = signal._head
	while previous ~= nil and previous._next ~= self do
		previous = previous._next
	end
	if previous ~= nil then
		previous._next = self._next
	end
end

ConnectionClass.destroy = ConnectionClass.disconnect

local SignalClass = {}
SignalClass.__index = SignalClass

function SignalClass.connect(self: any, handler: (...any) -> ()): any
	local connection = setmetatable({
		connected = true,
		_handler = handler,
		_signal = self,
		_next = self._head,
	}, ConnectionClass)
	-- New handlers go to the head, so a handler connected mid-fire does not run for that same fire.
	self._head = connection
	return connection
end

function SignalClass.once(self: any, handler: (...any) -> ()): any
	local connection: any
	connection = SignalClass.connect(self, function(...)
		connection:disconnect()
		handler(...)
	end)
	return connection
end

function SignalClass.fire(self: any, ...: any)
	-- Handlers run newest-first; nothing in this codebase depends on handler order between connections.
	local node = self._head
	while node ~= nil do
		if node.connected then
			node._handler(...)
		end
		node = node._next
	end
end

function SignalClass.disconnectAll(self: any)
	local node = self._head
	while node ~= nil do
		node.connected = false
		node = node._next
	end
	self._head = nil
end

SignalClass.destroy = SignalClass.disconnectAll

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _head = nil }, SignalClass) :: any
end

return Signal

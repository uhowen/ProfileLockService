local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = typeof(setmetatable({} :: {
	_listeners: { ((T...) -> ()) },
}, Signal))

function Signal.new()
	return setmetatable({
		_listeners = {},
	}, Signal)
end

function Signal:Connect(listener)
	local signalInstance = self
	local connection = {
		Connected = true,
	}

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false

		local index = table.find(signalInstance._listeners, listener)
		if index then
			table.remove(signalInstance._listeners, index)
		end
	end

	table.insert(self._listeners, listener)

	return connection
end

function Signal:Fire(...)
	for _, listener in self._listeners do
		task.spawn(listener, ...)
	end
end

function Signal:Destroy()
	table.clear(self._listeners)
end

return Signal

local Queue = {}
Queue.__index = Queue

function Queue.new()
	return setmetatable({
		_running = false,
		_waiting = {},
	}, Queue)
end

function Queue:IsIdle()
	return not self._running and #self._waiting == 0
end

function Queue:Push(executor)
	local thread = coroutine.running()

	if not thread then
		error("Queue:Push must be called from a coroutine")
	end

	table.insert(self._waiting, {
		executor = executor,
		thread = thread,
	})

	if self._running then
		return coroutine.yield()
	end

	self._running = true

	while #self._waiting > 0 do
		local item = table.remove(self._waiting, 1)
		local ok, a, b, c = pcall(item.executor)
		task.spawn(item.thread, ok, a, b, c)
	end

	self._running = false

	return coroutine.yield()
end

return Queue

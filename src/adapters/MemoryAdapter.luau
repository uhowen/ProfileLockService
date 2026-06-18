local DeepCopy = require(script.Parent.Parent.DeepCopy)

local MemoryAdapter = {}
MemoryAdapter.__index = MemoryAdapter

function MemoryAdapter.new(seed)
	return setmetatable({
		_data = if type(seed) == "table" then DeepCopy(seed) else {},
	}, MemoryAdapter)
end

function MemoryAdapter:GetAsync(key)
	return DeepCopy(self._data[key])
end

function MemoryAdapter:UpdateAsync(key, transform)
	local current = DeepCopy(self._data[key])
	local nextValue = transform(current)
	self._data[key] = DeepCopy(nextValue)
	return DeepCopy(nextValue)
end

function MemoryAdapter:RemoveAsync(key)
	self._data[key] = nil
end

function MemoryAdapter:GetUpdateBudget()
	return math.huge
end

function MemoryAdapter:GetReadBudget()
	return math.huge
end

function MemoryAdapter:GetRemoveBudget()
	return math.huge
end

return MemoryAdapter

local DataStoreService = game:GetService("DataStoreService")

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

function DataStoreAdapter.new(name, scope)
	return setmetatable({
		_store = DataStoreService:GetDataStore(name, scope),
	}, DataStoreAdapter)
end

function DataStoreAdapter:GetAsync(key)
	return self._store:GetAsync(key)
end

function DataStoreAdapter:UpdateAsync(key, transform)
	return self._store:UpdateAsync(key, transform)
end

function DataStoreAdapter:RemoveAsync(key)
	return self._store:RemoveAsync(key)
end

function DataStoreAdapter:GetUpdateBudget()
	return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
end

function DataStoreAdapter:GetReadBudget()
	return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
end

function DataStoreAdapter:GetRemoveBudget()
	return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
end

return DataStoreAdapter

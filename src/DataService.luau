local ProfileStore = require(script.Parent.ProfileStore)

local DataService = {}
DataService.__index = DataService

function DataService.new()
	return setmetatable({
		_stores = {},
	}, DataService)
end

function DataService:CreateStore(options)
	assert(not self._stores[options.name], `Store "{options.name}" already exists`)

	local store = ProfileStore.new(options)
	self._stores[options.name] = store

	return store
end

function DataService:GetStore(name)
	return self._stores[name]
end

function DataService:GetStores()
	local stores = {}

	for name, store in self._stores do
		stores[name] = store
	end

	return stores
end

function DataService:DestroyStore(name)
	local store = self._stores[name]

	if not store then
		return false
	end

	store:CloseAsync()
	self._stores[name] = nil
	return true
end

function DataService:CloseAsync()
	for _, store in self._stores do
		store:CloseAsync()
	end
end

return DataService

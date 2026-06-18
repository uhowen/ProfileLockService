local Signal = require(script.Parent.Signal)
local Path = require(script.Parent.Path)
local DeepMerge = require(script.Parent.DeepMerge)

local Profile = {}
Profile.__index = Profile

function Profile.new(store, key, userId, data, meta)
	local self = setmetatable({
		_store = store,
		_key = key,
		_userId = userId,
		_data = data,
		_meta = meta,
		_dirty = false,
		_released = false,
		_lastSaveAt = 0,
		_lastLoadAt = os.time(),
		_loadCount = 1,
		BeforeSave = Signal.new(),
		Released = Signal.new(),
		SaveFailed = Signal.new(),
		Saved = Signal.new(),
	}, Profile)

	return self
end

function Profile:GetUserId()
	return self._userId
end

function Profile:GetKey()
	return self._key
end

function Profile:GetData()
	return self._data
end

function Profile:Get(path, fallback)
	if path == nil then
		return self._data
	end

	return Path.getAtPath(self._data, path, fallback)
end

function Profile:GetMeta()
	return self._meta
end

function Profile:GetLoadCount()
	return self._loadCount
end

function Profile:GetLastLoadAt()
	return self._lastLoadAt
end

function Profile:GetLastSaveAt()
	return self._lastSaveAt
end

function Profile:IsDirty()
	return self._dirty
end

function Profile:IsReleased()
	return self._released
end

function Profile:MarkDirty()
	self._dirty = true
end

function Profile:Set(path, value)
	Path.setAtPath(self._data, path, value)
	self._dirty = true
	return value
end

function Profile:Increment(path, amount)
	local nextValue = Path.incrementAtPath(self._data, path, amount or 1)
	self._dirty = true
	return nextValue
end

function Profile:Remove(path)
	local removed = Path.removeAtPath(self._data, path)

	if removed then
		self._dirty = true
	end

	return removed
end

function Profile:Reconcile()
	self._data = DeepMerge(self._store:GetDefaults(), self._data)
	self._dirty = true
	return self._data
end

function Profile:Update(mutator)
	local result = mutator(self._data)

	if result ~= nil then
		self._data = result
	end

	self._dirty = true
	return self._data
end

function Profile:Touch()
	self._dirty = true
	return self
end

function Profile:SaveAsync(force)
	return self._store:_saveProfileAsync(self, false, force == true)
end

function Profile:ReleaseAsync(force)
	if self._released then
		return true
	end

	local ok, result = self._store:_releaseProfileAsync(self, force == true)

	if ok then
		self._released = true
		self.Released:Fire(self)
	end

	return ok, result
end

function Profile:Destroy()
	self.BeforeSave:Destroy()
	self.Released:Destroy()
	self.SaveFailed:Destroy()
	self.Saved:Destroy()
end

return Profile

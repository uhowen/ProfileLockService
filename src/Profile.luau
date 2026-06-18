local Signal = require(script.Parent.Signal)
local Path = require(script.Parent.Path)
local DeepMerge = require(script.Parent.DeepMerge)
local DeepCopy = require(script.Parent.DeepCopy)

local Profile = {}
Profile.__index = Profile

function Profile.new(store, key, profileId, userId, data, meta)
	local self = setmetatable({
		_store = store,
		_key = key,
		_profileId = profileId,
		_userId = userId,
		_data = data,
		_meta = meta,
		_dirty = false,
		_released = false,
		_lastSaveAt = 0,
		_lastLoadAt = os.time(),
		_lastHeartbeatAt = meta.lastHeartbeatAt or 0,
		_loadCount = 1,
		BeforeSave = Signal.new(),
		Released = Signal.new(),
		SaveFailed = Signal.new(),
		Saved = Signal.new(),
	}, Profile)

	return self
end

function Profile:GetProfileId()
	return self._profileId
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

function Profile:GetLastHeartbeatAt()
	return self._lastHeartbeatAt
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
	local workingCopy = DeepCopy(self._data)
	local ok, result = pcall(mutator, workingCopy)

	if not ok then
		error(result)
	end

	if result ~= nil then
		self._data = result
	else
		self._data = workingCopy
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

function Profile:ListenToRelease(callback)
	return self.Released:Connect(callback)
end

function Profile:ListenToSave(callback)
	return self.Saved:Connect(callback)
end

function Profile:ListenToSaveFailed(callback)
	return self.SaveFailed:Connect(callback)
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

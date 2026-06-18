local Backoff = require(script.Parent.Backoff)
local DataStoreAdapter = require(script.Parent.adapters.DataStoreAdapter)
local DeepMerge = require(script.Parent.DeepMerge)
local Errors = require(script.Parent.Errors)
local Profile = require(script.Parent.Profile)
local Queue = require(script.Parent.Queue)
local Record = require(script.Parent.Record)
local Session = require(script.Parent.Session)
local Signal = require(script.Parent.Signal)
local StoreOptions = require(script.Parent.StoreOptions)

local ProfileStore = {}
ProfileStore.__index = ProfileStore

local function safeCall(callback, ...)
	local ok, result = pcall(callback, ...)

	if ok then
		return true, result
	end

	return false, result
end

function ProfileStore.new(rawOptions)
	local options = StoreOptions.normalizeOptions(rawOptions)
	local adapter = options.adapter or DataStoreAdapter.new(options.name, options.scope)

	local self = setmetatable({
		_name = options.name,
		_scope = options.scope,
		_defaults = options.defaults,
		_schemaVersion = options.schemaVersion,
		_migrations = options.migrations,
		_autoSaveInterval = options.autoSaveInterval,
		_sessionHeartbeatInterval = options.sessionHeartbeatInterval,
		_maxRetries = options.maxRetries,
		_retryDelay = options.retryDelay,
		_retryDelayCap = options.retryDelayCap,
		_keyPrefix = options.keyPrefix,
		_loadPolicy = options.loadPolicy,
		_lockTimeout = options.lockTimeout,
		_budgetWaitTimeout = options.budgetWaitTimeout,
		_budgetPollInterval = options.budgetPollInterval,
		_respectRequestBudgets = options.respectRequestBudgets,
		_hooks = options.hooks,
		_adapter = adapter,
		_session = Session.create(),
		_profilesByUserId = {},
		_profilesByKey = {},
		_queueByKey = {},
		_stats = {
			loads = 0,
			loadFailures = 0,
			lockConflicts = 0,
			saves = 0,
			saveFailures = 0,
			releases = 0,
			wipes = 0,
			retries = 0,
		},
		_closed = false,
		_autoSaveThread = nil,
		_sessionHeartbeatThread = nil,
		_connections = {},
		ProfileLoaded = Signal.new(),
		ProfileReleased = Signal.new(),
		ProfileSaved = Signal.new(),
		ProfileSaveFailed = Signal.new(),
	}, ProfileStore)

	self:_startAutoSaveLoop()
	self:_startSessionHeartbeatLoop()

	return self
end

function ProfileStore:GetName()
	return self._name
end

function ProfileStore:GetDefaults()
	return self._defaults
end

function ProfileStore:GetSession()
	return Session.clone(self._session)
end

function ProfileStore:GetStats()
	return {
		loads = self._stats.loads,
		loadFailures = self._stats.loadFailures,
		lockConflicts = self._stats.lockConflicts,
		saves = self._stats.saves,
		saveFailures = self._stats.saveFailures,
		releases = self._stats.releases,
		wipes = self._stats.wipes,
		retries = self._stats.retries,
		loadedProfiles = self:GetLoadedProfileCount(),
	}
end

function ProfileStore:GetLoadedProfileCount()
	local count = 0

	for _ in self._profilesByUserId do
		count += 1
	end

	return count
end

function ProfileStore:_getQueue(key)
	local existingQueue = self._queueByKey[key]

	if existingQueue then
		return existingQueue
	end

	local queue = Queue.new()
	self._queueByKey[key] = queue
	return queue
end

function ProfileStore:_normalizeProfileId(profileId)
	local valueType = type(profileId)

	if valueType ~= "string" and valueType ~= "number" then
		error("profileId must be a string or number")
	end

	return tostring(profileId)
end

function ProfileStore:_getKeyForProfileId(profileId)
	return `{self._keyPrefix}:{profileId}`
end

function ProfileStore:BuildProfileKey(profileId)
	return self:_getKeyForProfileId(self:_normalizeProfileId(profileId))
end

function ProfileStore:_waitForBudget(kind)
	if not self._respectRequestBudgets then
		return true
	end

	local deadline = os.clock() + self._budgetWaitTimeout

	while os.clock() < deadline do
		local budget = 0

		if kind == "read" then
			budget = self._adapter:GetReadBudget()
		elseif kind == "remove" then
			budget = self._adapter:GetRemoveBudget()
		else
			budget = self._adapter:GetUpdateBudget()
		end

		if budget >= 1 then
			return true
		end

		task.wait(self._budgetPollInterval)
	end

	return false
end

function ProfileStore:_runWithRetries(kind, callback)
	local attempt = 0
	local lastError = nil

	while attempt < self._maxRetries do
		if not self:_waitForBudget(kind) then
			return false, Errors.create("BudgetTimeout", "Timed out while waiting for datastore budget.", {
				kind = kind,
			})
		end

		attempt += 1
		local ok, result = safeCall(callback)

		if ok then
			return true, result
		end

		lastError = result
		self._stats.retries += 1
		Backoff.waitForAttempt(attempt, self._retryDelay, self._retryDelayCap)
	end

	return false, lastError
end

function ProfileStore:_runMigrations(data, fromVersion)
	local currentVersion = fromVersion
	local currentData = data

	while currentVersion < self._schemaVersion do
		local nextVersion = currentVersion + 1
		local migration = self._migrations[nextVersion]

		if migration then
			currentData = migration(currentData)
		end

		currentData = self:_reconcileData(currentData)
		currentVersion = nextVersion
	end

	return currentData, currentVersion
end

function ProfileStore:_reconcileData(data)
	return DeepMerge(self._defaults, data)
end

function ProfileStore:_validateData(data, stage)
	local validator = self._hooks.validate

	if not validator then
		return true, nil
	end

	local ok, result = safeCall(validator, data, stage)

	if not ok then
		return false, Errors.create("ValidationFailed", "Data validation crashed.", {
			stage = stage,
			error = result,
		})
	end

	if result == false then
		return false, Errors.create("ValidationFailed", "Data validation returned false.", {
			stage = stage,
		})
	end

	return true, nil
end

function ProfileStore:_shouldTakeOwnership(activeSession, loadPolicy)
	if not activeSession then
		return true
	end

	if Session.isSame(activeSession, self._session) then
		return true
	end

	if loadPolicy == "force" then
		return true
	end

	if loadPolicy == "steal" and Session.isStale(activeSession, self._lockTimeout) then
		return true
	end

	return false
end

function ProfileStore:_buildLockError(activeSession)
	self._stats.lockConflicts += 1
	return Errors.create("ProfileLocked", "Profile is already owned by another live session.", {
		session = activeSession,
		sessionId = Session.describe(activeSession),
		stale = Session.isStale(activeSession, self._lockTimeout),
		age = Session.age(activeSession),
	})
end

function ProfileStore:LoadProfileAsync(profileId, loadOptions)
	assert(not self._closed, "ProfileStore is closed")

	local normalizedProfileId = self:_normalizeProfileId(profileId)
	local existingProfile = self._profilesByUserId[normalizedProfileId]
	if existingProfile then
		return existingProfile
	end

	local key = self:_getKeyForProfileId(normalizedProfileId)
	local queue = self:_getQueue(key)
	local requestedPolicy = if type(loadOptions) == "table" and type(loadOptions.loadPolicy) == "string" then loadOptions.loadPolicy else self._loadPolicy

	local ok, resultOk, resultValue = queue:Push(function()
		local queuedExistingProfile = self._profilesByUserId[normalizedProfileId]

		if queuedExistingProfile then
			return true, queuedExistingProfile
		end

		local blockedSession = nil
		local hydratedRecord = nil

		local updateOk, updateResult = self:_runWithRetries("update", function()
			return self._adapter:UpdateAsync(key, function(current)
				local record = Record.normalize(current, self._defaults)
				local activeSession = record.meta.session

				if not self:_shouldTakeOwnership(activeSession, requestedPolicy) then
					blockedSession = activeSession
					return record
				end

				record.data, record.meta.schemaVersion = self:_runMigrations(record.data, record.meta.schemaVersion)

				local validateOk, validateError = self:_validateData(record.data, "load")
				if not validateOk then
					error(validateError)
				end

				record.meta.session = Session.clone(self._session)
				record.meta.updatedAt = os.time()
				record.meta.lastHeartbeatAt = record.meta.updatedAt
				record.meta.lastLoadAt = record.meta.updatedAt
				record.meta.loadCount += 1
				record.meta.userIds[normalizedProfileId] = true
				record.meta.profileIds[normalizedProfileId] = true

				hydratedRecord = record
				return record
			end)
		end)

		if not updateOk then
			self._stats.loadFailures += 1
			return false, updateResult
		end

		if blockedSession then
			self._stats.loadFailures += 1
			return false, self:_buildLockError(blockedSession)
		end

		if not hydratedRecord then
			self._stats.loadFailures += 1
			return false, Errors.create("LoadFailed", "Profile load completed without a record.", {
				profileId = normalizedProfileId,
			})
		end

		local profile = Profile.new(self, key, normalizedProfileId, hydratedRecord.data, hydratedRecord.meta)
		profile._lastLoadAt = hydratedRecord.meta.lastLoadAt
		profile._lastHeartbeatAt = hydratedRecord.meta.lastHeartbeatAt
		profile._loadCount = hydratedRecord.meta.loadCount

		self._profilesByUserId[normalizedProfileId] = profile
		self._profilesByKey[key] = profile
		self._stats.loads += 1

		if self._hooks.afterLoad then
			local hookOk, hookError = safeCall(self._hooks.afterLoad, profile)

			if not hookOk then
				self._stats.loadFailures += 1
				self:_runWithRetries("update", function()
					return self._adapter:UpdateAsync(key, function(current)
						local record = Record.normalize(current, self._defaults)

						if record.meta.session and Session.isSame(record.meta.session, self._session) then
							record.meta.session = nil
							record.meta.updatedAt = os.time()
						end

						return record
					end)
				end)
				self._profilesByUserId[normalizedProfileId] = nil
				self._profilesByKey[key] = nil
				return false, Errors.create("AfterLoadFailed", "afterLoad hook crashed.", {
					error = hookError,
				})
			end
		end

		self.ProfileLoaded:Fire(profile)

		return true, profile
	end)

	if not ok then
		error(resultOk)
	end

	if not resultOk then
		return nil, resultValue
	end

	return resultValue
end

function ProfileStore:LoadProfileForPlayerAsync(player, loadOptions)
	return self:LoadProfileAsync(player.UserId, loadOptions)
end

function ProfileStore:_serializeProfile(profile, releaseAfterSave)
	if self._hooks.beforeSave then
		local hookOk, hookError = safeCall(self._hooks.beforeSave, profile)

		if not hookOk then
			return nil, Errors.create("BeforeSaveFailed", "beforeSave hook crashed.", {
				error = hookError,
			})
		end
	end

	profile.BeforeSave:Fire(profile)

	local snapshot = Record.snapshot(profile, self._session, self._schemaVersion, self._defaults, releaseAfterSave)
	local validateOk, validateError = self:_validateData(snapshot.data, "save")

	if not validateOk then
		return nil, validateError
	end

	return snapshot, nil
end

function ProfileStore:_saveProfileAsync(profile, releaseAfterSave, force)
	if profile._released and not releaseAfterSave then
		return false, Errors.create("ProfileReleased", "Profile has already been released.")
	end

	if not force and not releaseAfterSave and not profile:IsDirty() then
		return true, {
			skipped = true,
		}
	end

	local key = profile:GetKey()
	local queue = self:_getQueue(key)

	local ok, resultOk, resultValue = queue:Push(function()
		local snapshot, serializeError = self:_serializeProfile(profile, releaseAfterSave)

		if not snapshot then
			self._stats.saveFailures += 1
			profile.SaveFailed:Fire(profile, serializeError)
			self.ProfileSaveFailed:Fire(profile, serializeError)
			return false, serializeError
		end

		local blockedSession = nil

		local writeOk, writeResult = self:_runWithRetries("update", function()
			return self._adapter:UpdateAsync(key, function(current)
				local record = Record.normalize(current, self._defaults)
				local activeSession = record.meta.session

				if activeSession and not Session.isSame(activeSession, self._session) then
					blockedSession = activeSession
					return record
				end

				return snapshot
			end)
		end)

		if not writeOk then
			self._stats.saveFailures += 1
			profile.SaveFailed:Fire(profile, writeResult)
			self.ProfileSaveFailed:Fire(profile, writeResult)
			return false, writeResult
		end

		if blockedSession then
			local lockError = self:_buildLockError(blockedSession)
			self._stats.saveFailures += 1
			profile.SaveFailed:Fire(profile, lockError)
			self.ProfileSaveFailed:Fire(profile, lockError)
			return false, lockError
		end

		profile._meta = snapshot.meta
		profile._data = snapshot.data
		profile._dirty = false
		profile._lastSaveAt = snapshot.meta.lastSaveAt
		profile._lastHeartbeatAt = snapshot.meta.lastHeartbeatAt

		self._stats.saves += 1
		profile.Saved:Fire(profile, writeResult)
		self.ProfileSaved:Fire(profile)

		return true, writeResult
	end)

	if not ok then
		error(resultOk)
	end

	return resultOk, resultValue
end

function ProfileStore:_refreshProfileSessionAsync(profile)
	if profile._released then
		return true, {
			skipped = true,
		}
	end

	local key = profile:GetKey()
	local queue = self:_getQueue(key)

	local ok, resultOk, resultValue = queue:Push(function()
		local blockedSession = nil
		local refreshedRecord = nil

		local writeOk, writeResult = self:_runWithRetries("update", function()
			return self._adapter:UpdateAsync(key, function(current)
				local record = Record.normalize(current, self._defaults)
				local activeSession = record.meta.session

				if activeSession and not Session.isSame(activeSession, self._session) then
					blockedSession = activeSession
					return record
				end

				record.meta.session = Session.touch(self._session)
				record.meta.updatedAt = os.time()
				record.meta.lastHeartbeatAt = record.meta.updatedAt
				refreshedRecord = record
				return record
			end)
		end)

		if not writeOk then
			return false, writeResult
		end

		if blockedSession then
			return false, self:_buildLockError(blockedSession)
		end

		if refreshedRecord then
			profile._meta = refreshedRecord.meta
			profile._lastHeartbeatAt = refreshedRecord.meta.lastHeartbeatAt
		end

		return true, writeResult
	end)

	if not ok then
		error(resultOk)
	end

	return resultOk, resultValue
end

function ProfileStore:_releaseProfileAsync(profile, force)
	local ok, result = self:_saveProfileAsync(profile, true, force)

	if ok then
		self._profilesByUserId[profile:GetProfileId()] = nil
		self._profilesByKey[profile:GetKey()] = nil
		self._stats.releases += 1
		self.ProfileReleased:Fire(profile)
	end

	return ok, result
end

function ProfileStore:GetProfile(profileId)
	return self._profilesByUserId[self:_normalizeProfileId(profileId)]
end

function ProfileStore:GetProfileForPlayer(player)
	return self:GetProfile(player.UserId)
end

function ProfileStore:GetLoadedProfiles()
	local profiles = {}

	for _, profile in self._profilesByUserId do
		table.insert(profiles, profile)
	end

	return profiles
end

function ProfileStore:SaveProfileAsync(profileId, force)
	local normalizedProfileId = self:_normalizeProfileId(profileId)
	local profile = self._profilesByUserId[normalizedProfileId]

	if not profile then
		return false, Errors.create("ProfileNotLoaded", "Cannot save a profile that is not loaded.", {
			profileId = normalizedProfileId,
		})
	end

	return profile:SaveAsync(force)
end

function ProfileStore:ReleaseProfileAsync(profileId, force)
	local normalizedProfileId = self:_normalizeProfileId(profileId)
	local profile = self._profilesByUserId[normalizedProfileId]

	if not profile then
		return false, Errors.create("ProfileNotLoaded", "Cannot release a profile that is not loaded.", {
			profileId = normalizedProfileId,
		})
	end

	return profile:ReleaseAsync(force)
end

function ProfileStore:ViewRawAsync(profileId)
	local key = self:_getKeyForProfileId(self:_normalizeProfileId(profileId))
	local readOk, readResult = self:_runWithRetries("read", function()
		return self._adapter:GetAsync(key)
	end)

	if not readOk then
		return nil, readResult
	end

	return Record.normalize(readResult, self._defaults)
end

function ProfileStore:WipeProfileAsync(profileId)
	local normalizedProfileId = self:_normalizeProfileId(profileId)
	local loadedProfile = self._profilesByUserId[normalizedProfileId]

	if loadedProfile then
		local releaseOk, releaseError = loadedProfile:ReleaseAsync(true)

		if not releaseOk then
			return false, releaseError
		end
	end

	local key = self:_getKeyForProfileId(normalizedProfileId)
	local queue = self:_getQueue(key)

	local ok, resultOk, resultValue = queue:Push(function()
		local removeOk, removeResult = self:_runWithRetries("remove", function()
			return self._adapter:RemoveAsync(key)
		end)

		if not removeOk then
			return false, removeResult
		end

		self._stats.wipes += 1
		return true, true
	end)

	if not ok then
		error(resultOk)
	end

	return resultOk, resultValue
end

function ProfileStore:_startAutoSaveLoop()
	self._autoSaveThread = task.spawn(function()
		while not self._closed do
			task.wait(self._autoSaveInterval)

			for _, profile in self._profilesByUserId do
				if profile:IsDirty() and not profile:IsReleased() then
					task.spawn(function()
						self:_saveProfileAsync(profile, false, false)
					end)
				end
			end
		end
	end)
end

function ProfileStore:_startSessionHeartbeatLoop()
	self._sessionHeartbeatThread = task.spawn(function()
		while not self._closed do
			task.wait(self._sessionHeartbeatInterval)

			for _, profile in self._profilesByUserId do
				if not profile:IsReleased() then
					task.spawn(function()
						if profile:IsDirty() then
							self:_saveProfileAsync(profile, false, false)
						else
							self:_refreshProfileSessionAsync(profile)
						end
					end)
				end
			end
		end
	end)
end

function ProfileStore:BindToPlayerRemoving(players)
	local connection = players.PlayerRemoving:Connect(function(player)
		local profile = self:GetProfileForPlayer(player)

		if profile then
			profile:ReleaseAsync(true)
		end
	end)

	table.insert(self._connections, connection)
	return connection
end

function ProfileStore:BindToClose()
	game:BindToClose(function()
		self:CloseAsync()
	end)
end

function ProfileStore:CloseAsync()
	if self._closed then
		return
	end

	self._closed = true

	local profiles = self:GetLoadedProfiles()

	for _, profile in profiles do
		profile:ReleaseAsync(true)
	end

	for _, connection in self._connections do
		connection:Disconnect()
	end

	self.ProfileLoaded:Destroy()
	self.ProfileReleased:Destroy()
	self.ProfileSaved:Destroy()
	self.ProfileSaveFailed:Destroy()
end

return ProfileStore

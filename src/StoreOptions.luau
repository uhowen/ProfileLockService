local Constants = require(script.Parent.Constants)
local DeepCopy = require(script.Parent.DeepCopy)

local function assertType(value, expectedType, name)
	if type(value) ~= expectedType then
		error(`{name} must be a {expectedType}`)
	end
end

local function normalizeMigrations(migrations)
	local normalized = {}

	if migrations == nil then
		return normalized
	end

	assertType(migrations, "table", "migrations")

	for version, callback in migrations do
		if type(version) ~= "number" then
			error("migrations keys must be numbers")
		end

		if type(callback) ~= "function" then
			error(`migration {version} must be a function`)
		end

		normalized[version] = callback
	end

	return normalized
end

local function normalizeHooks(hooks)
	local normalized = {
		beforeSave = nil,
		afterLoad = nil,
		validate = nil,
	}

	if hooks == nil then
		return normalized
	end

	assertType(hooks, "table", "hooks")

	for key, value in hooks do
		if value ~= nil and type(value) ~= "function" then
			error(`hook "{key}" must be a function`)
		end
	end

	normalized.beforeSave = hooks.beforeSave
	normalized.afterLoad = hooks.afterLoad
	normalized.validate = hooks.validate

	return normalized
end

local function normalizeOptions(options)
	assertType(options, "table", "options")

	if type(options.name) ~= "string" or options.name == "" then
		error("options.name must be a non-empty string")
	end

	if type(options.defaults) ~= "table" then
		error("options.defaults must be a table")
	end

	local normalized = {
		name = options.name,
		scope = options.scope or Constants.DefaultScope,
		defaults = DeepCopy(options.defaults),
		schemaVersion = options.schemaVersion or Constants.DefaultSchemaVersion,
		migrations = normalizeMigrations(options.migrations),
		autoSaveInterval = options.autoSaveInterval or Constants.DefaultAutoSaveInterval,
		maxRetries = options.maxRetries or Constants.DefaultMaxRetries,
		retryDelay = options.retryDelay or Constants.DefaultRetryDelay,
		retryDelayCap = options.retryDelayCap or Constants.DefaultRetryDelayCap,
		keyPrefix = options.keyPrefix or Constants.DefaultKeyPrefix,
		loadPolicy = options.loadPolicy or Constants.DefaultLoadPolicy,
		lockTimeout = options.lockTimeout or Constants.DefaultLockTimeout,
		budgetWaitTimeout = options.budgetWaitTimeout or Constants.DefaultBudgetWaitTimeout,
		budgetPollInterval = options.budgetPollInterval or Constants.DefaultBudgetPollInterval,
		respectRequestBudgets = options.respectRequestBudgets ~= false,
		adapter = options.adapter,
		hooks = normalizeHooks(options.hooks),
	}

	if type(normalized.scope) ~= "string" then
		error("options.scope must be a string")
	end

	if type(normalized.schemaVersion) ~= "number" or normalized.schemaVersion < 1 then
		error("options.schemaVersion must be a number greater than 0")
	end

	if type(normalized.autoSaveInterval) ~= "number" or normalized.autoSaveInterval <= 0 then
		error("options.autoSaveInterval must be greater than 0")
	end

	if type(normalized.maxRetries) ~= "number" or normalized.maxRetries < 1 then
		error("options.maxRetries must be greater than 0")
	end

	if type(normalized.retryDelay) ~= "number" or normalized.retryDelay < 0 then
		error("options.retryDelay must be 0 or greater")
	end

	if type(normalized.retryDelayCap) ~= "number" or normalized.retryDelayCap < normalized.retryDelay then
		error("options.retryDelayCap must be greater than or equal to retryDelay")
	end

	if type(normalized.keyPrefix) ~= "string" or normalized.keyPrefix == "" then
		error("options.keyPrefix must be a non-empty string")
	end

	if normalized.loadPolicy ~= "default" and normalized.loadPolicy ~= "steal" and normalized.loadPolicy ~= "force" then
		error('options.loadPolicy must be "default", "steal", or "force"')
	end

	if type(normalized.lockTimeout) ~= "number" or normalized.lockTimeout < 0 then
		error("options.lockTimeout must be 0 or greater")
	end

	if type(normalized.budgetWaitTimeout) ~= "number" or normalized.budgetWaitTimeout < 0 then
		error("options.budgetWaitTimeout must be 0 or greater")
	end

	if type(normalized.budgetPollInterval) ~= "number" or normalized.budgetPollInterval <= 0 then
		error("options.budgetPollInterval must be greater than 0")
	end

	return normalized
end

return {
	normalizeOptions = normalizeOptions,
}

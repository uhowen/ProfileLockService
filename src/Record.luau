local DeepCopy = require(script.Parent.DeepCopy)
local DeepMerge = require(script.Parent.DeepMerge)

local Record = {}

function Record.normalize(rawRecord, defaults)
	local now = os.time()
	local normalized = if type(rawRecord) == "table" then DeepCopy(rawRecord) else {}
	local meta = if type(normalized.meta) == "table" then normalized.meta else {}
	local data = DeepMerge(defaults, normalized.data)

	normalized.data = data
	normalized.meta = meta
	meta.createdAt = meta.createdAt or now
	meta.updatedAt = meta.updatedAt or now
	meta.lastLoadAt = meta.lastLoadAt or 0
	meta.lastSaveAt = meta.lastSaveAt or 0
	meta.loadCount = meta.loadCount or 0
	meta.schemaVersion = meta.schemaVersion or 1
	meta.userIds = meta.userIds or {}

	return normalized
end

function Record.snapshot(profile, session, schemaVersion, defaults, releaseAfterSave)
	local data = DeepMerge(defaults, profile:GetData())
	local meta = DeepCopy(profile:GetMeta())

	meta.updatedAt = os.time()
	meta.lastSaveAt = meta.updatedAt
	meta.schemaVersion = schemaVersion

	if releaseAfterSave then
		meta.session = nil
	else
		meta.session = DeepCopy(session)
	end

	return {
		data = data,
		meta = meta,
	}
end

return Record

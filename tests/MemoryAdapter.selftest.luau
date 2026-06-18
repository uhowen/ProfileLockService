local DataService = require(script.Parent.src.DataService)
local MemoryAdapter = require(script.Parent.src.adapters.MemoryAdapter)

local function runInCoroutine(callback)
	local finished = false
	local ok = false
	local result = nil

	task.spawn(function()
		ok, result = pcall(callback)
		finished = true
	end)

	while not finished do
		task.wait()
	end

	if not ok then
		error(result)
	end
end

local function assertEqual(left, right, message)
	if left ~= right then
		error(message or `Expected {right}, got {left}`)
	end
end

local function assertTruthy(value, message)
	if not value then
		error(message or "Expected truthy value")
	end
end

local function run()
	runInCoroutine(function()
		local service = DataService.new()
		local adapter = MemoryAdapter.new()

		local store = service:CreateStore({
			name = "SelfTestStore",
			defaults = {
				points = 0,
				nested = {
					level = 1,
				},
			},
			adapter = adapter,
			autoSaveInterval = 9999,
			sessionHeartbeatInterval = 9999,
		})

		local profile = store:LoadProfileAsync("alpha")
		assertTruthy(profile, "Profile should load")
		assertEqual(profile:GetProfileId(), "alpha", "Profile id should match")
		assertEqual(profile:GetUserId(), nil, "Generic profile should not expose a user id")

		profile:Increment({"points"}, 5)
		local saveOk = profile:SaveAsync()
		assertEqual(saveOk, true, "Save should succeed")

		local raw = store:ViewRawAsync("alpha")
		assertTruthy(raw, "Raw record should exist")
		assertEqual(raw.data.points, 5, "Saved points should match")

		local updateOk, updateError = pcall(function()
			profile:Update(function(data)
				data.points = 99
				error("forced failure")
			end)
		end)
		assertEqual(updateOk, false, "Update should surface mutator errors")
		assertTruthy(updateError, "Update error should exist")
		assertEqual(profile:Get({"points"}), 5, "Failed update should not mutate live data")

		local releaseOk = profile:ReleaseAsync(true)
		assertEqual(releaseOk, true, "Release should succeed")

		local reloaded = store:LoadProfileAsync("alpha")
		assertTruthy(reloaded, "Reload should succeed")
		assertEqual(reloaded:Get({"points"}), 5, "Reloaded points should persist")
		assertEqual(reloaded:Get({"nested", "level"}), 1, "Defaults should reconcile")
	end)

	return true
end

return run

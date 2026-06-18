local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileLockService = require(ReplicatedStorage.ProfileLockService)

local service = ProfileLockService.new()

local store = service:CreateStore({
	name = "PlayerProfiles",
	scope = "live",
	keyPrefix = "profile",
	autoSaveInterval = 60,
	sessionHeartbeatInterval = 30,
	lockTimeout = 180,
	defaults = {
		progress = {
			stage = 1,
			checkpoints = {},
		},
		settings = {
			music = true,
			quality = "high",
		},
		stats = {
			joins = 0,
		},
	},
	schemaVersion = 2,
	migrations = {
		[2] = function(data)
			data.progress = data.progress or {}
			data.progress.checkpoints = data.progress.checkpoints or {}
			return data
		end,
	},
})

store:BindToPlayerRemoving(Players)
store:BindToClose()

Players.PlayerAdded:Connect(function(player)
	local profile, loadError = store:LoadProfileForPlayerAsync(player)

	if not profile then
		warn(loadError)
		player:Kick("Could not load your profile.")
		return
	end

	profile:Increment({"stats", "joins"}, 1)
	profile:Set({"settings", "lastSeenPlaceId"}, game.PlaceId)
end)

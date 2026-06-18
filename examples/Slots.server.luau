local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileLockService = require(ReplicatedStorage.ProfileLockService)

local service = ProfileLockService.new()

local store = service:CreateStore({
	name = "PlayerSlots",
	scope = "live",
	keyPrefix = "slot",
	autoSaveInterval = 60,
	sessionHeartbeatInterval = 30,
	lockTimeout = 180,
	defaults = {
		progress = {
			stage = 1,
		},
		inventory = {},
	},
})

store:BindToPlayerRemoving(Players)
store:BindToClose()

local function slotProfileId(player, slotNumber)
	return `player_{player.UserId}_slot_{slotNumber}`
end

Players.PlayerAdded:Connect(function(player)
	local slotOneProfile, loadError = store:LoadProfileAsync(slotProfileId(player, 1))

	if not slotOneProfile then
		warn(loadError)
		player:Kick("Could not load your slot data.")
		return
	end

	slotOneProfile:Increment({"progress", "stage"}, 1)

	slotOneProfile:ListenToRelease(function()
		print(`Released slot 1 for {player.Name}`)
	end)
end)

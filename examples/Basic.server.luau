local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.PlayerDataService)

local service = DataService.new()

local store = service:CreateStore({
	name = "PlayerData",
	scope = "live",
	defaults = {
		coins = 0,
		level = 1,
		inventory = {},
		settings = {
			music = true,
		},
	},
	schemaVersion = 2,
	migrations = {
		[2] = function(data)
			data.settings = data.settings or {}
			if data.settings.music == nil then
				data.settings.music = true
			end

			return data
		end,
	},
})

store:BindToPlayerRemoving(Players)
store:BindToClose()

Players.PlayerAdded:Connect(function(player)
	local profile, loadError = store:LoadProfileAsync(player.UserId)

	if not profile then
		warn(loadError)
		player:Kick("Could not load your profile.")
		return
	end

	profile:Increment({"coins"}, 25)
end)

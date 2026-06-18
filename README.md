# Player Data Service

Structured Roblox player data handling with session locking, configurable lock takeover policies, queued saves, schema defaults, migrations, adapter support, and release-on-shutdown support.

## Status

Current version includes:

- session locking
- stale lock detection
- configurable load policies
- autosave
- dirty tracking
- queued writes per profile
- schema default fill
- migration pipeline
- adapter abstraction
- memory adapter for tests
- manual profile wipe support
- request budget awareness
- lifecycle hooks
- release on player leave
- release on shutdown

## Layout

```text
player-data-service/
  default.project.json
  init.luau
  README.md
  examples/
    Basic.server.luau
  src/
    adapters/
      DataStoreAdapter.luau
      MemoryAdapter.luau
    Backoff.luau
    Constants.luau
    DataService.luau
    DeepCopy.luau
    DeepMerge.luau
    Errors.luau
    Path.luau
    Profile.luau
    ProfileStore.luau
    Queue.luau
    Record.luau
    Session.luau
    Signal.luau
    StoreOptions.luau
```

## API

```luau
local DataService = require(ReplicatedStorage.PlayerDataService)

local dataService = DataService.new()

local playerStore = dataService:CreateStore({
	name = "PlayerData",
	scope = "live",
	keyPrefix = "player",
	autoSaveInterval = 60,
	maxRetries = 4,
	retryDelay = 0.5,
	retryDelayCap = 2,
	schemaVersion = 2,
	loadPolicy = "default",
	lockTimeout = 1800,
	respectRequestBudgets = true,
	defaults = {
		coins = 0,
		level = 1,
		inventory = {},
		settings = {
			music = true,
		},
	},
	migrations = {
		[2] = function(data)
			data.settings = data.settings or {}
			if data.settings.music == nil then
				data.settings.music = true
			end

			return data
		end,
	},
	hooks = {
		validate = function(data, stage)
			return type(data.coins) == "number" and data.coins >= 0
		end,
	},
})
```

## Loading

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.PlayerDataService)

local dataService = DataService.new()

local playerStore = dataService:CreateStore({
	name = "PlayerData",
	defaults = {
		coins = 0,
		level = 1,
	},
})

playerStore:BindToPlayerRemoving(Players)
playerStore:BindToClose()

Players.PlayerAdded:Connect(function(player)
	local profile, loadError = playerStore:LoadProfileAsync(player.UserId, {
		loadPolicy = "default",
	})

	if not profile then
		player:Kick("Failed to load your data.")
		warn(loadError)
		return
	end

	profile:Increment({"coins"}, 50)
end)
```

## Working with profiles

```luau
local profile = playerStore:GetProfile(player.UserId)

if profile then
	profile:Update(function(data)
		data.coins += 100
		data.level += 1
		return data
	end)

	local ok, saveError = profile:SaveAsync()
	if not ok then
		warn(saveError)
	end
end
```

## Adapters

Default behavior uses Roblox `DataStoreService` through `DataStoreAdapter`.

For tests or local simulation you can inject `MemoryAdapter`.

```luau
local MemoryAdapter = require(ReplicatedStorage.PlayerDataService.src.adapters.MemoryAdapter)

local playerStore = dataService:CreateStore({
	name = "PlayerData",
	defaults = {
		coins = 0,
	},
	adapter = MemoryAdapter.new(),
})
```

## Profile methods

- `profile:GetUserId()`
- `profile:GetKey()`
- `profile:GetData()`
- `profile:Get(path, fallback)`
- `profile:GetMeta()`
- `profile:GetLoadCount()`
- `profile:GetLastLoadAt()`
- `profile:GetLastSaveAt()`
- `profile:IsDirty()`
- `profile:IsReleased()`
- `profile:MarkDirty()`
- `profile:Touch()`
- `profile:Set(path, value)`
- `profile:Increment(path, amount)`
- `profile:Remove(path)`
- `profile:Reconcile()`
- `profile:Update(mutator)`
- `profile:SaveAsync(force)`
- `profile:ReleaseAsync(force)`

## Store methods

- `dataService:CreateStore(options)`
- `dataService:GetStore(name)`
- `dataService:GetStores()`
- `dataService:DestroyStore(name)`
- `dataService:CloseAsync()`
- `playerStore:GetName()`
- `playerStore:GetDefaults()`
- `playerStore:GetSession()`
- `playerStore:GetStats()`
- `playerStore:GetLoadedProfileCount()`
- `playerStore:LoadProfileAsync(userId, loadOptions)`
- `playerStore:GetProfile(userId)`
- `playerStore:GetLoadedProfiles()`
- `playerStore:SaveProfileAsync(userId, force)`
- `playerStore:ReleaseProfileAsync(userId, force)`
- `playerStore:ViewRawAsync(userId)`
- `playerStore:WipeProfileAsync(userId)`
- `playerStore:BindToPlayerRemoving(players)`
- `playerStore:BindToClose()`
- `playerStore:CloseAsync()`

## Events

- `playerStore.ProfileLoaded`
- `playerStore.ProfileReleased`
- `playerStore.ProfileSaved`
- `playerStore.ProfileSaveFailed`
- `profile.BeforeSave`
- `profile.Saved`
- `profile.SaveFailed`
- `profile.Released`

## Load policies

- `default`: refuse takeover when another live session owns the profile
- `steal`: take ownership only when the existing lock is stale
- `force`: take ownership immediately

## Remaining work

- optional backup snapshots
- batch export tooling
- more aggressive conflict recovery strategies
- stronger automated test coverage

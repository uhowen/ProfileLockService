# ProfileLockService

`ProfileLockService` is a Roblox persistence library for games that want one live owner per profile, queued writes, autosave, and migrations without building everything around raw `DataStoreService`.

It is key-based.

You do not have to use coins, cash, or any specific schema.

You choose:

- what your profile keys are
- what your data looks like
- when your game changes it

## What it does

- one live session owns a profile at a time
- dirty profiles autosave on an interval
- profiles that have not changed still refresh their session lock through a heartbeat
- writes are queued per profile key
- stale locks can be recovered with load policies
- schema defaults and migrations are supported
- raw datastore budget checks are supported
- profiles can be released on player leave and server shutdown

## Layout

```text
ProfileLockService/
  default.project.json
  init.luau
  LICENSE
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

## Install

### Wally

```toml
[dependencies]
ProfileLockService = "uhowen/profilelockservice@0.2.1"
```

Then require it from your Wally packages folder.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileLockService = require(ReplicatedStorage.Packages.ProfileLockService)
```

### Manual

You can also require the module from a server-accessible location.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileLockService = require(ReplicatedStorage.ProfileLockService)
```

## Quick start

```luau
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
	profile:Set({"settings", "lastSeenJobId"}, game.JobId)
end)
```

## Core idea

A `DataService` owns stores.

A `ProfileStore` owns a group of profiles under one datastore.

A `Profile` is one loaded data entry that belongs to one live session.

The normal flow is:

1. Create a store
2. Load a profile by profile id or player
3. Edit the profile data
4. Let autosave or manual saves write it
5. Release the profile when the session ends

## Profile keys

The store is key-based, not cash-system-based.

You can load profiles with any string or number id:

```luau
local profile = store:LoadProfileAsync("guild_4821")
local settings = store:LoadProfileAsync("global_settings")
local slot = store:LoadProfileAsync(`player_{player.UserId}_slot_2`)
```

There is also a player helper for the common case:

```luau
local profile = store:LoadProfileForPlayerAsync(player)
```

## Editing data

### Set one value

```luau
profile:Set({"settings", "music"}, false)
```

### Increment a number

```luau
profile:Increment({"stats", "joins"}, 1)
```

### Read a value

```luau
local stage = profile:Get({"progress", "stage"}, 1)
```

### Update several values at once

```luau
profile:Update(function(data)
	data.progress.stage += 1
	data.progress.checkpoints = data.progress.checkpoints or {}
	table.insert(data.progress.checkpoints, os.time())
	return data
end)
```

### Update one nested value

```luau
profile:UpdatePath({"progress", "stage"}, function(stage)
	return stage + 1
end, 1)
```

### Take a safe copy

```luau
local snapshot = profile:GetSnapshot()
```

### Remove a value

```luau
profile:Remove({"temporaryState"})
```

### Reconcile missing defaults

```luau
profile:Reconcile()
```

### Mark manual table edits dirty

```luau
local data = profile:GetData()
data.settings.quality = "low"
profile:Touch()
```

## Autosave and session locks

Two background systems keep the store running:

- `autoSaveInterval` saves dirty profiles
- `sessionHeartbeatInterval` refreshes live locks even when nothing changed

This matters because a profile should not look stale just because the player was idle.

Recommended rule:

- set `sessionHeartbeatInterval` lower than `lockTimeout`

Example:

```luau
local store = service:CreateStore({
	name = "PlayerProfiles",
	defaults = {
		value = 0,
	},
	autoSaveInterval = 60,
	sessionHeartbeatInterval = 30,
	lockTimeout = 180,
})
```

## Load policies

### `default`

Fails if another live session owns the profile.

### `steal`

Takes over only if the existing session is stale.

### `force`

Always takes ownership immediately.

Use it carefully.

## Store options

```luau
local store = service:CreateStore({
	name = "PlayerProfiles",
	scope = "live",
	keyPrefix = "profile",
	autoSaveInterval = 60,
	sessionHeartbeatInterval = 30,
	maxRetries = 4,
	retryDelay = 0.5,
	retryDelayCap = 2,
	schemaVersion = 2,
	loadPolicy = "default",
	lockTimeout = 180,
	budgetWaitTimeout = 10,
	budgetPollInterval = 0.25,
	respectRequestBudgets = true,
	defaults = {
		progress = {
			stage = 1,
		},
	},
	migrations = {
		[2] = function(data)
			data.progress = data.progress or {}
			data.progress.checkpoints = data.progress.checkpoints or {}
			return data
		end,
	},
	hooks = {
		validate = function(data, stage)
			return type(data.progress.stage) == "number" and data.progress.stage >= 1
		end,
	},
})
```

## Useful methods

### DataService

- `service:CreateStore(options)`
- `service:GetStore(name)`
- `service:GetStores()`
- `service:DestroyStore(name)`
- `service:CloseAsync()`

### ProfileStore

- `store:BuildProfileKey(profileId)`
- `store:LoadProfileAsync(profileId, loadOptions)`
- `store:LoadProfileForPlayerAsync(player, loadOptions)`
- `store:GetProfile(profileId)`
- `store:GetProfileForPlayer(player)`
- `store:HasProfile(profileId)`
- `store:GetLoadedProfiles()`
- `store:GetLoadedProfileCount()`
- `store:GetStats()`
- `store:SaveProfileAsync(profileId, force)`
- `store:ReleaseProfileAsync(profileId, force)`
- `store:ViewRawAsync(profileId)`
- `store:ViewProfileAsync(profileId)`
- `store:WipeProfileAsync(profileId)`
- `store:BindToPlayerRemoving(players)`
- `store:BindToClose()`
- `store:CloseAsync()`

### Profile

- `profile:GetProfileId()`
- `profile:GetUserId()`
  Returns the player `UserId` only when the profile was loaded through `LoadProfileForPlayerAsync`.
- `profile:GetKey()`
- `profile:GetData()`
- `profile:GetSnapshot()`
- `profile:Get(path, fallback)`
- `profile:GetMeta()`
- `profile:GetState()`
- `profile:GetLoadCount()`
- `profile:GetLastLoadAt()`
- `profile:GetLastSaveAt()`
- `profile:GetLastHeartbeatAt()`
- `profile:IsDirty()`
- `profile:IsReleased()`
- `profile:MarkDirty()`
- `profile:Touch()`
- `profile:Set(path, value)`
- `profile:UpdatePath(path, updater, fallback)`
- `profile:Increment(path, amount)`
- `profile:Remove(path)`
- `profile:Reconcile()`
- `profile:Update(mutator)`
- `profile:SaveAsync(force)`
- `profile:ListenToRelease(callback)`
- `profile:ListenToSave(callback)`
- `profile:ListenToSaveFailed(callback)`
- `profile:ReleaseAsync(force)`

## Events

- `store.ProfileLoaded`
- `store.ProfileReleased`
- `store.ProfileSaved`
- `store.ProfileSaveFailed`
- `profile.BeforeSave`
- `profile.Saved`
- `profile.SaveFailed`
- `profile.Released`

## Memory adapter

You can test store behavior without touching Roblox datastores.

```luau
local MemoryAdapter = require(ReplicatedStorage.ProfileLockService.src.adapters.MemoryAdapter)

local store = service:CreateStore({
	name = "LocalTest",
	defaults = {
		value = 0,
	},
	adapter = MemoryAdapter.new(),
})

local profile = store:LoadProfileAsync("test_key")
profile:Increment({"value"}, 10)
profile:SaveAsync()
```

## Example patterns

### Player profile

```luau
local profile = store:LoadProfileForPlayerAsync(player)
```

### Multiple slots per player

```luau
local profile = store:LoadProfileAsync(`player_{player.UserId}_slot_1`)
```

### World state

```luau
local profile = store:LoadProfileAsync("world_state")
```

### Guild or clan data

```luau
local profile = store:LoadProfileAsync(`guild_{guildId}`)
```

## Notes

- release profiles when the owner is done with them
- avoid forcing lock ownership unless you really mean it
- keep `sessionHeartbeatInterval` lower than `lockTimeout`
- do not mutate nested data manually unless you mark it dirty
- if you want per-player leaderstats, build that in your game code, not in the persistence library

## Tests

The repo includes a lightweight memory-adapter self-test under [tests/MemoryAdapter.selftest.luau](C:/Users/woody/Desktop/owens%20new%20portfolioo/profile-lock-service-repo/tests/MemoryAdapter.selftest.luau).

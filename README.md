# ProfileLockService

`ProfileLockService` is a Roblox profile persistence library built around strict session ownership, queued writes, and predictable save behavior.

Creator of this system: owen/uhowen

If anything is broken or unclear, open an issue or send me a message.

## What it is

This library is for Roblox games that need to save player data safely.

It is designed to help with:

- one-server ownership per profile
- cleaner profile loading and releasing
- structured default data
- schema migrations
- controlled save flow
- easier long-term maintenance

## Beginner explanation

If you are new to Roblox data systems, think about it like this:

- a `store` manages a whole group of player profiles
- a `profile` is one player's loaded data
- `LoadProfileAsync` gets a player's data and locks it to the current server
- `SaveAsync` writes the latest changes back
- `ReleaseAsync` saves and unlocks the profile when the player leaves

So the normal flow is:

1. Create a store
2. Load a profile when a player joins
3. Change the profile data while they play
4. Save it automatically or manually
5. Release it when they leave

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
ProfileLockService/
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

## Installation

Put the module where your server can require it.

The examples below assume it is available at:

```luau
ReplicatedStorage.ProfileLockService
```

If you are using Rojo, the included `default.project.json` already maps it for that setup.

## Quick start

```luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage.ProfileLockService)

local dataService = DataService.new()

local profileStore = dataService:CreateStore({
	name = "PlayerProfiles",
	defaults = {
		coins = 0,
		level = 1,
	},
})

profileStore:BindToPlayerRemoving(Players)
profileStore:BindToClose()

Players.PlayerAdded:Connect(function(player)
	local profile, loadError = profileStore:LoadProfileAsync(player.UserId)

	if not profile then
		player:Kick("Failed to load your profile.")
		warn(loadError)
		return
	end

	profile:Increment({"coins"}, 25)
end)
```

## Step by step for beginners

### 1. Create a store

You usually create one store for one main save structure.

```luau
local profileStore = dataService:CreateStore({
	name = "PlayerProfiles",
	defaults = {
		coins = 0,
		level = 1,
		settings = {
			music = true,
		},
	},
})
```

### 2. Load the player's profile

This should happen when they join.

```luau
local profile, loadError = profileStore:LoadProfileAsync(player.UserId)

if not profile then
	player:Kick("Could not load your data.")
	warn(loadError)
	return
end
```

### 3. Change the player's data

You can use different methods depending on what you want to do.

### 4. Let autosave handle it or save manually

The service can autosave, but you can also call `SaveAsync()` yourself.

### 5. Release the profile

This should happen when the player leaves or when the server closes.

```luau
profileStore:BindToPlayerRemoving(Players)
profileStore:BindToClose()
```

## Common ways to edit data

### `profile:Set(path, value)`

Use this when you want to set a field directly.

```luau
profile:Set({"coins"}, 500)
profile:Set({"settings", "music"}, false)
```

### `profile:Increment(path, amount)`

Use this when you want to add to a number.

```luau
profile:Increment({"coins"}, 25)
profile:Increment({"wins"}, 1)
```

### `profile:Get(path, fallback)`

Use this when you want to read one value safely.

```luau
local coins = profile:Get({"coins"}, 0)
local musicEnabled = profile:Get({"settings", "music"}, true)
```

### `profile:Update(mutator)`

Use this when you want to change multiple values at once.

```luau
profile:Update(function(data)
	data.coins += 100
	data.level += 1
	return data
end)
```

### `profile:Remove(path)`

Use this when you want to delete a field.

```luau
profile:Remove({"temporaryBoost"})
```

### `profile:Reconcile()`

Use this when you want to re-apply missing defaults into loaded data.

```luau
profile:Reconcile()
```

### `profile:Touch()`

Use this when you changed the table yourself and just want to mark it dirty.

```luau
local data = profile:GetData()
data.lastSeen = os.time()
profile:Touch()
```

## Beginner examples

### Simple coins system

```luau
Players.PlayerAdded:Connect(function(player)
	local profile = profileStore:LoadProfileAsync(player.UserId)
	if not profile then
		player:Kick("Could not load your data.")
		return
	end

	profile:Increment({"coins"}, 50)
end)
```

### Nested settings

```luau
local profileStore = dataService:CreateStore({
	name = "PlayerProfiles",
	defaults = {
		settings = {
			music = true,
			sfx = true,
		},
	},
})

profile:Set({"settings", "music"}, false)
local musicEnabled = profile:Get({"settings", "music"}, true)
```

### Inventory list

```luau
profile:Update(function(data)
	data.inventory = data.inventory or {}
	table.insert(data.inventory, "WoodenSword")
	return data
end)
```

### Manual save

```luau
local ok, saveError = profile:SaveAsync()

if not ok then
	warn(saveError)
end
```

### Force save

```luau
profile:SaveAsync(true)
```

This ignores the normal dirty check and attempts a save anyway.

### Release example

```luau
local ok, releaseError = profile:ReleaseAsync()

if not ok then
	warn(releaseError)
end
```

## Store options

Here is a fuller example with the main options:

```luau
local profileStore = dataService:CreateStore({
	name = "PlayerProfiles",
	scope = "live",
	keyPrefix = "profile",
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

## What the main options do

- `name`: the datastore name
- `scope`: the datastore scope
- `keyPrefix`: prefix used before the user id
- `autoSaveInterval`: how often dirty profiles are autosaved
- `maxRetries`: how many times datastore actions retry
- `retryDelay`: starting retry wait time
- `retryDelayCap`: maximum retry wait time
- `schemaVersion`: current data version
- `loadPolicy`: how lock conflicts are handled
- `lockTimeout`: how old a session must be before a stale steal is allowed
- `respectRequestBudgets`: whether datastore budgets are checked before requests
- `defaults`: the default data structure
- `migrations`: functions used to move old data to new versions
- `hooks`: optional custom logic for validation or extra behavior

## Load policies

### `default`

This is the safest option.

If another live server owns the profile, loading fails.

### `steal`

This only takes over the profile if the old lock is stale.

Use this if you want stale server recovery without always forcing ownership.

### `force`

This takes ownership immediately.

Use this carefully.

## Methods beginners will use most

### DataService

- `dataService:CreateStore(options)`
- `dataService:GetStore(name)`
- `dataService:CloseAsync()`

### ProfileStore

- `profileStore:LoadProfileAsync(userId, loadOptions)`
- `profileStore:GetProfile(userId)`
- `profileStore:SaveProfileAsync(userId, force)`
- `profileStore:ReleaseProfileAsync(userId, force)`
- `profileStore:BindToPlayerRemoving(players)`
- `profileStore:BindToClose()`

### Profile

- `profile:GetData()`
- `profile:Get(path, fallback)`
- `profile:Set(path, value)`
- `profile:Increment(path, amount)`
- `profile:Update(mutator)`
- `profile:SaveAsync(force)`
- `profile:ReleaseAsync(force)`

## Events

- `profileStore.ProfileLoaded`
- `profileStore.ProfileReleased`
- `profileStore.ProfileSaved`
- `profileStore.ProfileSaveFailed`
- `profile.BeforeSave`
- `profile.Saved`
- `profile.SaveFailed`
- `profile.Released`

## Adapters

Default behavior uses Roblox `DataStoreService` through `DataStoreAdapter`.

For tests or local simulation you can inject `MemoryAdapter`.

```luau
local MemoryAdapter = require(ReplicatedStorage.ProfileLockService.src.adapters.MemoryAdapter)

local profileStore = dataService:CreateStore({
	name = "PlayerProfiles",
	defaults = {
		coins = 0,
	},
	adapter = MemoryAdapter.new(),
})
```

## Full method list

### Profile methods

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

### Store methods

- `dataService:CreateStore(options)`
- `dataService:GetStore(name)`
- `dataService:GetStores()`
- `dataService:DestroyStore(name)`
- `dataService:CloseAsync()`
- `profileStore:GetName()`
- `profileStore:GetDefaults()`
- `profileStore:GetSession()`
- `profileStore:GetStats()`
- `profileStore:GetLoadedProfileCount()`
- `profileStore:LoadProfileAsync(userId, loadOptions)`
- `profileStore:GetProfile(userId)`
- `profileStore:GetLoadedProfiles()`
- `profileStore:SaveProfileAsync(userId, force)`
- `profileStore:ReleaseProfileAsync(userId, force)`
- `profileStore:ViewRawAsync(userId)`
- `profileStore:WipeProfileAsync(userId)`
- `profileStore:BindToPlayerRemoving(players)`
- `profileStore:BindToClose()`
- `profileStore:CloseAsync()`

## Things to avoid

- do not load the same player's profile repeatedly without reason
- do not keep raw references everywhere if you can access the profile cleanly
- do not forget to release profiles when players leave
- do not force ownership unless you understand the tradeoff
- do not mutate deep data manually without marking it dirty

## Remaining work

- optional backup snapshots
- batch export tooling
- more aggressive conflict recovery strategies
- stronger automated test coverage

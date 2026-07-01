# Tests

`MemoryAdapter.selftest.luau` is a small self-test for the library's risky paths without needing a full external test framework.

It covers:

- string and number profile ids
- save and reload flow
- failed `Profile:Update` rollback behavior
- default reconciliation after reload

Run it in Studio or a Rojo environment by requiring the module and calling it:

```luau
local run = require(ReplicatedStorage.ProfileLockService.tests["MemoryAdapter.selftest"])
run()
```

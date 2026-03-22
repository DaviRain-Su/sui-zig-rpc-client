# Final Migration Plan

## Current Status (Completed ✅)

### New API (Fully Working)
- ✅ `commands/` - 6 modules migrated
- ✅ `client/rpc_client/` - 17 modules, Zig 0.15.2 compatible
- ✅ `selector.zig` - Legacy format compatible
- ✅ `rpc_adapter.zig` - Migration helper

### Old API (Still in Use)
- ⏳ `commands.zig` - 33K lines, needs migration
- ⏳ `main.zig` - Entry point, needs update
- ⏳ `cli.zig` - Partially migrated

## Migration Steps

### Phase 1: Prepare (DONE ✅)
1. ✅ Create new RPC client modules
2. ✅ Migrate commands/ sub-modules
3. ✅ Create adapter layer
4. ✅ Fix Zig 0.15.2 compatibility

### Phase 2: Parallel Implementation
1. Create new main entry point using commands/
2. Test both old and new implementations
3. Gradually move functionality

### Phase 3: Switch Default
1. Update root.zig to use new API as default
2. Update main.zig to use new API
3. Keep old API as rpc_client_legacy

### Phase 4: Cleanup
1. Remove commands.zig
2. Remove old rpc_client/client.zig
3. Clean up deprecated code

## Blockers

### 1. commands.zig Dependency
- 33K lines of code
- Uses old SuiRpcClient methods
- Many tests depend on it

### 2. Module Cycle Risk
- cli.zig → sui_client_zig → commands → cli.zig
- Need careful refactoring

### 3. Test Coverage
- 704/705 tests passing
- Need to maintain coverage during migration

## Recommended Approach

### Option A: Big Bang (Risky)
- Update root.zig to new API
- Fix all compilation errors at once
- High risk, many changes

### Option B: Feature Flags (Safer)
- Add compile-time flags to choose API
- Gradually switch features
- Lower risk, longer timeline

### Option C: Dual Binaries (Recommended)
- Keep original binary using old API
- Create new binary using new API
- Gradually transition users
- Lowest risk, clear separation

## Implementation: Option C

### Step 1: Create New Binary
```zig
// build.zig
const exe_new = b.addExecutable(.{
    .name = "sui-zig-rpc-client-v2",
    .root_source_file = "src/main_v2.zig",
});
```

### Step 2: Implement main_v2.zig
- Use new API only
- Import from commands/
- Simplified functionality

### Step 3: Gradual Feature Parity
- Add features to v2
- Test against v1
- Document differences

### Step 4: Deprecate v1
- Mark v1 as deprecated
- Guide users to v2
- Eventually remove v1

## Current Recommendation

**Stay with current dual-API approach:**
- Old API: stable, fully functional
- New API: available for new code
- Gradual migration as needed

**Benefits:**
- No breaking changes
- Backward compatible
- Flexible migration path
- Low risk

**When to fully migrate:**
- When commands.zig is fully replaced
- When all tests use new API
- When documentation is updated
- When users are ready

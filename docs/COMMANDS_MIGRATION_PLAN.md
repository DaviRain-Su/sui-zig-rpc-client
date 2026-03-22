# Commands Module Migration Plan

## Goal
Migrate `src/commands.zig` from old `rpc_client` API to new `rpc_client_new` API, then delete old implementation.

## Current State
- `commands.zig`: ~33,000 lines using old `client.rpc_client.*`
- Old API: `src/client/rpc_client/client.zig` (44,708 lines)
- New API: `src/client/rpc_client/root.zig` + 16 modules (~214,000 lines)

## Migration Strategy

### Phase 1: Create Compatibility Adapter
- Create `src/commands/adapter.zig` to bridge old and new APIs
- Map old types to new types
- Keep existing command logic unchanged initially

### Phase 2: Migrate Command by Command
1. `account` commands (balance, objects)
2. `tx` commands (simulate, execute, build)
3. `move` commands (call, publish)
4. `wallet` commands
5. Complex commands (swap, flash_loan)

### Phase 3: Remove Old Dependencies
- Update imports in `commands/mod.zig`
- Remove old API usage
- Clean up

### Phase 4: Delete Old Implementation
- Delete `src/client/rpc_client/client.zig`
- Update `src/root.zig` to use new API as default
- Update all references

## Type Mappings

| Old API | New API | Status |
|---------|---------|--------|
| `RpcRequest` | `rpc_client_new.client_core.RpcRequest` | ✅ Available |
| `ReadQueryActionResult` | `rpc_client_new.query.QueryResult` | ✅ Available |
| `ProgrammaticClientAction` | `rpc_client_new.builder.*` | ✅ Available |
| `ObjectDataOptions` | `rpc_client_new.object.ObjectDataOptions` | ✅ Available |
| `DynamicFieldName` | `rpc_client_new.object.DynamicFieldName` | ✅ Available |
| `OwnedObjectsFilter` | `rpc_client_new.object.OwnedObjectsFilter` | ✅ Available |

## Testing Strategy
- Maintain 700+ tests passing
- Add integration tests for new API
- Verify no regression in CLI behavior

## Timeline Estimate
- Phase 1: 1-2 hours
- Phase 2: 4-6 hours
- Phase 3: 1-2 hours
- Phase 4: 30 minutes

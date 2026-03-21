# AGENT.md - Sui Zig RPC Client Guidelines

## Build/Test Commands
- `zig build` - Compile the project
- `zig build test` - Run all tests (required before finishing changes)
- `zig build run -- help` - Run CLI locally and show usage
- `zig build run -- [command]` - Test specific CLI commands
- Run specific test: Use `zig test src/[file].zig` to run tests in a single file
- `zig build move-fixture-test` - Run Move fixture tests with `sui move test`

## Project Architecture
- **Modular structure**: Core client (`src/root.zig`), commands (`src/commands/`), and main CLI (`src/main.zig`)
- **Core modules**: `sui_client_zig` (RPC client), `commands` (CLI dispatch), main executable
- **Key components**: RPC client (`src/client/rpc_client/`), transaction builders (`src/tx_*.zig`), keystore (`src/keystore.zig`)
- **Tests**: Colocated with implementation using `test` blocks, no separate tests/ directory
- **Configuration**: Uses `~/.sui/sui_config/client.yaml` for RPC, `~/.sui/sui_config/sui.keystore` for keys

## Code Style & Conventions
- **Formatting**: Idiomatic Zig with 4-space indentation
- **Naming**: `snake_case` for functions/variables, `CamelCase` for types/enums
- **Testing**: Descriptive test names like `test "feature does specific thing"`
- **Imports**: Use qualified imports (`const std = @import("std")`), module aliases for clarity
- **Error handling**: Use Zig's error unions, provide context in error messages
- **JSON/RPC**: Small helper functions for payload construction (`write*`, `build*`)
- **Security**: Never commit real keys, use temporary fixtures, clean up test files

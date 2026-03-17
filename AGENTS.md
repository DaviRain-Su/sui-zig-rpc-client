# Repository Guidelines

## Project Structure & Module Organization
- `src/main.zig` — CLI entrypoint, config resolution (RPC/keystore), account helpers, and error mapping.
- `src/cli.zig` — command-line argument parsing and `--help` usage text.
- `src/commands.zig` — command dispatch (`tx simulate/payload/send`, `tx build`, `rpc`, `account` commands) and transaction payload helpers.
- `src/client/rpc_client/` — RPC transport and client surface.
- `README.md` — usage examples and behavior notes.
- Tests are colocated with implementation in `.zig` files using `test` blocks (no separate `tests/` directory today).

## Project Goal & Contributor Priority
- Long-term goal: make this CLI capable of calling any SUI on-chain program, not only fixed built-in RPC workflows.
- When choosing between equivalent tasks, prefer work in this order:
  - Generic instruction construction from CLI inputs (`--commands`, move-call args, future generic input schemas).
  - Account metadata and signer resolution (`--signer`, keystore selectors, sender inference).
  - Transaction lifecycle support: construction, simulation, submission, and confirmation.
  - Reusable RPC/client surfaces for end-to-end arbitrary program invocation.
- Narrow one-off command additions are lower priority unless they unlock a reusable path above.
- Prefer adding small, composable helpers over command-specific branching.

## Build, Test, and Development Commands
- `zig build`  
  Compile the project.
- `zig build test`  
  Run all tests. Do this before finishing each change.
- `zig build run -- help`  
  Run the CLI locally and print usage.
- `zig build run -- tx simulate ...` / `zig build run -- tx send ...`  
  Quick smoke checks for transaction paths.
- `zig build run -- account list`  
  Verify keystore integration flow.

## Coding Style & Naming Conventions
- Use idiomatic Zig formatting and 4-space indentation.
- Prefer `snake_case` for locals, parameters, and functions.
- Use descriptive enum/struct names in `CamelCase`.
- Keep JSON/RPC payload construction in small helper functions (`write*`, `build*`) and share when possible.
- Prefer `std.testing` assertions and avoid heavy inline duplication of parsing/building logic.
- Do not add broad abstractions unless it reduces duplication across tx workflows.

## Testing Guidelines
- Add tests close to the code being changed.
- Test naming style: descriptive sentence-like names, e.g. `test "tx_simulate rejects partial move-call args"`.
- New behavior should include:
  - a parser-level test (argument acceptance/rejection),
  - a command-level test (payload/params shape),
  - and mock RPC assertions when RPC calls are affected.
- Always run `zig build test` after edits and report pass/fail clearly.

## Security & Configuration Notes
- Default config paths used by the CLI:
  - RPC config: `~/.sui/sui_config/client.yaml` or `SUI_CONFIG`
  - Keystore: `~/.sui/sui_config/sui.keystore` or `SUI_KEYSTORE`
- Never commit real private keys, tokens, or local keystore files.
- For tests and local runs, use temporary fixture files and clean them up.

## Commit & Pull Request Guidelines
- This repo has no established commit history yet; use conventional, imperative commit messages such as:  
  - `feat: add shared programmable tx context builder`  
  - `fix(cli): reject invalid command JSON shapes`
- PRs should include:
  - concise summary and intent,
  - files changed,
  - verification commands/results (`zig build test` required),
  - and any remaining follow-up risks.

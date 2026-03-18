# TODO

## Goal

Make this CLI capable of constructing, simulating, sending, and confirming
transactions for arbitrary Sui on-chain programs, not only fixed built-in
workflows.

The highest-priority work is anything that reduces manual intervention in the
generic `move function` -> request artifact -> `tx dry-run/send` path.

## Highest Priority

### 1. Transaction-level joint candidate selection

Current state:
- `Pool`, `Position`, `Coin<T>`, and gas inputs can often be discovered or
  partially auto-selected.
- Cross-parameter linking exists in both directions for some object candidates.

Still needed:
- Rank complete `Pool / Position / Coin / gas` combinations, not just
  individual parameters.
- Prefer candidate sets that are internally consistent for one transaction.
- Avoid choosing business coins that conflict with gas payment.
- Make joint selection deterministic when multiple valid candidates exist.

Acceptance criteria:
- `move function --summarize` can produce a preferred artifact from a
  transaction-level best candidate set, not just per-parameter hints.

### 2. Dual-coin and vector coin auto-arrangement

Current state:
- Scalar `Coin<T>, amount` can already auto-select coins and produce
  `MergeCoins + SplitCoins` in preferred templates.

Still needed:
- Support dual-coin flows such as liquidity provision.
- Support `vector<Coin<T>>` automatic selection and coverage planning.
- Support multi-amount and multi-coin merge/split planning.
- Keep business coin selection isolated from gas coin selection.

Acceptance criteria:
- Common DeFi-style signatures can produce executable preferred templates
  without hand-written `SplitCoins` / `MergeCoins`.

### 3. Make `move function --dry-run/--send` close to one-click

Current state:
- `move function` can emit preferred request artifacts and directly execute
  `--dry-run` / `--send`.

Still needed:
- Resolve all inferable placeholders before execution.
- Leave only genuinely unknowable parameters for manual input.
- Reduce `UnresolvedMoveFunctionExecutionTemplate` failures in common flows.

Acceptance criteria:
- Typical real protocol calls can go from ABI discovery to dry-run without
  manual intermediate artifact editing.

## Medium Priority

### 4. Stronger shared object discovery

Current state:
- Shared objects are discovered from presets, object summaries, and module
  event heuristics.

Still needed:
- Add more generic discovery sources and fallback paths.
- Improve coverage for protocols that do not expose recent useful events.
- Improve candidate stability for shared objects such as pools.

### 5. Complete ABI lowering coverage

Current state:
- Common scalars, common wrappers, object arguments, `Option<T>`, many vectors,
  and concrete generic substitutions are supported.

Still needed:
- Unknown pure struct lowering.
- More nested generic/container combinations.
- Broader coverage for complex pure value encoding paths.

### 6. Remove remaining unsafe fallbacks

Current state:
- Most common programmable transaction flows go through local builder paths.

Still needed:
- Continue shrinking `unsafe_moveCall` and `unsafe_batchTransaction` fallback
  usage.
- Keep transaction construction, simulation, and execution aligned to the same
  local builder path.

## Lower Priority but Still Important

### 7. Broader signer and account support

Current state:
- Common keystore-backed flows work.

Still needed:
- Expand signature scheme coverage.
- Improve compatibility with broader account setups.

### 8. Discovery and execution ergonomics

Still needed:
- Keep improving direct CLI outputs so users do not need to manually rewrite
  generated request artifacts.
- Preserve artifact piping and reusable template flows while making the default
  path simpler.

## Cetus-Specific Readiness Gaps

These are not protocol-specific feature branches. They are concrete examples of
where the generic path still needs work.

- Joint selection of `Pool + Position + Coin + gas`.
- Dual-coin automatic merge/split planning for liquidity flows.
- Fewer unresolved placeholders in real `add_liquidity` / `swap` execution.

## Definition of Done

The project is close to its long-term goal when all of the following are true:

- Given `package/module/function/type args/sender`, the CLI can usually resolve
  the required object inputs automatically.
- Common DeFi-style calls can auto-select coins, auto-plan merge/split steps,
  and auto-select gas safely.
- `move function --dry-run` works for most real protocols without manual
  request editing.
- The local builder path handles nearly all transaction construction without
  depending on unsafe RPC fallbacks.

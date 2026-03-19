# TODO

## Goal

Make this CLI capable of constructing, simulating, sending, and confirming
transactions for arbitrary Sui on-chain programs, not only fixed built-in
workflows.

The main measure of progress is how much manual intervention is still required
in the generic `move function` -> request artifact -> `tx dry-run/send` path.

## Completed Foundation

### Generic transaction building and execution

- [x] Generic `move function` summary path backed by normalized Move ABI.
- [x] Request artifact generation for `tx dry-run` and `tx send`.
- [x] Direct execution from `move function --dry-run` and `--send`.
- [x] Stdin-backed request artifact piping with `@-`.
- [x] Auto gas payment selection for request artifacts.
- [x] Auto gas budget estimation via dry-run for request artifacts.

### Argument encoding and type handling

- [x] `bcs:<type>:<value>` typed pure-value encoding.
- [x] Simplified Move type tags such as `0x2::coin::Coin<0x2::sui::SUI>`.
- [x] Common wrapper lowering for strings, IDs, options, vectors, and common
  generic substitutions.
- [x] Indexed explicit argument overrides with `--arg-at`.
- [x] Indexed object overrides with `--object-arg-at`.
- [x] Indexed vector object overrides with `--object-arg-at <index> '[]'`.
- [x] Owner-context auto-selection for pure `address` / `signer`
  parameters in `move function` templates.

### Object discovery and candidate linking

- [x] Shared/owned object input token generation from object summaries.
- [x] Preset object aliases such as `clock` and Cetus global config.
- [x] Owned object candidate discovery from owner context.
- [x] Aggregate owned object candidate discovery across all owner pages instead
  of only the first `suix_getOwnedObjects` page.
- [x] Concrete generic owned object discovery after type specialization.
- [x] Shared object candidate discovery from module events.
- [x] Aggregate multiple recent event pages when discovering shared object
  candidates from module events.
- [x] `Pool -> Position` candidate linking across parameters.
- [x] `Position -> Pool` candidate linking from selected objects.
- [x] Candidate-set joint selection where owned candidates can resolve shared
  candidates.
- [x] Shared candidate scoring from owned candidate references when one
  candidate has a unique highest score.
- [x] Owned candidate scoring from selected object references when one
  candidate has a unique highest score.
- [x] Shared candidate scoring that also prefers already-selected object
  references over broader owned-candidate hints.
- [x] Shared/owned candidate scoring that weights explicit object references
  above auto-selected references.
- [x] Low-confidence deterministic tie-break selection for zero-score shared
  candidates discovered from ordered module events.
- [x] Vector-owned candidate scoring and stable ordering from selected object
  references.
- [x] Candidate `selection_score` exposure and deterministic score-first
  ordering in summaries.
- [x] Deterministic tie-break auto-selection for scored shared/owned
  candidates, with explicit `auto_selected_tiebreak` visibility.
- [x] Iterative multi-pass candidate propagation until shared/owned selections
  reach a stable fixed point.
- [x] Connected-component scoring bonuses for tied candidate sets so larger,
  more internally consistent object clusters rank higher.
- [x] Connected-component anchor bonuses so clusters already referenced by
  explicit/selected transaction objects outrank otherwise similar candidates.

### Coin automation

- [x] Amount-aware scalar `Coin<T>` selection.
- [x] Amount-aware `vector<Coin<T>>` coverage selection.
- [x] Avoid reusing selected business coins as auto gas payment.
- [x] Auto `SplitCoins` for scalar `Coin<T>, amount` preferred templates.
- [x] Auto `MergeCoins + SplitCoins` for covering scalar coin templates.
- [x] Ordered pairing of multiple trailing amount args to multiple scalar coin
  parameters for preferred split planning.
- [x] `MergeCoins + SplitCoins + MakeMoveVec` planning for `vector<Coin<T>>,
  amount` preferred templates.
- [x] Avoid reusing the same owned business coin across multiple `Coin<T>`
  parameters when auto-selecting and planning preferred split templates.
- [x] Avoid reusing already-selected scalar business coins inside later
  `vector<Coin<T>>` auto-selected parameters.

## Highest Priority Remaining Work

### 1. Transaction-level joint candidate ranking

- [ ] Rank complete `Pool / Position / Coin / gas` combinations instead of
  selecting each parameter mostly in isolation.
- [ ] Prefer candidate sets that are internally consistent for a single
  transaction.
- [ ] Make the final automatic choice deterministic when multiple valid
  combinations exist.
- [x] Expose the winning combination clearly in preferred summaries and request
  artifacts.

### 2. Dual-coin and multi-coin automatic arrangement

- [x] Support dual-coin flows such as liquidity provision with both asset sides
  selected automatically.
- [x] Support multi-amount and multi-coin merge/split planning in one template.
- [x] Keep gas coin exclusion correct in multi-coin scenarios.

### 3. Make `move function --dry-run/--send` close to one-click

- [ ] Resolve all inferable placeholders before execution.
- [ ] Leave only genuinely unknowable parameters for manual input.
- [ ] Reduce `UnresolvedMoveFunctionExecutionTemplate` failures in common
  protocol flows.
- [x] Make the default execution path prefer preferred request artifacts
  whenever a safe resolution exists.

## Medium Priority Remaining Work

### 4. Stronger shared object discovery

- [x] Add owned-object-content-based shared discovery beyond recent module
  events.
- [ ] Improve fallback behavior for protocols that do not expose recent useful
  events.
- [ ] Improve candidate stability for shared objects such as pools.

### 5. Complete ABI lowering coverage

- [ ] Support more unknown pure struct lowering.
- [ ] Support more nested generic/container combinations.
- [ ] Broaden coverage for complex pure-value encoding paths.

### 6. Remove remaining unsafe fallbacks

- [ ] Continue shrinking `unsafe_moveCall` usage.
- [ ] Continue shrinking `unsafe_batchTransaction` usage.
- [ ] Keep construction, simulation, and execution aligned to the same local
  builder path.

## Lower Priority but Important

### 7. Broader signer and account support

- [ ] Expand signature scheme coverage.
- [ ] Improve compatibility with broader account setups.

### 8. Discovery and execution ergonomics

- [ ] Keep reducing manual copying from summaries into execution commands.
- [ ] Preserve reusable artifact flows while simplifying the default CLI path.

## Cetus Readiness Gaps

These are not protocol-specific feature branches. They are concrete examples of
what the generic path still needs to finish.

- [ ] Joint selection of `Pool + Position + Coin + gas`.
- [ ] Dual-coin automatic merge/split planning for liquidity flows.
- [ ] Fewer unresolved placeholders in real `add_liquidity` / `swap`
  executions.

## Definition of Done

- [ ] Given `package/module/function/type args/sender`, the CLI can usually
  resolve the required object inputs automatically.
- [ ] Common DeFi-style calls can auto-select coins, auto-plan merge/split
  steps, and auto-select gas safely.
- [ ] `move function --dry-run` works for most real protocols without manual
  request editing.
- [ ] The local builder path handles nearly all transaction construction
  without depending on unsafe RPC fallbacks.

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
- [x] Separate chain built-in object presets from protocol-specific object
  registry entries so protocol aliases do not live in the generic built-in
  preset layer.
- [x] Preset object aliases such as `clock` and Cetus global config.
- [x] Owned object candidate discovery from owner context.
- [x] Aggregate owned object candidate discovery across all owner pages instead
  of only the first `suix_getOwnedObjects` page.
- [x] Concrete generic owned object discovery after type specialization.
- [x] Additional owned object candidate discovery from already discovered
  object content, not only owner-page queries.
- [x] Additional owned object candidate discovery from dynamic fields of
  already selected or discovered seed objects.
- [x] Aggregate owned candidates discovered from seed-object content and
  dynamic fields instead of treating the two sources as mutually exclusive.
- [x] Owned object candidate discovery from recent module events, filtered back
  down by owner and concrete struct type.
- [x] Aggregate object ids discovered from recent module event `parsedJson`
  and transaction `objectChanges` instead of treating the two sources as
  mutually exclusive.
- [x] Prioritize `txDigest -> showObjectChanges` followups for recent module
  events that do not already expose object ids in `parsedJson`.
- [x] Owned event fallback can continue from the parameter type's own
  `package/module` when the current function module exposes no useful
  candidates.
- [x] Reuse owned module-event discovery results across a single
  `move function` template build instead of rescanning the same module
  fallback in later parameters or fixed-point rounds.
- [x] Reuse borrowed owned module-event candidates inside fallback merge paths
  instead of recloning temporary candidate arrays on each lookup.
- [x] Shared object candidate discovery from module events.
- [x] Aggregate multiple recent event pages when discovering shared object
  candidates from module events.
- [x] Reuse shared module-event discovery results across a single
  `move function` template build instead of rescanning the same module
  fallback in later parameters or fixed-point rounds.
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
- [x] Low-confidence deterministic tie-break selection for zero-score owned
  candidates discovered from owner context.
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
- [x] Avoid reusing the same non-coin owned object across later scalar/vector
  object parameters during auto-selection.
- [x] Reserve explicit owned object arguments before cross-parameter owned
  auto-selection runs.

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
- [x] Reserve later explicit coin object arguments before earlier business-coin
  auto-selection runs.
- [x] Reserve later explicit coin object arguments before earlier preferred
  split/merge planning chooses its source coins.

## Highest Priority Remaining Work

### 1. Transaction-level joint candidate ranking

- [ ] Rank complete `Pool / Position / Coin / gas` combinations instead of
  selecting each parameter mostly in isolation.
- [x] Prefer candidate sets that are internally consistent for a single
  transaction.
- [x] Make the final automatic choice deterministic when multiple valid
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
- [x] Keep owner-context candidate resolution bounded in live RPC paths by
  caching more repeated discovery work than module-event scans alone.
- [x] Reuse repeated seed-object `showContent` reads across a single
  `move function` template build instead of rereading the same object during
  fallback discovery, scoring, and fixed-point rounds.
- [x] Reuse repeated object-id extraction from seed-object `showContent`
  payloads across a single `move function` template build instead of reparsing
  the same content JSON during shared/owned fallback and candidate scoring.
- [x] Reuse repeated seed-object dynamic-field scans across a single
  `move function` template build instead of rescanning the same object during
  shared/owned fallback discovery rounds.
- [x] Reuse recent module-event object-id discovery across shared/owned
  fallback paths instead of rescanning the same `package/module` event source
  twice in one template build.
- [x] Bound seed-object discovery work by prioritizing selected objects and
  only following a capped number of top-ranked candidates per parameter.
- [x] Skip candidate-seed expansion for parameters that already have a stable
  explicit or non-tiebreak auto selection.
- [x] Reuse borrowed cached dynamic-field discoveries inside shared/owned
  fallback hot paths instead of recloning temporary object-id lists.
- [x] Reuse repeated candidate object summary reads across a single
  `move function` template build instead of refetching the same object during
  shared/owned candidate filtering.
- [x] Reuse borrowed cached object summaries inside shared/owned candidate
  filtering instead of recloning the same summary struct on each lookup.
- [x] Reuse cached content-derived object ids inside joint candidate component
  scoring instead of rescanning raw `showContent` JSON while computing
  candidate-cluster connectivity and anchor bonuses.
- [x] Reuse borrowed cached content-derived object ids inside move discovery
  and scoring hot paths instead of recloning temporary discovery lists on each
  lookup.
- [x] Reuse collected seed object ids across a single shared/owned fallback
  pass, and only rebuild them when the current round actually changes a
  parameter's candidates or automatic selection.
- [x] Reuse parsed selected-object ids for repeated `explicit_arg_json` /
  `auto_selected_arg_json` values instead of reparsing the same argument JSON
  across fixed-point scoring passes.
- [x] Reuse selected-object id buckets across repeated fixed-point scoring
  passes until the explicit/auto-selected parameter state actually changes.
- [x] Reuse repeated initial owner-context owned-object discovery reads across
  a single `move function` template build instead of requerying the same
  `(owner, struct type)` for multiple identical parameters.
- [x] Reuse repeated coin-page reads across a single selected-argument
  resolution flow instead of requerying the same `(owner, coin type)` during
  merge/split and repeated coin selector resolution.
- [x] Reuse repeated owned-object page reads across a single selected-argument
  resolution flow instead of requerying the same `(owner, owned-object
  request)` during repeated object selector resolution.
- [x] Reuse repeated `sui_getObject(showOwner)` reads across a single
  selected-argument resolution flow instead of requerying the same object
  metadata for repeated `object_input` / `object_preset` selectors.
- [x] Make the default execution path prefer preferred request artifacts
  whenever a safe resolution exists.

## Medium Priority Remaining Work

### 4. Stronger shared object discovery

- [x] Add owned-object-content-based shared discovery beyond recent module
  events.
- [x] Aggregate shared candidates discovered from events and owned-object
  content instead of treating the two sources as mutually exclusive.
- [x] Use already-discovered shared candidates as additional seeds when
  discovering other shared object parameters.
- [x] Fallback shared discovery from dynamic fields of already selected or
  discovered seed objects.
- [x] Aggregate shared candidates discovered from seed-object content and
  dynamic fields instead of treating the two sources as mutually exclusive.
- [ ] Improve fallback behavior for protocols that do not expose recent useful
  events.
- [x] Improve candidate stability for shared objects such as pools.

### 5. Complete ABI lowering coverage

- [x] Support more unknown pure struct lowering.
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

### 9. Local Move contract coverage matrix

- [ ] Add a `counter_baseline` package for pure-value and sender/signer
  invocation coverage.
- [x] Add a `shared_state_lab` package for shared object and versioned shared
  object coverage.
- [x] Add a `generic_vault` package for generic object and generic pure struct
  coverage.
- [x] Add a `vector_router` package for `vector<object>`, `vector<Coin<T>>`,
  and `MakeMoveVec` coverage.
- [x] Add a `receipt_flow_lab` package for receipt/capability multi-step
  flows.
- [x] Add a `dynamic_registry` package for content/dynamic-field-based
  discovery coverage.
- [x] Add an `admin_upgrade_lab` package for capability/publish/upgrade
  coverage.
- [x] Add a `pool_like_protocol_lab` package for transaction-level
  `Pool + Position + Coin + gas` coverage.
- [ ] Wire the local package matrix into deterministic regression docs/tests,
  not only live protocol smoke checks.

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

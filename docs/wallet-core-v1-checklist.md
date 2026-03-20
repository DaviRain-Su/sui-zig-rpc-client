# Wallet Core V1 Checklist

This document defines what counts as a shippable `wallet-core v1` for this
repository.

The goal is not "feature complete wallet forever". The goal is a stable Sui
wallet execution core that a future web wallet can consume without reimplementing
transaction building, policy handling, or request lifecycle state.

## Scope

`wallet-core v1` in this repo means:

- one stable CLI surface for wallet/request/intent flows
- one stable artifact contract for `wallet_intent`, `request`, `sponsor_envelope`,
  and `schedule_job`
- one local Sui execution core for build, dry-run, sign, send, and status
- one local state layer for wallet, request, and delegated session lifecycle

It does **not** mean:

- a finished web wallet
- a full sponsor backend
- a production scheduler service
- protocol-specific "works on every DeFi package" guarantees

## Release Blockers

These items should be true before calling the current core "v1 ok".

### CLI Surface

- `wallet` lifecycle is stable:
  - `create/import/use/accounts/address/balance/coins/objects/export-public`
  - `connect/disconnect`
  - `passkey register/login/list/revoke`
  - `session create/list/revoke`
  - `policy inspect`
  - `fund`
- `request` lifecycle is stable:
  - `build/inspect/dry-run/sponsor/sign/send/status`
  - `list/cancel/resume/rebroadcast`
  - `schedule`
- `wallet intent` lifecycle is stable:
  - `build/dry-run/send`

### Artifact Contracts

- `wallet_intent` schema is stable enough for web and CLI reuse
- `request` artifacts can be produced from direct CLI input or from full
  `move function --summarize` output
- `sponsor_envelope` carries sponsor mode, gas source preference, fallback
  semantics, payment metadata, concurrency metadata, and delegated session data
- `schedule_job` carries deterministic replacement behavior and stale-object
  policy

### Execution Core

- build, dry-run, sign, send, and status continue to share the same local Sui
  builder path where possible
- delegated session metadata reaches execution-side provider authorizers
- sponsor and non-sponsor flows do not fork into unrelated execution stacks
- request lifecycle state is persisted and updated through `request_state.json`

### State Layers

- active wallet selector is persisted
- wallet registry supports local signer, passkey, and external wallet modes
- delegated session registry supports create/list/revoke with merged policy
- request lifecycle store supports:
  - `built`
  - `resolved`
  - `sponsored`
  - `signed`
  - `submitted`
  - `confirmed`
  - `failed`
  - `cancelled`
  - `replaced`

### Smoke Coverage

- deterministic command-level wallet smoke regressions exist for:
  - sponsored transfer
  - sponsored swap
  - session-limited swap
  - scheduled self-transfer
- external protocol smoke still covers at least:
  - Cetus live ABI / discovery / artifact sanity
  - Hashi local publish / finish_publish / deposit

## Non-Blocking V1 Follow-Up

These items are important, but should not block calling the current wallet core
`v1 ok` if the release blockers are solid.

- richer passkey backend and device sync
- production sponsor relay
- production scheduler service
- asset metadata registry / icons / trust policy
- payment inbox / merchant reconciliation tooling
- richer frontend-oriented preview rendering

## Remaining Core Risks

These are the main technical risks that still matter after wallet lifecycle
commands were added.

### Generic Sui Execution Risks

- `unsafe_moveCall` / `unsafe_batchTransaction` still need to keep shrinking
- joint selection of `Pool + Position + Coin + gas` is not fully solved
- some real DeFi flows still leave unresolved placeholders

### Wallet Product Risks

- passkey and external wallet modes are modeled locally, but not yet backed by
  a production-grade remote credential service
- scheduling is represented in artifacts and local state, but not yet backed by
  a persistent remote scheduler
- sponsor semantics are modeled, but there is no production sponsor policy
  server in this repo

## Verification Gate

Before tagging the current core as `wallet-core v1`, run at least:

```bash
zig build test --summary all
zig build move-fixture-test
bash scripts/hashi_publish_smoke.sh /tmp/hashi_inspect/packages/hashi
bash scripts/hashi_finish_publish_smoke.sh /tmp/hashi_inspect/packages/hashi
bash scripts/hashi_deposit_smoke.sh /tmp/hashi_inspect/packages/hashi
```

For live protocol sanity, keep a lightweight Cetus mainnet check in the release
notes:

- `sui_getNormalizedMoveFunction` against a real Cetus entrypoint
- at least one real artifact or dry-run path that still resolves correctly

## Exit Condition

This repo can call the current wallet layer `wallet-core v1` when:

- the CLI/API surface above is stable enough that a web wallet can consume it
  without redefining artifacts
- the release blockers are satisfied
- the verification gate passes
- the remaining risks are explicitly accepted as post-v1 work, not hidden debt

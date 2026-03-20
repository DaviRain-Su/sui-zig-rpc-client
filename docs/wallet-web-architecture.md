# Wallet Web Architecture

This document defines the next step after `wallet-core v1`: a Tempo-style Sui
wallet web application that reuses this repo's request/intent/policy core
instead of rebuilding transaction logic in TypeScript.

## Goals

- build a Sui wallet web product with a Tempo-like experience:
  - embedded passkey mode
  - external wallet mode
  - sponsor-aware request flow
  - scheduled actions
  - delegated session policies
  - clear request review and lifecycle visibility
- keep transaction lowering and request construction anchored to the current
  Zig wallet core
- make web and CLI consume the same artifact contracts

## Non-Goals

- do not port Tempo's chain-level transaction format into Sui
- do not fork a second Sui transaction builder in the frontend
- do not block web work on every remaining generic DeFi edge case

## Repo Split

The clean split should be:

### Current Repo: `wallet-core`

This repository remains the Sui execution and artifact core.

Responsibilities:

- Sui RPC client
- generic Move / PTB lowering
- wallet/request/intent artifact generation
- signer/provider/session policy contract
- local request lifecycle state model

### New Repo: `wallet-web`

The web wallet should live in a separate repository.

Responsibilities:

- onboarding flows
- account selection UX
- balances / assets / request review UI
- session and sponsor management UI
- scheduled request management UI

### Optional Service Repo: `wallet-services`

If needed, keep service processes separate from both core and web.

Responsibilities:

- sponsor relay
- scheduler
- passkey credential registry
- notification / webhook integration

## System Boundaries

### Web Uses Core Contracts

The web wallet should consume:

- `wallet_intent`
- request artifacts
- `sponsor_envelope`
- `schedule_job`
- request lifecycle state summaries

The web wallet should not invent alternative versions of those payloads.

### Web Does Not Own Lowering

The web wallet may gather user input and show previews, but it should not own:

- Move ABI lowering
- PTB construction
- gas planning semantics
- sponsor / request artifact contract design

That logic should stay in `wallet-core`.

## Account Modes

The web wallet should keep two equal first-class account modes.

### Embedded Passkey Mode

- domain-bound passkey registration
- device-oriented credential management
- session creation from embedded identity
- sponsor-friendly transaction approval flows

### External Wallet Mode

- connect/disconnect external wallet providers
- inspect connected signer metadata
- build the same `wallet_intent` / `request` flow even when final signing is
  external

## Artifact Flow

The intended end-to-end flow is:

1. web gathers user action and policy/session context
2. web builds a `wallet_intent`
3. core lowers that into a request artifact
4. optional sponsor step produces a `sponsor_envelope`
5. sign/send runs through the same execution core
6. request lifecycle state is tracked and displayed back in web UI

That gives web one stable lifecycle instead of per-feature special cases.

## Frontend MVP

The first web release should focus on a narrow but coherent product.

### Essential Screens

- onboarding / account mode selection
- wallet home:
  - address
  - balances
  - recent requests
- request review
- send / self-transfer
- swap
- session list / create / revoke
- scheduled request list / inspect / cancel

### Nice-to-Have Later

- advanced policy editor
- sponsor dashboard
- payment reconciliation dashboard
- route-aware multi-protocol comparison UI

## Service Interfaces

Even if services are mocked at first, define them as stable boundaries.

### Sponsor Service

Input:

- request artifact
- wallet/session metadata
- sponsor policy preferences

Output:

- `sponsor_envelope`
- refusal reason or fallback guidance

### Scheduler Service

Input:

- `schedule_job`

Output:

- persisted job id
- replace / cancel / stale-object status

### Passkey / Credential Service

Input:

- passkey registration / login metadata

Output:

- credential registry records
- revocation state
- device-oriented public metadata

## API Shape

Keep the API contract aligned with current artifacts.

- `POST /wallet-intents`
- `POST /requests/build`
- `POST /requests/dry-run`
- `POST /requests/sponsor`
- `POST /requests/sign`
- `POST /requests/send`
- `GET /requests/:id`
- `POST /schedules`
- `POST /schedules/:id/cancel`
- `POST /sessions`
- `POST /sessions/:id/revoke`

These do not all need to ship on day one, but the artifact vocabulary should
match the current CLI.

## Recommended Stack

The web wallet should be built with a conventional frontend stack and a thin
integration layer over the existing core.

- frontend:
  - React
  - TypeScript
  - a minimal state/query layer
- backend bridge:
  - lightweight HTTP wrapper around the core or direct core integration
- core:
  - this Zig repo

The important part is not the JS framework choice. The important part is
keeping one transaction/request core.

## Delivery Phases

### Phase 1: Core Bridge

- expose current wallet/request/intent flows behind a stable boundary
- prove web can build/dry-run/send through the same artifact contracts

### Phase 2: Wallet MVP

- onboarding
- balances
- request review
- send
- swap

### Phase 3: Session / Sponsor UX

- session creation and revoke UI
- sponsor request review
- explicit fallback and refusal handling

### Phase 4: Scheduling / Reconciliation

- scheduled request lifecycle
- payment metadata views
- reconciliation grouping

## Exit Condition

The web wallet architecture is ready when:

- the web repo can depend on stable core artifacts
- the frontend does not need to reinterpret or rebuild transaction logic
- session, sponsor, and schedule flows use the same contracts already proven in
  CLI
- web can ship as a consumer of `wallet-core`, not as a second transaction
  engine

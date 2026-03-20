# Sui Wallet MPP-Style Plan

## Goal

Build a Sui wallet system that delivers a Tempo/MPP-style experience without
pretending that Sui should adopt Tempo's chain-level transaction format.

The target product is:

- a Sui-first wallet with both web frontend and CLI
- built on top of the existing object-aware Zig transaction engine in this repo
- capable of passkey onboarding, sponsor-aware execution, batched actions,
  session/access policies, and scheduled execution
- compatible with Sui-native PTB, signer, and object semantics

## Core Position

Tempo/MPP is useful as a product and protocol-design reference. It is not the
right implementation shape for Sui at the transaction-type level.

On Sui, the correct approach is:

- keep Sui-native PTB and object semantics
- add a wallet intent layer above PTB
- add sponsor, scheduler, and policy services around PTB
- make web and CLI share the same intent and execution model

In short:

`MPP-style wallet UX on top of Sui-native execution`

## Non-Goals

This plan explicitly does not try to:

- invent a new Sui chain-level transaction type
- emulate EVM nonce semantics one-for-one
- replace Sui signer/account primitives with Tempo-specific wire formats
- turn this repo into a generic cross-chain wallet core before the Sui path is
  finished

## Feature Mapping

### Passkeys / WebAuthn / P256

MPP/Tempo reference:

- passkey-native embedded account UX

Sui implementation:

- passkey-backed wallet signer
- optionally paired with zkLogin or embedded account bootstrap
- frontend-first authentication, but CLI must be able to consume the resulting
  signer/session material

### Fee Sponsorship

MPP/Tempo reference:

- sponsored transactions and fee payer abstraction

Sui implementation:

- sponsor-ready request artifact generation
- sponsor service that accepts a wallet intent or request artifact and returns
  sponsored tx bytes or a signed sponsor attachment
- CLI and web both support dry-run with and without sponsor resolution

### Batch Calls

MPP/Tempo reference:

- multi-call transaction UX

Sui implementation:

- directly backed by PTB
- wallet UI/CLI must expose batching as a first-class action composer
- result chaining, merge/split planning, gas planning, and object reuse stay in
  the Sui engine

### Access Keys

MPP/Tempo reference:

- scoped access keys and limited delegated execution

Sui implementation:

- wallet policy layer plus delegated session/account capabilities
- not a chain-level transaction field
- enforced by wallet signer policy, optional backend policy service, and
  optional Move policy objects when persistent on-chain authorization is needed

### Parallel Nonces

MPP/Tempo reference:

- nonce-key concurrency

Sui implementation:

- concurrent execution through object separation, gas coin separation, and PTB
  planning
- wallet must reason about object conflicts, not account-sequence counters
- scheduler and CLI should surface whether a planned action can safely execute
  in parallel

### Scheduled Transactions

MPP/Tempo reference:

- scheduled execution built into the broader protocol story

Sui implementation:

- scheduler service plus signed wallet intent
- optional policy object or signed validity window
- relayer/scheduler submits a normal Sui transaction when conditions are met

## Product Shape

The product should be one wallet, but with clearly separated layers.

### User-Facing Surfaces

- `wallet-web`
- `wallet-cli`

### Account Modes

The wallet must support two first-class user modes.

- embedded account mode
- external wallet mode

Embedded account mode is for:

- passkey-first onboarding
- sponsor-friendly flows
- session/access policy management
- scheduled execution and background automation

External wallet mode is for:

- standard Sui wallet connection
- power users who do not want embedded credentials
- compatibility with the broader Sui wallet ecosystem

The product must not force a false choice between them. It should allow:

- starting with passkey and later exporting or linking
- starting with external wallet and later enabling embedded/session features
- explicit network/account switching without changing transaction semantics

### Shared Core

- `wallet-intent`
- `wallet-policy`
- `wallet-artifact`

### Execution Engines

- `sui-engine`
- future `tempo-engine` only if we later decide to support Tempo itself

### Services

- `sponsor-service`
- `scheduler-service`
- `passkey-auth-service`
- optional `policy-service`

## Account and Signer Model

The signer model needs to be more explicit than a generic `passkey-auth-service`.

### Embedded Passkey Account

This mode needs:

- credential registry
- domain / relying-party binding
- signer public key lookup
- device enrollment metadata
- recovery or secondary-access story

At the wallet level, passkey support is not complete unless it covers:

- registration
- authentication
- listing enrolled credentials
- revocation
- multi-device addition

### External Wallet Mode

This mode needs:

- wallet-standard compatible connection
- address discovery
- chain/network handshake
- capability detection
- fallback when advanced features like sponsorship or session execution are not
  available through the external signer

## Why This Repo Matters

This repository is already the right base for the Sui engine layer because it
already has:

- object-aware Move call and PTB construction
- sender/signer/gas handling
- dry-run, build, send, and request artifact flows
- protocol-level live validation against Cetus, FlowX, Turbos, and Hashi
- reusable CLI and RPC/client surfaces

That means this repo should remain focused on:

- Sui execution core
- intent lowering to PTB/request artifacts
- sponsor/scheduler friendly artifacts
- wallet-facing CLI primitives

It should not become the full frontend application repo by itself.

## Proposed Architecture

```text
apps/
  wallet-web/
  wallet-cli/

packages/
  wallet-intent/
  wallet-policy/
  wallet-artifact/
  signer-passkey/
  sponsor-client/
  scheduler-client/

engines/
  sui-engine/           <- this Zig repo's core responsibility

services/
  sponsor-service/
  scheduler-service/
  passkey-auth-service/
```

For the near term, this current repo can host:

- the Sui execution core
- the wallet intent schema
- CLI subcommands for wallet-style flows
- reference docs and smoke scripts

## Wallet Intent Envelope

The key abstraction should be a wallet intent, not a raw transaction.

Example shape:

```json
{
  "network": "sui:mainnet",
  "sender": "0x...",
  "actions": [
    {
      "kind": "swap",
      "route": "aggregator-v2/cetus",
      "from": "0x2::sui::SUI",
      "to": "0xdba34672...::usdc::USDC",
      "amount": "100000000"
    }
  ],
  "execution_mode": "dry_run",
  "valid_after_ms": null,
  "valid_before_ms": null,
  "sponsor": {
    "mode": "optional"
  },
  "policy": {
    "session_key": null,
    "spending_limit": null
  }
}
```

The lowering pipeline should be:

`wallet intent -> resolved request artifact -> Sui PTB/options -> dry-run/send`

## CLI Direction

The current CLI should grow wallet-oriented entrypoints without abandoning the
lower-level transaction tooling.

### Proposed New Commands

- `wallet account list`
- `wallet balance`
- `wallet intent build`
- `wallet intent dry-run`
- `wallet intent send`
- `wallet sponsor request`
- `wallet schedule create`
- `wallet session create`
- `wallet policy inspect`

### Relationship to Existing Commands

Existing low-level commands remain the execution substrate:

- `move function`
- `tx build`
- `tx dry-run`
- `tx send`
- `account objects`

New wallet commands should compile down to those same core paths instead of
adding a second transaction-construction stack.

## Tempo CLI Parity Check

This section answers a narrower question:

`Do we already cover the capability shape implied by Tempo's wallet/request CLI?`

Short answer:

- we cover the core transaction-experience direction
- we do not yet fully specify the operational CLI lifecycle around wallet
  management and request lifecycle management
- that missing part should be added explicitly instead of assumed

### `tempo wallet` Style Capabilities

The design already includes or strongly implies:

- account listing
- balance inspection
- passkey-backed account model
- session/access policy management
- sponsor-aware execution

The design does not yet spell out enough operational wallet commands for a real
CLI user journey. These should be added explicitly:

The first implementation batch is now in place:

- `wallet address`
- `wallet balance`

- `wallet create`
- `wallet import`
- `wallet export-public`
- `wallet use`
- `wallet coins`
- `wallet objects`
- `wallet signer inspect`
- `wallet passkey register`
- `wallet passkey login`
- `wallet connect`
- `wallet disconnect`
- `wallet accounts`
- `wallet fund`
- `wallet session revoke`

That means the current design is directionally correct but not yet at
Tempo-style CLI completeness for wallet lifecycle management.

### `tempo request` Style Capabilities

The design already includes or strongly implies:

- a request-like abstraction in the form of `wallet intent`
- dry-run before execution
- sponsor-aware request handling
- scheduled execution metadata
- shared web/CLI artifact flow

What is still missing is an explicit request lifecycle API at the CLI level.
That should be added as a first-class command group rather than buried inside
`wallet intent`.

The first implementation batch is now in place:

- `request build`
- `request inspect`
- `request dry-run`

Recommended commands:

- `request sponsor`
- `request sign`
- `request send`
- `request schedule`
- `request status`
- `request list`
- `request cancel`
- `request resume`
- `request rebroadcast`

Recommended artifacts:

- `wallet-intent.json`
- `request-artifact.json`
- `sponsor-envelope.json`
- `schedule-job.json`

### Concrete Gap Summary

So the right answer is:

- `wallet` parity: partial
- `request` parity: partial
- architecture: yes
- CLI lifecycle design: not yet complete

The missing work is not a rethink. It is a documentation and implementation
expansion around command groups and artifact contracts.

## Request Lifecycle

The request lifecycle needs to be explicit, not implied.

### Request States

At minimum, requests should be able to move through:

- `built`
- `resolved`
- `sponsored`
- `signed`
- `submitted`
- `confirmed`
- `failed`
- `scheduled`
- `cancelled`

### Request Operations

The CLI and frontend should both support:

- build a request from intent
- inspect request metadata and object freshness assumptions
- dry-run the request
- attach sponsor data
- attach signer/session approvals
- send the request
- poll and confirm the result
- schedule or cancel future execution

This is the piece that makes the wallet feel like a product instead of a thin
transaction wrapper.

## Frontend Direction

The frontend should not reimplement transaction logic. It should:

- collect user intent
- preview balances, object impacts, and sponsor behavior
- hand off to the same lowering logic or compatible artifact format
- invoke passkey/session signing
- submit via sponsor or direct send path

### Frontend MVP Screens

- onboarding
- account list / balances
- asset send
- swap
- transaction preview
- sponsored execution approval
- scheduled action creation
- session/access key management

## Policy Model

Access keys on Sui should be implemented as wallet policy, not fake nonce-key
emulation.

Initial policy scope should support:

- per-session allowed modules/functions
- spending limits per coin type
- recurring budget windows
- expiry windows
- optional recipient allowlists
- optional protocol allowlists
- optional object scope restrictions
- optional sponsor-only execution
- explicit revoke/update flows

This policy can start off-chain and later move partially on-chain where useful.

### Policy Features We Should Not Miss

To match the practical usefulness of Tempo-style access keys, policy must be
able to express:

- one-time spend limits
- daily / hourly recurring limits
- route-specific or protocol-specific permissions
- explicit destination restrictions
- session-name / device-name labeling
- emergency revocation

## Scheduling Model

Scheduled transactions should be treated as:

- signed wallet intent
- optional sponsor attachment
- scheduler-owned execution responsibility
- Sui-native PTB at actual execution time

This means scheduler correctness depends on:

- reproducible artifact generation
- object refresh before final execution
- clear failure states when object versions or balances drift

### Scheduling Features We Should Not Miss

The scheduling design should also cover:

- signed validity windows
- cancellation
- replacement / update of pending jobs
- sponsor interaction at execution time
- re-quote or re-resolve behavior for swaps
- explicit stale-object failure reporting

Scheduled execution in Sui is not just “send later”. It is “re-resolve safely
under moving object state”.

## Sponsorship and Fee Policy

Sui does not need Tempo's exact fee-token model, but the wallet still needs a
clear fee policy layer.

It should support:

- direct execution
- optional sponsorship
- sponsor-required execution
- gas source preference
- sponsor approval prompts
- fallback behavior when sponsor declines

The sponsor contract between CLI/web and service should include:

- sender
- requested action summary
- estimated gas
- sponsor policy metadata
- validity window
- replay protection / correlation id

## Payments and Reconciliation

Tempo documents put real weight on payment UX, not only transaction encoding.
The Sui wallet plan should do the same.

The wallet should eventually support:

- transfer memo / payment reference
- incoming payment watch
- payment request or invoice references
- simple reconciliation/export
- merchant-friendly payment status tracking

For Sui this likely means:

- wallet-level memo/reference metadata
- off-chain indexing
- explorer/deeplink integration
- optional on-chain companion objects for higher-assurance flows

## Assets and Metadata

The product needs an explicit metadata layer instead of relying on raw coin
types everywhere.

It should define:

- trusted token metadata source(s)
- symbol/decimals/icon resolution
- verification status
- protocol labels for route sources
- wallet-safe display names for wrapped assets

Without this, the frontend will degrade into explorer-style raw type strings.

## Concurrency and Execution Lanes

`Parallel nonces` in MPP should become `parallel-safe execution lanes` in Sui.

The wallet should explicitly reason about:

- gas coin lanes
- object conflict sets
- PTB-level concurrency safety
- swap and payment queueing
- user-visible “can run in parallel” hints

This should become both:

- a planner concern in the engine
- a UX concept in the wallet

## MVP Phases

### Phase 0: Documentation and Boundaries

- define this architecture clearly
- keep this repo focused on Sui engine and wallet-facing artifacts
- avoid cross-chain abstraction creep

### Phase 1: Wallet Intent Core

- define wallet intent schema
- add CLI commands to build/dry-run/send intents
- keep lowering on the existing local builder path

### Phase 2: Passkey and Sponsorship

- passkey signer integration
- sponsor-ready request flow
- sponsor service contract
- explicit external-wallet coexistence model

### Phase 3: Session / Access Policies

- session policy schema
- delegated execution in CLI and web
- auditable previews showing why an action is allowed
- recurring limits / recipient and protocol scoping

### Phase 4: Scheduling

- scheduler request schema
- validity windows
- replay protection and object-refresh logic
- cancel / replace / stale-state reporting

### Phase 5: Wallet UX Polish

- frontend flows
- better transaction preview
- clearer risk prompts
- route-aware swap UX
- payment references and reconciliation
- asset metadata and execution-lane UX

## Immediate Work Items

These are the next concrete steps that fit this repo.

1. Add a documented wallet intent schema to the repo.
2. Add explicit `wallet` CLI lifecycle commands:
   - create/import/use/address/balance/coins/objects
3. Add explicit `request` CLI lifecycle commands:
   - build/inspect/dry-run/sponsor/sign/send/schedule/status
4. Make request artifacts explicitly sponsor-friendly.
5. Add a passkey/session signer abstraction boundary.
6. Add an explicit embedded/external account-mode model to the design and CLI.
7. Add policy schema fields for recurring limits, recipient scoping, and
   protocol scoping.
8. Add scheduler-friendly artifact metadata:
   - validity window
   - sender
   - sponsor mode
   - object freshness requirements
9. Add payment reference and reconciliation metadata to the wallet artifact
   plan.
10. Add concurrency-lane metadata for parallel-safe execution planning.
11. Add wallet smoke scenarios that cover:
   - sponsored transfer
   - sponsored swap
   - session-limited swap
   - scheduled self-transfer

## Risks

### Over-Abstracting Too Early

If we try to unify Sui and Tempo transaction formats too early, the result will
be vague and fragile. The common layer should stop at intent and policy.

### Rebuilding the Transaction Stack Twice

The frontend must not fork transaction lowering logic away from this CLI engine.

### Treating Sui Like an Account-Nonce Chain

Sui concurrency should be modeled around objects, gas coins, and PTB conflicts,
not borrowed EVM nonce mental models.

### Scheduling Without Object Refresh

Scheduled execution must re-check object versions and balances before final
submission.

## Success Criteria

This plan is succeeding when:

- the same wallet intent can be built from web or CLI
- the same Sui engine lowers that intent into request artifacts/PTB
- sponsor and non-sponsor paths share one execution core
- passkey/session flows do not force a second transaction builder
- embedded and external wallet modes can coexist cleanly
- common wallet actions work with clear previews:
  - send
  - swap
  - sponsor
  - schedule
  - delegated session execution
- request lifecycle is explicit enough that a user can inspect, sponsor, sign,
  send, and resume work from artifacts instead of re-creating actions manually
- payment and reconciliation metadata exist so the wallet can grow into real
  payment UX rather than only developer tooling

## References

- MPP overview: `https://mpp.dev/overview`
- Tempo CLI docs: `https://docs.tempo.xyz/cli`
- Tempo transaction docs: `https://docs.tempo.xyz/protocol/transactions`

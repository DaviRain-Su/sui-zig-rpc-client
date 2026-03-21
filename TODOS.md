# TODOS

## P1 — Define the intent-to-artifact contract before adding more natural-language intents

**What:** Define a typed intermediate representation between natural-language parsing and the existing structured tx/request builders, including validation ownership for the read-only branch and the swap branch.

**Why:** The current plan keeps 3 intents, uses hybrid routing, and allows independent branch rules. Without a written contract here, each branch will keep inventing its own parsing, validation, and lowering semantics, which turns the system into multiple execution brains.

**Pros:**
- Keeps natural-language parsing separate from trusted execution
- Reduces repeated branch-specific logic
- Makes tests and future intent additions much easier to reason about
- Preserves the existing core as the single structured engine

**Cons:**
- Adds upfront design work before adding more intents
- May force some current prototype assumptions to be rewritten

**Context:** The engineering review found that `src/commands.zig`, `src/cli.zig`, and `src/tx_pipeline.zig` already provide a strong structured execution path, while `src/intent_parser.zig` is still a toy parser with mock-heavy behavior and no stable provider-to-engine contract. The main deferred risk is not raw parsing quality; it is the missing typed handoff between “the parser thinks this is the user’s intent” and “the execution core trusts this enough to preview or execute.” Define that contract, its field validation rules, which branch owns which validations, and which failures must be explicit refusals.

**Depends on / blocked by:**
- Depends on keeping the 3-intent MVP scope explicit
- Blocks adding more send-capable intents safely
- Should be resolved before broadening beyond the current hybrid MVP

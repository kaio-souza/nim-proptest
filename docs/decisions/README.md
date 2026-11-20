# Architecture Decision Records

Each file records one decision: its context, what was decided, the consequences, and the evidence that will confirm it. An accepted decision is not edited afterwards; if it changes, a new ADR supersedes it.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-integrated-shrinking-on-choice-sequences.md) | Integrated shrinking over a recorded choice sequence | Proposed |
| [0002](0002-zero-dependencies-runner-agnostic.md) | Zero dependencies; runner-agnostic core with adapters | Proposed |
| [0003](0003-reproducibility-and-failure-database.md) | Seeds for replay and a local failure database | Proposed |
| [0004](0004-evidence-policy.md) | No feature without tests, value tests and benchmarks | Accepted |
| [0005](0005-own-prng-and-stable-hashing.md) | Own versioned PRNG and stable hashing, checked by golden tests | Proposed |
| [0006](0006-failure-identity-and-flaky-detection.md) | Failure signatures, no slippage, flaky detection, multiple failures | Proposed |
| [0007](0007-generator-representation.md) | Closure-free built-in generators; closures only for user combinators | Proposed |
| [0008](0008-deterministic-performance-gates.md) | CI gates on executions and allocations, not timings | Proposed |
| [0009](0009-assertions-inside-forall.md) | `check`/`require` inside `forAll` rewritten to raise; one report to the runner | Proposed |
| [0010](0010-forall-in-syntax.md) | `forAll(x in source)`: one form for types and generators | Accepted |

## Template

```markdown
# ADR-NNNN: Title

- Status: Proposed | Accepted | Superseded by ADR-XXXX
- Date: YYYY-MM-DD
- Requirements: SPEC IDs

## Context
## Decision
## Consequences
## Evidence
```

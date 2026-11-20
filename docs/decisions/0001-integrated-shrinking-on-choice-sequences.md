# ADR-0001: Integrated shrinking over a recorded choice sequence

- Status: Proposed
- Date: 2026-11-19
- Requirements: G1, C1, C7, S1–S5, M3, F1

## Context

There are two established ways to shrink a failing input:

1. **Type-based shrinking**: each type has a shrink function that proposes smaller values. Simple, but every custom generator needs its own shrinker, and `map`/`filter`/`flatMap` lose shrinking or produce values that break the generator's constraints.
2. **Integrated shrinking over choices**: a generator does not draw from an RNG directly; it consumes a **sequence of choices** (integers) from a source that records them. To shrink, the engine shrinks *the recorded sequence* (delete blocks, lower values, sort) and re-runs the generator on it. Whatever the generator builds from a smaller sequence is, by construction, a valid and simpler value.

## Decision

Use integrated shrinking over a recorded choice sequence.

- `Gen[T]` is a proc that reads choices from a `ChoiceSource`. In normal runs the source draws from a seeded RNG and records each draw; during shrinking it replays a candidate sequence.
- Built-in generators are written so that smaller choices produce simpler values (e.g. choice `0` is the integer `0`, a short sequence is a short list).
- The shrinker works only on the sequence: delete spans, zero spans, lower individual choices, sort spans. It knows nothing about types.
- When a candidate sequence runs out, the source returns `0`, so generators always terminate.
- Generation that exceeds the maximum sequence length (RL7) marks the case as an **overrun**: it is invalid, not a failure.
- Shrink passes use binary/exponential search on values and span sizes, and remember sequences already tried (PF6). A candidate is accepted only if it is smaller in shortlex order and fails with the same signature (RL4, RL14, ADR-0006).

## Consequences

- Custom generators, `map`, `filter` and `flatMap` shrink without extra code, and shrunk values always satisfy the generator (S1, S2).
- Shrinking command sequences in stateful tests (M3) is the same algorithm, because commands are generated from choices too.
- The fuzzing bridge (F1) becomes natural: fuzzer bytes are just another choice source.
- Generator authors must follow one rule: draw choices so that "smaller choice → simpler value". This is documented, and built-ins provide the building blocks.
- Shrink quality depends on the passes of the sequence shrinker; reference bugs in the SPEC measure it.

## Evidence

To be provided by the S1 value tests (shrinking through `map`/`filter`) and the shrink-time benchmarks (PF1).

# ADR-0007: Generator representation

- Status: Proposed
- Date: 2026-11-19
- Requirements: G1, G3, G4, C1–C7, PF4, PF5, PF9

## Context

`Gen[T]` could be a closure (`proc(src: var ChoiceSource): T {.closure.}`) or a compile-time construct. Closures are flexible and make combinators trivial, but each one costs a heap allocation when built and an indirect call per value; nested `map`/`filter` chains multiply this. Pure compile-time generators (templates, concepts) are fast but make user-defined combinators and runtime-chosen generators awkward, and heavy macro use slows compilation.

## Decision

Use both, each where it fits:

- **Built-in, type-inferred generators** (`forAll(xs in seq[int])`, derived object generators) are expanded by the `forAll` macro into direct calls to inline procs over the choice source. No closure, no indirect call.
- **User-built generators** (`ints(0, 10).map(...)`, `oneOf(...)`) are values of type `Gen[T]`, a small object wrapping a closure. They are built once per property, not per case.
- Both forms read from the same `ChoiceSource`, so shrinking (ADR-0001) is identical for both.
- The choice buffer lives in the `ChoiceSource`, preallocated with the maximum sequence length (RL7) and reused across cases and shrink attempts: drawing a choice never allocates (PF4).
- Derived generators for object types are generated once per type and reused, to keep compile time bounded (PF9).

## Consequences

- The common case (properties over plain types) has the lowest possible overhead.
- Users write combinators with ordinary closures; the cost is paid only when they use them.
- Two code paths to keep consistent; golden tests (Q7) cover both producing the same values for the same seed.

## Evidence

PF1 benchmarks comparing type-inferred and closure-based generators against the hand-written baseline; allocation counts per case (PF7); compile-time benchmark (PF9).

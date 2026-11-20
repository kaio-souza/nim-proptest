# Roadmap

Updated 2026-11-19. IDs refer to [`SPEC.md`](SPEC.md).

Legend: [x] done · [ ] pending · [~] deferred

## Where we are

**Design phase.** Requirements and initial decisions are written down; no code yet.

## v0.1: smallest useful core

Goal: write a property over built-in types inside `std/unittest`, get a minimal, reproducible counterexample.

Foundations first: the parts that are expensive to change later (PRNG, choice buffer, failure identity, generator representation) are settled here.

- [ ] Own PRNG and stable hashing, with golden tests (RL1, RL2, Q7, ADR-0005)
- [ ] Choice source with a preallocated, reused buffer and bounded length (G1, PF4, RL7, ADR-0001)
- [ ] Built-in generators, expanded without closures; type inference; size control (G2, G3, G7, PF5, ADR-0007)
- [ ] Combinators `map`, `filter`, `flatMap`, `oneOf`, `elements`, `constant` (C1, C2)
- [ ] Integrated shrinking with deterministic results, failure signatures and no slippage (S1–S3, RL4, RL14)
- [ ] Flaky detection; generator errors reported separately (RL3, RL6, ADR-0006)
- [ ] `forAll`, `assume`, failure report (A1–A3)
- [ ] Seed printing, `PROPTEST_SEED`, crash breadcrumbs (R1, R2, R5, RL9)
- [ ] Per-property settings (K1)
- [ ] `std/unittest` integration (I1)
- [ ] Value tests for S1, RL3, RL4; benchmarks with the hand-written baseline (PF1, EV2, EV3)
- [ ] CI: orc/arc × threads (Q1), deterministic gates on shrink executions and allocations (PF7, ADR-0008), sanitizers (Q6)

## v0.2: stateful testing

Goal: replace the planned model test of `circuit_breaker` with this library.

- [ ] Model, commands, preconditions, postconditions (M1, M2)
- [ ] Sequence shrinking (M3) and failures printed as Nim code (M4)
- [ ] Invariants and injectable time (M5, M6)
- [ ] Fresh system and model per sequence, teardown always runs (RL13)
- [ ] `circuit_breaker` model test (its V2/Q5) as the first external user

## v0.3: richer generation and diagnostics

- [ ] Object, case object and distinct derivation (G4)
- [ ] Collections, refs, string alphabets, float options (G5, G6, G9)
- [ ] Edge-case bias (G8)
- [ ] `frequency`, `recursive`, `sized`, `unique` (C3–C6)
- [ ] `classify` and `cover` (D1, D2)
- [ ] Shrink budget and quality targets (S4, S5), efficient shrink passes (PF6)
- [ ] Multiple distinct failures (RL5)
- [ ] Per-case deadline and time budget per property (RL8, PF8)
- [ ] Health checks (RL11)
- [ ] Lazy formatting (PF10), compile-time benchmark (PF9)

## v0.4: workflow

- [ ] Failure database with versioned format and atomic writes, explicit examples (R3, R4, RL12)
- [ ] Stability policy documented and enforced by golden tests (RL15)
- [ ] Environment-driven defaults and validation (K2, K3)
- [ ] `unittest2` module and standalone API (I2, I3)
- [ ] Publish to the Nimble index

## v1.0: acceptance criteria

All P0 and P1 requirements implemented and tested; benchmarks published; CI on Linux, macOS and Windows; public API fully documented; used by at least one external project (`circuit_breaker`).

## After 1.0

- [~] M7 parallel linearizability checking
- [~] RL10 watchdog thread
- [~] F1 fuzzing bridge
- [~] I4 async properties
- [~] PF3 parallel case execution
- [~] Q3 JS backend
- [~] D3 size statistics

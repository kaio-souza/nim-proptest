# Roadmap

Updated 2026-11-19. IDs refer to [`SPEC.md`](SPEC.md).

Legend: [x] done (implemented and tested) · [ ] pending · [~] deferred

## Where we are

**v0.1 implemented and tested, not yet published.** Status per requirement: [`TRACEABILITY.md`](TRACEABILITY.md) (95 requirements, 56 done or partial, all with evidence).

| Evidence | Result |
|---|---|
| Tests | 72, all passing on orc/arc × threads on/off × debug/release |
| Sanitizers | ASan, UBSan and leak checks clean on orc and arc |
| Golden tests | PRNG and hash match the authors' reference C code and the official FNV-1a vectors; generated values pinned for seed 42 |
| Value tests | the reference bugs of SPEC Part IV shrink to their exact minima; multiple bugs and no slippage verified on 20 seeds each (100/100 on 100 seeds) |
| Shrink cost (gate) | 17 to 113 property executions per reference bug (target < 500) |
| Allocation gate | 0 allocations per choice and per generated integer |

The test suite found and fixed two real problems during development: undefined behavior (`countLeadingZeroBits(0)`) that produced out-of-range integers **only in release builds**, and multi-bug detection that depended on luck with the seed (exploration now continues after the first failure).

## v0.1: smallest useful core

Goal: write a property over built-in types inside `std/unittest`, get a minimal, reproducible counterexample.

- [x] Own PRNG and stable hashing, with golden tests (RL1, RL2, Q7, ADR-0005)
- [x] Choice source with a fixed buffer, reused across cases, bounded length (G1, PF4, RL7, ADR-0001)
- [x] Built-in generators, expanded without closures; type inference; size control (G2, G3, G7, PF5, ADR-0007)
- [x] Combinators `map`, `filter`, `flatMap`, `oneOf`, `elements`, `constant`; custom generators as plain procs (C1, C2, C7)
- [x] Integrated shrinking: deterministic, failure signatures, no slippage, merge pass (S1–S3, S5, RL4, RL14, PF6)
- [x] Flaky detection (double re-run); generator errors reported separately (RL3, RL6, ADR-0006)
- [x] Multiple distinct failures, found by exploration and shrinking (RL5)
- [x] `forAll(x in source)`, `forAllResult`, `assume`, failure report, `Defect`s as failures, value printing (A1–A5, I3, ADR-0010)
- [x] `check`/`require` rewriting inside `forAll`, quiet exploration (A6, O1, ADR-0009)
- [x] `--panics:on` detected at compile time with a warning (A7)
- [x] Seed printing, `PROPTEST_SEED`, crash breadcrumbs in `.proptest/last-run` (R1, R2, R5, RL9)
- [x] Per-property settings, environment defaults, validation (K1, K2 partial, K3)
- [x] `std/unittest` integration (I1)
- [x] Unit tests per requirement, value tests, dogfooding (EV1, EV3, Q5)
- [x] Benchmarks with the hand-written baseline, in debug and release (PF1, PF2)
- [x] Deterministic gates on shrink executions and allocations (PF7, ADR-0008)
- [x] Traceability matrix and its check (ADR-0004)
- [x] CI workflows: test matrix, sanitizers, examples, `nim doc`, traceability, gates (Q1, Q4, Q6, Q8)
- [ ] First real CI run on GitHub

## Performance against the initial targets

Measured on an Intel Core i5-10210U laptop (noisy: repeated runs vary by up to 2×), Nim 2.2.4, ORC.

| Metric | Target (release / debug) | Measured (release / debug) | |
|---|---|---|---|
| Drawing one choice | < 5 ns / < 20 ns | 3.6–8.6 ns / 70 ns | release borderline, debug missed |
| Generating an `int` | < 10 ns / < 40 ns | 20–33 ns / 280 ns | missed |
| Per-case overhead incl. an `int` | < 200 ns / < 1 µs | 64 ns / 1.6 µs | release met, debug missed |
| Run of 100 cases, `x in int` | milliseconds (PF2) | 0.006 ms / 0.16 ms | met |
| Run of 100 cases, `xs in seq[int]` | milliseconds (PF2) | 0.16 ms / 1.5 ms | met |
| Shrinking a reference bug | < 500 executions | 17–113 | met |

Missed targets go to v0.3 below. Already done to get here: inlined hot paths, a fixed choice buffer instead of `seq.add`, no 64-bit division in the exploration distribution, constant-time float scaling (from 149 ns to ~55 ns per float).

## v0.2: stateful testing

Goal: replace the planned model test of `circuit_breaker` with this library.

- [ ] Model, commands, preconditions, postconditions (M1, M2)
- [ ] Sequence shrinking (M3) and failures printed as Nim code (M4)
- [ ] Invariants and injectable time (M5, M6)
- [ ] Fresh system and model per sequence, teardown always runs (RL13)
- [ ] `circuit_breaker` model test (its V2/Q5) as the first external user
- [ ] Stateful testing tutorial based on that test (DOC4)

## v0.3: richer generation and diagnostics

- [ ] Object, case object and distinct derivation (G4)
- [ ] Collections, refs, string alphabets, float options (G5, G6, G9)
- [ ] Edge-case bias (G8)
- [ ] `frequency`, `recursive`, `sized`, `unique` (C3–C6)
- [ ] `classify` and `cover` (D1, D2)
- [ ] Time budget for shrinking (S4, rest)
- [ ] Generation speed: meet the `int` and debug-build targets above
- [ ] Per-case deadline and time budget per property (RL8, PF8)
- [ ] Health checks (RL11)
- [ ] Lazy formatting (PF10), compile-time benchmark (PF9)
- [ ] Verbosity levels; statistics and warnings in the report (O2, O4)
- [ ] Writing generators guide and property patterns cookbook (DOC2, DOC3)

## v0.4: workflow

- [ ] Failure database with versioned format and atomic writes, explicit examples (R3, R4, RL12)
- [ ] Stability policy documented and enforced by golden tests (RL15)
- [ ] JSON report for CI (O3)
- [ ] Configuration reference and troubleshooting guide (DOC5, DOC6)
- [ ] Remaining environment variables (K2: `PROPTEST_DEADLINE`, `PROPTEST_VERBOSITY`, `PROPTEST_REPORT`)
- [ ] `unittest2` module (I2)
- [ ] CI on macOS and Windows, Nim devel (Q2)
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

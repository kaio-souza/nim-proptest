# Roadmap

Updated 2026-11-20. IDs refer to [`SPEC.md`](SPEC.md).

Legend: [x] done (implemented and tested) · [ ] pending · [~] deferred

## Where we are

**v0.3 implemented and tested (bug-finding power, coverage, budgets, health checks), not yet published.** v0.2 is tagged and on GitHub; the v0.3 changes have been checked locally on the full CI matrix. Next: v0.4. Status per requirement: [`TRACEABILITY.md`](TRACEABILITY.md) (95 requirements, 72 done or partial, all with evidence).

| Evidence | Result |
|---|---|
| Tests | 107, all passing on orc/arc × threads on/off × debug/release |
| Sanitizers | ASan, UBSan and leak checks clean on orc and arc |
| Golden tests | PRNG and hash match the authors' reference C code and the official FNV-1a vectors; generated values pinned for seed 42 |
| Value tests | the reference bugs of SPEC Part IV shrink to their exact minima, including the stateful queue (4 steps, 20/20 seeds); multiple bugs and no slippage verified on 20 seeds each (100/100 on 100 seeds) |
| Shrink cost (gate) | 9 to 214 property executions per reference bug (target < 500) |
| Bug-finding (gate) | `b_find`, 100 seeds: exact boundary in a range 1 → 68, a bug needing a command to stay away 3 → 97, breaker probe 72 → 80, no row worse (v0.2 → v0.3) |
| Allocation gate | 0 allocations per choice, per generated integer and per stateful sequence; static labels checked by a test |
| External user | `nim-circuit-breaker` model test (its V2/Q5): 1000 sequences, three planted model mistakes found and shrunk |

The test suite found and fixed real problems during development: in v0.3, a local minimum of the shrinker (`-1` was not shrunk to `1` when `0` was a different bug), now handled by a new pass; in v0.2, a leak under LeakSanitizer when a replayed sequence raised (an ARC behavior of Nim 2.2.4 with temporaries passed to a raising call). In v0.1, undefined behavior (`countLeadingZeroBits(0)`) that produced out-of-range integers **only in release builds**, and multi-bug detection that depended on luck with the seed (exploration now continues after the first failure).

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
- [x] First real CI run on GitHub (green)

## Performance against the initial targets

Measured on an Intel Core i5-10210U laptop (noisy: repeated runs vary by up to 2×), Nim 2.2.4, ORC.

| Metric | Target (release / debug) | Measured (release / debug) | |
|---|---|---|---|
| Drawing one choice | < 5 ns / < 20 ns | 3.6–8.6 ns / 70 ns | release borderline, debug missed |
| Generating an `int` | < 10 ns / < 40 ns | 20–33 ns / 280 ns | missed |
| Per-case overhead incl. an `int` | < 200 ns / < 1 µs | 64 ns (v0.2) → ~120 ns (v0.3) / 1.6 µs | release met, debug missed |
| Run of 100 cases, `x in int` | milliseconds (PF2) | 0.006 → 0.012 ms / 0.16 ms | met |
| Run of 100 cases, `xs in seq[int]` | milliseconds (PF2) | 0.19 → 0.24 ms / 1.5 ms | met |
| Shrinking a reference bug | < 500 executions | 9–214 | met |
| One stateful sequence, 50 steps max | none set | ~0.6 µs (v0.2) → ~0.9 µs (v0.3), 0 allocations | |

v0.3 costs (minimum of 400 runs, against v0.2 built from its tag): about 6 µs more per property and 15–25% more for collection-heavy cases. They come from health checks (input hashes, sampled generation timing), boundary hints on every integer draw (one more PRNG call, a hinted value in 1 draw of 4) and stateful statistics and swarm choices. Every target that was met is still met; the per-case budget has less room left.

Missed targets go to v0.4 below. Already done to get here: inlined hot paths, a fixed choice buffer instead of `seq.add`, no 64-bit division in the exploration distribution, constant-time float scaling (from 149 ns to ~55 ns per float).

## v0.2: stateful testing

Goal: replace the planned model test of `circuit_breaker` with this library. Design: [ADR-0011](decisions/0011-stateful-testing.md).

- [x] Spike: `result` binding, `typeof` of argument sources, enabled-command draw (ADR-0011 questions settled)
- [x] Spans in `ChoiceSource` and the `deleteSpans` pass, also used by collections (S2, PF6)
- [x] Model, commands, preconditions, postconditions (M1, M2); `checkStateMachine`, `stateMachineResult`, `maxSteps`
- [x] Sequence shrinking (M3) and failures printed as Nim code (M4): `replayCommands`, `showCode`
- [x] Invariants and injectable time (M5, M6)
- [x] Fresh system and model per sequence, teardown always runs (RL13)
- [x] Value test (3 pushes + 1 pop → 4 steps) and shrink/allocation gates
- [x] `circuit_breaker` model test (its V2/Q5) as the first external user
- [x] Stateful testing tutorial (DOC4): [`STATEFUL.md`](STATEFUL.md), example run in CI
- [ ] First CI run of v0.2 on GitHub (push), including `nim-circuit-breaker` CI once proptest v0.2 is reachable from it

Learned in v0.2, for v0.3: uniform integers rarely hit a specific boundary (a timeout of exactly 1000 ms in `0 .. 2000`). The tutorial adds boundaries by hand with `oneOf(..., elements([...]))`; boundary hints and swarm testing (v0.3, ADR-0012) should make that unnecessary.

## v0.3: find more bugs, and show what was tested

Reordered after v0.2. Two weaknesses showed up while testing real code: a bug at an exact domain boundary (a timeout of exactly 1000 ms) was rarely hit by uniform integers, and nothing in the report said so. The cap of the circuit breaker's backoff, too, was only reached once the clock range was widened by hand. More generator types would not have helped. Knowing what was generated, and steering exploration toward boundaries, would have. Design: [ADR-0012](decisions/0012-bug-finding-power.md) (proposed).

Order of work (each step lands with tests, a value test and, where it touches the hot path, a gate):

1. **Bug-finding benchmark** (`benchmarks/b_find.nim`): planted bugs (including the v0.2 ones: breaker boundary, backoff cap, queue) run over N fixed seeds; the gate is the detection rate and the median number of cases to the first failure. Every later step must move these numbers, not just pass tests.
2. **`classify` / `cover` (D1, D2)**, plus automatic statistics for state machines: how often each command ran, sequence lengths, and how often each command was disabled by its precondition. Printed in the report (O4); static labels do not allocate (PF10).
3. **Edge-case bias, complete (G8)**: integers already hit 0, 1 and the limits. Add -1, floats (`-0.0`, subnormals, `NaN`, `Inf`), empty and single-element collections, with a configurable probability. **Boundary hints**: `ints(0, 2000, near = [openFor])` explores `v-1, v, v+1` around given values, so the tutorial's `oneOf(..., elements([...]))` workaround goes away.
4. **Swarm testing for state machines**: each sequence randomly disables a subset of commands, so long runs of a few commands (five probe failures in a row to reach the backoff cap) become likely. Shrinking is unaffected: the subset is part of the choice sequence.
5. **Per-case deadline and time budgets (RL8, PF8, S4 rest)**: a case slower than the deadline is a failure and is shrunk; the run and the shrink stop gracefully at their budgets and say so. A case that never returns needs a watchdog (RL10, after 1.0); until then it is replayable from `.proptest/last-run`.
6. **Health checks (RL11)** and **verbosity levels (O2)**: a filter that rejects almost everything, generation dominating the run time, data constantly hitting size limits.
7. **Docs**: property patterns cookbook (DOC3), and a section of the tutorial on reading coverage.

- [x] Bug-finding benchmark with detection-rate gate (`benchmarks/b_find.nim`, in `nimble gate`). Baseline before v0.3, 20 seeds each: reverse, midpoint overflow, boundary 100, stateful queue 20/20; breaker probe at exactly 1000 ms 16/20; **exact 1000 in 0..2000 0/20; breaker backoff cap 0/20**
- [x] Median cases to the first failure in `b_find` (`PropertyResult.firstFailureAt`; reports say "falsified at case N")
- [x] `classify`, `cover`, `label`; stateful statistics: commands ran, blocked by preconditions, sequence lengths (D1, D2, O4, PF10)
- [x] Edge-case bias for integers, floats and collections, with `edgeBias`; boundary hints with `ints(..., near = [...])` (G8)
- [x] Swarm testing for state machines, hybrid: half of the sequences (M2)
- [x] Per-case deadline; time budgets for runs and shrinking (RL8 partial: a case that never returns needs RL10; PF8, S4)
- [x] Health checks: data too large, few distinct inputs, slow generation, `suppress`; verbosity levels (RL11, O2)
- [x] Property patterns cookbook (DOC3), `examples/patterns.nim` in CI; tutorial updated
- [x] Experiment: mined constants, **adopted**: the body's literals and constants get half of the hinted draws, the file's literals the rest (ADR-0012)

Measured on `b_find` with 100 seeds, before v0.3 → v0.3: exact 1000 in `0..2000` 1 → 68; 12 increments without reset 3 → 97; breaker probe at exactly 1000 ms 72 → 80; stateful queue, reverse, overflow, boundary 100: 100 → 100; breaker backoff cap 0 → 3. Rows move by up to ~10 points between equivalent implementations (a different random stream), so only larger changes are read as effects.

What did **not** work, recorded for later: plain swarm (every sequence) lowered the breaker boundary row (72 → 57); the hybrid keeps both gains. The breaker's backoff cap (five reopenings, each after the right wait) stays out of reach of random sequences: a "deep state". Targeted exploration (maximize a value such as `model.level`) is the known technique for it, candidate for after v0.4.

Decided in ADR-0012: deadline off by default (`PROPTEST_DEADLINE` for CI); `cover` in state machines counts per sequence.

## v0.4: richer generation

- [ ] Object, case object and distinct derivation (G4)
- [ ] Collections, refs, string alphabets, float options (G5, G6, G9)
- [ ] `frequency`, `recursive`, `sized`, `unique` (C3–C6)
- [ ] Generation speed: meet the `int` and debug-build targets above
- [ ] Compile-time benchmark (PF9), with derived generators in it
- [ ] Writing generators guide (DOC2)

## v0.5: workflow

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

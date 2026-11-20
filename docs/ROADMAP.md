# Roadmap

Updated 2026-11-20. IDs refer to [`SPEC.md`](SPEC.md).

Legend: [x] done (implemented and tested) · [ ] pending · [~] deferred

Work is planned by **theme and priority, not by version**. Most themes take a day or two, so a version per theme would only add ceremony. A release (a tag and a CHANGELOG heading) is cut when it is worth one: a user needs a fixed point, or a set of changes should land together (see [Generation changes](#4-generation-changes-together)). Last tag: `v0.2.0`; everything after it is under *Unreleased* in the [CHANGELOG](../CHANGELOG.md).

## Where we are

**Usable, not yet in the Nimble index.** Built-in types, your own types with no generator code, stateful tests, a failure database, coverage statistics and boundary-seeking exploration all work and are tested. Everything is green on GitHub CI on Linux, macOS and Windows, with Nim devel as an allowed failure. Status per requirement: [`TRACEABILITY.md`](TRACEABILITY.md) (95 requirements, 82 done or partial, all with evidence).

| Evidence | Result |
|---|---|
| Tests | 138, all passing on orc/arc × threads on/off × debug/release, on Linux, macOS and Windows |
| Sanitizers | ASan, UBSan and leak checks clean on orc and arc |
| Golden tests | PRNG and hash match the authors' reference C code and the official FNV-1a vectors; generated values pinned for seed 42 |
| Value tests | the reference bugs of SPEC Part IV shrink to their exact minima, including the stateful queue (4 steps, 20/20 seeds); multiple bugs and no slippage verified on 20 seeds each (100/100 on 100 seeds) |
| Shrink cost (gate) | 9 to 214 property executions per reference bug (target < 500) |
| Bug-finding (gate) | `b_find`, 100 seeds: exact boundary in a range 1 → 68, a bug needing a command to stay away 3 → 97, breaker probe 72 → 80, no row worse (before → after the bug-finding work) |
| Allocation gate | 0 allocations per choice, per generated integer and per stateful sequence; static labels checked by a test |
| Compile time | 50 properties over derived types build as fast as over `int` (~3.5 s, `b_compile`) |
| External user | `nim-circuit-breaker` model test (its V2/Q5): 1000 sequences, three planted model mistakes found and shrunk |

The test suite found and fixed real problems during development:

- a local minimum of the shrinker (`-1` was not shrunk to `1` when `0` was a different bug), now handled by a new pass;
- a leak under LeakSanitizer when a replayed sequence raised (an ARC behavior of Nim 2.2.4 with temporaries passed to a raising call);
- undefined behavior (`countLeadingZeroBits(0)`) that produced out-of-range integers **only in release builds**;
- multi-bug detection that depended on luck with the seed (exploration now continues after the first failure);
- `example(...)` that did not compile next to `classify`/`cover`/`label`, because the body was rewritten in place (also made the failure database key depend on generated names).

## Next, by priority

What keeps a new user from adopting the library, most blocking first.

### 1. Their platform and test runner

- [x] CI on macOS and Windows; Nim devel as an allowed failure (Q2). Nim comes from the official downloads, no third-party actions. It found a test helper that used POSIX shell syntax, and the first CI run of the derived generators under the sanitizers found a leak with tables (a Nim 2.2.4 ARC bug, fixed with named locals)
- [ ] `unittest2` adapter (I2)
- [ ] JSON report for CI tools, `PROPTEST_REPORT` (O3, K2)

### 2. Learning it alone

- [ ] Configuration reference: every setting and environment variable in one place (DOC5)
- [ ] Troubleshooting guide: what to do when something looks wrong (DOC6)

### 3. Trust over time

- [ ] Stability policy written down: what may change between versions, enforced by golden tests (RL15). The wait for the Nimble index (below) starts here.

### 4. Generation changes, together

Anything that alters the values generated for a seed. They land **together**, in one release, so that old seeds stop replaying once and not after every change, and so the stability wait is not restarted by each of them.

- [ ] `sized`, `unique`, `sortedSeq` (C5, C6)
- [ ] Generation speed: meet the `int` and debug-build targets below
- [ ] Targeted exploration for deep states (the breaker's backoff cap, ADR-0012), if `b_find` shows a gain
- [ ] Any pending change to the exploration distribution

## Done, by theme

### Core: properties over built-in types

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

### Stateful testing

Goal: replace the planned model test of `circuit_breaker` with this library. Design: [ADR-0011](decisions/0011-stateful-testing.md).

- [x] Spans in `ChoiceSource` and the `deleteSpans` pass, also used by collections (S2, PF6)
- [x] Model, commands, preconditions, postconditions (M1, M2); `checkStateMachine`, `stateMachineResult`, `maxSteps`
- [x] Sequence shrinking (M3) and failures printed as Nim code (M4): `replayCommands`, `showCode`
- [x] Invariants and injectable time (M5, M6)
- [x] Fresh system and model per sequence, teardown always runs (RL13)
- [x] Value test (3 pushes + 1 pop → 4 steps) and shrink/allocation gates
- [x] `circuit_breaker` model test (its V2/Q5) as the first external user
- [x] Stateful testing tutorial (DOC4): [`STATEFUL.md`](STATEFUL.md), example run in CI

On `ubuntu-latest` kernels (`vm.mmap_rnd_bits=32`) the ASan of the gcc in `nimlang/nim:2.2.4` sometimes looped forever on `AddressSanitizer:DEADLYSIGNAL`; the sanitizer jobs lower it to 28 on the runner and run the image with `docker run`, one suite per job.

Learned here: uniform integers rarely hit a specific boundary (a timeout of exactly 1000 ms in `0 .. 2000`), and nothing in the report said so. That set the next theme.

### Find more bugs, and show what was tested

Knowing what was generated, and steering exploration toward boundaries, mattered more than more generator types. Design: [ADR-0012](decisions/0012-bug-finding-power.md).

- [x] Bug-finding benchmark with detection-rate gate (`benchmarks/b_find.nim`, in `nimble gate`); median cases to the first failure (`PropertyResult.firstFailureAt`)
- [x] `classify`, `cover`, `label`; stateful statistics: commands ran, blocked by preconditions, sequence lengths (D1, D2, O4, PF10)
- [x] Edge-case bias for integers, floats and collections, with `edgeBias`; boundary hints with `ints(..., near = [...])` (G8)
- [x] Swarm testing for state machines, hybrid: half of the sequences (M2)
- [x] Per-case deadline; time budgets for runs and shrinking (RL8 partial: a case that never returns needs RL10; PF8, S4)
- [x] Health checks: data too large, few distinct inputs, slow generation, `suppress`; verbosity levels (RL11, O2)
- [x] Property patterns cookbook (DOC3), `examples/patterns.nim` in CI
- [x] Mined constants, **adopted**: the body's literals and constants get half of the hinted draws, the file's literals the rest

Measured on `b_find` with 100 seeds, before → after: exact 1000 in `0..2000` 1 → 68; 12 increments without reset 3 → 97; breaker probe at exactly 1000 ms 72 → 80; stateful queue, reverse, overflow, boundary 100: 100 → 100; breaker backoff cap 0 → 3. Rows move by up to ~10 points between equivalent implementations (a different random stream), so only larger changes are read as effects.

What did **not** work: plain swarm (every sequence) lowered the breaker boundary row (72 → 57); the hybrid keeps both gains. The breaker's backoff cap (five reopenings, each after the right wait) stays out of reach of random sequences: a "deep state". Targeted exploration is the known technique (priority 4 above).

### Their own types, and bugs that stay found

- [x] Object, case object and `distinct` derivation, with no code to write (G4); private fields of other modules included (ADR-0013)
- [x] `ref` objects and recursive types with a depth bound; `recursive` and `frequency` for trees and weighted choices (G5, C4, C3)
- [x] `Table`, `OrderedTable`, `HashSet` (G5); string alphabets: alphanumeric, identifiers, valid UTF-8 (G6)
- [x] Failure database: past failures replayed first on the next run, versioned format, atomic writes (R3, RL12); explicit examples always run (R4) (ADR-0014)
- [x] Compile-time benchmark with derived generators (PF9)
- [x] Writing generators guide (DOC2), `examples/generators.nim` in CI

New API only: the shrink and detection baselines are identical, number for number. One narrow exception, a fix: boundary hints no longer pick up internal label slot numbers, which changes the values only of properties with three or more `classify`/`cover`/`label` calls (CHANGELOG).

Found while building it: case objects whose discriminant is a `range` type cannot be derived with Nim 2.2.4 (assigning it crashes the compiler, and it has no address): a clear compile error says to use an enum or write `arbitrary`. The failure database is off by default in the library's own tests and benchmarks (`-d:proptestDb=off`), which need repeatable runs.

## Performance against the initial targets

Measured on an Intel Core i5-10210U laptop (noisy: repeated runs vary by up to 2×), Nim 2.2.4, ORC.

| Metric | Target (release / debug) | Measured (release / debug) | |
|---|---|---|---|
| Drawing one choice | < 5 ns / < 20 ns | 3.6–8.6 ns / 70 ns | release borderline, debug missed |
| Generating an `int` | < 10 ns / < 40 ns | 20–33 ns / 280 ns | missed |
| Per-case overhead incl. an `int` | < 200 ns / < 1 µs | 64 ns → ~120 ns / 1.6 µs | release met, debug missed |
| Run of 100 cases, `x in int` | milliseconds (PF2) | 0.006 → 0.012 ms / 0.16 ms | met |
| Run of 100 cases, `xs in seq[int]` | milliseconds (PF2) | 0.19 → 0.24 ms / 1.5 ms | met |
| Shrinking a reference bug | < 500 executions | 9–214 | met |
| One stateful sequence, 50 steps max | none set | ~0.6 µs → ~0.9 µs, 0 allocations | |

Arrows: before → after the bug-finding work (minimum of 400 runs). It costs about 6 µs more per property and 15–25% more for collection-heavy cases: health checks (input hashes, sampled generation timing), boundary hints on every integer draw (one more PRNG call, a hinted value in 1 draw of 4) and stateful statistics and swarm choices. Every target that was met is still met; the per-case budget has less room left.

Missed targets are in priority 4 above (they change generated values). Already done to get here: inlined hot paths, a fixed choice buffer instead of `seq.add`, no 64-bit division in the exploration distribution, constant-time float scaling (from 149 ns to ~55 ns per float).

## Publication in the Nimble index

- [~] **On hold** until stability is shown (decided 2026-11-20). Proposed criteria, by time and use rather than by version count: the stability policy written down and the generation changes landed; then a few weeks with no breaking API change and no generation change; used in at least two more of the author's projects in that time with no library bug found; CI green on Linux, macOS and Windows (Q2). Until then, install from GitHub.

## 1.0: acceptance criteria

All P0 and P1 requirements implemented and tested; benchmarks published; CI on Linux, macOS and Windows; public API fully documented; used by at least one external project (`circuit_breaker`).

## After 1.0

- [~] M7 parallel linearizability checking
- [~] RL10 watchdog thread
- [~] F1 fuzzing bridge
- [~] I4 async properties
- [~] PF3 parallel case execution
- [~] Q3 JS backend
- [~] D3 size statistics

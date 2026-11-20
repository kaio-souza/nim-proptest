# Roadmap

Updated 2026-11-20. IDs refer to [`SPEC.md`](SPEC.md).

Legend: [x] done (implemented and tested) · [ ] pending · [~] deferred

Work is planned by **theme and priority, not by version**. Most themes take a day or two, so a version per theme would only add ceremony. A release (a tag and a CHANGELOG heading) is cut when it is worth one: a user needs a fixed point, or a set of changes should land together (see [Generation changes](#4-generation-changes-together)). Last tag: `v0.2.0`; everything after it is under *Unreleased* in the [CHANGELOG](../CHANGELOG.md).

## Where we are

**Usable, not yet in the Nimble index.** Built-in types, your own types with no generator code, stateful tests, a failure database, coverage statistics and boundary-seeking exploration all work and are tested. Everything is green on GitHub CI on Linux, macOS and Windows, with Nim devel as an allowed failure. Status per requirement: [`TRACEABILITY.md`](TRACEABILITY.md) (97 requirements, 91 done or partial, all with evidence).

| Evidence | Result |
|---|---|
| Tests | 158, all passing on orc/arc × threads on/off × debug/release, on Linux, macOS and Windows |
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
- [x] `unittest2` support (I2): no module needed, `forAll` resolves `checkpoint`/`fail` at the call site (ADR-0002, amended); tested in CI with unittest2 0.3.0
- [x] JSON report for CI tools, `PROPTEST_REPORT` or the `report` setting (O3, K2): one JSON Lines entry per property, appended, versioned by `format`

### 2. Learning it alone

- [x] Configuration reference: every setting and environment variable in one place, with recipes and trade-offs (DOC5): [`CONFIGURATION.md`](CONFIGURATION.md)
- [x] Troubleshooting guide: from the message you see to its cause and fix, with real reports (DOC6): [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md). `scripts/check_docs.nim` (in `nimble trace`) keeps both in step with the code: every setting, environment variable and define documented, every heading link valid.

Learned while writing them: in `-d:release`, failures other than `check` lose their line (no stack trace), so two bugs of the same exception type are reported as one, and `--stackTrace:on` alone is not enough (it needs `--lineTrace:on`). And a property that discards every case never grows its sizes, so an `assume` on the length of a collection gives up with 0 passing cases.

- [x] Compile-time warning when failures cannot be located (A8): built without `stackTrace` and `lineTrace` (`-d:release`, `-d:danger`), failures other than `check` are told apart by exception type only, so two bugs of the same type are reported as one. Like the `--panics:on` warning (A7), it says so at compile time and suggests `--stackTrace:on --lineTrace:on`; `-d:proptestTraceWarning=false` silences it (the library's own suite does, since its failures go through `check`). No generated value changes.

### 3. Trust over time

- [x] Stability policy written down: what may change between versions, enforced by golden tests (RL15): [`STABILITY.md`](STABILITY.md), [ADR-0015](decisions/0015-stability-policy.md). Generation changes only in minor releases; a golden snapshot of 51 properties through the whole pipeline (seed derivation, sizes, edge bias, mined constants, derived types, combinators, a state machine, shrinking, the failure database file) runs on every CI job. The wait for the Nimble index (below) starts here, on 2026-11-20.

### 4. Generation changes, together

Anything that alters the values generated for a seed. They land **together**, in one release, so that old seeds stop replaying once and not after every change, and so the stability wait is not restarted by each of them. All of them are in the CHANGELOG under **Generation changes**; the golden snapshot and the shrink and detection baselines were regenerated once, for the whole batch.

- [x] `sized`, `resize` (C5): the size is recorded as a choice, so shrinking and replay see the size a case was generated with, and shrinking can lower it
- [x] `uniqueSeqs`, `sortedSeqs` (C6)
- [x] Generation speed: one zigzag choice per signed integer instead of sign + magnitude; one PRNG call for most magnitudes; choice buffers that grow on demand instead of 64 KB per property; no stack traces or runtime checks in the hot path, whose indices are checked by hand. Debug builds gain the most (a case of `x in int`: 1.13 → 0.70 µs, now within its target); the targets that assumed a uniform draw were recalibrated ([below](#performance-against-the-targets))
- [x] Targeted exploration (D4, [ADR-0016](decisions/0016-targeted-exploration.md)): `target(score, name)`; the breaker's backoff cap goes from 3 to 20 of 100 seeds
- [x] Sizes grow with discarded cases too: `assume(xs.len > 30 and ...)` went from giving up with 0 passing cases to 100 passing cases with about 200 discards
- [ ] Any pending change to the exploration distribution: none known

Tried and not adopted: compiling the hot path with `-O2` inside debug builds (`localPassC`) made an `int` 3× faster in debug, but mixing optimized and unoptimized C files made UndefinedBehaviorSanitizer report null loads inside the Nim runtime, which a global `-O2` does not; unexplained, so not shipped.

Found on the way: in a template, `classify`/`label`/`target` arrived as bound symbols and were not rewritten, and a command named like an existing proc (`reset`) was rejected by `stateMachine`; both fixed.

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

### Cases that never return

A case that never returns used to hang the whole test program; in CI, until the job's time limit, with no clue. Design: [ADR-0017](decisions/0017-watchdog.md).

- [x] Watchdog thread (RL10, moved here from after 1.0): after `hangTimeout` (off by default; `PROPTEST_HANG_TIMEOUT`, recommended in CI) it reports the property, what was running, the choices and the replay command, saves the case in the failure database and ends the process with exit code 1; a `hung` line goes to the JSON report
- [x] The next run replays the hung case first with its inputs recorded, so a case that still hangs is reported with `x = 42` (or the stateful steps, the last one being the step that does not return)
- [x] Cost: one atomic increment per case; needs `--threads:on` (Nim 2's default)

Not done: shrinking a hang. It would need one child process per shrink step, each still-hanging step costing a full timeout (ADR-0017).

## Performance against the targets

Measured on an Intel Core i5-10210U laptop, Nim 2.2.4, ORC. The machine is noisy (repeated runs vary by up to 2×), so the numbers come from A/B runs: the previous and the current code alternated 15 times, pinned to one core, minimum kept.

| Metric | Target (release / debug) | Before → after the generation batch (release / debug) | |
|---|---|---|---|
| Drawing one choice | < 5 ns / < 50 ns | 4.2 → 3.2 ns / 78 → 41 ns | met |
| Generating an `int` | < 30 ns / < 150 ns | 24 → 23 ns / 230 → 101 ns | met |
| Generating a `float` | none set | 43 → 39 ns / 452 → 253 ns | |
| Per-case overhead incl. an `int` | < 200 ns / < 1 µs | 130 → 117 ns / 1134 → 705 ns | met (debug was missed before) |
| Run of 100 cases, `x in int` | milliseconds (PF2) | 0.012 ms / 0.07 ms | met |
| A `seq[int]` at size 50 | none set | 1.64 → 1.55 µs / 13.3 → 9.1 µs | |
| Shrinking a reference bug | < 500 executions | 9–236 (total 685 → 644) | met |

Targets calibrated on 2026-11-20 (SPEC, section 16): the first ones (an `int` < 10 / < 40 ns, a choice < 20 ns in debug) assumed a uniform draw. A uniform 64-bit draw costs about 3 ns; the distribution that finds boundary bugs (edge values, sizes, hints) costs about 20 ns in release. Debug builds keep Nim's checks in the caller's code; inside the library they are now off on the hot path.

## Publication in the Nimble index

- [~] **On hold** until stability is shown (decided 2026-11-20). Proposed criteria, by time and use rather than by version count: the stability policy written down and the generation changes landed; then a few weeks with no breaking API change and no generation change; used in at least two more of the author's projects in that time with no library bug found; CI green on Linux, macOS and Windows (Q2). Until then, install from GitHub.

## 1.0: acceptance criteria

All P0 and P1 requirements implemented and tested; benchmarks published; CI on Linux, macOS and Windows; public API fully documented; used by at least one external project (`circuit_breaker`).

## After 1.0

- [~] M7 parallel linearizability checking
- [~] F1 fuzzing bridge
- [~] I4 async properties
- [~] PF3 parallel case execution
- [~] Q3 JS backend
- [~] D3 size statistics
- [~] Capture what the property body prints during the final re-run and show it inside the report, delimited (was part of O1; needs redirecting stdout/stderr at the file-descriptor level on every platform, while the guide already steers output into `classify`, `label` and `check`)

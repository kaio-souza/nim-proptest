# Requirements specification

`proptest` is a property-based testing library for the Nim programming language, distributed as a Nimble package. Each requirement has an ID used in test names, benchmarks and ADRs; its status and evidence are in [`TRACEABILITY.md`](TRACEABILITY.md). Priorities: **P0** essential, **P1** expected from a mature library.

- Rationale for the main choices: [`decisions/`](decisions/README.md).

---

# Part I: Product

## 1. Problem

Example-based tests only check the cases their author thought of. Property-based testing (PBT) states a rule that must hold for *every* input ("decoding an encoded value returns the original", "the breaker never runs more than `maxProbes` probes"), generates hundreds of inputs, and when the rule breaks, **shrinks** the failing input to the smallest one that still fails.

As of 2026-11-19 the Nim package index (3 012 packages) has no property-based testing library. Fuzzers exist, but they target crash discovery in C/C++/Nim binaries, not readable properties inside a unit test suite. Library authors in Nim either hand-roll random loops without shrinking or go without.

## 2. Goals

1. Writing a property must be as easy as writing a unit test: one macro, typed variables, generators inferred from types.
2. Every failure is reported as a **minimal**, **reproducible** counterexample.
3. **Stateful (model-based) testing** is a first-class feature, not an add-on: random command sequences run against the real system and a reference model, shrunk to the shortest failing sequence.
4. Zero dependencies outside the standard library; works with `std/unittest`, `unittest2` or standalone.
5. Proven with the same evidence policy as its first consumer, `circuit_breaker` (tests per requirement, value tests, benchmarks).

## 3. Non-goals

- Coverage-guided fuzzing.
- Formal verification or symbolic execution.
- A new test runner. The library plugs into existing runners.
- Mutation testing.

## 4. Target users

| User | Typical property |
|---|---|
| Library authors | round-trips (`decode(encode(x)) == x`), invariants of data structures |
| Parser and serializer authors | "never crashes on any input", "pretty-print then parse is identity" |
| Authors of stateful components (caches, breakers, queues, state machines) | model-based tests of command sequences |
| Application developers | business rules over generated domain objects |

---

# Part II: Requirements

## 5. Generators (G)

| ID | Pri | Requirement |
|----|-----|-------------|
| G1 | P0 | `Gen[T]` type: a value that produces `T` from a source of random choices. |
| G2 | P0 | Built-in generators for `bool`, all integer and float types, `char`, `string`, `enum`, `range`, `seq[T]`, `array[N, T]`, `set[T]`, `tuple`, `Option[T]`. |
| G3 | P0 | Generators **inferred from types**: `forAll(xs in seq[int])` needs no explicit generator. |
| G4 | P1 | Automatic generators for `object` types (including case objects) and `distinct` types, derived by a macro. |
| G5 | P1 | `Table`, `OrderedTable`, `HashSet`, `ref` objects with a recursion depth limit. |
| G6 | P1 | Strings by alphabet: ASCII, printable, alphanumeric, full Unicode (valid UTF-8), custom charset. |
| G7 | P0 | **Size control**: generated values start small and grow over the run; collections respect a maximum size. |
| G8 | P1 | **Edge-case bias**: integers hit `0`, `-1`, `1`, `low`, `high`; floats hit `0.0`, `-0.0`, `NaN`, `Inf`, subnormals; collections hit empty and single-element cases, with a configurable probability. |
| G9 | P1 | Floats: option to exclude `NaN`/`Inf`, and bounded ranges. |

## 6. Combinators (C)

| ID | Pri | Requirement |
|----|-----|-------------|
| C1 | P0 | `map`, `filter` (with a retry limit and a clear error when the filter rejects too much), `flatMap`. |
| C2 | P0 | `oneOf` (choose among generators), `elements` (choose among values), `constant`. |
| C3 | P1 | `frequency` (weighted choice). |
| C4 | P1 | `recursive` for tree-shaped data with a depth bound. |
| C5 | P1 | `sized` (access the current size), `resize`. |
| C6 | P1 | Collections of distinct values and sorted collections: `uniqueSeqs`, `sortedSeqs`. |
| C7 | P1 | Custom generators written as ordinary procs over the choice source, without implementing a shrinker. |

## 7. Shrinking (S)

| ID | Pri | Requirement |
|----|-----|-------------|
| S1 | P0 | **Integrated shrinking**: every generator, including those built with `map`, `filter` and `flatMap`, shrinks automatically. Users never write a shrinker ([ADR-0001](decisions/0001-integrated-shrinking-on-choice-sequences.md)). |
| S2 | P0 | Shrunk values always satisfy the generator's constraints (a filtered generator never shrinks to a rejected value). |
| S3 | P0 | Shrinking is deterministic for a given seed. |
| S4 | P1 | Shrinking budget: maximum steps and maximum time, configurable; the best counterexample found so far is reported when the budget runs out. |
| S5 | P1 | Quality targets, verified by value tests: integers shrink toward 0, collections toward fewer and simpler elements, strings toward shorter and lower code points. |

## 8. Reproducibility (R)

| ID | Pri | Requirement |
|----|-----|-------------|
| R1 | P0 | Every failure prints the seed and a one-line command to replay it. |
| R2 | P0 | `PROPTEST_SEED` environment variable (and a config field) fixes the seed for a run. |
| R3 | P1 | **Failure database**: shrunk counterexamples are saved under `.proptest/` and replayed first on the next run, so a fixed bug is re-checked immediately ([ADR-0003](decisions/0003-reproducibility-and-failure-database.md)). |
| R4 | P1 | Explicit examples (`example(...)`) always run before random cases, to pin known regressions. |
| R5 | P0 | No global mutable state: two properties never influence each other's randomness. |

## 9. Properties and assertions (A)

| ID | Pri | Requirement |
|----|-----|-------------|
| A1 | P0 | `forAll(a in T, b in gen, ...)`: each variable comes from a type or a `Gen[T]`; the body runs once per generated case; a raised exception or failed `check` is a failure. |
| A2 | P0 | `assume(cond)` discards a case; a run fails with a clear message when too many cases are discarded. |
| A3 | P0 | Failure report: property name, minimal counterexample with variable names, the original error and stack trace, number of cases run and shrink steps. |
| A4 | P1 | `Defect`s count as failures (they are what PBT is meant to find), with an option to let them propagate. |
| A5 | P1 | Values are printed with `$` when available, falling back to a structural representation. |
| A6 | P0 | **Assertions inside `forAll`**: `check` and `require` from `std/unittest`/`unittest2` do not raise on failure; inside a `forAll` body they are rewritten so a failure aborts the current case silently and is seen by the engine. The host runner is told about the failure once, with the final report ([ADR-0009](decisions/0009-assertions-inside-forall.md)). |
| A7 | P1 | **`--panics:on`**: `Defect`s cannot be caught in this mode, so the process stops at the first failing case. This is detected at compile time, documented, and the crash breadcrumbs (RL9) allow replay; shrinking requires `--panics:off`. |
| A8 | P1 | **Builds that cannot locate failures**: without stack and line traces (`-d:release`, `-d:danger`) failures other than `check` are told apart by exception type only (RL4), so two bugs of the same type look like one. This is detected at compile time with a warning that names the fix; `-d:proptestTraceWarning=false` silences it. |

## 10. Stateful / model-based testing (M)

| ID | Pri | Requirement |
|----|-----|-------------|
| M1 | P0 | Define a **model** (reference implementation), the **system under test**, and **commands** with preconditions, a generator for their arguments, an execution step on both, and a postcondition comparing results. |
| M2 | P0 | Random command sequences, with preconditions respected during generation and shrinking. |
| M3 | P0 | Failing sequences shrink to the shortest sequence and simplest arguments that still fail. |
| M4 | P0 | The failure report prints the sequence as runnable Nim code, ready to paste as a regression test. |
| M5 | P1 | Invariants checked after every command. |
| M6 | P1 | Injectable time and side effects in the model (e.g. advancing a fake clock is a command). |

## 11. Statistics and coverage (D)

| ID | Pri | Requirement |
|----|-----|-------------|
| D1 | P1 | `classify` / `label`: tag cases and print the distribution at the end of the run. |
| D2 | P1 | `cover(percent, cond, label)`: fail the property when a required class of inputs was generated too rarely. |
| D4 | P1 | **Targeted exploration**: `target(score, name)` in a property or state machine steers part of the exploration toward cases with higher scores, to reach deep states that random cases rarely reach; the best score per name is reported ([ADR-0016](decisions/0016-targeted-exploration.md)). |

## 11a. Output and reporting (O)

| ID | Pri | Requirement |
|----|-----|-------------|
| O1 | P0 | **Quiet exploration**: the library prints nothing per case or per shrink step by default; only the final report. Output written by the property body itself is not captured: it appears once per execution, so the documentation steers it into `classify`/`label` and the `check` message instead. |
| O2 | P1 | Verbosity levels: `quiet` (failures only), `normal` (default), `verbose` (every case), `debug` (every shrink step). |
| O3 | P1 | Machine-readable report (JSON) for CI tooling, enabled by configuration or environment variable. |
| O4 | P1 | The report includes the statistics (D1), coverage results (D2) and health-check warnings (RL11). |

## 12. Configuration (K)

| ID | Pri | Requirement |
|----|-----|-------------|
| K1 | P0 | Per-property settings: number of cases, maximum size, maximum discard ratio, shrink budget, seed. |
| K2 | P1 | Global defaults through environment variables, so CI can run more cases than local development (e.g. `PROPTEST_CASES=10000`). |
| K3 | P1 | Validation of settings with clear errors. |

Environment variables and their defaults: [`CONFIGURATION.md`](CONFIGURATION.md).

## 13. Integration (I)

| ID | Pri | Requirement |
|----|-----|-------------|
| I1 | P0 | Works inside `std/unittest` (`test` / `suite`). |
| I2 | P1 | Works inside `unittest2` without making it a dependency ([ADR-0002](decisions/0002-zero-dependencies-runner-agnostic.md); no module turned out to be needed). |
| I3 | P1 | Standalone use (no test framework): a property returns a result object. |

## 14. Fuzzing bridge (F)

| ID | Pri | Requirement |
|----|-----|-------------|

## 15. Reliability (RL)

A testing library is only useful if its failures can be trusted: every reported counterexample must be real, minimal for the *same* bug, and reproducible anywhere.

| ID | Pri | Requirement |
|----|-----|-------------|
| RL1 | P0 | **Own, versioned PRNG**: the same seed produces the same choice stream on every Nim version, OS, 32/64-bit target and backend (C, C++). `std/random` is never used for generation ([ADR-0005](decisions/0005-own-prng-and-stable-hashing.md)). |
| RL2 | P0 | **Stable hashing** for seed derivation and failure database keys, implemented in the library; `std/hashes` is never used for anything persisted or printed. |
| RL3 | P0 | **Flaky detection**: the final counterexample is re-run twice before being reported; if either run passes, the property is reported as *flaky* with the observed outcomes, never as a normal failure ([ADR-0006](decisions/0006-failure-identity-and-flaky-detection.md)). |
| RL4 | P0 | **Failure identity during shrinking**: a candidate only counts as "still failing" if it fails the same way (exception type and raise/check location). Shrinking never slips from one bug to another. |
| RL5 | P1 | **Multiple distinct failures**: different failures found while generating or shrinking are each shrunk and reported (up to a configurable limit), instead of being merged or lost. |
| RL6 | P0 | **Generator errors are not property failures**: an exception inside a generator, an exhausted `filter`, or an overrun is reported as a generator problem with its own message. |
| RL7 | P0 | **Bounded resources**: maximum choice sequence length, recursion depth and collection size. Exceeding a bound marks the case invalid (overrun); generation never hangs or exhausts memory. |
| RL8 | P1 | **Per-case deadline**: a case slower than the deadline is a failure and is shrunk like any other. Configurable, can be disabled. |
| RL9 | P1 | **Crash breadcrumbs**: the run seed is written to `.proptest/last-run` before the first case, and the current case index is kept in memory, so a segfault, stack overflow or externally killed hang can still be replayed. |
| RL10 | P1 | **Watchdog**: a thread that, when a case runs longer than `hangTimeout`, prints what was running, the case's choices (its inputs when recorded) and the replay command, saves the case in the failure database so the next run replays it first with its inputs, and ends the process ([ADR-0017](decisions/0017-watchdog.md)). |
| RL11 | P1 | **Health checks** that fail early with an actionable message: filter rejecting too many cases, generation dominating the run time, generated data hitting size limits too often, generator producing too few distinct values. Each check can be disabled. |
| RL12 | P1 | **Failure database robustness**: versioned format, atomic writes (temporary file + rename), safe with concurrent test processes; entries that no longer fit the current generators are discarded, never turned into failures. |
| RL13 | P1 | **Isolation in stateful tests**: a fresh system under test and model per sequence, built by a factory; a teardown hook always runs, even after a failure. |
| RL14 | P1 | **Shrinker invariants**, checked by the library's own properties: the result is never larger than the original (shortlex order on the choice sequence), it still fails the same way, and shrinking terminates within its budget. |
| RL15 | P1 | **Stability policy**: within a minor version, the same seed and the same generator code produce the same values; any change to built-in generation is listed in the CHANGELOG. |

## 16. Performance (PF)

Properties should be cheap enough to run on every save, next to unit tests. Initial targets below are to be calibrated with the first benchmarks.

| ID | Pri | Requirement |
|----|-----|-------------|
| PF1 | P0 | Benchmark suite: cost per choice drawn, per built-in generator, per-case overhead of `forAll`, and shrinking cost on the reference bugs. Baseline: an equivalent hand-written random loop with no library. |
| PF2 | P1 | A default run (100 cases) of a simple property completes in milliseconds, **in debug builds**, which is how test suites usually run. Benchmarks are reported for debug and release. |
| PF4 | P0 | **No allocation per choice**: the choice buffer is preallocated and reused across cases and shrink attempts. |
| PF5 | P1 | **Built-in generators without closures**: type-inferred generators (`forAll(xs in seq[int])`) are expanded at compile time into direct calls; closures are used only for user-built combinators ([ADR-0007](decisions/0007-generator-representation.md)). |
| PF6 | P1 | **Efficient shrinking**: passes use binary/exponential search on values and span sizes instead of decrementing by one, and a cache of already tried sequences avoids re-running duplicates. |
| PF7 | P0 | **Deterministic performance gates**: the number of property executions spent shrinking each reference bug and the allocations per case are deterministic and are gated in CI. Wall-clock timings are informational ([ADR-0008](decisions/0008-deterministic-performance-gates.md)). |
| PF8 | P1 | **Time budget per property**: generation stops gracefully when the budget is reached, and the report says how many cases ran. |
| PF9 | P1 | **Compile-time cost**: a benchmark measures the compile time of a test file with 50 properties and derived object generators, with a budget. |
| PF10 | P1 | **Lazy formatting**: values are converted to strings only for the final report; `classify` with static labels does not allocate per case. |

Targets (release / debug; measured with `nimble bench`): drawing one choice < 5 ns / < 50 ns; generating an `int` < 30 ns / < 150 ns; per-case overhead excluding the body < 200 ns / < 1 µs; each reference bug shrunk to its minimal counterexample in < 500 property executions. Calibrated on 2026-11-20 from the first targets (one choice < 20 ns in debug; an `int` < 10 / < 40 ns), which assumed a uniform draw: a uniform 64-bit draw costs about 3 ns, but the distribution that finds boundary bugs (edges, sizes, hints) costs about 20 ns in release, and debug builds pay for Nim's runtime checks in the caller's code. The per-case targets, which decide how fast a suite runs, are unchanged and met.

## 17. Portability and quality (Q)

| ID | Pri | Requirement |
|----|-----|-------------|
| Q1 | P0 | `--mm:orc` and `--mm:arc`, with and without `--threads:on`, zero warnings. |
| Q2 | P1 | CI on Linux, macOS and Windows; Nim stable and devel. |
| Q4 | P0 | Public API fully documented (`##`) with `nim doc` published. |
| Q5 | P0 | The library tests itself with properties (dogfooding), in addition to unit tests. |
| Q6 | P1 | AddressSanitizer, UndefinedBehaviorSanitizer and leak checks in CI (closures held by generators must not leak under ARC). |
| Q7 | P0 | **Golden tests**: fixed seeds with their expected choice streams and generated values are committed and checked on every CI platform and backend (proves RL1, RL2, RL15). |
| Q8 | P1 | Examples and the README quickstart are compiled and run in CI. |

## 18. User documentation (DOC)

| ID | Pri | Requirement |
|----|-----|-------------|
| DOC1 | P0 | README with a quickstart that works after `nimble install` (validated by Q8). |
| DOC2 | P1 | **Writing generators** guide, including the rule "a smaller choice must produce a simpler value" (ADR-0001) and how to avoid heavy `filter`s. |
| DOC3 | P1 | **Property patterns** cookbook: round-trip, reference implementation (oracle), invariants, idempotence, metamorphic relations, "never crashes". |
| DOC4 | P1 | **Stateful testing tutorial**, using a circuit breaker as the worked example. |
| DOC5 | P1 | Configuration reference: every setting and environment variable, with defaults. |
| DOC6 | P1 | Troubleshooting: flaky properties, health-check messages, slow shrinking, replaying a seed, `--panics:on`. |
| DOC7 | P0 | CHANGELOG with semantic versioning, including every change to generated values (RL15). |

---

# Part III: Differentiators

What should make this library the obvious choice in Nim:

1. **Shrinking that just works.** Integrated shrinking over the choice sequence means custom generators built with `map`/`filter`/`flatMap` shrink for free. Users never write shrinkers (S1, ADR-0001).
2. **Stateful testing from day one**, with shrunk command sequences printed as runnable Nim code (M1–M4). This is the hardest part of PBT to get right and the one that finds the most valuable bugs.
3. **Types are the specification.** `forAll(x in MyObject)` works because generators are derived by macros at compile time (G3, G4).
4. **Failures that stay fixed.** Seed replay plus a failure database that re-runs past counterexamples first (R1–R3).
5. **Coverage you can assert.** `cover` turns "the generator probably produces edge cases" into a checked requirement (D2).
6. **Failures you can trust.** A reported counterexample is re-run twice before it is shown, fails the same way as the original bug, and replays identically on any Nim version, OS and backend. Flaky properties are called out as flaky (RL1–RL4).
7. **Survives crashes and hangs.** The seed is on disk before the first case, and deadlines turn hangs into ordinary, shrinkable failures (RL8, RL9).
8. **Fast enough for every save, with gates that do not flake.** No allocation per choice, closure-free built-in generators, and CI gates on deterministic metrics (executions and allocations) instead of noisy timings (PF4, PF5, PF7).
9. **Proven, not promised.** Every requirement has a test; shrink quality is measured against reference bugs; performance claims point to benchmarks (Part IV).
10. **Path to fuzzing and concurrency.** The same property can feed a fuzzer (F1) and a parallel linearizability check (M7).

---

# Part IV: Evidence policy

Same rule as `circuit_breaker`: **nothing is delivered without tests and benchmarks that prove its value and its performance.**

| ID | Rule |
|----|------|
| EV1 | Every requirement has at least one test citing its ID in the name (`test "S1: map shrinks without a custom shrinker"`). |
| EV2 | Every requirement affecting generation speed, shrinking time or per-case overhead has a benchmark. |
| EV3 | Every differentiator has a **value test**: a planted bug that example-based tests miss and the property finds, with the expected minimal counterexample. |
| EV4 | Every fixed bug gets a regression test. |
| EV5 | Tests are deterministic: fixed seeds, no wall clock, no network. |
| EV6 | Public claims point to a reproducible test or benchmark in the repository. |
| EV7 | Performance gates in CI use deterministic metrics (executions, allocations); wall-clock numbers are published but never gate a build. |

## Reference bugs for value tests

| Differentiator | Planted bug | Expected result |
|---|---|---|
| S1 integrated shrinking | `reverse` that drops the last element when `len > 3` | counterexample shrinks to a 4-element list of zeros |
| S1 through `map`/`filter` | bug triggered only by even numbers ≥ 100 from a filtered generator | counterexample is exactly `100` |
| M1–M4 stateful | a queue whose `pop` is wrong after exactly 3 pushes and 1 pop | shortest failing sequence (4 commands) printed as Nim code |
| R3 failure database | a property that failed in the previous run | the saved case runs first and fails before any random case |
| D2 coverage | a generator that never produces empty strings | `cover` fails with the observed percentage |
| G8 edge-case bias | a function that breaks on `int.high` | found within the default 100 cases |
| RL1/Q7 cross-platform replay | fixed seed | identical choice stream and values on Linux, macOS, Windows and JS |
| RL3 flaky detection | a property that fails only on odd-numbered executions | reported as flaky, never as a counterexample |
| RL4 failure identity | an assertion bug whose shrunk inputs would hit an unrelated `IndexDefect` | the reported counterexample still raises the original assertion |
| RL5 multiple failures | two independent bugs in one function | both reported, each with its own minimal counterexample |
| RL8 deadline | a function that is slow (60 ms) when the input contains `42`; one that never returns needs the RL10 watchdog (ADR-0012) | reported as a deadline failure with counterexample `[42]` |
| RL11 health check | `filter` that accepts 1 value in 10 000 | run stops early with a message suggesting a constructive generator |
| A6 quiet assertions | a property with a failing `check` inside `std/unittest` | one failure reported by the runner, no intermediate output from shrinking |
| PF6/PF7 shrink cost | each reference bug above | number of executions to reach the minimum, gated in CI |
| First real consumer | `circuit_breaker` model test (its SPEC V2/Q5) | runs in that project's CI |

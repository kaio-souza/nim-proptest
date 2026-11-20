# Traceability matrix

Status of every requirement in [`SPEC.md`](SPEC.md), checked by `scripts/check_traceability.nim` (`nimble trace`, CI job). Per-version view: [`ROADMAP.md`](ROADMAP.md).

Rules of the check:
- **done** and **partial** need a test whose name cites the ID (`test "S1: ..."`, value tests as `V-S1`), unless the Tests column says `CI` (the CI matrix is the evidence), `bench` (a benchmark gate) or `doc` (documentation).
- A Benchmark column naming `b_xxx` requires `benchmarks/b_xxx.nim`.
- Every ID cited by a test must have a row here.
- **pending** and **deferred** are not checked.

| ID | Requirement | Status | Tests | Benchmark | Notes |
|----|-------------|--------|-------|-----------|-------|
| G1 | `Gen[T]` over a choice source | done | t_choices | n/a | |
| G2 | Built-in generators | done | t_choices, t_gen | b_gen | integers incl. `range`, floats, bool, char, string, enum, seq, array, set, Option, tuple |
| G3 | Generators inferred from types | done | t_gen | b_gen | `x in T`, user `arbitrary` overloads |
| G4 | Object and distinct derivation | pending | | | v0.4 |
| G5 | Tables, sets, refs | pending | | | v0.4 |
| G6 | String alphabets | partial | t_gen | n/a | custom alphabets; alphanumeric and UTF-8 in v0.4 |
| G7 | Size control | done | t_choices | n/a | |
| G8 | Edge-case bias | done | t_choices, t_gen, t_values, t_find | b_find | limits, special floats, empty and single collections (`edgeBias`); boundary hints: `near`, mined constants (ADR-0012) |
| G9 | Float options and ranges | done | t_choices, t_gen | n/a | |
| C1 | `map`, `filter`, `flatMap` | done | t_gen, t_engine, t_values | n/a | |
| C2 | `oneOf`, `elements`, `constant` | done | t_gen | n/a | |
| C3 | `frequency` | pending | | | v0.4 |
| C4 | `recursive` | pending | | | v0.4 |
| C5 | `sized`, `resize` | pending | | | v0.6 |
| C6 | `unique`, `sortedSeq` | pending | | | v0.6 |
| C7 | Custom generators as procs | done | t_gen | n/a | `newGen`, `arbitrary` overloads |
| S1 | Integrated shrinking | done | t_choices, t_shrink, t_values | b_shrink | |
| S2 | Shrunk values satisfy the generator | done | t_values | n/a | |
| S3 | Deterministic shrinking | done | t_shrink, t_engine | b_shrink | |
| S4 | Shrink budget | done | t_shrink, t_engine, t_find | n/a | executions and time (`shrinkTimeBudget`); best counterexample so far |
| S5 | Shrink quality targets | done | t_values | b_shrink | integers to the exact boundary, shortest strings and lists |
| R1 | Seed and replay command on failure | done | t_engine, t_integration | n/a | |
| R2 | `PROPTEST_SEED` | done | t_integration | n/a | |
| R3 | Failure database | pending | | | v0.4 |
| R4 | Explicit examples | pending | | | v0.4 |
| R5 | No global state between properties | done | t_prng, t_engine | n/a | |
| A1 | `forAll(x in source)` | done | t_engine, t_integration | b_gen | ADR-0010 |
| A2 | `assume` | done | t_choices, t_engine | n/a | |
| A3 | Failure report | done | t_engine | n/a | |
| A4 | `Defect`s count as failures | done | t_engine | n/a | |
| A5 | Value printing | done | t_engine | n/a | |
| A6 | `check`/`require` inside `forAll` | done | t_engine, t_integration | n/a | ADR-0009 |
| A7 | `--panics:on` | done | t_integration | n/a | compile-time warning |
| M1 | Model, system, commands | done | t_stateful | n/a | `stateMachine` macro; malformed machines rejected at compile time |
| M2 | Random command sequences | done | t_stateful, t_find | b_gen, b_find | commands drawn among the enabled ones; arguments may read the model; swarm testing; 0 allocations per sequence |
| M3 | Sequence shrinking | done | t_stateful, t_choices | b_shrink | steps are spans deleted whole (ADR-0011); value test on 20 seeds |
| M4 | Failures as Nim code | done | t_stateful | n/a | `replayCommands` block compiled and run by a test; `showCode` |
| M5 | Invariants | done | t_stateful | n/a | |
| M6 | Injectable time | done | t_stateful | n/a | time as a command; exact boundary found |
| M7 | Parallel linearizability | deferred | | | after 1.0 |
| D1 | `classify` | done | t_find | n/a | also `label`; discards and shrinking not counted |
| D2 | `cover` | done | t_find | n/a | fails only when confidently below (Wilson 95%); per sequence in state machines |
| D3 | Size statistics | deferred | | | |
| O1 | Quiet exploration | done | t_integration | n/a | |
| O2 | Verbosity levels | done | t_find | n/a | `verbosity`, `PROPTEST_VERBOSITY` |
| O3 | JSON report | pending | | | v0.5 |
| O4 | Statistics and warnings in the report | done | t_find | n/a | labels, stateful commands and lengths, health-check warnings |
| K1 | Per-property settings | done | t_engine | n/a | |
| K2 | Environment defaults | partial | t_integration, t_find | n/a | `PROPTEST_CASES`, `PROPTEST_MAX_SHRINKS`, `PROPTEST_SEED`, `PROPTEST_DB`, `PROPTEST_DEADLINE`, `PROPTEST_TIME_BUDGET`, `PROPTEST_VERBOSITY`; `PROPTEST_REPORT` in v0.5 |
| K3 | Settings validation | done | t_engine | n/a | |
| I1 | `std/unittest` integration | done | t_integration | n/a | |
| I2 | `unittest2` adapter | pending | | | v0.5 |
| I3 | Standalone use | done | t_engine | n/a | `forAllResult`, `runProperty`, `PropertyError` |
| I4 | Async properties | deferred | | | |
| F1 | Fuzzing bridge | deferred | | | |
| RL1 | Own versioned PRNG | partial | t_prng | n/a | matches the reference C code on Linux; other OSes and JS pending in CI |
| RL2 | Stable hashing | done | t_prng | n/a | FNV-1a official vectors |
| RL3 | Flaky detection | done | t_values | n/a | double re-run |
| RL4 | Failure identity during shrinking | done | t_engine, t_values | n/a | 20 seeds |
| RL5 | Multiple distinct failures | done | t_values | b_shrink | 20 seeds; exploration continues after the first failure |
| RL6 | Generator errors are not failures | done | t_engine | n/a | |
| RL7 | Bounded resources | done | t_choices, t_engine | n/a | `maxChoices`, overruns discarded |
| RL8 | Per-case deadline | partial | t_find | n/a | slow cases fail and shrink; a case that never returns needs RL10 (after 1.0) |
| RL9 | Crash breadcrumbs | done | t_integration | n/a | |
| RL10 | Watchdog | deferred | | | |
| RL11 | Health checks | done | t_engine, t_find | n/a | filter, data too large, few distinct inputs, slow generation; `suppress` |
| RL12 | Failure database robustness | pending | | | with R3 |
| RL13 | Isolation in stateful tests | done | t_stateful | n/a | fresh model and setup per sequence; teardown after failures |
| RL14 | Shrinker invariants | done | t_shrink | n/a | |
| RL15 | Stability policy | partial | t_gen | n/a | golden snapshot; written policy in v0.5 |
| PF1 | Benchmark suite with baseline | done | bench | b_gen, b_shrink | |
| PF2 | Fast default run, debug and release | done | bench | b_gen | 100 cases: 0.16 ms (`int`) and 1.5 ms (`seq[int]`) in debug; ROADMAP has the table |
| PF3 | Parallel cases | deferred | | | |
| PF4 | No allocation per choice | done | t_choices | b_gen | allocation gate |
| PF5 | Built-in generators without closures | done | bench | b_gen | `TypeGen` + `drawFrom` |
| PF6 | Efficient shrinking | done | t_shrink | b_shrink | binary search, tried-sequence cache, merge pass |
| PF7 | Deterministic performance gates | done | bench | b_shrink, b_gen | executions and allocations |
| PF8 | Time budget per property | done | t_find | n/a | `timeBudget`, `PROPTEST_TIME_BUDGET` |
| PF9 | Compile-time benchmark | pending | | | v0.4 |
| PF10 | Lazy formatting | done | t_find | n/a | inputs formatted only for the final report; static labels do not allocate per case |
| Q1 | orc/arc × threads, no warnings | done | CI | n/a | also release/debug |
| Q2 | macOS, Windows, devel | pending | | | v0.5 |
| Q3 | JS backend | deferred | | | |
| Q4 | Public API documented | partial | CI | n/a | `##` on the public API, `nim doc` built in CI |
| Q5 | Dogfooding | done | t_prng, t_choices, t_shrink, t_values | n/a | |
| Q6 | Sanitizers | done | CI | n/a | ASan, UBSan, leak checks |
| Q7 | Golden tests | done | t_prng, t_gen | n/a | |
| Q8 | Examples compiled in CI | done | CI | n/a | |
| DOC1 | README quickstart | done | doc | n/a | README snippets live in `examples/quickstart.nim` and `examples/tour.nim`, built and run in CI |
| DOC2 | Writing generators guide | pending | | | v0.4 |
| DOC3 | Property patterns cookbook | done | doc | n/a | [`PATTERNS.md`](PATTERNS.md); its example `examples/patterns.nim` runs in CI |
| DOC4 | Stateful testing tutorial | done | doc | n/a | [`STATEFUL.md`](STATEFUL.md); its example `examples/stateful.nim` runs in CI |
| DOC5 | Configuration reference | pending | | | v0.5 |
| DOC6 | Troubleshooting | pending | | | v0.5 |
| DOC7 | CHANGELOG | done | doc | n/a | |

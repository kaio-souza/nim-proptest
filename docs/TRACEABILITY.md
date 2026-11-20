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
| G4 | Object and distinct derivation | pending | | | v0.3 |
| G5 | Tables, sets, refs | pending | | | v0.3 |
| G6 | String alphabets | partial | t_gen | n/a | custom alphabets; Unicode pending |
| G7 | Size control | done | t_choices | n/a | |
| G8 | Edge-case bias | partial | t_choices, t_gen, t_values | n/a | integer and float limits; collection edge cases pending |
| G9 | Float options and ranges | done | t_choices, t_gen | n/a | |
| C1 | `map`, `filter`, `flatMap` | done | t_gen, t_engine, t_values | n/a | |
| C2 | `oneOf`, `elements`, `constant` | done | t_gen | n/a | |
| C3 | `frequency` | pending | | | |
| C4 | `recursive` | pending | | | |
| C5 | `sized`, `resize` | pending | | | |
| C6 | `unique`, `sortedSeq` | pending | | | |
| C7 | Custom generators as procs | done | t_gen | n/a | `newGen`, `arbitrary` overloads |
| S1 | Integrated shrinking | done | t_choices, t_shrink, t_values | b_shrink | |
| S2 | Shrunk values satisfy the generator | done | t_values | n/a | |
| S3 | Deterministic shrinking | done | t_shrink, t_engine | b_shrink | |
| S4 | Shrink budget | partial | t_shrink, t_engine | n/a | execution budget; time budget pending |
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
| M1 | Model, system, commands | pending | | | v0.2 |
| M2 | Random command sequences | pending | | | v0.2 |
| M3 | Sequence shrinking | pending | | | v0.2 |
| M4 | Failures as Nim code | pending | | | v0.2 |
| M5 | Invariants | pending | | | v0.2 |
| M6 | Injectable time | pending | | | v0.2 |
| M7 | Parallel linearizability | deferred | | | after 1.0 |
| D1 | `classify` | pending | | | v0.3 |
| D2 | `cover` | pending | | | v0.3 |
| D3 | Size statistics | deferred | | | |
| O1 | Quiet exploration | done | t_integration | n/a | |
| O2 | Verbosity levels | pending | | | |
| O3 | JSON report | pending | | | |
| O4 | Statistics and warnings in the report | pending | | | |
| K1 | Per-property settings | done | t_engine | n/a | |
| K2 | Environment defaults | partial | t_integration | n/a | `PROPTEST_CASES`, `PROPTEST_MAX_SHRINKS`, `PROPTEST_SEED`, `PROPTEST_DB` |
| K3 | Settings validation | done | t_engine | n/a | |
| I1 | `std/unittest` integration | done | t_integration | n/a | |
| I2 | `unittest2` adapter | pending | | | |
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
| RL8 | Per-case deadline | pending | | | |
| RL9 | Crash breadcrumbs | done | t_integration | n/a | |
| RL10 | Watchdog | deferred | | | |
| RL11 | Health checks | partial | t_engine | n/a | filter rejection hint; other checks pending |
| RL12 | Failure database robustness | pending | | | with R3 |
| RL13 | Isolation in stateful tests | pending | | | with M1 |
| RL14 | Shrinker invariants | done | t_shrink | n/a | |
| RL15 | Stability policy | partial | t_gen | n/a | golden snapshot; written policy pending |
| PF1 | Benchmark suite with baseline | done | bench | b_gen, b_shrink | |
| PF2 | Fast default run, debug and release | done | bench | b_gen | 100 cases: 0.16 ms (`int`) and 1.5 ms (`seq[int]`) in debug; ROADMAP has the table |
| PF3 | Parallel cases | deferred | | | |
| PF4 | No allocation per choice | done | t_choices | b_gen | allocation gate |
| PF5 | Built-in generators without closures | done | bench | b_gen | `TypeGen` + `drawFrom` |
| PF6 | Efficient shrinking | done | t_shrink | b_shrink | binary search, tried-sequence cache, merge pass |
| PF7 | Deterministic performance gates | done | bench | b_shrink, b_gen | executions and allocations |
| PF8 | Time budget per property | pending | | | |
| PF9 | Compile-time benchmark | pending | | | |
| PF10 | Lazy formatting | pending | | | inputs are already formatted only for the final report; test pending |
| Q1 | orc/arc × threads, no warnings | done | CI | n/a | also release/debug |
| Q2 | macOS, Windows, devel | pending | | | |
| Q3 | JS backend | deferred | | | |
| Q4 | Public API documented | partial | CI | n/a | `##` on the public API, `nim doc` built in CI |
| Q5 | Dogfooding | done | t_prng, t_choices, t_shrink, t_values | n/a | |
| Q6 | Sanitizers | done | CI | n/a | ASan, UBSan, leak checks |
| Q7 | Golden tests | done | t_prng, t_gen | n/a | |
| Q8 | Examples compiled in CI | done | CI | n/a | |
| DOC1 | README quickstart | done | doc | n/a | README snippets live in `examples/quickstart.nim` and `examples/tour.nim`, built and run in CI |
| DOC2 | Writing generators guide | pending | | | |
| DOC3 | Property patterns cookbook | pending | | | |
| DOC4 | Stateful testing tutorial | pending | | | v0.2 |
| DOC5 | Configuration reference | pending | | | |
| DOC6 | Troubleshooting | pending | | | |
| DOC7 | CHANGELOG | done | doc | n/a | |

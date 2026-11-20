# Changelog

All notable changes. Versions follow semantic versioning. Any change to the values generated for a given seed is listed under **Generation changes** (see the stability policy, SPEC RL15).

## Unreleased (v0.3)

Find more bugs, and show what was tested (ADR-0012). Every change below was
measured with the new bug-finding benchmark (`benchmarks/b_find.nim`, 100
seeds): a bug at an exact boundary inside a range went from 1 to 68 seeds,
a bug that needs a command to stay away from 3 to 97, with no row worse.

### Added
- `classify`, `cover` and `label` inside `forAll` and `stateMachine`
  commands; percentages in the report. `cover` fails a property (status
  `psInsufficientCoverage`) only when the share is confidently below the
  requirement (95% Wilson interval); otherwise it warns. Static labels do
  not allocate per case.
- State machines report, without any code, how often each command ran, how
  often its precondition blocked it, and sequence lengths; a command that
  never ran is a warning.
- Boundary hints: `ints(lo, hi, near = [...])`, and integer constants mined
  from the property and from the test file (`mineConstants`, on).
- Swarm testing for state machines (`swarm`, on): half of the sequences
  leave some commands out.
- `edgeBias` setting; edge cases now also cover empty and single-element
  collections, with one shared probability.
- `deadline` (per case, off by default; `PROPTEST_DEADLINE`), `timeBudget`
  (`PROPTEST_TIME_BUDGET`) and `shrinkTimeBudget`.
- Health checks with fixes: data too large for `maxChoices`, input spaces
  smaller than `cases`, generation dominating the run time (`suppress`).
- Verbosity levels (`verbosity`, `PROPTEST_VERBOSITY`): passing properties
  print their statistics and warnings at `normal`; `verbose` prints every
  case, `debug` every shrink step.
- `PropertyResult.firstFailureAt`; reports say at which case a property
  failed.
- Bug-finding benchmark and gate (`b_find`), property patterns cookbook
  (`docs/PATTERNS.md`, `examples/patterns.nim`).

### Changed
- A new shrink pass lowers a choice and raises the next one, so `-1`
  shrinks to `1` when `0` is not a counterexample.
- `StateRunner` takes a `swarm` parameter.

### Generation changes
- The exploration distribution changed (edge share, collection edges, hint
  and swarm choices): values generated for a given seed differ from v0.2.
  The golden test was updated with this entry.

## v0.2 (2026-11-20)

### Added
- Stateful (model-based) testing, ADR-0011: the `stateMachine` macro (model,
  setup, teardown, commands with preconditions, `run`, postconditions and
  updates, invariants), `checkStateMachine`, `stateMachineResult`, and the
  `maxSteps` setting. Commands are chosen among those enabled by their
  preconditions, so generated and shrunk sequences are always valid.
- Failing sequences are reported as a `replayCommands` block of Nim code, with
  the failing step; `replayCommands` runs it as a regression test. `showCode`
  prints values as Nim literals (overload it for custom types).
- Shrinking deletes whole collection elements and stateful steps (spans) in a
  new first pass, `deleteSpans`.
- Stateful testing tutorial (`docs/STATEFUL.md`) and `examples/stateful.nim`.

### Changed
- `Probe` (shrinker callback) takes a third parameter, the recorded spans.
- `check` messages print each expression on one line.

### Fixed
- A replayed stateful sequence that raised leaked memory under ARC/ORC
  (found by LeakSanitizer before release).

## v0.1 (unreleased, superseded by v0.2)

### Added
- Design documentation: specification, roadmap, architecture and ADRs 0001–0010.
- MIT license and package manifest (`proptest.nimble`).
- Core library (v0.1): own PRNG and stable hash; choice sequences
  with reused buffers; type-inferred generators for integers, floats, `bool`,
  `char`, `string`, enums, `seq`, `array`, `set`, `Option` and tuples;
  combinators; integrated shrinking with failure signatures, multiple failures
  and flaky detection; `forAll(x in source)` with `check` rewriting and
  `std/unittest` integration; seed replay and crash breadcrumbs.
- `forAllResult`: same arguments as `forAll`, returns the `PropertyResult`.
- Exploration continues after the first failure to find other distinct bugs
  (stops at `maxFailures`); a merge pass in the shrinker (`[1, 1]` → `[2]`).
- Test suite (72 tests, value tests, golden tests), benchmarks, deterministic
  gates (`nimble gate`), traceability check (`nimble trace`), CI workflows.
- `examples/quickstart.nim`.

### Generation changes
- The exploration distribution of integers now proposes the type limits with
  probability 2/16 and avoids 64-bit divisions. Values generated for a given
  seed differ from earlier development builds (no release was affected).

### Fixed (during development, before any release)
- `drawInt` with a single-value range (`lo == hi`) could return values outside
  the range in release builds: `countLeadingZeroBits(0)` is undefined
  behavior. Regression test in `tests/t_choices.nim`.

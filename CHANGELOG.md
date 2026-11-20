# Changelog

All notable changes. Versions follow semantic versioning. Any change to the values generated for a given seed is listed under **Generation changes** (see the stability policy, SPEC RL15).

## Unreleased (v0.2)

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

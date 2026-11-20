# ADR-0015: Stability policy for generated values

- Status: Accepted
- Date: 2026-11-20
- Requirements: RL15, Q7, DOC7

## Context

A seed is only useful if it replays. Users copy `PROPTEST_SEED` from CI failures, pin seeds in regression tests and keep a failure database of choice sequences. All of that breaks silently if the values a seed produces change in a release the user did not expect to matter. At the same time, most improvements to a property-testing library (edge cases, distributions, faster generators, better shrinking) change those values. The roadmap already batches such changes ("Generation changes, together"), but nothing said where the boundary is, what counts as a change, or how it is checked.

The golden test before this ADR covered nine basic types drawn straight from a `ChoiceSource`: not the seed derivation, the size schedule, edge bias, mined constants, derived types, combinators, state machines or shrinking, which is where most changes happen.

## Decision

- **Boundary: the minor version.** Within a minor version (all its patch releases) the same seed, test code and settings give the same values, exploration, stateful sequences, shrink path and counterexample, on every tested platform and build mode. Generation changes go only into a minor release, before and after 1.0. They do not need a major release: they never break code, only replays, and the CHANGELOG says which.
- **What counts as a generation change**: anything that alters the above, and the formats of the failure database and of the JSON report (`format`). Shrinking is included: a different counterexample for the same seed is as visible to a user as different inputs.
- **Not covered**: the text report, printing of values, warnings, anything time-dependent, performance (shrink execution counts), and additions to the API or to the JSON report.
- **Enforcement: a golden snapshot of the whole pipeline**, `tests/golden/snapshot.txt`, produced by `tests/golden.nim` and compared by `t_golden` on every CI job. Each of ~50 properties records a hash of every value generated and every shrink candidate (so the shrink path is covered), plus a few values spread over the run for a readable diff. `nimble golden` rewrites it; the commit that does so must add a CHANGELOG entry under "Generation changes".
- **Constant mining is off in the snapshot** except for one property in its own module (`tests/golden_mined.nim`). Mining reads the integer literals of the whole test file, so with it on, editing the golden file itself would change every section, and maintenance edits would look like generation changes.
- **Breaking API changes**: before 1.0 in a minor release, after 1.0 in a major release, preceded when possible by a `{.deprecated.}` release.

## Consequences

- Patch releases are safe to take without reading the CHANGELOG; minor releases need a look at "Generation changes".
- Improvements that change values wait for the next minor release, which the batching in the roadmap already assumed.
- A bug fix that changes values also waits, unless the bug makes the library unusable; then the patch release lists it under "Generation changes", as an explicit exception.
- The snapshot is sensitive by design: an unintended change anywhere in the pipeline fails CI with the sections and values that changed, on the platform where it happened.
- The snapshot cannot cover user code; the policy states which user edits change values (moving a property, literals in the test file, settings).

## Evidence

`tests/t_golden.nim` on every CI job (Linux, macOS, Windows × orc/arc × threads × debug/release); changing `defaultEdgeBias` from 0.25 to 0.26 fails it with the changed sections, and adding a literal to `tests/golden.nim` does not change it. `tests/t_prng.nim` checks the PRNG and hash against reference vectors. Policy for users: [docs/STABILITY.md](../STABILITY.md).

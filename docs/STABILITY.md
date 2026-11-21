# Stability policy

What you can rely on between versions of proptest, what may change, and how each change is announced. Requirement RL15; enforced by golden tests (Q7); reasons in [ADR-0015](decisions/0015-stability-policy.md).

**In short:** within a minor version (1.0.0, 1.0.1, 1.0.2, ...) the same seed produces the same values, the same exploration and the same counterexample. Changes to any of that happen only in a new minor version, and every one is listed in the CHANGELOG under **Generation changes**.

## Why it matters to you

A seed is a promise that a run can be replayed. If generation changed in a patch release, a `PROPTEST_SEED` copied from a CI failure yesterday could replay something else today, after an innocent dependency update. Your own regression tests that pin a seed (`initSettings(seed = 42)`) would start checking different inputs without anything in your code changing.

The opposite promise, "values never change", would freeze the library: better edge cases, faster generators and smarter shrinking all change values. The policy picks the middle: changes are allowed, but only at a version boundary you choose to cross, and always announced.

## What stays the same within a minor version

Given the same proptest version (patch releases included), the same test code and the same settings:

| What | Covers |
|---|---|
| **Generated values** | every built-in generator (`x in T` for every supported type, derived objects, case objects, `distinct`, `ref`, containers), every combinator, and the draw primitives your own generators use (`drawInt`, `drawBool`, `drawIndex`, `drawFloat`, ...) |
| **The run** | how the run seed becomes each property's seed (from its `name`), how sizes grow over the run, edge-case bias, mined constants and `near` hints, swarm testing, how many cases are discarded |
| **Stateful sequences** | which commands run, in which order, with which arguments |
| **Shrinking** | the path the shrinker takes and the reported minimal counterexample, for every failure found |
| **Failure database** | its file format (`proptest-db 1`) and how entries are keyed |
| **JSON report** | the meaning of every field of `format` 1 |

It holds on every platform and build the CI tests: Linux, macOS and Windows; debug and release; `--mm:orc` and `--mm:arc`; threads on and off; Nim 2.2.4 (Nim devel is also tested, as an allowed failure: a compiler change could break it before a release says so). The random generator and the hash are the library's own, checked against reference vectors, so nothing depends on the standard library's `random` or `hash`, which may change between Nim versions.

### What "the same test code" means

Your code decides part of what is generated, so some edits of yours change values even with the same library version and seed:

- **Moving a property.** Its default name is `file:line`, and its seed comes from its name. Give it a `name` to keep its seed when lines move.
- **Integer literals in the test file.** They are proposed as boundary values (`mineConstants`). Adding a literal to the file can change what other properties in it generate. `mineConstants = false` makes a property independent of its file.
- **Your own generators** and the order in which they draw.
- **Settings that shape inputs:** `cases`, `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm`, `mineConstants`, including from the environment (`PROPTEST_CASES`).

[CONFIGURATION.md](CONFIGURATION.md#what-a-replay-needs) lists what a replay needs.

## What may change in any release

These are not covered: relying on them in a test would make the test fragile.

- **The text report**: wording, layout, which statistics and warnings are printed. Parse the [JSON report](../README.md#json-report-for-ci) instead.
- **How values are printed** (`show`, `showCode`) when the change makes them clearer or more correct. A `replayCommands` block printed by an older version stays valid Nim, but a newer version may print it differently.
- **Health checks and warnings**: new checks, other thresholds.
- **Anything that depends on time**: `deadline`, `timeBudget`, `shrinkTimeBudget`, the slow-generation check. A faster machine runs more cases within a time budget.
- **Performance**: the number of shrink executions to reach the same counterexample may drop (the counterexample itself stays the same within a minor version).
- **New API**: new generators, combinators, settings, fields in `PropertyResult` and new fields in the JSON report. Adding a field never changes `format`.

## How changes are announced

Every release's CHANGELOG entry groups changes by kind:

| Heading | Contains | Allowed in |
|---|---|---|
| **Added**, **Fixed**, **Changed** | new API, bug fixes, report or documentation changes | any release |
| **Generation changes** | anything in [What stays the same](#what-stays-the-same-within-a-minor-version): values, exploration, shrinking, file formats | a minor release (x.y.0) |
| **Breaking** | API changes that make code stop compiling or change meaning | a major release (x.0.0) |

A **Generation changes** entry says what changes, for which generators or settings, and whether saved seeds and failure database entries still replay. Generation changes are batched: several land together in one minor release, so seeds stop replaying once rather than after each improvement.

A **Breaking** API change is preceded, when possible, by a `{.deprecated.}` version of the old API for at least one minor release, with a message naming the replacement.

A bug fix that changes values (a generator that could never produce some value it should) is still a generation change: it waits for the next minor release unless the bug makes the library unusable, in which case the patch release says so under **Generation changes**.

## When you upgrade

- **Patch release (1.0.1 → 1.0.2):** nothing to do. Seeds, pinned tests and saved failures keep working.
- **Minor release (1.0 → 1.1):** read **Generation changes**. Seeds printed by the old version replay other inputs: replay old CI failures with the old version. Properties with a fixed `seed` now check other inputs, which is usually fine; review any test that asserts on the exact values a seed produces. The failure database needs nothing: entries that no longer fit the generators are dropped, entries that now pass are forgotten after three runs, and a real bug still fails.
- **To keep a specific input forever**, do not rely on a seed: write it down with `example(...)` or, for state machines, paste the `replayCommands` block into a test. Those do not depend on generation at all.

## How it is enforced

- **Golden snapshot** (`tests/t_golden.nim`, `tests/golden/snapshot.txt`): runs 51 properties through the whole pipeline (every type and combinator, derived types, mined constants, edge bias, sizes, swarm, shrinking of several reference bugs, a state machine, the failure database file) and compares a hash of every generated value and every shrink candidate, plus readable samples, with the committed snapshot. CI runs it on every platform and build mode above.
- **Reference vectors** (`tests/t_prng.nim`): the random generator and the hash against their authors' reference code and the official FNV-1a vectors.
- **Process**: when the snapshot test fails, the message says so. An intended change is recorded with `nimble golden` and a CHANGELOG entry under **Generation changes** in the same commit; anything else is a regression to fix.

The snapshot test is the evidence that a patch release keeps its promise: if it passes on the release commit, the release generates exactly what the previous one in the same minor version did.

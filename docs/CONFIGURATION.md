# Configuration reference

Every setting, environment variable and compile-time option, with its default, what it costs and when to change it. Problems and their fixes: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

- [Recipes](#recipes): copy one and adapt it
- [How a value is chosen](#how-a-value-is-chosen): explicit setting, environment, default
- [Settings](#settings), grouped by what they control
- [Environment variables](#environment-variables)
- [Compile-time options](#compile-time-options): build mode, `--panics`, stack traces
- [Files the library writes](#files-the-library-writes)
- [What a replay needs](#what-a-replay-needs)

## Recipes

**Day to day, nothing to set.** 100 cases per property, shrinking on, failures saved and replayed first on the next run. Most properties never need a setting.

```nim
forAll(xs in seq[int]):
  check xs.sorted.sorted == xs.sorted
```

**More cases in CI than on your machine.** Use the environment, not the code, so local runs stay fast:

```sh
PROPTEST_CASES=1000 PROPTEST_REPORT=proptest-report.jsonl nimble test
```

A property that sets `cases` itself ignores `PROPTEST_CASES` (see [precedence](#how-a-value-is-chosen)): leave `cases` out of properties you want CI to scale.

**A nightly deep run.** Many more cases, bounded by time so a slow property cannot take the night:

```sh
PROPTEST_CASES=100000 PROPTEST_TIME_BUDGET=60000 PROPTEST_VERBOSITY=quiet nimble test
```

`timeBudget` is per property: each stops after 60 s with a warning that says how many cases ran.

**Replay a failure.** Copy the `Replay:` line of the report. Same binary, same environment otherwise:

```sh
PROPTEST_SEED=17542877672211577899 ./tests/t_sorting
```

**See what a property generates.** Every case's inputs, and every statistic:

```sh
PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20 ./tests/t_sorting
```

**One expensive property.** Fewer, larger cases, and a cap on time per case:

```nim
forAll(initSettings(cases = 30, maxSize = 300, deadline = 2000), doc in Document):
  check parse(render(doc)) == doc
```

**A property that must always see the same inputs** (an example in documentation, a test of the library itself): fix the seed. It then ignores `PROPTEST_SEED`.

```nim
forAll(initSettings(seed = 42), x in int): ...
```

**The same settings for many properties.** `Settings` is a plain object; build it once:

```nim
let heavy = initSettings(cases = 50, maxSize = 500, deadline = 1000)

test "round trip":
  forAll(heavy, doc in Document):
    check parse(render(doc)) == doc

test "rendering is stable":
  forAll(heavy, doc in Document):
    check render(doc) == render(parse(render(doc)))
```

Each property still gets its own seed (derived from its `file:line` name), so sharing settings does not make two properties draw the same values. Leave `name` empty in shared settings for that reason.

## How a value is chosen

For each setting, the first that applies wins:

1. **The argument** given to `initSettings(...)`.
2. **The environment variable**, for the settings that have one (read when `initSettings` runs).
3. **The built-in default.**

```nim
# PROPTEST_CASES=1000 in the environment:
forAll(x in int): ...                          # 1000 cases: environment
forAll(initSettings(cases = 20), x in int): ... # 20 cases: argument
```

The seed follows the same order: `seed` in the settings, then `PROPTEST_SEED`, then a random seed picked once per process. That **run seed** is not used directly: each property derives its own seed from it and from its `name`, so one `PROPTEST_SEED` replays every property of the program, and properties do not share random streams.

An environment variable that cannot be parsed is an error, not a silent default: `PROPTEST_CASES=abc` raises `ValueError: PROPTEST_CASES is not an integer: abc` at the first property. Invalid settings (`cases = 0`, `edgeBias = 2.0`) raise `ValueError: invalid proptest settings: ...` before any case runs.

## Settings

Pass them to `initSettings(...)` among the arguments of `forAll`, `forAllResult` or `checkStateMachine`. For state machines a **case is a whole sequence** of commands.

### How much to test

| Setting | Default | Environment | Valid |
|---|---|---|---|
| `cases` | 100 | `PROPTEST_CASES` | >= 1 |
| `maxSize` | 100 | | >= 0 |
| `maxSteps` | 50 | | >= 1 |
| `maxDepth` | 5 | | >= 0 |
| `maxChoices` | 8192 | | >= 1 |

**`cases`**: cases explored, passing or failing. Cost grows linearly; the chance of hitting a bug that needs a rare input grows too, but slowly: a bug hit by 1 input in 1000 is found by 100 cases about 1 run in 10, by 1000 cases about 2 runs in 3. Raise it in CI rather than in the code. **Changing it changes the inputs** of every case (sizes grow over the run, see `maxSize`), so a seed only replays with the same `cases`.

**`maxSize`**: how large values get. Sizes grow from 0 at the first case to `maxSize` at the last, so the first cases are small and simple. Discarded cases do not advance the size: a property that discards everything keeps generating small values ([gave up](TROUBLESHOOTING.md#gave-up-after-n-passing-cases)). Measured on `seq[int]` with 100 cases:

| `maxSize` | mean length | longest |
|---|---|---|
| 10 | 3 | 16 |
| 100 (default) | 40 | 154 |
| 1000 | 416 | 1927 |

Raise it when a bug needs long inputs (a buffer that fills at 256 elements); lower it when the code under test is slow on large inputs. Nested collections are shorter than top-level ones. Larger values also take longer to shrink, but shrinking always ends at a minimal one. Size limits of one generator are better set on the generator: `seqs(ints(), maxLen = 10)`.

**`maxSteps`** (state machines): the longest command sequence. Most bugs need few steps, and swarm testing (below) makes long runs of one command likely within 50. Raise it for bugs that need many steps (a counter that overflows after 300 increments); cost per sequence grows with it.

**`maxDepth`**: how deep recursive data goes while exploring (trees, `ref` objects that point to their own type, nested `seq`). Deeper means larger, slower cases. 0 gives the simplest value of a recursive type (a `nil` ref, an empty list of children).

**`maxChoices`**: random choices one case may use (an `int` is one choice, a `seq` is about one per element plus its elements). A case that needs more is skipped and counted as "too large", which keeps a runaway generator from exhausting memory. When the [health check](TROUBLESHOOTING.md#warning-cases-needed-more-than-maxchoices) says many cases were skipped, bound the generator's sizes first; raise `maxChoices` only if large cases are the point.

### Shrinking

| Setting | Default | Environment | Valid |
|---|---|---|---|
| `maxShrinks` | 2000 | `PROPTEST_MAX_SHRINKS` | >= 0 |
| `shrinkTimeBudget` | 0 (none) | | >= 0 ms |
| `maxFailures` | 3 | | >= 1 |

**`maxShrinks`**: property executions spent shrinking each failure. The library's reference bugs shrink to their exact minimum in 9 to 214 executions, so 2000 is generous; the budget matters when one execution is slow. 0 reports the first failing case as found, unshrunk.

**`shrinkTimeBudget`**: a time cap per failure, for slow properties. When it hits, the report says "Shrinking stopped at its time budget" and shows the smallest counterexample so far: valid, maybe not minimal.

**`maxFailures`**: distinct failures (different exception type or location) kept and shrunk. Exploration goes on after the first failure to find others, and stops once this many are known. 1 stops at the first bug, which is faster but hides a second bug until the first is fixed.

### Finding bugs

| Setting | Default | Environment | Valid |
|---|---|---|---|
| `edgeBias` | 0.25 | | 0.0 .. 1.0 |
| `mineConstants` | true | | |
| `swarm` | true | | |
| `maxDiscardRatio` | 10 | | >= 0 |

**`edgeBias`**: the share of draws that propose an edge value instead of a uniform one: 0, 1, -1 and the type's limits for integers; -0.0, NaN, infinities and subnormals for floats; empty and one-element collections. Bugs cluster there. 0.0 gives uniform values only; higher values test edges more and typical values less. Changing it changes the inputs of every case.

**`mineConstants`**: integer literals and constants in the property body (and, with fewer draws, in the whole test file) are proposed as `v - 1`, `v`, `v + 1`. This is how `x == 1000` is found in `0 .. 2000`. It also means a property mentioning `997` sees 996 to 998 more often than chance: usually what you want. Turn it off to measure plain random behavior. For a boundary defined in another module, use `ints(lo, hi, near = [v])`.

**`swarm`** (state machines): half of the sequences leave a random subset of commands out, so long runs of the remaining ones become likely ("12 increments with no reset": found on 3 of 100 seeds without swarm, 97 with it). The other half use every command. Turn it off only to compare.

**`maxDiscardRatio`**: a property gives up after `cases × maxDiscardRatio` discarded cases (by `assume`, by `filter`, or too large). Raising it hides the problem; generating valid values directly fixes it ([gave up](TROUBLESHOOTING.md#gave-up-after-n-passing-cases)).

### Time

| Setting | Default | Environment | Valid |
|---|---|---|---|
| `deadline` | 0 (off) | `PROPTEST_DEADLINE` | >= 0 ms |
| `timeBudget` | 0 (none) | `PROPTEST_TIME_BUDGET` | >= 0 ms |

**`deadline`**: a case that takes longer fails with `DeadlineExceeded`, and is shrunk like any failure: to the smallest input that is still slow. Use it to find performance cliffs (quadratic behavior on some input). While exploring, a case is allowed 1.25 × the deadline, so one just over it does not become a flaky report. Trade-off: timings vary between machines and under load, so set it well above normal case times, especially in CI. It does not stop a case that never returns: that needs a watchdog thread (planned).

**`timeBudget`**: a time cap on exploration, per property. When it hits, the property stops and reports what it did: a passing property says "time budget of N ms reached after K of M cases" as a warning. It keeps CI time bounded at the cost of fewer cases on slow machines.

### Output

| Setting | Default | Environment | Values |
|---|---|---|---|
| `verbosity` | `vNormal` | `PROPTEST_VERBOSITY` | `quiet`, `normal`, `verbose`, `debug` |
| `report` | empty (none) | `PROPTEST_REPORT` | a file path |
| `suppress` | `{}` | | `hcLargeData`, `hcFewDistinct`, `hcSlowGeneration` |

**`verbosity`**:

| Level | Prints |
|---|---|
| `quiet` | failures only |
| `normal` | also warnings, and the statistics of properties that use `classify`, `cover` or `label` |
| `verbose` | also one line per case with its inputs, and every statistic (stateful command counts, sequence lengths) |
| `debug` | also every accepted shrink step |

In the environment, the names have no `v` prefix (`PROPTEST_VERBOSITY=verbose`); in code they do (`verbosity = vVerbose`).

**`report`**: a [JSON Lines](https://jsonlines.org) file each property result is appended to, for CI tools. The file and its directory are created; several test programs can share one file. A path that cannot be written raises `IOError` naming the path. Fields: see the [README](../README.md#json-report-for-ci). Example: list the failures and how to replay them.

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status) — \(.replay)"' proptest-report.jsonl
```

**`suppress`**: health checks not to run on this property. Prefer fixing what a check reports; suppress when the warning is expected (a property over `bool` really has two inputs).

### Identity and reproduction

| Setting | Default | Environment |
|---|---|---|
| `seed` | random | `PROPTEST_SEED` |
| `name` | `file:line` | |

**`seed`**: fixes the run seed for this property; it then ignores `PROPTEST_SEED`. Good for documentation and the library's own tests; bad for ordinary tests, which would explore the same 100 inputs forever.

**`name`**: shown in reports, and used for two things:

- **The property's seed** is derived from the run seed and the name. With the default name (`file:line`), adding a line above a property changes its inputs for the same `PROPTEST_SEED`. A seed printed in a report replays the binary that printed it; after editing the file, rely on the failure database instead.
- **The failure database key.** Without a name the key is a hash of the property's code, so editing the property forgets its saved failures (they may no longer make sense). With a name, saved failures survive edits; those that no longer fit the generators are dropped.

Give a name to properties you refer to elsewhere (a bug tracker, a CI dashboard): it stays stable when lines move.

## Environment variables

| Variable | Sets | Format | Typical use |
|---|---|---|---|
| `PROPTEST_SEED` | run seed | unsigned 64-bit integer | replay a failure |
| `PROPTEST_CASES` | default `cases` | integer | more cases in CI |
| `PROPTEST_MAX_SHRINKS` | default `maxShrinks` | integer | slow properties in CI |
| `PROPTEST_DEADLINE` | default `deadline` | integer, ms | catch slow cases in CI |
| `PROPTEST_TIME_BUDGET` | default `timeBudget` | integer, ms | bound nightly runs |
| `PROPTEST_VERBOSITY` | default `verbosity` | `quiet`, `normal`, `verbose`, `debug` | look at generated inputs |
| `PROPTEST_REPORT` | default `report` | file path | JSON for CI tools |
| `PROPTEST_DB` | directory of local files | path, or `off` | move or disable `.proptest/` |

Settings with no variable (`maxSize`, `edgeBias`, ...) change what a property tests rather than how long it runs, so they are better kept in its code where a reader sees them. To set them for a whole suite, share a `Settings` value ([recipe](#recipes)).

## Compile-time options

**Build mode and stack traces.** Failures are told apart by exception type and by the line in your code where they were raised. That line comes from the stack trace, which `-d:release` and `-d:danger` turn off:

| Build | `check` failures | `doAssert`, `raise`, index errors | Overflow and index checks |
|---|---|---|---|
| debug (default) | located | located | on |
| `-d:release` | located | type only | on |
| `-d:release --stackTrace:on` | located | file only (`t_sort.nim:0`) | on |
| `-d:release --stackTrace:on --lineTrace:on` | located | located | on |
| `-d:danger` | located | type only | **off** |

Without locations, two different bugs that raise the same exception type look like one, and the report says "Location unknown (no stack trace)". Prefer debug builds for property tests, or add `--stackTrace:on --lineTrace:on` to a release build (both: the stack trace alone has no line numbers). Avoid `-d:danger`: with checks off, an out-of-bounds index is undefined behavior instead of a failure the library can catch and shrink.

**`--panics:on`.** Defects (`IndexDefect`, `AssertionDefect`, ...) end the process at once, so the failing case cannot be shrunk. The library warns at compile time. Build tests with the default `--panics:off`; if you must keep it on, the run seed is already in `.proptest/last-run` to replay the crash.

**`-d:proptestDb=<dir>` or `-d:proptestDb=off`.** The compiled-in default of `PROPTEST_DB`, for a test binary that should never write files (the variable still overrides it).

**Memory management and threads.** `--mm:orc` (default) and `--mm:arc`, with threads on or off, are all tested in CI on Linux, macOS and Windows.

## Files the library writes

All under `PROPTEST_DB` (default `.proptest`, relative to the working directory). Add it to `.gitignore`.

| File | Written | Purpose |
|---|---|---|
| `last-run` | before the first case of each run | the run seed and the command: replays a run that crashed or hung |
| `db/<hash>.txt` | after a property that failed | minimal failing cases, replayed first on the next runs; forgotten after 3 passing runs in a row |

Write errors are ignored: a read-only directory never fails a test. `PROPTEST_DB=off` writes nothing.

**Trade-off of the failure database.** A bug you just saw is retried first, so a fix is checked at once, without waiting for random exploration to find it again. The cost: two runs of the same binary with the same seed can differ, because the second also replays saved failures. Use `PROPTEST_DB=off` when you need runs to be identical (benchmarks, comparing seeds). In CI the directory starts empty unless you cache it; caching it carries failures from one CI run to the next.

## What a replay needs

`PROPTEST_SEED=<n>` reproduces a run exactly when everything else that decides the inputs is the same:

- the same compiled test (same code, so the same property names and the same constants mined from it);
- the same settings that shape the inputs: `cases`, `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm`, `mineConstants`, including `PROPTEST_CASES`;
- a property that is deterministic: no clock, global state, threads or I/O that change its outcome. Otherwise the report says FLAKY.

The library's own random generator and hash are fixed (tested against reference vectors on every platform), so the same seed gives the same values on Linux, macOS and Windows, in debug and release. Generated values for a seed change between library versions only with a CHANGELOG entry under **Generation changes**.

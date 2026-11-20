# proptest

A **property-based testing library for the [Nim](https://nim-lang.org) programming language**, distributed as a Nimble package. State a rule, let the library generate the inputs, and get the **smallest** input that breaks it.

> **Status: v0.4, usable, not yet in the Nimble index.** Properties over built-in types and **your own objects with no generator code**, and stateful (model-based) tests, work today, with automatic shrinking, failures that are replayed first on the next run, coverage statistics and boundary-seeking exploration. The API may still change before 1.0. See [what works today](#what-works-today) and the [roadmap](docs/ROADMAP.md).

## Installation

```sh
nimble install https://github.com/kaio-souza/nim-proptest
```

Or from a clone: `nimble install` (or `nimble develop` to work on it). Requires Nim >= 2.2.4; no dependencies outside the standard library.

## Quick start

```nim
import proptest, std/[unittest, algorithm]

suite "sorting":
  test "sort is idempotent":
    forAll(xs in seq[int]):
      check xs.sorted.sorted == xs.sorted

  test "custom generators shrink for free":
    let evens = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 0)
    forAll(n in evens):
      check n < 100
```

The second property is wrong, and the report shows the **minimal** counterexample (100, not some random large even number) and how to replay it:

```
[FAILED] custom generators shrink for free
  Property 'quickstart.nim:20' falsified at case 8 (50 cases passed, 0 discarded).
  Counterexample (1 choices, 45 shrink executions):
    n = 100
  Error: [PropertyFailed] check failed: n < 100
      n was 100
  Location: quickstart.nim:21
  Replay: PROPTEST_SEED=17542877672211577899 ./quickstart
```

Runnable versions: [`examples/quickstart.nim`](examples/quickstart.nim) (with planted bugs), [`examples/tour.nim`](examples/tour.nim) (every feature below), [`examples/generators.nim`](examples/generators.nim) (the generators guide), [`examples/patterns.nim`](examples/patterns.nim) (the patterns cookbook) and [`examples/stateful.nim`](examples/stateful.nim) (the stateful tutorial); compiled and run in CI.

## Writing properties

### Variables: `name in source`

Each variable is a **type** (the generator is inferred) or a **generator value**:

```nim
forAll(xs in seq[int], s in string, flag in bool): ...     # types
forAll(n in ints(0, 100), word in strings("abc", 1, 5)): ... # generator values
```

Sources are evaluated once per property. `forAll(x: int)` cannot work: Nim parses a call whose arguments all look like `name: value` as an object constructor, before any macro runs.

### Assertions

Inside `forAll`, `check` and `require` are rewritten so that a failing case is caught silently and only the final, shrunk failure is reported (once). `doAssert`, any raised exception and `Defect`s (index errors, overflows...) count as failures too.

### Discarding cases: `assume`

```nim
forAll(a in ints(-1000, 1000), b in ints(-1000, 1000)):
  assume(b != 0)
  check a mod b == a - (a div b) * b
```

Too many discarded cases stop the run with a "gave up" report. Prefer generating valid values directly over `assume` and `filter`.

### Settings

Pass an `initSettings(...)` value among the arguments:

```nim
forAll(initSettings(cases = 500, maxShrinks = 5_000), x in int8): ...
```

| Setting | Default | Meaning |
|---|---|---|
| `cases` | 100 | Cases to run |
| `maxSteps` | 50 | Stateful tests: commands per sequence |
| `maxDepth` | 5 | Nesting of recursive data while exploring |
| `maxShrinks` | 2000 | Execution budget for shrinking each failure |
| `maxSize` | 100 | Size reached by the last case (bounds typical collection lengths) |
| `maxDiscardRatio` | 10 | Give up after `cases × ratio` discarded cases |
| `maxFailures` | 3 | Distinct failures reported per property |
| `maxChoices` | 8192 | Random choices per case; larger cases are discarded |
| `deadline` | 0 (off) | Per-case limit in ms: slower cases fail and are shrunk |
| `timeBudget` | 0 (none) | Exploration time limit in ms; stops gracefully and says so |
| `shrinkTimeBudget` | 0 (none) | Shrinking time limit per failure in ms; keeps the best so far |
| `edgeBias` | 0.25 | Share of edge-case proposals (limits, 0, 1, special floats, empty and single collections) |
| `mineConstants` | true | Integer constants of the property and the test file as boundary hints |
| `swarm` | true | Stateful tests: half of the sequences leave some commands out |
| `verbosity` | `vNormal` | `vQuiet`, `vNormal`, `vVerbose` (every case, every statistic), `vDebug` (shrink steps) |
| `suppress` | `{}` | Health checks to skip: `hcLargeData`, `hcFewDistinct`, `hcSlowGeneration` |
| `seed` | random | Fixes the run seed |
| `name` | `file:line` | Property name; derives its own seed |

| Environment variable | Effect |
|---|---|
| `PROPTEST_SEED` | Replays a run (printed in every failure report) |
| `PROPTEST_CASES` | Default `cases`, e.g. more in CI than locally |
| `PROPTEST_MAX_SHRINKS` | Default `maxShrinks` |
| `PROPTEST_DB` | Directory for local files: run seed, failure database (default `.proptest`), or `off` |
| `PROPTEST_DEADLINE` | Default `deadline` in ms (e.g. set it in CI) |
| `PROPTEST_TIME_BUDGET` | Default `timeBudget` in ms |
| `PROPTEST_VERBOSITY` | `quiet`, `normal`, `verbose` or `debug` |

## Generators

### Types, including yours

`x in T` generates any of these, nested in any way, with no code: integers of every width (including `range` types), `float`/`float32` (including NaN, infinities and -0.0), `bool`, `char`, `string`, enums, `seq`, `array`, `set`, `Option`, tuples, `Table`, `OrderedTable`, `HashSet`, and **your own types**:

```nim
type
  Kind = enum circle, rect
  Shape = object                  # fields need not be exported
    name: string
    case kind: Kind
    of circle: r: int
    of rect: w, h: int
  Node = ref object               # recursive: bounded automatically
    val: int
    left, right: Node

forAll(s in Shape, n in Node): ...
```

Objects, case objects, `distinct` and `ref` objects are derived field by field; a bug in one branch of a case object shrinks to that branch with the simplest fields, and a tree bug to the smallest tree. Integers reach `low(T)` and `high(T)` often, because bugs live there. Guide: [docs/GENERATORS.md](docs/GENERATORS.md).

### Combinators

| Generator | Values | Shrinks toward |
|---|---|---|
| `ints(lo, hi)`, `ints()`, `ints(lo, hi, near = [v])` | integers in `lo .. hi`; `near` proposes `v-1`, `v`, `v+1` | the value closest to 0 |
| `floats(lo, hi)`, `floats(allowNaN, allowInf)` | floats | 0.0 |
| `bools()` | `bool` | `false` |
| `chars(alphabet)` | characters of `alphabet` | its first character |
| `strings(alphabet, minLen, maxLen)` | strings | shorter, first characters |
| `seqs(g, minLen, maxLen)` | `seq` of values from `g` | shorter, simpler elements |
| `tables(k, v, ...)`, `hashSets(g, ...)` | containers of generated values | fewer, simpler entries |
| `alphanumeric`, `identifiers(maxLen)`, `unicodeStrings(minLen, maxLen)` | letters and digits, identifiers, valid UTF-8 over every plane | shorter, `a` |
| `frequency([(w, g), ...])` | one generator, chosen by weight | the first entry |
| `recursive(base, extend, maxDepth)` | trees: each level is `base` or one level deeper | `base` |
| `optionals(g)` | `Option` | `none` |
| `elements([a, b, c])` | one of the values | the first |
| `oneOf(g1, g2, ...)` | a value from one generator | the first generator |
| `constant(v)` | always `v` | |
| `g.map(f)`, `g.filter(pred)`, `g.flatMap(f)` | transformed values | through the original generator |
| `gen(T)` | the type-inferred generator as a value | |

You never write a shrinker: every generator, including `map`, `filter` and `flatMap` chains, shrinks automatically, and shrunk values still satisfy the filter.

### When fields must agree: write `arbitrary`

Derivation fills each field independently. When fields must agree (a start before an end), overload `arbitrary`; it always wins over derivation:

```nim
proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money =
  Money(cents: src.drawInt(0, 1_000_000),
        currency: elements(["USD", "EUR", "BRL"]).generate(src))
```

Or build a generator value with `newGen` from the draw primitives (`drawInt`, `drawBool`, `drawIndex`, `drawFloat`, `drawFloatRange`, `drawUpTo`). The only rule: a smaller choice must mean a simpler value, which every primitive already follows.

```nim
let sortedPairs = newGen(proc(src: ChoiceSource): (int, int) =
  let a = src.drawInt(-100, 100)
  let b = src.drawInt(a, 100)
  (a, b))
```

## Finding more bugs, and seeing what was tested

Passing says nothing about inputs that were never generated. Ways to check and to steer that (design: [ADR-0012](docs/decisions/0012-bug-finding-power.md); patterns: [docs/PATTERNS.md](docs/PATTERNS.md)):

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  classify(xs.len == 0, "empty")          # share of cases, printed after the run
  cover(20.0, xs.len >= 10, "ten or more") # fails if confidently below 20%
  label("len " & $min(xs.len, 3))         # cases by a computed text
  check ...
```

- **Boundaries.** Integers hit 0, 1, -1 and their type's limits; floats hit -0.0, NaN, infinities and subnormals; collections hit empty and single-element. Integer constants used in the property (`const openFor = 1000`), and integer literals of the test file, are proposed as `v - 1`, `v`, `v + 1`. For a boundary defined elsewhere: `ints(0, 2000, near = [openFor])`.
- **Swarm testing** (state machines): half of the sequences leave some commands out, so long runs of the others become likely (a bug that needs 12 increments with no reset: found on 3 of 100 seeds before, 97 of 100 with it).
- **Deadlines and budgets**: `deadline` makes a slow case a failure, shrunk to what makes it slow; `timeBudget` and `shrinkTimeBudget` stop early and say so.
- **Health checks** warn, with a fix, about data too large for `maxChoices`, input spaces smaller than `cases`, and generation dominating the run time.

The library's own bug-finding power is measured: [`benchmarks/b_find.nim`](benchmarks/b_find.nim) runs planted bugs on fixed seeds and CI fails if a detection rate drops.

## Results and failures

- **Inside a unittest `test`**: a failing property fails the test with one report.
- **Elsewhere**: `forAll` raises `PropertyError` (with `.propertyResult`), and `forAllResult(...)` (same arguments) returns the `PropertyResult` without raising.

| Status | Meaning |
|---|---|
| `psPassed` | every case passed |
| `psFailed` | at least one counterexample, re-run twice to confirm it |
| `psFlaky` | the minimal counterexample did not fail again: the property depends on time, global state, threads or I/O |
| `psGaveUp` | too many cases discarded by `assume` or `filter` |
| `psGeneratorError` | a generator raised: a bug in the generator, not in the code under test |
| `psInsufficientCoverage` | every case passed, but a `cover` requirement was confidently missed |

Up to `maxFailures` **distinct** bugs (different exception type or location) are reported separately, each shrunk on its own; shrinking never turns one bug into another.

**Reproducing**: every report prints `PROPTEST_SEED=<n>`; run the same binary with it to get the same cases and the same counterexample. The seed is also written to `.proptest/last-run` before the first case, so it survives a crash.

**Failures stay found**: each reproduced failure is saved in `.proptest/db/` and replayed **before any random case** on the next runs, so a fix is checked at once; an entry is forgotten after passing three runs in a row. `PROPTEST_DB=off` disables it. Add `.proptest/` to your `.gitignore` (CI may cache it). To pin a case for good, add `example(...)` (one value per variable, run first) or paste the `replayCommands` block of a stateful report into a test:

```nim
forAll(x in int, s in string, example(0, ""), example(-1, "a")): ...
```

## What works today

| Feature | Status |
|---|---|
| `forAll` / `forAllResult` with types and generator values | ✅ |
| Built-in type generators, combinators, custom `arbitrary` and `newGen` | ✅ |
| Integrated shrinking, multiple distinct failures, flaky detection | ✅ |
| `check`/`require` rewriting, `assume`, settings, environment variables | ✅ |
| `std/unittest` integration; standalone use | ✅ |
| Seed replay and crash breadcrumbs | ✅ (verified on Linux; macOS, Windows and JS pending in CI) |
| Stateful / model-based testing: `stateMachine`, shortest failing sequence printed as `replayCommands` code | ✅ |
| Generators derived for objects, case objects, `distinct`, `ref` and recursive types; `Table`, `HashSet`; `frequency`, `recursive`; Unicode strings | ✅ |
| Failure database (past failures replayed first), explicit `example(...)` | ✅ |
| `classify` / `cover` / `label`, stateful statistics, verbosity levels | ✅ |
| Edge-case bias, boundary hints (`near`, mined constants), swarm testing | ✅ |
| Per-case deadline, time budgets for runs and shrinking, health checks | ✅ |
| macOS and Windows CI, `unittest2` adapter, JSON report, stability policy | v0.5 |

## Known limitations

- **A case that never returns hangs the test**: `deadline` catches slow cases, but stopping one that loops forever needs a watchdog thread (planned after 1.0). The seed is already in `.proptest/last-run` to replay it.
- **Deep states are still rare**: a state that needs a long, specific path (five reopenings of a breaker in a row, each after the right wait) is seldom reached by random sequences. Write that path as a `replayCommands` test.
- **`--panics:on`**: `Defect`s end the process at the first failing case, so it cannot be shrunk (a compile-time warning says so).
- A broad `except CatchableError` inside the property body also catches the library's internal signals (`assume`, failed `check`); re-raise them or catch narrower types.
- The values generated for a seed may change between versions before 1.0 (always listed in the [CHANGELOG](CHANGELOG.md)), so an old seed may not replay after an upgrade.
- Generation speed is still above some targets (about 20 ns per `int` in release); see [measured performance](docs/ROADMAP.md#performance-against-the-initial-targets).

## Stateful testing

Random command sequences run against the real system and a simple model; after every step both must agree. A failure is reported as the **shortest** failing sequence, printed as Nim code to paste as a regression test. Full tutorial: [`docs/STATEFUL.md`](docs/STATEFUL.md).

```nim
type Model = object
  items: seq[int]

stateMachine BoundedQueue:
  model: Model()                            # fresh for every sequence
  setup:
    let q = newBoundedQueue[int](capacity = 3)

  command push(x in ints(-10, 10)):
    precondition: model.items.len < 3       # only valid sequences are generated
    run: q.push(x)
    update: model.items.add x

  command pop():
    precondition: model.items.len > 0
    run: q.pop()
    postcondition: result == model.items[0] # checked before `update`
    update: model.items.delete(0)

  invariant: q.len == model.items.len

test "queue matches its model":
  checkStateMachine(BoundedQueue)
```

With a queue whose `pop` is wrong after exactly 3 pushes and 1 pop:

```
  Shortest failing sequence (4 steps, 12 choices, 115 shrink executions):
    replayCommands BoundedQueue:
      push(0)
      push(0)
      push(0)
      pop()
  Error: [PropertyFailed] check failed: result == model.items[0]
      result was 1
      model.items[0] was 0
  Failed at step 4: pop()
```

Time is a command (`command advance(ms in ints(0, 2000))` moving a fake clock), so time-based bugs shrink to exact waits. `teardown:` always runs; arguments may be drawn from the model (`k in elements(model.keys)`).

## Quality

- 136 tests, passing on `orc`/`arc` × threads on/off × debug/release; ASan, UBSan and leak checks clean.
- The PRNG and hash match the authors' reference C implementations and the official FNV-1a vectors (golden tests).
- Value tests: each reference bug of the [SPEC](docs/SPEC.md) shrinks to its exact minimal counterexample; two independent bugs are both reported, and shrinking never slips from one bug to another (checked on 20 seeds).
- Deterministic gates in CI: shrinking each reference bug takes 9 to 214 executions (baseline in `benchmarks/baseline/shrink.json`); planted bugs must keep being found on as many seeds as the baseline (`benchmarks/baseline/find.json`); drawing choices and running stateful steps never allocate, and a test checks the same for static labels.
- First external user: the [`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-breaker) model test runs 1000 random sequences against its breaker.
- Every requirement has a row in [`docs/TRACEABILITY.md`](docs/TRACEABILITY.md), checked by `nimble trace`. Design decisions: [`docs/decisions/`](docs/decisions/README.md).

```sh
nimble test     # test suite
nimble gate     # deterministic performance gates
nimble bench    # timings (informational)
nimble trace    # traceability matrix
```

## License

[MIT](LICENSE)

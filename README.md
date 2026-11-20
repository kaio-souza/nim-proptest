# proptest

A **property-based testing library for the [Nim](https://nim-lang.org) programming language**, distributed as a Nimble package. State a rule, let the library generate the inputs, and get the **smallest** input that breaks it.

> **Status: v0.1, usable, not yet in the Nimble index.** Properties over built-in and custom types work today, with automatic shrinking and reproducible failures. Stateful testing comes in v0.2. The API may still change before 1.0. See [what works today](#what-works-today) and the [roadmap](docs/ROADMAP.md).

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
  Property 'quickstart.nim:20' falsified after 13 passing cases (0 discarded).
  Counterexample (1 choices, 45 shrink executions):
    n = 100
  Error: [PropertyFailed] check failed: n < 100
      n was 100
  Location: quickstart.nim:21
  Replay: PROPTEST_SEED=17542877672211577899 ./quickstart
```

Runnable versions: [`examples/quickstart.nim`](examples/quickstart.nim) (with planted bugs) and [`examples/tour.nim`](examples/tour.nim) (every feature below; compiled and run in CI).

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
| `maxShrinks` | 2000 | Execution budget for shrinking each failure |
| `maxSize` | 100 | Size reached by the last case (bounds typical collection lengths) |
| `maxDiscardRatio` | 10 | Give up after `cases × ratio` discarded cases |
| `maxFailures` | 3 | Distinct failures reported per property |
| `maxChoices` | 8192 | Random choices per case; larger cases are discarded |
| `seed` | random | Fixes the run seed |
| `name` | `file:line` | Property name; derives its own seed |

| Environment variable | Effect |
|---|---|
| `PROPTEST_SEED` | Replays a run (printed in every failure report) |
| `PROPTEST_CASES` | Default `cases`, e.g. more in CI than locally |
| `PROPTEST_MAX_SHRINKS` | Default `maxShrinks` |
| `PROPTEST_DB` | Directory for local files (default `.proptest`), or `off` |

## Generators

### Built-in types

Integers of every width (including `range` types), `float`/`float32` (including NaN, infinities and -0.0), `bool`, `char`, `string` (printable ASCII), enums, `seq[T]`, `array[N, T]`, `set[T]`, `Option[T]` and tuples, nested in any way. Integers reach `low(T)` and `high(T)` often, because bugs live there.

### Combinators

| Generator | Values | Shrinks toward |
|---|---|---|
| `ints(lo, hi)`, `ints()` | integers in `lo .. hi` | the value closest to 0 |
| `floats(lo, hi)`, `floats(allowNaN, allowInf)` | floats | 0.0 |
| `bools()` | `bool` | `false` |
| `chars(alphabet)` | characters of `alphabet` | its first character |
| `strings(alphabet, minLen, maxLen)` | strings | shorter, first characters |
| `seqs(g, minLen, maxLen)` | `seq` of values from `g` | shorter, simpler elements |
| `optionals(g)` | `Option` | `none` |
| `elements([a, b, c])` | one of the values | the first |
| `oneOf(g1, g2, ...)` | a value from one generator | the first generator |
| `constant(v)` | always `v` | |
| `g.map(f)`, `g.filter(pred)`, `g.flatMap(f)` | transformed values | through the original generator |
| `gen(T)` | the type-inferred generator as a value | |

You never write a shrinker: every generator, including `map`, `filter` and `flatMap` chains, shrinks automatically, and shrunk values still satisfy the filter.

### Your own types

Overload `arbitrary`, and `forAll(m in Money)` works:

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

Up to `maxFailures` **distinct** bugs (different exception type or location) are reported separately, each shrunk on its own; shrinking never turns one bug into another.

**Reproducing**: every report prints `PROPTEST_SEED=<n>`; run the same binary with it to get the same cases and the same counterexample. The seed is also written to `.proptest/last-run` before the first case, so it survives a crash. Add `.proptest/` to your `.gitignore`.

## What works today

| Feature | Status |
|---|---|
| `forAll` / `forAllResult` with types and generator values | ✅ |
| Built-in type generators, combinators, custom `arbitrary` and `newGen` | ✅ |
| Integrated shrinking, multiple distinct failures, flaky detection | ✅ |
| `check`/`require` rewriting, `assume`, settings, environment variables | ✅ |
| `std/unittest` integration; standalone use | ✅ |
| Seed replay and crash breadcrumbs | ✅ (verified on Linux; macOS, Windows and JS pending in CI) |
| Stateful / model-based testing | v0.2 |
| Object generators derived automatically (no `arbitrary` needed) | v0.3 |
| `classify` / `cover`, health checks beyond filters, per-case deadline | v0.3 |
| Failure database (replay past failures first), `unittest2` adapter, JSON report | v0.4 |

## Known limitations

- **No per-case timeout yet**: a case that loops forever hangs the test. The seed is already in `.proptest/last-run` to replay it.
- **`--panics:on`**: `Defect`s end the process at the first failing case, so it cannot be shrunk (a compile-time warning says so).
- A broad `except CatchableError` inside the property body also catches the library's internal signals (`assume`, failed `check`); re-raise them or catch narrower types.
- The values generated for a seed may change between versions before 1.0 (always listed in the [CHANGELOG](CHANGELOG.md)), so an old seed may not replay after an upgrade.
- Generation speed is still above some targets (about 20 ns per `int` in release); see [measured performance](docs/ROADMAP.md#performance-against-the-initial-targets).

## Stateful testing (planned for v0.2)

Random command sequences will run against the real system and a simple model; a failure is reported as the shortest failing sequence, printed as Nim code. Design sketch, not working code:

```nim
stateMachine BoundedQueue:
  model: Model
  system: newBoundedQueue[int](capacity = 3)

  command push(x: int):
    precondition: model.items.len < 3
    run: system.push(x)
    update: model.items.add x

  command pop():
    precondition: model.items.len > 0
    run: system.pop()
    postcondition: result == model.items[0]   # checked before `update`
    update: model.items.delete(0)

  invariant: system.len == model.items.len
```

## Quality

- 72 tests, passing on `orc`/`arc` × threads on/off × debug/release; ASan, UBSan and leak checks clean.
- The PRNG and hash match the authors' reference C implementations and the official FNV-1a vectors (golden tests).
- Value tests: each reference bug of the [SPEC](docs/SPEC.md) shrinks to its exact minimal counterexample; two independent bugs are both reported, and shrinking never slips from one bug to another (checked on 20 seeds).
- Deterministic gates in CI: shrinking each reference bug takes 17 to 113 executions (baseline in `benchmarks/baseline/shrink.json`), and drawing choices never allocates.
- Every requirement has a row in [`docs/TRACEABILITY.md`](docs/TRACEABILITY.md), checked by `nimble trace`. Design decisions: [`docs/decisions/`](docs/decisions/README.md).

```sh
nimble test     # test suite
nimble gate     # deterministic performance gates
nimble bench    # timings (informational)
nimble trace    # traceability matrix
```

## License

[MIT](LICENSE)

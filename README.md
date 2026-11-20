# proptest

A **property-based testing library for the [Nim](https://nim-lang.org) programming language**, distributed as a Nimble package. State a rule, let the library generate the inputs, and get the **smallest** input that breaks it.

> **Status: design phase.** The package is not published yet and the API below is a sketch of the intended usage, not working code. See [`docs/SPEC.md`](docs/SPEC.md) and [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Installation (planned)

```sh
nimble install proptest
```

Requires Nim >= 2.2.4. No dependencies outside the Nim standard library. Works with `std/unittest`, `unittest2` or standalone.

## Intended usage

```nim
import proptest, std/[unittest, algorithm]

suite "sorting":
  test "sort is idempotent":
    forAll(xs: seq[int]):
      check xs.sorted.sorted == xs.sorted

  test "custom generators shrink for free":
    let evens = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 0)
    forAll(n = evens):
      check process(n) >= 0
```

On failure:

```
[FAILED] custom generators shrink for free
  Falsified after 37 cases and 12 shrinks:
    n = 100
  Error: AssertionDefect: process(n) >= 0
  Replay: PROPTEST_SEED=8412093 nim r tests/t_process.nim
```

### Stateful testing (sketch)

Random command sequences run against the real system and a simple model; a failure is reported as the shortest failing sequence, printed as Nim code.

```nim
import proptest, proptest/stateful, std/[unittest, deques]

type Model = object
  items: seq[int]            # the model: a plain seq

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

test "bounded queue behaves like a seq":
  checkStateMachine(BoundedQueue)
```

On failure:

```
Falsified after 58 sequences and 41 shrinks. Minimal sequence:
  var q = newBoundedQueue[int](capacity = 3)
  q.push(0)
  q.push(0)
  q.push(1)
  doAssert q.pop() == 0    # got 1
```

## Planned highlights

- **Integrated shrinking**: generators built with `map`, `filter` and `flatMap` shrink automatically; you never write a shrinker.
- **Stateful / model-based testing** as a first-class feature.
- **Generators from types**, including objects, through compile-time derivation.
- **Failures you can trust**: every counterexample is re-run before it is reported, shrinking never slips to a different bug, and flaky properties are called out as flaky.
- **Reproducible anywhere**: an own versioned PRNG means a seed replays identically on any Nim version, OS and backend; the seed is saved before the first case, so even crashes and hangs can be replayed.
- **Fast enough for every save**: no allocation per generated choice, closure-free built-in generators, and CI gates on deterministic metrics instead of noisy timings.
- **Coverage assertions** (`cover`) to prove generators reach the cases you care about.
- **Zero dependencies**; works with `std/unittest`, `unittest2` or standalone.

## License

[MIT](LICENSE)

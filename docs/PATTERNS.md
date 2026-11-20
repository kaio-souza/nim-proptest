# Property patterns cookbook

The hard part of property-based testing is rarely the library. It is deciding **what to check** when you cannot write down the expected output for a random input. These patterns cover most real properties. Each one has a passing version in [`examples/patterns.nim`](../examples/patterns.nim), compiled and run in CI.

## Round trip

If one function undoes another, composing them gives the input back. Use it for serialization, parsing, encoding, compression and conversions.

```nim
forAll(xs in seq[int]):
  check decode(encode(xs)) == xs
```

It catches lost precision, escaping bugs and empty or edge-case inputs (`@[]`, `low(int)`) that hand-written examples skip.

## Oracle (reference implementation)

Compare the code with a slower, obviously correct version: an optimized function against a naive loop, a new implementation against the old one, a cache against direct computation.

```nim
forAll(xs in seq[int]):
  check fastSum(xs) == oracleSum(xs)
```

A stateful test is this same pattern applied to a sequence of operations: the model is the oracle ([STATEFUL.md](STATEFUL.md)).

## Invariant

When the exact output is unknown, some of its properties are not: a sort keeps the length and orders the elements; a balanced tree stays balanced; a total stays non-negative.

```nim
forAll(xs in seq[int]):
  let s = xs.sorted
  check s.len == xs.len
  for i in 1 ..< s.len: check s[i - 1] <= s[i]
```

## Idempotence

Applying the operation twice is the same as applying it once: normalizing, deduplicating, formatting, setting a flag, an HTTP `PUT`.

```nim
forAll(xs in seq[int]):
  check dedupe(dedupe(xs)) == dedupe(xs)
```

## Metamorphic relation

You do not know `f(x)`, but you know how it changes when `x` changes in a known way. Adding an element adds it to the sum, shuffling does not change a set, scaling the input scales a linear output.

```nim
forAll(xs in seqs(ints(-1000, 1000)), k in ints(-1000, 1000)):
  check oracleSum(xs & @[k]) == oracleSum(xs) + k
```

Bound the values when the relation can overflow: an overflow is a real finding, but not the one this property is about.

## Never crashes

The weakest property and often the most productive one: for any input, the code either returns or raises the error it documents. `Defect`s (index out of bounds, overflow, nil access) and unexpected exceptions are failures.

```nim
forAll(s in string):
  try: discard parseJson(s)
  except JsonParsingError, ValueError: discard
```

## Boundaries

Bugs live where the domain changes: the last retry, a timeout of exactly 1000 ms, a capacity of 3. Integer generators already try `0`, `1`, `-1` and the type's limits. For your own boundaries:

- **Constants are mined automatically.** Integer literals and `const` values used in the property, and integer literals anywhere in the test file, are proposed as `v - 1`, `v` and `v + 1` while exploring ([ADR-0012](decisions/0012-bug-finding-power.md)). `initSettings(mineConstants = false)` turns this off.
- **Say it explicitly** with `ints(lo, hi, near = [...])` when the boundary comes from elsewhere (another module, a configuration file):

```nim
forAll(attempt in ints(0, 100, near = [maxRetries])):
  if attempt < maxRetries: check backoffMs(attempt) >= 100
  else: check backoffMs(attempt) == -1
```

Neither changes shrinking: the reported counterexample is still the simplest one.

## Coverage: make sure the interesting cases happen

A property that passes says nothing about inputs that were never generated. `classify` shows the distribution; `cover` turns a requirement into a check:

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  cover(5.0, xs.len == 0, "empty")
  cover(20.0, xs.len >= 10, "ten or more")
  check ...
```

```
Property 'patterns.nim:69' passed 300 cases.
  Statistics (300 cases):
     14.0%  empty  (cover: 5.0% required)
     61.0%  ten or more  (cover: 20.0% required)
```

`cover` fails the property only when the observed share is **confidently** below the requirement (the upper bound of a 95% Wilson interval). With too few cases to be sure it prints a warning and suggests raising `cases`. `label($x.kind)` counts cases by a computed text. In a state machine, `cover` counts sequences, and the report also lists how often each command ran and how often its precondition blocked it.

## When a property is hard to find

- Start with **never crashes**, then add **round trip** and **invariants**: they need no expected values.
- If you have two implementations, or an old and a new version, use **oracle**.
- If the system has state (a cache, a queue, a connection, a circuit breaker), use a **state machine**.
- If the property is true only for some inputs, generate those inputs directly. `assume` and `filter` discard cases, and too many discards stop the run with a message saying so.

# Writing generators

Most properties need no generator code: types are generated from their definition. This guide covers what is automatic, when to write a generator, and the one rule every generator must follow. Every snippet is in [`examples/generators.nim`](../examples/generators.nim), compiled and run in CI. Design: [ADR-0013](decisions/0013-derived-generators.md).

## 1. Nothing to write

`forAll(x in T)` works for:

| `T` | Generated | Shrinks toward |
|---|---|---|
| integers, `range`, floats, `bool`, `char`, enums | the whole domain, edge cases often | 0, `false`, the first value |
| `string`, `seq`, `array`, `set`, tuples, `Option` | element by element | shorter, simpler elements, `none` |
| `Table`, `OrderedTable`, `HashSet` | entries from their types | fewer, simpler entries |
| **objects** | field by field, **private fields included** | every field simplest |
| **case objects** | a branch, then its fields | the first branch |
| **`distinct` types** | from their base type | the base type's simplest value |
| **`ref` objects** | `nil` or a new object | `nil` |
| **recursive types** | trees bounded by `maxDepth` (default 5) | the smallest tree |

```nim
type
  Currency = enum usd, eur, brl
  Payment = object
    id: int64
    amount: int
    currency: Currency
    note: string
  EventKind = enum paid, refunded, cancelled
  Event = object
    at: int
    case kind: EventKind
    of paid: payment: Payment
    of refunded: refundOf: int64
    of cancelled: reason: string
  Expr = ref object
    case op: char
    of '+', '*': lhs, rhs: Expr
    else: value: int

forAll(p in Payment, e in Event, x in Expr): ...
```

Types from other modules work without exporting their fields. A field whose type has no generator (a `proc`, a `ptr`, a lock) stops compilation with a message naming the field. A case object whose discriminant is a `range` type cannot be derived with Nim 2.2.4, and the compiler message says so: use an enum, or write `arbitrary`.

Recursive data are bounded while exploring: `ref` fields are more often `nil` the deeper they are, and nested collections get shorter, so trees stay small (`initSettings(maxDepth = ...)` changes the bound). Shrinking is not affected.

## 2. When random fields make invalid objects: write `arbitrary`

Derivation fills each field independently. When fields must agree (a start before an end, a total equal to the sum of the lines, an ID that exists in a list), write `arbitrary` for the type. It always wins over derivation, and every property using the type gets it.

```nim
type DateRange = object
  first, last: int            # invariant: first <= last

proc arbitrary(src: ChoiceSource; t: typedesc[DateRange]): DateRange =
  let first = src.drawInt(0, 36_500)
  let length = src.drawInt(0, 365)
  DateRange(first: first, last: first + length)
```

**Build valid values; do not filter invalid ones.** `filter` and `assume` throw cases away. Above a small rejection rate the run slows down, and then stops with a message suggesting this. Drawing `length` instead of `last` makes every value valid.

## 3. The one rule: a smaller choice must mean a simpler value

Generators never see random numbers, only **choices**: unsigned integers drawn from the choice source. Shrinking makes the recorded choices smaller and shorter, then replays them ([ADR-0001](decisions/0001-integrated-shrinking-on-choice-sequences.md)). For this to give simpler values, choice 0 must be the simplest value, and smaller choices simpler ones. Every draw primitive already follows the rule:

| Primitive | Choice 0 gives |
|---|---|
| `drawInt(lo, hi)` | the value of `lo .. hi` closest to 0 |
| `drawBool()` | `false` |
| `drawIndex(n)` | 0: put the simplest alternative first |
| `drawFloat`, `drawFloatRange` | 0.0 |
| `initMany` + `more` | no more elements |
| `drawRune()` | `'a'` |

So the rule comes down to two choices of yours:

- **Put the simplest alternative first**: `elements([common, rare])`, `frequency([(9, usual), (1, unusual)])`, an enum whose first value is the default.
- **Draw what makes the value valid**, as `length` above, rather than drawing freely and fixing afterwards: a "fix-up" can turn a smaller choice into a bigger value.

## 4. Generator values: combinators

When the type is not enough (a range, an alphabet, a distribution), pass a generator value instead of a type:

```nim
let prices = frequency([(8, ints(1, 10_000)), (1, constant(0)), (1, ints(1_000_000, 10_000_000))])
let usernames = identifiers(maxLen = 12)
let labels = tables(identifiers(8), ints(0, 99), maxLen = 5)

forAll(price in prices, user in usernames, l in labels): ...
```

| Combinator | Values |
|---|---|
| `ints(lo, hi, near = [...])` | integers; `near` lists boundaries of your domain to try often |
| `frequency([(w, g), ...])` | one of the generators, by weight |
| `elements([...])`, `oneOf(...)`, `constant(v)` | fixed choices |
| `strings(alphabet, ...)` (e.g. `strings(alphanumeric, ...)`), `identifiers(...)`, `unicodeStrings(...)` | text, including valid UTF-8 over every plane |
| `seqs`, `tables`, `hashSets`, `optionals` | containers of generated values |
| `uniqueSeqs(g, ...)`, `sortedSeqs(g, ...)` | sequences of distinct values, or in ascending order |
| `sized(proc(n: int): Gen[T] = ...)`, `g.resize(n)` | a generator that depends on the current size, or a fixed size |
| `g.map(f)`, `g.filter(p)`, `g.flatMap(f)` | transformations (shrinking goes through them) |
| `recursive(base, extend, maxDepth)` | trees: each level is `base` or one level deeper |
| `newGen(proc(src: ChoiceSource): T = ...)` | anything, from draw primitives |

Recursive generators take the generator of the level below:

```nim
let exprs = recursive(leaf(), proc(inner: Gen[Expr]): Gen[Expr] =
  newGen(proc(src: ChoiceSource): Expr =
    let times = src.drawBool()           # false ('+') is the simpler one
    let (l, r) = (inner.generate(src), inner.generate(src))
    if times: Expr(op: '*', lhs: l, rhs: r) else: Expr(op: '+', lhs: l, rhs: r)))
```

### Distinct and sorted collections

Two shapes come up often enough to have their own generators. Both shrink like `seqs` and keep their shape while shrinking:

```nim
forAll(ids in uniqueSeqs(ints(1, 10_000), maxLen = 20)):   # no duplicates
  check buildIndex(ids).len == ids.len

forAll(xs in sortedSeqs(ints(), minLen = 1)):              # ascending
  check lowerBound(xs, xs[0]) == 0                        # std/algorithm
```

`uniqueSeqs` draws again when a value repeats an earlier one, up to `maxTries` (100) times per element, then discards the case like a `filter`. With few distinct values (`uniqueSeqs(bools(), minLen = 3)`) the property gives up and says so. `sortedSeqs` sorts after generating, so it never discards. Prefer them over `assume(xs.isSorted)`, which [gives up](TROUBLESHOOTING.md#gave-up-after-n-passing-cases).

### The size: `sized` and `resize`

The size grows from 0 at the first case to `maxSize` at the last. Built-in collections and integers already follow it; `sized` gives it to your own generator, and `resize` fixes it for one generator:

```nim
# A square matrix whose side follows the size.
let matrices = sized(proc(n: int): Gen[seq[seq[int]]] =
  let side = max(1, n div 10)
  seqs(seqs(ints(0, 9), side, side), side, side))

# Short lists, whatever the size of the case.
let shortLists = gen(seq[int]).resize(3)
```

The size `sized` sees is recorded with the case, so shrinking and replay see the same size (shrinking may lower it, which makes values simpler). Use it as an upper bound or a scale, as above.

## 5. Pinning known cases

`example(...)` runs fixed values before any random case, one per variable. Use it for a regression that must never come back, or a case the specification names:

```nim
forAll(user in usernames, example("root"), example("a")):
  check user.len >= 1
```

Failures are also saved in `.proptest/db/` and replayed first on the next runs, until they pass three times in a row ([ADR-0014](decisions/0014-failure-database-and-examples.md)).

## 6. Printing values

Reports print inputs with `$` when it exists, and stateful reports print command arguments as Nim code (`showCode`): objects as `Payment(id: 0, amount: 0, ...)`, tables as `{1: "a"}.toTable`, `ref` values with `nil` where empty. If a type's `$` is not readable or its constructor is not visible where the report will be pasted, overload `show` or `showCode` for it.

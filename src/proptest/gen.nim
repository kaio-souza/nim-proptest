## Generators.
##
## Two forms read from the same `ChoiceSource` (ADR-0007):
##
## - `arbitrary(src, T)`: generator inferred from a type. Expanded into direct
##   calls, no closure. Add an overload for your own types:
##   `proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money`.
## - `Gen[T]`: a value built with combinators (`ints`, `map`, `filter`...),
##   created once per property and shared by every case.

import std/options
import choices

export options

# ------------------------------------------------------- type-inferred (G2/G3)

proc arbitrary*(src: ChoiceSource; t: typedesc[bool]): bool =
  src.drawBool()

proc arbitrary*[T: SomeInteger](src: ChoiceSource; t: typedesc[T]): T =
  ## Any value of `T`, including `low(T)` and `high(T)`; shrinks toward 0.
  src.drawInt(low(T), high(T))

proc arbitrary*[T: SomeFloat](src: ChoiceSource; t: typedesc[T]): T =
  ## Any float, including NaN, infinities and -0.0. Use `floats` to exclude them.
  T(src.drawFloat())

proc arbitrary*(src: ChoiceSource; t: typedesc[char]): char =
  ## Any byte, printable ASCII first.
  charOrder[src.drawIndex(256)]

proc enumValues[T: enum](): seq[T] {.compileTime.} =
  for e in T: result.add e

proc arbitrary*[T: enum](src: ChoiceSource; t: typedesc[T]): T =
  ## Any declared value; shrinks toward the first one.
  const values = enumValues[T]()
  values[src.drawIndex(values.len)]

proc arbitrary*(src: ChoiceSource; t: typedesc[string]): string =
  ## Printable ASCII string; shrinks toward shorter strings and simpler characters.
  var m = src.initMany(0, high(int))
  while src.more(m):
    result.add printableAlphabet[src.drawIndex(printableAlphabet.len)]

proc arbitrary*[T](src: ChoiceSource; t: typedesc[seq[T]]): seq[T] =
  mixin arbitrary
  var m = src.initMany(0, high(int))
  while src.more(m):
    result.add src.arbitrary(T)

proc arbitrary*[N, T](src: ChoiceSource; t: typedesc[array[N, T]]): array[N, T] =
  mixin arbitrary
  for x in result.mitems:
    x = src.arbitrary(T)

proc arbitrary*[T](src: ChoiceSource; t: typedesc[set[T]]): set[T] =
  mixin arbitrary
  var m = src.initMany(0, high(int))
  while src.more(m):
    result.incl src.arbitrary(T)

proc arbitrary*[T](src: ChoiceSource; t: typedesc[Option[T]]): Option[T] =
  ## `none` is the simplest value.
  mixin arbitrary
  if src.drawBool(0.8): some(src.arbitrary(T)) else: none(T)

proc arbitrary*[T: tuple](src: ChoiceSource; t: typedesc[T]): T =
  mixin arbitrary
  for f in result.fields:
    f = src.arbitrary(typeof(f))

# ---------------------------------------------------------------- Gen[T] (G1)

type
  Gen*[T] = object
    ## A generator value. Build with combinators or `newGen`.
    run: proc(src: ChoiceSource): T {.closure.}

proc newGen*[T](fn: proc(src: ChoiceSource): T): Gen[T] =
  ## Custom generator from a plain proc over the choice source (C7). It
  ## shrinks automatically as long as smaller choices mean simpler values.
  Gen[T](run: fn)

proc generate*[T](g: Gen[T]; src: ChoiceSource): T {.inline.} =
  ## Draws one value.
  g.run(src)

proc gen*[T](t: typedesc[T]): Gen[T] =
  ## The type-inferred generator of `T` as a `Gen[T]`, to combine it.
  mixin arbitrary
  newGen(proc(src: ChoiceSource): T = src.arbitrary(T))

# ------------------------------------------- `forAll(x in source)` plumbing

type
  TypeGen*[T] = object
    ## Marker for "generate from the type": zero size, no closure (PF5).

template hoist*(t: typedesc): untyped =
  ## Evaluated once per property: a type becomes a `TypeGen` marker...
  TypeGen[t]()

proc hoist*[T](g: Gen[T]): Gen[T] {.inline.} =
  ## ...and a generator value is kept as is.
  g

proc drawFrom*[T](src: ChoiceSource; g: TypeGen[T]): T {.inline.} =
  ## Direct call to the type-inferred generator.
  mixin arbitrary
  src.arbitrary(T)

proc drawFrom*[T](src: ChoiceSource; g: Gen[T]): T {.inline.} =
  g.run(src)

# ----------------------------------------------------------------- combinators

proc map*[T, U](g: Gen[T]; f: proc(x: T): U): Gen[U] =
  newGen(proc(src: ChoiceSource): U = f(g.run(src)))

proc filter*[T](g: Gen[T]; pred: proc(x: T): bool; maxTries = 100): Gen[T] =
  ## Keeps values satisfying `pred`. After `maxTries` rejections in one case
  ## the case is discarded; too many discards stop the run with a message
  ## that points at the filter (C1). Prefer constructive generators.
  newGen(proc(src: ChoiceSource): T =
    for _ in 0 ..< maxTries:
      let v = g.run(src)
      if pred(v): return v
    raise newException(FilterExhausted,
      "filter rejected " & $maxTries & " values in a row"))

proc flatMap*[T, U](g: Gen[T]; f: proc(x: T): Gen[U]): Gen[U] =
  ## The next generator depends on a generated value.
  newGen(proc(src: ChoiceSource): U = f(g.run(src)).run(src))

proc constant*[T](value: T): Gen[T] =
  newGen(proc(src: ChoiceSource): T = value)

proc elements*[T](values: openArray[T]): Gen[T] =
  ## One of `values`; shrinks toward the first.
  if values.len == 0:
    raise newException(ValueError, "elements: no values")
  let vs = @values
  newGen(proc(src: ChoiceSource): T = vs[src.drawIndex(vs.len)])

proc oneOf*[T](gens: varargs[Gen[T]]): Gen[T] =
  ## Picks one generator per value; shrinks toward the first generator.
  if gens.len == 0:
    raise newException(ValueError, "oneOf: no generators")
  let gs = @gens
  newGen(proc(src: ChoiceSource): T = gs[src.drawIndex(gs.len)].run(src))

proc bools*(): Gen[bool] =
  newGen(proc(src: ChoiceSource): bool = src.drawBool())

proc ints*[T: SomeInteger](lo, hi: T; near: openArray[T] = []): Gen[T] =
  ## Integers in `lo .. hi`; shrinks toward the value closest to zero.
  ## `near` lists boundaries of your domain (a timeout, a capacity): while
  ## exploring, `v - 1`, `v` and `v + 1` are proposed now and then (G8,
  ## ADR-0012). Shrinking is unchanged.
  if lo > hi:
    raise newException(ValueError, "ints: lo > hi")
  if near.len == 0:
    return newGen(proc(src: ChoiceSource): T = src.drawInt(lo, hi))
  var hints: seq[int64]
  for v in near:
    when T is uint64 or T is uint:
      if uint64(v) <= uint64(high(int64)): hints.add int64(v)
    else:
      hints.add int64(v)
  newGen(proc(src: ChoiceSource): T = src.drawInt(lo, hi, hints))

proc ints*(): Gen[int] =
  ## Any `int`.
  ints(low(int), high(int))

proc floats*(allowNaN = true; allowInf = true): Gen[float] =
  ## Any float; NaN and infinities can be excluded (G9).
  newGen(proc(src: ChoiceSource): float = src.drawFloat(allowNaN, allowInf))

proc floats*(lo, hi: float): Gen[float] =
  ## Finite floats in `lo .. hi` (G9).
  if not (lo <= hi):
    raise newException(ValueError, "floats: invalid range")
  newGen(proc(src: ChoiceSource): float = src.drawFloatRange(lo, hi))

proc chars*(alphabet = printableAlphabet): Gen[char] =
  ## Characters of `alphabet`; shrinks toward its first character.
  if alphabet.len == 0:
    raise newException(ValueError, "chars: empty alphabet")
  newGen(proc(src: ChoiceSource): char = alphabet[src.drawIndex(alphabet.len)])

proc strings*(alphabet = printableAlphabet; minLen = 0; maxLen = high(int)): Gen[string] =
  ## Strings over `alphabet` with `minLen .. maxLen` characters.
  if alphabet.len == 0 or minLen < 0 or maxLen < minLen:
    raise newException(ValueError, "strings: invalid alphabet or lengths")
  newGen(proc(src: ChoiceSource): string =
    var m = src.initMany(minLen, maxLen)
    while src.more(m):
      result.add alphabet[src.drawIndex(alphabet.len)])

proc seqs*[T](g: Gen[T]; minLen = 0; maxLen = high(int)): Gen[seq[T]] =
  ## Sequences of values from `g` with `minLen .. maxLen` elements.
  if minLen < 0 or maxLen < minLen:
    raise newException(ValueError, "seqs: invalid lengths")
  newGen(proc(src: ChoiceSource): seq[T] =
    var m = src.initMany(minLen, maxLen)
    while src.more(m):
      result.add g.run(src))

proc optionals*[T](g: Gen[T]): Gen[Option[T]] =
  ## `none` or a value from `g`; shrinks toward `none`.
  newGen(proc(src: ChoiceSource): Option[T] =
    if src.drawBool(0.8): some(g.run(src)) else: none(T))

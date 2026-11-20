## Tour of the API: every snippet of the README "Writing properties" section.
## All properties here pass; CI compiles and runs this file.

import proptest, std/[unittest, algorithm, strutils]

# --- Your own type: overload `arbitrary` --------------------------------------

type Money = object
  cents: int
  currency: string

proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money =
  ## Built from other generators: shrinks automatically (toward 0 USD).
  Money(cents: src.drawInt(0, 1_000_000),
        currency: elements(["USD", "EUR", "BRL"]).generate(src))

# --- A custom generator from draw primitives ---------------------------------

let sortedPairs = newGen(proc(src: ChoiceSource): (int, int) =
  let a = src.drawInt(-100, 100)
  let b = src.drawInt(a, 100)      # depends on `a`: still shrinks correctly
  (a, b))

proc parsesBack(n: int): bool =
  ## A property used outside a unittest test.
  let r = forAllResult(initSettings(cases = 200), x in ints(-n, n)):
    check parseInt($x) == x
  r.passed

suite "tour":
  test "types are generators":
    forAll(xs in seq[int], s in string, flag in bool):
      check xs.reversed.reversed == xs
      check s.len >= 0 or flag

  test "generator values and combinators":
    let evens = ints(0, 1_000).map(proc(x: int): int = 2 * x)
    forAll(n in evens, word in strings("abc", 1, 5), p in sortedPairs):
      check n mod 2 == 0
      check word.len in 1 .. 5
      check p[0] <= p[1]

  test "custom types":
    forAll(m in Money):
      check m.cents >= 0
      check m.currency in ["USD", "EUR", "BRL"]

  test "assume discards cases":
    # (With `a in int, b in int` this property finds a real bug: low(int) div -1
    # overflows. Bounded ranges keep the example about `assume`.)
    forAll(a in ints(-1000, 1000), b in ints(-1000, 1000)):
      assume(b != 0)
      check a mod b == a - (a div b) * b

  test "settings":
    forAll(initSettings(cases = 500, maxShrinks = 5_000), x in int8):
      check int(x) in -128 .. 127

  test "results outside a test":
    check parsesBack(1_000_000)

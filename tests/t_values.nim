## Value tests (SPEC Part IV): each differentiator is proven with a planted
## bug that example-based tests easily miss, and the exact minimal
## counterexample the library must report.

import std/[unittest, strutils]
import proptest

proc buggyReverse(xs: seq[int]): seq[int] =
  ## Planted bug: drops the last element when there are more than 3.
  for i in countdown(xs.high, 0): result.add xs[i]
  if xs.len > 3: result.setLen(result.len - 1)

proc input(r: PropertyResult; failure = 0; variable = 0): string =
  r.failures[failure].inputs[variable].value

suite "value tests":
  test "V-S1: integrated shrinking reduces a list bug to the minimal list":
    # Example-based tests with 0 to 3 elements pass; the property finds the
    # bug and reports the simplest list that shows it.
    check buggyReverse(@[1, 2, 3]).buggyReverse == @[1, 2, 3]
    let r = forAllResult(initSettings(seed = 1), xs in seq[int]):
      check buggyReverse(buggyReverse(xs)) == xs
    check r.status == psFailed
    check r.input == "@[0, 0, 0, 0]"

  test "V-S1/C1: shrinking works through filter and map without a custom shrinker":
    let evens = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 0)
    let r = forAllResult(initSettings(seed = 2), n in evens):
      check n < 100
    check r.input == "100"
    let labels = ints(0, 1_000).map(proc(x: int): string = "#" & $x)
    let r2 = forAllResult(initSettings(seed = 3), s in labels):
      check s.len < 4
    check r2.input == "\"#100\""

  test "V-S2: shrunk values still satisfy the generator's filter":
    let odds = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 1)
    let r = forAllResult(initSettings(seed = 4), n in odds):
      check n < 50
    check r.input == "51"

  test "V-S5/Q5: integers shrink to the exact boundary of the bug":
    # Dogfooding: for every threshold t, a bug triggered by x > t must be
    # reported as exactly t + 1.
    forAll(initSettings(seed = 5, cases = 50), t in ints(0, 1_000_000)):
      let r = forAllResult(initSettings(seed = 6, name = "inner"), x in int):
        check x <= t
      check r.status == psFailed
      check r.input == $(t + 1)

  test "V-S5: strings shrink to the shortest, simplest string":
    let r = forAllResult(initSettings(seed = 7), s in string):
      check 'z' notin s
    check r.input == "\"z\""
    let r2 = forAllResult(initSettings(seed = 8), s in string):
      check s.len < 3
    check r2.input == "\"aaa\""

  test "V-RL3: a property that fails on alternate runs is reported as flaky":
    var runs = 0
    let r = forAllResult(initSettings(seed = 9), x in int):
      inc runs
      if runs mod 2 == 1 and x > 5:
        raise newException(ValueError, "fails on odd runs only")
    check r.status == psFlaky
    check r.failures[0].flaky
    check "FLAKY" in formatReport(r)

  test "V-RL4: shrinking never slips from an assertion bug to an unrelated IndexDefect":
    for seed in 1'u64 .. 20'u64:
      let r = forAllResult(initSettings(seed = seed), xs in seq[int]):
        if xs.len >= 3 and xs[0] == 0:
          discard xs[10]              # a different bug, on a different line
        if xs.len >= 3:
          check xs[2] < 1000
      check r.failures.len == 2
      for f in r.failures:
        if f.signature.kind == "PropertyFailed":
          # Minimal input that reaches the check without the IndexDefect.
          check f.inputs[0].value == "@[1, 0, 1000]"
        else:
          check f.signature.kind == "IndexDefect"
          check f.inputs[0].value == "@[0, 0, 0]"

  test "V-RL5: two independent bugs are both reported, each with its own minimum":
    for seed in 1'u64 .. 20'u64:
      let r = forAllResult(initSettings(seed = seed), a in ints(0, 1000), b in ints(0, 1000)):
        if a > 100: raise newException(ValueError, "bug A")
        if b > 100: raise newException(IOError, "bug B")
      check r.failures.len == 2
      for f in r.failures:
        let values = (f.inputs[0].value, f.inputs[1].value)
        if f.signature.kind == "ValueError": check values == ("101", "0")
        else: check values == ("0", "101")

  test "V-G8: a bug at int.high is found within the default 100 cases":
    var found = 0
    for seed in 1'u64 .. 200'u64:
      let r = forAllResult(initSettings(seed = seed, name = "edge"), x in int):
        check x != high(int)
      if r.status == psFailed: inc found
    # About 99.8% per run by design (maximum proposed with p = 2/16 and a
    # positive sign with p = 1/2); measured over 200 fixed seeds.
    check found >= 195

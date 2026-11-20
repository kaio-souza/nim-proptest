## Property patterns cookbook (docs/PATTERNS.md): one passing property per
## pattern. CI compiles and runs this file.

import proptest, std/[unittest, algorithm, strutils, json, sequtils, tables]

# Code under test for the examples.
proc encode(xs: seq[int]): string = xs.mapIt($it).join(",")
proc decode(s: string): seq[int] =
  if s.len == 0: @[] else: s.split(',').mapIt(parseInt(it))

proc fastSum(xs: seq[int]): int =
  ## "Optimized" version to check against an obviously correct oracle.
  var acc = 0
  for x in xs: acc = acc +% x
  acc

proc oracleSum(xs: seq[int]): int =
  for x in xs: result = result +% x

proc dedupe(xs: seq[int]): seq[int] =
  for x in xs:
    if x notin result: result.add x

const maxRetries = 5          # a domain constant: mined as a boundary hint

proc backoffMs(attempt: int): int =
  ## 100 ms doubled per attempt, up to `maxRetries` attempts.
  if attempt >= maxRetries: -1 else: 100 shl attempt

suite "property patterns":
  test "round trip: decode(encode(x)) == x":
    forAll(xs in seq[int]):
      check decode(encode(xs)) == xs

  test "oracle: the fast version agrees with the simple one":
    forAll(xs in seq[int]):
      check fastSum(xs) == oracleSum(xs)

  test "invariant: the result keeps a property of the input":
    forAll(xs in seq[int]):
      let s = xs.sorted
      check s.len == xs.len
      for i in 1 ..< s.len: check s[i - 1] <= s[i]

  test "idempotence: doing it twice is doing it once":
    forAll(xs in seq[int]):
      check dedupe(dedupe(xs)) == dedupe(xs)

  test "metamorphic: a known change of input gives a known change of output":
    forAll(xs in seqs(ints(-1000, 1000)), k in ints(-1000, 1000)):
      check oracleSum(xs & @[k]) == oracleSum(xs) + k

  test "never crashes: any input is handled":
    forAll(s in string):
      try:
        discard parseJson(s)
      except JsonParsingError, ValueError:
        discard              # rejecting bad input is fine; crashing is not

  test "boundaries: say where the domain changes":
    # `maxRetries` is mined from this file; `near` names the boundary too.
    forAll(attempt in ints(0, 100, near = [maxRetries])):
      classify(attempt == maxRetries, "at the limit")
      let ms = backoffMs(attempt)
      if attempt < maxRetries: check ms >= 100
      else: check ms == -1

  test "coverage: make sure the interesting cases happen":
    forAll(initSettings(cases = 300), xs in seq[int]):
      cover(5.0, xs.len == 0, "empty")
      cover(20.0, xs.len >= 10, "ten or more")
      check xs.sorted.len == xs.len

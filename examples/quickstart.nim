## Quickstart: passing properties, a planted bug and a custom generator.
import proptest, std/[unittest, algorithm]

proc buggyReverse(xs: seq[int]): seq[int] =
  ## Planted bug: drops the last element when there are more than 3.
  for i in countdown(xs.high, 0): result.add xs[i]
  if xs.len > 3: result.setLen(result.len - 1)

suite "quickstart":
  test "sort is idempotent":
    forAll(xs in seq[int]):
      check xs.sorted.sorted == xs.sorted

  test "reverse twice is identity (finds the planted bug)":
    forAll(xs in seq[int]):
      check buggyReverse(buggyReverse(xs)) == xs

  test "custom generators shrink for free":
    let evens = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 0)
    forAll(n in evens):
      check n < 100

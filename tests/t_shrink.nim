## The shrinker on its own, with synthetic probes (ADR-0001).

import std/[unittest, sets, hashes]
import proptest, proptest/shrink

proc sumAtLeast(t: uint64; calls: ptr int = nil): Probe =
  ## Fails (returns true) when the choices add up to at least `t`.
  result = proc(candidate: seq[uint64]; used: var seq[uint64]): bool =
    if calls != nil: inc calls[]
    used = candidate
    var s = 0'u64
    for c in candidate: s += c
    s >= t

suite "shrinker":
  test "RL14/Q5: shortlexLess is a strict order: shorter first, then by value":
    forAll(initSettings(seed = 31), a in seq[uint64], b in seq[uint64]):
      check not shortlexLess(a, a)
      check not (shortlexLess(a, b) and shortlexLess(b, a))
      if a.len < b.len: check shortlexLess(a, b)
    check shortlexLess([1'u64, 9], [2'u64, 0])
    check shortlexLess([9'u64], [0'u64, 0])

  test "S1/RL14/Q5: the result is never larger, still fails, and is minimal":
    forAll(initSettings(seed = 32, cases = 200),
           start in seqs(ints(0'u64, 1000'u64), 1, 20), t in ints(1'u64, 500'u64)):
      var s = 0'u64
      for c in start: s += c
      assume(s >= t)
      var sh = initShrinker(start, 10_000, sumAtLeast(t))
      sh.shrink()
      check not shortlexLess(start, sh.best)
      var used: seq[uint64]
      check sumAtLeast(t)(sh.best, used)
      # The smallest sequence whose sum reaches t is the single choice [t].
      check sh.best == @[t]

  test "S3: shrinking is deterministic":
    let start = @[400'u64, 3, 900, 7, 0, 55]
    var a = initShrinker(start, 10_000, sumAtLeast(1000))
    var b = initShrinker(start, 10_000, sumAtLeast(1000))
    a.shrink()
    b.shrink()
    check a.best == b.best
    check a.executions == b.executions

  test "S4: the execution budget is never exceeded":
    var calls = 0
    var sh = initShrinker(@[400'u64, 3, 900, 7, 0, 55], 5, sumAtLeast(1000, addr calls))
    sh.shrink()
    check sh.executions <= 5
    check calls == sh.executions

  test "PF6: a candidate is never executed twice":
    var seen: HashSet[Hash]
    var duplicates = 0
    let probe: Probe = proc(candidate: seq[uint64]; used: var seq[uint64]): bool =
      let h = hash(candidate)
      if h in seen: inc duplicates
      seen.incl h
      used = candidate
      var s = 0'u64
      for c in candidate: s += c
      s >= 1000
    var sh = initShrinker(@[400'u64, 3, 900, 7, 0, 55, 13, 2], 10_000, probe)
    sh.shrink()
    check duplicates == 0
    check sh.best == @[1000'u64]

  test "PF6: binary search finds large minimal values in few executions":
    var sh = initShrinker(@[high(uint64) div 2], 10_000, sumAtLeast(123_456_789))
    sh.shrink()
    check sh.best == @[123_456_789'u64]
    check sh.executions < 100

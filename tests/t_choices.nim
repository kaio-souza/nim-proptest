## Choice source and drawing primitives (ADR-0001).

import std/[unittest, math]
import proptest

proc replaying(choices: openArray[uint64]): ChoiceSource =
  result = newChoiceSource(1)
  result.startReplay(choices, 100)

suite "choice source":
  test "G1/RL7: drawing past maxChoices is an overrun":
    let src = newChoiceSource(1, maxChoices = 3)
    src.startRandom(10)
    for _ in 0 ..< 3: discard src.drawBool()
    expect Overrun:
      discard src.drawBool()

  test "G1: replay reads the candidate, clamps to bounds and pads with zeros":
    let src = replaying([5'u64, 200])
    check src.drawUpTo(10) == 5
    check src.drawUpTo(100) == 100
    check src.drawUpTo(7) == 0
    check src.choices == @[5'u64, 100, 0]

  test "S1/G1: choice 0 is the simplest value of every primitive":
    let src = replaying([])
    check src.drawInt(-5, 5) == 0
    check src.drawInt(3, 9) == 3
    check src.drawInt(-9, -3) == -3
    check src.drawInt(10'u8, 20'u8) == 10'u8
    check src.drawBool() == false
    check src.drawIndex(4) == 0
    check src.drawFloat() == 0.0
    check src.drawFloatRange(2.0, 3.0) == 2.0
    check src.drawFloatRange(-3.0, -2.0) == -2.0
    var m = src.initMany(0, 10)
    check not src.more(m)

  test "S1: integers shrink toward zero, positive before negative":
    # One choice per signed integer, in zigzag order: 0, 1, -1, 2, -2, ...
    var expected = @[0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5]
    for c, v in expected:
      check replaying([uint64(c)]).drawInt(-10, 10) == v
    # An asymmetric range: alternate while both sides have values, then the
    # rest of the longer side.
    expected = @[0, 1, -1, 2, -2, 3, 4, 5, 6]
    for c, v in expected:
      check replaying([uint64(c)]).drawInt(-2, 6) == v
    check replaying([0'u64]).drawInt(3, 9) == 3             # origin: the bound closest to 0
    check replaying([0'u64]).drawInt(-9, -3) == -3

  test "G2: drawInt reaches both extremes of every width":
    check replaying([253'u64]).drawInt(low(int8), high(int8)) == high(int8)
    check replaying([high(uint64)]).drawInt(low(int8), high(int8)) == low(int8)
    check replaying([high(uint64) - 2]).drawInt(low(int64), high(int64)) == high(int64)
    check replaying([high(uint64)]).drawInt(low(int64), high(int64)) == low(int64)
    check replaying([high(uint64)]).drawInt(0'u64, high(uint64)) == high(uint64)

  test "S1/Q5: every signed value has exactly one choice, and replays to itself":
    # The choice a value is recorded with (as hints do) reads back as the
    # value, for ranges of every shape: no value is unreachable.
    forAll(initSettings(seed = 4, cases = 300), lo in ints(-20, 20), span in ints(0, 40), k in ints(0, 40)):
      let hi = lo + span
      let v = lo + min(k, span)
      let rec = newChoiceSource(1)
      rec.startRandom(10)
      rec.useHints([int64(v)])
      var got = false
      for attempt in 0 ..< 400:          # a hint is proposed on some draws
        rec.startRandom(10)
        let x = rec.drawInt(lo, hi, near = [int64(v)])
        if x == v:
          check replaying(rec.choices).drawInt(lo, hi) == v
          got = true
          break
      check got

  test "G2/Q5: drawInt stays in bounds for any range":
    forAll(initSettings(seed = 3, cases = 300), seed in uint64, a in int64, b in int64):
      let (lo, hi) = (min(a, b), max(a, b))
      let src = newChoiceSource(seed)
      src.startRandom(50)
      for _ in 0 ..< 10:
        let v = src.drawInt(lo, hi)
        check v >= lo and v <= hi

  test "G2: single-value ranges always give that value (regression: UB in release)":
    # countLeadingZeroBits(0) is undefined: release builds produced values
    # outside lo .. hi. Found by the G2/Q5 property in the release matrix.
    let src = newChoiceSource(0)
    for i in 0 ..< 10_000:
      src.startRandom(i mod 101)
      check src.drawInt(0'i64, 0'i64) == 0
      check src.drawInt(5'u8, 5'u8) == 5'u8
      check src.drawInt(-7, -7) == -7
      check src.drawMagnitude(0) == 0

  test "G2: drawInt rejects an empty range":
    let src = replaying([])
    expect ValueError:
      discard src.drawInt(5, 1)

  test "G9: drawFloat never yields NaN or infinities when they are disallowed":
    let src = newChoiceSource(4)
    for i in 0 ..< 5_000:
      src.startRandom(i mod 100)
      let f = src.drawFloat(allowNaN = false, allowInf = false)
      check not f.isNaN
      check f.classify notin {fcInf, fcNegInf}
    # Disallowed special kinds replay as finite values.
    for kind in 1'u64 .. 3'u64:
      let f = replaying([kind]).drawFloat(allowNaN = false, allowInf = false)
      check f == 0.0

  test "G8/G9: drawFloat produces special values while exploring":
    let src = newChoiceSource(5)
    var nan, inf, negZero = false
    for i in 0 ..< 5_000:
      src.startRandom(50)
      let f = src.drawFloat()
      if f.isNaN: nan = true
      elif f == Inf or f == NegInf: inf = true
      elif f == 0.0 and f.classify == fcNegZero: negZero = true
    check nan and inf and negZero

  test "G9/Q5: drawFloatRange stays in range":
    forAll(initSettings(seed = 6, cases = 300), seed in uint64,
           a in floats(-1e9, 1e9), b in floats(-1e9, 1e9)):
      let (lo, hi) = (min(a, b), max(a, b))
      let src = newChoiceSource(seed)
      src.startRandom(50)
      for _ in 0 ..< 10:
        let v = src.drawFloatRange(lo, hi)
        check v >= lo and v <= hi

  test "G7: collections respect minLen and maxLen":
    let src = newChoiceSource(7)
    for i in 0 ..< 1_000:
      src.startRandom(i mod 101)
      var m = src.initMany(2, 4)
      var n = 0
      while src.more(m): inc n
      check n in 2 .. 4

  test "G7: typical lengths grow with the size":
    let src = newChoiceSource(8)
    proc averageLength(size: int): float =
      var total = 0
      for _ in 0 ..< 500:
        src.startRandom(size)
        var m = src.initMany(0, high(int))
        while src.more(m): inc total
      total / 500
    let small = averageLength(0)
    let large = averageLength(100)
    check small < 2.0
    check large > 20.0

  test "PF4: drawing choices does not allocate once the buffers exist":
    let src = newChoiceSource(9)
    src.startRandom(100)
    # Warm-up with the same work: buffers grow on demand, then stay.
    for _ in 0 ..< 1_000:
      discard src.drawInt(low(int), high(int))
      discard src.drawBool()
    let before = getOccupiedMem()
    for _ in 0 ..< 50:
      src.startRandom(100)
      for _ in 0 ..< 1_000:
        discard src.drawInt(low(int), high(int))
        discard src.drawBool()
    check getOccupiedMem() == before

  test "A2: assume discards the case":
    expect DiscardCase:
      assume(false)
    assume(true)

  test "M3/S2: each collection element, with its continue choice, is one span":
    let src = replaying([1'u64, 5, 1, 7, 0])
    var m = src.initMany(0, 10)
    var n = 0
    while src.more(m):
      discard src.drawUpTo(10)
      inc n
    check n == 2
    check src.spans == @[(start: 0, stop: 2), (start: 2, stop: 4)]
    # endElement closes the current element at once (stateful steps).
    src.startReplay([1'u64, 3], 100)
    var m2 = src.initMany(0, 10)
    check src.more(m2)
    discard src.drawUpTo(10)
    src.endElement(m2)
    check src.spans == @[(start: 0, stop: 2)]

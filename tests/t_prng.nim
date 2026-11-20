## PRNG and stable hash (ADR-0005). Golden values come from the authors'
## reference C implementations (splitmix64.c, xoshiro256starstar.c) and from
## the official FNV-1a test vectors, not from this library.

import std/[unittest, sets]
import proptest, proptest/prng

const
  seeds = [0'u64, 1'u64, 42'u64, high(uint64)]
  splitMixGolden = [
    [0xE220A8397B1DCDAF'u64, 0x6E789E6AA1B965F4'u64, 0x06C45D188009454F'u64],
    [0x910A2DEC89025CC1'u64, 0xBEEB8DA1658EEC67'u64, 0xF893A2EEFB32555E'u64],
    [0xBDD732262FEB6E95'u64, 0x28EFE333B266F103'u64, 0x47526757130F9F52'u64],
    [0xE4D971771B652C20'u64, 0xE99FF867DBF682C9'u64, 0x382FF84CB27281E9'u64]]
  xoshiroGolden = [
    [0x99EC5F36CB75F2B4'u64, 0xBF6E1F784956452A'u64, 0x1A5F849D4933E6E0'u64,
     0x6AA594F1262D2D2C'u64, 0xBBA5AD4A1F842E59'u64],
    [0xB3F2AF6D0FC710C5'u64, 0x853B559647364CEA'u64, 0x92F89756082A4514'u64,
     0x642E1C7BC266A3A7'u64, 0xB27A48E29A233673'u64],
    [0x15780B2E0C2EC716'u64, 0x6104D9866D113A7E'u64, 0xAE17533239E499A1'u64,
     0xECB8AD4703B360A1'u64, 0xFDE6DC7FE2EC5E64'u64],
    [0x8F5520D52A7EAD08'u64, 0xC476A018CAA1802D'u64, 0x81DE31C0D260469E'u64,
     0xBF658D7E065F3C2F'u64, 0x913593FDA1BCA32A'u64]]

suite "prng (ADR-0005)":
  test "RL1/Q7: SplitMix64 matches the reference implementation":
    for k, seed in seeds:
      var st = seed
      for i in 0 .. 2:
        check splitMix64(st) == splitMixGolden[k][i]

  test "RL1/Q7: xoshiro256** matches the reference implementation":
    for k, seed in seeds:
      var r = initXoshiro256(seed)
      for i in 0 .. 4:
        check r.next() == xoshiroGolden[k][i]

  test "RL2/Q7: FNV-1a matches the official test vectors":
    check fnv1a64("") == 0xCBF29CE484222325'u64
    check fnv1a64("a") == 0xAF63DC4C8601EC8C'u64
    check fnv1a64("foobar") == 0x85944171F73967E8'u64

  test "RL1/Q5: below stays within its bound":
    forAll(initSettings(seed = 1, cases = 300), seed in uint64, bound in uint64):
      var r = initXoshiro256(seed)
      for _ in 0 ..< 20:
        check r.below(bound) <= bound

  test "RL1: below covers every value of a small range":
    var r = initXoshiro256(7)
    var seen: HashSet[uint64]
    for _ in 0 ..< 1000:
      seen.incl r.below(3)
    check seen == toHashSet([0'u64, 1, 2, 3])
    check r.below(0) == 0

  test "RL1: below has no modulo bias":
    # bound 2 has 3 outcomes: a biased `mod` would favour some of them.
    var r = initXoshiro256(99)
    var counts: array[3, int]
    for _ in 0 ..< 30_000:
      inc counts[r.below(2)]
    for c in counts:
      check c in 9_500 .. 10_500

  test "RL1/Q5: nextFloat is in [0, 1)":
    forAll(initSettings(seed = 2), seed in uint64):
      var r = initXoshiro256(seed)
      for _ in 0 ..< 20:
        let f = r.nextFloat()
        check f >= 0.0 and f < 1.0

  test "R5/RL2: derived seeds are stable and differ per property name":
    check deriveSeed(1, "a") == deriveSeed(1, "a")
    check deriveSeed(1, "a") != deriveSeed(1, "b")
    check deriveSeed(1, "a") != deriveSeed(2, "a")

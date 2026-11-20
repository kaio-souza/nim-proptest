## Deterministic pseudo-random numbers and stable hashing (ADR-0005).
##
## Everything here uses fixed-width `uint64` arithmetic only, so the same seed
## gives the same stream on every Nim version, OS, word size and backend.
## `std/random` and `std/hashes` are never used for anything that is printed
## or persisted.

import std/bitops

type
  Xoshiro256* = object
    ## xoshiro256** generator (Blackman and Vigna).
    s: array[4, uint64]

proc rotl(x: uint64; k: int): uint64 {.inline.} =
  (x shl k) or (x shr (64 - k))

proc splitMix64*(state: var uint64): uint64 =
  ## SplitMix64 step: advances `state` and returns the next output.
  state += 0x9E3779B97F4A7C15'u64
  var z = state
  z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9'u64
  z = (z xor (z shr 27)) * 0x94D049BB133111EB'u64
  z xor (z shr 31)

proc initXoshiro256*(seed: uint64): Xoshiro256 =
  ## Seeds the four state words through SplitMix64, as recommended by the authors.
  var sm = seed
  for i in 0 .. 3:
    result.s[i] = splitMix64(sm)

proc next*(r: var Xoshiro256): uint64 {.inline.} =
  ## Next 64 random bits.
  result = rotl(r.s[1] * 5, 7) * 9
  let t = r.s[1] shl 17
  r.s[2] = r.s[2] xor r.s[0]
  r.s[3] = r.s[3] xor r.s[1]
  r.s[1] = r.s[1] xor r.s[2]
  r.s[0] = r.s[0] xor r.s[3]
  r.s[2] = r.s[2] xor t
  r.s[3] = rotl(r.s[3], 45)

proc below*(r: var Xoshiro256; bound: uint64): uint64 {.inline.} =
  ## Uniform value in `0 .. bound` (inclusive), without modulo bias
  ## (bitmask rejection).
  if bound == 0: return 0
  if bound == high(uint64): return r.next()
  let mask = high(uint64) shr countLeadingZeroBits(bound)
  while true:
    let x = r.next() and mask
    if x <= bound: return x

proc nextFloat*(r: var Xoshiro256): float {.inline.} =
  ## Uniform float in `[0, 1)` built from the top 53 bits.
  float(r.next() shr 11) * (1.0 / 9007199254740992.0)

proc fnv1a64*(s: string): uint64 =
  ## FNV-1a 64-bit hash: stable across versions and platforms.
  result = 0xcbf29ce484222325'u64
  for c in s:
    result = (result xor uint64(ord(c))) * 0x100000001b3'u64

proc deriveSeed*(runSeed: uint64; key: string): uint64 =
  ## Independent stream seed for `key` (a property name) within a run (R5).
  var st = runSeed xor fnv1a64(key)
  splitMix64(st)

## Choice sequences (ADR-0001).
##
## Generators never read random numbers directly: they draw *choices* from a
## `ChoiceSource`. While exploring, choices come from the PRNG and are recorded;
## while shrinking or replaying, they come from a candidate sequence. A smaller
## choice must always produce a simpler value, so shrinking the sequence
## shrinks the value.
##
## The buffers are allocated once per property and reused for every case and
## every shrink attempt: drawing a choice never allocates (PF4).

import std/[fenv, bitops]
import prng

type
  SourceMode* = enum
    smRandom  ## Draw from the PRNG and record.
    smReplay  ## Read from a candidate sequence; zeros after its end.

  CasePhase* = enum
    cpGenerate  ## Building the inputs: exceptions are generator errors.
    cpBody      ## Running the property body: exceptions are failures.

  DiscardCase* = object of CatchableError
    ## Raised by `assume`: the case is discarded, not failed.
  FilterExhausted* = object of DiscardCase
    ## A `filter` rejected too many values in a row for one case.
  Overrun* = object of CatchableError
    ## The case needed more choices than allowed (RL7): it is invalid.

  ChoiceSource* = ref object
    ## Source of choices for one property. Created once, reused per case.
    mode: SourceMode
    rng: Xoshiro256
    prefix: seq[uint64]
    buf: seq[uint64]        # fixed length maxChoices; `count` entries in use
    count: int
    maxChoices: int
    size: int
    wideBits: int           # bit width of "wide" magnitudes for this size
    phase*: CasePhase
    recordInputs*: bool
    inputs*: seq[tuple[name, value: string]]
    spans: seq[Span]        # reused buffer; see `addSpan`
    steps*: seq[string]     # stateful tests: steps as Nim code (recordInputs)
    machine*: string        # stateful tests: machine name (recordInputs)

  Span* = tuple[start, stop: int]
    ## Choices `start ..< stop` that make one element of a collection or one
    ## step of a stateful sequence. The shrinker tries to delete them whole.

  Many* = object
    ## State of a variable-length collection being generated (see `more`).
    minLen, maxLen, target, count: int
    elemStart: int          # first choice of the current element, or -1

const
  defaultMaxChoices* = 8192
  printableAlphabet* = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" &
    "0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    ## Printable ASCII, simplest characters first.

proc buildCharOrder(): array[256, char] =
  var seen: array[256, bool]
  var i = 0
  for c in printableAlphabet:
    result[i] = c
    seen[ord(c)] = true
    inc i
  for b in 0 .. 255:
    if not seen[b]:
      result[i] = char(b)
      inc i

const charOrder* = buildCharOrder()
  ## Every byte, printable ASCII first: index 0 is the simplest `char`.

# ------------------------------------------------------------------ lifecycle

proc newChoiceSource*(seed: uint64; maxChoices = defaultMaxChoices): ChoiceSource =
  result = ChoiceSource(rng: initXoshiro256(seed), maxChoices: maxChoices)
  result.buf = newSeq[uint64](maxChoices)
  result.prefix = newSeqOfCap[uint64](maxChoices)
  result.spans = newSeqOfCap[Span](64)

proc resetCase(src: ChoiceSource; size: int) {.inline.} =
  src.count = 0
  src.size = size
  src.wideBits = clamp(1 + (63 * size) div 100, 1, 64)
  src.phase = cpGenerate
  src.recordInputs = false
  src.inputs.setLen(0)
  src.spans.setLen(0)
  src.steps.setLen(0)

proc startRandom*(src: ChoiceSource; size: int) =
  ## Prepares a new exploration case of the given size.
  src.resetCase(size)
  src.mode = smRandom

proc startReplay*(src: ChoiceSource; candidate: openArray[uint64]; size: int) =
  ## Prepares a case that replays `candidate` (zeros after its end).
  src.resetCase(size)
  src.mode = smReplay
  src.prefix.setLen(candidate.len)
  for i in 0 ..< candidate.len:
    src.prefix[i] = candidate[i]

proc choices*(src: ChoiceSource): seq[uint64] =
  ## Copy of the choices consumed by the current case so far.
  src.buf[0 ..< src.count]

proc choiceCount*(src: ChoiceSource): int {.inline.} =
  ## Number of choices consumed by the current case so far.
  src.count

proc spans*(src: ChoiceSource): seq[Span] =
  ## Copy of the spans recorded by the current case so far.
  src.spans

proc addSpan*(src: ChoiceSource; start, stop: int) {.inline.} =
  ## Records choices `start ..< stop` as one deletable unit. Reuses the
  ## buffer's capacity across cases.
  if stop > start: src.spans.add (start, stop)

proc size*(src: ChoiceSource): int {.inline.} =
  ## Current size: grows over a run, bounds typical collection lengths.
  src.size

proc isRandom*(src: ChoiceSource): bool {.inline.} = src.mode == smRandom

# -------------------------------------------------------------- core drawing

proc overrun(src: ChoiceSource) {.noinline, noreturn.} =
  raise newException(Overrun, "case needed more than " & $src.maxChoices & " choices")

template drawImpl(src: ChoiceSource; bound: uint64; proposal: untyped): uint64 =
  ## Records one choice in `0 .. bound`. `proposal` is evaluated only in
  ## random mode and must already be within bounds.
  block:
    let i = src.count
    if i >= src.maxChoices: overrun(src)
    var v: uint64
    if src.mode == smRandom:
      v = proposal
    else:
      v = if i < src.prefix.len: min(src.prefix[i], bound) else: 0'u64
    src.buf[i] = v
    src.count = i + 1
    v

proc drawUpTo*(src: ChoiceSource; bound: uint64): uint64 {.inline.} =
  ## Uniform choice in `0 .. bound`. Shrinks toward 0.
  drawImpl(src, bound, src.rng.below(bound))

proc drawBool*(src: ChoiceSource; p = 0.5): bool {.inline.} =
  ## `true` with probability `p` while exploring. Shrinks toward `false`.
  drawImpl(src, 1, (if p == 0.5: src.rng.next() shr 63
                    elif src.rng.nextFloat() < p: 1'u64 else: 0'u64)) == 1

proc drawIndex*(src: ChoiceSource; n: int): int {.inline.} =
  ## Uniform index in `0 ..< n` (`n >= 1`). Shrinks toward 0.
  if n <= 1: return 0
  int(src.drawUpTo(uint64(n - 1)))

proc proposeMagnitude(src: ChoiceSource; maxMag: uint64): uint64 {.inline.} =
  ## Random-mode distribution for magnitudes (2 PRNG calls): 0 and 1 with
  ## 1/16 each, the maximum with 2/16 (type limits are where bugs live),
  ## small values up to the size with 5/16, values of up to `wideBits`
  ## random bits with 7/16. Only exploration uses it: the shrink order does
  ## not depend on it, so a slightly uneven reduction is harmless here.
  let r = src.rng.next()
  let strategy = r and 15
  if strategy == 0: return 0
  if strategy <= 2: return maxMag
  if strategy == 3: return min(1'u64, maxMag)
  let x = src.rng.next()
  var limit: uint64
  if strategy <= 8:
    limit = uint64(max(src.size, 1))
  else:
    # 1 .. wideBits, by multiply-shift instead of a slow 64-bit `mod`.
    let bits = 1 + int((((r shr 4) and 63) * uint64(src.wideBits)) shr 6)
    limit = if bits >= 64: high(uint64) else: (1'u64 shl bits) - 1
  let b = min(maxMag, limit)
  if b == high(uint64): return x
  # countLeadingZeroBits(0) is undefined behavior (wrong only in release).
  if b == 0: return 0
  # Into 0 .. b without division: mask to the next power of two, then fold.
  var v = x and (high(uint64) shr countLeadingZeroBits(b))
  if v > b: v -= b + 1
  v

proc drawMagnitude*(src: ChoiceSource; maxMag: uint64): uint64 {.inline.} =
  ## Choice in `0 .. maxMag`, biased toward small values and boundaries
  ## while exploring. Shrinks toward 0.
  drawImpl(src, maxMag, src.proposeMagnitude(maxMag))

proc drawInt*[T: SomeInteger](src: ChoiceSource; lo, hi: T): T =
  ## Integer in `lo .. hi`. Shrinks toward the value of the range closest to
  ## zero; positive values are simpler than negative ones.
  if lo > hi:
    raise newException(ValueError, "drawInt: lo (" & $lo & ") > hi (" & $hi & ")")
  when T is SomeUnsignedInt:
    T(uint64(lo) + src.drawMagnitude(uint64(hi) - uint64(lo)))
  else:
    let l = int64(lo)
    let h = int64(hi)
    let origin = if l > 0: l elif h < 0: h else: 0'i64
    let up = cast[uint64](h) - cast[uint64](origin)
    let down = cast[uint64](origin) - cast[uint64](l)
    if down == 0:
      T(cast[int64](cast[uint64](origin) + src.drawMagnitude(up)))
    elif up == 0:
      T(cast[int64](cast[uint64](origin) - src.drawMagnitude(down)))
    elif src.drawBool():
      T(cast[int64](cast[uint64](origin) - (src.drawMagnitude(down - 1) + 1)))
    else:
      T(cast[int64](cast[uint64](origin) + src.drawMagnitude(up)))

# -------------------------------------------------------------------- floats

const
  fkFinite = 0'u64
  fkInf = 1'u64
  fkNegInf = 2'u64
  fkNaN = 3'u64
  fkNegZero = 4'u64
  fkMax = 5'u64
  fkSubnormal = 6'u64
  fkEpsilon = 7'u64
  fracBits = 20
  maxScale = 970'u64

proc proposeFloatKind(src: ChoiceSource; allowNaN, allowInf: bool): uint64 =
  if src.rng.below(9) != 0: return fkFinite
  var kinds: array[7, uint64]
  var n = 0
  for k in [fkNegZero, fkMax, fkSubnormal, fkEpsilon]:
    kinds[n] = k
    inc n
  if allowInf:
    kinds[n] = fkInf
    kinds[n + 1] = fkNegInf
    n += 2
  if allowNaN:
    kinds[n] = fkNaN
    inc n
  kinds[int(src.rng.below(uint64(n - 1)))]

proc drawFloat*(src: ChoiceSource; allowNaN = true; allowInf = true): float =
  ## Any float, with special values (infinities, NaN, -0.0, extremes) mixed in
  ## while exploring. Shrinks toward 0.0 and toward simple fractions.
  let kind = drawImpl(src, fkEpsilon, src.proposeFloatKind(allowNaN, allowInf))
  case kind
  of fkInf:
    if allowInf: return Inf
  of fkNegInf:
    if allowInf: return NegInf
  of fkNaN:
    if allowNaN: return NaN
  of fkNegZero: return -0.0
  of fkMax: return maximumPositiveValue(float)
  of fkSubnormal: return cast[float](1'u64)
  of fkEpsilon: return epsilon(float)
  else: discard
  let negative = src.drawBool()
  let whole = src.drawMagnitude(1'u64 shl 53)
  let frac = drawImpl(src, (1'u64 shl fracBits) - 1,
    (if src.rng.below(1) == 0: 0'u64 else: src.rng.below((1'u64 shl fracBits) - 1)))
  let scale = drawImpl(src, maxScale,
    (if src.rng.below(8) == 0: src.rng.below(maxScale) else: 0'u64))
  var v = float(whole) + float(frac) / float(1'u64 shl fracBits)
  if scale > 0:
    # Exact power of two built from its bits: constant cost (scale <= 970).
    v *= cast[float]((1023'u64 + scale) shl 52)
    if v > maximumPositiveValue(float):
      v = (if allowInf: Inf else: maximumPositiveValue(float))
  if negative: -v else: v

proc drawFloatRange*(src: ChoiceSource; lo, hi: float): float =
  ## Finite float in `lo .. hi`. Shrinks toward the value closest to zero.
  if not (lo <= hi):
    raise newException(ValueError, "drawFloatRange: invalid range")
  const steps = (1'u64 shl 53) - 1
  let origin = clamp(0.0, lo, hi)
  let up = hi - origin
  let down = origin - lo
  template fraction(): float =
    float(drawImpl(src, steps, (case src.rng.below(9)
                                of 0: 0'u64
                                of 1: steps
                                else: src.rng.below(steps)))) / float(steps)
  let negative = if up > 0 and down > 0: src.drawBool() else: down > 0
  if negative: clamp(origin - down * fraction(), lo, hi)
  else: clamp(origin + up * fraction(), lo, hi)

# --------------------------------------------------------------- collections

proc initMany*(src: ChoiceSource; minLen, maxLen: int): Many =
  ## Starts a collection with `minLen .. maxLen` elements. While exploring, a
  ## target length is picked from the current size; it costs no choice.
  result = Many(minLen: minLen, maxLen: maxLen, target: minLen, elemStart: -1)
  if src.mode == smRandom and maxLen > minLen:
    let extra = uint64(maxLen - minLen)
    let typical = uint64(2 * max(src.size, 1))
    if src.rng.below(7) != 0:
      result.target = minLen + int(src.rng.below(min(extra, typical)))

proc more*(src: ChoiceSource; m: var Many): bool =
  ## Whether to add one more element. Each optional element costs one choice
  ## (1 = continue), so deleting choices deletes elements when shrinking.
  ## Each element, with its continue choice, is recorded as a span.
  if m.elemStart >= 0:
    src.addSpan(m.elemStart, src.count)
  m.elemStart = src.count
  if m.count < m.minLen:
    inc m.count
    return true
  if m.count >= m.maxLen:
    m.elemStart = -1
    return false
  let v = drawImpl(src, 1, (if m.count < m.target: 1'u64 else: 0'u64))
  if v == 1:
    inc m.count
    result = true
  else:
    m.elemStart = -1

proc endElement*(src: ChoiceSource; m: var Many) {.inline.} =
  ## Closes the span of the current element now instead of at the next
  ## `more` call (used when an element may end the case, as a stateful step).
  if m.elemStart >= 0:
    src.addSpan(m.elemStart, src.count)
    m.elemStart = -1

proc assume*(cond: bool) =
  ## Discards the current case when `cond` is false (A2).
  if not cond:
    raise newException(DiscardCase, "assumption not met")

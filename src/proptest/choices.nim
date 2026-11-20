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

import std/[fenv, bitops, monotimes, times, hashes]
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
    caseId: int             # exploration case counter (labels)
    collect: bool           # labels are counted only while exploring
    slots: seq[LabelStat]   # static labels, by compile-time slot (PF10)
    dynamic: seq[LabelStat] # labels whose text is computed (`label`)
    lengthHist*: array[8, int] # stateful: sequence lengths 0, 1, 2-3, 4-7, ... 64+
    edgeCut: uint64         # edge proposals when a 16-bit draw is below this (G8)
    hints: seq[int64]       # boundary hints of the property (ADR-0012)
    nPrimary: int           # the first `nPrimary` hints come from the property itself
    hintsSet: bool
    timing*: bool           # health check: this case measures generation time
    genNs*: int64           # generation time measured in timed cases
    genStart: MonoTime

  LabelKind* = enum
    lkClassify  ## `classify(cond, "name")`
    lkCover     ## `cover(percent, cond, "name")`
    lkLabel     ## `label(text)`
    lkCommand   ## stateful: a command ran
    lkDisabled  ## stateful: a command's precondition was false

  LabelStat* = object
    ## How often a label was hit while exploring (D1, D2).
    name*: string
    kind*: LabelKind
    required*: float        ## `cover`: required percentage of cases.
    cases*: int             ## Cases (sequences, for state machines) that hit it.
    events*: int            ## Hits in total (steps, for state machines).
    lastCase, caseEvents: int

  Span* = tuple[start, stop: int]
    ## Choices `start ..< stop` that make one element of a collection or one
    ## step of a stateful sequence. The shrinker tries to delete them whole.

  Many* = object
    ## State of a variable-length collection being generated (see `more`).
    minLen, maxLen, target, count: int
    elemStart: int          # first choice of the current element, or -1

const
  defaultMaxChoices* = 8192
  defaultEdgeBias* = 0.25
    ## Share of exploration proposals that are edge cases (G8): integer
    ## limits, 0 and 1, special floats, empty and single-element collections.
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

proc newChoiceSource*(seed: uint64; maxChoices = defaultMaxChoices;
                      edgeBias = defaultEdgeBias): ChoiceSource =
  result = ChoiceSource(rng: initXoshiro256(seed), maxChoices: maxChoices,
                        edgeCut: uint64(clamp(edgeBias, 0.0, 1.0) * 65536.0))
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
  inc src.caseId
  src.collect = true

proc startReplay*(src: ChoiceSource; candidate: openArray[uint64]; size: int) =
  ## Prepares a case that replays `candidate` (zeros after its end).
  src.resetCase(size)
  src.mode = smReplay
  src.collect = false
  src.prefix.setLen(candidate.len)
  for i in 0 ..< candidate.len:
    src.prefix[i] = candidate[i]

proc choices*(src: ChoiceSource): seq[uint64] =
  ## Copy of the choices consumed by the current case so far.
  src.buf[0 ..< src.count]

proc choicesHash*(src: ChoiceSource): Hash =
  ## Hash of the choices consumed so far, without copying them.
  hash(src.buf.toOpenArray(0, src.count - 1))

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

proc beginGenerate*(src: ChoiceSource) {.inline.} =
  ## Generators run from here: exceptions are generator errors (RL6).
  src.phase = cpGenerate
  if src.timing: src.genStart = getMonoTime()

proc beginBody*(src: ChoiceSource) {.inline.} =
  ## The property body runs from here: exceptions are failures.
  if src.timing and src.phase == cpGenerate:
    src.genNs += (getMonoTime() - src.genStart).inNanoseconds
  src.phase = cpBody

# -------------------------------------------------------------------- labels

proc hit(st: var LabelStat; caseId: int) {.inline.} =
  inc st.events
  if st.lastCase != caseId:
    st.lastCase = caseId
    st.caseEvents = 0
    inc st.cases
  inc st.caseEvents

proc recordLabel*(src: ChoiceSource; slot: int; cond: bool; name: string;
                  kind: LabelKind; required = 0.0) {.inline.} =
  ## Counts a static label (`classify`, `cover`, stateful statistics). `slot`
  ## is assigned at compile time, so this does not allocate per case (PF10).
  if src.isNil or not src.collect: return
  if slot >= src.slots.len: src.slots.setLen(slot + 1)
  if src.slots[slot].name.len == 0:
    src.slots[slot].name = name
    src.slots[slot].kind = kind
    src.slots[slot].required = required
  if cond: src.slots[slot].hit(src.caseId)

proc recordDynamic*(src: ChoiceSource; name: string) =
  ## Counts a label whose text is computed (`label($x.kind)`).
  if src.isNil or not src.collect: return
  for st in src.dynamic.mitems:
    if st.name == name:
      st.hit(src.caseId)
      return
  src.dynamic.add LabelStat(name: name, kind: lkLabel)
  src.dynamic[^1].hit(src.caseId)

proc recordLength*(src: ChoiceSource; steps: int) {.inline.} =
  ## Stateful: histogram of sequence lengths, no allocation.
  if src.isNil or not src.collect: return
  let bucket = if steps <= 0: 0 else: min(7, 1 + fastLog2(steps))
  inc src.lengthHist[bucket]

proc discardLabels*(src: ChoiceSource) =
  ## Forgets what the current case counted: it was discarded.
  for list in [addr src.slots, addr src.dynamic]:
    for st in list[].mitems:
      if st.lastCase == src.caseId and st.caseEvents > 0:
        dec st.cases
        st.events -= st.caseEvents
        st.caseEvents = 0
        st.lastCase = 0

proc labelStats*(src: ChoiceSource): seq[LabelStat] =
  ## Every label counted so far, static ones first.
  for st in src.slots:
    if st.name.len > 0: result.add st
  result.add src.dynamic

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
  ## Random-mode distribution for magnitudes (2 PRNG calls). With
  ## probability `edgeBias` (default 1/4) an edge: 0 (1/4 of edges), 1 (1/4)
  ## or the maximum (1/2: type limits are where bugs live). Otherwise small
  ## values up to the size (5/12) or values of up to `wideBits` random bits
  ## (7/12). Only exploration uses it: the shrink order does not depend on it.
  let r = src.rng.next()
  if (r and 0xFFFF) < src.edgeCut:
    case (r shr 16) and 3
    of 0: return 0
    of 1: return min(1'u64, maxMag)
    else: return maxMag
  let x = src.rng.next()
  var limit: uint64
  if ((r shr 16) and 0xFFFF) < 27307:   # 5/12 of 65536
    limit = uint64(max(src.size, 1))
  else:
    # 1 .. wideBits, by multiply-shift instead of a slow 64-bit `mod`.
    let bits = 1 + int((((r shr 32) and 63) * uint64(src.wideBits)) shr 6)
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

const hintMask = 3   # hints on 1/4 of integer draws (measured, ADR-0012)

proc useHints*(src: ChoiceSource; primary: openArray[int64]; secondary: openArray[int64] = []) =
  ## Boundary hints for the whole property (ADR-0012): while exploring,
  ## integer draws sometimes propose `h - 1`, `h` or `h + 1`. `primary`
  ## hints (named in the property itself) get half of the hinted draws.
  ## Set once.
  ## Duplicates are harmless (a slightly larger weight), so they are kept:
  ## no quadratic de-duplication per property.
  if src.hintsSet: return
  src.hintsSet = true
  src.hints.setLen(0)
  src.hints.add primary
  src.nPrimary = primary.len
  src.hints.add secondary

proc forceInt[T: SomeInteger](src: ChoiceSource; lo, hi, v: T): T =
  ## Records the choices that `drawInt(lo, hi)` would read to produce `v`
  ## (same layout), so a hinted value shrinks like any other.
  when T is SomeUnsignedInt:
    T(uint64(lo) + drawImpl(src, uint64(hi) - uint64(lo), uint64(v) - uint64(lo)))
  else:
    let l = int64(lo)
    let h = int64(hi)
    let x = int64(v)
    let origin = if l > 0: l elif h < 0: h else: 0'i64
    let up = cast[uint64](h) - cast[uint64](origin)
    let down = cast[uint64](origin) - cast[uint64](l)
    let above = cast[uint64](x) - cast[uint64](origin)
    let below = cast[uint64](origin) - cast[uint64](x)
    if down == 0:
      T(cast[int64](cast[uint64](origin) + drawImpl(src, up, above)))
    elif up == 0:
      T(cast[int64](cast[uint64](origin) - drawImpl(src, down, below)))
    elif x < origin:
      discard drawImpl(src, 1, 1'u64)
      T(cast[int64](cast[uint64](origin) - (drawImpl(src, down - 1, below - 1) + 1)))
    else:
      discard drawImpl(src, 1, 0'u64)
      T(cast[int64](cast[uint64](origin) + drawImpl(src, up, above)))

proc pickHint[T: SomeInteger](src: ChoiceSource; lo, hi: T; local: openArray[int64];
                              v: var T): bool =
  ## With probability 1/4, one of `local` or the property's hints, +-1,
  ## when it falls in `lo .. hi`.
  let total = local.len + src.hints.len
  if total == 0: return false
  let r = src.rng.next()
  if (r and hintMask) != 0: return false
  # Half of the time among the hints named in the property (`near`, the
  # body's literals and constants); otherwise among all, biased to the front
  # (the file's most frequent literals).
  # Indices by multiply-shift on 16-bit slices: no 64-bit division.
  template below(bits: uint64; n: int): int = int(((bits and 0xFFFF) * uint64(n)) shr 16)
  let first = local.len + src.nPrimary
  let i = if first > 0 and ((r shr 2) and 1) == 0: below(r shr 8, first)
          else: min(below(r shr 8, total), below(r shr 24, total))
  let h = if i < local.len: local[i] else: src.hints[i - local.len]
  let off = int64(below(r shr 40, 3)) - 1
  if (off < 0 and h == low(int64)) or (off > 0 and h == high(int64)): return false
  let x = h + off
  when T is SomeUnsignedInt:
    if x < 0 or uint64(x) < uint64(lo) or uint64(x) > uint64(hi): return false
  else:
    if x < int64(lo) or x > int64(hi): return false
  v = T(x)
  true

proc drawInt*[T: SomeInteger](src: ChoiceSource; lo, hi: T; near: openArray[int64] = []): T =
  ## Integer in `lo .. hi`. Shrinks toward the value of the range closest to
  ## zero; positive values are simpler than negative ones. While exploring,
  ## values next to `near` and to the property's hints are proposed now and
  ## then (ADR-0012).
  if lo > hi:
    raise newException(ValueError, "drawInt: lo (" & $lo & ") > hi (" & $hi & ")")
  if src.mode == smRandom and (near.len > 0 or src.hints.len > 0):
    var v: T
    if src.pickHint(lo, hi, near, v): return src.forceInt(lo, hi, v)
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
  # Special values with half the edge share (1/8 by default).
  if (src.rng.next() and 0xFFFF) >= src.edgeCut div 2: return fkFinite
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
    let r = src.rng.next()
    if (r and 0xFFFF) < src.edgeCut:
      # Edge (G8): the shortest collection, or one element more.
      result.target = minLen + int((r shr 16) and 1)
    else:
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

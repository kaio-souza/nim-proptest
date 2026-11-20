## Shrinking over choice sequences (ADR-0001).
##
## The shrinker knows nothing about types. It proposes smaller sequences
## (shortlex order) and asks a probe whether each one still fails with the
## same signature. Accepted results are always strictly smaller, so it
## terminates; a budget of executions bounds its cost (S4, PF6).

import std/[sets, hashes, monotimes, times]
import choices

export Span

type
  Probe* = proc(candidate: seq[uint64]; used: var seq[uint64];
                spans: var seq[Span]): bool {.closure.}
    ## Runs `candidate`; returns true when it fails with the target
    ## signature, and stores in `used` the choices actually consumed and in
    ## `spans` the elements and steps recorded while consuming them.

  Shrinker* = object
    best*: seq[uint64]
    bestSpans*: seq[Span]   ## Spans of `best` (empty when unknown).
    executions*: int
    budget: int
    tried: HashSet[Hash]
    probe: Probe
    stopAt: MonoTime         # time budget (S4); zero = none
    timedOut*: bool          ## The time budget ended shrinking early.

proc shortlexLess*(a, b: openArray[uint64]): bool =
  ## Shorter is smaller; equal lengths compare choice by choice.
  if a.len != b.len: return a.len < b.len
  for i in 0 ..< a.len:
    if a[i] != b[i]: return a[i] < b[i]
  false

proc initShrinker*(start: seq[uint64]; budget: int; probe: Probe;
                   spans: seq[Span] = @[]; timeBudgetMs = 0): Shrinker =
  ## `budget` bounds executions; `timeBudgetMs` (0 = none) bounds time (S4).
  result = Shrinker(best: start, bestSpans: spans, budget: budget, probe: probe)
  if timeBudgetMs > 0:
    result.stopAt = getMonoTime() + initDuration(milliseconds = timeBudgetMs)

proc exhausted*(sh: var Shrinker): bool {.inline.} =
  if sh.executions >= sh.budget: return true
  if sh.stopAt != MonoTime() and getMonoTime() > sh.stopAt:
    sh.timedOut = true
    return true

proc attempt(sh: var Shrinker; candidate: seq[uint64]): bool =
  ## Tries a candidate; adopts what it actually consumed when that is smaller.
  if sh.exhausted or not shortlexLess(candidate, sh.best): return false
  let h = hash(candidate)
  if h in sh.tried: return false
  sh.tried.incl h
  inc sh.executions
  var used: seq[uint64]
  var spans: seq[Span]
  if sh.probe(candidate, used, spans) and shortlexLess(used, sh.best):
    sh.best = used
    sh.bestSpans = spans
    result = true

proc deleteSpans(sh: var Shrinker): bool =
  ## Deletes whole elements and stateful steps, last first. Spans of more
  ## than 2 choices only: shorter ones are covered by `deleteChunks`.
  var i = sh.bestSpans.len - 1
  while i >= 0 and not sh.exhausted:
    let (a, b) = sh.bestSpans[i]
    if b - a > 2 and b <= sh.best.len:
      if sh.attempt(sh.best[0 ..< a] & sh.best[b .. ^1]):
        result = true
        i = min(i, sh.bestSpans.len)
    dec i

proc deleteChunks(sh: var Shrinker): bool =
  for k in [8, 4, 2, 1]:
    var i = sh.best.len - k
    while i >= 0 and not sh.exhausted:
      let cand = sh.best[0 ..< i] & sh.best[i + k .. ^1]
      if sh.attempt(cand):
        result = true
      i = min(i - 1, sh.best.len - k)

proc zeroChunks(sh: var Shrinker): bool =
  for k in [8, 4, 2]:
    var i = 0
    while i + k <= sh.best.len and not sh.exhausted:
      var nonZero = false
      for j in i ..< i + k:
        if sh.best[j] != 0: nonZero = true
      if nonZero:
        var cand = sh.best
        for j in i ..< i + k: cand[j] = 0
        if sh.attempt(cand): result = true
      inc i

proc minimizeValues(sh: var Shrinker): bool =
  ## Lowers each choice by binary search toward 0.
  var i = 0
  while i < sh.best.len and not sh.exhausted:
    if sh.best[i] > 0:
      var cand = sh.best
      cand[i] = 0
      if sh.attempt(cand):
        result = true
      else:
        var lo = 0'u64          # known to pass (or unusable)
        var hi = sh.best[i]     # known to fail
        while lo + 1 < hi and not sh.exhausted and i < sh.best.len:
          let mid = lo + (hi - lo) div 2
          cand = sh.best
          cand[i] = mid
          if sh.attempt(cand):
            result = true
            if i >= sh.best.len: break
            hi = min(mid, sh.best[i])
          else:
            lo = mid
    inc i

proc mergeChunks(sh: var Shrinker): bool =
  ## Deletes a chunk and adds its last choice (typically a magnitude) to an
  ## earlier choice, so two elements become one: `[1, 1]` → `[2]` when only
  ## the total matters. Sizes 3, 2 and 1 cover element layouts of one or two
  ## choices after the "continue" choice. Costlier: run as a fallback.
  const reach = 8
  for k in [3, 2, 1]:
    var i = sh.best.len - k
    while i >= 1 and not sh.exhausted:
      let moved = sh.best[i + k - 1]
      if moved > 0:
        var j = i - 1
        while j >= max(0, i - reach) and not sh.exhausted and i + k <= sh.best.len:
          var cand = sh.best[0 ..< i] & sh.best[i + k .. ^1]
          let base = cand[j]
          cand[j] = if base > high(uint64) - moved: high(uint64) else: base + moved
          if sh.attempt(cand):
            result = true
            break
          # Signed integers are one zigzag choice (+v is 2v - 1): the sum of
          # two positive values is the sum of their choices plus one.
          if cand[j] < high(uint64) and (base and 1) == 1 and (moved and 1) == 1:
            inc cand[j]
            if sh.attempt(cand):
              result = true
              break
          dec j
      i = min(i - 1, sh.best.len - k)

proc lowerAndBump(sh: var Shrinker): bool =
  ## Lowers a choice by one and raises the next one by one: `(1, 0)` →
  ## `(0, 1)`: moves weight to a later choice when lowering the earlier one
  ## alone does not fail. Fallback pass.
  var i = 0
  while i + 1 < sh.best.len and not sh.exhausted:
    if sh.best[i] > 0 and sh.best[i + 1] < high(uint64):
      var cand = sh.best
      dec cand[i]
      inc cand[i + 1]
      if sh.attempt(cand): result = true
    inc i

proc shrink*(sh: var Shrinker) =
  ## Runs the cheap passes until none makes progress, then the merge pass;
  ## repeats while anything improves and the budget lasts.
  var progress = true
  while progress and not sh.exhausted:
    progress = false
    if sh.deleteSpans(): progress = true
    if sh.deleteChunks(): progress = true
    if sh.zeroChunks(): progress = true
    if sh.minimizeValues(): progress = true
    if not progress and sh.mergeChunks(): progress = true
    if not progress and sh.lowerAndBump(): progress = true

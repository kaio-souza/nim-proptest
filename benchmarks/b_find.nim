## Bug-finding power (ADR-0012): planted bugs, each run on fixed seeds with
## default settings; how many seeds find the bug. Deterministic for fixed
## seeds, so it can gate CI like shrink executions (ADR-0008):
##
##   b_find            print the table
##   b_find --check    fail if a detection rate drops below the baseline
##   b_find --update   rewrite benchmarks/baseline/find.json
##
## The rows of v0.2 are the gaps found while testing real code: they are
## expected to be low before v0.3 and must go up as v0.3 lands.

import std/[os, json, strformat, tables]
import ../src/proptest

const seeds = 20

# --- Planted bugs over plain values -----------------------------------------

proc buggyReverse(xs: seq[int]): seq[int] =
  for i in countdown(xs.high, 0): result.add xs[i]
  if xs.len > 3: result.setLen(result.len - 1)

proc midpoint(a, b: int): int = (a + b) div 2     # overflows near the limits

proc clampPercent(x: int): int =
  ## Planted: 100 itself is rejected (boundary inside the range).
  if x < 0: 0 elif x >= 100: -1 else: x

proc nearTimeout(ms: int): bool =
  ## Planted: wrong at exactly 1000 ms, inside 0 .. 2000.
  ms != 1000

# --- Planted bugs in state machines (the v0.2 findings) ----------------------

type
  Clock = ref object
    ms: int
  BState = enum Closed, Open, HalfOpen
  Breaker = ref object
    clock: Clock
    state: BState
    failures, openedAt, level: int
  BModel = object
    state: BState
    failures, now, openedAt, level: int

const
  threshold = 3
  baseMs = 1000
  capMs = 8000

proc timeout(level: int; capped = true): int =
  ## Open period after `level + 1` reopenings: 1 s, 2 s, 4 s, capped at 8 s.
  let t = baseMs shl min(level, 10)
  if capped: min(t, capMs) else: t

proc allows(b: Breaker; boundaryBug, capBug: bool): bool =
  if b.state == Open:
    let waited = b.clock.ms - b.openedAt
    let t = timeout(b.level - 1, capped = not capBug)   # planted: no cap
    if (if boundaryBug: waited > t else: waited >= t):  # planted: > instead of >=
      b.state = HalfOpen
  b.state != Open

proc trip(b: Breaker) =
  b.state = Open
  b.openedAt = b.clock.ms
  inc b.level

proc call(b: Breaker; ok: bool; boundaryBug = false; capBug = false): string =
  if not b.allows(boundaryBug, capBug): return "rejected"
  case b.state
  of HalfOpen:
    if ok:
      b.state = Closed
      b.failures = 0
      b.level = 0
    else: b.trip()
  else:
    if ok: b.failures = 0
    else:
      inc b.failures
      if b.failures >= threshold: b.trip()
  if ok: "ok" else: "failed"

proc admits(m: BModel): bool =
  m.state != Open or m.now - m.openedAt >= timeout(m.level - 1)

proc called(m: var BModel; ok: bool) =
  if not m.admits: return
  if m.state == Open: m.state = HalfOpen
  if m.state == HalfOpen:
    if ok:
      m = BModel(now: m.now)
    else:
      m.state = Open
      m.openedAt = m.now
      inc m.level
  elif ok:
    m.failures = 0
  else:
    inc m.failures
    if m.failures >= threshold:
      m.state = Open
      m.openedAt = m.now
      inc m.level

template breakerMachine(name: untyped; boundaryBug, capBug: bool; maxWait: int) =
  stateMachine name:
    model: BModel()
    setup:
      let clock = Clock()
      let b = Breaker(clock: clock)
    command succeed():
      run: b.call(true, boundaryBug, capBug)
      postcondition: result == (if model.admits: "ok" else: "rejected")
      update: model.called(true)
    command fail():
      run: b.call(false, boundaryBug, capBug)
      postcondition: result == (if model.admits: "failed" else: "rejected")
      update: model.called(false)
    command advance(ms in ints(0, maxWait)):
      run: clock.ms += ms
      update: model.now += ms

breakerMachine(BreakerBoundary, true, false, 2000)
breakerMachine(BreakerCap, false, true, 3000)

type
  Queue = ref object
    items: seq[int]
    pushes, pops: int
  QueueModel = object
    items: seq[int]

proc pop(q: Queue): int =
  result = q.items[0]
  q.items.delete(0)
  inc q.pops
  if q.pushes == 3 and q.pops == 1: inc result

stateMachine QueueBug:
  model: QueueModel()
  setup:
    let q = Queue()
  command push(x in ints(-10, 10)):
    precondition: model.items.len < 3
    run:
      q.items.add x
      inc q.pushes
    update: model.items.add x
  command pop():
    precondition: model.items.len > 0
    run: q.pop()
    postcondition: result == model.items[0]
    update: model.items.delete(0)

# --- The suite ----------------------------------------------------------------

type Row = tuple[name: string; found: proc(seed: uint64): bool]

proc s(seed: uint64): Settings = initSettings(seed = seed, name = "find")

let rows: seq[Row] = @[
  ("reverse drops last element", proc(seed: uint64): bool =
    let r = forAllResult(s(seed), xs in seq[int]):
      check buggyReverse(buggyReverse(xs)) == xs
    not r.passed),
  ("midpoint overflow (limits)", proc(seed: uint64): bool =
    let r = forAllResult(s(seed), a in int, b in int):
      let m = midpoint(a, b)
      check m >= min(a, b) and m <= max(a, b)
    not r.passed),
  ("boundary 100 in 0..1000", proc(seed: uint64): bool =
    let r = forAllResult(s(seed), x in ints(0, 1000)):
      check clampPercent(x) >= 0
    not r.passed),
  ("exact 1000 in 0..2000", proc(seed: uint64): bool =
    let r = forAllResult(s(seed), ms in ints(0, 2000)):
      check nearTimeout(ms)
    not r.passed),
  ("stateful queue (3 push + 1 pop)", proc(seed: uint64): bool =
    not stateMachineResult(QueueBug, s(seed)).passed),
  ("breaker: probe at exactly 1000 ms", proc(seed: uint64): bool =
    not stateMachineResult(BreakerBoundary, s(seed)).passed),
  ("breaker: backoff cap (5 reopenings)", proc(seed: uint64): bool =
    not stateMachineResult(BreakerCap, s(seed)).passed),
]

const baselineFile = currentSourcePath().parentDir / "baseline" / "find.json"

proc main() =
  var current = initOrderedTable[string, int]()
  echo &"""{"planted bug":<38} {"found":>9}"""
  for (name, found) in rows:
    var n = 0
    for seed in 1 .. seeds:
      if found(uint64(seed)): inc n
    current[name] = n
    echo &"{name:<38} {n:>6}/{seeds}"

  let args = commandLineParams()
  if "--update" in args:
    var j = newJObject()
    for k, v in current: j[k] = %v
    writeFile(baselineFile, j.pretty & "\n")
    echo "baseline updated: ", baselineFile
  elif "--check" in args:
    let base = parseFile(baselineFile)
    var failed = false
    for k, v in current:
      if not base.hasKey(k):
        echo "FAIL: no baseline for '", k, "' (run with --update)"
        failed = true
      elif v < base[k].getInt:
        echo &"FAIL: '{k}' found on {v}/{seeds} seeds, baseline {base[k].getInt}"
        failed = true
    if failed: quit 1
    echo "OK: no detection regression against ", baselineFile.extractFilename

main()

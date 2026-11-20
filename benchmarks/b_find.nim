## Bug-finding power (ADR-0012): planted bugs, each run on fixed seeds with
## default settings: how many seeds find the bug, and the median case number
## of the first failure among those that do. Deterministic for fixed seeds,
## so it can gate CI like shrink executions (ADR-0008):
##
##   b_find            print the table
##   b_find --check    fail if a detection rate drops, or a median rises,
##                     against the baseline
##   b_find --update   rewrite benchmarks/baseline/find.json
##
## The rows of v0.2 are the gaps found while testing real code: they are
## expected to be low before v0.3 and must go up as v0.3 lands.

import std/[os, json, strformat, tables, algorithm, strutils]
import ../src/proptest

let seeds = (if existsEnv("B_FIND_SEEDS"): parseInt(getEnv("B_FIND_SEEDS")) else: 20)
  ## 20 for the gate; more (B_FIND_SEEDS) to decide between designs.

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

template breakerMachine(name: untyped; boundaryBug, capBug: bool; maxWait: int;
                        targeted = false) =
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
    invariant:
      when targeted:
        target(float(model.level), "reopenings")      # ADR-0016
      else:
        discard

breakerMachine(BreakerBoundary, true, false, 2000)
breakerMachine(BreakerCap, false, true, 3000)
breakerMachine(BreakerCapTargeted, false, true, 3000, targeted = true)

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

# A bug that needs one command to stay away: 12 increments with no reset in
# between, among other commands. The classic case for swarm testing.
type Counter = ref object
  n: int

stateMachine NoReset:
  model: 0
  setup:
    let c = Counter()
  command incr():
    run:
      inc c.n
      c.n < 12                 # planted: breaks at 12
    postcondition: result
    update: inc model
  command reset():
    run: c.n = 0
    update: model = 0
  command read():
    run: c.n
    postcondition: result == model
  command noop():
    run: discard
  command peek():
    run: c.n >= 0
    postcondition: result

# --- The suite ----------------------------------------------------------------

type Row = tuple[name: string; run: proc(seed: uint64): PropertyResult]

proc s(seed: uint64): Settings = initSettings(seed = seed, name = "find")

let rows: seq[Row] = @[
  ("reverse drops last element", proc(seed: uint64): PropertyResult =
    let r = forAllResult(s(seed), xs in seq[int]):
      check buggyReverse(buggyReverse(xs)) == xs
    r),
  ("midpoint overflow (limits)", proc(seed: uint64): PropertyResult =
    let r = forAllResult(s(seed), a in int, b in int):
      let m = midpoint(a, b)
      check m >= min(a, b) and m <= max(a, b)
    r),
  ("boundary 100 in 0..1000", proc(seed: uint64): PropertyResult =
    let r = forAllResult(s(seed), x in ints(0, 1000)):
      check clampPercent(x) >= 0
    r),
  ("exact 1000 in 0..2000", proc(seed: uint64): PropertyResult =
    let r = forAllResult(s(seed), ms in ints(0, 2000)):
      check nearTimeout(ms)
    r),
  ("stateful queue (3 push + 1 pop)", proc(seed: uint64): PropertyResult =
    stateMachineResult(QueueBug, s(seed))),
  ("breaker: probe at exactly 1000 ms", proc(seed: uint64): PropertyResult =
    stateMachineResult(BreakerBoundary, s(seed))),
  ("breaker: backoff cap (5 reopenings)", proc(seed: uint64): PropertyResult =
    stateMachineResult(BreakerCap, s(seed))),
  ("breaker: backoff cap, target(level)", proc(seed: uint64): PropertyResult =
    stateMachineResult(BreakerCapTargeted, s(seed))),
  ("12 increments without reset", proc(seed: uint64): PropertyResult =
    stateMachineResult(NoReset, s(seed))),
]

const baselineFile = currentSourcePath().parentDir / "baseline" / "find.json"

proc main() =
  var current = initOrderedTable[string, (int, int)]()
  echo &"""{"planted bug":<38} {"found":>9} {"median case":>12}"""
  for (name, run) in rows:
    var at: seq[int]
    for seed in 1 .. seeds:
      let r = run(uint64(seed))
      if not r.passed: at.add r.firstFailureAt
    at.sort()
    let median = if at.len == 0: 0 else: at[at.len div 2]
    current[name] = (at.len, median)
    let shown = if at.len == 0: "-" else: $median
    echo &"{name:<38} {at.len:>6}/{seeds} {shown:>12}"

  let args = commandLineParams()
  if "--update" in args:
    var j = newJObject()
    for k, v in current: j[k] = %*{"found": v[0], "median": v[1]}
    writeFile(baselineFile, j.pretty & "\n")
    echo "baseline updated: ", baselineFile
  elif "--check" in args:
    let base = parseFile(baselineFile)
    var failed = false
    for k, v in current:
      if not base.hasKey(k):
        echo "FAIL: no baseline for '", k, "' (run with --update)"
        failed = true
        continue
      let (bFound, bMedian) = (base[k]["found"].getInt, base[k]["median"].getInt)
      if v[0] < bFound:
        echo &"FAIL: '{k}' found on {v[0]}/{seeds} seeds, baseline {bFound}"
        failed = true
      elif v[0] == bFound and bFound > 0 and v[1] > bMedian:
        echo &"FAIL: '{k}' median case {v[1]}, baseline {bMedian}"
        failed = true
    if failed: quit 1
    echo "OK: no detection regression against ", baselineFile.extractFilename

main()

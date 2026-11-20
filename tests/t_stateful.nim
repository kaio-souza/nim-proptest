## Stateful (model-based) testing (ADR-0011): M1–M6, RL13.

import std/[unittest, strutils, os, options]
import proptest
import helpers
import fixtures/f_machine

# ---------------------------------------------------------------- machines

var violations, setups, teardowns, longest: int

type Counted = object
  n: int

# Preconditions guard `take`; a bug when n reaches 3 makes shrinking run too.
stateMachine Guarded:
  model: Counted()
  setup:
    var stock = 0
  command give():
    run: inc stock
    update: inc model.n
  command take():
    precondition: model.n > 0
    run:
      if stock <= 0: inc violations
      dec stock
      stock
    postcondition: model.n != 3    # planted: fails when taking from 3
    update: dec model.n

# Invariant-only bug: `size` is wrong once 2 items are in.
type Bag = ref object
  items: seq[int]

proc size(b: Bag): int =
  if b.items.len == 2: 3 else: b.items.len

stateMachine BagMachine:
  model: Counted()
  setup:
    let bag = Bag()
  command put(x in int):
    run: bag.items.add x
    update: inc model.n
  command clear():
    run: bag.items.setLen(0)
    update: model.n = 0
  invariant: bag.size == model.n

# M6: time is a command. A cache entry lives 10 ms; the system's bug keeps
# it alive at exactly 10 ms.
type
  FakeClock = ref object
    now: int
  TtlCache = ref object
    clock: FakeClock
    storedAt: int
    has: bool
  TtlModel = object
    has: bool
    age: int

proc get(c: TtlCache): bool =
  c.has and c.clock.now - c.storedAt <= 10   # bug: should be < 10

stateMachine Ttl:
  model: TtlModel()
  setup:
    let clock = FakeClock()
    let cache = TtlCache(clock: clock)
  command put():
    run:
      cache.has = true
      cache.storedAt = clock.now
    update: model = TtlModel(has: true, age: 0)
  command advance(ms in ints(0, 20)):
    run: clock.now += ms
    update: model.age += ms
  command get():
    run: cache.get()
    postcondition: result == (model.has and model.age < 10)

# RL13: counts setups and teardowns; the model must start fresh each time.
stateMachine Lifecycle:
  model: Counted()
  setup:
    inc setups
    var count = 0
  teardown:
    inc teardowns
  command bump():
    run: inc count
    update: inc model.n
  command boom():
    precondition: model.n >= 2
    run: raise newException(IOError, "planted")
  invariant: count == model.n

# RL5: two independent bugs, different exception types.
stateMachine TwoBugs:
  model: ()
  command a(x in ints(0, 100)):
    run:
      if x > 5: raise newException(ValueError, "bug in a")
  command c(flag in bool):
    run:
      if flag: raise newException(IOError, "bug in c")

# M2: arguments drawn from the model (handles); K: maxSteps.
type Keys = object
  keys: seq[int]

stateMachine Handles:
  model: Keys()
  setup:
    var stored: seq[int]
    var steps = 0
  command add(k in ints(0, 1000)):
    run:
      stored.add k
      inc steps
      longest = max(longest, steps)
    update: model.keys.add k
  command remove(k in elements(model.keys)):
    precondition: model.keys.len > 0
    run:
      check k in stored
      stored.delete(stored.find(k))
      inc steps
      longest = max(longest, steps)
    update: model.keys.delete(model.keys.find(k))
  invariant: stored.len == model.keys.len

# RL6: an argument source that raises is a generator error, not a failure.
stateMachine BadSource:
  model: Keys()
  command remove(k in elements(model.keys)):   # no precondition: empty list
    run: discard k

proc runOutsideTest() =
  checkStateMachine(BoundedQueue, initSettings(seed = 1))

proc replayBlock(report: string): string =
  ## The `replayCommands` block of a report, dedented.
  var inBlock = false
  for line in report.splitLines:
    if line.strip.startsWith("replayCommands"): inBlock = true
    elif inBlock and not line.startsWith("      "): break
    if inBlock: result.add line[4 .. ^1] & "\n"

# ------------------------------------------------------------------- tests

suite "stateful testing":
  test "M1: a valid sequence replays without error":
    replayCommands BoundedQueue:
      push(1)
      push(2)
      pop()
      pop()
    check push(BoundedQueue, 4).stepCode == "push(4)"
    check pop(BoundedQueue).stepCode == "pop()"

  test "M1: malformed machines are rejected at compile time":
    let (log1, ok1) = compileFixture("f_badmachine")
    check not ok1
    check "command 'noop' needs a `run:` section" in log1
    let (log2, ok2) = compileFixture("f_badmachine2")
    check not ok2
    check "declare command arguments as `name in Type` or `name in generator`" in log2

  test "M2/Q5: preconditions hold while exploring and while shrinking":
    violations = 0
    for seed in 1 .. 20:
      let r = stateMachineResult(Guarded, initSettings(seed = uint64(seed), cases = 200))
      check r.status == psFailed
      check r.failures[0].steps == @["give()", "give()", "give()", "take()"]
    check violations == 0

  test "M2: replayCommands rejects a sequence that breaks a precondition":
    expect ValueError:
      replayCommands BoundedQueue:
        pop()
    try:
      replayCommands BoundedQueue:
        push(1)
        pop()
        pop()
    except ValueError as e:
      check "precondition of step 3 (pop()) is false" in e.msg

  test "M2: arguments can be drawn from the model; maxSteps bounds sequences":
    longest = 0
    let r = stateMachineResult(Handles, initSettings(seed = 3, maxSteps = 5))
    check r.status == psPassed
    check longest in 1 .. 5
    longest = 0
    check stateMachineResult(Handles, initSettings(seed = 3)).passed
    check longest > 5

  test "V-M3: the queue bug shrinks to exactly 4 steps on 20 seeds":
    # SPEC Part IV: wrong after exactly 3 pushes and 1 pop.
    for seed in 1 .. 20:
      let r = stateMachineResult(BoundedQueue, initSettings(seed = uint64(seed)))
      check r.status == psFailed
      check r.failures.len == 1
      check r.failures[0].steps == @["push(0)", "push(0)", "push(0)", "pop()"]

  test "M4: the printed sequence is Nim code that reproduces the failure":
    let r = stateMachineResult(BoundedQueue, initSettings(seed = 7))
    let report = formatReport(r)
    check "Shortest failing sequence (4 steps" in report
    check "Failed at step 4: pop()" in report
    let code = replayBlock(report)
    check code == "replayCommands BoundedQueue:\n  push(0)\n  push(0)\n  push(0)\n  pop()\n"
    writeFile(fixturesDir / "f_replay_gen.nim",
      "# Generated by t_stateful: a report's replay block, compiled as is.\n" &
      "import proptest, f_machine\n\n" & code)
    let (log, ok) = compileFixture("f_replay_gen")
    check ok
    if not ok: echo log
    let (output, code2) = runFixture("f_replay_gen")
    check code2 != 0
    check "check failed: result == model.items[0]" in output

  test "M5: invariants are checked after every command":
    let r = stateMachineResult(BagMachine, initSettings(seed = 5))
    check r.status == psFailed
    check r.failures[0].steps == @["put(0)", "put(0)"]
    check "bag.size == model.n" in r.failures[0].message

  test "M6: time is injected as a command and the boundary is found exactly":
    for seed in 1 .. 10:
      let r = stateMachineResult(Ttl, initSettings(seed = uint64(seed), cases = 300))
      check r.status == psFailed
      check r.failures[0].steps == @["put()", "advance(10)", "get()"]

  test "RL13: a fresh system and model per sequence; teardown always runs":
    setups = 0
    teardowns = 0
    let r = stateMachineResult(Lifecycle, initSettings(seed = 2))
    check r.status == psFailed               # `boom` fails, the invariant never does
    check r.failures[0].signature.kind == "IOError"
    check r.failures[0].steps == @["bump()", "bump()", "boom()"]
    check setups > 100
    check teardowns == setups

  test "RL5: independent stateful bugs are reported separately":
    let r = stateMachineResult(TwoBugs, initSettings(seed = 4, cases = 300))
    check r.status == psFailed
    check r.failures.len == 2
    var seen: seq[seq[string]]
    for f in r.failures: seen.add f.steps
    check @["a(6)"] in seen
    check @["c(true)"] in seen

  test "RL6: an argument source that raises is a generator error":
    let r = stateMachineResult(BadSource, initSettings(seed = 1))
    check r.status == psGeneratorError

  test "I1/I3: checkStateMachine raises PropertyError outside a unittest test":
    expect PropertyError:
      runOutsideTest()

  test "M4: showCode prints values as Nim expressions":
    check showCode(-3) == "-3"
    check showCode("a\"b\n") == "\"a\\\"b\\n\""
    check showCode('x') == "'x'"
    check showCode(1.5) == "1.5"
    check showCode(NaN) == "NaN"
    check showCode(-Inf) == "-Inf"
    check showCode(high(uint64)) == "18446744073709551615'u64"
    check showCode(@[1, 2]) == "@[1, 2]"
    check showCode([true, false]) == "[true, false]"
    check showCode((1, "a")) == "(1, \"a\")"
    check showCode((x: 1, y: 2)) == "(x: 1, y: 2)"
    check showCode((7,)) == "(7,)"
    check showCode(some(3)) == "some(3)"
    check showCode(none(int)) == "none(int)"
    check showCode({1'u8, 3}) == "{1, 3}"

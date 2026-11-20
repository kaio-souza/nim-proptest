## Stateful testing tutorial (docs/STATEFUL.md): a small circuit breaker
## checked against a model. CI compiles and runs this file; it passes.
## Build with -d:plantBug to see the failure report of the tutorial.

import proptest, std/unittest

# --- The system under test ---------------------------------------------------

type
  Clock = ref object
    ms: int                        # a fake clock: tests move it by hand

  State = enum Closed, Open, HalfOpen

  Breaker = ref object
    clock: Clock
    state: State
    failures: int                  # consecutive failures while Closed
    openedAt: int

const threshold = 3                # failures that open the circuit
const openFor = 1000               # ms before a probe call is allowed

proc newBreaker(clock: Clock): Breaker = Breaker(clock: clock)

proc allows(b: Breaker): bool =
  ## Whether a call may run now. Open becomes HalfOpen once the timeout elapses.
  if b.state == Open:
    let waited = b.clock.ms - b.openedAt
    if (when defined(plantBug): waited > openFor else: waited >= openFor):
      b.state = HalfOpen
  b.state != Open

proc record(b: Breaker; ok: bool) =
  case b.state
  of Closed:
    if ok: b.failures = 0
    else:
      inc b.failures
      if b.failures >= threshold:
        b.state = Open
        b.openedAt = b.clock.ms
  of HalfOpen:
    if ok:
      b.state = Closed
      b.failures = 0
    else:
      b.state = Open
      b.openedAt = b.clock.ms
  of Open: discard

proc call(b: Breaker; succeeds: bool): string =
  ## "ok", "failed" or "rejected".
  if not b.allows: return "rejected"
  b.record(succeeds)
  if succeeds: "ok" else: "failed"

# --- The model: the same rules, as simply as possible ------------------------

type Model = object
  state: State
  failures, now, openedAt: int

proc admits(m: Model): bool =
  m.state != Open or m.now - m.openedAt >= openFor

proc called(m: var Model; ok: bool) =
  if not m.admits: return
  if m.state == Open: m.state = HalfOpen
  if ok:
    m.state = Closed
    m.failures = 0
  elif m.state == HalfOpen:
    m.state = Open
    m.openedAt = m.now
  else:
    inc m.failures
    if m.failures >= threshold:
      m.state = Open
      m.openedAt = m.now

# --- The state machine -------------------------------------------------------

stateMachine BreakerSpec:
  model: Model()
  setup:
    let clock = Clock()
    let breaker = newBreaker(clock)

  command succeed():
    run: breaker.call(succeeds = true)
    postcondition: result == (if model.admits: "ok" else: "rejected")
    update: model.called(ok = true)

  command fail():
    run: breaker.call(succeeds = false)
    postcondition: result == (if model.admits: "failed" else: "rejected")
    update: model.called(ok = false)

  # Any wait. `openFor` (1000) is a constant of this file, so waits of 999,
  # 1000 and 1001 are proposed often (ADR-0012); `ints(0, 2000, near =
  # [openFor])` would say it explicitly.
  command advance(ms in ints(0, 2000)):
    run: clock.ms += ms
    update: model.now += ms

  invariant:
    check breaker.state == model.state
    check breaker.failures == model.failures

suite "stateful tutorial":
  test "the breaker follows its model":
    checkStateMachine(BreakerSpec, initSettings(cases = 500))

  test "a regression test pasted from a report":
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()

# Stateful testing tutorial

Some bugs are not in one function call but in a **sequence** of calls: a queue that misbehaves after three pushes and a pop, a cache that keeps an entry one millisecond too long, a circuit breaker that lets a probe through at the wrong moment. Example-based tests only find them if someone already thought of the sequence.

Stateful (model-based) testing writes down the rules once, as a small **model**, and lets the library generate random command sequences, run each one on the real system and on the model, and compare them after every step. When they disagree, it shrinks the sequence to the **shortest** one that still fails and prints it as Nim code you can paste as a regression test.

This tutorial builds the example in [`examples/stateful.nim`](../examples/stateful.nim) (compiled and run in CI). Design: [ADR-0011](decisions/0011-stateful-testing.md).

## 1. The system: a circuit breaker

A circuit breaker protects a caller from a failing dependency. After `threshold` consecutive failures it **opens** and rejects calls; after `openFor` milliseconds it lets one **probe** call through (half-open); a successful probe closes it, a failed one opens it again.

```nim
type
  Clock = ref object
    ms: int                        # a fake clock: tests move it by hand
  State = enum Closed, Open, HalfOpen
  Breaker = ref object
    clock: Clock
    state: State
    failures: int
    openedAt: int

const threshold = 3
const openFor = 1000

proc call(b: Breaker; succeeds: bool): string =
  ## "ok", "failed" or "rejected".
```

The clock is injected. Time-based code is only testable when the test can move time itself, without `sleep`.

## 2. The model: the rules, as simply as possible

The model is a plain value that predicts what the system should do. It does not need to be efficient or general, only obviously correct:

```nim
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
```

## 3. The machine: commands, preconditions, postconditions

```nim
stateMachine BreakerSpec:
  model: Model()                     # a fresh model for every sequence
  setup:                             # a fresh system for every sequence
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

  # Any wait, plus the waits around the timeout: bugs live at boundaries.
  command advance(ms in oneOf(ints(0, 2000), elements([openFor - 1, openFor, openFor + 1]))):
    run: clock.ms += ms
    update: model.now += ms

  invariant:
    check breaker.state == model.state
    check breaker.failures == model.failures
```

What each section does:

| Section | Runs | Notes |
|---|---|---|
| `model:` | once per sequence | An expression; the variable `model` holds it. Use `model: ()` when there is no model. |
| `setup:` | once per sequence | Statements. Their variables are visible in every command. |
| `teardown:` | after every sequence, even a failing one | Runs whenever `setup` completed. |
| `command name(x in source, ...)` | per step | Arguments use the `forAll` syntax: a type or a generator. |
| `precondition:` | before choosing a command | Sees the model. Only enabled commands are generated, during exploration **and** shrinking. |
| `run:` | the step | Its value is `result` in `postcondition:`. |
| `postcondition:` | after `run`, **before** `update` | Compares `result` with what the model predicts. A single expression is checked; otherwise write `check` lines. |
| `update:` | after the postcondition | Moves the model forward. |
| `invariant:` | after every step | Same rules as `postcondition:`. |

Time is just another command (`advance`). Everything time-based becomes reproducible and shrinkable.

Arguments may depend on the model, for example `k in elements(model.keys)` to act on a key added earlier. Give such commands a precondition (`model.keys.len > 0`) so the source is never asked for an element of an empty list.

## 4. Running it

```nim
suite "breaker":
  test "the breaker follows its model":
    checkStateMachine(BreakerSpec, initSettings(cases = 500))
```

Each case is one random sequence of up to `maxSteps` commands (default 50; `initSettings(maxSteps = ...)`). Sequences grow over the run, short ones first. `stateMachineResult(BreakerSpec)` returns the `PropertyResult` instead of failing the test, as `forAllResult` does.

## 5. Reading a failure

Build the example with `-d:plantBug`. That bug lets the probe through only *after* 1000 ms, not *at* 1000 ms:

```
Property 'BreakerSpec' falsified after 499 passing cases (0 discarded).
  Shortest failing sequence (5 steps, 12 choices, 130 shrink executions):
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()
  Error: [PropertyFailed] check failed: result == if model.admits: "ok" else: "rejected"
      result was "rejected"
      if model.admits: "ok" else: "rejected" was "ok"
  Location: stateful.nim:92
  Failed at step 5: succeed()
  Replay: PROPTEST_SEED=3 ./stateful
```

The random sequence that first failed had dozens of steps. The report shows the shortest one: three failures to open the circuit, a wait of **exactly** the timeout, and the call that should have been let through. Any earlier step can be removed and the bug disappears; any wait other than 1000 does not show it.

The `replayCommands` block is valid Nim. Paste it into a test and it runs the same steps, with the same setup, postconditions and invariants, as a permanent regression test:

```nim
  test "probe allowed exactly at the timeout (regression)":
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()
```

If a replayed step's precondition is false, `replayCommands` raises `ValueError` naming that step, because such a sequence can never be generated.

## 6. When the model is wrong

A failure means that the system and the model disagree. Sometimes the model is the one that is wrong. While writing this example, the first version of `called` did not count the failure that opens the circuit, and the test answered within a few cases:

```
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
  Error: [PropertyFailed] check failed: breaker.failures == model.failures
      breaker.failures was 3
      model.failures was 2
```

Three steps are enough to see which rule is off. Decide which side matches the specification, and fix that side.

## 7. Tips

- **Keep the model dumb.** A list instead of a ring buffer, a counter instead of a sliding window. If the model is as complex as the system, both can share the same bug.
- **Generate boundaries on purpose.** A uniform wait in `0 .. 2000` hits exactly 1000 rarely. `oneOf(ints(0, 2000), elements([...]))` adds the values the specification cares about, and shrinking still works.
- **Check what the user observes**: returned values in postconditions, visible state in invariants. Do not check private fields.
- **Expected errors are values.** If the system raises on a rejected call, catch it inside `run:` and return something the model predicts (`"rejected"`). Any exception that escapes `run:` is a failure.
- **A real example**: [`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-breaker) tests its breaker this way (`tests/t_model.nim`), with backoff, `successThreshold` and its `FakeClock`, over 1000 sequences.

## Limits (v0.2)

- Commands run one after another on one thread. Parallel linearizability checks are planned after 1.0 (M7).
- Argument values are printed with `showCode`, which produces Nim literals for built-in types. For a custom argument type, overload `showCode` so the printed block compiles.
- `stateMachine` must be used at module level. The generated names (`BreakerSpec`, `BreakerSpecStep`, the command constructors) are exported, so a machine can live in its own module.

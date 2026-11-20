# ADR-0011: Stateful testing: `stateMachine` macro over the choice sequence

- Status: Accepted (implemented in v0.2)
- Date: 2026-11-20
- Requirements: M1–M6, RL13, DOC4 (M7 out of scope)

## Context

v0.2 must let a user describe a system under test, a reference model and commands, then find the **shortest** failing command sequence and print it as **runnable Nim code** (M1–M4). The first external user is the `nim-circuit-breaker` model test (its V2/Q5): random `call` outcomes and clock advances compared against a small state model, with the fake clock (`FakeClock`, `advance`) as part of the system (M6).

Constraints from earlier decisions:

- Shrinking works only on the choice sequence (ADR-0001). Stateful testing must be a *generator* over choices, not a second shrinker.
- Built-in paths stay closure-free (ADR-0007); assertions inside the body are rewritten (ADR-0009).
- Failures are identified by signature, with no slippage (ADR-0006).

## Decision

### 1. One macro defines the machine; one call runs it

```nim
type Model = object
  items: seq[int]

stateMachine BoundedQueue:
  model: Model()                          # initial model, evaluated per sequence
  setup:                                  # fresh system per sequence (RL13)
    let q = newBoundedQueue[int](capacity = 3)
  teardown:                               # always runs, even after a failure
    q.close()

  command push(x in ints(-10, 10)):       # arguments use `forAll` syntax
    precondition: model.items.len < 3     # sees the model only
    run: q.push(x)
    update: model.items.add x

  command pop():
    precondition: model.items.len > 0
    run: q.pop()
    postcondition: result == model.items[0]   # checked before `update`
    update: model.items.delete(0)

  invariant: q.len == model.items.len     # after every command (M5)

suite "queue":
  test "matches the model":
    checkStateMachine(BoundedQueue)                      # or with initSettings(...)
    # let r = stateMachineResult(BoundedQueue)           # PropertyResult, no raise
```

- `setup:` is a statement list, not an expression. Its variables are visible to every command. It handles systems made of several objects, such as a breaker and its `FakeClock`, so time is injected by an ordinary command (M6):

  ```nim
  setup:
    let clock = newFakeClock()
    let cb = newCircuitBreaker(cfg, clock.source)
  command advance(ms in ints(0, 5_000)):
    run: clock.advance(initDuration(milliseconds = ms))
    update: model.tick(ms)
  ```

- `run:` is an expression; when `postcondition:` is present its value is bound to `result`. Expected exceptions, such as `CircuitOpenError`, are caught by the user inside `run` and turned into a value the model predicts. Any exception that escapes is a failure, as in `forAll`.
- `check`/`require` are rewritten inside `run`, `postcondition`, `update` and `invariant`, as in `forAll`. A plain `postcondition: expr` is a `check`.
- `assume` inside a command discards the whole sequence (rare: preconditions are the normal tool).

### 2. Code generation: one proc per machine, commands inlined

The macro emits a `PropertyProc` (the same type `forAll` uses), so `runProperty` and the whole engine are reused unchanged: exploration, signatures, multiple failures, flaky detection, seed replay.

```nim
proc(src: ChoiceSource) =
  var model = <model expr>
  <setup>
  try:
    var steps = initMany(src, 0, settings.maxSteps)
    while src.more(steps):
      var enabled: array[N, uint8]; var n = 0
      if <precondition 0>: enabled[n] = 0; inc n      # one line per command
      ...
      if n == 0: break                                # nothing enabled: end
      src.startSpan()
      case enabled[src.drawIndex(n)]
      of 0:                                           # push
        src.phase = cpGenerate
        let x = drawFrom(src, <hoisted gen>)
        if src.recordInputs: src.recordStep("push", [show(x)])
        src.phase = cpBody
        <run>; <postcondition>; <update>
      ...
      src.endSpan()
      <invariant>
  finally:
    <teardown>
```

- **Preconditions during generation and shrinking (M2):** the command index is drawn among the commands *enabled in the current model*, so every replayed sequence is valid by construction and no sequence is rejected. When shrinking deletes a step, later indices are reinterpreted against the new enabled set; the shrinker keeps the result only if it still fails with the same signature.
- **Arguments that depend on the state:** argument sources may read `model` (for example `k in elements(model.keys)`). This covers "handles" (ids returned by one command and used by another) without a separate bundle mechanism. Preconditions see the model, not the arguments, so arguments are never rejected after being drawn.
- Sources that do not depend on the model are hoisted once per property (as in `forAll`); others are evaluated per step.
- New setting `maxSteps` (default 50) in `Settings`; sequences grow with `size`, like collections.

### 3. Shrinking: steps as spans (M3)

A step costs 1 (continue) + 1 (command) + k (arguments) choices. The current passes delete chunks of 8, 4, 2 and 1 choices, which misses steps with larger arguments. We add **spans** to `ChoiceSource`: `more` records each element of a `Many`, with its continue choice, as a `(start, stop)` pair in a reused buffer (no allocation, ADR-0008), and `endElement` closes a step's span at once. The step loop is a `Many`, so seqs, strings and stateful steps all get spans without extra code. A new pass, `deleteSpans`, runs **first** and tries to delete each span of more than 2 choices, last first (shorter spans are covered by `deleteChunks`).

Zeroing the continue choice of a step ends the sequence there, so `zeroChunks`/`minimizeValues` already truncate sequences. Lowering a command index moves toward the *first enabled* command, which defines "simpler command" as declaration order. That is documented.

### 4. Report: the sequence as runnable code (M4)

When `recordInputs` is on, each step is recorded as `(command, args shown)`. `Failure` gains `steps: seq[string]`, and the report prints them inside a block that can be pasted as is:

```
Property 'BoundedQueue' falsified after 37 passing cases (0 discarded).
  Shortest failing sequence (4 steps, 52 shrink executions):
    replayCommands BoundedQueue:
      push(0)
      push(0)
      push(0)
      pop()
  Error: [PropertyFailed] check failed: result == model.items[0]
      result was 1, model.items[0] was 0
  Failed at step 4 (pop)
  Replay: PROPTEST_SEED=...
```

`replayCommands M: <calls>` is a macro that resolves each call by name against the commands of `M` and runs the steps with the same setup, model, postconditions, invariants and teardown. Preconditions are checked and reported as an error if violated. Command names never become global procs, so `push`/`pop` do not clash with user code.

Argument values are printed with `show`, which already produces Nim literals for built-in types. Custom types need a `show` that returns valid Nim code (documented).

## Implementation notes (v0.2)

The open questions were settled by a spike and by measurement:

1. **`result` binding**: `let result = <run>` compiles inside the generated void closure. A `{.push warning[ResultShadowed]: off.}` around it silences the warning. `result` is the only name.
2. **No debug mode for `replayCommands`.** The report already names the failing step (`Failed at step N: ...`), and a pasted block is ordinary code where the user can add `echo`. It can be added later without breaking anything.
3. **`maxSteps` = 50, grown with `size` like any collection.** A sequence that ends early because no command is enabled is a valid, shorter sequence, not a discard, so it never counts toward "gave up".

Deviations from the sketch above, found while implementing:

- `stateMachine Name*:` does not parse, so the generated names are **always exported**. A machine can live in its own module and be replayed from another (tested).
- Argument types are generated as type aliases of `typeof(<source drawn with model and setup in scope>)`. A `typeof` written directly as a parameter type stayed unresolved during overload resolution when another proc had the same name (`advance` on `FakeClock`).
- `teardown:` runs whenever `setup:` completed. If setup itself raises, the variables teardown would use may not exist.
- In replay mode the runner receives no `ChoiceSource` (nil). With ARC/ORC in Nim 2.2.4, a ref allocated in the caller (or passed as a temporary argument) leaked under LeakSanitizer when the runner raised. Named locals and a nil source keep the replay path leak-free.
- `propCheck` now prints expressions on one line, so a postcondition such as `result == (if model.admits: a else: b)` does not break the report layout.

Measured cost of `deleteSpans` as the first pass (`benchmarks/b_shrink.nim`): the wide-step queue bug drops from ~1100 to 205 executions (20 seeds: 9194 → 4039 in total); three existing reference bugs need fewer executions (49→47, 24→20, 68→66), `reverse` needs more (113→125), and the 4-step queue is unchanged (115). The baseline was updated accordingly. As a fallback pass it saved nothing.

## Consequences

- No change to the engine loop, the shrinker contract or the report for `forAll`. Stateful testing is a generator plus a report section.
- Spans are a small engine change that also improves seq shrinking. They must keep the zero-allocation gate green.
- Commands are inlined in one `case`: no closures, no dynamic dispatch, and compile errors point at user code.
- Not covered by this ADR: parallel linearizability (M7), async commands (I4) and per-step deadlines (RL8). The structure (one span per step, a recorded step list) does not block them.

## Evidence

- Unit tests per requirement: M1 (definition and errors from the macro), M2 (preconditions never violated, over 1000 sequences), M5, M6, RL13 (teardown runs after a failure, a fresh model per sequence).
- Value test (SPEC Part IV): a queue wrong after exactly 3 pushes and 1 pop shrinks to the 4 steps above, with `0` arguments, on 20 seeds. Two independent stateful bugs are both reported.
- The printed `replayCommands` block is compiled and run by a test (golden + execution), so M4 means "runnable", not just "looks like code".
- Gates: shrink executions for the reference bug (baseline in `benchmarks/baseline/shrink.json`), zero allocations per step outside user code. `deleteSpans` was meant not to raise any existing baseline; it raises one (`reverse`, +12) and lowers three, accepted above.
- External user: the `nim-circuit-breaker` model test runs in that project's CI (V2/Q5), and the stateful tutorial (DOC4) is based on it.

Results (v0.2): all of the above in `tests/t_stateful.nim` (14 tests) and `tests/t_choices.nim`, green on orc/arc × threads on/off × debug/release and clean under ASan/UBSan/LSan. The queue bug shrinks to `push(0) ×3, pop()` on 20 of 20 seeds (115 executions for seed 1). A 50-step sequence allocates nothing (`b_gen --check`). `nim-circuit-breaker/tests/t_model.nim` passes over 1000 sequences and catches three planted model mistakes, each shrunk to its minimal sequence.

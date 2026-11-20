# Troubleshooting

Find what you see, then read why it happens and what to do. The reports below are real output (file names shortened). Every setting mentioned is described in [CONFIGURATION.md](CONFIGURATION.md).

**The property fails or stops**

- [Gave up after N passing cases](#gave-up-after-n-passing-cases)
- [FLAKY: the minimal case did not fail again](#flaky-the-minimal-case-did-not-fail-again)
- [A generator raised](#a-generator-raised)
- [Missed its coverage requirements](#missed-its-coverage-requirements)
- [DeadlineExceeded](#deadlineexceeded)
- [The test hangs](#the-test-hangs)
- [The process ends with no report](#the-process-ends-with-no-report)

**The report is surprising**

- [Two bugs reported as one, or "Location unknown"](#two-bugs-reported-as-one-or-location-unknown)
- [The counterexample is not as small as it could be](#the-counterexample-is-not-as-small-as-it-could-be)
- [Replayed from the failure database](#replayed-from-the-failure-database)
- [`PROPTEST_SEED` does not reproduce the failure](#proptest_seed-does-not-reproduce-the-failure)

**It passes, but should it?**

- [The property passes, but the bug is there](#the-property-passes-but-the-bug-is-there)
- [Warning: only N distinct inputs](#warning-only-n-distinct-inputs)
- [Warning: cases needed more than maxChoices](#warning-cases-needed-more-than-maxchoices)
- [Warning: generating inputs takes most of the run time](#warning-generating-inputs-takes-most-of-the-run-time)
- [Warning: command never ran](#warning-command-never-ran)
- [Warning: time budget reached](#warning-time-budget-reached)

**Other**

- [The test suite is slow](#the-test-suite-is-slow)
- [Output from the property floods the terminal](#output-from-the-property-floods-the-terminal)
- [A pasted `replayCommands` block fails with "precondition ... is false"](#a-pasted-replaycommands-block-fails-with-precondition--is-false)
- [Compile errors](#compile-errors)

---

## The property fails or stops

### Gave up after N passing cases

```
Property 'assume' gave up after 0 passing cases: 1001 cases discarded (0 by filters, 0 too large).
```

**Why.** Too many cases were thrown away: by `assume(...)`, by a `filter` that rejected 100 values in a row, or because they were too large for `maxChoices`. After `cases × maxDiscardRatio` discards (1000 by default) the property stops, because it is no longer testing much. When most discards come from filters, the message adds "Most discards come from `filter`: generate valid values directly instead."

Not one case passed above, and this is why: sizes grow with the cases that **pass**, so while every case is discarded, inputs stay as small as at the first case, and a condition on their size never becomes true.

**What to do.** Generate valid values instead of rejecting invalid ones. The property above wanted lists of more than 30 elements whose first element is not greater than the second:

```nim
# Gives up: rejects every case.
forAll(xs in seq[int]):
  assume(xs.len > 30 and xs[0] <= xs[1])
  ...

# Passes 100 cases: builds only valid inputs, and still shrinks.
let longLists = seqs(ints(), minLen = 31, maxLen = 200).map(
  proc(xs: seq[int]): seq[int] =
    result = xs
    if result[0] > result[1]: swap(result[0], result[1]))

forAll(xs in longLists):
  ...
```

For values that depend on each other (a start before an end), draw the first and then the second within its range, as in [GENERATORS.md](GENERATORS.md). Keep `assume` for rare exclusions (`assume(d != 0)`).

**Trade-off.** Raising `maxDiscardRatio` makes the message go away but not the cost: each discarded case still runs the generator, and the cases that pass are the few that happened to fit, so they may all look alike.

### FLAKY: the minimal case did not fail again

```
Property 'flaky' is flaky at case 3 (67 cases passed, 0 discarded).
  FLAKY: the minimal case did not fail again when re-run.
  Common causes: time, randomness, global state, threads or I/O in the property.
  Counterexample (1 choices, 1 shrink executions):
    x = 0
  Error: [PropertyFailed] check failed: counter mod 3 != 0
        counter mod 3 was 0
```

**Why.** After shrinking, every failure is run twice more. If it does not fail both times, the outcome did not depend only on the generated inputs. Above, the property read a global counter that changes on every run.

**What to do.** Find what the property reads besides its inputs:

- **Global or module state**: a cache, a counter, a singleton. Create fresh state inside the body, or reset it at the start.
- **Time**: `now()`, `epochTime()`, timeouts. Inject a clock and control it from the property (the [stateful tutorial](STATEFUL.md) does this with a fake clock).
- **Randomness** in the code under test: seed it from a generated value (`seed in uint64`).
- **Threads, files, network**: order and timing change between runs. Test the logic without them, or make the test own the resource (a temporary directory per case).

The report still shows the counterexample: the bug may be real, but not reproducible as written. Do not just re-run until it passes.

### A generator raised

```
Property 'price': a generator raised: [ValueError] invalid integer:
  This is a problem in a generator, not in the code under test.
```

**Why.** The exception came from generating inputs, before the body ran: here, an `arbitrary` for `Money` called `parseInt` on a random string. The library stops at once instead of reporting a bug that is not in your code.

**What to do.** Fix the generator so every choice gives a valid value. Draw what you need directly (`src.drawInt(0, 1_000_000)`) rather than generating something broader and converting it.

A different error with a similar look: built-in generators raise `ValueError` for impossible arguments (`ints: lo > hi`, `seqs: invalid lengths`) when the property starts, before any case. Check the arguments.

### Missed its coverage requirements

```
Property 'empty lists' passed 100 cases but missed its coverage requirements:
    cover 'empty': 8.0% of 100 cases, 50.0% required
  Statistics (100 cases):
      8.0%  empty  (cover: 50.0% required)
```

**Why.** `cover(50.0, xs.len == 0, "empty")` asks for at least 50% of cases to be empty lists, and only 8% were. Every case passed, but the cases you said matter were rare, so the property did not test what you meant. A requirement fails only when even the optimistic end of a statistical interval is below it; when there are too few cases to be sure, it is a warning ("too few cases to be sure; raise `cases`") instead.

**What to do.** Either the generator should produce those cases more often (a dedicated generator, `frequency`, `near = [...]`), or the requirement is too strict. A requirement around the share you actually need to test well (5%, 10%) is usually right; 50% for one situation means it deserves its own property.

### DeadlineExceeded

```
Property 'slow' falsified at case 2 (80 cases passed, 0 discarded).
  Counterexample (1 choices, 9 shrink executions):
    x = 16
  Error: [DeadlineExceeded] case took 10.2 ms; deadline 5.0 ms
```

**Why.** `deadline` (or `PROPTEST_DEADLINE`) is set, and a case took longer. It is shrunk like any failure, to the smallest input that is still slow: here, the code sleeps when `x > 15`, and 16 is that boundary.

**What to do.** If the slowness is a bug (quadratic behavior on some input), the counterexample shows the input. If it is noise (a loaded CI machine, a debug build), raise the deadline: set it well above normal case times. Exploration already allows 1.25 × the deadline, but shrinking and re-runs use the deadline itself, so a borderline case can also be reported as FLAKY.

### The test hangs

**Why.** A case never returns (an infinite loop, a deadlock). `deadline` cannot stop it: it measures a case after it returns.

**What to do.**

1. Stop the process. The run seed was written before the first case:
   ```sh
   cat .proptest/last-run        # PROPTEST_SEED=... and the command
   ```
2. Replay with that seed and with the case inputs printed. `PROPTEST_VERBOSITY=verbose` prints each case **after** it returns, so its last line is the case before the hanging one. To see the hanging case itself, print the inputs at the top of the body while you investigate:
   ```nim
   forAll(xs in seq[int]):
     echo "trying ", xs        # temporary
     ...
   ```
3. Once you know the input, turn it into an `example(...)` or a plain test, fix the loop, and remove the `echo`.

### The process ends with no report

**Why.** Usually `--panics:on`: a Defect (`IndexDefect`, `AssertionDefect`, overflow) ends the process instead of being raised, so the library cannot shrink it or report it. The compiler warns: "proptest: compiled with --panics:on". Other causes: a segmentation fault (`nil` access under `-d:danger`, or in C code), or `quit()` called by the code under test.

**What to do.** Build the tests with `--panics:off` (the default) and without `-d:danger`. The seed is in `.proptest/last-run` to replay the crash under a debugger.

## The report is surprising

### Two bugs reported as one, or "Location unknown"

Debug build: two bugs, two failures.

```
Property 'two bugs' falsified at case 8 (53 cases passed, 0 discarded).
Failure 1 of 2 (ValueError at t_bugs.nim:28)
  ...
    x = 51
    y = 0
  Error: [ValueError] x too big
Failure 2 of 2 (ValueError at t_bugs.nim:29)
  ...
    x = 0
    y = 51
  Error: [ValueError] y too big
```

Same property built with `-d:release`: one failure, the second bug hidden.

```
Property 'two bugs' falsified at case 8 (53 cases passed, 0 discarded).
  Counterexample (2 choices, 17 shrink executions):
    x = 51
    y = 0
  Error: [ValueError] x too big
  Location unknown (no stack trace): failures are told apart by type only.
```

**Why.** Two failures are the same bug when they have the same exception type and are raised at the same line of your code. The line comes from the stack trace, which `-d:release` turns off. `check` failures keep their line in every build, because the line is recorded where `check` is written.

**What to do.** Run property tests in debug builds, or add `--stackTrace:on --lineTrace:on` to the release build ([table](CONFIGURATION.md#compile-time-options)). Such a build is announced at compile time by the warning "proptest: built without stack traces". The opposite case, one bug reported as several, happens when the same bug raises at different lines depending on the input; the counterexamples then look alike, and fixing one fixes the others.

### The counterexample is not as small as it could be

**Why**, from most to least common:

- **A custom generator breaks the shrinking rule**: a smaller choice must give a simpler value. `src.drawInt(0, 100)` follows it; `100 - src.drawInt(0, 100)` inverts it, so shrinking moves toward 100. Map simple choices to simple values.
- **Shrinking stopped early**: the report says "Shrinking stopped at its time budget" (`shrinkTimeBudget`), or the executions shown equal `maxShrinks`. Raise the budget, or make one execution faster.
- **The minimum is not where you expect**: shrinking minimizes the *choices*, which for built-in generators means shorter collections, values closer to 0, the first enum value, the first `oneOf` branch. `x = -1` may be the simplest failing value when `x = 1` passes.
- **A `filter` sits on top**: shrunk values must still pass the filter, which can block simpler values. Generating valid values directly helps here too.

### Replayed from the failure database

```
  Replayed from the failure database: it failed in an earlier run.
```

**Why.** A failure found on an earlier run was saved in `.proptest/db/` and is replayed before any random case, so a fix is checked at once. This one still fails.

**What to do.** Nothing special: it is a real failure, with the same report as when it was found. An entry is forgotten after it passes 3 runs in a row; entries that no longer fit the generators (you changed the types) are dropped. To start clean, delete `.proptest/db/`; to disable it, `PROPTEST_DB=off`.

### `PROPTEST_SEED` does not reproduce the failure

**Why.** The seed reproduces a run only if everything else that decides the inputs is the same. Check, in order:

1. **The code changed.** A property's seed comes from its name, which by default is its `file:line`: adding a line above it changes its inputs. Constants mined from the file change too. Use the seed with the binary that printed it, or give the property a `name`.
2. **The settings differ.** `cases` decides how sizes grow, so `PROPTEST_CASES=1000` with a seed printed by a 100-case run gives other inputs. The same holds for `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm` and `mineConstants`.
3. **The property sets `seed`.** A fixed seed in the settings wins over `PROPTEST_SEED`.
4. **The property is not deterministic.** If the report said FLAKY, see [above](#flaky-the-minimal-case-did-not-fail-again).

Platform and build mode do not matter: the same seed gives the same values on Linux, macOS and Windows, debug and release.

## It passes, but should it?

### The property passes, but the bug is there

A passing property only says that the inputs it tried were fine. Look at what it tried:

1. **Count the cases you care about.** Add `classify` for the situations the bug needs, and `cover` if they must happen:
   ```nim
   forAll(xs in seq[int]):
     classify(xs.len == 0, "empty")
     classify(xs.len > 100, "long")
     cover(1.0, low(int) in xs, "has low(int)")
     check ...
   ```
   The statistics are printed after a passing run.
2. **Look at the inputs** with `PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20`.
3. Then, depending on what is missing:

| Missing | Fix | Trade-off |
|---|---|---|
| a specific value (a limit defined in another module) | `ints(lo, hi, near = [limit])` | none: other values are still drawn |
| long inputs | raise `maxSize`, or `seqs(g, minLen = ...)` | slower cases |
| a rare combination | more `cases` (in CI: `PROPTEST_CASES`) | time grows linearly |
| a whole category | a dedicated generator, or `frequency` | more code to keep |
| deep states of a state machine | raise `maxSteps`; keep `swarm` on | longer sequences |

Integer constants in the property body are already proposed as `v - 1`, `v`, `v + 1` (`mineConstants`); constants defined in another module are not.

### Warning: only N distinct inputs

```
Property 'few inputs' passed 100 cases.
  Warnings:
    only 2 distinct inputs in 100 passing cases: the input space is small, so a plain loop over it would be exhaustive
```

**Why.** The property ran 100 cases over far fewer distinct inputs (fewer than 1 in 10 distinct). Here the input is a `bool`, which has two values.

**What to do.** If the input space really is that small, a loop over all values is shorter and complete:

```nim
for b in [false, true]:
  check ...
```

If it should be larger, the generator is too narrow (`ints(0, 3)` where you meant `ints(0, 3000)`). If the warning is expected, `initSettings(suppress = {hcFewDistinct})`.

### Warning: cases needed more than maxChoices

```
Property 'too large' passed 100 cases.
  Warnings:
    440 cases needed more than maxChoices (8192) choices and were skipped: bound collection sizes (`seqs(g, maxLen = ...)`) or raise maxChoices
```

**Why.** Nested collections grow fast: a `seq[seq[string]]` with `maxSize = 1000` produces values with tens of thousands of choices. Those cases were skipped, and the 100 that passed are the smaller ones: large inputs went untested.

**What to do.** Bound the sizes where they matter, or lower `maxSize`. The same shape with bounds produces no warning even at `maxSize = 1000`:

```nim
let bounded = seqs(seqs(strings(alphanumeric, 0, 20), maxLen = 10), maxLen = 100)
forAll(initSettings(maxSize = 1000), v in bounded): ...
```

Raise `maxChoices` only when large inputs are the point, knowing each case then takes longer to run and to shrink.

### Warning: generating inputs takes most of the run time

**Why.** More than 80% of the time went into generating inputs rather than running the property: usually a `filter` that rejects most values, or a custom generator that builds large values and throws most of them away.

**What to do.** Generate valid values directly, or bound sizes. If the property is cheap and generation is legitimately the work, `suppress = {hcSlowGeneration}`.

### Warning: command never ran

```
Property 'CounterSpec' passed 100 cases.
  Warnings:
    command 'reset' never ran in 100 sequences; its precondition was false 1934 times
```

**Why.** In a state machine, a command whose precondition is never true is never tested. Here `reset` needs more than 1000 increments, and sequences are at most 50 steps long.

**What to do.** Make the state reachable (raise `maxSteps`, or add a command that gets there faster), or loosen the precondition if the model allows it. The statistics at `PROPTEST_VERBOSITY=verbose` show how often each command ran and how often its precondition was false.

### Warning: time budget reached

```
Property 'budget' passed 173 cases.
  Warnings:
    time budget of 200 ms reached after 173 of 100000 cases
```

**Why.** `timeBudget` (or `PROPTEST_TIME_BUDGET`) stopped exploration early. The property passed the cases it ran.

**What to do.** Nothing, if bounded time was the goal. If not, raise the budget, lower `cases`, or make the property faster.

## Other

### The test suite is slow

In rough order of effect:

1. **Build mode.** Generation in a debug build is several times slower than in release. If you build tests in release, add `--stackTrace:on --lineTrace:on` to keep failure locations ([why](#two-bugs-reported-as-one-or-location-unknown)).
2. **Fewer cases locally, more in CI.** Keep the default in code and set `PROPTEST_CASES` in CI.
3. **Smaller inputs.** A lower `maxSize`, or bounded generators, for properties whose code is slow on large inputs.
4. **Bound the time.** `timeBudget` per property; `deadline` to find the inputs that make one case slow.

To see where time goes, `PROPTEST_REPORT=report.jsonl` records `durationMs` per property:

```sh
jq -r '"\(.durationMs)\t\(.name)"' report.jsonl | sort -rn | head
```

### Output from the property floods the terminal

**Why.** The body runs once per case and once per shrink step: an `echo` in it prints hundreds of times. The library itself prints nothing per case at the default verbosity.

**What to do.** Remove debugging output once done. To see inputs, use `PROPTEST_VERBOSITY=verbose`; to see distributions, `classify` and `label`. Text that should explain a failure belongs in the `check` itself: comparisons already print both sides (`x was 500`).

### A pasted `replayCommands` block fails with "precondition ... is false"

```
replayCommands: precondition of step 3 (pop()) is false, so this sequence cannot happen
```

**Why.** The sequence was printed by an earlier version of the state machine. The model or the preconditions changed, so the sequence is no longer possible.

**What to do.** If the change was intended, delete the regression test or regenerate it from a new failing run. If not, the change broke the model.

### Compile errors

| Error | Cause | Fix |
|---|---|---|
| `type expected` at `forAll(x: int)` | Nim parses `name: value` arguments as an object constructor before the macro sees them | write `forAll(x in int)` |
| `declare variables as `name in Type` or `name in generator`` | `forAll(x = ints(0, 1))` | `forAll(x in ints(0, 1))` |
| `forAll needs a body: forAll(x in int): ...` | the call has no body, or is used as an expression | add the body; to get the result as a value, `let r = forAllResult(...): ...` |
| `proptest cannot generate field 'f' of P: overload `arbitrary` for its type, or for P` | a field type with no generator (a `proc`, a pointer, a type from C) | write `arbitrary` for that field's type, or for `P` ([GENERATORS.md](GENERATORS.md)) |
| `proptest cannot derive T: its discriminant 'k' is a range type` | a Nim 2.2.4 limitation | use an enum for the discriminant, or write `arbitrary` for `T` |
| `example(...) needs one value per variable (N)` | an example with too few or too many values | one value per `name in source`, in order |
| `classify is only valid inside forAll or a stateMachine` | `classify`, `cover` or `label` outside a property | move it into the body |
| Warning `proptest: compiled with --panics:on` | see [above](#the-process-ends-with-no-report) | build tests with `--panics:off` |
| Warning `proptest: built without stack traces`, or `... without --lineTrace:on` | a release build: see [above](#two-bugs-reported-as-one-or-location-unknown) | `--stackTrace:on --lineTrace:on`, or `-d:proptestTraceWarning=false` if your properties fail through `check` |

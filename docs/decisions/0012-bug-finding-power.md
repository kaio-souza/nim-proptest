# ADR-0012: Bug-finding power: measured detection, coverage, boundaries and swarm testing

- Status: Proposed
- Date: 2026-11-20
- Requirements: D1, D2, O4, PF10, G8, M2, RL8, PF8, S4, RL11, O2

## Context

v0.2 tested real code (`nim-circuit-breaker`, the tutorial's breaker) and showed where the library is weak:

- **Exact domain boundaries are rare.** A probe allowed at `> 1000 ms` instead of `>= 1000 ms` needs a wait of exactly 1000. Drawn from `ints(0, 2000)`, that happens rarely: 1 seed in 3 found it within 500 cases. The tutorial works around it by hand with `oneOf(ints(0, 2000), elements([999, 1000, 1001]))`.
- **Deep states are rare.** The breaker's backoff cap needs five reopenings in a row. With clock advances of at most 3 s it was never reached in 1000 sequences, and a model without the cap passed.
- **Nothing told us.** Both gaps were found only by planting bugs by hand and seeing that they survived. The report says "passed" either way.

The evidence policy (ADR-0004) proves that bugs we know about shrink well. It does not measure how likely the library is to *find* a bug in the first place.

## Decision

### 1. Measure bug-finding power first: `benchmarks/b_find.nim`

A suite of planted bugs, each run on K fixed seeds (K = 20), records:

- the **detection rate** (seeds that found it within the default settings);
- the **median number of cases to the first failure** (new field `PropertyResult.firstFailureAt`).

Both are deterministic for fixed seeds, so they can gate CI like shrink executions (ADR-0008): a change may not lower a detection rate or raise a median beyond the baseline. The initial suite holds the v0.2 bugs (breaker boundary, backoff cap, queue, the reference bugs of SPEC Part IV) plus one per v0.3 feature. Every later step of v0.3 must improve these numbers.

### 2. `classify` and `cover` (D1, D2), and automatic stateful statistics

Inside a `forAll` body or a command:

```nim
forAll(xs in seq[int]):
  classify(xs.len == 0, "empty")
  cover(5.0, xs.len > 50, "long")        # at least 5% of cases
  check ...
```

- The macro gives every call site a compile-time slot index, so a static label costs one counter increment per case and no allocation (PF10). Dynamic labels (`label($x.kind)`) go to a table.
- `cover` fails the property (new status `psInsufficientCoverage`) only when the run is **confidently** below the requirement: the upper bound of a 95% Wilson interval on the observed rate is under the required percentage. A short run never fails on noise; it warns instead.
- State machines get statistics without any code: how often each command ran, how often its precondition disabled it, and the distribution of sequence lengths. A command that never ran is a warning.
- The report prints the distribution (O4), for passing properties too when verbosity is `normal` or higher (O2).

### 3. Edge-case bias and boundary hints (G8)

- Complete G8 in the existing random-mode proposals, which do not affect the shrink order: integers also hit `-1`; floats hit `-0.0`, subnormals, `NaN` and `Inf` where allowed; collections hit empty and single-element. The share of edge proposals becomes a setting (`edgeBias`, default as today: about 3/16).
- **Boundary hints**: `ints(lo, hi, near = [a, b])` proposes `v - 1`, `v`, `v + 1` for each hint with a fixed share of the edge budget. Hints change only exploration. A hinted value is an ordinary magnitude choice, so it shrinks like any other.

### 4. Swarm testing for state machines

At the start of each sequence, one choice per command decides whether that command is *allowed* in this sequence (choice 0 = allowed, so shrinking moves toward "all allowed"). A command is generated only if allowed **and** enabled by its precondition. If the swarm leaves nothing enabled, every enabled command is allowed for that step. This makes long runs of a few commands likely, which is what deep states need (five failed probes in a row). Groce et al. (ISSTA 2012) showed that swarm testing finds more bugs than a single uniform mix. On by default if `b_find` confirms it, with a `swarm = false` setting.

### 5. Deadlines and time budgets (RL8, PF8, S4)

- `deadline` setting (per case, off by default, `PROPTEST_DEADLINE` to set it globally): a case slower than the deadline fails with signature kind `DeadlineExceeded` at the property's location, and is shrunk like any failure. While exploring, the limit is 1.25 × the deadline, so a case that is only just over does not become a flaky report. Re-runs confirm with the plain deadline.
- `timeBudget` (per run) and `shrinkTimeBudget`: stop gracefully, report how many cases ran or the best counterexample so far.
- A case that **never returns** cannot be stopped without a watchdog thread (RL10, after 1.0). The run seed is already in `.proptest/last-run` for replay. The SPEC value test for RL8 (a loop that never ends on `42`) needs RL10, so for v0.3 it becomes "a case that takes 2 s when the input contains 42".

### 6. Health checks (RL11) and verbosity (O2)

They extend today's give-up message: a filter that rejects almost all values, generation taking most of the run time, collections constantly hitting their size limit, a generator with very few distinct values. Each check names its fix and can be disabled. `PROPTEST_VERBOSITY` selects `quiet | normal | verbose | debug`.

## Consequences

- v0.3 adds API (`classify`, `cover`, `label`, `near`, new settings) but changes no existing signature.
- The random-mode distribution changes (edge bias, hints, swarm choices). Values generated for a given seed change: this goes under **Generation changes** in the CHANGELOG, as the stability policy requires.
- `b_find` becomes the reference for any future change to generation. A change that "looks better" but lowers detection is rejected.

## Settled questions

1. **Mining constants: an experiment, adopted only if `b_find` says so.** After `b_find` and boundary hints land, the macros collect integer literals and `const` values used in comparisons of the body, the model and the preconditions (`openFor`), and pass them as automatic hints to integer sources of the same type. It is adopted (on by default, `mineConstants = false` to opt out) only if it raises the detection rate of the boundary bugs without lowering any other row of `b_find`. If it is noisy, explicit `near = [...]` stays the documented way. Reason: hand-written hints only help when someone already suspects the boundary, which is exactly when a property was least needed.
2. **Default deadline: off.** `deadline = 0` disables it; `PROPTEST_DEADLINE` (milliseconds) turns it on globally, for example in CI. Reason: timings vary between machines and under load, so a default deadline turns into flaky failures on slow CI runners, the opposite of RL3. A team that wants it sets it once in CI.
3. **`cover` inside state machines counts per sequence.** A sequence is "covered" by a label if any of its steps hit it, so `cover(20.0, model.state == Open, "reached Open")` reads as "20% of sequences reach Open". Reason: the question a model test asks is "do we reach this state", not "how many steps were spent in it". `classify` inside commands keeps per-step counts as well, and the report shows both.

## Evidence

- `b_find` baseline before any v0.3 change; every step lands with its effect on detection rate and median cases.
- Value tests from SPEC Part IV: D2 (a generator that never produces empty strings → `cover` fails with the observed percentage), G8 (`int.high` bug found within 100 cases), RL8 (the "slow on 42" case reported as a deadline failure with counterexample `[42]`), RL11 (a filter that accepts 1 value in 10 000 stops the run early with a message).
- The tutorial's boundary bug is found by `ints(0, 2000, near = [openFor])` on 20/20 seeds, and the breaker's backoff cap with the original 3 s advances once swarm testing is on.

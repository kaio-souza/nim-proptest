# Architecture

Ties the ADRs into one picture of how a property runs. Modules marked *(planned)* do not exist yet.

## Glossary

| Term | Meaning |
|---|---|
| **Choice** | A `uint64` drawn by a generator. Every generated value is built from choices. |
| **Choice sequence** | The recorded list of choices consumed by one case. Shrinking works on it ([ADR-0001](decisions/0001-integrated-shrinking-on-choice-sequences.md)). |
| **Choice source** | Object that hands choices to generators: from the PRNG while exploring, from a candidate sequence while shrinking or replaying. |
| **Case** | One execution of the property body with one generated set of inputs. |
| **Overrun** | A case that needed more choices than the maximum length; invalid, not a failure. |
| **Signature** | Identity of a failure: exception type and raise/check location ([ADR-0006](decisions/0006-failure-identity-and-flaky-detection.md)). |
| **Shrinking** | Searching for a smaller choice sequence that fails with the same signature. |
| **Shortlex order** | Shorter sequence is smaller; same length compares choice by choice. Shrinking only moves down this order. |
| **Flaky** | A property whose final counterexample does not fail again in both re-runs. |
| **Span** | Choices that make one collection element or one stateful step, with its "continue" choice; the shrinker deletes it whole ([ADR-0011](decisions/0011-stateful-testing.md)). |
| **Step** | One command of a stateful sequence, with its arguments; printed as a Nim call. |
| **Failure database** | `.proptest/` directory with the minimal sequences of past failures ([ADR-0003](decisions/0003-reproducibility-and-failure-database.md)). |

## Modules

```
src/
  proptest.nim                 # public API: forAll macro (ADR-0010), PropertyError, std/unittest adapter
  proptest/
    prng.nim                   # SplitMix64, xoshiro256**, stable FNV-1a hash (ADR-0005)
    choices.nim                # ChoiceSource, reused buffers, overrun, draw primitives, assume (ADR-0001)
    gen.nim                    # arbitrary(src, T) overloads, Gen[T], combinators, hoist/drawFrom (ADR-0007)
    assertions.nim             # check/require rewriting, propCheck, show (ADR-0009)
    signature.nim              # failure signatures from exception type + user stack frame (ADR-0006)
    shrink.nim                 # shrink passes on choice sequences, tried-sequence cache
    engine.nim                 # Settings, run loop: explore, shrink, double re-run, results
    report.nim                 # text report
    database.nim               # run seed, crash breadcrumbs (ADR-0003); failure database (planned)
    derive.nim                 # (planned) compile-time generators for objects and distinct types
    stateful.nim               # stateMachine and replayCommands macros, sequence runner (ADR-0011)
    unittest2.nim              # (planned) optional adapter, explicit import (ADR-0002)
```

### Drawing primitives

Every generator is built from these `ChoiceSource` procs; each records one choice per call:

| Primitive | Choice | Simplest value |
|---|---|---|
| `drawUpTo(bound)` | `0 .. bound`, uniform | 0 |
| `drawBool(p)` | 0 or 1 | `false` |
| `drawIndex(n)` | `0 ..< n`, uniform | first element |
| `drawMagnitude(max)` | `0 .. max`, biased to small values and boundaries while exploring | 0 |
| `drawInt(lo, hi)` | optional sign choice + magnitude from the value closest to 0 | value closest to 0, positive before negative |
| `drawFloat` / `drawFloatRange` | kind (finite or special), sign, whole part, fraction, scale | 0.0 |
| `initMany` + `more` | one "continue" choice per optional element; each element recorded as a span | empty collection |

The random distribution (what is likely while exploring) and the shrink order (what is simple) are independent: the bias lives only in random mode, and replay just reads choices.

## Life of a property

```
forAll(...)
  ├─ derive property seed = SplitMix64(run seed, FNV-1a(property name))
  ├─ write run seed to .proptest/last-run                  (crash breadcrumbs)
  ├─ (planned) replay saved sequences from the failure database (R3)
  ├─ (planned) replay explicit examples                         (R4)
  └─ for each of `cases` cases (continuing after a failure, until maxFailures distinct):
       ├─ choice source records draws from the PRNG (size grows over the run)
       ├─ generators build the inputs (overrun → invalid case)
       ├─ run the body (assertions raise, exceptions caught)
       ├─ ok / discarded (assume) / failed (signature) / generator error
       └─ health checks: discard ratio and filter rejections (generation time and sizes planned)
  on failure, for each distinct signature (up to the limit):
       ├─ shrink the sequence: delete spans (elements, steps), delete chunks, zero,
       │    lower (binary search), then merge
       │    accept candidate only if smaller in shortlex AND same signature
       ├─ re-run the minimal sequence twice: fails both times → counterexample; otherwise → flaky
       ├─ save the sequence to the failure database
       └─ report: inputs, error, seed, replay command, statistics
```

## Life of a stateful sequence

A machine is a property whose input is a command sequence ([ADR-0011](decisions/0011-stateful-testing.md)); the engine above runs it unchanged.

```
stateMachine M:              (one runner closure, commands inlined in a case)
  ├─ model := fresh model expression; setup statements (fresh system)
  ├─ loop:
  │    ├─ enabled := commands whose precondition holds on the model
  │    ├─ none enabled, or "continue" choice is 0 → stop
  │    ├─ draw the command among the enabled ones, then its arguments
  │    ├─ run; postcondition (result vs model, before update); update model
  │    ├─ invariant
  │    └─ close the step's span
  └─ teardown (always, once setup succeeded)
replayCommands M: the same runner, fed with given steps; a violated
precondition raises ValueError instead of being skipped.
```

## Tests and benchmarks

```
tests/
  config.nims          # path to ../src
  helpers.nim          # compile and run fixtures in a separate process
  t_prng.nim           # golden values from the reference C code (RL1, RL2, Q7)
  t_choices.nim        # drawing primitives, replay, bounds, allocation (G*, S1, PF4, RL7)
  t_gen.nim            # type-inferred generators, combinators, golden values (G*, C*, RL15)
  t_shrink.nim         # the shrinker with synthetic probes (S*, RL14, PF6)
  t_engine.nim         # run loop, reports, settings, signatures (A*, K*, R*, RL*, I3)
  t_integration.nim    # fixtures: unittest output, env vars, files, compile errors (I1, O1, A7, R2, RL9)
  t_values.nim         # SPEC Part IV reference bugs and their exact minima (V-*)
  fixtures/            # small programs compiled and run by t_integration
benchmarks/
  harness.nim          # warm-up, 30 samples, median/p95/p99, allocations
  b_gen.nim            # cost per choice / value / case vs. a hand-written loop; allocation gate
  b_shrink.nim         # executions per reference bug; gate against baseline/shrink.json
scripts/
  check_traceability.nim
```

Test names cite the SPEC IDs they verify; value tests use `V-<ID>`. Several tests use `forAll` on the library itself (dogfooding, Q5).

## Determinism contract

Given the same library version, the same generator code and the same seed, the sequence of cases, the shrink path and the final counterexample are identical on every platform and backend. Golden tests (Q7) enforce this; the CHANGELOG lists every change that breaks it (RL15).

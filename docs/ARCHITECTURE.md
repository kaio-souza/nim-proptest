# Architecture (planned)

Status: **design**. This document ties the ADRs into one picture of how a property runs. It will be updated to describe the actual code once v0.1 exists.

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
| **Flaky** | A property whose final counterexample does not fail again when re-run. |
| **Failure database** | `.proptest/` directory with the minimal sequences of past failures ([ADR-0003](decisions/0003-reproducibility-and-failure-database.md)). |

## Planned modules

```
src/
  proptest.nim                 # public API: forAll, assume, generators, std/unittest adapter
  proptest/
    prng.nim                   # SplitMix64, xoshiro256**, stable FNV-1a hash (ADR-0005)
    choices.nim                # ChoiceSource, preallocated buffer, overrun (ADR-0001, ADR-0007)
    gen.nim                    # Gen[T], built-in generators, combinators
    derive.nim                 # compile-time generators for objects and distinct types
    shrink.nim                 # shrink passes on choice sequences, tried-sequence cache
    engine.nim                 # run loop: generate, execute, classify, shrink, re-run
    signature.nim              # failure signatures and flaky detection (ADR-0006)
    assertions.nim             # check/require rewriting inside forAll (ADR-0009)
    report.nim                 # text and JSON reports, statistics, health checks
    database.nim               # failure database and crash breadcrumbs (ADR-0003)
    stateful.nim               # models, commands, sequence generation (v0.2)
    unittest2.nim              # optional adapter, explicit import (ADR-0002)
```

## Life of a property

```
forAll(...)
  ├─ derive property seed = SplitMix64(run seed, FNV-1a(property name))
  ├─ write run seed to .proptest/last-run                  (crash breadcrumbs)
  ├─ replay saved sequences from the failure database      (R3)
  ├─ replay explicit examples                              (R4)
  └─ for each case until `cases` or the time budget:
       ├─ choice source records draws from the PRNG (size grows over the run)
       ├─ generators build the inputs (overrun → invalid case)
       ├─ run the body (assertions raise, exceptions caught)
       ├─ ok / discarded (assume) / failed (signature) / generator error
       └─ health checks on discard ratio, generation time, sizes
  on failure, for each distinct signature (up to the limit):
       ├─ shrink the sequence: delete, zero, lower (binary search), sort spans
       │    accept candidate only if smaller in shortlex AND same signature
       ├─ re-run the minimal sequence: fails again → counterexample; passes → flaky
       ├─ save the sequence to the failure database
       └─ report: inputs, error, seed, replay command, statistics
```

## Determinism contract

Given the same library version, the same generator code and the same seed, the sequence of cases, the shrink path and the final counterexample are identical on every platform and backend. Golden tests (Q7) enforce this; the CHANGELOG lists every change that breaks it (RL15).

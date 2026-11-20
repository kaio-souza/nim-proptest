# ADR-0016: Targeted exploration

- Status: Accepted
- Date: 2026-11-20
- Requirements: D4 (new), M2; follows ADR-0012

## Context

ADR-0012 left one row of `b_find` out of reach: a circuit breaker whose backoff cap needs five reopenings in a row, each after waiting long enough. Swarm testing, boundary hints and edge bias found it on 3 of 100 seeds. Random sequences rarely chain five rare events; each extra reopening multiplies the odds against. The known technique is targeted property-based testing (Löscher and Sagonas, ISSTA 2017; Hypothesis's `target()`): the property reports a score, and the engine searches for cases that raise it.

## Decision

- **API**: `target(score, name = "")` inside a `forAll` body or a `stateMachine` command or invariant, rewritten like `classify` (it needs the choice source). Each case keeps its highest score per name. NaN is ignored.
- **Search**: the engine keeps, per name, the passing case with the highest score (its choice sequence; copied only on improvement). Once half of the cases have run, every other case is an **extension**: it replays a prefix of a best case, at least half of it and chosen at random, then continues exploring at random. Names take turns.
- **Extension**: the prefix is forced inside random mode (`ChoiceSource.forced`), so every exploration decision (hints, swarm, sizes) still applies after it. A collection that already reached its random target length keeps growing with probability 7/8 per element after the prefix, so a command sequence can be extended rather than stopping where the best case stopped.
- **Report**: the best score per name appears in the notes of a passing property, in the failure report and in the JSON report (`targets`, a new field of `format` 1).
- **No target, no change**: a property that never calls `target` explores exactly as before.

### Parameters, measured

`b_find`, breaker backoff cap with `target(float(model.level))` in the invariant, 100 seeds:

| Start | Extension cases | Prefix kept | Found |
|---|---|---|---|
| after 1/2 of the cases | 1 in 2 | ≥ 1/2 | **20** |
| after 1/2 | 1 in 3 | ≥ 1/2 | 20 |
| after 1/3 | 1 in 2 | ≥ 1/2 | 16 |
| after 1/4 | 1 in 2 | ≥ 1/2 | 16 |
| after 1/2 | every case | ≥ 1/2 | 14 |
| after 1/2 | 1 in 2 | any | 13 |
| after 1/2 | 1 in 2 | ≥ 3/4 | 13 |
| after 1/4 | every case | ≥ 3/4 | 9 |

Without `target`: 3. More targeting is worse: the search needs a diverse first half to find a good start, and random cases between extensions keep finding new starts.

## Consequences

- Deep states become reachable when the property can measure progress toward them (a model field, a queue length, a nesting depth). The breaker cap goes from 3 to 20 of 100 seeds; a counter that must reach 25 among increments, decrements and resets from 29 to 36 of 40 (`t_find`).
- It helps much less for independent values: a list with many odd elements did not improve consistently, because there is no accumulated progress to extend. The README says so and points to `near` hints and dedicated generators instead.
- A target that is not monotone in the state (it goes up and down along a sequence) still works, because the case's score is its maximum.
- Extension cases replay prefixes, so `target` makes a property's exploration depend on its own scores: still deterministic for a seed.

## Evidence

`benchmarks/b_find.nim` row "breaker: backoff cap, target(level)" (gate baseline); `tests/t_find.nim`, "targeted exploration (D4)"; the golden snapshot section "targeted exploration".

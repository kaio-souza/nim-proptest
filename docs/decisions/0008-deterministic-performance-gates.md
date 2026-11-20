# ADR-0008: Deterministic performance gates

- Status: Proposed
- Date: 2026-11-19
- Requirements: PF1, PF6, PF7, EV2, EV7

## Context

Wall-clock benchmarks on shared CI runners are noisy, so a timing gate with a fixed limit fails at random (in `circuit_breaker` this kept the regression gate deferred). The most important performance properties of this library can be measured without time:

- **Shrinking cost**: the number of property executions needed to reach the minimal counterexample of a reference bug. For a fixed seed this number is exactly reproducible.
- **Allocation cost**: allocations per case and per choice, counted by the allocator.

## Decision

- CI **gates** on deterministic metrics:
  - executions to shrink each reference bug (SPEC Part IV), with a committed baseline; a regression above the baseline fails the build;
  - allocations per choice (must be 0) and per case for built-in generators.
- Wall-clock benchmarks (ns per choice, per value, per case, compile time) are run and published in the job summary and README, in debug and release, but never fail a build.
- Baselines are updated only by an explicit change with a justification.

## Consequences

- Shrinker regressions and accidental allocations are caught automatically, with zero false positives.
- A faster but differently ordered shrinker may change execution counts; that is a deliberate baseline update, reviewed like any other change.

## Evidence

CI job comparing execution and allocation counts against the committed baseline.

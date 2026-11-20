# ADR-0003: Seeds for replay and a local failure database

- Status: Proposed
- Date: 2026-11-19
- Requirements: R1–R5, K2, M4

## Context

A random test that fails once and passes on the next run is worse than no test: it erodes trust and is hard to debug. Property failures must be repeatable on any machine, and a counterexample found once should not be lost after the bug is "fixed".

## Decision

- Every property run derives its RNG from a seed, using the library's own PRNG (ADR-0005). The seed is printed on failure with a one-line replay command; `PROPTEST_SEED` fixes it for a run.
- Each property gets its own stream derived from the run seed and the property name (stable hash, ADR-0005), so adding or reordering properties does not change the cases of others (R5).
- **Crash breadcrumbs**: the run seed is written to `.proptest/last-run` before the first case, so a crash or a killed hang can still be replayed (RL9).
- **Failure database**: after shrinking, the minimal choice sequence is saved to `.proptest/<property-key>` in the project directory. On the next run, saved sequences are replayed before random cases. Entries are removed when they pass N consecutive times.
- The database format is versioned; writes are atomic (temporary file + rename), so concurrent test processes never corrupt it; entries that no longer fit the current generators are discarded, never reported as failures (RL12).
- The database is a plain directory meant to be ignored by git; CI can cache it.
- Stateful failures are also printed as runnable Nim code (M4), which is the form meant to be committed as a regression test.

## Consequences

- Replay is exact only for the same library version and generator code; the report says so.
- The database adds file I/O to test runs; it can be disabled by configuration.

## Evidence

R3 value test (a previously failing case runs first); test that the same seed produces the same cases across runs.

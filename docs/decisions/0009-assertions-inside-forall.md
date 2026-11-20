# ADR-0009: Assertions inside `forAll`

- Status: Proposed
- Date: 2026-11-19
- Requirements: A1, A6, O1, I1, I2

## Context

In `std/unittest` (and `unittest2`), a failed `check` does not raise. It prints a message, marks the current test as failed and lets the code continue. Inside a property this breaks the engine twice:

1. The engine cannot see that a case failed, so it cannot shrink.
2. Each failing case explored during generation and shrinking would print its own failure: hundreds of lines for a single bug, and a test marked failed even if the final result is a flaky report.

## Decision

- The `forAll` macro rewrites `check` and `require` calls **inside its body** into the library's own assertions. They evaluate the same expression and, on failure, raise an internal `PropertyFailed` exception carrying the expression text and, when available, the values of its operands (like `check` prints them).
- `PropertyFailed` is a `CatchableError`, so it works with `--panics:on` too; its signature (ADR-0006) is the location of the rewritten `check`.
- The engine reports to the host runner once, after shrinking and the flaky re-run: through `checkpoint` + `fail()` in `std/unittest`, and through the equivalent in the `unittest2` adapter (I2).
- `doAssert`/`assert` and any raised exception keep working unchanged (they already raise).
- Calls to `check` in procs called *from* the body are not rewritten (macros only see the body); the documentation recommends `doAssert` or returning `bool` in helpers, and a health check (RL11) warns when the runner's test status changes during exploration.

## Consequences

- Properties read like ordinary unit tests and produce a single, clean failure.
- The rewriting depends on the shape of `check`/`require` in the supported runners; adapter tests cover each runner version in CI.

## Evidence

A6 value test (one failure reported, no intermediate output); tests for both runners.

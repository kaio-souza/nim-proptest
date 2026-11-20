# ADR-0002: Zero dependencies; runner-agnostic core with adapters

- Status: Proposed
- Date: 2026-11-19
- Requirements: I1–I3, Q1

## Context

Nim projects test with `std/unittest`, `unittest2`, or plain programs that `doAssert`. A testing library that forces one runner, or pulls dependencies into every test build, limits who can adopt it.

## Decision

- The core (generators, shrinking, `forAll` engine) depends only on the standard library and returns a result object; it does not print or fail by itself.
- Thin adapters turn that result into a failure of the host runner:
  - `std/unittest`: part of the main module (it is in the stdlib).
  - `unittest2`: an optional module, imported explicitly; the package does not declare it as a dependency.
  - Standalone: the result object can be inspected or raised as an exception.
- Requires the same Nim baseline as `circuit_breaker` (>= 2.2.4) unless a lower one is proven in CI.

## Consequences

- Installing the package downloads nothing else.
- The `unittest2` adapter is compiled only by users who import it; CI must test it separately.

## Evidence

`.nimble` with only `requires "nim >= ..."`; CI jobs for each adapter.

## Amendment (2026-11-20): no `unittest2` module

The adapter module turned out to be unnecessary. `forAll` and `checkStateMachine` expand to `checkpoint(report); fail()` inside a test, detected with `declared(testStatusIMPL)`, and leave those names unbound, so they resolve at the call site: to `std/unittest` or to `unittest2`, whichever the test file imports. `unittest2` defines the same three names with the same meaning, and the `check`/`require` rewriting (ADR-0009) works by name. Users import `proptest` and `unittest2`, nothing else.

Evidence: `tests/fixtures/f_unittest2.nim` (a passing property, a failing one and a state machine) and the I2 test in `t_integration`. CI installs `unittest2` 0.3.0 and sets `PROPTEST_REQUIRE_UNITTEST2`, so the test cannot be skipped there; locally it is skipped when `unittest2` is not installed. If a later `unittest2` changes those names, the module of the original decision is the fallback.

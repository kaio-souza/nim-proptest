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

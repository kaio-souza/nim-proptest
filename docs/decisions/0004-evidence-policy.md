# ADR-0004: Evidence policy

- Status: Accepted
- Date: 2026-11-19
- Requirements: EV1–EV6, Q5

## Context

A testing library that is not itself rigorously tested is hard to trust. Shrink quality and generation speed are easy to claim and hard to verify.

## Decision

Adopt the same evidence policy as `circuit_breaker`:

1. Every requirement has a test that cites its ID in the name.
2. Every differentiator has a value test built around a planted reference bug, with the expected minimal counterexample (SPEC Part IV).
3. Generation, per-case overhead and shrinking have benchmarks.
4. Every fixed bug gets a regression test.
5. A traceability matrix (`docs/TRACEABILITY.md`) is checked in CI once code exists.
6. The library tests itself with properties (dogfooding).

## Consequences

More work per feature; in exchange, every claim in the README is backed by the repository.

## Evidence

Traceability check in CI (to be added with the first code).

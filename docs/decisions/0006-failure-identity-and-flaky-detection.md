# ADR-0006: Failure identity and flaky detection

- Status: Proposed
- Date: 2026-11-19
- Requirements: RL3, RL4, RL5, RL6, A3

## Context

Two classic ways for a property-based testing tool to lie:

1. **Slippage**: while shrinking, a candidate fails for a *different* reason (e.g. the original assertion bug shrinks into an input that hits an unrelated `IndexDefect`). A naive shrinker accepts it because "it still fails", and the user gets a minimal example of the wrong bug.
2. **Flakiness**: the property depends on time, global state, threads or the network. The reported counterexample passes when the user runs it, and trust in the tool collapses.

## Decision

- **Failure identity**: every failure gets a signature: the exception type plus the location of the raise or the failed `check` (file and line from the stack trace). During shrinking a candidate is accepted only if its signature equals the one being shrunk.
- **Multiple failures**: a candidate with a different signature is not discarded; it is kept as a new failure and shrunk separately, up to a configurable limit (default 3). The report lists each one.
- **Flaky detection**: before reporting, the final counterexample is executed again. If it does not fail with the same signature, the property is reported as **flaky**, with the original error and the outcome of the re-run, and a hint about common causes.
- **Generator errors** (exceptions in generators, exhausted filters, overruns) have their own category and never become property failures or signatures.

## Consequences

- Reports are trustworthy: what is printed reproduces, and it is the bug that was found.
- One extra execution per reported failure.
- Signatures depend on stack traces; in builds without them (`--stackTrace:off`), the identity falls back to the exception type and message, and the report says identity is weaker.

## Evidence

Value tests RL3 (alternating property reported as flaky), RL4 (no slippage to `IndexDefect`) and RL5 (two independent bugs both reported).

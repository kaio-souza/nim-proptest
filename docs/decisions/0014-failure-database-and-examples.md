# ADR-0014: Failure database and explicit examples

- Status: Accepted (implemented in v0.4); details ADR-0003 for R3/R4
- Date: 2026-11-20
- Requirements: R3, R4, RL12

## Context

Until v0.3, a counterexample found by a random run was gone at the next run unless someone copied its seed or replay block. Fixing a bug and rerunning gave no evidence: the next random run might not hit the case again. ADR-0003 decided on a failure database; this ADR fixes the details that implementation needed.

## Decision

### Failure database (R3, RL12)

- **What is saved**: after the double re-run, the minimal choice sequence of each reproduced failure (flaky ones are not saved).
- **Where**: `<PROPTEST_DB>/db/<key>.txt` (default `.proptest/db/`), one file per property.
- **Key**: the property name when given (`initSettings(name = ...)`); otherwise the file name plus a hash of the property's code (the `forAll` body, or the machine definition). A key from `file:line` would orphan entries whenever lines move; a code hash keeps them while the property is unchanged, and drops them when it changes (the old sequences would mean something else anyway).
- **Format**: a first line `proptest-db 1` (version), then one entry per line: `<passes> <choice> <choice> ...`. Another version is ignored, not an error.
- **Use**: before exploring, each saved sequence is replayed. If it fails, it is a failure like any other: shrunk (usually already minimal), reported, and marked "from the failure database". If it passes, its pass count goes up; after **3 passes in a row** it is removed, so a fixed bug is re-checked on the next runs and then forgotten. A sequence that is discarded, overruns or makes a generator raise no longer fits the generators: it is removed, never reported (RL12).
- **Writes**: a temporary file in the same directory, then a rename: atomic, so concurrent test processes never leave a half-written file. Errors are ignored: the database never fails a test.
- `PROPTEST_DB=off` disables it, as it disables the breadcrumbs.

### Explicit examples (R4)

`example(...)` among the arguments of `forAll`, with one value per variable in order, runs before any random case:

```nim
forAll(x in int, s in string, example(0, ""), example(-1, "a")):
  check parse($x & s).isOk
```

A failing example is reported with its inputs and is not shrunk (it is fixed by definition). Random exploration still runs, to find other bugs. In state machines, `replayCommands` blocks play this role.

## Consequences

- A second run after a failure re-checks the failing case first: the fix is verified immediately, before any random case.
- `.proptest/` must stay out of version control (already documented); CI can cache it to carry failures between runs.
- Values replayed from the database depend on the generators: after a generation change (CHANGELOG), old entries may pass or be removed. That is acceptable: the database is a cache, the `replayCommands` block and `example(...)` are the permanent regression tests.

## Evidence

Value test (SPEC Part IV): a property that failed in the previous run fails on the saved case before any random case (`firstFailureAt == 1`). Tests: entry removed after 3 passes; a sequence that no longer fits is removed silently; corrupted and other-version files are ignored; atomic write leaves no temporary file; `PROPTEST_DB=off` writes nothing; examples run first, are not shrunk, and report their inputs.

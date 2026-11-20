# ADR-0017: Watchdog for cases that never return

- Status: Accepted
- Date: 2026-11-20
- Requirements: RL10 (moved from after 1.0, raised to P1), RL8, RL9, R3

## Context

`deadline` (RL8) measures a case after it returns, so a case that never returns (an infinite loop, a deadlock, a wait for an event that never comes) hangs the whole test program. In CI the job then runs until its time limit and shows nothing about the cause. The run seed was already written to `.proptest/last-run` (RL9), but replaying it only hangs again, and verbose output prints a case after it returns, so the hanging case itself is never printed.

Nim cannot stop a thread in the middle of arbitrary code: there is no safe way to interrupt the case and continue the run, and so no way to shrink it in the same process.

## Decision

- **A watchdog thread**, started by the first property that runs (`--threads:on` only, Nim 2's default; compiled out otherwise). The engine bumps an atomic counter at the start of every case (exploration, saved cases, examples, shrink candidates, re-runs) and says what it is doing. The thread wakes every `hangTimeout / 10` (5 to 500 ms); when the counter has not moved for `hangTimeout`, it fires.
- **When it fires**, it prints the property, what was running, whether inputs were being generated or the body was running, the inputs or stateful steps when they were recorded, the case's choices and the replay command; saves the case in the failure database marked as hung (`passes = -1`); appends a `"status": "hung"` line to the JSON report; and ends the process with exit code 1.
- **Inputs on the next run**: recording inputs on every case would cost time on every case, so exploration does not. Saved cases and explicit examples are now replayed with their inputs recorded (they are few), so the next run, which replays the hung case first, prints its inputs if it hangs again. `PROPTEST_VERBOSITY=verbose` records them on every case, for the first run.
- **`hangTimeout`**: off by default (0); `PROPTEST_HANG_TIMEOUT` or the setting turns it on. Ending the process is drastic, and a default timeout would also end a debugging session paused inside a case, or a property whose cases are legitimately slow. The documentation recommends turning it on in CI (60 s), where a hang otherwise runs until the job's time limit with no clue; the library's own CI does.
- **One property at a time**: the watchdog is armed by one property; a property nested in another, or run concurrently on another thread, is not armed but still counts as progress.

Rejected:

- **Shrinking the hang in child processes** (re-running the test binary with the candidate choices, one process per shrink step): every step that still hangs costs a full timeout and a process start, the binary would have to run only that property, and the result is a smaller hang rather than a cause. The saved case plus its printed inputs gets most of the value.
- **Generating the inputs from the watchdog thread** (replaying the generators up to the body): it would run the property's closures on a second thread while the first is still running, sharing reference counts without synchronization.

## Consequences

- With the watchdog on, a hang becomes a report with a replay command and, from the next run, the inputs; in CI it fails fast with that report instead of timing out. With it off (the default), a hang behaves as before: the run hangs until it is stopped.
- The process ends: properties after the hanging one do not run in that run, and the unittest summary is not printed. The JSON report says `hung`.
- Cost: one atomic increment per case and a thread sleeping in the background; no allocation per case.
- The watchdog reads the property's choice buffer while the property's thread is stuck. It does not lock it: the stuck thread is not drawing choices, and the process ends right after.

## Evidence

`tests/fixtures/f_hang.nim` and the RL10 tests in `t_integration` (report on the first run, inputs on the second, a `hung` JSON line, inputs at once with verbose output); `t_engine` runs 3000 fast cases with a 25 ms timeout without firing.

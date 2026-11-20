## Fixture: a property that never returns when x is 42 (RL10). Run with a
## short PROPTEST_HANG_TIMEOUT; the watchdog reports it and ends the process.
import proptest, std/os

let r = forAllResult(initSettings(name = "hangs on 42", seed = 1), x in ints(0, 100, near = [42])):
  while x == 42:
    sleep(10)                # never returns: a deadlock or a lost wake-up
echo "not reached: ", r.status

## Fixture: properties whose results go to the JSON report when
## PROPTEST_REPORT is set (O3): one passing with statistics, one failing
## with a message that needs escaping, and a state machine.
import proptest
import f_machine

discard forAllResult(initSettings(name = "passing", seed = 1), x in ints(0, 9)):
  classify(x < 5, "small")
  cover(10.0, x == 0, "zero")

discard forAllResult(initSettings(name = "failing", seed = 1), s in string):
  if s.len > 0:
    # Quotes, a backslash, a newline and a byte that is not valid UTF-8.
    raise newException(ValueError, "bad \"input\"\\\nbyte \xFF")

discard stateMachineResult(BoundedQueue, initSettings(seed = 1))
echo "done"

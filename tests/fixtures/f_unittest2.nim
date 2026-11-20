## Fixture: the f_unittest properties, and a state machine, inside unittest2
## (I2). Compiled only when unittest2 is installed.
import proptest, unittest2
import f_machine

suite "fixture":
  test "passes":
    forAll(initSettings(seed = 1), x in int):
      check x == x

  test "fails":
    forAll(initSettings(seed = 1), x in ints(0, 1000)):
      check x < 500

  test "machine":
    checkStateMachine(BoundedQueue, initSettings(seed = 1))

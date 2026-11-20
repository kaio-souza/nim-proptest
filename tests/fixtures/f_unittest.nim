## Fixture: one passing and one failing property inside std/unittest.
import proptest, std/unittest

suite "fixture":
  test "passes":
    forAll(initSettings(seed = 1), x in int):
      check x == x

  test "fails":
    forAll(initSettings(seed = 1), x in ints(0, 1000)):
      check x < 500

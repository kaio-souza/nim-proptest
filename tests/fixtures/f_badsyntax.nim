## Fixture: must NOT compile (`name = gen` is not a valid variable form).
import proptest

forAll(x = ints(), y in int):
  discard

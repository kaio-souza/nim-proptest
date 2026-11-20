## Fixture: must NOT compile (example with the wrong number of values).
import proptest

forAll(x in int, s in string, example(1)):
  discard

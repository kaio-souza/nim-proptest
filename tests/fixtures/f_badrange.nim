## Fixture: must NOT compile (a case object with a range discriminant).
import proptest

type Event = object
  case kind: range[0 .. 1]
  of 0: a: int
  of 1: b: string

forAll(e in Event):
  discard

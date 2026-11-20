## Fixture: must NOT compile (a field type with no generator).
import proptest

type Handler = object
  name: string
  callback: proc (x: int): int

forAll(h in Handler):
  discard

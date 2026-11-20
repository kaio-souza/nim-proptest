## Fixture: must NOT compile (a command argument declared as `x: T`).
import proptest

stateMachine Broken:
  model: 0
  command put(x: int):
    run: discard

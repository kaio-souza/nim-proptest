## Fixture: must NOT compile (a command without `run:`).
import proptest

stateMachine Broken:
  model: 0
  command noop():
    precondition: true

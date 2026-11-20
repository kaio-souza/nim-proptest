## Fixture: a queue with a planted bug, defined in its own module so that
## tests can import the machine (generated symbols are exported) and so that
## a printed `replayCommands` block can be compiled on its own (M4).

import proptest

type
  Queue* = ref object
    items: seq[int]
    pushes, pops: int
  QueueModel* = object
    items*: seq[int]

proc push*(q: Queue; x: int) =
  q.items.add x
  inc q.pushes

proc pop*(q: Queue): int =
  ## Planted bug (SPEC Part IV): wrong after exactly 3 pushes and 1 pop.
  result = q.items[0]
  q.items.delete(0)
  inc q.pops
  if q.pushes == 3 and q.pops == 1: inc result

proc len*(q: Queue): int = q.items.len

stateMachine BoundedQueue:
  model: QueueModel()
  setup:
    let q = Queue()
  command push(x in ints(-10, 10)):
    precondition: model.items.len < 3
    run: q.push(x)
    update: model.items.add x
  command pop():
    precondition: model.items.len > 0
    run: q.pop()
    postcondition: result == model.items[0]
    update: model.items.delete(0)
  invariant: q.len == model.items.len

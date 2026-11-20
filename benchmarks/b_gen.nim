## PF1/PF4/PF5: cost of drawing choices and generating values, against a
## hand-written random loop with no library (the baseline).
##
## Each operation is one case of 100 values, so numbers are comparable to a
## property run; divide by 100 for the cost per value.
##
## `--check` (with -d:nimAllocStats): fails if drawing choices or running a
## stateful step (outside user code) allocates.

import std/os
import harness
import ../src/proptest, ../src/proptest/prng

const
  perCase = 100
  ops = 2_000

type CounterModel = object
  value: int

# A machine whose own code never allocates: what remains is the library's
# cost per step (ADR-0011: zero allocations per step outside user code).
stateMachine Counter:
  model: CounterModel()
  setup:
    var counter = 0
  command add(by in ints(0, 3)):
    run: counter += by
    update: model.value += by
  command reset():
    precondition: model.value > 0
    run: counter = 0
    update: model.value = 0
  invariant: counter == model.value

proc main() =
  header("generation (one op = one case of 100 values)")
  var rng = initXoshiro256(1)
  let src = newChoiceSource(1)

  bench("baseline: 100 x xoshiro below(high)", ops):
    for _ in 0 ..< perCase: keep = int(rng.below(high(uint64)) and 1)
  bench("PF4 100 x drawUpTo (choice recorded)", ops):
    src.startRandom(50)
    for _ in 0 ..< perCase: keep = int(src.drawUpTo(high(uint64)) and 1)
  let drawRow = results[^1]

  bench("PF5 100 x arbitrary(int) (TypeGen, no closure)", ops):
    src.startRandom(50)
    for _ in 0 ..< perCase: keep = src.drawFrom(TypeGen[int]())
  let g = ints(low(int), high(int))
  bench("PF5 100 x ints() (Gen closure)", ops):
    src.startRandom(50)
    for _ in 0 ..< perCase: keep = src.drawFrom(g)
  bench("100 x arbitrary(bool)", ops):
    src.startRandom(50)
    for _ in 0 ..< perCase: keep = ord(src.arbitrary(bool))
  bench("100 x arbitrary(float)", ops):
    src.startRandom(50)
    for _ in 0 ..< perCase: keep = int(src.arbitrary(float) > 0.0)
  bench("1 x arbitrary(seq[int]) at size 50", ops):
    src.startRandom(50)
    keep = src.arbitrary(seq[int]).len
  bench("1 x arbitrary(string) at size 50", ops):
    src.startRandom(50)
    keep = src.arbitrary(string).len

  header("stateful (one op = one sequence of 50 steps)")
  let runner = stateMachineRunner(Counter)
  bench("M2 one sequence, 50 steps (2 commands)", ops div 10):
    src.startRandom(100)
    runner(src, @[], false, 50, true)
    keep = src.choiceCount
  let stepRow = results[^1]

  header("engine (one op = one run of 100 passing cases)")
  bench("PF1 forAllResult, x in int, empty body", 200):
    let r = forAllResult(initSettings(seed = 1, name = "bench"), x in int):
      keep = x
    keep = r.casesRun
  bench("PF1 forAllResult, xs in seq[int], empty body", 200):
    let r = forAllResult(initSettings(seed = 1, name = "bench"), xs in seq[int]):
      keep = xs.len
    keep = r.casesRun

  writeJson("gen.json")
  if "--check" in commandLineParams():
    when defined(nimAllocStats):
      if drawRow.allocsPerOp != 0.0:
        echo "FAIL: drawing choices allocates (", drawRow.allocsPerOp, " per op)"
        quit 1
      echo "OK: drawing choices does not allocate"
      if stepRow.allocsPerOp != 0.0:
        echo "FAIL: stateful steps allocate (", stepRow.allocsPerOp, " per sequence)"
        quit 1
      echo "OK: stateful steps do not allocate"
    else:
      echo "--check needs -d:nimAllocStats"
      quit 1

main()

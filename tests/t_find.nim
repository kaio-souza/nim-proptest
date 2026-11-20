## Finding bugs and showing what was tested (ADR-0012): labels and coverage,
## edge cases and boundary hints, swarm testing, deadlines and budgets,
## health checks, verbosity.

import std/[unittest, strutils, os, sequtils]
import proptest

proc found(r: PropertyResult): bool = r.status == psFailed

# --- Machines ------------------------------------------------------------------

type Counter = ref object
  n: int

# Needs 12 increments with no reset in between, among other commands.
stateMachine NoReset:
  model: 0
  setup:
    let c = Counter()
  command incr():
    run:
      inc c.n
      c.n < 12
    postcondition: result
    update: inc model
  command reset():
    run: c.n = 0
    update: model = 0
  command read():
    run: c.n
    postcondition: result == model
  command noop():
    run: discard
  command peek():
    run: c.n >= 0
    postcondition: result

# `never` is always disabled by its precondition; coverage per sequence.
stateMachine Coverage:
  model: 0
  command step():
    run: discard
    update:
      inc model
      cover(50.0, model >= 3, "reached 3 steps")
      classify(true, "steps")
  command never():
    precondition: model < 0
    run: discard

suite "labels and coverage (D1, D2, O4)":
  test "D1: classify reports the share of cases, discards and shrinking excluded":
    let r = forAllResult(initSettings(seed = 1, cases = 400), x in ints(0, 99)):
      assume(x != 50)
      classify(x < 10, "small")
      classify(x >= 10, "large")
    check r.passed
    check r.labeledCases == 400
    var small, large = 0
    for st in r.labels:
      if st.name == "small": small = st.cases
      if st.name == "large": large = st.cases
    check small + large == 400
    check small in 20 .. 200          # edges and small values favor 0 .. 9

  test "D1: label counts cases by a computed text":
    let r = forAllResult(initSettings(seed = 2), x in ints(0, 2)):
      label("x=" & $x)
    var names: seq[string]
    for st in r.labels: names.add st.name
    check "x=0" in names and "x=1" in names and "x=2" in names

  test "V-D2: cover fails when a class is generated too rarely, with the observed share":
    # SPEC Part IV: a generator that never produces empty strings.
    let r = forAllResult(initSettings(seed = 3), s in strings(minLen = 1)):
      cover(10.0, s.len == 0, "empty")
    check r.status == psInsufficientCoverage
    check "cover 'empty': 0.0% of 100 cases, 10.0% required" in r.message
    check "missed its coverage requirements" in formatReport(r)

  test "D2: a requirement that is only uncertainly missed is a warning, not a failure":
    let r = forAllResult(initSettings(seed = 4, cases = 20), x in ints(0, 99)):
      cover(30.0, x >= 50, "upper half")
    check r.status == psPassed
    var share = 0
    for st in r.labels:
      if st.name == "upper half": share = st.cases
    if share * 100 < 30 * 20:
      check r.warnings.len == 1
      check "too few cases to be sure" in r.warnings[0]

  test "D2/O4: in a state machine, cover counts sequences; commands are counted":
    let r = stateMachineResult(Coverage, initSettings(seed = 5, cases = 200))
    check r.status in {psPassed, psInsufficientCoverage}
    var reached, stepCmd, neverCmd, neverDisabled = -1
    for st in r.labels:
      if st.name == "reached 3 steps": reached = st.cases
      if st.name == "step" and st.kind == lkCommand: stepCmd = st.events
      if st.name == "never" and st.kind == lkCommand: neverCmd = st.cases
      if st.name == "never" and st.kind == lkDisabled: neverDisabled = st.events
    check reached in 1 .. 200                # a sequence counts once
    check stepCmd > 200                      # steps, not sequences
    check neverCmd == 0
    check neverDisabled > 0
    check r.warnings.anyIt("command 'never' never ran" in it)
    check r.lengthHist[0] + r.lengthHist[1] + r.lengthHist[2] < 200

  test "PF10: static labels do not allocate per case":
    let src = newChoiceSource(1)
    src.startRandom(10)
    src.recordLabel(0, true, "a", lkClassify)          # first call registers
    let before = getOccupiedMem()
    for i in 0 ..< 10_000:
      src.startRandom(10)
      src.recordLabel(0, i mod 3 == 0, "a", lkClassify)
    check getOccupiedMem() == before

suite "verbosity (O2)":
  test "O2: quiet prints nothing; normal shows labels and warnings; verbose shows all":
    let quiet = forAllResult(initSettings(seed = 6, verbosity = vQuiet), x in ints(0, 3)):
      classify(x == 0, "zero")
    check formatNotes(quiet) == ""
    let normal = forAllResult(initSettings(seed = 6), x in ints(0, 3)):
      classify(x == 0, "zero")
    check "Statistics (100 cases)" in formatNotes(normal)
    check "zero" in formatNotes(normal)
    let machine = stateMachineResult(NoReset, initSettings(seed = 6, verbosity = vVerbose,
                                                           swarm = false, cases = 3))
    if machine.passed:
      check "Commands (" in formatNotes(machine)
      check "Sequence lengths" in formatNotes(machine)

  test "O2: PROPTEST_VERBOSITY is validated":
    putEnv("PROPTEST_VERBOSITY", "loud")
    expect ValueError:
      discard initSettings()
    putEnv("PROPTEST_VERBOSITY", "verbose")
    check initSettings().verbosity == vVerbose
    delEnv("PROPTEST_VERBOSITY")

suite "edge cases, hints and swarm (G8, M2)":
  test "G8: integers, floats and collections hit their edge cases":
    let src = newChoiceSource(7)
    var high, low, zero, empty, single, special = 0
    for _ in 0 ..< 10_000:
      src.startRandom(50)
      let x = src.drawInt(low(int), high(int))
      if x == high(int): inc high
      if x == low(int): inc low
      if x == 0: inc zero
      let f = src.drawFloat()
      if f != f or f == Inf or f == -Inf or (f == 0.0 and 1.0 / f < 0): inc special
      var m = src.initMany(0, 100)
      var n = 0
      while src.more(m): inc n
      if n == 0: inc empty
      if n == 1: inc single
    check high > 300 and low > 300 and zero > 200
    check special > 300
    check empty > 500 and single > 500

  test "G8: edgeBias = 0 turns edge proposals off":
    let src = newChoiceSource(8, edgeBias = 0.0)
    var high = 0
    for _ in 0 ..< 10_000:
      src.startRandom(50)
      if src.drawInt(low(int), high(int)) == high(int): inc high
    check high == 0
    expect ValueError:
      validate(initSettings(edgeBias = 1.5))

  test "V-G8: near hints find a bug at an exact boundary inside the range":
    for seed in 1'u64 .. 20'u64:
      let r = forAllResult(initSettings(seed = seed, mineConstants = false),
                           ms in ints(0, 2000, near = [1000])):
        check ms != 1000
      check r.found
      check r.failures[0].inputs[0].value == "1000"

  test "V-G8: integer literals of the test file are mined as boundary hints":
    var mined, plain = 0
    for seed in 1'u64 .. 20'u64:
      let r = forAllResult(initSettings(seed = seed), x in ints(0, 5000)):
        check x != 1777
      if r.found: inc mined
      let r2 = forAllResult(initSettings(seed = seed, mineConstants = false), x in ints(0, 5000)):
        check x != 1777
      if r2.found: inc plain
    check mined >= 15
    check plain <= 3

  test "V-M2: swarm testing finds a bug that needs a command to stay away":
    var swarm, plain = 0
    for seed in 1'u64 .. 20'u64:
      if stateMachineResult(NoReset, initSettings(seed = seed)).found: inc swarm
      if stateMachineResult(NoReset, initSettings(seed = seed, swarm = false)).found: inc plain
    check swarm >= 18
    check plain <= 3

suite "deadlines and budgets (RL8, PF8, S4)":
  test "V-RL8: a case slower than the deadline is a failure, shrunk to its cause":
    # SPEC Part IV: slow when the input contains 42 (a loop that never ends
    # needs the watchdog of RL10, after 1.0).
    let r = forAllResult(initSettings(seed = 9, deadline = 20), xs in seqs(ints(0, 100))):
      if 42 in xs: sleep(60)
    check r.found
    check r.failures[0].signature.kind == "DeadlineExceeded"
    check r.failures[0].inputs[0].value == "@[42]"
    check "deadline 20.0 ms" in r.failures[0].message

  test "RL8: the deadline is off by default and set by PROPTEST_DEADLINE":
    check initSettings().deadline == 0
    putEnv("PROPTEST_DEADLINE", "250")
    check initSettings().deadline == 250
    delEnv("PROPTEST_DEADLINE")

  test "PF8: the time budget stops exploration gracefully and says so":
    let r = forAllResult(initSettings(seed = 10, cases = 1000, timeBudget = 50), x in int):
      sleep(5)
    check r.passed
    check r.casesRun < 1000
    check r.warnings.anyIt("time budget of 50 ms reached" in it)

  test "S4: the shrink time budget keeps the best counterexample so far":
    let r = forAllResult(initSettings(seed = 11, shrinkTimeBudget = 30), xs in seq[int]):
      sleep(2)
      check xs.len < 3
    check r.found
    check r.failures[0].shrinkStopped
    check "Shrinking stopped at its time budget" in formatReport(r)

suite "health checks (RL11)":
  test "RL11: data too large for maxChoices is reported, and can be suppressed":
    # Long lists in the later, larger cases exceed 150 choices.
    let big = seqs(ints(0, 9), 0, 100_000)
    let r = forAllResult(initSettings(seed = 12, maxChoices = 150), xs in big):
      discard
    check r.status == psPassed
    check r.overruns > 0
    check r.warnings.anyIt("needed more than maxChoices" in it)
    let quiet = forAllResult(initSettings(seed = 12, maxChoices = 150,
                                          suppress = {hcLargeData}), xs in big):
      discard
    check not quiet.warnings.anyIt("maxChoices" in it)

  test "RL11: a tiny input space is reported":
    let r = forAllResult(initSettings(seed = 13), b in bool):
      discard
    check r.warnings.anyIt("2 distinct inputs in 100" in it)

  test "RL11: generation dominating the run time is reported":
    let slow = newGen(proc(src: ChoiceSource): int =
      sleep(8)              # 12 timed cases x 8 ms: above the 50 ms threshold
      src.drawInt(0, 10))
    let r = forAllResult(initSettings(seed = 14, suppress = {hcFewDistinct}), x in slow):
      discard
    check r.warnings.anyIt("generating inputs takes" in it)

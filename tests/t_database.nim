## Failure database and explicit examples (ADR-0014): R3, R4, RL12.

import std/[unittest, os, strutils]
import proptest
import helpers
import fixtures/f_machine

let dbDir = getTempDir() / ("proptest-db-test-" & $getCurrentProcessId())

proc dbFiles(): seq[string] =
  if dirExists(dbDir / "db"):
    for f in walkFiles(dbDir / "db" / "*"): result.add f

proc fresh() =
  removeDir(dbDir)
  putEnv("PROPTEST_DB", dbDir)

var bugOn = true

proc buggy(x: int): bool =
  ## Planted: wrong for x >= 1000 while `bugOn`.
  not (bugOn and x >= 1000)

suite "failure database (R3, RL12)":
  test "V-R3: a failure of the previous run is replayed first":
    fresh()
    bugOn = true
    let first = forAllResult(initSettings(seed = 1, name = "db: buggy"), x in int):
      check buggy(x)
    check first.status == psFailed
    check first.failures[0].source == fsExplored
    check dbFiles().len == 1
    # Another seed: random exploration would find it later, if at all; the
    # saved case fails first.
    let second = forAllResult(initSettings(seed = 99, name = "db: buggy"), x in int):
      check buggy(x)
    check second.status == psFailed
    check second.firstFailureAt == 1
    check second.failures[0].source == fsDatabase
    check second.failures[0].inputs[0].value == "1000"
    check "Replayed from the failure database" in formatReport(second)

  test "R3: once fixed, an entry is re-checked, then forgotten after 3 passes":
    fresh()
    bugOn = true
    discard forAllResult(initSettings(seed = 2, name = "db: fixed"), x in int):
      check buggy(x)
    check dbFiles().len == 1
    bugOn = false
    for run in 1 .. 2:
      let r = forAllResult(initSettings(seed = 2, name = "db: fixed"), x in int):
        check buggy(x)
      check r.passed
      check dbFiles().len == 1
      check readFile(dbFiles()[0]).splitLines[1].startsWith($run & " ")
    let r = forAllResult(initSettings(seed = 2, name = "db: fixed"), x in int):
      check buggy(x)
    check r.passed
    check dbFiles().len == 0

  test "RL12: a saved sequence that no longer fits is dropped, never reported":
    fresh()
    discard forAllResult(initSettings(seed = 3, name = "db: fits"), x in ints(0, 10)):
      check x < 5
    check dbFiles().len == 1
    # The property now discards those inputs: the entry no longer fits.
    let r = forAllResult(initSettings(seed = 3, name = "db: fits"), x in ints(0, 10)):
      assume(x < 5)
    check r.passed
    check dbFiles().len == 0

  test "RL12: other versions and corrupted files are ignored":
    fresh()
    discard forAllResult(initSettings(seed = 4, name = "db: corrupt"), x in ints(0, 10)):
      check x < 5
    let f = dbFiles()[0]
    writeFile(f, "proptest-db 99\n0 7\n")
    let r = forAllResult(initSettings(seed = 4, name = "db: corrupt"), x in ints(0, 10)):
      check x < 50
    check r.passed
    writeFile(f, "proptest-db 1\nnot numbers\n")
    let r2 = forAllResult(initSettings(seed = 4, name = "db: corrupt"), x in ints(0, 10)):
      check x < 50
    check r2.passed

  test "RL12: writes are atomic and PROPTEST_DB=off writes nothing":
    fresh()
    discard forAllResult(initSettings(seed = 5, name = "db: atomic"), x in int):
      check x < 1000
    for f in walkFiles(dbDir / "db" / "*"):
      check ".tmp" notin f
    removeDir(dbDir)
    putEnv("PROPTEST_DB", "off")
    discard forAllResult(initSettings(seed = 5, name = "db: off"), x in int):
      check x < 1000
    check not dirExists(dbDir)

  test "R3: the default key follows the property's code, not its line":
    fresh()
    discard forAllResult(initSettings(seed = 6), x in ints(0, 100)):
      check x != 77
    check dbFiles().len == 1
    # The same code elsewhere in the file shares the entry...
    let same = forAllResult(initSettings(seed = 600), x in ints(0, 100)):
      check x != 77
    check same.firstFailureAt == 1
    # ...a different property does not.
    let other = forAllResult(initSettings(seed = 600), x in ints(0, 100)):
      check x != 78
    check other.failures.len == 0 or other.failures[0].source != fsDatabase

  test "R3: the key ignores the macro's own rewrites (labels, checks)":
    # Regression: the key hashed the rewritten body, whose gensym'd names
    # differ between two copies of the same code.
    fresh()
    discard forAllResult(initSettings(seed = 6), x in ints(0, 100)):
      classify(x > 50, "high")
      check x != 77
    check dbFiles().len == 1
    let same = forAllResult(initSettings(seed = 600), x in ints(0, 100)):
      classify(x > 50, "high")
      check x != 77
    check same.firstFailureAt == 1
    check same.failures[0].source == fsDatabase

  test "R3: state machines replay their saved sequence first":
    fresh()
    let first = stateMachineResult(BoundedQueue, initSettings(seed = 7))
    check first.status == psFailed
    let second = stateMachineResult(BoundedQueue, initSettings(seed = 70))
    check second.firstFailureAt == 1
    check second.failures[0].source == fsDatabase
    check second.failures[0].steps == @["push(0)", "push(0)", "push(0)", "pop()"]
    removeDir(dbDir)
    putEnv("PROPTEST_DB", "off")

suite "explicit examples (R4)":
  test "V-R4: examples run before random cases and report their inputs":
    let r = forAllResult(initSettings(seed = 8), x in ints(0, 10), s in string,
                         example(3, "magic"), example(4, "")):
      check s != "magic"
    check r.status == psFailed
    check r.firstFailureAt == 1
    check r.failures[0].source == fsExample
    check r.failures[0].inputs == @[(name: "x", value: "3"), (name: "s", value: "\"magic\"")]
    check r.failures[0].shrinkExecutions == 0
    check "An explicit example (not shrunk)" in formatReport(r)

  test "R4: passing examples are run too, and random cases still follow":
    var seen: seq[int]
    let r = forAllResult(initSettings(seed = 9, cases = 20), x in ints(0, 1_000_000),
                         example(424242)):
      seen.add x
    check r.passed
    check seen[0] == 424242
    check seen.len == 21

  test "R4: examples work with classify, cover and label in the body":
    # Regression: the body was rewritten in place, so the example's copy
    # referred to the random cases' `src` and did not compile.
    let r = forAllResult(initSettings(seed = 10, cases = 50), x in ints(-5, 5),
                         example(1), example(-1)):
      classify(x > 0, "positive")
      cover(1, x < 0, "negative")
      label(if x == 0: "zero" else: "nonzero")
      check x != 1
    check r.status == psFailed
    check r.failures[0].source == fsExample
    check r.failures[0].inputs == @[(name: "x", value: "1")]

  test "R4: an example with the wrong number of values is a compile error":
    let (log, ok) = compileFixture("f_badexample")
    check not ok
    check "example(...) needs one value per variable (2)" in log

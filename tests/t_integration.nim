## End-to-end behavior through separately compiled fixture programs:
## runner output, environment variables, files and compile-time messages.

import std/[unittest, os, strutils]
import helpers

suite "integration":
  test "I1/O1/A6: a failing property fails its unittest test once, without intermediate output":
    let (buildLog, ok) = compileFixture("f_unittest")
    check ok
    if not ok: echo buildLog
    let (output, code) = runFixture("f_unittest", {"PROPTEST_DB": "off"})
    check code == 1
    check "[OK] passes" in output
    check "[FAILED] fails" in output
    # One report, despite the dozens of failing cases explored while shrinking.
    check countOf(output, "check failed") == 1
    check countOf(output, "falsified") == 1
    check "x = 500" in output

  test "A7: --panics:on is reported at compile time":
    let (buildLog, ok) = compileFixture("f_unittest", "--panics:on -o:" &
      quoteShell(fixturesDir / "f_unittest_panics"))
    check ok
    check "proptest: compiled with --panics:on" in buildLog

  test "R1/R2: PROPTEST_SEED replays a run exactly":
    check compileFixture("f_seed").ok
    let env = {"PROPTEST_SEED": "12345", "PROPTEST_DB": "off"}
    let a = runFixture("f_seed", env)
    let b = runFixture("f_seed", env)
    check a.code == 0
    check a.output == b.output
    check "runSeed=12345" in a.output
    check "counterexample=@[0, 0, 0]" in a.output
    let other = runFixture("f_seed", {"PROPTEST_SEED": "999", "PROPTEST_DB": "off"})
    check "runSeed=999" in other.output
    # Shrinking is seed-independent in its result: the minimum is the same.
    check "counterexample=@[0, 0, 0]" in other.output

  test "K2: PROPTEST_CASES changes the default number of cases":
    check compileFixture("f_seed").ok
    let r = runFixture("f_seed", {"PROPTEST_CASES": "7", "PROPTEST_DB": "off"})
    check "cases=7" in r.output

  test "RL9: the run seed is saved before the first case":
    check compileFixture("f_seed").ok
    let dir = getTempDir() / "proptest_db_" & $getCurrentProcessId()
    removeDir(dir)
    discard runFixture("f_seed", {"PROPTEST_SEED": "777", "PROPTEST_DB": dir})
    check fileExists(dir / "last-run")
    check "PROPTEST_SEED=777" in readFile(dir / "last-run")
    removeDir(dir)

  test "RL9: PROPTEST_DB=off writes no file":
    check compileFixture("f_seed").ok
    let dir = fixturesDir / ".proptest"
    removeDir(dir)
    discard runFixture("f_seed", {"PROPTEST_DB": "off"})
    check not dirExists(dir)

  test "A1: `name = gen` is rejected at compile time with the right form":
    let (buildLog, ok) = compileFixture("f_badsyntax")
    check not ok
    check "declare variables as `name in Type` or `name in generator`" in buildLog

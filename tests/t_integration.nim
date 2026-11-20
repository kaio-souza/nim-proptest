## End-to-end behavior through separately compiled fixture programs:
## runner output, environment variables, files and compile-time messages.

import std/[unittest, os, strutils, json]
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

  test "A8: a build that cannot locate failures is reported at compile time":
    # tests/config.nims silences the warning for the suite; the command line
    # turns it back on here.
    proc warnings(flags: string): string =
      let (log, ok) = compileFixture("f_seed", "-d:proptestTraceWarning=true " & flags &
        " -o:" & quoteShell(fixturesDir / "f_seed_trace"))
      check ok
      log
    check "proptest: built" notin warnings("")
    let release = warnings("-d:release")
    check "proptest: built without stack traces" in release
    check "--stackTrace:on --lineTrace:on" in release
    check "proptest: built with --stackTrace:on but without --lineTrace:on" in
      warnings("-d:release --stackTrace:on")
    check "proptest: built" notin warnings("-d:release --stackTrace:on --lineTrace:on")
    check "proptest: built" notin warnings("-d:release -d:proptestTraceWarning=false")

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

  test "I2: inside unittest2 a failing property fails its test once, with no adapter module":
    # unittest2 is not a dependency (ADR-0002): skipped when it is not
    # installed, unless PROPTEST_REQUIRE_UNITTEST2 is set (CI installs it).
    let (buildLog, ok) = compileFixture("f_unittest2")
    if not ok and "cannot open file: unittest2" in buildLog and
       getEnv("PROPTEST_REQUIRE_UNITTEST2").len == 0:
      skip()
    else:
      check ok
      if not ok: echo buildLog
      let (output, code) = runFixture("f_unittest2", {"PROPTEST_DB": "off"})
      check code == 1
      check countOf(output, "[FAILED ]") == 2
      check countOf(output, "falsified") == 2
      check countOf(output, "check failed: x < 500") == 1
      check "x = 500" in output
      check "replayCommands BoundedQueue" in output
      check "2 FAILED" in output

  test "O3/K2: PROPTEST_REPORT appends one JSON line per property":
    check compileFixture("f_report").ok
    let path = getTempDir() / ("proptest_report_" & $getCurrentProcessId()) / "report.jsonl"
    removeDir(parentDir(path))
    let env = {"PROPTEST_REPORT": path, "PROPTEST_DB": "off"}
    let r = runFixture("f_report", env)
    check r.code == 0
    check fileExists(path)
    let lines = readFile(path).strip.splitLines
    check lines.len == 3
    let passing = parseJson(lines[0])
    check passing["format"].getInt == 1
    check passing["name"].getStr == "passing"
    check passing["status"].getStr == "passed"
    check passing["passed"].getBool
    check passing["seed"].getStr == "1"
    check passing["casesPassed"].getInt == 100
    check passing["durationMs"].getFloat >= 0.0
    check passing["labeledCases"].getInt == 100
    var kinds: seq[string]
    for l in passing["labels"]: kinds.add l["kind"].getStr
    check kinds == @["classify", "cover"]
    check passing["labels"][1]["required"].getFloat == 10.0
    let failing = parseJson(lines[1])
    check failing["status"].getStr == "failed"
    check not failing["passed"].getBool
    check failing["replay"].getStr.startsWith("PROPTEST_SEED=1 ")
    let f = failing["failures"][0]
    check f["kind"].getStr == "ValueError"
    check f["source"].getStr == "explored"
    check f["message"].getStr == "bad \"input\"\\\nbyte ÿ"
    check f["inputs"][0]["name"].getStr == "s"
    check f["inputs"][0]["value"].getStr == "\"a\""
    let machine = parseJson(lines[2])
    check machine["status"].getStr == "failed"
    check machine["failures"][0]["machine"].getStr == "BoundedQueue"
    check machine["failures"][0]["steps"].len == 4
    # A second run appends: CI can point every test program at one file.
    discard runFixture("f_report", env)
    check readFile(path).strip.splitLines.len == 6
    removeDir(parentDir(path))

  test "O3: without PROPTEST_REPORT no report is written":
    check compileFixture("f_report").ok
    let r = runFixture("f_report", {"PROPTEST_DB": "off"})
    check r.code == 0
    check "done" in r.output
    check not fileExists(fixturesDir / "report.jsonl")

  test "RL10: a case that never returns is reported, saved, and shown with its inputs next run":
    check compileFixture("f_hang").ok
    let dir = getTempDir() / ("proptest_hang_" & $getCurrentProcessId())
    removeDir(dir)
    let env = {"PROPTEST_HANG_TIMEOUT": "300", "PROPTEST_DB": dir / "db",
               "PROPTEST_REPORT": dir / "report.jsonl"}
    let first = runFixture("f_hang", env)
    check first.code == 1
    check "property 'hangs on 42' did not return" in first.output
    check "more than 300 ms (hangTimeout) while exploring" in first.output
    check "Choices (1): 42" in first.output
    check "Replay: PROPTEST_SEED=1 " in first.output
    check "saved in the failure database" in first.output
    check "not reached" notin first.output
    let second = runFixture("f_hang", env)
    check second.code == 1
    check "replaying a case that hung in an earlier run" in second.output
    check "    x = 42" in second.output
    let lines = readFile(dir / "report.jsonl").strip.splitLines
    check lines.len == 2
    check parseJson(lines[0])["status"].getStr == "hung"
    removeDir(dir)

  test "RL10: with verbose output the inputs are shown on the first run":
    check compileFixture("f_hang").ok
    let r = runFixture("f_hang", {"PROPTEST_HANG_TIMEOUT": "300", "PROPTEST_DB": "off",
                                  "PROPTEST_VERBOSITY": "verbose"})
    check r.code == 1
    check "    x = 42" in r.output

  test "A1: `name = gen` is rejected at compile time with the right form":
    let (buildLog, ok) = compileFixture("f_badsyntax")
    check not ok
    check "declare variables as `name in Type` or `name in generator`" in buildLog

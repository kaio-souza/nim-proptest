## The run loop: cases, discards, failures, signatures, reports, settings.

import std/[unittest, strutils, os, json]
import proptest

proc failsOutsideATest() =
  ## Module-level proc: here `forAll` is not inside a unittest `test`.
  forAll(initSettings(seed = 3), x in ints(0, 100)):
    check x < 50

suite "engine":
  test "A1/K1: forAll runs the configured number of cases":
    var n = 0
    let r = forAllResult(initSettings(seed = 1, cases = 37), x in int):
      inc n
    check r.status == psPassed
    check r.casesRun == 37
    check n == 37

  test "A2: assume discards cases; too many discards give up":
    let r = forAllResult(initSettings(seed = 2, cases = 10, maxDiscardRatio = 3), x in int):
      assume(false)
    check r.status == psGaveUp
    check r.discarded == 31
    check "discarded" in formatReport(r)

  test "A3/R1: the report shows inputs, error, location and the replay seed":
    let r = forAllResult(initSettings(seed = 4, name = "report"), x in ints(0, 100)):
      check x < 50
    check r.status == psFailed
    let text = formatReport(r)
    check "Property 'report' falsified" in text
    check "x = 50" in text
    check "check failed: x < 50" in text
    check "Location: t_engine.nim:" in text
    check "PROPTEST_SEED=4" in text

  test "A4: Defects count as failures":
    let r = forAllResult(initSettings(seed = 5), xs in seq[int]):
      discard xs[3]
    check r.status == psFailed
    check r.failures[0].signature.kind == "IndexDefect"
    check r.failures[0].inputs[0].value == "@[]"

  test "A5: values are shown readably":
    check show("a\"b") == "\"a\\\"b\""
    check show('c') == "'c'"
    check show(@[1, 2]) == "@[1, 2]"
    check show((1, "x")) == "(1, \"x\")"

  test "A6: check inside forAll reports the value of each side":
    let r = forAllResult(initSettings(seed = 6), x in ints(0, 100), y in ints(0, 100)):
      check x + y < 100
    check r.status == psFailed
    let msg = r.failures[0].message
    check "check failed: x + y < 100" in msg
    check "x + y was 100" in msg

  test "A6: check accepts a block of conditions":
    let r = forAllResult(initSettings(seed = 7), x in ints(0, 10)):
      check:
        x >= 0
        x < 5
    check r.status == psFailed
    check "x < 5" in r.failures[0].message

  test "RL4: the failure signature is the location of the failing check":
    let r = forAllResult(initSettings(seed = 8), x in ints(0, 100)):
      check x < 10
    check r.failures[0].signature.kind == "PropertyFailed"
    check r.failures[0].signature.location.startsWith("t_engine.nim:")

  test "RL6: exceptions in generators are generator errors, not failures":
    let broken = newGen(proc(src: ChoiceSource): int =
      raise newException(KeyError, "broken"))
    let r = forAllResult(initSettings(seed = 9), x in broken):
      discard
    check r.status == psGeneratorError
    check "KeyError" in r.message
    check r.failures.len == 0

  test "RL7: overruns are discarded, not failed":
    # Two integers need two choices; only one is allowed.
    let r = forAllResult(initSettings(seed = 10, maxChoices = 1, cases = 5), x in int, y in int):
      discard
    check r.status == psGaveUp
    check r.overruns > 0

  test "C1/RL11: a filter that rejects too much stops the run with a hint":
    # No literal here: constants of this file are mined as hints (ADR-0012),
    # so `x == 7` would be found.
    let impossible = ints(0, 1_000_000).filter(proc(x: int): bool = x * 2 == x + x + 1)
    let r = forAllResult(initSettings(seed = 11, cases = 10), x in impossible):
      discard
    check r.status == psGaveUp
    check r.filterDiscards == r.discarded
    check "filter" in r.message

  test "S3/R2: the same seed gives the same result":
    proc once(): PropertyResult =
      forAllResult(initSettings(seed = 12, name = "same"), xs in seq[int]):
        check xs.len < 4 or xs[1] < 50
    let a = once()
    let b = once()
    check a.status == psFailed
    check a.casesRun == b.casesRun
    check a.failures[0].choices == b.failures[0].choices
    check a.failures[0].shrinkExecutions == b.failures[0].shrinkExecutions
    check a.failures[0].inputs == b.failures[0].inputs

  test "R5: a property's cases depend on its name, not on other properties":
    proc firstInput(name: string): string =
      let r = forAllResult(initSettings(seed = 13, name = name), x in int):
        check false
      r.failures[0].inputs[0].value
    let before = firstInput("alpha")
    discard firstInput("beta")
    check firstInput("alpha") == before

  test "K3: invalid settings are rejected":
    for bad in [initSettings(cases = 0), initSettings(maxChoices = 0),
                initSettings(maxFailures = 0), initSettings(maxShrinks = -1)]:
      expect ValueError:
        discard runProperty(proc(src: ChoiceSource) = discard, bad)

  test "I3: forAllResult and runProperty never raise for failing properties":
    let r = forAllResult(initSettings(seed = 14), x in int):
      raise newException(IOError, "boom")
    check r.status == psFailed
    check not r.passed

  test "I3: outside a unittest test, forAll raises PropertyError with the result":
    try:
      failsOutsideATest()
      check false
    except PropertyError as e:
      check e.propertyResult.status == psFailed
      check "x = 50" in e.msg

  test "S4: the shrink budget bounds the executions":
    let r = forAllResult(initSettings(seed = 15, maxShrinks = 3), xs in seq[int]):
      check xs.len < 3
    check r.status == psFailed
    check r.failures[0].shrinkExecutions <= 3

  test "O3/K1: the report setting appends the result; an unwritable path is a clear error":
    let dir = getTempDir() / ("proptest_report_engine_" & $getCurrentProcessId())
    removeDir(dir)
    let path = dir / "out.jsonl"
    let r = forAllResult(initSettings(seed = 16, name = "to report", report = path), x in int):
      discard
    check r.passed
    let line = parseJson(readFile(path).strip)
    check line["name"].getStr == "to report"
    check line["status"].getStr == "passed"
    # A file where a directory should be: the run raises IOError naming the path.
    writeFile(dir / "file", "")
    expect IOError:
      discard forAllResult(initSettings(seed = 16, report = dir / "file" / "out.jsonl"), x in int):
        discard
    try:
      discard forAllResult(initSettings(seed = 16, report = dir / "file" / "out.jsonl"), x in int):
        discard
    except IOError as e:
      check "PROPTEST_REPORT" in e.msg
      check "out.jsonl" in e.msg
    removeDir(dir)

  test "O3: report strings are valid JSON, whatever the bytes":
    let r = forAllResult(initSettings(seed = 17, name = "esc\t\x01\xC3\xA9\xFF"), x in int):
      discard
    let line = toJsonLine(r)
    check line.count('\n') == 0
    let j = parseJson(line)
    check j["name"].getStr == "esc\t\x01éÿ"

  test "RL10/K3: fast cases never trigger the watchdog; hangTimeout is validated":
    # A watchdog that fired here would end this test program.
    var n = 0
    let r = forAllResult(initSettings(seed = 18, cases = 3000, hangTimeout = 25), xs in seq[int]):
      n += xs.len
    check r.passed
    expect ValueError:
      validate(initSettings(hangTimeout = -1))
    # Off by default; the environment turns it on (CI sets it).
    let env = getEnv("PROPTEST_HANG_TIMEOUT")
    delEnv("PROPTEST_HANG_TIMEOUT")
    check initSettings().hangTimeout == 0
    putEnv("PROPTEST_HANG_TIMEOUT", "1234")
    check initSettings().hangTimeout == 1234
    if env.len > 0: putEnv("PROPTEST_HANG_TIMEOUT", env) else: delEnv("PROPTEST_HANG_TIMEOUT")

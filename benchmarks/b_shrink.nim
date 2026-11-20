## PF6/PF7: shrinking cost on the reference bugs of SPEC Part IV.
##
## The number of property executions spent shrinking is deterministic for a
## fixed seed, so it can gate CI without noise (ADR-0008):
##
##   b_shrink --check    fail if any bug needs more executions than the baseline
##   b_shrink --update   rewrite benchmarks/baseline/shrink.json
##
## Wall-clock time per shrink is printed for information only.

import std/[os, json, monotimes, times, strformat, tables, algorithm]
import ../src/proptest

proc buggyReverse(xs: seq[int]): seq[int] =
  for i in countdown(xs.high, 0): result.add xs[i]
  if xs.len > 3: result.setLen(result.len - 1)

type Case = tuple[name: string; run: proc(): PropertyResult]

let evens = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 0)
let labels = ints(0, 1_000).map(proc(x: int): string = "#" & $x)

let cases: seq[Case] = @[
  ("reverse drops last element", proc(): PropertyResult =
    forAllResult(initSettings(seed = 1), xs in seq[int]):
      check buggyReverse(buggyReverse(xs)) == xs),
  ("filtered evens >= 100", proc(): PropertyResult =
    forAllResult(initSettings(seed = 2), n in evens):
      check n < 100),
  ("mapped labels of length 4", proc(): PropertyResult =
    forAllResult(initSettings(seed = 3), s in labels):
      check s.len < 4),
  ("int boundary 123456", proc(): PropertyResult =
    forAllResult(initSettings(seed = 6, name = "inner"), x in int):
      check x <= 123_456),
  ("string containing z", proc(): PropertyResult =
    forAllResult(initSettings(seed = 7), s in string):
      check 'z' notin s),
  ("list sum >= 1500", proc(): PropertyResult =
    forAllResult(initSettings(seed = 1), xs in seqs(ints(0, 1000))):
      var s = 0
      for x in xs: s += x
      check s < 1500),
  ("two independent bugs", proc(): PropertyResult =
    forAllResult(initSettings(seed = 11), a in ints(0, 1000), b in ints(0, 1000)):
      if a > 100: raise newException(ValueError, "bug A")
      if b > 100: raise newException(IOError, "bug B")),
]

const baselineFile = currentSourcePath().parentDir / "baseline" / "shrink.json"

proc main() =
  var current = initOrderedTable[string, int]()
  echo &"""{"reference bug":<30} {"executions":>10} {"time ms":>9}  counterexample"""
  for (name, run) in cases:
    let t0 = getMonoTime()
    let r = run()
    let ms = (getMonoTime() - t0).inMicroseconds.float / 1000.0
    var total = 0
    var shown: seq[string]
    for f in r.failures:
      total += f.shrinkExecutions
      for (_, v) in f.inputs: shown.add v
    current[name] = total
    echo &"{name:<30} {total:>10} {ms:>9.2f}  {shown}"

  let args = commandLineParams()
  if "--update" in args:
    var j = newJObject()
    for k, v in current: j[k] = %v
    createDir(baselineFile.parentDir)
    writeFile(baselineFile, j.pretty & "\n")
    echo "baseline updated: ", baselineFile
  elif "--check" in args:
    let base = parseFile(baselineFile)
    var failed = false
    for k, v in current:
      if not base.hasKey(k):
        echo "FAIL: no baseline for '", k, "' (run with --update)"
        failed = true
      elif v > base[k].getInt:
        echo &"FAIL: '{k}' needs {v} executions, baseline {base[k].getInt}"
        failed = true
    if failed: quit 1
    echo "OK: no shrinking regression against ", baselineFile.extractFilename

main()

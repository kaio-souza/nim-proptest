## Validates docs/TRACEABILITY.md against the test and benchmark sources
## (ADR-0004). Exit code 1 lists every problem found.
##
## - `done` and `partial` rows need a test whose name cites the ID
##   (`test "S1: ..."`, `test "V-S1/C1: ..."`), unless the Tests column says
##   `CI` (CI matrix), `bench` (a benchmark gate) or `doc` (documentation).
## - A Benchmark column naming `b_xxx` requires `benchmarks/b_xxx.nim`.
## - Every ID cited by a test must have a row.

import std/[os, strutils, sets, tables]

proc isId(s: string): bool =
  ## One to three capital letters followed by digits: S1, RL14, DOC7.
  var i = 0
  while i < s.len and s[i] in {'A'..'Z'}: inc i
  i in 1..3 and i < s.len and s[i ..< s.len].allCharsInSet({'0'..'9'})

let root = currentSourcePath().parentDir.parentDir

var testSrc = ""
for f in walkFiles(root / "tests" / "t_*.nim"): testSrc.add readFile(f) & "\n"

var testedIds = initHashSet[string]()
for line in testSrc.splitLines:
  let t = line.strip
  if not t.startsWith("test \""): continue
  let head = t[6 .. ^1].split(':')[0]
  for part in head.split('/'):
    let id = part.strip.replace("V-", "")
    if id.isId: testedIds.incl id

const exempt = ["CI", "bench", "doc"]
var problems: seq[string]
var rows = initTable[string, string]()
var done = 0

for line in readFile(root / "docs" / "TRACEABILITY.md").splitLines:
  let cols = line.split('|')
  if cols.len < 7: continue
  let id = cols[1].strip
  if not id.isId: continue
  let status = cols[3].strip
  let tests = cols[4].strip
  let bench = cols[5].strip
  if id in rows: problems.add id & ": duplicated row"
  rows[id] = status
  if status notin ["done", "partial", "pending", "deferred"]:
    problems.add id & ": unknown status '" & status & "'"
  if status in ["done", "partial"]:
    inc done
    if tests notin exempt and id notin testedIds:
      problems.add id & ": marked '" & status & "' but no test name cites it"
    for b in bench.split(','):
      let name = b.strip
      if name.startsWith("b_") and not fileExists(root / "benchmarks" / (name & ".nim")):
        problems.add id & ": benchmark " & name & " not found"

for id in testedIds:
  if id notin rows:
    problems.add id & ": cited by a test but missing from TRACEABILITY.md"

if problems.len > 0:
  echo "Traceability check FAILED:"
  for p in problems: echo "  - ", p
  quit 1
echo "Traceability OK: ", rows.len, " requirements, ", done,
  " done or partial, ", testedIds.len, " IDs cited by tests."

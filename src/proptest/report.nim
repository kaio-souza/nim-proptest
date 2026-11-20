## Text report of a property result (A3, O1).

import std/[os, strutils, strformat]
import engine, choices

proc indent(text: string; spaces: int): string =
  let pad = repeat(' ', spaces)
  var first = true
  for line in text.strip(leading = false).splitLines:
    if not first: result.add '\n'
    result.add pad & line
    first = false

proc replayLine(r: PropertyResult): string =
  "Replay: PROPTEST_SEED=" & $r.runSeed & " " & getAppFilename()

proc formatFailure(f: Failure; n, total: int): string =
  if total > 1:
    result.add "Failure " & $n & " of " & $total & " (" & $f.signature & ")\n"
  case f.source
  of fsDatabase: result.add "  Replayed from the failure database: it failed in an earlier run.\n"
  of fsExample: result.add "  An explicit example (not shrunk).\n"
  of fsExplored: discard
  if f.flaky:
    result.add "  FLAKY: the minimal case did not fail again when re-run.\n" &
      "  Common causes: time, randomness, global state, threads or I/O in the property.\n"
  if f.machine.len > 0:
    # Stateful (M4): the sequence as code that can be pasted into a test.
    result.add "  Shortest failing sequence (" & $f.steps.len & " steps, " &
      $f.choices.len & " choices, " & $f.shrinkExecutions & " shrink executions):\n"
    result.add "    replayCommands " & f.machine & ":\n"
    if f.steps.len == 0:
      result.add "      discard  # fails in setup or teardown, before any step\n"
    for step in f.steps:
      result.add "      " & step & "\n"
  else:
    result.add "  Counterexample (" & $f.choices.len & " choices, " &
      $f.shrinkExecutions & " shrink executions):\n"
    if f.inputs.len == 0:
      result.add "    (no inputs)\n"
    for (name, value) in f.inputs:
      result.add "    " & name & " = " & value & "\n"
  if f.shrinkStopped:
    result.add "  Shrinking stopped at its time budget: the smallest counterexample found so far.\n"
  result.add "  Error: [" & f.signature.kind & "] " & indent(f.message, 4).strip & "\n"
  if f.signature.location.len > 0:
    result.add "  Location: " & f.signature.location & "\n"
  else:
    result.add "  Location unknown (no stack trace): failures are told apart by type only.\n"
  if f.steps.len > 0:
    result.add "  Failed at step " & $f.steps.len & ": " & f.steps[^1] & "\n"

proc pct(hits, n: int): string =
  if n == 0: "  n/a" else: formatFloat(100.0 * hits.float / n.float, ffDecimal, 1).align(5) & "%"

const lengthBuckets = ["0", "1", "2-3", "4-7", "8-15", "16-31", "32-63", "64+"]

proc formatStats*(r: PropertyResult; withStateful: bool): string =
  ## Label percentages (D1, D2) and, if asked, the stateful statistics.
  let n = r.labeledCases
  var width = 0
  for st in r.labels: width = max(width, st.name.len)
  var user, commands: string
  for st in r.labels:
    case st.kind
    of lkClassify, lkLabel:
      user.add &"    {pct(st.cases, n)}  {st.name}\n"
    of lkCover:
      user.add &"    {pct(st.cases, n)}  {st.name}  (cover: {st.required:.1f}% required)\n"
    of lkCommand:
      var disabled = 0
      for d in r.labels:
        if d.kind == lkDisabled and d.name == st.name: disabled = d.events
      commands.add &"    {st.name.alignLeft(width)}  in {pct(st.cases, n)} of sequences, " &
        &"{st.events} steps; precondition false {disabled} times\n"
    of lkDisabled: discard
  if user.len > 0:
    result.add "  Statistics (" & $n & " cases):\n" & user
  if withStateful and commands.len > 0:
    result.add "  Commands (" & $n & " sequences):\n" & commands
    var lengths: seq[string]
    for i, c in r.lengthHist:
      if c > 0: lengths.add lengthBuckets[i] & ": " & $c
    if lengths.len > 0:
      result.add "  Sequence lengths: " & lengths.join(", ") & "\n"

proc formatWarnings(r: PropertyResult): string =
  if r.warnings.len > 0:
    result.add "  Warnings:\n"
    for w in r.warnings: result.add "    " & w & "\n"

proc formatNotes*(r: PropertyResult): string =
  ## What a passing property prints, by verbosity (O2): warnings at
  ## `normal`, plus the statistics of explicit labels; everything at `verbose`.
  if r.verbosity == vQuiet: return ""
  let verbose = r.verbosity >= vVerbose
  var hasUser = false
  for st in r.labels:
    if st.kind in {lkClassify, lkCover, lkLabel}: hasUser = true
  var body = ""
  if hasUser or verbose: body.add formatStats(r, withStateful = verbose)
  body.add formatWarnings(r)
  if body.len > 0:
    result = "Property '" & r.name & "' passed " & $r.casesRun & " cases.\n" & body
    result.stripLineEnd

proc formatReport*(r: PropertyResult): string =
  ## Multi-line report; empty for passing properties.
  case r.status
  of psPassed:
    return ""
  of psGaveUp:
    result = "Property '" & r.name & "' " & r.message & ".\n"
  of psGeneratorError:
    result = "Property '" & r.name & "': " & r.message & "\n" &
      "  This is a problem in a generator, not in the code under test.\n"
  of psInsufficientCoverage:
    result = "Property '" & r.name & "' passed " & $r.casesRun &
      " cases but missed its coverage requirements:\n" & indent(r.message, 4) & "\n" &
      formatStats(r, withStateful = true)
  of psFailed, psFlaky:
    let verb = if r.status == psFailed: "falsified" else: "is flaky"
    # The first failure's case number; exploration then went on looking for
    # other bugs, so the passing count includes later cases.
    result = "Property '" & r.name & "' " & verb & " at case " & $r.firstFailureAt &
      " (" & $r.casesRun & " cases passed, " & $r.discarded & " discarded).\n"
    for i, f in r.failures:
      result.add formatFailure(f, i + 1, r.failures.len)
    if r.verbosity >= vNormal:
      result.add formatStats(r, withStateful = r.verbosity >= vVerbose)
  if r.status != psPassed: result.add formatWarnings(r)
  result.add "  " & replayLine(r)

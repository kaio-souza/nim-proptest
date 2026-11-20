## Text report of a property result (A3, O1).

import std/[os, strutils]
import engine

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
  result.add "  Error: [" & f.signature.kind & "] " & indent(f.message, 4).strip & "\n"
  if f.signature.location.len > 0:
    result.add "  Location: " & f.signature.location & "\n"
  else:
    result.add "  Location unknown (no stack trace): failures are told apart by type only.\n"
  if f.steps.len > 0:
    result.add "  Failed at step " & $f.steps.len & ": " & f.steps[^1] & "\n"

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
  of psFailed, psFlaky:
    let verb = if r.status == psFailed: "falsified" else: "is flaky"
    result = "Property '" & r.name & "' " & verb & " after " & $r.casesRun &
      " passing cases (" & $r.discarded & " discarded).\n"
    for i, f in r.failures:
      result.add formatFailure(f, i + 1, r.failures.len)
  result.add "  " & replayLine(r)

## Assertions inside `forAll` (ADR-0009).
##
## `check` and `require` from `std/unittest` do not raise on failure. Inside a
## `forAll` body they are rewritten into `propCheck`, which raises
## `PropertyFailed`, so the engine sees each failing case without printing
## anything. The runner is told once, with the final report.

import std/[macros, os]

type
  PropertyFailed* = object of CatchableError
    ## A failed assertion inside a property body.
    location*: string  ## `file:line` of the assertion: its failure signature.

proc show*[T](x: T): string =
  ## Representation used in reports: quoted strings and chars, `$` when it
  ## exists, `repr` otherwise.
  when T is string or T is char:
    result.addQuoted(x)
  elif compiles($x):
    $x
  else:
    repr(x)

proc raiseFailed*(msg, location: string) {.noinline, noreturn.} =
  var e = newException(PropertyFailed, msg)
  e.location = location
  raise e

const comparisons = ["==", "!=", "<", "<=", ">", ">=", "in", "notin"]

macro propCheck*(cond: untyped): untyped =
  ## Like `check`, but raises `PropertyFailed`. For comparisons, the report
  ## shows the value of each side.
  let info = cond.lineInfoObj
  let loc = newLit(extractFilename(info.filename) & ":" & $info.line)
  let text = newLit(cond.repr)
  if cond.kind == nnkInfix and cond[0].kind == nnkIdent and $cond[0] in comparisons:
    let a = genSym(nskLet, "lhs")
    let b = genSym(nskLet, "rhs")
    let lhs = cond[1]
    let rhs = cond[2]
    let test = infix(a, $cond[0], b)
    # Literal sides add nothing to the report ("100 was 100").
    var details = newLit("")
    for (side, value) in [(lhs, a), (rhs, b)]:
      if side.kind notin nnkLiterals:
        let sideText = newLit("\n    " & side.repr & " was ")
        details = quote do: `details` & `sideText` & show(`value`)
    result = quote do:
      block:
        let `a` = `lhs`
        let `b` = `rhs`
        if not `test`:
          raiseFailed("check failed: " & `text` & `details`, `loc`)
  else:
    result = quote do:
      if not (`cond`):
        raiseFailed("check failed: " & `text`, `loc`)

proc rewriteChecks*(n: NimNode; propCheckSym: NimNode): NimNode =
  ## Replaces every `check`/`require` call in `n` with `propCheck`.
  if n.kind in {nnkCall, nnkCommand} and n.len >= 2 and n[0].kind == nnkIdent and
     (n[0].eqIdent("check") or n[0].eqIdent("require")):
    result = newStmtList()
    for i in 1 ..< n.len:
      let arg = n[i]
      if arg.kind == nnkStmtList:
        for s in arg:
          result.add newCall(propCheckSym, rewriteChecks(s, propCheckSym))
      else:
        result.add newCall(propCheckSym, rewriteChecks(arg, propCheckSym))
    return
  result = n
  for i in 0 ..< n.len:
    result[i] = rewriteChecks(n[i], propCheckSym)

## Assertions inside `forAll` (ADR-0009).
##
## `check` and `require` from `std/unittest` do not raise on failure. Inside a
## `forAll` body they are rewritten into `propCheck`, which raises
## `PropertyFailed`, so the engine sees each failing case without printing
## anything. The runner is told once, with the final report.

import std/[macros, os, options, typetraits]

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

proc showCode*[T](x: T): string =
  ## `x` as a Nim expression, used to print stateful failures as runnable
  ## code (M4). Overload it for custom types whose `$` is not valid Nim.
  mixin showCode
  when T is SomeFloat:
    let suffix = when T is float32: "'f32" else: ""
    if x != x: result = (when T is float32: "NaN.float32" else: "NaN")
    elif x == Inf: result = (when T is float32: "Inf.float32" else: "Inf")
    elif x == -Inf: result = (when T is float32: "-Inf.float32" else: "-Inf")
    else: result = $x & suffix
  elif T is uint64 or T is uint:
    result = $x
    if uint64(x) > uint64(high(int)): result.add "'u64"
  elif T is string or T is char or T is enum or T is SomeInteger or T is bool:
    result = show(x)
  elif T is seq or T is array:
    result = (when T is seq: "@[" else: "[")
    var first = true
    for v in x:
      if not first: result.add ", "
      result.add showCode(v)
      first = false
    result.add "]"
  elif T is set:
    result = "{"
    var first = true
    for v in x:
      if not first: result.add ", "
      result.add showCode(v)
      first = false
    result.add "}"
  elif T is Option:
    result = if x.isSome: "some(" & showCode(x.get) & ")" else: "none(" & $typeof(x.get) & ")"
  elif T is tuple:
    result = "("
    var n = 0
    for name, v in x.fieldPairs:
      if n > 0: result.add ", "
      when isNamedTuple(T): result.add name & ": "
      result.add showCode(v)
      inc n
    if n == 1 and not isNamedTuple(T): result.add ","
    result.add ")"
  else:
    result = show(x)

proc raiseFailed*(msg, location: string) {.noinline, noreturn.} =
  var e = newException(PropertyFailed, msg)
  e.location = location
  raise e

const comparisons = ["==", "!=", "<", "<=", ">", ">=", "in", "notin"]

proc oneLine(n: NimNode): string =
  ## `repr` on a single line, so multi-line expressions (an `if`
  ## expression, say) do not break the report layout.
  var space = false
  for c in n.repr:
    if c in {'\n', '\r', ' ', '\t'}:
      space = result.len > 0
    else:
      if space: result.add ' '
      space = false
      result.add c

macro propCheck*(cond: untyped): untyped =
  ## Like `check`, but raises `PropertyFailed`. For comparisons, the report
  ## shows the value of each side.
  let info = cond.lineInfoObj
  let loc = newLit(extractFilename(info.filename) & ":" & $info.line)
  let text = newLit(oneLine(cond))
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
        let sideText = newLit("\n    " & oneLine(side) & " was ")
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

## Assertions inside `forAll` (ADR-0009).
##
## `check` and `require` from `std/unittest` do not raise on failure. Inside a
## `forAll` body they are rewritten into `propCheck`, which raises
## `PropertyFailed`, so the engine sees each failing case without printing
## anything. The runner is told once, with the final report.

import std/[macros, os, options, typetraits, tables, sets, unicode, strutils]

type
  PropertyFailed* = object of CatchableError
    ## A failed assertion inside a property body.
    location*: string  ## `file:line` of the assertion: its failure signature.

proc showCode*[T](x: T): string

proc typeName[T](t: typedesc[T]): string =
  ## Canonical name of a type for printed code: `Hash` is an alias of
  ## `int`, and Nim may print a generic instance with the alias it saw first.
  when T is int: "int"
  elif T is int64: "int64"
  elif T is int32: "int32"
  elif T is uint: "uint"
  elif T is uint64: "uint64"
  elif T is float: "float"
  else: $T

proc quoteString(s: string): string =
  ## A Nim string literal that shows every character: printable text as is
  ## (including non-ASCII letters), invisible ones (controls, DEL, C1
  ## controls U+0080..U+009F, invalid UTF-8) as `\xNN` escapes.
  result = "\""
  var i = 0
  while i < s.len:
    let c = s[i]
    if ord(c) < 0x80:
      case c
      of '"': result.add "\\\""
      of '\\': result.add "\\\\"
      of '\n': result.add "\\n"
      of '\t': result.add "\\t"
      of '\r': result.add "\\r"
      elif ord(c) < 0x20 or ord(c) == 0x7F: result.add "\\x" & toHex(ord(c), 2)
      else: result.add c
      inc i
    else:
      let size = runeLenAt(s, i)
      let chunk = s[i ..< min(s.len, i + size)]
      let valid = chunk.len == size and validateUtf8(chunk) == -1
      if valid and int(runeAt(s, i)) notin 0x80 .. 0x9F:
        result.add chunk                 # a visible character, as is
        i += size
      elif valid:                        # a C1 control: invisible
        for b in chunk: result.add "\\x" & toHex(ord(b), 2)
        i += size
      else:                              # invalid UTF-8: byte by byte
        result.add "\\x" & toHex(ord(c), 2)
        inc i
  result.add "\""

proc show*[T](x: T): string =
  ## Representation used in reports: quoted strings and chars, `$` when it
  ## exists, Nim code for `ref` and `distinct` values, `repr` otherwise.
  when T is string:
    quoteString(x)
  elif T is char:
    result.addQuoted(x)
  elif compiles($x):
    $x
  elif T is ref object or T is distinct:
    showCode(x)
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
  elif T is Table or T is OrderedTable:
    if x.len == 0:
      result = "init" & (when T is Table: "Table" else: "OrderedTable") & "[" & typeName(typeof(keys(x))) & ", " & typeName(typeof(values(x))) & "]()"
    else:
      result = "{"
      var first = true
      for k, v in x.pairs:
        if not first: result.add ", "
        result.add showCode(k) & ": " & showCode(v)
        first = false
      result.add (when T is Table: "}.toTable" else: "}.toOrderedTable")
  elif T is HashSet:
    if x.len == 0:
      result = "initHashSet[" & typeName(typeof(items(x))) & "]()"
    else:
      result = "["
      var first = true
      for v in x:
        if not first: result.add ", "
        result.add showCode(v)
        first = false
      result.add "].toHashSet"
  elif T is distinct:
    result = $T & "(" & showCode(distinctBase(T)(x)) & ")"
  elif T is ref object:
    if x.isNil: result = "nil"
    else:
      result = $T & "("
      var n = 0
      for name, v in x[].fieldPairs:
        if n > 0: result.add ", "
        result.add name & ": " & showCode(v)
        inc n
      result.add ")"
  elif T is object and not (T is Option):
    result = $T & "("
    var n = 0
    for name, v in x.fieldPairs:
      if n > 0: result.add ", "
      result.add name & ": " & showCode(v)
      inc n
    result.add ")"
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
  # A new tree, never `n` itself (see `rewriteLabels`).
  result = copyNimNode(n)
  for c in n:
    result.add rewriteChecks(c, propCheckSym)

## Property-based testing for Nim.
##
## .. code-block:: nim
##   import proptest, std/[unittest, algorithm]
##
##   test "sort is idempotent":
##     forAll(xs in seq[int]):
##       check xs.sorted.sorted == xs.sorted
##
## Each variable is declared as `name in source`, where the source is a type
## (`xs in seq[int]`, generator inferred from the type, no closure) or a
## generator value (`n in ints(0, 10)`). Sources are evaluated once per
## property. An optional `Settings` value may be passed among the arguments:
## `forAll(initSettings(cases = 500), x in int): ...`.
##
## (`forAll(x: int)` cannot be used: when every argument has that shape, Nim
## parses the call as an object constructor before any macro sees it.)
##
## Inside `test` (std/unittest) a failing property marks the test as failed
## and prints one report. Outside a test, `forAll` raises `PropertyError`.
## `runProperty` gives the result object without raising (I3).

import std/[macros, os, strutils]
import proptest/[choices, gen, assertions, engine, report, stateful, labels, mining, prng]

export choices, gen, assertions, engine, report, stateful, labels

when compileOption("panics"):
  {.warning: "proptest: compiled with --panics:on. Defects end the process at the " &
    "first failing case, so it cannot be shrunk. Replay it with the seed saved in " &
    ".proptest/last-run, or build the tests with --panics:off.".}

type
  PropertyError* = object of CatchableError
    ## Raised by `forAll` outside a unittest `test` when the property fails.
    propertyResult*: PropertyResult

proc printNotes*(r: PropertyResult) =
  ## Prints what a passing property has to say (statistics, warnings), by
  ## verbosity (O2, O4).
  let notes = formatNotes(r)
  if notes.len > 0: echo notes

proc raisePropertyError*(r: PropertyResult) {.noinline, noreturn.} =
  var e = newException(PropertyError, formatReport(r))
  e.propertyResult = r
  raise e

proc buildProperty(args: NimNode; resVar: NimNode): NimNode =
  ## Statements that build the settings and the property proc, run it and
  ## store the `PropertyResult` in `resVar`. Shared by `forAll` and
  ## `forAllResult`.
  if args.len == 0 or args[^1].kind != nnkStmtList:
    error("forAll needs a body: forAll(x in int): ...", args)
  let body = args[^1]
  let src = genSym(nskParam, "src")
  let info = (if args.len > 1: args[0] else: body).lineInfoObj
  let defaultName = newLit(extractFilename(info.filename) & ":" & $info.line)
  var genLets = newStmtList()
  var draws = newStmtList()
  var records = newStmtList()
  var settingsExpr: NimNode = nil
  var vars: seq[(NimNode, NimNode)]        # (name, hoisted source)
  var examples: seq[NimNode]

  proc declare(name, value: NimNode): NimNode =
    nnkLetSection.newTree(newIdentDefs(
      nnkPragmaExpr.newTree(name, nnkPragma.newTree(ident"used")), newEmptyNode(), value))

  for i in 0 ..< args.len - 1:
    let a = args[i]
    if a.kind == nnkInfix and a[0].eqIdent("in") and a[1].kind == nnkIdent:
      let g = genSym(nskLet, "source")
      vars.add (a[1], g)
      genLets.add newLetStmt(g, newCall(ident"hoist", a[2]))
      draws.add declare(a[1], newCall(ident"drawFrom", src, g))
      records.add newCall(newDotExpr(newDotExpr(src, ident"inputs"), ident"add"),
        nnkTupleConstr.newTree(newLit($a[1]), newCall(bindSym"show", a[1])))
    elif a.kind in {nnkExprColonExpr, nnkExprEqExpr}:
      error("declare variables as `name in Type` or `name in generator`", a)
    elif a.kind in {nnkCall, nnkCommand} and a.len >= 1 and a[0].eqIdent("example"):
      examples.add a
    else:
      if settingsExpr != nil:
        error("forAll accepts a single Settings expression", a)
      settingsExpr = a
  if settingsExpr == nil:
    settingsExpr = newCall(bindSym"initSettings")

  var slot = 0
  let checked = rewriteChecks(rewriteLabels(body, src, slot), bindSym"propCheck")
  # Boundary hints (ADR-0012): the body's literals and constants first, then
  # the literals of the whole file. Computed once per property.
  let bodyAcc = genSym(nskVar, "bodyHints")
  let mined = genSym(nskLet, "hints")
  genLets.add bodyHints(body, bodyAcc)
  let fileHints = genSym(nskLet, "fileHints")
  genLets.add newLetStmt(mined, bodyAcc)
  genLets.add newLetStmt(fileHints, prefix(minedHints(if args.len > 1: args[0] else: body), "@"))
  let settingsVar = genSym(nskVar, "settings")
  let prop = genSym(nskLet, "prop")
  # Failure database key (ADR-0014): the file and a hash of the code, so
  # moving lines keeps the entries and changing the property drops them.
  # Only the variables and the body: settings (a seed, a case count) and
  # examples do not change what the property is.
  var code = body.repr
  for (name, g) in vars: code.add $name
  for i in 0 ..< args.len - 1:
    if args[i].kind == nnkInfix and args[i][0].eqIdent("in"): code.add args[i].repr
  let codeKey = newLit(extractFilename(info.filename) & "#" & toHex(fnv1a64(code)))
  let dbKey = genSym(nskLet, "dbKey")
  # Explicit examples (R4): one value per variable, run before random cases.
  let exampleList = genSym(nskVar, "examples")
  var exampleProcs = newStmtList()
  for ex in examples:
    if ex.len - 1 != vars.len:
      error("example(...) needs one value per variable (" & $vars.len & ")", ex)
    # A fresh parameter symbol per generated proc: reusing one gensym'd
    # parameter in several procs crashes the compiler.
    let exSrc = genSym(nskParam, "src")
    var binds = newStmtList()
    var recs = newStmtList()
    for i, (name, g) in vars:
      binds.add nnkLetSection.newTree(newIdentDefs(
        nnkPragmaExpr.newTree(name, nnkPragma.newTree(ident"used")),
        newCall(ident"typeof", newCall(ident"drawFrom", exSrc, g)), ex[i + 1]))
      recs.add newCall(newDotExpr(newDotExpr(exSrc, ident"inputs"), ident"add"),
        nnkTupleConstr.newTree(newLit($name), newCall(bindSym"show", name)))
    var exSlot = 0
    let exBody = rewriteChecks(rewriteLabels(body.copyNimTree, exSrc, exSlot), bindSym"propCheck")
    exampleProcs.add quote do:
      `exampleList`.add proc(`exSrc`: ChoiceSource) =
        beginBody(`exSrc`)
        `binds`
        if `exSrc`.recordInputs:
          `recs`
        `exBody`
  result = quote do:
    `genLets`
    var `settingsVar` = `settingsExpr`
    let `dbKey` = if `settingsVar`.name.len > 0: `settingsVar`.name else: `codeKey`
    if `settingsVar`.name.len == 0:
      `settingsVar`.name = `defaultName`
    var `exampleList`: seq[PropertyProc]
    `exampleProcs`
    let `prop`: PropertyProc = proc(`src`: ChoiceSource) =
      useHints(`src`, `mined`, `fileHints`)
      beginGenerate(`src`)
      `draws`
      if `src`.recordInputs:
        `records`
      beginBody(`src`)
      `checked`
    let `resVar` = runProperty(`prop`, `settingsVar`, `dbKey`, `exampleList`)

macro forAll*(args: varargs[untyped]): untyped =
  ## Runs the body for many generated cases; see the module documentation.
  ## Inside a unittest `test`, a failure marks the test as failed with one
  ## report; elsewhere it raises `PropertyError`.
  let res = genSym(nskLet, "res")
  let run = buildProperty(args, res)
  result = quote do:
    block:
      `run`
      if `res`.passed:
        printNotes(`res`)
      else:
        when declared(testStatusIMPL):
          checkpoint(formatReport(`res`))
          fail()
        else:
          raisePropertyError(`res`)

macro forAllResult*(args: varargs[untyped]): PropertyResult =
  ## Same arguments as `forAll`, but returns the `PropertyResult` instead of
  ## failing or raising (I3).
  let res = genSym(nskLet, "res")
  let run = buildProperty(args, res)
  result = quote do:
    (block:
      `run`
      `res`)

macro checkStateMachine*(machine: typed; settings: untyped = nil): untyped =
  ## Runs random command sequences of a machine defined with `stateMachine`
  ## (ADR-0011). Inside a unittest `test`, a failure marks the test as failed
  ## with one report, which prints the shortest failing sequence as a
  ## `replayCommands` block; elsewhere it raises `PropertyError`.
  let res = genSym(nskLet, "res")
  let s = if settings.kind == nnkNilLit: newCall(bindSym"initSettings") else: settings
  result = quote do:
    block:
      let `res` = stateMachineResult(`machine`, `s`)
      if `res`.passed:
        printNotes(`res`)
      else:
        when declared(testStatusIMPL):
          checkpoint(formatReport(`res`))
          fail()
        else:
          raisePropertyError(`res`)

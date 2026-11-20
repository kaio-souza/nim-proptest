## Run loop of a property: generate, execute, shrink, re-run, report.

import std/[os, strutils]
import prng, choices, signature, shrink, database

export signature

type
  Settings* = object
    ## Per-property settings (K1). Build with `initSettings`.
    name*: string          ## Property name; derives its seed. Empty: `file:line`.
    cases*: int            ## Passing cases required.
    maxSize*: int          ## Size reached by the last case.
    maxDiscardRatio*: int  ## Give up after `cases * maxDiscardRatio` discards.
    maxShrinks*: int       ## Execution budget for shrinking each failure.
    maxChoices*: int       ## Maximum choices per case (RL7).
    maxFailures*: int      ## Distinct failures kept and shrunk (RL5).
    seed*: uint64          ## Run seed; 0 uses `PROPTEST_SEED` or a random one.

  PropertyStatus* = enum
    psPassed          ## Every case passed.
    psFailed          ## At least one reproducible counterexample.
    psFlaky           ## Failures did not reproduce when re-run (RL3).
    psGaveUp          ## Too many discarded cases.
    psGeneratorError  ## A generator raised (RL6).

  Failure* = object
    signature*: Signature
    choices*: seq[uint64]      ## Minimal choice sequence.
    message*: string
    stackTrace*: string
    inputs*: seq[tuple[name, value: string]]
    shrinkExecutions*: int
    flaky*: bool

  PropertyResult* = object
    name*: string
    status*: PropertyStatus
    runSeed*: uint64
    casesRun*: int
    discarded*: int
    filterDiscards*: int
    overruns*: int
    failures*: seq[Failure]
    message*: string           ## Details for `psGaveUp` and `psGeneratorError`.

  PropertyProc* = proc(src: ChoiceSource) {.closure.}
    ## Generates the inputs and runs the body once.

  Outcome = enum
    ocPass, ocDiscard, ocOverrun, ocFail, ocGenError

  CaseResult = object
    outcome: Outcome
    filter: bool
    signature: Signature
    message: string
    stackTrace: string

proc envInt(name: string; default: int): int =
  let v = getEnv(name).strip
  if v.len == 0: return default
  try: parseInt(v)
  except ValueError: raise newException(ValueError, name & " is not an integer: " & v)

proc initSettings*(name = "";
                   cases = envInt("PROPTEST_CASES", 100);
                   maxSize = 100;
                   maxDiscardRatio = 10;
                   maxShrinks = envInt("PROPTEST_MAX_SHRINKS", 2000);
                   maxChoices = defaultMaxChoices;
                   maxFailures = 3;
                   seed = 0'u64): Settings =
  ## Defaults can be changed globally with environment variables (K2):
  ## `PROPTEST_CASES`, `PROPTEST_MAX_SHRINKS`, `PROPTEST_SEED`.
  Settings(name: name, cases: cases, maxSize: maxSize, maxDiscardRatio: maxDiscardRatio,
           maxShrinks: maxShrinks, maxChoices: maxChoices, maxFailures: maxFailures,
           seed: seed)

proc validate*(s: Settings) =
  ## Raises `ValueError` describing the first invalid setting (K3).
  template req(cond: bool; msg: string) =
    if not cond: raise newException(ValueError, "invalid proptest settings: " & msg)
  req s.cases >= 1, "cases must be >= 1"
  req s.maxSize >= 0, "maxSize must be >= 0"
  req s.maxDiscardRatio >= 0, "maxDiscardRatio must be >= 0"
  req s.maxShrinks >= 0, "maxShrinks must be >= 0"
  req s.maxChoices >= 1, "maxChoices must be >= 1"
  req s.maxFailures >= 1, "maxFailures must be >= 1"

proc passed*(r: PropertyResult): bool {.inline.} = r.status == psPassed

# ----------------------------------------------------------------- execution

proc classify(src: ChoiceSource; e: ref Exception; r: var CaseResult) =
  if src.phase == cpGenerate:
    r.outcome = ocGenError
    r.message = "[" & $e.name & "] " & e.msg
  else:
    r.outcome = ocFail
    r.signature = signatureOf(e)
    r.message = e.msg
    if src.recordInputs:
      r.stackTrace = e.getStackTrace()

proc execute(prop: PropertyProc; src: ChoiceSource): CaseResult =
  try:
    prop(src)
    result.outcome = ocPass
  except FilterExhausted:
    result.outcome = ocDiscard
    result.filter = true
  except DiscardCase:
    result.outcome = ocDiscard
  except Overrun:
    result.outcome = ocOverrun
  except CatchableError as e:
    classify(src, e, result)
  except Defect as e:
    # Not reachable with --panics:on (A7): the process ends instead.
    classify(src, e, result)

proc sizeFor(s: Settings; caseIndex: int): int {.inline.} =
  ## Sizes grow from 0 to `maxSize` over the run: simple cases first.
  if s.cases <= 1: s.maxSize else: (s.maxSize * caseIndex) div (s.cases - 1)

# -------------------------------------------------------------------- engine

proc runProperty*(prop: PropertyProc; settings: Settings): PropertyResult =
  ## Runs a property and returns its result. Never raises for failures of the
  ## property itself; raises `ValueError` for invalid settings.
  validate(settings)
  let rs = if settings.seed != 0: settings.seed else: runSeed()
  writeBreadcrumb(rs)
  result = PropertyResult(name: settings.name, runSeed: rs)
  let src = newChoiceSource(deriveSeed(rs, settings.name), settings.maxChoices)
  let maxDiscards = settings.cases * settings.maxDiscardRatio

  # 1. Explore `cases` cases (passing or failing), unless too many are
  #    discarded. After a failure, exploration goes on to look for other
  #    distinct bugs (RL5) and stops once `maxFailures` are known.
  var failingCases = 0
  while result.casesRun + failingCases < settings.cases and
        result.failures.len < settings.maxFailures:
    src.startRandom(sizeFor(settings, result.casesRun + failingCases))
    let r = execute(prop, src)
    case r.outcome
    of ocPass:
      inc result.casesRun
    of ocDiscard, ocOverrun:
      inc result.discarded
      if r.filter: inc result.filterDiscards
      if r.outcome == ocOverrun: inc result.overruns
      if result.discarded > maxDiscards:
        result.status = psGaveUp
        result.message = "gave up after " & $result.casesRun & " passing cases: " &
          $result.discarded & " cases discarded (" & $result.filterDiscards &
          " by filters, " & $result.overruns & " too large)"
        if result.filterDiscards * 2 > result.discarded:
          result.message.add ". Most discards come from `filter`: generate valid values directly instead."
        return
    of ocGenError:
      result.status = psGeneratorError
      result.message = "a generator raised: " & r.message
      return
    of ocFail:
      inc failingCases
      var known = false
      for f in result.failures:
        if f.signature == r.signature: known = true
      if not known:
        result.failures.add Failure(signature: r.signature, choices: src.choices,
                                    message: r.message)
  if result.failures.len == 0:
    result.status = psPassed
    return

  # 2. Shrink every distinct failure (RL4, RL5). Failures found while
  #    shrinking another one are queued and shrunk in turn.
  var failures = move result.failures
  let maxShrinks = settings.maxShrinks
  let maxFailures = settings.maxFailures
  let maxSize = settings.maxSize
  var idx = 0
  while idx < failures.len:
    let target = failures[idx].signature
    let probe: Probe = proc(candidate: seq[uint64]; used: var seq[uint64]): bool =
      src.startReplay(candidate, maxSize)
      let r = execute(prop, src)
      if r.outcome != ocFail: return false
      used = src.choices
      if r.signature == target: return true
      if failures.len < maxFailures:
        var known = false
        for f in failures:
          if f.signature == r.signature: known = true
        if not known:
          failures.add Failure(signature: r.signature, choices: used, message: r.message)
    var sh = initShrinker(failures[idx].choices, maxShrinks, probe)
    sh.shrink()
    failures[idx].choices = sh.best
    failures[idx].shrinkExecutions = sh.executions
    inc idx
  result.failures = move failures

  # 3. Re-run each minimal sequence twice: record inputs and detect
  #    flakiness (RL3). Two runs catch properties that alternate.
  var anyReal = false
  for f in result.failures.mitems:
    var reproduced = true
    for attempt in 0 .. 1:
      src.startReplay(f.choices, settings.maxSize)
      src.recordInputs = attempt == 1
      let r = execute(prop, src)
      if r.outcome == ocFail and r.signature == f.signature:
        if attempt == 1:
          f.message = r.message
          f.stackTrace = r.stackTrace
      else:
        reproduced = false
    f.inputs = src.inputs
    if reproduced: anyReal = true
    else: f.flaky = true
  result.status = if anyReal: psFailed else: psFlaky

## Run loop of a property: generate, execute, shrink, re-run, report.

import std/[os, strutils, math, monotimes, times, hashes]
import prng, choices, signature, shrink, database, jsonout, watchdog

export reportFormat

export signature

type
  Verbosity* = enum
    ## What is printed (O2). `PROPTEST_VERBOSITY` sets the default.
    vQuiet = "quiet"      ## Failures only.
    vNormal = "normal"    ## Also warnings, and statistics of properties that use labels.
    vVerbose = "verbose"  ## Also every statistic, and each case's inputs.
    vDebug = "debug"      ## Also every accepted shrink step.

  Settings* = object
    ## Per-property settings (K1). Build with `initSettings`.
    name*: string          ## Property name; derives its seed. Empty: `file:line`.
    cases*: int            ## Passing cases required.
    maxSize*: int          ## Size reached by the last case.
    maxDiscardRatio*: int  ## Give up after `cases * maxDiscardRatio` discards.
    maxShrinks*: int       ## Execution budget for shrinking each failure.
    maxChoices*: int       ## Maximum choices per case (RL7).
    maxFailures*: int      ## Distinct failures kept and shrunk (RL5).
    maxSteps*: int         ## Stateful tests: maximum commands per sequence.
    verbosity*: Verbosity  ## What is printed (O2).
    swarm*: bool           ## Stateful tests: swarm testing (ADR-0012).
    edgeBias*: float       ## Share of edge-case proposals while exploring (G8).
    mineConstants*: bool   ## Integer literals of the test file as boundary hints (ADR-0012).
    deadline*: int         ## Per-case deadline in ms; 0 = off (RL8). `PROPTEST_DEADLINE`.
    timeBudget*: int       ## Exploration time budget in ms; 0 = none (PF8).
    shrinkTimeBudget*: int ## Shrinking time budget per failure in ms; 0 = none (S4).
    suppress*: set[HealthCheck] ## Health checks not to run (RL11).
    maxDepth*: int         ## Nesting depth of recursive data while exploring (ADR-0013).
    report*: string        ## JSON Lines file the result is appended to; empty = none (O3). `PROPTEST_REPORT`.
    hangTimeout*: int      ## A case running longer (ms) is reported and the process ends (RL10); 0 (default) = off. `PROPTEST_HANG_TIMEOUT`.
    seed*: uint64          ## Run seed; 0 uses `PROPTEST_SEED` or a random one.

  HealthCheck* = enum
    ## Early warnings with a fix (RL11); `initSettings(suppress = {...})`.
    hcLargeData        ## Many cases exceed `maxChoices`.
    hcFewDistinct      ## Far fewer distinct inputs than cases.
    hcSlowGeneration   ## Generating inputs takes most of the run time.

  PropertyStatus* = enum
    psPassed          ## Every case passed.
    psFailed          ## At least one reproducible counterexample.
    psFlaky           ## Failures did not reproduce when re-run (RL3).
    psGaveUp          ## Too many discarded cases.
    psGeneratorError  ## A generator raised (RL6).
    psInsufficientCoverage  ## Every case passed, but a `cover` requirement was not met (D2).

  FailureSource* = enum
    fsExplored   ## Found by random exploration.
    fsDatabase   ## Replayed from the failure database (R3).
    fsExample    ## An explicit `example(...)` (R4).

  Failure* = object
    signature*: Signature
    source*: FailureSource
    choices*: seq[uint64]      ## Minimal choice sequence.
    message*: string
    stackTrace*: string
    inputs*: seq[tuple[name, value: string]]
    steps*: seq[string]        ## Stateful tests: the failing sequence as Nim calls.
    machine*: string           ## Stateful tests: the machine name.
    shrinkExecutions*: int
    shrinkStopped*: bool       ## Shrinking hit its time budget: best counterexample so far (S4).
    flaky*: bool
    spans: seq[Span]
    exampleIndex: int

  PropertyResult* = object
    name*: string
    status*: PropertyStatus
    runSeed*: uint64
    casesRun*: int
    discarded*: int
    firstFailureAt*: int       ## Case number (1-based, discards included) of the first failure; 0 if none.
    filterDiscards*: int
    overruns*: int
    failures*: seq[Failure]
    message*: string           ## Details for `psGaveUp`, `psGeneratorError`, `psInsufficientCoverage`.
    labels*: seq[LabelStat]    ## `classify`/`cover`/`label` counts, and stateful statistics (D1).
    labeledCases*: int         ## Cases the label percentages refer to (discards excluded).
    lengthHist*: array[8, int] ## Stateful: sequence lengths 0, 1, 2-3, 4-7, ... 64+.
    warnings*: seq[string]     ## Health checks and coverage notes (RL11, O4).
    targets*: seq[tuple[label: string, best: float]] ## Best `target` score per name (ADR-0016).
    verbosity*: Verbosity

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

proc envVerbosity(): Verbosity =
  let v = getEnv("PROPTEST_VERBOSITY").strip.toLowerAscii
  if v.len == 0: return vNormal
  for x in Verbosity:
    if $x == v: return x
  raise newException(ValueError, "PROPTEST_VERBOSITY must be quiet, normal, verbose or debug: " & v)

proc initSettings*(name = "";
                   cases = envInt("PROPTEST_CASES", 100);
                   maxSize = 100;
                   maxDiscardRatio = 10;
                   maxShrinks = envInt("PROPTEST_MAX_SHRINKS", 2000);
                   maxChoices = defaultMaxChoices;
                   maxFailures = 3;
                   maxSteps = 50;
                   verbosity = envVerbosity();
                   swarm = true;
                   edgeBias = defaultEdgeBias;
                   mineConstants = true;
                   deadline = envInt("PROPTEST_DEADLINE", 0);
                   timeBudget = envInt("PROPTEST_TIME_BUDGET", 0);
                   shrinkTimeBudget = 0;
                   suppress: set[HealthCheck] = {};
                   maxDepth = defaultMaxDepth;
                   report = getEnv("PROPTEST_REPORT");
                   hangTimeout = envInt("PROPTEST_HANG_TIMEOUT", 0);
                   seed = 0'u64): Settings =
  ## Defaults can be changed globally with environment variables (K2):
  ## `PROPTEST_CASES`, `PROPTEST_MAX_SHRINKS`, `PROPTEST_SEED`,
  ## `PROPTEST_REPORT`, ...
  Settings(name: name, cases: cases, maxSize: maxSize, maxDiscardRatio: maxDiscardRatio,
           maxShrinks: maxShrinks, maxChoices: maxChoices, maxFailures: maxFailures,
           maxSteps: maxSteps, verbosity: verbosity, swarm: swarm,
           edgeBias: edgeBias, mineConstants: mineConstants,
           deadline: deadline, timeBudget: timeBudget,
           shrinkTimeBudget: shrinkTimeBudget, suppress: suppress, maxDepth: maxDepth,
           report: report, hangTimeout: hangTimeout, seed: seed)

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
  req s.maxSteps >= 1, "maxSteps must be >= 1"
  req s.edgeBias >= 0.0 and s.edgeBias <= 1.0, "edgeBias must be in 0.0 .. 1.0"
  req s.deadline >= 0, "deadline must be >= 0 (ms; 0 disables it)"
  req s.maxDepth >= 0, "maxDepth must be >= 0"
  req s.timeBudget >= 0, "timeBudget must be >= 0 (ms; 0 means none)"
  req s.shrinkTimeBudget >= 0, "shrinkTimeBudget must be >= 0 (ms; 0 means none)"
  req s.hangTimeout >= 0, "hangTimeout must be >= 0 (ms; 0 disables the watchdog)"

proc passed*(r: PropertyResult): bool {.inline.} = r.status == psPassed

proc wilsonUpper*(hits, n: int; z = 1.96): float =
  ## Upper bound of the Wilson score interval for a proportion: `cover` fails
  ## only when even this bound is below the requirement (ADR-0012).
  if n == 0: return 1.0
  let p = hits / n
  let nf = n.float
  let z2 = z * z
  (p + z2 / (2 * nf) + z * sqrt(p * (1 - p) / nf + z2 / (4 * nf * nf))) / (1 + z2 / nf)

proc checkCoverage(r: var PropertyResult) =
  ## D2: fail confidently-low `cover` requirements; note the uncertain ones.
  let n = r.labeledCases
  for st in r.labels:
    if st.kind != lkCover: continue
    let observed = if n == 0: 0.0 else: 100.0 * st.cases.float / n.float
    if observed >= st.required: continue
    let line = "cover '" & st.name & "': " & formatFloat(observed, ffDecimal, 1) &
      "% of " & $n & " cases, " & formatFloat(st.required, ffDecimal, 1) & "% required"
    if 100.0 * wilsonUpper(st.cases, n) < st.required:
      if r.status == psPassed: r.status = psInsufficientCoverage
      if r.message.len > 0: r.message.add "\n"
      r.message.add line
    else:
      r.warnings.add line & " (too few cases to be sure; raise `cases`)"


# ----------------------------------------------------------------- execution

# The run loop executes once per case and per shrink step: no stack or line
# traces in its own frames. A failure's stack trace is captured when the
# exception is raised, from the frames of the property and the code under
# test, which keep theirs (library frames are skipped by signatures anyway).
{.push stackTrace: off, lineTrace: off.}

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

proc execute(prop: PropertyProc; src: ChoiceSource; limitNs = 0'i64;
             property = ""): CaseResult =
  let t0 = if limitNs > 0: getMonoTime() else: MonoTime()
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
  if limitNs > 0 and result.outcome in {ocPass, ocDiscard}:
    # RL8: a case that returned, but too late, is a failure of its own kind.
    let took = (getMonoTime() - t0).inNanoseconds
    if took > limitNs:
      result.outcome = ocFail
      result.filter = false
      result.signature = Signature(kind: "DeadlineExceeded", location: property)
      result.message = "case took " & formatFloat(took.float / 1e6, ffDecimal, 1) &
        " ms; deadline " & formatFloat(limitNs.float / 1e6, ffDecimal, 1) & " ms"

proc echoCase(name: string; n: int; outcome: Outcome; src: ChoiceSource) =
  ## `verbose`: one line per case (O2).
  var parts: seq[string]
  for (k, v) in src.inputs: parts.add k & " = " & v
  if src.steps.len > 0: parts.add src.steps.join("; ")
  let what = case outcome
    of ocPass: "passed"
    of ocDiscard: "discarded"
    of ocOverrun: "too large"
    of ocFail: "FAILED"
    of ocGenError: "generator error"
  echo "  [", name, "] case ", n, " ", what, ": ", parts.join(", ")

proc sizeFor(s: Settings; attempt: int): int {.inline.} =
  ## Sizes grow from 0 to `maxSize` over the run: simple cases first. Every
  ## attempt counts, discarded ones included, so a property that discards
  ## small inputs (`assume(xs.len > 30)`) still reaches larger ones.
  if s.cases <= 1: s.maxSize
  else: min(s.maxSize, (s.maxSize * attempt) div (s.cases - 1))

# --------------------------------------------------------- JSON report (O3)

proc statusName(s: PropertyStatus): string =
  case s
  of psPassed: "passed"
  of psFailed: "failed"
  of psFlaky: "flaky"
  of psGaveUp: "gaveUp"
  of psGeneratorError: "generatorError"
  of psInsufficientCoverage: "insufficientCoverage"

proc toJsonLine*(r: PropertyResult; durationMs = 0.0): string =
  ## One property result as a single line of JSON (O3). The seed is a string:
  ## it does not fit the 53-bit integers of many JSON readers.
  result = "{"
  result.addJson("format", reportFormat); result.add ','
  result.addJson("name", r.name); result.add ','
  result.addJson("status", statusName(r.status)); result.add ','
  result.addJson("passed", r.status == psPassed); result.add ','
  result.addJson("seed", $r.runSeed); result.add ','
  result.addJson("program", getAppFilename()); result.add ','
  result.addJson("replay", "PROPTEST_SEED=" & $r.runSeed & " " & getAppFilename()); result.add ','
  result.addJson("casesPassed", r.casesRun); result.add ','
  result.addJson("discarded", r.discarded); result.add ','
  result.addJson("firstFailureAt", r.firstFailureAt); result.add ','
  result.addJson("durationMs", round(durationMs, 3)); result.add ','
  result.addJson("message", r.message); result.add ','
  result.add "\"failures\":["
  for i, f in r.failures:
    if i > 0: result.add ','
    result.add '{'
    result.addJson("kind", f.signature.kind); result.add ','
    result.addJson("location", f.signature.location); result.add ','
    result.addJson("message", f.message); result.add ','
    result.addJson("source", (case f.source
      of fsExplored: "explored"
      of fsDatabase: "database"
      of fsExample: "example")); result.add ','
    result.addJson("flaky", f.flaky); result.add ','
    result.addJson("choices", f.choices.len); result.add ','
    result.addJson("shrinkExecutions", f.shrinkExecutions); result.add ','
    result.addJson("shrinkStopped", f.shrinkStopped); result.add ','
    result.add "\"inputs\":["
    for j, (name, value) in f.inputs:
      if j > 0: result.add ','
      result.add '{'
      result.addJson("name", name); result.add ','
      result.addJson("value", value)
      result.add '}'
    result.add "],"
    result.addJson("machine", f.machine); result.add ','
    result.addJson("steps", f.steps); result.add ','
    result.addJson("stackTrace", f.stackTrace)
    result.add '}'
  result.add "],"
  result.addJson("labeledCases", r.labeledCases); result.add ','
  result.add "\"labels\":["
  for i, st in r.labels:
    if i > 0: result.add ','
    result.add '{'
    result.addJson("name", st.name); result.add ','
    result.addJson("kind", (case st.kind
      of lkClassify: "classify"
      of lkCover: "cover"
      of lkLabel: "label"
      of lkCommand: "command"
      of lkDisabled: "preconditionFalse")); result.add ','
    result.addJson("cases", st.cases); result.add ','
    result.addJson("events", st.events)
    if st.kind == lkCover:
      result.add ','
      result.addJson("required", st.required)
    result.add '}'
  result.add "],"
  result.add "\"targets\":["
  for i, t in r.targets:
    if i > 0: result.add ','
    result.add '{'
    result.addJson("label", t.label); result.add ','
    result.addJson("best", t.best)
    result.add '}'
  result.add "],"
  result.addJson("warnings", r.warnings)
  result.add '}'

proc appendReport*(path: string; r: PropertyResult; durationMs = 0.0) =
  ## Appends `r` to the JSON Lines file `path`, creating it and its directory.
  ## One write per line, so runs of several test programs share the file.
  appendJsonLine(path, toJsonLine(r, durationMs))

# -------------------------------------------------------------------- engine

proc runProperty*(prop: PropertyProc; settings: Settings; dbKey = "";
                  examples: seq[PropertyProc] = @[]): PropertyResult =
  ## Runs a property and returns its result. Never raises for failures of the
  ## property itself; raises `ValueError` for invalid settings. Explicit
  ## `examples` run first (R4), then the failures saved under `dbKey` in the
  ## failure database (R3, ADR-0014), then random cases.
  validate(settings)
  let rs = if settings.seed != 0: settings.seed else: runSeed()
  writeBreadcrumb(rs)
  result = PropertyResult(name: settings.name, runSeed: rs, verbosity: settings.verbosity)
  let runStarted = getMonoTime()
  defer:
    if settings.report.len > 0:
      appendReport(settings.report, result,
                   (getMonoTime() - runStarted).inNanoseconds.float / 1e6)
  let src = newChoiceSource(deriveSeed(rs, settings.name), settings.maxChoices,
                            settings.edgeBias)
  # RL10: a case that never returns is reported by the watchdog thread.
  let watching = armWatchdog(settings.name, dbKey, rs, settings.hangTimeout, src,
                             "PROPTEST_SEED=" & $rs & " " & getAppFilename(), settings.report)
  defer:
    if watching: disarmWatchdog()
  if not settings.mineConstants: src.useHints([])   # locks the hints empty
  src.maxDepth = settings.maxDepth
  let maxDiscards = settings.cases * settings.maxDiscardRatio
  let verbose = settings.verbosity >= vVerbose
  # RL8: 1.25 x the deadline while exploring, so a case just over it does not
  # turn into a flaky report; shrinking and re-runs use the deadline itself.
  let deadlineNs = int64(settings.deadline) * 1_000_000
  let exploreLimit = deadlineNs + deadlineNs div 4
  let started = getMonoTime()
  let budgetNs = int64(settings.timeBudget) * 1_000_000
  var failingCases = 0
  var caseNumber = 0

  # 0. Explicit examples, then saved failures, before any random case.
  var kept: seq[DbEntry]          # saved entries still worth keeping
  defer:
    # Save what failed (reproduced) and what is still being re-checked.
    if dbKey.len > 0:
      var entries = kept
      if result.status == psFailed:
        for f in result.failures:
          if f.source != fsExample and not f.flaky:
            var dup = false
            for e in entries:
              if e.choices == f.choices: dup = true
            if not dup: entries.add DbEntry(passes: 0, choices: f.choices)
      saveEntries(dbKey, entries)
  template noteFailure(r: CaseResult; how: FailureSource; index = -1) =
    inc failingCases
    if result.firstFailureAt == 0: result.firstFailureAt = caseNumber
    var known = false
    for f in result.failures:
      if f.signature == r.signature: known = true
    if not known:
      result.failures.add Failure(signature: r.signature, choices: src.choices,
                                  message: r.message, spans: src.spans,
                                  source: how, exampleIndex: index)
  for i, ex in examples:
    src.startReplay([], settings.maxSize)
    inc caseNumber
    src.recordInputs = true          # rare cases: inputs for the watchdog
    caseStarted(waExample, caseNumber)
    let r = execute(ex, src, deadlineNs, settings.name)
    if r.outcome == ocFail: noteFailure(r, fsExample, i)
  for e in loadEntries(dbKey):
    src.startReplay(e.choices, settings.maxSize)
    inc caseNumber
    src.recordInputs = true          # rare cases: inputs for the watchdog
    caseStarted(if e.passes == hungMark: waSavedHang else: waSaved, caseNumber)
    let r = execute(prop, src, deadlineNs, settings.name)
    case r.outcome
    of ocFail:
      noteFailure(r, fsDatabase)
    of ocPass:
      if e.passes + 1 < dbPassesToForget:
        kept.add DbEntry(passes: e.passes + 1, choices: e.choices)
    of ocDiscard, ocOverrun, ocGenError:
      discard              # no longer fits the generators: forgotten (RL12)

  # 1. Explore `cases` cases (passing or failing), unless too many are
  #    discarded. After a failure, exploration goes on to look for other
  #    distinct bugs (RL5) and stops once `maxFailures` are known.
  # Health checks (RL11): distinct inputs, and generation time on 1 case in 8.
  # Up to 64 distinct input hashes in a fixed array: no allocation, and
  # "few distinct inputs" only matters below that.
  var seenHashes: array[64, Hash]
  var nSeen = 0
  var manyDistinct = false
  var timedNs = 0'i64
  var bests: seq[tuple[label: string, score: float, choices: seq[uint64]]]
  var nextTarget = 0
  while result.casesRun + failingCases < settings.cases and
        result.failures.len < settings.maxFailures:
    if budgetNs > 0 and (getMonoTime() - started).inNanoseconds > budgetNs:
      # PF8: stop gracefully and say so.
      result.warnings.add "time budget of " & $settings.timeBudget & " ms reached after " &
        $(result.casesRun + failingCases) & " of " & $settings.cases & " cases"
      break
    let size = sizeFor(settings, result.casesRun + failingCases + result.discarded)
    # Targeted exploration (ADR-0016): once half of the cases ran, every
    # other case starts from a prefix (at least half) of the best case of a
    # `target` name, in turn, and explores from there.
    let attempt = result.casesRun + failingCases + result.discarded
    if bests.len > 0 and 2 * attempt >= settings.cases and (attempt and 1) == 1:
      let b = addr bests[nextTarget mod bests.len]
      inc nextTarget
      let n = b.choices.len
      let keep = if n <= 1: n else: n div 2 + int(src.nextRandom() mod uint64(n - n div 2))
      src.startExtend(b.choices, keep, size)
    else:
      src.startRandom(size)
    inc caseNumber
    src.recordInputs = verbose
    src.timing = (caseNumber and 7) == 0 and hcSlowGeneration notin settings.suppress
    let t0 = if src.timing: getMonoTime() else: MonoTime()
    caseStarted(waExploring, caseNumber)
    let r = execute(prop, src, exploreLimit, settings.name)
    if src.timing: timedNs += (getMonoTime() - t0).inNanoseconds
    if r.outcome == ocPass and not manyDistinct and hcFewDistinct notin settings.suppress:
      let h = src.choicesHash
      var known = false
      for k in 0 ..< nSeen:
        if seenHashes[k] == h:
          known = true
          break
      if not known:
        if nSeen == seenHashes.len: manyDistinct = true
        else:
          seenHashes[nSeen] = h
          inc nSeen
    if verbose: echoCase(settings.name, caseNumber, r.outcome, src)
    case r.outcome
    of ocPass:
      inc result.casesRun
      # Keep the best case per `target` name; copying only on improvement.
      for (label, score) in src.caseTargets:
        var found = false
        for b in bests.mitems:
          if b.label == label:
            found = true
            if score > b.score:
              b.score = score
              b.choices = src.choices
        if not found:
          bests.add (label, score, src.choices)
    of ocDiscard, ocOverrun:
      src.discardLabels()
      inc result.discarded
      if r.filter: inc result.filterDiscards
      if r.outcome == ocOverrun: inc result.overruns
      if result.discarded > maxDiscards:
        result.status = psGaveUp
        result.message = "gave up after " & $result.casesRun & " passing cases: " &
          $result.discarded & " cases discarded (" & $result.filterDiscards &
          " by filters, " & $result.overruns & " too large)"
        if result.filterDiscards * 2 > result.discarded:
          result.message.add ". Most discards come from `filter` or `uniqueSeqs` rejecting " &
            "values: generate valid values directly, or widen the generator."
        return
    of ocGenError:
      result.status = psGeneratorError
      result.message = "a generator raised: " & r.message
      return
    of ocFail:
      noteFailure(r, fsExplored)
  let explored = result.casesRun + failingCases
  if hcLargeData notin settings.suppress and result.overruns * 10 > explored + result.discarded and
     result.overruns > 0:
    result.warnings.add $result.overruns & " cases needed more than maxChoices (" &
      $settings.maxChoices & ") choices and were skipped: bound collection sizes " &
      "(`seqs(g, maxLen = ...)`) or raise maxChoices"
  if hcFewDistinct notin settings.suppress and result.casesRun >= 50 and not manyDistinct and
     nSeen * 10 < result.casesRun:
    result.warnings.add "only " & $nSeen & " distinct inputs in " & $result.casesRun &
      " passing cases: the input space is small, so a plain loop over it would be exhaustive"
  if hcSlowGeneration notin settings.suppress and timedNs > 50_000_000 and
     src.genNs * 10 > timedNs * 8:
    result.warnings.add "generating inputs takes " & $(src.genNs * 100 div timedNs) &
      "% of the run time: prefer constructive generators to `filter`, or smaller sizes"
  result.labels = src.labelStats
  for b in bests: result.targets.add (b.label, b.score)
  result.labeledCases = result.casesRun + failingCases
  result.lengthHist = src.lengthHist
  if result.failures.len == 0:
    result.status = psPassed
    result.checkCoverage()
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
    let probe: Probe = proc(candidate: seq[uint64]; used: var seq[uint64];
                            spans: var seq[Span]): bool =
      src.startReplay(candidate, maxSize)
      caseStarted(waShrinking, caseNumber)
      let r = execute(prop, src, deadlineNs, settings.name)
      if r.outcome != ocFail: return false
      used = src.choices
      spans = src.spans
      if r.signature == target:
        if settings.verbosity >= vDebug:
          echo "  [", settings.name, "] shrink: ", candidate.len, " choices still fail"
        return true
      if failures.len < maxFailures:
        var known = false
        for f in failures:
          if f.signature == r.signature: known = true
        if not known:
          failures.add Failure(signature: r.signature, choices: used, message: r.message,
                               spans: spans)
    var sh = initShrinker(failures[idx].choices, maxShrinks, probe, failures[idx].spans,
                          settings.shrinkTimeBudget)
    sh.shrink()
    failures[idx].shrinkStopped = sh.timedOut
    failures[idx].choices = sh.best
    failures[idx].shrinkExecutions = sh.executions
    inc idx
  result.failures = move failures

  # 3. Re-run each minimal sequence twice: record inputs and detect
  #    flakiness (RL3). Two runs catch properties that alternate.
  var anyReal = false
  for f in result.failures.mitems:
    var reproduced = true
    let run = if f.source == fsExample: examples[f.exampleIndex] else: prop
    for attempt in 0 .. 1:
      src.startReplay(f.choices, settings.maxSize)
      src.recordInputs = attempt == 1
      caseStarted(waRerunning, caseNumber)
      let r = execute(run, src, deadlineNs, settings.name)
      if r.outcome == ocFail and r.signature == f.signature:
        if attempt == 1:
          f.message = r.message
          f.stackTrace = r.stackTrace
      else:
        reproduced = false
    f.inputs = src.inputs
    f.steps = src.steps
    f.machine = src.machine
    if reproduced: anyReal = true
    else: f.flaky = true
  result.status = if anyReal: psFailed else: psFlaky

{.pop.}

## Watchdog for cases that never return (RL10, ADR-0017). Off by default:
## `hangTimeout` / `PROPTEST_HANG_TIMEOUT` turns it on.
##
## A running case cannot be interrupted safely: Nim has no way to stop a
## thread in the middle of arbitrary code. So when a case runs longer than
## `hangTimeout`, a background thread reports it (property, seed, what the
## engine was doing, the case's choices and, when they were recorded, its
## inputs), saves the case in the failure database, appends a `hung` line to
## the JSON report, and ends the process with exit code 1.
##
## The next run replays the saved case first with its inputs recorded, so a
## case that still hangs is reported with its inputs (`x = 42`).
##
## Cost on the engine's side: one atomic increment per case. The thread is
## started by the first property that arms it, and only with
## `--threads:on` (Nim 2's default); without threads there is no watchdog.

import choices

type
  WatchActivity* = enum
    ## What the engine is doing, for the report.
    waExample = "running an explicit example"
    waSaved = "replaying a saved failure"
    waSavedHang = "replaying a case that hung in an earlier run"
    waExploring = "exploring"
    waShrinking = "shrinking a failure"
    waRerunning = "re-running the minimal failing case"

when compileOption("threads"):
  import std/[os, locks, atomics]
  import database, jsonout

  type Watched = object
    ## What the watchdog needs to know about the running property. Written
    ## by the property's thread under `lock`, copied by the watchdog.
    name, key, replay, report: string
    seed: uint64
    timeoutMs: int
    src: pointer          # the property's ChoiceSource, never owned here

  var
    lock: Lock
    watched: Watched
    armed: Atomic[bool]
    beat: Atomic[int]          # bumped at the start of every case
    activity: Atomic[int]      # a WatchActivity
    caseNumber: Atomic[int]
    started: bool              # touched by the arming thread only
    thread: Thread[void]

  proc choicesLine(choices: seq[uint64]): string =
    const shown = 64
    for i, c in choices:
      if i == shown:
        result.add " ... (" & $(choices.len - shown) & " more)"
        break
      if i > 0: result.add ' '
      result.add $c

  proc fire(w: Watched) =
    ## Reports the case that does not return and ends the process.
    if w.src.isNil: return
    let src {.cursor.} = cast[ChoiceSource](w.src)
    let what = WatchActivity(activity.load)
    let choices = src.choices
    let phase = if src.phase == cpGenerate: "generating its inputs" else: "running the property"
    var saved = false
    let dbDir = databaseDir()
    if w.key.len > 0 and dbDir != "off":
      var entries = loadEntries(w.key)
      var known = false
      for e in entries.mitems:
        if e.choices == choices:
          e.passes = hungMark
          known = true
      if not known: entries.add DbEntry(passes: hungMark, choices: choices)
      saveEntries(w.key, entries)
      saved = true
    var msg = "\nproptest: property '" & w.name & "' did not return: a case has run for more than " &
      $w.timeoutMs & " ms (hangTimeout) while " & $what & " (case " & $caseNumber.load &
      "), " & phase & ".\n"
    if src.recordInputs and src.inputs.len > 0:
      msg.add "  Inputs:\n"
      for (name, value) in src.inputs: msg.add "    " & name & " = " & value & "\n"
    elif src.steps.len == 0:
      msg.add "  Inputs: not recorded while exploring (formatting them would cost time on every case).\n"
      if saved:
        msg.add "  The case was saved in the failure database: the next run replays it first and\n" &
                "  prints its inputs here if it still does not return.\n"
      else:
        msg.add "  To see them, replay with PROPTEST_VERBOSITY=verbose (the failure database is off).\n"
    if src.steps.len > 0:
      msg.add "  Steps so far (the last one does not return):\n"
      for step in src.steps: msg.add "    " & step & "\n"
    msg.add "  Choices (" & $choices.len & "): " & choicesLine(choices) & "\n"
    msg.add "  Replay: " & w.replay & "\n"
    msg.add "  The process stops here (exit code 1): a running case cannot be interrupted safely.\n"
    try:
      stderr.write msg
      stderr.flushFile()
    except IOError: discard
    if w.report.len > 0:
      var line = "{"
      line.addJson("format", reportFormat); line.add ','
      line.addJson("name", w.name); line.add ','
      line.addJson("status", "hung"); line.add ','
      line.addJson("passed", false); line.add ','
      line.addJson("seed", $w.seed); line.add ','
      line.addJson("program", getAppFilename()); line.add ','
      line.addJson("replay", w.replay); line.add ','
      line.addJson("message", "a case has run for more than " & $w.timeoutMs &
        " ms (hangTimeout) while " & $what); line.add ','
      line.addJson("hangTimeoutMs", w.timeoutMs)
      line.add '}'
      try: appendJsonLine(w.report, line)
      except IOError: discard
    quit(QuitFailure)

  proc watch() {.thread.} =
    var lastBeat = -1
    var still = 0
    while true:
      var w: Watched
      {.cast(gcsafe).}:
        withLock lock: w = watched
      let tick = if w.timeoutMs <= 0: 200 else: clamp(w.timeoutMs div 10, 5, 500)
      sleep(tick)
      if not armed.load or w.timeoutMs <= 0:
        lastBeat = -1
        still = 0
        continue
      let b = beat.load
      if b != lastBeat:
        lastBeat = b
        still = 0
        continue
      still += tick
      if still >= w.timeoutMs:
        {.cast(gcsafe).}:
          withLock lock: w = watched
          if armed.load: fire(w)

  proc armWatchdog*(name, key: string; seed: uint64; timeoutMs: int;
                    src: ChoiceSource; replay, report: string): bool =
    ## Starts watching a property; false when off (`timeoutMs <= 0`) or when
    ## another property is already watched (nested or concurrent).
    if timeoutMs <= 0: return false
    var expected = false
    if not armed.compareExchange(expected, true): return false
    if not started:
      initLock(lock)
      started = true
      withLock lock:
        watched = Watched(name: name, key: key, replay: replay, report: report,
                          seed: seed, timeoutMs: timeoutMs, src: cast[pointer](src))
      createThread(thread, watch)
    else:
      withLock lock:
        watched = Watched(name: name, key: key, replay: replay, report: report,
                          seed: seed, timeoutMs: timeoutMs, src: cast[pointer](src))
    beat.atomicInc
    true

  proc disarmWatchdog*() =
    withLock lock: watched.src = nil
    armed.store(false)

  proc caseStarted*(what: WatchActivity; n: int) {.inline.} =
    ## A case starts: the watchdog sees progress.
    activity.store(ord(what), moRelaxed)
    caseNumber.store(n, moRelaxed)
    beat.atomicInc()

else:
  proc armWatchdog*(name, key: string; seed: uint64; timeoutMs: int;
                    src: ChoiceSource; replay, report: string): bool =
    ## Without `--threads:on` there is no watchdog.
    false

  proc disarmWatchdog*() = discard

  proc caseStarted*(what: WatchActivity; n: int) {.inline.} = discard

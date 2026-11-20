## Run seed and crash breadcrumbs (ADR-0003, RL9).
##
## The run seed comes from `PROPTEST_SEED` or is picked once per process. It
## is written to `.proptest/last-run` before the first case, so a crash or a
## killed hang can still be replayed. `PROPTEST_DB=off` disables the files;
## `PROPTEST_DB=<dir>` moves them. File errors never fail a test.

import std/[os, strutils, monotimes, times]
import prng

var
  cachedRunSeed: uint64
  runSeedReady: bool
  breadcrumbDone: bool

const proptestDb {.strdefine.} = ".proptest"
  ## Default of `PROPTEST_DB`; `-d:proptestDb=off` disables the files by
  ## default (the library's own tests and benchmarks need repeatable runs).

proc databaseDir*(): string =
  ## Directory of the local files, or "off".
  getEnv("PROPTEST_DB", proptestDb)

proc runSeed*(): uint64 =
  ## Seed of this process: `PROPTEST_SEED` when set, otherwise random.
  if not runSeedReady:
    let env = getEnv("PROPTEST_SEED").strip
    if env.len > 0:
      try:
        cachedRunSeed = uint64(parseBiggestUInt(env))
      except ValueError:
        raise newException(ValueError, "PROPTEST_SEED is not an unsigned integer: " & env)
    else:
      var st = uint64(getMonoTime().ticks) xor
               (uint64(getCurrentProcessId()) shl 32) xor
               uint64(epochTime() * 1e6)
      cachedRunSeed = splitMix64(st)
      if cachedRunSeed == 0: cachedRunSeed = 1
    runSeedReady = true
  cachedRunSeed

proc writeBreadcrumb*(seed: uint64) =
  ## Writes the run seed once per process, atomically (temporary file + rename).
  if breadcrumbDone: return
  breadcrumbDone = true
  let dir = databaseDir()
  if dir == "off": return
  try:
    createDir(dir)
    let tmp = dir / ("last-run.tmp" & $getCurrentProcessId())
    writeFile(tmp, "PROPTEST_SEED=" & $seed & "\ncommand=" & getAppFilename() & "\n")
    moveFile(tmp, dir / "last-run")
  except OSError, IOError:
    discard

# ---------------------------------------------------------- failure database

const
  dbHeader = "proptest-db 1"
  dbPassesToForget* = 3
  hungMark* = -1
    ## `passes` of a case saved by the watchdog (RL10): it did not return.
    ## A saved failure is forgotten after passing this many runs in a row.

type DbEntry* = object
  ## A saved minimal choice sequence and how many runs in a row it passed.
  passes*: int
  choices*: seq[uint64]

proc dbFile(key: string): string =
  databaseDir() / "db" / (toHex(fnv1a64(key)).toLowerAscii & ".txt")

proc loadEntries*(key: string): seq[DbEntry] =
  ## Saved failures of the property `key` (ADR-0014). A missing file, another
  ## format version or a malformed line gives no entries, never an error.
  if databaseDir() == "off" or key.len == 0: return
  let path = dbFile(key)
  try:
    if not fileExists(path): return
    var first = true
    for line in lines(path):
      if first:
        if line.strip != dbHeader: return
        first = false
        continue
      let parts = line.splitWhitespace
      if parts.len < 1: continue
      var e = DbEntry(passes: parseInt(parts[0]))
      for p in parts[1 .. ^1]: e.choices.add parseBiggestUInt(p).uint64
      result.add e
  except CatchableError:
    result.setLen(0)

proc saveEntries*(key: string; entries: openArray[DbEntry]) =
  ## Writes the entries atomically (temporary file + rename, RL12), or
  ## removes the file when there are none. Errors are ignored.
  if databaseDir() == "off" or key.len == 0: return
  let path = dbFile(key)
  try:
    if entries.len == 0:
      if fileExists(path): removeFile(path)
      return
    createDir(path.parentDir)
    var text = dbHeader & "\n"
    for e in entries:
      text.add $e.passes
      for c in e.choices: text.add " " & $c
      text.add "\n"
    let tmp = path & ".tmp" & $getCurrentProcessId()
    writeFile(tmp, text)
    moveFile(tmp, path)
  except CatchableError:
    discard

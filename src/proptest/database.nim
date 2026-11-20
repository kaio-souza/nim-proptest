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

proc databaseDir*(): string =
  ## Directory of the local files, or "off".
  getEnv("PROPTEST_DB", ".proptest")

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

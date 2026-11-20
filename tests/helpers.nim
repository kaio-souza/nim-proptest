## Shared helpers for the test suite.

import std/[os, osproc, strtabs, strutils]

const
  testsDir* = currentSourcePath().parentDir
  fixturesDir* = testsDir / "fixtures"

proc compileFixture*(name: string; flags = ""): tuple[output: string; ok: bool] =
  ## Compiles `tests/fixtures/<name>.nim` into `tests/fixtures/<name>`.
  let cmd = quoteShell(getCurrentCompilerExe()) & " c --hints:off " & flags &
    " -o:" & quoteShell(fixturesDir / name) & " " & quoteShell(fixturesDir / (name & ".nim"))
  let (output, code) = execCmdEx(cmd)
  (output, code == 0)

proc runFixture*(name: string; env: openArray[(string, string)] = []): tuple[output: string; code: int] =
  ## Runs a compiled fixture with extra environment variables.
  ## The environment is passed to the process, not as a `K=V cmd` prefix:
  ## that is POSIX shell syntax and fails on Windows.
  let fullEnv = newStringTable(modeCaseSensitive)
  for k, v in envPairs(): fullEnv[k] = v
  for (k, v) in env: fullEnv[k] = v
  let (output, code) = execCmdEx(quoteShell(fixturesDir / name), env = fullEnv,
                                 workingDir = fixturesDir)
  (output, code)

proc countOf*(haystack, needle: string): int =
  haystack.count(needle)

## Shared helpers for the test suite.

import std/[os, osproc, strutils]

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
  var cmd = ""
  for (k, v) in env:
    cmd.add k & "=" & quoteShell(v) & " "
  cmd.add quoteShell(fixturesDir / name)
  let (output, code) = execCmdEx(cmd, workingDir = fixturesDir)
  (output, code)

proc countOf*(haystack, needle: string): int =
  haystack.count(needle)

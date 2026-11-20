## PF9: compile-time cost of a test file with 50 properties over derived
## object generators (ADR-0013), against the same file over plain `int`s.
##
## Compile times depend on the machine, so this is informational in
## `nimble bench`; `--check` fails only past a generous budget (default
## 120 s, `B_COMPILE_BUDGET` to change it), to catch an explosion.

import std/[os, osproc, strformat, strutils, times, monotimes]

const header = """
import proptest, std/unittest
type
  Kind = enum circle, rect, tri
  Shape = object
    name: string
    case kind: Kind
    of circle: r: int
    of rect: w, h: int
    of tri: a, b, c: uint8
  Id = distinct int64
  Node = ref object
    val: int
    left, right: Node
  Order = object
    id: Id
    lines: seq[(string, int)]
    shape: Shape
    tags: HashSet[string]
    extra: Table[string, float]
"""

proc writeFile(path: string; derived: bool) =
  var s = header & "\nsuite \"compile\":\n"
  for i in 0 ..< 50:
    let src = if not derived: "int"
              else: ["Shape", "Order", "Node", "Id", "seq[Order]"][i mod 5]
    s.add &"  test \"p{i}\":\n    forAll(initSettings(cases = 1), x{i} in {src}):\n" &
          &"      check $x{i}.typeof != \"\"\n"
  writeFile(path, s)

proc compileSeconds(path: string): float =
  let cache = getTempDir() / ("b_compile_cache_" & path.splitFile.name)
  removeDir(cache)
  let cmd = quoteShell(getCurrentCompilerExe()) & " c --hints:off --warnings:off " &
    "--path:" & quoteShell(currentSourcePath().parentDir.parentDir / "src") &
    " --nimcache:" & quoteShell(cache) & " -o:" & quoteShell(path.changeFileExt("")) &
    " " & quoteShell(path)
  let t0 = getMonoTime()
  let (output, code) = execCmdEx(cmd)
  result = (getMonoTime() - t0).inMilliseconds.float / 1000
  if code != 0:
    echo output
    quit "compilation failed: " & path

proc main() =
  let dir = getTempDir() / "proptest_b_compile"
  createDir(dir)
  let plain = dir / "plain50.nim"
  let derived = dir / "derived50.nim"
  writeFile(plain, false)
  writeFile(derived, true)
  let p = compileSeconds(plain)
  let d = compileSeconds(derived)
  echo &"PF9: 50 properties over int      : {p:6.1f} s"
  echo &"PF9: 50 properties, derived types: {d:6.1f} s  ({d - p:+.1f} s)"
  if "--check" in commandLineParams():
    let budget = parseFloat(getEnv("B_COMPILE_BUDGET", "120"))
    if d > budget:
      quit &"FAIL: {d:.1f} s exceeds the budget of {int(budget)} s"
    echo &"OK: within the budget of {int(budget)} s"

main()

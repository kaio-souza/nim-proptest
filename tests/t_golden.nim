## Golden snapshot (RL15, Q7): what a seed produces, through the whole
## pipeline, must not change within a minor version (docs/STABILITY.md).
## CI runs it on Linux, macOS and Windows, debug and release, orc and arc.

import std/[unittest, os, strutils]
import golden

const snapshotFile = currentSourcePath().parentDir / "golden" / "snapshot.txt"

suite "golden snapshot":
  test "RL15/Q7: a seed generates, explores and shrinks exactly as recorded":
    # Normalised: a Windows checkout with core.autocrlf turns \n into \r\n.
    let expected = readFile(snapshotFile).replace("\r\n", "\n")
    let actual = snapshot()
    if actual != expected:
      let a = actual.splitLines
      let e = expected.splitLines
      var shown = 0
      var section = ""
      for i in 0 ..< max(a.len, e.len):
        let x = if i < a.len: a[i] else: "<end>"
        let y = if i < e.len: e[i] else: "<end>"
        if x.startsWith("## "): section = x
        if x != y and shown < 10:
          echo "  ", section, "\n    recorded: ", y, "\n    now:      ", x
          inc shown
      echo "\n  The values generated for a seed changed. If this is intended, it is a\n" &
        "  generation change: run `nimble golden` and list it in the CHANGELOG under\n" &
        "  \"Generation changes\" (docs/STABILITY.md). Otherwise it is a regression."
    check actual == expected

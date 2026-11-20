## Rewrites tests/golden/snapshot.txt (`nimble golden`). Run it only for an
## intended generation change, and list that change in the CHANGELOG under
## "Generation changes" (docs/STABILITY.md).

import std/os
import ../tests/golden

let path = currentSourcePath().parentDir.parentDir / "tests" / "golden" / "snapshot.txt"
let old = if fileExists(path): readFile(path) else: ""
let now = snapshot()
if now == old:
  echo "Golden snapshot unchanged."
else:
  writeFile(path, now)
  echo "Golden snapshot updated: ", path
  echo "This is a generation change: add it to the CHANGELOG under \"Generation changes\"."

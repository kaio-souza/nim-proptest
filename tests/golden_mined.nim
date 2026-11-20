## Golden snapshot, mined constants (ADR-0012): in a module of its own, so
## that its file literals are only the ones below. Do not add literals here
## without regenerating the snapshot (`nimble golden`).

import proptest

proc minedRun*(seed: uint64): (PropertyResult, seq[string]) =
  var shown: seq[string]
  let r = forAllResult(initSettings(name = "mined constants", seed = seed),
                       x in ints(0, 2000)):
    shown.add $x
    if x == 1000: discard      # 1000 is mined: 999, 1000, 1001 are proposed
  (r, shown)

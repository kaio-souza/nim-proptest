## Golden snapshot of what a seed produces (RL15, Q7; docs/STABILITY.md).
##
## `snapshot()` runs properties through the whole pipeline (run seed, seed
## derived from the property name, sizes growing over the run, edge bias,
## mined constants, swarm testing, shrinking) and renders, for each one, a
## hash of every generated value plus the first values in full. The text is
## committed in `tests/golden/snapshot.txt`; `t_golden` fails when it changes.
##
## A change here is a **generation change**: update the file with
## `nimble golden` and list the change under "Generation changes" in the
## CHANGELOG (docs/STABILITY.md).
##
## Constant mining is off in every property here (`mineConstants = false`),
## so that editing this file does not change the snapshot: the integer
## literals of a test file are boundary hints. Mining is covered on its own
## by `golden_mined.nim`, whose literals stay fixed.

import std/[os, strutils, options, tables, sets]
import proptest
import proptest/prng
import fixtures/[f_types, f_machine]
import golden_mined

const
  runSeed = 2026'u64
  shownValues = 6     # values printed in full per property, spread over the run
  maxWidth = 100      # characters per printed value

type
  Color = enum red, green, blue
  Celsius = distinct int
  Pair = tuple[a: int8, b: bool]
  Node = ref object
    val: int
    kids: seq[Node]

proc `$`(c: Celsius): string = $int(c) & "C"

var text: string

proc settings(name: string): Settings =
  initSettings(name = name, seed = runSeed, mineConstants = false)

proc section(title: string; r: PropertyResult; values: seq[string]) =
  text.add "## " & title & "\n"
  text.add "status=" & $r.status & " cases=" & $r.casesRun & " discarded=" & $r.discarded &
    " values=" & $values.len & " hash=" & toHex(fnv1a64(values.join("\n"))) & "\n"
  let n = min(shownValues, values.len)
  for k in 0 ..< n:
    let i = if n <= 1: 0 else: k * (values.len - 1) div (n - 1)
    let v = values[i]
    text.add "  [" & $i & "] " & (if v.len > maxWidth: v[0 ..< maxWidth] & "..." else: v) & "\n"
  for f in r.failures:
    text.add "  counterexample:"
    for (name, value) in f.inputs: text.add " " & name & "=" & value
    for step in f.steps: text.add " " & step & ";"
    text.add "  (" & f.signature.kind & ", " & $f.choices.len & " choices)\n"

template values(title: string; source: untyped) =
  ## Every value a 100-case run of `source` generates.
  block:
    var shown: seq[string]
    let r = forAllResult(settings(title), x in source):
      shown.add show(x)
    section(title, r, shown)

proc snapshot*(): string =
  text = ""
  text.add "# proptest golden snapshot: run seed " & $runSeed & "\n" &
    "# Regenerate with `nimble golden`; a change is a generation change (docs/STABILITY.md).\n\n"

  # --- Types: the generator is inferred (G2, G3) --------------------------
  values("int", int)
  values("int8", int8)
  values("uint64", uint64)
  values("range", range[-5 .. 5])
  values("float", float)
  values("float32", float32)
  values("bool", bool)
  values("char", char)
  values("string", string)
  values("enum", Color)
  values("seq[int]", seq[int])
  values("seq[seq[int8]]", seq[seq[int8]])
  values("array", array[3, uint8])
  values("set", set[Color])
  values("Option", Option[int16])
  values("tuple", Pair)

  # --- Containers and derived types (G4, G5) ------------------------------
  values("Table", Table[int8, string])
  values("OrderedTable", OrderedTable[Color, int])
  values("HashSet", HashSet[int16])
  values("object, private fields, other module", Account)
  values("case object", Shape)
  values("distinct", Celsius)
  values("recursive ref", Node)

  # --- Combinators (C1-C4, G6, G8) ----------------------------------------
  values("ints(lo, hi)", ints(-1000, 1000))
  values("ints near", ints(0, 1_000_000, near = [65_536]))
  values("floats(lo, hi)", floats(-1.0, 1.0))
  values("floats finite", floats(allowNaN = false, allowInf = false))
  values("chars", chars("abc"))
  values("strings", strings("xyz", 1, 8))
  values("seqs", seqs(ints(0, 9), 2, 5))
  values("map", ints(0, 100).map(proc(n: int): string = $(n * 2)))
  values("filter", ints(0, 1000).filter(proc(n: int): bool = n mod 3 == 0))
  values("flatMap", ints(1, 4).flatMap(proc(n: int): Gen[seq[int]] = seqs(ints(0, 9), n, n)))
  values("elements", elements(["a", "b", "c"]))
  values("oneOf", oneOf(ints(0, 9), ints(100, 109)))
  values("frequency", frequency([(1, constant(0)), (3, ints(1, 9))]))
  values("optionals", optionals(bools()))
  values("tables", tables(ints(0, 9), bools(), maxLen = 4))
  values("hashSets", hashSets(ints(0, 20), maxLen = 5))
  values("alphanumeric", strings(alphanumeric, 0, 12))
  values("identifiers", identifiers())
  values("unicodeStrings", unicodeStrings(0, 6))
  values("recursive", recursive(ints(0, 9).map(proc(n: int): string = $n),
    proc(inner: Gen[string]): Gen[string] =
      seqs(inner, 1, 3).map(proc(xs: seq[string]): string = "(" & xs.join(" ") & ")")))

  # --- Exploration settings ------------------------------------------------
  block:
    let (r, shown) = minedRun(runSeed)
    section("mined constants (golden_mined.nim)", r, shown)
  block:
    var shown: seq[string]
    let r = forAllResult(initSettings(name = "no edge bias", seed = runSeed, edgeBias = 0.0,
                                      mineConstants = false), x in int):
      shown.add $x
    section("no edge bias", r, shown)
  block:
    var shown: seq[string]
    let r = forAllResult(initSettings(name = "sizes", seed = runSeed, cases = 20, maxSize = 10,
                                      mineConstants = false),
                         xs in seq[int]):
      shown.add $xs.len
    section("sizes (cases = 20, maxSize = 10)", r, shown)

  # --- Shrinking: the reported counterexamples (S1-S3, RL5) -----------------
  block:
    var shown: seq[string]
    let r = forAllResult(settings("shrink int"), x in int):
      shown.add $x
      check x < 1000
    section("shrink: int boundary", r, shown)
  block:
    var shown: seq[string]
    let r = forAllResult(settings("shrink seq"), xs in seq[int]):
      shown.add show(xs)
      check xs.len < 3 or xs[0] <= xs[1]
    section("shrink: seq", r, shown)
  block:
    var shown: seq[string]
    let r = forAllResult(settings("shrink two bugs"),
                         x in ints(0, 100), s in string):
      shown.add $x & " " & show(s)
      check x <= 50
      check s.len < 4
    section("shrink: two bugs", r, shown)
  block:
    var shown: seq[string]
    let r = forAllResult(settings("shrink object"), s in Shape):
      shown.add show(s)
      check s.sides.len < 3 or s.sides[0] < 100
    section("shrink: case object", r, shown)

  # --- State machines (M1-M3, swarm) ---------------------------------------
  block:
    let r = stateMachineResult(BoundedQueue, settings("queue"))
    var stats: seq[string]
    for st in r.labels: stats.add $st.kind & " " & st.name & ": " & $st.cases &
      " sequences, " & $st.events & " events"
    section("state machine: planted queue bug", r, stats)

  # --- Failure database format (R3, ADR-0014) ------------------------------
  block:
    let dir = getTempDir() / ("proptest_golden_" & $getCurrentProcessId())
    removeDir(dir)
    putEnv("PROPTEST_DB", dir)
    discard forAllResult(settings("db entry"), xs in seq[int8]):
      check xs.len < 2
    delEnv("PROPTEST_DB")
    text.add "## failure database file\n"
    for f in walkFiles(dir / "db" / "*.txt"):
      text.add "  " & extractFilename(f) & "\n"
      for line in readFile(f).strip.splitLines: text.add "  | " & line & "\n"
    removeDir(dir)

  text

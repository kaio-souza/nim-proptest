## Derived generators (ADR-0013): objects, case objects, distinct, ref and
## recursive types; standard containers; frequency, recursive; alphabets.

import std/[unittest, strutils, unicode, sequtils]
import proptest
import helpers
import fixtures/f_types

type
  Point = object
    x, y: int
  Id = distinct int
  Node = ref object
    val: int
    left, right: Node
  Tree = object
    label: char
    kids: seq[Tree]
  Inventory = object
    items: Table[string, int]
    tags: HashSet[string]
    order: OrderedTable[int, bool]
  Money = object
    cents: int
    currency: string

proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money =
  ## A user overload: always wins over derivation.
  Money(cents: src.drawInt(0, 100), currency: "EUR")

proc depth(n: Node): int =
  if n.isNil: 0 else: 1 + max(depth(n.left), depth(n.right))

proc size(t: Tree): int =
  result = 1
  for k in t.kids: result += size(k)

proc input(r: PropertyResult): string = r.failures[0].inputs[0].value

suite "derived generators (G4)":
  test "G4: plain objects are generated with no code":
    var nonZero = 0
    forAll(initSettings(seed = 1), p in Point):
      if p.x != 0: inc nonZero
    check nonZero > 50

  test "G4: private fields of a type from another module are generated":
    var owners, positive = 0
    forAll(initSettings(seed = 2), a in Account):
      if a.cents > 0: inc positive
    check positive > 20

  test "G4: case objects reach every branch, with the branch's fields":
    var kinds: set[Kind]
    forAll(initSettings(seed = 3), s in Shape):
      kinds.incl s.kind
      check s.sides.len == (case s.kind
                            of circle: 1
                            of rect: 2
                            of tri: 3)
    check kinds == {circle, rect, tri}

  test "V-G4: a bug in one branch shrinks to that branch with the simplest fields":
    let r = forAllResult(initSettings(seed = 4), s in Shape):
      check not (s.kind == tri and s.sides[2] > 100)
    check r.status == psFailed
    check r.input == "(name: \"\", kind: tri, a: 0, b: 0, c: 101)"

  test "G4: distinct types are generated from their base type":
    var seen = 0
    forAll(initSettings(seed = 5), i in Id):
      if int(i) != 0: inc seen
    check seen > 50
    let r = forAllResult(initSettings(seed = 5), i in Id):
      check int(i) < 10
    check r.input == "Id(10)"

  test "G4: a user overload of arbitrary wins over derivation":
    forAll(initSettings(seed = 6), m in Money):
      check m.currency == "EUR"
      check m.cents in 0 .. 100

  test "G4: a field with no generator is a clear compile error":
    let (log, ok) = compileFixture("f_badderive")
    check not ok
    check "proptest cannot generate field 'callback' of Handler" in log

  test "G4: a range discriminant is a clear compile error (Nim 2.2.4 limit)":
    let (log, ok) = compileFixture("f_badrange")
    check not ok
    check "its discriminant 'kind' is a range type" in log

  test "G5: ref objects include nil, and recursive types stay bounded":
    var nils, maxDepth = 0
    forAll(initSettings(seed = 7, cases = 300), n in Node):
      if n.isNil: inc nils
      maxDepth = max(maxDepth, depth(n))
    check nils > 10
    check maxDepth in 2 .. defaultMaxDepth + 1
    var biggest = 0
    forAll(initSettings(seed = 8, cases = 300), t in Tree):
      biggest = max(biggest, size(t))
    check biggest > 3
    check biggest < 3000

  test "V-G5: a tree bug shrinks to the smallest tree":
    let r = forAllResult(initSettings(seed = 9), n in Node):
      check depth(n) < 3
    check r.status == psFailed
    # Shortlex: a nil `left` comes before a non-nil one, so the chain leans right.
    check r.input == "Node(val: 0, left: nil, right: Node(val: 0, left: nil, " &
                     "right: Node(val: 0, left: nil, right: nil)))"

  test "G5: maxDepth bounds recursion while exploring":
    var deepest = 0
    forAll(initSettings(seed = 10, cases = 300, maxDepth = 2), n in Node):
      deepest = max(deepest, depth(n))
    check deepest <= 3
    expect ValueError:
      validate(initSettings(maxDepth = -1))

suite "containers and combinators (G5, C3, C4)":
  test "G5: Table, OrderedTable and HashSet are generated and shrink":
    var nonEmpty = 0
    forAll(initSettings(seed = 11), inv in Inventory):
      if inv.items.len > 0 and inv.tags.len > 0 and inv.order.len > 0: inc nonEmpty
    check nonEmpty > 20
    let r = forAllResult(initSettings(seed = 12), t in Table[int, string]):
      check 7 notin t
    check r.input == "{7: \"\"}"

  test "G5: tables and hashSets combinators":
    forAll(initSettings(seed = 13), t in tables(ints(0, 9), bools(), maxLen = 5),
           s in hashSets(ints(0, 3))):
      check t.len <= 5
      for k in t.keys: check k in 0 .. 9
      for v in s: check v in 0 .. 3

  test "G5/M4: showCode prints containers and objects as Nim code":
    check showCode({1: "a"}.toTable) == "{1: \"a\"}.toTable"
    check showCode(initTable[int, string]()) == "initTable[int, string]()"
    check showCode(["x"].toHashSet) == "[\"x\"].toHashSet"
    check showCode(initHashSet[int]()) == "initHashSet[int]()"
    check showCode(Point(x: 1, y: -2)) == "Point(x: 1, y: -2)"
    check showCode(Id(3)) == "Id(3)"
    check showCode(Node(val: 1)) == "Node(val: 1, left: nil, right: nil)"
    check showCode(Node(nil)) == "nil"

  test "C3: frequency follows the weights and shrinks to the first entry":
    var counts: array[2, int]
    forAll(initSettings(seed = 14, cases = 1000),
           x in frequency([(9, constant(0)), (1, constant(1))])):
      inc counts[x]
    check counts[0] > 800 and counts[1] > 30
    let r = forAllResult(initSettings(seed = 15),
                         x in frequency([(1, ints(0, 10)), (5, ints(100, 200))])):
      check x < 150
    check r.input == "150"
    expect ValueError:
      discard frequency([(0, constant(1))])

  test "C4: recursive builds bounded trees that shrink to the base case":
    let leaf = ints(0, 9).map(proc(x: int): Tree = Tree(label: char(ord('0') + x)))
    let trees = recursive(leaf, proc(inner: Gen[Tree]): Gen[Tree] =
      seqs(inner, 1, 4).map(proc(ks: seq[Tree]): Tree = Tree(label: 'n', kids: ks)), maxDepth = 4)
    var deepest = 0
    proc treeDepth(t: Tree): int =
      result = 1
      for k in t.kids: result = max(result, 1 + treeDepth(k))
    forAll(initSettings(seed = 16, cases = 300), t in trees):
      deepest = max(deepest, treeDepth(t))
    check deepest in 3 .. 5
    let r = forAllResult(initSettings(seed = 17), t in trees):
      check t.kids.len == 0
    check r.input == "(label: 'n', kids: @[(label: '0', kids: @[])])"

suite "string alphabets (G6)":
  test "G6: alphanumeric and identifiers":
    forAll(initSettings(seed = 18), s in strings(alphanumeric, 1, 8), id in identifiers()):
      check s.allCharsInSet(Letters + Digits)
      check id.len >= 1 and id[0] in Letters
      check id.allCharsInSet(Letters + Digits)
    let r = forAllResult(initSettings(seed = 19), id in identifiers()):
      check id.len < 3
    check r.input == "\"aaa\""

  test "G6: unicodeStrings are valid UTF-8 and reach every plane":
    var astral, bmp, control = 0
    forAll(initSettings(seed = 20, cases = 300), s in unicodeStrings()):
      check validateUtf8(s) == -1
      for r in s.runes:
        if int(r) >= 0x10000: inc astral
        elif int(r) >= 0x80: inc bmp
        elif int(r) < 0x20: inc control
    check astral > 0 and bmp > 0 and control > 0

  test "V-G6: a non-ASCII bug shrinks to the simplest non-ASCII code point":
    let r = forAllResult(initSettings(seed = 21), s in unicodeStrings()):
      check s.allIt(ord(it) < 128)
    check r.status == psFailed
    check r.input == "\"\\xC2\\x80\""          # U+0080, as Nim escapes it

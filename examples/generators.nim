## Writing generators (docs/GENERATORS.md): every snippet of the guide.
## All properties pass; CI compiles and runs this file.

import proptest, std/[unittest, strutils, algorithm, sets]

# --- 1. Nothing to write: derived generators ------------------------------------

type
  Currency = enum usd, eur, brl
  Payment = object
    id: int64
    amount: int            # cents
    currency: Currency
    note: string
  EventKind = enum paid, refunded, cancelled
  Event = object
    at: int
    case kind: EventKind
    of paid: payment: Payment
    of refunded: refundOf: int64
    of cancelled: reason: string
  Expr = ref object        # recursive: bounded automatically
    case op: char
    of '+', '*': lhs, rhs: Expr
    else: value: int

# --- 2. When random fields make invalid objects: write `arbitrary` ------------

type DateRange = object
  first, last: int         # days; invariant: first <= last

proc arbitrary(src: ChoiceSource; t: typedesc[DateRange]): DateRange =
  ## Build valid values directly; no `filter`. Simpler choices still mean
  ## simpler values: an empty range at day 0.
  let first = src.drawInt(0, 36_500)
  let length = src.drawInt(0, 365)
  DateRange(first: first, last: first + length)

# --- 3. Generator values: combinators ------------------------------------------

let prices = frequency([(8, ints(1, 10_000)), (1, constant(0)), (1, ints(1_000_000, 10_000_000))])
let usernames = identifiers(maxLen = 12)
let labels = tables(identifiers(8), ints(0, 99), maxLen = 5)

proc leaf(): Gen[Expr] =
  ints(0, 9).map(proc(v: int): Expr = Expr(op: 'n', value: v))

let exprs = recursive(leaf(), proc(inner: Gen[Expr]): Gen[Expr] =
  newGen(proc(src: ChoiceSource): Expr =
    let times = src.drawBool()           # false ('+') is the simpler one
    let (l, r) = (inner.generate(src), inner.generate(src))
    if times: Expr(op: '*', lhs: l, rhs: r) else: Expr(op: '+', lhs: l, rhs: r)))

proc eval(e: Expr): int =
  case e.op
  of '+': eval(e.lhs) + eval(e.rhs)
  of '*': eval(e.lhs) * eval(e.rhs)
  else: e.value

suite "writing generators":
  test "derived objects and case objects":
    forAll(p in Payment, e in Event):
      check p.currency in {usd, eur, brl}
      check e.kind in {paid, refunded, cancelled}

  test "recursive types are bounded":
    forAll(e in Expr):
      discard e                       # nil is a valid Expr too

  test "a hand-written arbitrary keeps an invariant":
    forAll(r in DateRange):
      check r.first <= r.last

  test "combinators":
    forAll(price in prices, user in usernames, l in labels):
      check price >= 0
      check user[0] in Letters
      check l.len <= 5

  test "recursive generators":
    forAll(e in exprs):
      check eval(e) >= 0

  test "distinct and sorted collections":
    forAll(ids in uniqueSeqs(ints(1, 10_000), maxLen = 20)):   # no duplicates
      check ids.toHashSet.len == ids.len
    forAll(xs in sortedSeqs(ints(), minLen = 1)):              # ascending
      check lowerBound(xs, xs[0]) == 0

  test "the size: sized and resize":
    let matrices = sized(proc(n: int): Gen[seq[seq[int]]] =
      let side = max(1, n div 10)
      seqs(seqs(ints(0, 9), side, side), side, side))
    let shortLists = gen(seq[int]).resize(3)
    forAll(m in matrices, l in shortLists):
      check m.len == m[0].len
      check l.len <= 10

  test "explicit examples run first":
    forAll(user in usernames, example("root"), example("a")):
      check user.len >= 1

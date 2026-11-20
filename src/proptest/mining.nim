## Constants mined from the test's source file (ADR-0012, experiment).
##
## Bugs sit at the boundaries of a domain: a timeout of 1000 ms, a capacity
## of 3, a threshold of 100. Those numbers are usually written somewhere in
## the test file, in a constant, a configuration or a helper. At compile
## time, `forAll` and `stateMachine` read the file that calls them and keep
## its integer literals. While exploring, integer draws then propose
## `v - 1`, `v` and `v + 1` now and then, when they fit the range
## (`drawInt`). Shrinking is unchanged. Turn off with
## `initSettings(mineConstants = false)`.

import std/[macros, strutils, tables]

const maxMined = 64

var minedCache {.compileTime.}: Table[string, seq[int64]]

proc scanIntegers(text: string): seq[int64] {.compileTime.} =
  ## Decimal and hexadecimal integer literals, with `_` separators and
  ## optional type suffixes; floats and digits inside identifiers are
  ## skipped. 0, 1 and -1 are left out: edge cases already cover them.
  var i = 0
  var counts: OrderedTable[int64, int]
  while i < text.len:
    let c = text[i]
    if c == '#':                       # skip comments to the end of line
      while i < text.len and text[i] != '\n': inc i
      continue
    if c == '"':                       # skip string literals
      inc i
      while i < text.len and text[i] != '"' and text[i] != '\n':
        if text[i] == '\\': inc i
        inc i
      inc i
      continue
    if c in Digits and (i == 0 or text[i - 1] notin IdentChars + {'.'}):
      let negative = i > 0 and text[i - 1] == '-' and
                     (i < 2 or text[i - 2] in Whitespace + {'(', '[', ',', '='})
      var j = i
      var value: int64
      var ok = true
      if c == '0' and j + 1 < text.len and text[j + 1] in {'x', 'X'}:
        j += 2
        var digits = ""
        while j < text.len and text[j] in HexDigits + {'_'}:
          if text[j] != '_': digits.add text[j]
          inc j
        try: value = int64(parseHexInt(digits)) except ValueError: ok = false
      else:
        var digits = ""
        while j < text.len and text[j] in Digits + {'_'}:
          if text[j] != '_': digits.add text[j]
          inc j
        if j + 1 < text.len and text[j] == '.' and text[j + 1] in Digits: ok = false   # float
        if j < text.len and text[j] in {'e', 'E'}: ok = false
        if ok:
          try: value = parseBiggestInt(digits) except ValueError: ok = false
      if j < text.len and text[j] == '\'':   # type suffix: 'i64, 'u8...
        inc j
        while j < text.len and text[j] in IdentChars: inc j
      if ok:
        if negative: value = -value
        if value notin [0'i64, 1, -1]:
          counts.mgetOrPut(value, 0).inc
      i = j
      continue
    inc i
  # The most frequent literals first: they are the domain's constants.
  var pairs: seq[(int, int64)]
  for v, n in counts: pairs.add (n, v)
  for a in 1 ..< pairs.len:          # insertion sort, stable, compile time
    var b = a
    while b > 0 and pairs[b - 1][0] < pairs[b][0]:
      swap(pairs[b - 1], pairs[b])
      dec b
  for k in 0 ..< min(pairs.len, maxMined):
    result.add pairs[k][1]

proc minedHints*(callSite: NimNode): NimNode {.compileTime.} =
  ## An array literal of the integers found in the file of `callSite`.
  let file = callSite.lineInfoObj.filename
  if file notin minedCache:
    var found: seq[int64]
    try:
      found = scanIntegers(staticRead(file))
    except CatchableError:
      discard
    minedCache[file] = found
  result = nnkBracket.newTree()
  for v in minedCache[file]:
    result.add newLit(v)
  if result.len == 0:
    result = newCall(ident"default", nnkBracketExpr.newTree(ident"array", newLit(0), ident"int64"))

proc bodyHints*(body, acc: NimNode): NimNode {.compileTime.} =
  ## Statements that declare `acc` and collect into it the
  ## integer literals and compile-time constants (`const openFor = 1000`)
  ## used in `body`. They rank before the file's literals: the property
  ## itself names the boundaries that matter most.
  var lits: seq[int64]
  var names: seq[string]
  proc walk(n: NimNode) =
    case n.kind
    of nnkIntLit .. nnkInt64Lit:
      let v = n.intVal
      if v notin [0'i64, 1, -1] and v notin lits: lits.add v
    of nnkIdent:
      if $n notin names and names.len < 32: names.add $n
    of nnkDotExpr:
      walk(n[0])            # `model.x`: only the root can be a constant
    else:
      for c in n: walk(c)
  walk(body)
  result = newStmtList(quote do:
    var `acc` {.used.}: seq[int64])
  for v in lits:
    result.add newCall(newDotExpr(acc, ident"add"), newLit(v))
  for name in names:
    let id = ident(name)
    # Only integer constants: checking the type first, because evaluating
    # `int64(x)` at compile time crashes Nim 2.2.4 for some constants (a
    # `set[char]` such as `Letters`) instead of failing `compiles`.
    result.add quote do:
      when compiles(typeof(`id`)):
        when typeof(`id`) isnot typedesc and typeof(`id`) is SomeInteger:
          when compiles(static(`id`)):
            when int64(static(`id`)) notin [0'i64, 1, -1]:
              `acc`.add int64(static(`id`))

## `classify`, `cover` and `label` (D1, D2, ADR-0012).
##
## Inside `forAll` and the commands of a `stateMachine`, the macros rewrite
## these calls: each call site gets a slot fixed at compile time, so a label
## with a literal name costs one counter update per case and no allocation
## (PF10). Counts are kept only while exploring, not while shrinking, and
## discarded cases are not counted.

import std/macros
import choices

template classify*(cond: bool; name: string) =
  ## Counts the cases where `cond` holds under `name`; the report shows the
  ## percentage. Valid inside `forAll` and `stateMachine` commands.
  {.error: "classify is only valid inside forAll or a stateMachine".}

template cover*(percent: float; cond: bool; name: string) =
  ## Like `classify`, and the property fails when `cond` held in fewer than
  ## `percent` % of the cases, with statistical confidence (D2). In a state
  ## machine a sequence counts once if any of its steps meets `cond`.
  {.error: "cover is only valid inside forAll or a stateMachine".}

template label*(text: string) =
  ## Counts cases by a computed text, e.g. `label($shape.kind)`.
  {.error: "label is only valid inside forAll or a stateMachine".}

const nestedMacros = ["forAll", "forAllResult", "stateMachine"]

proc rewriteLabels*(n, src: NimNode; nextSlot: var int): NimNode =
  ## Replaces `classify`/`cover`/`label` calls in `n` with counting calls on
  ## `src`, giving each call site the next free slot. Nested properties are
  ## left alone: their own macro rewrites them.
  if n.kind in {nnkCall, nnkCommand} and n.len >= 1 and n[0].kind == nnkIdent:
    let callee = n[0]
    for m in nestedMacros:
      if callee.eqIdent(m): return n
    if callee.eqIdent("classify") and n.len == 3:
      result = newCall(bindSym"recordLabel", src, newLit(nextSlot),
        rewriteLabels(n[1], src, nextSlot), n[2], bindSym"lkClassify")
      inc nextSlot
      return
    if callee.eqIdent("cover") and n.len == 4:
      result = newCall(bindSym"recordLabel", src, newLit(nextSlot),
        rewriteLabels(n[2], src, nextSlot), n[3], bindSym"lkCover",
        newCall(ident"float", n[1]))
      inc nextSlot
      return
    if callee.eqIdent("label") and n.len == 2:
      return newCall(bindSym"recordDynamic", src, rewriteLabels(n[1], src, nextSlot))
  result = n
  for i in 0 ..< n.len:
    result[i] = rewriteLabels(n[i], src, nextSlot)

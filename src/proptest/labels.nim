## `classify`, `cover`, `label` (D1, D2, ADR-0012) and `target` (targeted
## exploration, ADR-0016).
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

template target*(score: float; name = "") =
  ## Targeted exploration: tells the engine to look for cases with a higher
  ## `score` (e.g. `target(float(model.level), "reopenings")`). After half of
  ## the cases, every other case starts from a prefix of the best case so far
  ## and explores from there, climbing toward high scores: deep states that
  ## random cases rarely reach. The report shows the best score per name.
  ## Valid inside `forAll` and `stateMachine` commands and invariants.
  {.error: "target is only valid inside forAll or a stateMachine".}

const nestedMacros = ["forAll", "forAllResult", "stateMachine"]

proc calleeIs(callee: NimNode; name: string): bool =
  ## `callee` names `name`: an identifier, or a symbol when the call comes
  ## from a template (which binds `classify`, `target`... to these templates).
  case callee.kind
  of nnkIdent, nnkSym: callee.eqIdent(name)
  of nnkOpenSymChoice, nnkClosedSymChoice: callee.len > 0 and callee[0].eqIdent(name)
  else: false

proc rewriteLabels*(n, src: NimNode; nextSlot: var int): NimNode =
  ## Replaces `classify`/`cover`/`label` calls in `n` with counting calls on
  ## `src`, giving each call site the next free slot. Nested properties are
  ## left alone: their own macro rewrites them.
  if n.kind in {nnkCall, nnkCommand} and n.len >= 1 and
     n[0].kind in {nnkIdent, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice}:
    let callee = n[0]
    for m in nestedMacros:
      if callee.calleeIs(m): return n
    if callee.calleeIs("classify") and n.len == 3:
      result = newCall(bindSym"recordLabel", src, newLit(nextSlot),
        rewriteLabels(n[1], src, nextSlot), n[2], bindSym"lkClassify")
      inc nextSlot
      return
    if callee.calleeIs("cover") and n.len == 4:
      result = newCall(bindSym"recordLabel", src, newLit(nextSlot),
        rewriteLabels(n[2], src, nextSlot), n[3], bindSym"lkCover",
        newCall(ident"float", n[1]))
      inc nextSlot
      return
    if callee.calleeIs("label") and n.len == 2:
      return newCall(bindSym"recordDynamic", src, rewriteLabels(n[1], src, nextSlot))
    if callee.calleeIs("target") and n.len in 2 .. 3:
      return newCall(bindSym"recordTarget", src,
        newCall(ident"float", rewriteLabels(n[1], src, nextSlot)),
        (if n.len == 3: n[2] else: newLit("")))
  # A new tree, never `n` itself: callers rewrite the same body more than
  # once (examples) and read the original afterwards (database key, hints).
  result = copyNimNode(n)
  for c in n:
    result.add rewriteLabels(c, src, nextSlot)

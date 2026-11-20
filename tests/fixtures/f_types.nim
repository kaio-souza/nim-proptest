## Fixture: types of another module, with private fields (G4). Only the
## type names are exported, as is common in test helpers and libraries.

type
  Kind* = enum circle, rect, tri
  Shape* = object
    name: string
    case kind: Kind
    of circle: r: int
    of rect: w, h: int
    of tri: a, b, c: uint8
  Account* = object
    owner: string
    cents: int64

proc kind*(s: Shape): Kind = s.kind
proc sides*(s: Shape): seq[int] =
  case s.kind
  of circle: @[s.r]
  of rect: @[s.w, s.h]
  of tri: @[int(s.a), int(s.b), int(s.c)]
proc cents*(a: Account): int64 = a.cents

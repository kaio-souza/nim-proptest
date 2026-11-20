# ADR-0013: Derived generators for objects, refs and recursive types

- Status: Accepted (implemented in v0.4)
- Date: 2026-11-20
- Requirements: G4, G5, G6, C3, C4, PF9, DOC2

## Context

Most Nim data are `object`s. Until v0.3, `forAll(m in Money)` required a hand-written `arbitrary` for every type: the main reason a new user could not just try the library. The same holds for case objects, `distinct` types, `ref` objects, recursive types (trees, ASTs) and the standard containers (`Table`, `HashSet`).

Constraints: no closure on the type-inferred path (ADR-0007); a smaller choice must give a simpler value (ADR-0001); v0.4 must not change the values of existing generators for a given seed (stability, ROADMAP); most test types do not export their fields.

## Decision

### 1. Automatic, generic, through `fieldPairs`

A generic overload `arbitrary[T: object](src, T)` fills `result` field by field with `fieldPairs`, so nothing has to be written or called. A spike confirmed what makes this possible in Nim 2.2.4:

- `fieldPairs` reaches **private fields** of a type declared in another module, so test types need not export anything;
- on a **case object**, a discriminant can be assigned inside the loop with `{.cast(uncheckedAssign).}`, and the fields of the chosen branch are visited after it. The discriminant names come from a small typed macro over `getTypeImpl`.

A user overload (`proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money`) is non-generic and always wins. A field whose type has no generator stops compilation with a message that names the field and says to overload `arbitrary` for its type.

- `distinct` types: `T(arbitrary(distinctBase(T)))`.
- `ref` objects: `nil` or a new object; `nil` is the simplest value (choice 0), so shrinking moves toward `nil` and the report shows where `nil` is enough to fail. Nil references are also an edge case worth testing.

### 2. Recursion: a depth counter on the choice source

Recursive types (`ref Node` fields, `seq[Node]` children) would grow without bound. The choice source keeps a nesting depth, raised while a derived object (or a `recursive` level) is generated. While exploring:

- the chance of a non-nil `ref` falls with depth, and is 0 at `maxDepth` (setting, default 5);
- the typical length of collections is divided by `depth + 1`, and is the minimum at `maxDepth`.

Only exploration proposals change. Replay reads choices as before, so shrinking is unaffected, and at depth 0 nothing changes: existing generators produce the same values for a seed.

### 3. Combinators and containers

- `frequency([(3, a), (1, b)])`: weighted choice; shrinks toward the first entry.
- `recursive(base, extend, maxDepth)`: `extend` builds one level from the generator of the level below; each level chooses between `base` (choice 0, simpler) and going deeper.
- `Table`, `OrderedTable`, `HashSet` from their element types, and `tables`, `hashSets` combinators; `showCode` prints them as `toTable`/`toHashSet` literals for stateful reports.
- String alphabets: `alphanumeric`, `identifiers(...)`, and `unicodeStrings(...)` (valid UTF-8). Code points are ordered printable ASCII first, then control characters, then the rest without surrogates, so they shrink toward `'a'`.

## Consequences

- `forAll(s in Shape)` works for any object, case object, `distinct` or `ref` object made of supported types, with no code.
- A generic overload for every `object` could capture types that need a hand-written generator (invariants between fields). The user overload still wins, and DOC2 says when to write one: when random field values make invalid objects.
- Derivation is instantiated per type at compile time: PF9 measures it.

## Evidence

Tests per requirement (`tests/t_derive.nim`): plain, private, case (every branch reached), `distinct`, `ref` (nil reached), recursive types bounded, user overload wins, clear error for an unsupported field; value tests: a bug in one branch of a case object shrinks to that branch with simplest fields; a tree bug shrinks to the smallest tree. Golden values of existing generators unchanged. PF9 benchmark: compile time of 50 properties over derived types.

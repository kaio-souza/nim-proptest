# ADR-0005: Own PRNG and stable hashing

- Status: Proposed
- Date: 2026-11-19
- Requirements: RL1, RL2, RL15, R1, R2, R5, Q3, Q7

## Context

A printed seed is a promise: "run this again and you will see the same failure". The standard library cannot keep that promise across environments:

- `std/random` does not guarantee the same stream across Nim versions, and its API mixes platform-sized `int` into results.
- `std/hashes` is explicitly allowed to change between versions and differs between backends; using it to derive per-property seeds or failure database keys would silently change every case after a compiler upgrade.
- A seed shared in a bug report must replay on another developer's OS, on 32-bit targets and on the JS backend.

## Decision

- The library ships its own PRNG, implemented with fixed-width `uint64` arithmetic only:
  - **SplitMix64** to derive independent streams (run seed + property key → property seed);
  - **xoshiro256\*\*** as the stream generator.
- Choices are always `uint64`. Conversions to bounded integers use a documented, platform-independent method (no `mod` bias; no platform `int` in the stream). Floats are built from bits with a fixed recipe.
- Property keys are hashed with a library-owned, versioned hash (FNV-1a 64-bit over the property's full name).
- The algorithms are part of the stability policy (RL15): changing them is a breaking change, announced in the CHANGELOG.
- Golden tests (Q7) commit the expected streams and values for fixed seeds and run on every CI platform and backend. On the JS backend, 64-bit arithmetic must be verified explicitly (BigInt-backed `int64`/`uint64`).

## Consequences

- Seeds replay identically across compiler upgrades, operating systems and backends.
- The PRNG is not cryptographic, which is fine for testing.
- A few dozen lines of arithmetic to maintain, fully covered by golden tests.

## Evidence

Golden tests on all CI platforms and the JS backend; RL1 value test.

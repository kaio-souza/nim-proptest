# Package

version       = "0.1.0"
author        = "Kaio Souza"
description   = "Property-based testing for Nim: generators from types, integrated shrinking and stateful testing, with reproducible failures."
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tests", "benchmarks", "examples", "docs", "scripts"]
# 0.1.0 is unreleased: see CHANGELOG.md and docs/ROADMAP.md.

# Dependencies (ADR-0002: standard library only)

requires "nim >= 2.2.4"

# Tasks (`nimble test` runs every tests/t_*.nim)

const benchFlags = "nim c -r --hints:off --warnings:off -d:release --opt:speed "

task bench, "Run the benchmarks (timings are informational)":
  exec benchFlags & "--mm:orc benchmarks/b_gen.nim"
  exec benchFlags & "--mm:arc -d:nimAllocStats benchmarks/b_gen.nim"
  exec benchFlags & "benchmarks/b_shrink.nim"

task gate, "Deterministic performance gates: shrink executions and allocations (ADR-0008)":
  exec benchFlags & "benchmarks/b_shrink.nim --check"
  # ARC: Nim 2.2.4 crashes with ORC + nimAllocStats when re-raising.
  exec benchFlags & "--mm:arc -d:nimAllocStats benchmarks/b_gen.nim --check"

task trace, "Check the traceability matrix (ADR-0004)":
  exec "nim r --hints:off scripts/check_traceability.nim"

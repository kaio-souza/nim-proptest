# Package

version       = "1.0.0"
author        = "Kaio Souza"
description   = "Property-based testing for Nim: generators from types, integrated shrinking and stateful testing, with reproducible failures."
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tests", "benchmarks", "examples", "docs", "scripts"]

# Dependencies (ADR-0002: standard library only)

requires "nim >= 2.2.4"

# Tasks (`nimble test` runs every tests/t_*.nim)

const benchFlags = "nim c -r --hints:off --warnings:off -d:release --opt:speed -d:proptestDb=off "

task bench, "Run the benchmarks (timings are informational)":
  exec benchFlags & "--mm:orc benchmarks/b_gen.nim"
  exec benchFlags & "--mm:arc -d:nimAllocStats benchmarks/b_gen.nim"
  exec benchFlags & "benchmarks/b_shrink.nim"
  exec benchFlags & "benchmarks/b_find.nim"
  exec "nim c -r --hints:off --warnings:off benchmarks/b_compile.nim --check"

task gate, "Deterministic gates: shrink executions, allocations, bug detection (ADR-0008, ADR-0012)":
  exec benchFlags & "benchmarks/b_shrink.nim --check"
  exec benchFlags & "benchmarks/b_find.nim --check"
  # ARC: Nim 2.2.4 crashes with ORC + nimAllocStats when re-raising.
  exec benchFlags & "--mm:arc -d:nimAllocStats benchmarks/b_gen.nim --check"

task golden, "Rewrite the golden snapshot: only for an intended generation change (docs/STABILITY.md)":
  exec "nim r --hints:off --path:src -d:proptestDb=off -d:proptestTraceWarning=false scripts/update_golden.nim"

task trace, "Check the traceability matrix (ADR-0004) and that the docs match the code":
  exec "nim r --hints:off scripts/check_traceability.nim"
  exec "nim r --hints:off scripts/check_docs.nim"

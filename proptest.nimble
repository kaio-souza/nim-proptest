# Package

version       = "0.0.0"
author        = "Kaio Souza"
description   = "Property-based testing for Nim: generators from types, integrated shrinking and stateful testing, with reproducible failures."
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tests", "benchmarks", "examples", "docs"]
# Status: design phase. Version 0.1.0 is the first release with code (docs/ROADMAP.md).

# Dependencies (ADR-0002: standard library only)

requires "nim >= 2.2.4"

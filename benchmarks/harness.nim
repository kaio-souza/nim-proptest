## Minimal benchmark harness (PF1): warm-up, 30 samples, median/p95/p99,
## allocations per operation (compile with -d:nimAllocStats and --mm:arc:
## Nim 2.2.4 crashes with ORC + nimAllocStats on re-raise), and optional
## JSON output when the BENCH_JSON_DIR environment variable is set.

import std/[monotimes, times, algorithm, strformat, strutils, os, json]

type BenchResult* = object
  name*: string
  medianNs*, p95Ns*, p99Ns*, minNs*: float
  allocsPerOp*: float

var results*: seq[BenchResult]
var keep* {.volatile.}: int  ## Write results here so the compiler keeps the work.

const samples = 30

proc allocCount*(): int =
  ## Number of allocations so far (0 without -d:nimAllocStats).
  let s = $getAllocStats()           # "(allocCount: N, deallocCount: M)"
  let i = s.find("allocCount: ")
  if i < 0: return 0
  var j = i + "allocCount: ".len
  while j < s.len and s[j].isDigit:
    result = result * 10 + (ord(s[j]) - ord('0'))
    inc j

proc percentile(xs: seq[float]; p: float): float =
  xs[min(xs.high, int(p * xs.len.float))]

proc addResult*(r: BenchResult) =
  results.add r
  let allocs = if r.allocsPerOp < 0: "n/a" else: &"{r.allocsPerOp:.2f}"
  echo &"{r.name:<52} {r.medianNs:>9.1f} {r.p95Ns:>9.1f} {r.p99Ns:>9.1f} {allocs:>9}"

proc measurementAllocs(): int =
  ## Allocations made by `allocCount` itself (it builds a string), so they
  ## can be subtracted from every measurement.
  let a = allocCount()
  let b = allocCount()
  b - a

let allocOverhead* = measurementAllocs()

template bench*(label: string; opsPerSample: int; body: untyped) =
  block:
    for _ in 0 ..< opsPerSample: body          # warm-up
    var times = newSeqOfCap[float](samples)
    let a0 = allocCount()
    for _ in 0 ..< samples:
      let t0 = getMonoTime()
      for _ in 0 ..< opsPerSample: body
      times.add (getMonoTime() - t0).inNanoseconds.float / opsPerSample.float
    let allocs = when defined(nimAllocStats):
        max(0, allocCount() - a0 - allocOverhead).float / float(samples * opsPerSample)
      else: -1.0
    times.sort()
    let r = BenchResult(name: label, medianNs: percentile(times, 0.5),
      p95Ns: percentile(times, 0.95), p99Ns: percentile(times, 0.99),
      minNs: times[0], allocsPerOp: allocs)
    addResult(r)

proc header*(title: string) =
  let mm = when defined(gcOrc): "orc" elif defined(gcArc): "arc" else: "other"
  let flags = (when compileOption("threads"): "threads:on" else: "threads:off") &
    (when defined(release): " release" else: " debug") &
    (when defined(nimAllocStats): "" else: " (no alloc stats)")
  echo &"\n## {title}  [nim {NimVersion}, mm:{mm}, {flags}]"
  echo &"""{"benchmark":<52} {"median":>9} {"p95":>9} {"p99":>9} {"allocs/op":>9}"""
  echo &"""{"":<52} {"ns/op":>9} {"ns/op":>9} {"ns/op":>9} {"":>9}"""

proc writeJson*(file: string) =
  let dir = getEnv("BENCH_JSON_DIR")
  if dir.len == 0: return
  createDir(dir)
  var arr = newJArray()
  for r in results: arr.add %*r
  writeFile(dir / file, $(%*{"nim": NimVersion, "results": arr}))

## Failure signatures (ADR-0006): two failures are "the same bug" when they
## have the same exception type and the same location in user code.

import std/[os, strutils, tables, compilesettings]
import assertions

type
  Signature* = object
    kind*: string      ## Exception type name.
    location*: string  ## `file:line` in user code, empty when unknown.

const
  nimLibDir = querySetting(libPath)
  ownSrcDir = currentSourcePath().parentDir.parentDir
  libSubdirs = ["system", "pure", "pure/collections", "std", "core", "impure", "deprecated/pure", ""]

var libFileCache {.threadvar.}: Table[string, bool]

proc isLibraryFile(filename: string): bool =
  ## True for frames from the Nim standard library or from proptest itself.
  if filename.isAbsolute:
    return filename.startsWith(nimLibDir) or filename.startsWith(ownSrcDir)
  # Without --excessiveStackTrace only the base name is known.
  if filename in libFileCache:
    return libFileCache[filename]
  result = fileExists(ownSrcDir / filename) or fileExists(ownSrcDir / "proptest" / filename)
  if not result:
    for d in libSubdirs:
      if fileExists(nimLibDir / d / filename):
        result = true
        break
  libFileCache[filename] = result

proc `==`*(a, b: Signature): bool =
  a.kind == b.kind and a.location == b.location

proc `$`*(s: Signature): string =
  if s.location.len > 0: s.kind & " at " & s.location else: s.kind

proc signatureOf*(e: ref Exception): Signature =
  ## Type of `e` plus the innermost stack frame in user code. Without stack
  ## traces, only the type: identity is weaker and the report says so.
  result.kind = $e.name
  if e of PropertyFailed:
    result.location = (ref PropertyFailed)(e).location
    return
  when compileOption("stackTrace"):
    let entries = e.getStackTraceEntries()
    for i in countdown(entries.high, 0):
      let f = $entries[i].filename
      if f.len > 0 and not isLibraryFile(f):
        result.location = extractFilename(f) & ":" & $entries[i].line
        return

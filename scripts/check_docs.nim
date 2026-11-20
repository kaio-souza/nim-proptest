## Keeps the documentation in step with the code (DOC5, DOC6). Exit code 1
## lists every problem found.
##
## - Every `Settings` field, `PROPTEST_*` environment variable and
##   `-d:` define of the library appears in docs/CONFIGURATION.md.
## - Every link to a heading (`#anchor`, `FILE.md#anchor`) in README.md and
##   docs/*.md points to a heading that exists, using GitHub's anchor rules.

import std/[os, strutils, sets]

let root = currentSourcePath().parentDir.parentDir
var problems: seq[string]
var nFields, nLinks: int

# ------------------------------------------------- configuration reference

let config = readFile(root / "docs" / "CONFIGURATION.md")

proc documented(name: string): bool = ("`" & name & "`") in config or
  ("`" & name & " ") in config or ("`" & name & "=") in config

var src = ""
for f in walkDirRec(root / "src"):
  if f.endsWith(".nim"): src.add readFile(f) & "\n"

# Settings fields: the lines of `Settings* = object` up to the first blank line.
let engine = readFile(root / "src" / "proptest" / "engine.nim")
let start = engine.find("Settings* = object")
if start < 0: problems.add "engine.nim: `Settings* = object` not found"
else:
  var fields = 0
  for line in engine[start .. ^1].splitLines[1 .. ^1]:
    if line.strip.len == 0: break
    let t = line.strip
    let star = t.find("*:")
    if star > 0 and t[0 ..< star].allCharsInSet(IdentChars):
      inc fields
      let name = t[0 ..< star]
      if not documented(name):
        problems.add "setting `" & name & "` is not in docs/CONFIGURATION.md"
  if fields == 0: problems.add "engine.nim: no Settings fields found"
  nFields = fields

var envVars = initHashSet[string]()
var i = src.find("PROPTEST_")
while i >= 0:
  var j = i + "PROPTEST_".len
  while j < src.len and src[j] in {'A'..'Z', '_'}: inc j
  envVars.incl src[i ..< j]
  i = src.find("PROPTEST_", j)
for name in envVars:
  if not documented(name):
    problems.add "environment variable `" & name & "` is not in docs/CONFIGURATION.md"

for line in src.splitLines:
  let t = line.strip
  if t.startsWith("const ") and (".strdefine." in t or ".intdefine." in t or ".booldefine." in t):
    let name = t.split(' ')[1]
    if ("-d:" & name) notin config:
      problems.add "define `-d:" & name & "` is not in docs/CONFIGURATION.md"

# ----------------------------------------------------------- heading links

proc slug(heading: string): string =
  ## GitHub's anchor for a heading: lower case, punctuation dropped,
  ## spaces to hyphens (underscores and hyphens kept).
  for c in heading.toLowerAscii:
    if c in {'a'..'z', '0'..'9', '_', '-'}: result.add c
    elif c == ' ': result.add '-'
    elif ord(c) >= 0x80: result.add c

proc anchors(path: string): HashSet[string] =
  var inCode = false
  for line in lines(path):
    if line.startsWith("```"): inCode = not inCode
    if inCode or not line.startsWith("#"): continue
    result.incl slug(line.strip(chars = {'#'}).strip)

var docs = @[root / "README.md"]
for f in walkFiles(root / "docs" / "*.md"): docs.add f
for path in docs:
  let text = readFile(path)
  var k = text.find("](")
  while k >= 0:
    let close = text.find(')', k + 2)
    if close < 0: break
    let inner = text[k + 2 ..< close]
    k = text.find("](", close)
    let hash = inner.find('#')
    if hash < 0 or inner.startsWith("http") or ' ' in inner: continue
    let file = inner[0 ..< hash]
    let anchor = inner[hash + 1 .. ^1]
    inc nLinks
    let target = if file.len == 0: path else: path.parentDir / file
    if not fileExists(target):
      problems.add extractFilename(path) & ": link to missing file " & file
    elif anchor notin anchors(target):
      problems.add extractFilename(path) & ": no heading for #" & anchor &
        " in " & extractFilename(target)

if problems.len > 0:
  echo "Documentation check FAILED:"
  for p in problems: echo "  - ", p
  quit 1
echo "Documentation OK: ", nFields, " settings and ", envVars.len,
  " environment variables documented, ", nLinks, " heading links valid."

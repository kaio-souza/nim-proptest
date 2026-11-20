## JSON Lines output of the report (O3): string escaping and fields, shared
## by the engine and the watchdog (RL10).

from std/unicode import runeLenAt, validateUtf8
import std/[os, strutils]

const reportFormat* = 1
  ## Version of the JSON report; raised when a field changes meaning or goes away.

proc addJson*(o: var string; s: string) =
  ## `s` as a JSON string. Bytes that are not valid UTF-8 (a raw byte in an
  ## exception message) become `\u00XX`, so the line stays valid JSON.
  o.add '"'
  var i = 0
  while i < s.len:
    let c = s[i]
    case c
    of '"': o.add "\\\""
    of '\\': o.add "\\\\"
    of '\n': o.add "\\n"
    of '\r': o.add "\\r"
    of '\t': o.add "\\t"
    of '\0' .. '\x08', '\x0B', '\x0C', '\x0E' .. '\x1F', '\x7F':
      o.add "\\u00" & toHex(ord(c), 2)
    of ' ', '!', '#' .. '[', ']' .. '~':
      o.add c
    of '\x80' .. '\xFF':
      let size = runeLenAt(s, i)
      let chunk = s[i ..< min(s.len, i + size)]
      if chunk.len == size and validateUtf8(chunk) == -1:
        o.add chunk
        i += size
        continue
      o.add "\\u00" & toHex(ord(c), 2)
    inc i
  o.add '"'

proc addJson*(o: var string; key: string; value: string) =
  o.addJson(key)
  o.add ':'
  o.addJson(value)

proc addJson*(o: var string; key: string; value: int | bool | float) =
  o.addJson(key)
  o.add ':'
  o.add $value

proc addJson*(o: var string; key: string; values: seq[string]) =
  o.addJson(key)
  o.add ":["
  for i, v in values:
    if i > 0: o.add ','
    o.addJson(v)
  o.add ']'

proc appendJsonLine*(path, line: string) =
  ## Appends `line` and a newline to the JSON Lines file `path`, creating it
  ## and its directory. One write per line, so programs can share the file.
  try:
    let dir = parentDir(path)
    if dir.len > 0: createDir(dir)
    var f = open(path, fmAppend)
    try: f.write line & "\n"
    finally: f.close()
  except IOError, OSError:
    raise newException(IOError, "proptest: cannot write the report to '" & path &
      "' (PROPTEST_REPORT): " & getCurrentExceptionMsg())

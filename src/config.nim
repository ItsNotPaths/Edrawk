import std/[os, strutils]
import rawk_bufferlib
export LineNumberMode, CursorMode

type TabMode* = enum tmSpaces2, tmSpaces4, tmTab

var
  tabMode*: TabMode = tmSpaces4
  themePref*: string = "default"
  cursorJumpLines*: int = 10
  lineNumbers*: LineNumberMode = lnmGlobal
  cursorMode*: CursorMode = cmInsert
  fontSize*: uint32 = 14

proc indentString*(): string =
  case tabMode
  of tmSpaces2: "  "
  of tmSpaces4: "    "
  of tmTab:     "\t"

proc configDir*(): string = getConfigDir() / "edrawk"
proc configPath*(): string = configDir() / "config"

proc loadConfig*() =
  let path = configPath()
  if not fileExists(path): return
  for raw in lines(path):
    let line = raw.strip()
    if line.len == 0 or line.startsWith('#'): continue
    let colon = line.find(':')
    if colon <= 0: continue
    let key = line[0 ..< colon].strip()
    var rest = line[colon+1 .. ^1]
    let hash = rest.find('#')
    if hash >= 0: rest = rest[0 ..< hash]
    let val = rest.strip()
    case key
    of "tab_mode":
      case val
      of "spaces2": tabMode = tmSpaces2
      of "spaces4": tabMode = tmSpaces4
      of "tab":     tabMode = tmTab
      else: discard
    of "theme":
      if val.len > 0: themePref = val
    of "cursor_jump_lines":
      try:
        let n = parseInt(val)
        if n >= 1: cursorJumpLines = n
      except ValueError: discard
    of "line_numbers":
      case val
      of "off":      lineNumbers = lnmOff
      of "global":   lineNumbers = lnmGlobal
      of "relative": lineNumbers = lnmRelative
      else: discard
    of "cursor_mode":
      case val
      of "insert": cursorMode = cmInsert
      of "normal": cursorMode = cmNormal
      else: discard
    of "font_size":
      try:
        let n = parseInt(val)
        if n >= 6 and n <= 64: fontSize = uint32(n)
      except ValueError: discard
    else: discard

# ---------- persistence ----------

proc atomicWrite(path, body: string) =
  let tmp = path & ".tmp"
  writeFile(tmp, body)
  moveFile(tmp, path)

proc setConfigKey*(key, value: string) =
  ## Find/replace the `<key>:` line in the user's config (preserving
  ## leading whitespace), or append it if missing. Atomic via temp+rename
  ## so a crash mid-write can't truncate the file. Creates the file if
  ## it doesn't exist yet — handy for first-run theme switches before
  ## the user has touched `~/.config/edrawk/config` themselves.
  let path = configPath()
  createDir(configDir())
  var lines: seq[string] = @[]
  if fileExists(path):
    for l in lines(path): lines.add(l)
  var found = false
  let prefix = key & ":"
  for i in 0 ..< lines.len:
    let stripped = lines[i].strip(leading = true, trailing = false)
    if stripped.startsWith(prefix):
      let indent = lines[i][0 ..< lines[i].len - stripped.len]
      lines[i] = indent & key & ": " & value
      found = true
      break
  if not found:
    if lines.len > 0 and lines[^1].len > 0: lines.add("")
    lines.add(key & ": " & value)
  atomicWrite(path, lines.join("\n") & "\n")

## Hardwired single-line command line. Hidden by default. `openCl(prefill)`
## reveals it focused, with the buffer pre-loaded. Esc cancels, Enter
## dispatches to a fixed set of editor commands (open / save / close / quit).

import std/[os, strutils]
import rawk_luigi, rawk_bufferlib
import editor_ref, theme, config

const
  padX*: cint = 6
  padY*: cint = 3

type Cl* = object
  e*: Element
  buf*: string
  cursor*: int           # byte index into buf
  prevFocus*: ptr Element
  error*: string         # last dispatch error; cleared on next keystroke
  injected*: bool        # buffer was prefilled (not user-typed); border tints

var
  theCl*: ptr Cl
  clOnOpenCb*, clOnCloseCb*: proc() {.closure.}
    ## Layout hooks fired when the CL toggles visibility. Edrawk uses these
    ## to swap the menubar out of the way so the CL occupies its row
    ## instead of pushing the tab strip down. Callbacks should toggle
    ## ELEMENT_HIDE only; the CL itself handles the parent refresh.

# ---------- height / visibility ----------

proc clHeight*(): cint =
  let (_, gH) = glyphDims()
  gH + 2 * padY

proc isOpen*(c: ptr Cl): bool =
  c != nil and (c.e.flags and ELEMENT_HIDE) == 0

# ---------- dispatch ----------

proc setError(c: ptr Cl, msg: string) =
  c.error = msg
  elementRepaint(addr c.e, nil)

proc anyDirty(): bool =
  if theEditor == nil: return false
  for i in 0 ..< editorTabCount(theEditor):
    if editorTabIsDirty(theEditor, i): return true
  false

proc cmdOpen(c: ptr Cl, arg: string): bool =
  if arg.len == 0:
    c.setError("open: missing path"); return false
  if theEditor == nil: return false
  editorOpenFile(theEditor, absolutePath(arg))
  true

proc cmdSave(c: ptr Cl): bool =
  if theEditor == nil: return false
  if not editorActiveHasPath():
    c.setError("save: buffer has no path"); return false
  saveCurrent(theEditor)
  true

proc cmdClose(c: ptr Cl, force: bool): bool =
  if theEditor == nil: return false
  if not force and editorIsDirty():
    c.setError("close: buffer is dirty, use close!"); return false
  let idx = editorActiveIdx(theEditor)
  editorCloseTab(theEditor, idx)
  true

proc cmdQuit(c: ptr Cl, force: bool): bool =
  if not force and anyDirty():
    c.setError("quit: unsaved changes, use quit!"); return false
  quit(0)

proc cmdTheme(c: ptr Cl, arg: string): bool =
  if arg.len == 0:
    c.setError("theme: missing name (try :themes for a list)"); return false
  if not theme.loadThemeByName(arg):
    c.setError("theme: not found: " & arg); return false
  # Persist so the choice survives restart. setConfigKey creates the file
  # if it doesn't exist yet, so a fresh install can `:theme zenburn` once
  # and stick.
  config.setConfigKey("theme", arg)
  # Repaint every window — luigi caches palette-derived bits per element.
  var w = cast[ptr Window](ui.windows)
  while w != nil:
    elementRepaint(addr w.e, nil)
    w = w.next
  true

proc cmdThemes(c: ptr Cl): bool =
  ## Dumps the discovered theme names into the CL's error line as info;
  ## not literally an error, but it's the one status surface we have.
  let names = theme.themeNames()
  if names.len == 0:
    c.setError("themes: none discovered"); return false
  var parts: seq[string] = @[]
  for n in names:
    parts.add(if n == theme.activeTheme: "* " & n else: "  " & n)
  c.setError("themes:  " & parts.join("   "))
  false                                 # keep CL open so the user sees it

proc cmdJump(c: ptr Cl, arg: string): bool =
  ## `:j +N` / `:j -N` jump relative; `:j N` jumps to absolute line N (1-based).
  ## Mirrors Prawk's cmdJump.
  if arg.len == 0:
    c.setError("jump: missing line"); return false
  if theEditor == nil: return false
  try:
    if arg[0] == '+':
      editorJumpRelative(theEditor,  parseInt(arg[1 .. ^1]))
    elif arg[0] == '-':
      editorJumpRelative(theEditor, -parseInt(arg[1 .. ^1]))
    else:
      editorJumpAbsolute(theEditor,  parseInt(arg))
    return true
  except ValueError:
    c.setError("jump: not a number: " & arg); return false

proc splitOnAnd*(s: string): seq[string] =
  ## Splits `s` on `&&` outside single/double quotes. Each segment is
  ## whitespace-trimmed; empty ones are dropped. Lets a single CL line
  ## chain commands (`save && quit`, `open foo.txt && jump 100`).
  result = @[]
  var cur = ""
  var inSingle = false
  var inDouble = false
  var i = 0
  while i < s.len:
    let c = s[i]
    if inSingle:
      cur.add(c)
      if c == '\'': inSingle = false
      inc i
    elif inDouble:
      cur.add(c)
      if c == '"': inDouble = false
      elif c == '\\' and i + 1 < s.len:
        cur.add(s[i + 1]); inc i
      inc i
    elif c == '\'':
      cur.add(c); inSingle = true; inc i
    elif c == '"':
      cur.add(c); inDouble = true; inc i
    elif c == '&' and i + 1 < s.len and s[i + 1] == '&':
      let t = cur.strip()
      if t.len > 0: result.add(t)
      cur = ""
      i += 2
    else:
      cur.add(c); inc i
  let t = cur.strip()
  if t.len > 0: result.add(t)

proc dispatch(c: ptr Cl, raw: string): bool =
  ## Returns true if the CL should close after the command. False keeps it
  ## open so the user can see the error and edit.
  let line = raw.strip()
  if line.len == 0: return true
  let sp = line.find(' ')
  let head = if sp < 0: line else: line[0 ..< sp]
  let rest = if sp < 0: "" else: line[sp + 1 .. ^1].strip()
  case head
  of "open", "o", "e": return cmdOpen(c, rest)
  of "save", "w":      return cmdSave(c)
  of "close":          return cmdClose(c, force = false)
  of "close!":         return cmdClose(c, force = true)
  of "quit", "q":      return cmdQuit(c, force = false)
  of "quit!", "q!":    return cmdQuit(c, force = true)
  of "wq":
    if not cmdSave(c): return false
    return cmdQuit(c, force = false)
  of "wq!":
    if not cmdSave(c): return false
    return cmdQuit(c, force = true)
  of "jump", "j":      return cmdJump(c, rest)
  of "theme":          return cmdTheme(c, rest)
  of "themes":         return cmdThemes(c)
  else:
    c.setError("unknown command: " & head)
    return false

# ---------- open / close ----------

proc dispatchChain(c: ptr Cl, raw: string): bool =
  ## Run an `&&`-chain segment by segment. Stops on the first segment that
  ## returns false (error or status-display like `:themes`) so the user
  ## sees the failure context instead of marching on. Returns true only
  ## when every segment succeeded — the close decision in the Enter
  ## handler / clExecute uses that.
  let segs = splitOnAnd(raw)
  if segs.len == 0: return true
  for seg in segs:
    if not dispatch(c, seg): return false
  true

proc clExecute*(line: string) =
  ## Public dispatcher — runs a command line without opening the visible
  ## CL. Lets the menubar reuse the same dispatch path as typed commands.
  if theCl == nil: return
  discard dispatchChain(theCl, line)

proc clClose*(c: ptr Cl) =
  if c == nil or not isOpen(c): return
  c.e.flags = c.e.flags or ELEMENT_HIDE
  if clOnCloseCb != nil: clOnCloseCb()
  c.buf.setLen(0)
  c.cursor = 0
  c.error.setLen(0)
  c.injected = false
  let prev = c.prevFocus
  c.prevFocus = nil
  if prev != nil:
    elementFocus(prev)
    elementRepaint(prev, nil)
  elementRefresh(c.e.parent)

proc openCl*(prefill: string = "") =
  if theCl == nil: return
  let c = theCl
  if c.e.window != nil and c.e.window.focused != addr c.e:
    c.prevFocus = c.e.window.focused
  c.buf = prefill
  c.cursor = prefill.len
  c.error.setLen(0)
  c.injected = prefill.len > 0
  if (c.e.flags and ELEMENT_HIDE) != 0:
    c.e.flags = c.e.flags and not ELEMENT_HIDE
    if clOnOpenCb != nil: clOnOpenCb()
    elementRefresh(c.e.parent)
  elementFocus(addr c.e)
  elementRepaint(addr c.e, nil)

# ---------- input ----------

proc insertText(c: ptr Cl, s: string) =
  if s.len == 0: return
  c.buf.insert(s, c.cursor)
  c.cursor += s.len
  c.injected = false
  c.error.setLen(0)
  elementRepaint(addr c.e, nil)

proc backspace(c: ptr Cl) =
  if c.cursor == 0: return
  c.buf.delete(c.cursor - 1 .. c.cursor - 1)
  dec c.cursor
  c.injected = false
  c.error.setLen(0)
  elementRepaint(addr c.e, nil)

proc deleteForward(c: ptr Cl) =
  if c.cursor >= c.buf.len: return
  c.buf.delete(c.cursor .. c.cursor)
  c.injected = false
  c.error.setLen(0)
  elementRepaint(addr c.e, nil)

# ---------- paint ----------

proc paint(c: ptr Cl, painter: ptr Painter) =
  let (gW, _) = glyphDims()
  drawBlock(painter, c.e.bounds, ui.theme.textboxFocused)
  let leftX = c.e.bounds.l + padX
  let promptRect = Rectangle(
    l: leftX, r: c.e.bounds.r - padX,
    t: c.e.bounds.t, b: c.e.bounds.b)
  if c.error.len > 0:
    let txt = "!! " & c.error
    drawString(painter, promptRect, txt.cstring, txt.len,
               currentPalette.urgent, cint(ALIGN_LEFT), nil)
    return
  let txt = ":" & c.buf
  drawString(painter, promptRect, txt.cstring, txt.len,
             ui.theme.text, cint(ALIGN_LEFT), nil)
  let beforeCursor = ":" & c.buf.substr(0, c.cursor - 1)
  let cx = leftX + measureStringWidth(beforeCursor.cstring, beforeCursor.len)
  drawInvert(painter, Rectangle(
    l: cx, r: cx + gW,
    t: c.e.bounds.t + padY, b: c.e.bounds.b - padY))
  if c.injected:
    drawBorder(painter, c.e.bounds, currentPalette.clInject,
               Rectangle(l: 2, r: 2, t: 2, b: 2))

# ---------- message handler ----------

proc clMessage(element: ptr Element, message: Message, di: cint, dp: pointer): cint {.cdecl.} =
  let c = cast[ptr Cl](element)

  if message == msgGetHeight:
    if (element.flags and ELEMENT_HIDE) != 0: return 0
    return clHeight()

  elif message == msgPaint:
    paint(c, cast[ptr Painter](dp))
    return 1

  elif message == msgKeyTyped:
    let k = cast[ptr KeyTyped](dp)
    let code = k.code
    if code == int(KEYCODE_ESCAPE):
      clClose(c)
      return 1
    if code == int(KEYCODE_ENTER):
      let line = c.buf
      let shouldClose = dispatchChain(c, line)
      if shouldClose: clClose(c)
      return 1
    if code == int(KEYCODE_BACKSPACE):
      backspace(c)
      return 1
    if code == int(KEYCODE_DELETE):
      deleteForward(c)
      return 1
    if code == int(KEYCODE_LEFT):
      if c.cursor > 0: dec c.cursor
      elementRepaint(element, nil)
      return 1
    if code == int(KEYCODE_RIGHT):
      if c.cursor < c.buf.len: inc c.cursor
      elementRepaint(element, nil)
      return 1
    if code == int(KEYCODE_HOME):
      c.cursor = 0
      elementRepaint(element, nil)
      return 1
    if code == int(KEYCODE_END):
      c.cursor = c.buf.len
      elementRepaint(element, nil)
      return 1
    if k.text != nil and k.textBytes > 0:
      var s = newString(int(k.textBytes))
      copyMem(addr s[0], k.text, int(k.textBytes))
      # Filter control chars; the editor widget accepts them but the CL
      # is single-line plain text.
      var clean = ""
      for ch in s:
        if ch >= ' ' and ch.int < 127: clean.add(ch)
      insertText(c, clean)
      return 1
    return 0

  return 0

# ---------- create ----------

proc clCreate*(parent: ptr Element, flags: uint32 = 0): ptr Cl =
  let e = elementCreate(csize_t(sizeof(Cl)), parent,
                        flags or ELEMENT_H_FILL or ELEMENT_TAB_STOP or ELEMENT_HIDE,
                        clMessage, "Cl")
  let c = cast[ptr Cl](e)
  theCl = c
  return c

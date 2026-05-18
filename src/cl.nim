## Hardwired single-line command line. Hidden by default. `openCl(prefill)`
## reveals it focused, with the buffer pre-loaded. Esc cancels, Enter
## dispatches to a fixed set of editor commands (open / save / close / quit).

import std/[os, strutils]
import rawk_luigi, rawk_bufferlib
import editor_ref, theme

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

var theCl*: ptr Cl

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
  else:
    c.setError("unknown command: " & head)
    return false

# ---------- open / close ----------

proc clClose*(c: ptr Cl) =
  if c == nil or not isOpen(c): return
  c.e.flags = c.e.flags or ELEMENT_HIDE
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
      let shouldClose = dispatch(c, line)
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

## Edrawk menubar — File / View only; trimmer than Prawk's because
## Edrawk has a hardwired CL dispatch (no command registry). Menu options
## go through cl.clExecute so they share one code path with typed
## commands.
##
## File   : Open (prefill), Save, Close, Quit
## View   : Themes list (currently-active marked with `* `)
##
## Alt+F and Alt+V open the respective menus. Keyboard navigation inside
## a popup: J/K + arrows, Enter to invoke, Esc to close.

import rawk_luigi, rawk_bufferlib
import cl, theme

type
  MenuOpKind = enum mokDispatch, mokPrefill

  MenuOption = object
    label:   string
    kind:    MenuOpKind
    payload: string      # for mokDispatch: the CL line. for mokPrefill: prefill text.

  MenuItem = object
    label:   cstring
    x, w:    cint
    options: seq[MenuOption]

  Menubar* = object
    e*: Element
    items:     array[2, MenuItem]      # File, View
    hovered:   int
    prevFocus: ptr Element
    menuOpen:  bool

var theMenubar*: ptr Menubar

const
  padX: cint = 10
  padY: cint = 3

proc menusClose(): bool {.cdecl, importc: "_UIMenusClose".}

# ---------- menu population ----------

proc mkDispatch(label, line: string): MenuOption =
  MenuOption(label: label, kind: mokDispatch, payload: line)

proc mkPrefill(label, line: string): MenuOption =
  MenuOption(label: label, kind: mokPrefill, payload: line)

proc rebuildFileOptions(mb: ptr Menubar) =
  mb.items[0].options = @[
    mkPrefill("Open...", "open "),     # path lands in palette for typing
    mkDispatch("Save",   "save"),
    mkDispatch("Close",  "close"),
    mkDispatch("Quit",   "quit"),
  ]

proc rebuildViewOptions(mb: ptr Menubar) =
  mb.items[1].options = @[mkDispatch("--- Themes ---", "")]
  for n in theme.themeNames():
    let label = if n == theme.activeTheme: "* " & n else: "  " & n
    mb.items[1].options.add(mkDispatch(label, "theme " & n))

# ---------- runtime helpers ----------

proc firstChild(e: ptr Element): ptr Element =
  cast[ptr Element](e.children)

proc isButton(e: ptr Element): bool =
  e != nil and e.cClassName != nil and $e.cClassName == "Button"

proc nextButton(e: ptr Element): ptr Element =
  var cur = e.next
  while cur != nil and not isButton(cur): cur = cur.next
  cur

proc prevButton(first, target: ptr Element): ptr Element =
  var cur = first
  var lastBtn: ptr Element = nil
  while cur != nil and cur != target:
    if isButton(cur): lastBtn = cur
    cur = cur.next
  lastBtn

proc findPopupMenuWin(): ptr Window =
  var w = cast[ptr Window](ui.windows)
  while w != nil:
    if (w.e.flags and WINDOW_MENU) != 0: return w
    w = w.next
  return nil

proc restoreFocusAfterMenu(mb: ptr Menubar) =
  mb.menuOpen = false
  let prev = mb.prevFocus
  mb.prevFocus = nil
  if prev != nil and mb.e.window != nil:
    elementFocus(prev)
    elementRepaint(prev, nil)

proc runOption(cp: pointer) {.cdecl.} =
  if cp == nil: return
  let o = cast[ptr MenuOption](cp)
  if o.payload.len == 0: return        # separator
  case o.kind
  of mokDispatch: clExecute(o.payload)
  of mokPrefill:  openCl(o.payload)

proc menuButtonMessage(element: ptr Element, message: Message,
                       di: cint, dp: pointer): cint {.cdecl.} =
  if message == msgKeyTyped:
    let k = cast[ptr KeyTyped](dp)
    let code = k.code
    let first = firstChild(element.parent)
    if code == int(KEYCODE_DOWN) or code == int(KEYCODE_LETTER('J')):
      let nxt = nextButton(element)
      if nxt != nil: elementFocus(nxt)
      return 1
    if code == int(KEYCODE_UP) or code == int(KEYCODE_LETTER('K')):
      let prv = prevButton(first, element)
      if prv != nil: elementFocus(prv)
      return 1
    if code == int(KEYCODE_ENTER):
      discard elementMessage(element, msgClicked, 0, nil)
      discard menusClose()
      return 1
    if code == int(KEYCODE_ESCAPE):
      discard menusClose()
      return 1
  elif message == msgClicked:
    discard menusClose()
    return 0
  return 0

proc spawnMenu(mb: ptr Menubar, idx: int) =
  if idx < 0 or idx >= mb.items.len: return
  case idx
  of 0: rebuildFileOptions(mb)
  of 1: rebuildViewOptions(mb)
  else: discard
  if mb.items[idx].options.len == 0: return
  if not mb.menuOpen and mb.e.window != nil:
    mb.prevFocus = mb.e.window.focused
  mb.menuOpen = true
  let m = menuCreate(addr mb.e, 0)
  for i in 0 ..< mb.items[idx].options.len:
    let optPtr = addr mb.items[idx].options[i]
    menuAddItem(m, 0, mb.items[idx].options[i].label.cstring,
                invoke = runOption, cp = cast[pointer](optPtr))
  menuShow(m)
  var child = firstChild(addr m.e)
  var firstBtn: ptr Element = nil
  while child != nil:
    if child.cClassName != nil and $child.cClassName == "Button":
      child.messageUser = menuButtonMessage
      if firstBtn == nil: firstBtn = child
    child = child.next
  if firstBtn != nil:
    elementFocus(firstBtn)
  elementFocus(addr mb.e)

proc openFileMenuCb*(cp: pointer) {.cdecl.} =
  if cp != nil: spawnMenu(cast[ptr Menubar](cp), 0)
proc openViewMenuCb*(cp: pointer) {.cdecl.} =
  if cp != nil: spawnMenu(cast[ptr Menubar](cp), 1)

# ---------- element message handler ----------

proc hitItem(mb: ptr Menubar, localX: cint): int =
  for i in 0 ..< mb.items.len:
    let it = mb.items[i]
    if localX >= it.x and localX < it.x + it.w: return i
  return -1

proc menubarMessage(element: ptr Element, message: Message,
                    di: cint, dp: pointer): cint {.cdecl.} =
  let mb = cast[ptr Menubar](element)

  if message == msgGetHeight:
    let (_, gH) = glyphDims()
    return gH + 2 * padY

  elif message == msgPaint:
    let painter = cast[ptr Painter](dp)
    drawBlock(painter, element.bounds, ui.theme.panel2)
    var x: cint = element.bounds.l
    for i in 0 ..< mb.items.len:
      let label = mb.items[i].label
      let textW = measureStringWidth(label)
      let w = textW + 2 * padX
      let itemRect = Rectangle(l: x, r: x + w,
                               t: element.bounds.t, b: element.bounds.b)
      let bg = if i == mb.hovered: ui.theme.buttonHovered else: ui.theme.panel2
      drawBlock(painter, itemRect, bg)
      drawString(painter, itemRect, label, -1,
                 ui.theme.text, cint(ALIGN_CENTER), nil)
      mb.items[i].x = x - element.bounds.l
      mb.items[i].w = w
      x += w
    return 1

  elif message == msgKeyTyped:
    if mb.menuOpen:
      let popup = findPopupMenuWin()
      if popup == nil:
        restoreFocusAfterMenu(mb)
        return 0
      let target = popup.focused
      var rc: cint = 0
      if target != nil:
        rc = elementMessage(target, msgKeyTyped, di, dp)
      if findPopupMenuWin() == nil:
        restoreFocusAfterMenu(mb)
      return rc
    return 0

  elif message == msgMouseMove:
    let w = element.window
    if w != nil:
      let lx = w.cursorX - element.bounds.l
      let h = hitItem(mb, lx)
      if h != mb.hovered:
        mb.hovered = h
        elementRepaint(element, nil)
    return 0

  elif message == msgLeftDown:
    let w = element.window
    if w == nil: return 0
    let lx = w.cursorX - element.bounds.l
    let h = hitItem(mb, lx)
    if h < 0: return 0
    spawnMenu(mb, h)
    return 1

  return 0

proc menubarCreate*(parent: ptr Element, flags: uint32 = 0): ptr Menubar =
  let e = elementCreate(csize_t(sizeof(Menubar)), parent, flags or ELEMENT_TAB_STOP,
                        menubarMessage, "EdrawkMenubar")
  let mb = cast[ptr Menubar](e)
  mb.items[0] = MenuItem(label: cstring"File")
  mb.items[1] = MenuItem(label: cstring"View")
  mb.hovered = -1
  theMenubar = mb
  return mb

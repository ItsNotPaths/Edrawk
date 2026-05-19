## Edrawk — a rawk applet wrapping just the prawk-style text editor widget.
##
## Layout: optional CL line at top (Alt+C to open), tab strip, editor body.
## No menubar, tree, terminal, minimap, or git pane — that's prawk.

import std/os
import rawk_luigi, rawk_bufferlib
import config, theme, editor_ref, editortabs, cl

# ---------- argv ----------

var startFile: string

proc resolveArgv() =
  if paramCount() == 0: return
  let arg = paramStr(1)
  if fileExists(arg):
    startFile = absolutePath(arg)
  elif not dirExists(arg):
    # Doesn't exist yet — open as a new buffer at that path so :w will save.
    startFile = absolutePath(arg)

# ---------- shortcut callbacks ----------

proc shortcutOpenCl(cp: pointer)     {.cdecl.} = openCl("")
proc shortcutOpenFile(cp: pointer)   {.cdecl.} = openCl("open ")
proc shortcutSave(cp: pointer)       {.cdecl.} = openCl("save")
proc shortcutClose(cp: pointer)      {.cdecl.} = openCl("close")
proc shortcutQuit(cp: pointer)       {.cdecl.} = openCl("quit")
proc shortcutJump(cp: pointer)       {.cdecl.} = openCl("jump ")
proc shortcutWrapToggle(cp: pointer) {.cdecl.} = editorWrapToggleActive()

# ---------- main ----------

initialise()
config.loadConfig()
theme.activeTheme = config.themePref
loadInitialTheme()
loadFont(config.fontSize)
loadAllSyntaxes()
resolveArgv()

let win = windowCreate(nil, 0, "Edrawk", 900, 600)
let root = panelCreate(addr win.e, PANEL_GRAY or PANEL_EXPAND)

# Children of `root` are stacked vertically (no PANEL_HORIZONTAL on root).
discard clCreate(addr root.e)
discard editorTabsCreate(addr root.e)

let host = EditorHost(
  indentString:    proc(): string         = config.indentString(),
  lineNumbers:     proc(): LineNumberMode = config.lineNumbers,
  cursorMode:      proc(): CursorMode     = config.cursorMode,
  cursorJumpLines: proc(): int            = config.cursorJumpLines,
  recordOpen:      proc(p: string)        = discard,
  onTabsChanged:   proc() =
    if theEditorTabs != nil:
      elementRepaint(addr theEditorTabs.e, nil))
let editor = editorCreate(addr root.e,
                          ELEMENT_V_FILL or ELEMENT_H_FILL, host)
editor_ref.theEditor = editor

if startFile.len > 0:
  editorOpenFile(editor, startFile)

# Window-level shortcuts. All Alt+letter chords either open the CL with a
# prefilled command (mirroring Prawk's paletteJumpCb / paletteLockCb pattern)
# or toggle a per-buffer setting. Ctrl-based motion + editing lives inside
# the editor widget itself and isn't re-registered here.
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('C')), alt: true, invoke: shortcutOpenCl))
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('O')), alt: true, invoke: shortcutOpenFile))
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('W')), alt: true, invoke: shortcutSave))
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('Q')), alt: true, invoke: shortcutClose))
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('Q')), alt: true, shift: true, invoke: shortcutQuit))
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('J')), alt: true, invoke: shortcutJump))
windowRegisterShortcut(win, Shortcut(
  code: int(KEYCODE_LETTER('Z')), alt: true, invoke: shortcutWrapToggle))

elementFocus(addr editor.e)
quit messageLoop()

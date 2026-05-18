## edrawk — a rawk applet that wraps just the prawk-style text editor widget
## from rawk-bufferlib. No tabs strip, tree, terminal, menubar — only the
## editor in a panel.
##
## Usage: edrawk [path]

import std/os
import rawk_luigi
import rawk_bufferlib

const palette = (
  bg:             0x292828'u32,
  fg:             0xd4be98'u32,
  accent:         0x9253be'u32,
  muted:          0x928374'u32,
  urgent:         0xea6962'u32,
  borderLight:    0x504945'u32,
  borderDark:     0x32302f'u32,
  separator:      0x45403d'u32,
  codeKeyword:    0xd3869b'u32,
  codeString:     0xd8a657'u32,
  codeComment:    0x928374'u32,
  codeNumber:     0xd3869b'u32,
  codeOperator:   0xe78a4e'u32,
  codeType:       0xa9b665'u32,
  codeReturnType: 0x89b482'u32,
)

proc applyTheme() =
  ui.theme.panel1           = palette.bg
  ui.theme.panel2           = palette.borderLight
  ui.theme.selected         = palette.accent
  ui.theme.border           = palette.borderDark
  ui.theme.text             = palette.fg
  ui.theme.textDisabled     = palette.muted
  ui.theme.textSelected     = palette.bg
  ui.theme.buttonNormal     = palette.borderLight
  ui.theme.buttonHovered    = palette.separator
  ui.theme.buttonPressed    = palette.accent
  ui.theme.buttonDisabled   = palette.borderDark
  ui.theme.textboxNormal    = palette.borderLight
  ui.theme.textboxFocused   = palette.separator
  ui.theme.codeFocused      = palette.borderLight
  ui.theme.codeBackground   = palette.bg
  ui.theme.codeDefault      = palette.fg
  ui.theme.codeComment      = palette.codeComment
  ui.theme.codeString       = palette.codeString
  ui.theme.codeNumber       = palette.codeNumber
  ui.theme.codeOperator     = palette.codeOperator
  ui.theme.codePreprocessor = palette.codeKeyword
  setHighlightTheme(ExtraTheme(
    codeKeyword:    palette.codeKeyword,
    codeType:       palette.codeType,
    codeReturnType: palette.codeReturnType,
    urgent:         palette.urgent,
    accent:         palette.accent))

initialise()
applyTheme()
loadFont()
loadAllSyntaxes()

let win = windowCreate(nil, 0, "edrawk", 900, 600)
let root = panelCreate(addr win.e, PANEL_GRAY or PANEL_EXPAND)
let editor = editorCreate(addr root.e,
                          ELEMENT_V_FILL or ELEMENT_H_FILL,
                          defaultHost())

if paramCount() > 0:
  editorOpenFile(editor, absolutePath(paramStr(1)))

elementFocus(addr editor.e)
quit messageLoop()

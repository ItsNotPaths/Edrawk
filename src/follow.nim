## Alt+Enter "follow what's under the cursor", Edrawk-flavored. A `[[wikilink]]`
## opens the first matching `<name>.md` under the working dir; an existing file
## path opens directly. No symbol/goto-definition — that needs the project grep
## + results pane Edrawk deliberately doesn't have (see Prawk for that).
##
## Resolution against `getCurrentDir()` since Edrawk has no project-root notion.

import std/[os, strutils]
import rawk_luigi, rawk_bufferlib, editor_ref

proc caretLine(): (string, int) =
  ## (current line, caret column), or ("", -1) when unavailable.
  if theEditor == nil: return ("", -1)
  let b = activeBuf(theEditor)
  if b == nil: return ("", -1)
  let lines = bufLines(b)
  let row = bufCursorRow(b)
  if row < 0 or row >= lines.len: return ("", -1)
  var col = bufCursorCol(b)
  if col > lines[row].len: col = lines[row].len
  (lines[row], col)

proc linkAtCursor(line: string, col: int): string =
  ## Inner text of a `[[ ... ]]` enclosing the caret, else "".
  var i = 0
  while i + 1 < line.len:
    if line[i] == '[' and line[i + 1] == '[':
      let innerStart = i + 2
      let close = line.find("]]", innerStart)
      if close < 0: break
      if col >= i and col <= close + 2:
        let inner = line[innerStart ..< close].strip()
        if inner.len > 0: return inner
      i = close + 2
    else:
      inc i
  ""

proc pathAtCursor(line: string, col0: int): string =
  ## The maximal non-delimiter run around the caret (a candidate path).
  const delim = {' ', '\t', '"', '\'', '`', '(', ')', '[', ']', '{', '}',
                 '<', '>', ',', ';', '=', '*', ':'}
  var col = col0
  if col < line.len and line[col] in delim and col > 0 and line[col - 1] notin delim:
    dec col
  if col >= line.len or line[col] in delim: return ""
  var s = col
  while s > 0 and line[s - 1] notin delim: dec s
  var e = col
  while e < line.len and line[e] notin delim: inc e
  line[s ..< e]

proc searchNote(dir, wantLower: string): string =
  ## First file named `wantLower` (case-insensitive) at or below `dir`. Skips
  ## hidden dirs (`.git` etc.) since Edrawk has no ignore config.
  var subdirs: seq[string]
  try:
    for kind, entry in walkDir(dir):
      let nm = extractFilename(entry)
      if kind == pcDir or kind == pcLinkToDir:
        if not nm.startsWith("."): subdirs.add(entry)
      elif nm.toLowerAscii == wantLower:
        return entry
  except OSError: discard
  for sd in subdirs:
    let r = searchNote(sd, wantLower)
    if r.len > 0: return r
  ""

proc resolvePath(tok: string): string =
  ## A path-ish token (`/` or `.` in it) resolving to an existing file —
  ## absolute, or relative to the working dir. "" when it isn't one.
  if tok.len == 0 or ('/' notin tok and '.' notin tok): return ""
  if isAbsolute(tok):
    return (if fileExists(tok): tok else: "")
  let cand = getCurrentDir() / tok
  if fileExists(cand): return cand
  ""

proc openInEditor(path: string, replace: bool) =
  if theEditor == nil: return
  if replace and not editorTabIsDirty(theEditor, editorActiveIdx(theEditor)):
    editorReplaceActive(theEditor, path)
  else:
    editorOpenFile(theEditor, path)
  elementFocus(addr theEditor.e)

proc followUnderCursor*(replace: bool) =
  ## Alt+Enter (replace=false: new tab) / Alt+Shift+Enter (replace=true: in
  ## place). [[wikilink]] -> note, else an existing file path -> open.
  let (line, col) = caretLine()
  if col < 0: return
  let link = linkAtCursor(line, col)
  if link.len > 0:
    let note = searchNote(getCurrentDir(), (link & ".md").toLowerAscii)
    if note.len > 0: openInEditor(note, replace)
    return
  let p = resolvePath(pathAtCursor(line, col))
  if p.len > 0: openInEditor(p, replace)

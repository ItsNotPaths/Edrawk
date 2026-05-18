## Global editor pointer. Set once by edrawk.nim after editorCreate; read by
## modules (cl, editortabs) that need to reach the active editor without
## threading a pointer through every call site.

import std/strutils
import rawk_bufferlib

var theEditor*: ptr Editor

proc editorIsDirty*(): bool =
  if theEditor == nil: false
  else: rawk_bufferlib.editorIsDirty(theEditor)

proc editorForceOpenFile*(path: string) =
  if theEditor != nil: editorOpenFile(theEditor, path)

proc editorWrapToggleActive*() =
  if theEditor != nil: editorWrapToggle(theEditor)

proc editorActiveHasPath*(): bool =
  ## Bufferlib doesn't expose the path directly; the tab label is the
  ## stable public surface. `[scratch]` = no path; `~ <hash> <name>` = diff://.
  if theEditor == nil: return false
  let lbl = editorTabLabel(theEditor, editorActiveIdx(theEditor))
  let body = if lbl.startsWith("* "): lbl[2 .. ^1] else: lbl
  body.len > 0 and body != "[scratch]" and not body.startsWith("~ ")

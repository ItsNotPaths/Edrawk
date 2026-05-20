# Edrawk

A minimal wayluigi-based text editor. Wraps the `rawk-bufferlib` editor widget
with a tab strip and a one-line command-line. No tree, no terminal, no git
pane — that's [Prawk](https://Github.com/ItsNotPaths/Prawk). Linux x86_64.

![Edrawk](https://files.paths.place/Edrawk-1.png)

## Run

```
./edrawk             # scratch buffer
./edrawk path/to/file
```

## Keys

Editor key bindings come from `rawk-bufferlib` (`Ctrl+S` save, `Ctrl+F/B/N/P`
Emacs motion, `Insert` toggle cursor mode, `Shift+Alt+H/L/Arrow` word/page
motion, etc.). Edrawk adds:

| Key | Action |
|---|---|
| `Alt+C` | Open CL (replaces the menubar row) |
| `Alt+O` | Open CL with `open ` prefilled |
| `Alt+W` / `Alt+Q` / `Alt+Shift+Q` | Inject `save` / `close` / `quit` |
| `Alt+J` | Inject `jump ` |
| `Alt+Z` | Toggle soft-wrap on the active buffer |
| `Alt+F` / `Alt+V` | File / View menu |
| `Alt+Enter` | Follow under caret: `[[link]]` → note, file path → open it |
| `Alt+Shift+Enter` | Same, opening in the current tab instead of a new one |
| `Esc` | Close the CL (if open), keep buffer focus |

## Commands

Type after `Alt+C`. Chain segments with `&&` (`save && close`). Errors keep
the CL open with the message highlighted; clean runs auto-close.

| Command | What |
|---|---|
| `open <path>` / `o` / `e` | Open file (creates a new buffer if absent) |
| `save` / `w` | Save active buffer |
| `close` / `close!` | Close active tab (force = discard dirty) |
| `quit` / `q` / `quit!` / `q!` | Quit (force = ignore dirty) |
| `wq` / `wq!` | Save then quit |
| `jump <N>` / `j <N>` / `j +N` / `j -N` | Absolute / relative line jump |
| `put <cmd>` | Run `<cmd>`, insert its output at the caret(s) |
| `pipeout <cmd>` | Pipe the selection through `<cmd>`, replace it with the output |
| `theme <name>` / `themes` | Switch theme / list installed themes |

`put`/`pipeout` run synchronously — a long command blocks the editor (no
background shell). `Alt+Enter` resolves links and paths against the cwd.

## Config

`~/.config/edrawk/config` — one `key: value` per line. Defaults shown.

```
tab_mode:          spaces4    # spaces2 | spaces4 | tab
theme:             default
cursor_jump_lines: 10
line_numbers:      global     # off | global | relative
cursor_mode:       insert     # insert | normal
font_size:         14
```

## Build

```
./download-deps.sh
./release.sh --local
```

X11 and Wayland flavors via `-d:wayland`, same as Prawk.

## License

GPLv3.

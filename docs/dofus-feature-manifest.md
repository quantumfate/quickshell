# Dofus multibox feature — manifest

A single reference for the Dofus team/taskbar/auto-swap feature: every file,
state schema, IPC call, and action, across the three repos. Written so the whole
thing can later be reimplemented behind one Go binary — each row names the owner,
the input, and the side effect.

## Repos

| Repo | Path | Role |
| ---- | ---- | ---- |
| quickshell | `~/Projects/github/quantumfate/quickshell` (symlinked `~/.config/quickshell/quantumfate`) | UI: bar, taskbar, state services, IPC surface |
| hypr | `~/.config/hypr` (github `quantumfate/hypr`) | Compositor config: keybinds, submaps, launch flow |
| scripts | `~/Projects/github/quantumfate/scripts/bin` (on `$PATH`) | `dofus_swap.py` OCR turn detector |

## State (single source of truth = files)

| File | Writer(s) | Schema |
| ---- | --------- | ------ |
| `$XDG_STATE_HOME/dofus/team.json` | quickshell `DofusState`, hypr `store.lua`, scripts | `{ title_prefix: "Dofus ", selected: "pioneer", teams: { <key>: [name, …] } }` — list ORDER = turn order |
| `~/.config/dofus-swap.json` | `dofus_swap.py` ONLY | `{ region: {left,top,width,height}, hashes: { <lowercased-name>: <phash-hex> } }` |
| `$XDG_STATE_HOME/dofus_swap.log` | `dofus_swap.py run` | detector stdout/stderr |

Join key across all three: the **character name** (`team.json` order ↔ window
title `"Dofus <Name>"` ↔ `hashes` key, lowercased). No window ids are persisted.

## quickshell — files

| Path | Responsibility |
| ---- | -------------- |
| `services/DofusState.qml` | team.json read/write; reorder/rename/add/remove; `dofus` IPC |
| `services/DofusWindows.qml` | live join of `Hyprland.toplevels` (title-prefix) × team order → `slots`; focus/rename/close/cycle/activate; `dofusWindows` IPC |
| `services/DofusSwap.qml` | reflects `dofus-swap.json`; shells `dofus_swap.py`; detector via `setsid`/`pkill`/`pgrep`; `dofusSwap` IPC |
| `services/Hypr.qml` | window actions over the Lua dispatch layer (focus/close by selector, retitle by pid) — shared by every taskbar |
| `services/Notify.qml` | in-shell feedback bus; `Notify.send(summary, body, level)` |
| `services/Store.qml` | generic reactive JSON-file bridge |
| `services/Theme.qml` | palette + bar typography/tokens |
| `modules/bar/Bar.qml` | per-monitor bar (`Variants`, excludes `HDMI-A-1`); per-screen taskbar setting (`taskbarByScreen`); `bar` + compat `dofusPanel` IPC |
| `modules/bar/WindowStrip.qml` | GENERIC taskbar: takes resolved `slots` + action handlers; a button shows only where its handler is wired |
| `modules/bar/WindowChip.qml` | GENERIC chip: focus/rename/reorder/close/capture, content-wrapped, tips below bar, Dofus capture-feedback |
| `modules/bar/DofusTaskbar.qml` | WindowStrip wired to Dofus (order=team.json, +reorder/capture); present windows only |
| `modules/bar/WorkspaceTaskbar.qml` | WindowStrip wired to the bar monitor's active workspace (focus/rename/close); the "default" bar |
| `modules/bar/SwapControl.qml` | calibrate-region + run/stop detector |
| `modules/bar/Toasts.qml` | renders the Notify queue under the bar |
| `modules/bar/PollText.qml` | waybar exec-model label (command on interval + click/scroll) |
| `modules/bar/{Workspaces,Cpu,Memory,Disk,Network,WindowTitle,Submap,HyprLayout,Language,Tray,Brightness,Pulseaudio,Mako,Clock,Wlogout,HoverTip}.qml` | bar modules |
| `modules/common/WindowRename.qml` | `window` IPC (headless rename + prompt widget) |
| `scripts/dofus-team` | shell read access to team.json for non-QML consumers |

## IPC surface — `qs -c quantumfate ipc call <target> <fn> [arg]`

| Target | Function | Effect |
| ------ | -------- | ------ |
| `dofus` | `team` / `selected` | print roster / active key |
| `dofus` | `select <key>` / `reload` | switch team (persist) / re-read file |
| `dofusWindows` | `slots` | `name\tpresent\taddress` per slot |
| `dofusWindows` | `focus <name>` | focus + raise that window |
| `dofusWindows` | `next` / `prev` | cycle present windows in turn order |
| `dofusWindows` | `activate <index0>` | focus + raise team member (0-based) |
| `dofusSwap` | `calibrate` | `dofus_swap.py calibrate` (slurp region) |
| `dofusSwap` | `learn <name>` | `dofus_swap.py learn <name>` (hash current region) |
| `dofusSwap` | `run` / `stop` / `toggle` | detached detector on/off |
| `dofusSwap` | `status` | running/calibrated/learned summary |
| `bar` | `toggleTaskbar` / `showTaskbar` / `hideTaskbar` | taskbar visibility |
| `dofusPanel` | `show` / `hide` / `toggle` | back-compat alias → taskbar (hypr submap) |
| `window` | `rename <title>` / `prompt <pid>` | headless retitle / rename widget |
| `theme` | `get` / `set <palette>` / `cycle` | palette |
| `help` | `all` | annotated IPC overview |

## Actions — who does what, with which command

| Action | Owner | Underlying command |
| ------ | ----- | ------------------ |
| Focus + raise a window | `DofusWindows.focus` / hypr | `hyprctl dispatch focuswindow address:…` + `alterzorder top` |
| Rename a window | `DofusWindows.rename` / `WindowRename` | `xdotool set_window --name` + `DofusState.rename` |
| Close a window | `DofusWindows.close` | `hyprctl dispatch closewindow address:…` |
| Reorder | `DofusState.reorder` | team.json splice (persist) |
| Cycle turn order | hypr `team.iterate` → `dofusWindows next/prev` | UI join (no hyprctl query) |
| Activate F1..F8 | hypr `team.activate` → `dofusWindows activate` | UI join |
| Calibrate region | `dofus_swap.py calibrate` | `slurp` |
| Learn turn-hash | `dofus_swap.py learn <name>` | `grim` region + `imagehash.phash` |
| Detector run/stop | `DofusSwap` + hypr `swap.lua` | `setsid dofus_swap.py run` / `pkill -f 'dofus_swap.py run'` |
| Broadcast click | hypr `team.press` | detached `xdotool` focus+click loop |
| Auto double-click | hypr `team.double_click_*` | detached `xdotool click --repeat 2` |

## hypr — files

`hypr/services/dofus/{dofus,team,swap,launch,common,ipc,init}.lua`,
`hypr/lib/{store,qs,submap}.lua`, binds in `hypr/binds.lua`.
`team.iterate`/`team.activate` now delegate to `dofusWindows` IPC (the UI owns the
window join); `common.lua` reads team.json via `store.lua`.

## Gotcha — this Hyprland routes `dispatch` through Lua

The compositor runs a Lua config layer: over the Hyprland IPC socket, a
`dispatch <x>` is evaluated as `return hl.dispatch(<x>)`, NOT as a native
dispatcher. So the usual `focuswindow`, `alterzorder`, `closewindow` strings
silently fail to parse. Everything that focuses/raises/closes a window must send
**Lua expressions** instead:

| Intent | String passed to `Hyprland.dispatch(...)` / `hyprctl dispatch …` |
| ------ | --------------------------------------------------------------- |
| focus by title | `hl.dsp.focus({ window = [[title:Dofus <Name>]] })` |
| raise (float)  | `hl.dsp.window.bring_to_top()` |
| close (active) | `hl.dsp.window.close()` (focus the target first) |
| run arbitrary  | `hyprctl -q eval '<lua>'` (what `dofus_swap.py` uses) |

`[[ ]]` are Lua long-string brackets (title may contain spaces). Windows are
matched by **title**, not address: XWayland Dofus toplevels expose no stable
address through Quickshell (`lastIpcObject` is null), and the title carries the
character name anyway. `hl.dsp.*` known fields: `focus`, `window.bring_to_top`,
`window.close`, `exec_cmd` (`kill_active`/`close_window` do NOT exist here).
A Go rewrite talking to the socket must emit the same Lua, or bypass the Lua
layer via the native dispatcher socket if the plugin exposes one.

## Gotcha — Quickshell `Process` children can't create Wayland surfaces

A program spawned as a direct Quickshell `Process` child does **not** get its own
session, and a Wayland client that needs a surface (e.g. `slurp`'s region picker)
then **runs but draws nothing** — no layer surface, no error, it just hangs. This
looks exactly like "the button does nothing." Diagnose by counting layer
**surfaces**, not the process: `hyprctl layers -j` — a working `slurp` shows a
`selection` surface on each output; the broken one shows none while `pgrep slurp`
still returns 1.

Fix: launch such tools **fully detached** in their own session, the same way the
detector does:

```
setsid <tool> … >/dev/null 2>&1 </dev/null &
```

A detached launcher can't report its exit, so if you need the result (notify /
state reset), have the detached script call back over IPC when it finishes —
`DofusSwap.calibrate` runs `setsid bash -c 'dofus_swap.py calibrate && qs … ipc
call dofusSwap _calDone ok || … _calDone cancel' &`. `grim`/`xdotool` don't need
this (no Wayland surface), which is why capture and rename worked as plain
Processes but calibrate did not.

## Notes for a Go reimplementation

A single binary could own: the team.json + dofus-swap.json read/write, the
Hyprland IPC socket (`$XDG_RUNTIME_DIR/hypr/$HIS/.socket.sock` for dispatch,
`.socket2.sock` for the live event stream to keep the join warm), the phash
detector loop (replacing `dofus_swap.py`), and expose one command/RPC surface the
bar and keybinds call — collapsing the current three-process split. The bar UI
would then be the only remaining QML, reading the same two JSON files.

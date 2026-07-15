# quantumfate quickshell

Desktop shell built on [Quickshell](https://quickshell.outfoxxed.me/). Part of
the quantumfate desktop, alongside the
[**hypr**](https://github.com/quantumfate/hypr) compositor config and the
[**scripts**](https://github.com/quantumfate/scripts) CLI helpers.

**See [ARCHITECTURE.md](ARCHITECTURE.md)** for how the UI and Hyprland config
bridge (shared JSON state + IPC).

## Run

```sh
qs -c quantumfate          # if symlinked into ~/.config/quickshell/quantumfate
qs -p ~/Projects/github/quantumfate/quickshell/shell.qml
```

Install (symlink so edits are live):

```sh
ln -s ~/Projects/github/quantumfate/quickshell ~/.config/quickshell/quantumfate
```

## Layout

```
shell.qml            root ShellRoot; wires each top-level widget/window
services/            singletons = shared global state (one concern each)
  Config.qml           paths & constants
  DofusState.qml       Dofus team single source of truth (team.json bridge)
modules/<feature>/   the widgets; PascalCase files auto-import within a dir
  dofus/               DofusTeam (window) + CharacterRow (delegate)
scripts/             shell glue for non-QML consumers
assets/              seeds, images, fonts
```

Convention: **state lives in a `services/` singleton, views live in `modules/`.**
Add a new feature = new `modules/<name>/` + (if it owns global state) a
singleton in `services/`, then drop the root widget into `shell.qml`.

## Shared state — the Store bridge

State shared with the Hyprland Lua config goes through a `Store`: a JSON file in
`$XDG_STATE_HOME/<name>.json` that is the single source of truth, mirrored
reactively on both sides.

```
$XDG_STATE_HOME/<name>.json          ← single source of truth
     ▲ FileView.watchChanges ▲       ▲ mtime-cached reload ▲
  services/Store.qml (QML)        hypr/lib/store.lua (Lua)
```

- **QML:** `Store { name: "dofus/team" }` → `.data`, `.get(...keys)`, `.set(patch)`, `.put(obj)`. `watchChanges` reloads on any external write.
- **Lua:** `Store.define("dofus/team")` → `:get(...)`, `:set(patch)`, `:update(fn)`. Decoded copy kept in RAM, refreshed only when the file's mtime changes (via vendored `hypr/lib/json.lua`, no `jq`).
- Writes are atomic (tmp + rename) and pretty-printed 2-space on both sides, so either runtime can edit and the other converges.

Rule of thumb: **state → a Store (shared) or a singleton (QML-only); commands → IPC.**
A new shared feature = pick a `name`, `Store.define` it in Lua, `Store {}` it in
QML. `DofusState` is the reference example.

## Dofus team = single source of truth

Ordered team list drives turn order, F1–F8 activate, launch order, swap args.
The order lives in **one** JSON file; everything else reads it.

```
~/.local/state/dofus/team.json   (XDG_STATE_HOME) — the truth
        ↑ edit            ↑ read
   Quickshell UI     Hyprland Lua config, dofus_swap.py, scripts
```

### How scripts interact

1. **File directly** (always works, even if the shell isn't running):
   ```sh
   scripts/dofus-team names     # ordered names, one per line
   scripts/dofus-team titles    # names prefixed with "Dofus "
   scripts/dofus-team selected  # active team key
   ```
   or raw: `jq -r '.teams[.selected][]' ~/.local/state/dofus/team.json`

2. **IPC into the running shell** (sees unsaved in-memory edits):
   ```sh
   qs -c quantumfate ipc call dofus team        # ordered names
   qs -c quantumfate ipc call dofus select duo  # switch active team
   qs -c quantumfate ipc call dofusPanel toggle # show/hide the HUD
   ```

## IPC surface

```sh
qs -c quantumfate ipc show           # raw signatures of every target
qs -c quantumfate ipc call help all  # annotated overview with examples
```

Targets: `help`, `theme`, `dofus`, `dofusPanel`, `cheatsheet`. When you add an
`IpcHandler`, document it in `modules/common/IpcHelp.qml`.

### zsh completion

`completions/_qs` completes configs, `ipc` subcommands, and — by reading
`qs ipc show` live — every target and its functions (so it never goes stale).
Install by putting it on your `$fpath`:

```sh
mkdir -p ~/.local/share/zsh/site-functions
ln -s "$PWD/completions/_qs" ~/.local/share/zsh/site-functions/_qs
# ensure this dir is on $fpath before `compinit` in ~/.zshrc:
#   fpath=(~/.local/share/zsh/site-functions $fpath)
```

Writers (UI, scripts) edit the JSON; `DofusState` watches the file and reloads,
so all consumers converge. Editing in the UI writes the file back.

### Wiring the Hyprland Lua config

`hypr/services/dofus/common.lua` currently hard-codes the team. Point it at the
JSON instead so the Lua and the UI share one truth — read the file in
`common.lua` and drop the hard-coded `M.characters`.

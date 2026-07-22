# Architecture

How the [quantumfate desktop](https://github.com/quantumfate) fits together, and
the bridges between the Quickshell UI and the Hyprland config.

## The three repositories

| Repo                                                               | Role                                                                             |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| [**quickshell**](https://github.com/quantumfate/quickshell) (this) | The desktop shell / UI: widgets, theming, shared-state singletons.               |
| [**hypr**](https://github.com/quantumfate/hypr)                    | The Hyprland compositor config (Lua): keybinds, submaps, window rules, services. |
| [**scripts**](https://github.com/quantumfate/scripts)              | Standalone CLI helpers on `$PATH` (e.g. `dofus_swap.py`, `dofus-team`).          |

They are separate processes that cooperate over two well-defined bridges. There
is no daemon and no bespoke socket protocol.

## Two runtimes, one truth

```
        ┌─────────────────────┐        ┌──────────────────────────┐
        │  Hyprland (Lua)      │        │  Quickshell (QML)        │
        │  event-driven,       │        │  long-running, reactive  │
        │  keybind actions      │        │  windows + widgets       │
        └──────────┬───────────┘        └────────────┬─────────────┘
                   │                                  │
        ┌──────────┴──────────────  BRIDGES  ─────────┴─────────────┐
        │                                                            │
   (1) STATE — a JSON file is the single source of truth       (2) COMMAND — IPC
        │                                                            │
   $XDG_STATE_HOME/<name>.json                          qs -c quantumfate ipc call
   e.g. dofus/team.json, theme.json                     e.g. dofusPanel toggle
```

Rule of thumb: **state goes through a Store (a file); commands go through IPC.**

### Bridge 1 — State (file as source of truth)

A shared piece of state lives in `$XDG_STATE_HOME/<name>.json`. Each side has a
thin reactive wrapper over that file, and they converge automatically:

| direction                           | mechanism                                                                     |
| ----------------------------------- | ----------------------------------------------------------------------------- |
| Quickshell edits → Hyprland sees it | Lua `Store.define` handle, mtime-cached, re-reads on next access (a keypress) |
| Hyprland edits → Quickshell sees it | QML `Store { }` uses `FileView.watchChanges` — instant, reactive              |
| either writes                       | atomic tmp + rename bumps mtime → the other side notices                      |

- QML side: [`services/Store.qml`](services/Store.qml) — `Store { name: "dofus/team" }`.
- Lua side: [`hypr/lib/store.lua`](https://github.com/quantumfate/hypr/blob/main/hypr/lib/store.lua) + vendored `hypr/lib/json.lua` (no `jq`).
- Standalone scripts read the same file directly (see `scripts/dofus-team`, `dofus_swap.py`).

Because the file is the truth, adding a third reader (a script, a cron job) needs
no coordination — it just reads the JSON.

### Bridge 2 — Command (IPC)

Actions that are _not_ state — "toggle the panel", "show the cheatsheet",
"switch palette" — go over Quickshell's IPC:

```
qs -c quantumfate ipc call <target> <function> [args]
qs -c quantumfate ipc show          # raw signatures of every target
qs -c quantumfate ipc call help all # annotated overview (modules/common/IpcHelp.qml)
```

The Hyprland side calls these from keybinds (see
[`hypr/services/dofus/ipc.lua`](https://github.com/quantumfate/hypr/blob/main/hypr/services/dofus/ipc.lua)
and the cheatsheet bind in `hypr/binds.lua`).

### Submap callbacks (the glue for which-key UI)

Hyprland submap trees
([`hypr/lib/submap.lua`](https://github.com/quantumfate/hypr/blob/main/hypr/lib/submap.lua))
support `on_enter` / `on_leave` callbacks per node. These fire IPC so the UI
follows compositor state: entering the Dofus submap shows the team panel,
entering a team submap selects that team, leaving hides the panel.

## Layout of this repo

```
shell.qml            root ShellRoot; wires each top-level widget/window
services/            singletons = shared global state, one concern each
  Config.qml           paths & constants
  Theme.qml            colorscheme (Store-backed) — the theming seam
  Store.qml            generic reactive JSON-file bridge (Bridge 1)
  DofusState.qml       Dofus team state over a Store
modules/<feature>/   the widgets; PascalCase files auto-import within a dir
  common/IpcHelp.qml   `help` IPC target
  dofus/               team HUD + editor
  cheatsheet/          which-key keybind overlay
completions/_qs      zsh completion (reads `ipc show`, self-maintaining)
scripts/             shell glue for non-QML consumers
assets/              seed state files, images, fonts
```

## Delivery & dependencies

Dual, equal delivery of the shell + its runtime deps (mirrors the sibling
`hypr` repo):

| Path        | Target machines                | Installs + deploys via                                                                                            |
| ----------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| **Ansible** | Arch/CachyOS and other non-nix | `ansible/roles/quickshell` (pacman)                                                                               |
| **Nix**     | NixOS / nix-managed hosts      | `flake.nix`: `nixosModules.quickshell` (packages) + `homeManagerModules.quickshell` (deploy config + completions) |

Dependency completeness (verified against the QML imports): the `quickshell`
package pulls its hard deps (qt6-base/declarative/svg/wayland, libpipewire,
polkit), but two needs are **not** hard deps and are declared explicitly in both
paths — `Qt5Compat.GraphicalEffects` → `qt6-5compat` (nix `qt6.qt5compat`), and
`Services.UPower` → `upower`. The `Services.Pipewire` service needs the pipewire
daemon + wireplumber **running** (system services, not packaged here). Binaries
the shell shells out to (`jq`, `notify-send`, `xdotool`, `nmcli`, `ip`, `awk`,
`pgrep`, `curl`, `xdg-open`, `grim`, `slurp`, `python`+pillow/imagehash) are all
declared. `nvidia-smi` (GPU stats) ships with the proprietary driver and is
intentionally host-specific.

## Adding things

- **A shared state** → pick a `name`; `Store.define(name)` in Lua, `Store { name }` in QML. Done.
- **A command** → add a function to an `IpcHandler`; document it in `modules/common/IpcHelp.qml`. `ipc show` and the zsh completion pick it up automatically.
- **A widget** → new `modules/<name>/`, read colors from `Theme`, drop the root into `shell.qml`.
- **A palette / full re-theme** → add to `Theme.palettes`; switch live via `ipc call theme set <name>` or editing `theme.json`.

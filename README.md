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

State files (`team.json`, `theme.json`) are **self-seeded** on first run from
`Store` defaults, so a fresh checkout just works — no manual copying.

## Deploy

Two provisioning paths, each an importable "output" you can wire into a larger
controller/config:

- **Ansible** — `ansible/`. Run directly:

  ```sh
  ansible-galaxy collection install -r ansible/requirements.yml
  ansible-playbook ansible/playbook.yml --ask-become-pass
  ```

  Or import the `quickshell` role from your own controller (see
  `ansible/requirements.yml`). Installs runtime packages (Arch), symlinks the
  config, ensures the state dir.

- **Nix flake** — `flake.nix`. Import the modules
  (`inputs.quantumfate-quickshell.url = "github:quantumfate/quickshell"`):

  ```nix
  # home-manager: deploy the config + zsh completions
  imports = [ inputs.quantumfate-quickshell.homeManagerModules.quickshell ];
  programs.quickshellDesktop.enable = true;   # optional: .name = "quantumfate"

  # NixOS: install the runtime packages
  imports = [ inputs.quantumfate-quickshell.nixosModules.quickshell ];
  programs.quickshellDesktop.enable = true;
  ```

  `devShells.<system>.default` gives `quickshell` + tools for `nix develop`.

Both handle the **full** manual setup — runtime packages (incl. `xdotool` for
window rename), the config symlink, the `_qs`/`_qfs` zsh completions + `fpath`
wiring — and rely on the shell self-seeding state, so neither copies data files.
(`qfs` itself ships in the [scripts](https://github.com/quantumfate/scripts)
repo; autostart lives in the [hypr](https://github.com/quantumfate/hypr) config.)

## Editor setup (QML completion)

Completion/diagnostics come from the QML language server, `qmlls`. Two things
matter:

1. **Use a real Qt `qmlls`** (e.g. `qmlls6`, Qt 6.11 — matching the Qt Quickshell
   is built against), not a minimal standalone build. The Qt one knows the
   default import root.
2. **Point it at the import path** so `import Quickshell` / `import QtQuick`
   resolve: pass `-I /usr/lib/qt6/qml` (where Quickshell installs its modules).

Neovim (this repo's owner uses lspconfig):

```lua
qmlls = {
  cmd = { "qmlls6", "-I", "/usr/lib/qt6/qml" },
  filetypes = { "qml", "qmljs" },
  root_markers = { ".qmlls.ini", "shell.qml", ".git" },
}
```

When `qs` is running it also drops a `.qmlls.ini` symlink here pointing at its
per-launch VFS `buildDir`, which gives qmlls type info for _your own_ components
and singletons on top of the installed modules. That file is git-ignored (the
path is ephemeral); the stable, editor-agnostic setup is the `-I` flag above.

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

### `qfs` wrapper

`qfs` (in the [scripts](https://github.com/quantumfate/scripts) repo) wraps the
IPC surface so you rarely type the long form:

```sh
qfs                       # annotated overview  (ipc call help all)
qfs show                  # raw signatures      (ipc show)
qfs theme cycle           # ipc call theme cycle
qfs window rename "..."   # ipc call window rename ...
qfs kill | log | list     # passthrough to qs -c <config>
```

Config name via `$QFS_CONFIG` (default `quantumfate`).

### zsh completion

`completions/_qs` (for raw `qs`) and `completions/_qfs` (for `qfs`) both read
`qs ipc show` live, so every target and function completes and never goes stale.
Install by putting them on your `$fpath`:

```sh
mkdir -p ~/.local/share/zsh/site-functions
ln -s "$PWD/completions/_qs"  ~/.local/share/zsh/site-functions/_qs
ln -s "$PWD/completions/_qfs" ~/.local/share/zsh/site-functions/_qfs
# ensure this dir is on $fpath before `compinit` in ~/.zshrc:
#   fpath=(~/.local/share/zsh/site-functions $fpath)
```

Writers (UI, scripts) edit the JSON; `DofusState` watches the file and reloads,
so all consumers converge. Editing in the UI writes the file back.

### Wiring the Hyprland Lua config

`hypr/services/dofus/common.lua` currently hard-codes the team. Point it at the
JSON instead so the Lua and the UI share one truth — read the file in
`common.lua` and drop the hard-coded `M.characters`.

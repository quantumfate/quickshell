# quantumfate quickshell

Desktop shell built on [Quickshell](https://quickshell.outfoxxed.me/). Part of
the quantumfate desktop, alongside the [hypr](https://codeberg.org/quantumfate/hypr)
compositor config and the [scripts](https://codeberg.org/quantumfate/scripts) CLI
helpers.

**See [ARCHITECTURE.md](ARCHITECTURE.md)** for how the UI and the Hyprland
config bridge (shared JSON state + IPC).

## Run

```sh
qs -c quantumfate          # if symlinked into ~/.config/quickshell/quantumfate
qs -p ~/Projects/codeberg/quantumfate/quickshell/shell.qml
```

Install (symlink so edits are live):

```sh
ln -s ~/Projects/codeberg/quantumfate/quickshell ~/.config/quickshell/quantumfate
```

State files (`team.json`, `theme.json`) seed themselves on first run from
`Store` defaults, so a fresh checkout just works.

## Deploy

Two provisioning paths, each importable as an "output" of a larger config:

- **Ansible** — `ansible/`. Run directly:

  ```sh
  ansible-galaxy collection install -r ansible/requirements.yml
  ansible-playbook ansible/playbook.yml --ask-become-pass
  ```

  Or import the `quickshell` role from your own controller (see
  `ansible/requirements.yml`). Installs the runtime packages (Arch), symlinks
  the config, creates the state dir.

- **Nix flake** — `flake.nix`. Add it as an input
  (`url = "https://codeberg.org/quantumfate/quickshell"`) and import the
  modules:

  ```nix
  # home-manager: deploy the config + zsh completions
  imports = [ inputs.quantumfate-quickshell.homeManagerModules.quickshell ];
  programs.quickshellDesktop.enable = true;   # optional: .name = "quantumfate"

  # NixOS: install the runtime packages
  imports = [ inputs.quantumfate-quickshell.nixosModules.quickshell ];
  programs.quickshellDesktop.enable = true;
  ```

  `devShells.<system>.default` gives `quickshell` + tools for `nix develop`.

Both handle the full manual setup — runtime packages (incl. `xdotool` for
window rename), the config symlink, the `_qs`/`_qfs` completions + `fpath`
wiring — without copying data files. (`qfs` ships in the [scripts](https://codeberg.org/quantumfate/scripts)
repo; autostart lives in the [hypr](https://codeberg.org/quantumfate/hypr) config.)

## Editor setup (QML completion)

Completion comes from the QML language server, `qmlls`:

1. Use a real Qt `qmlls` (e.g. `qmlls6`, Qt 6.11 — matching what Quickshell is
   built against), not a minimal standalone build.
2. Point it at the import path: `-I /usr/lib/qt6/qml`.

Neovim (lspconfig):

```lua
qmlls = {
  cmd = { "qmlls6", "-I", "/usr/lib/qt6/qml" },
  filetypes = { "qml", "qmljs" },
  root_markers = { ".qmlls.ini", "shell.qml", ".git" },
}
```

While `qs` is running it drops a `.qmlls.ini` symlink here pointing at its
per-launch VFS `buildDir`, giving qmlls type info for the local components on
top of the installed modules. That file is git-ignored (the path is ephemeral).

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

Convention: state lives in a `services/` singleton, views in `modules/`. A new
feature is a new `modules/<name>/` plus, if it owns global state, a singleton
in `services/`, then the root widget drops into `shell.qml`.

## Shared state — the Store bridge

State shared with the Hyprland Lua config goes through a `Store`: a JSON file
in `$XDG_STATE_HOME/<name>.json` that is the single source of truth, mirrored
on both sides.

```
$XDG_STATE_HOME/<name>.json          ← single source of truth
     ▲ FileView.watchChanges ▲       ▲ mtime-cached reload ▲
  services/Store.qml (QML)        hypr/lib/store.lua (Lua)
```

- **QML:** `Store { name: "dofus/team" }` → `.data`, `.get(...keys)`,
  `.set(patch)`, `.put(obj)`. `watchChanges` reloads on any external write.
- **Lua:** `Store.define("dofus/team")` → `:get(...)`, `:set(patch)`,
  `:update(fn)`. Decoded copy kept in RAM, refreshed when the file's mtime
  changes (vendored `hypr/lib/json.lua`, no `jq`).
- Writes are atomic (tmp + rename) and pretty-printed on both sides, so either
  runtime can edit and the other converges.

Rule of thumb: state → a Store (shared) or a singleton (QML-only); commands →
IPC. `DofusState` is the reference example.

## Dofus team

Ordered team list drives turn order, F1–F8 activation, launch order, swap args.
The order lives in **one** JSON file; everything else reads it:

```
~/.local/state/dofus/team.json   (XDG_STATE_HOME) — the truth
        ↑ edit            ↑ read
   Quickshell UI     Hyprland Lua config, dofus_swap.py, scripts
```

### How scripts interact

1. **File directly** (works even if the shell isn't running):

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

Targets: `help`, `theme`, `dofus`, `dofusPanel`, `cheatsheet`, `obsidian`,
`obsidianCreate`. When you add an `IpcHandler`, document it in
`modules/common/IpcHelp.qml`.

### `qfs` wrapper

`qfs` (in the [scripts](https://codeberg.org/quantumfate/scripts) repo) wraps the
IPC surface:

```sh
qfs                       # annotated overview  (ipc call help all)
qfs show                  # raw signatures      (ipc show)
qfs theme cycle           # ipc call theme cycle
qfs window rename "..."   # ipc call window rename ...
qfs kill | log | list     # passthrough to qs -c <config>
```

Config name via `$QFS_CONFIG` (default `quantumfate`).

### zsh completion

`completions/_qs` (raw `qs`) and `completions/_qfs` both read `qs ipc show`
live, so targets and functions complete and never go stale. Install by putting
them on your `$fpath`:

```sh
mkdir -p ~/.local/share/zsh/site-functions
ln -s "$PWD/completions/_qs"  ~/.local/share/zsh/site-functions/_qs
ln -s "$PWD/completions/_qfs" ~/.local/share/zsh/site-functions/_qfs
# ensure this dir is on $fpath before `compinit` in ~/.zshrc:
#   fpath=(~/.local/share/zsh/site-functions $fpath)
```

Writers (UI, scripts) edit the JSON; `DofusState` watches the file and
reloads, so all consumers converge. Editing in the UI writes the file back.

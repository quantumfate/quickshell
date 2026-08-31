# Architecture

This repository bridges everything on my desktop with the concept of a `store`.

## The three repositories

| Repo                                                          | Role                                                          |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| [**quickshell**](https://codeberg.org/quantumfate/quickshell) | The desktop shell: widgets, theming, shared-state singletons. |
| [**hypr**](https://codeberg.org/quantumfate/hypr)             | The Hyprland config (Lua): keybinds, submaps, window rules.   |
| [**scripts**](https://codeberg.org/quantumfate/scripts)       | Standalone CLI helpers on `$PATH`.                            |

My obsidian is managed too but not listed here.

## Bridge 1 — State (the Store)

A `Store` is a reactive wrapper over `$XDG_STATE_HOME/<name>.json`, the single
source of truth shared by both runtimes. Each side edits the same file and
they converge automatically:

| direction                           | mechanism                                                         |
| ----------------------------------- | ----------------------------------------------------------------- |
| Quickshell edits → Hyprland sees it | Lua `Store.define` handle, mtime-cached, re-read on next access.  |
| Hyprland edits → Quickshell sees it | QML `Store { }` uses `FileView.watchChanges` — instant, reactive. |
| either writes                       | atomic tmp + rename bumps mtime → the other side notices.         |

- QML side: `services/Store.qml` — `Store { name: "theme" }` → `.data`,
  `.get(...)`, `.set(patch)`, `.put(obj)`, `defaults` (seeds an empty file).
- Lua side:
  [`hypr/lib/store.lua`](https://codeberg.org/quantumfate/hypr/src/branch/main/hypr/lib/store.lua)
  — `Store.define("theme")` → `:get(...)`, `:set(patch)`, `:update(fn)`
  (vendored `json.lua`, no `jq`).
- A third reader (script, cron) just reads the JSON — no coordination.

Every singleton that owns shared state is a Store: `Theme` (`theme.json`),
`DofusState` (`dofus/team.json`), `ObsidianVault` (`obsidian/tags.json`),
`Notify` (`notifications.json`).

## Bridge 2 — Command (IPC)

Actions that aren't state — "toggle the panel", "show the cheatsheet",
"switch palette" — go over Quickshell's IPC:

```
qs -c quantumfate ipc call <target> <function> [args]
qs -c quantumfate ipc show          # raw signatures
qs -c quantumfate ipc call help all # annotated overview
```

Hyprland calls these from keybinds and submap `on_enter`/`on_leave` callbacks,
so the UI follows compositor state (entering a submap shows the matching panel).

## Delivery & dependencies

Dual, equal delivery of the shell + runtime deps (mirrors the `hypr` repo):

| Path        | Target machines           | Installs + deploys via                                                                                     |
| ----------- | ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Ansible** | Arch/CachyOS              | `ansible/roles/quickshell` (pacman)                                                                        |
| **Nix**     | NixOS / nix-managed hosts | `flake.nix`: `nixosModules.quickshell` (packages) + `homeManagerModules.quickshell` (deploy + completions) |

Dependencies not hard-linked from the `quickshell` package are declared
explicitly: `Qt5Compat.GraphicalEffects` → `qt6-5compat`, `Services.UPower` →
`upower`; `Services.Pipewire` needs the pipewire/wireplumber daemons running.
Binaries the shell shells out to (`jq`, `notify-send`, `xdotool`, `nmcli`,
`grim`, `slurp`, `python`+pillow/imagehash, …) are all declared.

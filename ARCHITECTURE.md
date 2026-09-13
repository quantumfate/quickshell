# Architecture

This repository bridges everything on my desktop with the concept of a `store`.

## The three repositories

| Repo                                                          | Role                                                          |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| [**quickshell**](https://codeberg.org/quantumfate/quickshell) | The desktop shell: widgets, theming, shared-state singletons. |
| [**hypr**](https://codeberg.org/quantumfate/hypr)             | The Hyprland config (Lua): keybinds, submaps, window rules.   |
| [**scripts**](https://codeberg.org/quantumfate/scripts)       | Standalone CLI helpers on `$PATH`.                            |

My obsidian is managed too but not listed here.

## the Store

The `Store` is a reactive wrapper over `$XDG_STATE_HOME/<name>.json`, the single
source of truth shared by both runtimes.

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

Two stores define _policy_ rather than current state. They are read by the
event manager and the launcher scripts (and written by the scene editor and
the mood config surface), but no singleton owns them yet:
[`scenes.json`](schemas/scenes.schema.json) (workspace scenes, LEO-235) and
[`mood-policy.json`](schemas/mood-policy.schema.json) (per-mood policy,
LEO-236). Their schemas and seeds live under `schemas/` + `assets/`, and the
tests lock the seeds to the QML that still owns the same facts (Focus.qml's
mood table) so the two cannot drift.

## Command (IPC)

IPC takes care of actions that do not require a state:

```
qs -c quantumfate ipc call <target> <function> [args]
qs -c quantumfate ipc show          # raw signatures
qs -c quantumfate ipc call help all # annotated overview
```

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

# Architecture

This repository bridges everything on my desktop with the concept of a `store`.

## The three repositories

| Repo                                                          | Role                                                          |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| [**quickshell**](https://github.com/quantumfate/quickshell) | The desktop shell: widgets, theming, shared-state singletons. |
| [**hypr**](https://github.com/quantumfate/hypr)             | The Hyprland config (Lua): keybinds, submaps, window rules.   |
| [**scripts**](https://github.com/quantumfate/scripts)       | Standalone CLI helpers on `$PATH`.                            |

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
  [`hypr/lib/store.lua`](https://github.com/quantumfate/hypr/src/branch/main/hypr/lib/store.lua)
  — `Store.define("theme")` → `:get(...)`, `:set(patch)`, `:update(fn)`
  (vendored `json.lua`, no `jq`).
- A third reader (script, cron) just reads the JSON — no coordination.

Every singleton that owns shared state is a Store: `Theme` (`theme.json`),
`DofusState` (`dofus/team.json`), `ObsidianVault` (`obsidian/tags.json`),
`Notify` (`notifications.json`).

### Where this is going

The two policy stores below are being replaced by one **declaration**: a mode
names what may exist on the desk — workspaces, scenes, binding trees, services,
notification routing, projects — and a reconciler converges the running system
on it. The engine is `hyprfocus`; the cross-repo architecture lives in the
sibling `system-config` repo, and this repo is where the declaration is edited,
since the shell is the runtime that can write the store while the compositor
reads it.

Three consequences for the code below:

- **Oracles mostly disappear.** `sceneState` and `backgroundTaskLevel` answer
  "is this allowed"; a declaration answers "does this exist", and a binding
  that a mode does not admit is simply not loaded. Gates survive only for what
  escapes declaration.
- **`background` is inert today.** Every shipped mood sets `allow: ["*"]`,
  while real stopping happens off a _scene_ key in the scripts repo. Policy
  keyed by mode and enforcement keyed by scene cannot express one intent, which
  is the divergence the declaration removes.
- **Notification routing needs identity first.** `route` records what happened
  but keys on nothing stable; `app_name` is self-reported free text. Resolution
  moves to a chain — `desktopEntry`, our own `x-hyprfocus-source` hint,
  `category`, then urgency for severity only.

The naming is settled: the engine is hyprfocus, a state is a **mode**, and
"mood" retires.

Two stores define _policy_ rather than current state. [`scenes.json`](schemas/scenes.schema.json) (workspace scenes, LEO-235) is read by the event
manager and the scene editor but owned by no singleton yet. [`mood-policy.json`](schemas/mood-policy.schema.json)
(per-mood policy, LEO-236) is owned by `Focus` since LEO-237: Focus's
`policyDefaults` literal is the definitional table, the asset under `assets/`
is its exact serialization, and `Focus.patchMood` is the one writer the mood
config surface uses — so a UI edit lands in the same file the Hyprland event
manager and the launcher scripts read. `focus.json` stays the active-state
pointer (`{ mode, until }`); the lockstep tests pin the policy seeds to the
QML literals so the file and the shell cannot drift.

Since LEO-238, Enforcement is _dispatch-time oracles + one systemd seam_, never
a second interpretation of the policy:

- **Oracles.** `Focus.sceneState(scene)` → `reachable`/`blocked` and
  `Focus.backgroundTaskLevel(task)` → `allow`/`defer`/`prevent`/`unset`/`blocked`
  are the single resolvers; the mood panel and the scripts read the same
  function. IPC exposes them as `focus scene <name>` and `focus bg <task>`.
- **Notifications.** `Notify` records a `route` on every history entry
  (`shown` | `dnd` | `mood`) and re-positions the toast queue per the active
  mood's `position`; per-toast expiry comes from the mood's `timeout` (0 =
  sticky). A mood that sets `queue` + `digest_on_exit` folds its buffered,
  suppressed notifications into one digest toast when the mood ends. LEO-240
  (routed notification centre) will consume the `route` field.
- **Background seam.** Focus fires `,scene-apply.sh <mode>` (detached, failing
  open) on every mood transition. The script lives in the **scripts** repo with
  its own contract (`etc/scene-managed.json`) — the desktop's delivery rule
  keeps each repo's data with its consumer, so quickshell never reads it. It
  stops/restarts user units per the mood's reachable scenes + deferred/prevented
  background tasks, honours a `protected` rail, never force-kills, and logs every
  decision to `$XDG_STATE_HOME/scene-policy/log.jsonl` (LEO-241's feed).

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

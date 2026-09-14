# Agent notes

This repo is the desktop shell: a Quickshell config (QML) that is one executor
of the `hyprfocus` declaration. Compositor logic lives in the sibling
[hypr](https://github.com/quantumfate/hypr) repo; packaging/provisioning in
[system-config](https://github.com/quantumfate/system-config).

## Read order

New to the repo, read in this order — each layer points at the next:

1. [README.md](README.md) — run/install, the Store pattern, IPC surface.
2. [ARCHITECTURE.md](ARCHITECTURE.md) — the Store contract, the policy stores
   (`focus.json`, `mood-policy.json`, `scenes.json`), the enforcement seam, and
   the "where this is going" (mode → declaration).
3. Cross-repo: hypr `AGENTS.md` (the scene contract + compositor half of the
   same stores) and `system-config/docs/hyprfocus.md` (the full engine).

## Repo map

| Path           | Owns                                                                                                      |
| -------------- | --------------------------------------------------------------------------------------------------------- |
| `shell.qml`    | the shell entry; instantiates the bars + services                                                         |
| `modules/`     | widgets per surface (`bar`, `control`, `cheatsheet`, `dofus`, …)                                          |
| `services/`    | singletons with state or IPC (`Store`, `Theme`, `Focus`, `Notify`, `Hyprfocus`, `DofusState`, `Sound`, …) |
| `schemas/`     | JSON schemas for the state files the Store reads/writes                                                   |
| `assets/`      | serialized defaults for the policy stores (pinned by lockstep tests)                                      |
| `scripts/`     | `dofus-team`, provisioning helpers                                                                        |
| `completions/` | zsh completions (`_qs`, `_qfs`), read `ipc show` live                                                     |
| `tests/`       | node --test specs that load the real QML sources                                                          |

## The two languages

- State → a `Store` (`services/Store.qml`): reactive wrapper over
  `$XDG_STATE_HOME/<name>.json`, atomic writes, `watchChanges` reloads. The
  Lua side mirrors it in hypr's `hypr/lib/store.lua` — same file, either side
  edits, both converge.
- Commands → IPC (`IpcHandler`); `qs -c quantumfate ipc call help all` for the
  annotated surface. `qfs` (hypr `bin/`) wraps it.

## Contract

- **The declaration is edited here.** Mode policy (`mood-policy.json`), the
  focus pointer (`focus.json`) and scenes (`scenes.json`) live in
  `$XDG_STATE_HOME`; `Focus`'s `policyDefaults` literal is the definitional
  table and `assets/*.default.json` is its exact serialization — the lockstep
  tests pin them; change both or change neither.
- **A mood is a mode id** (`neutral`, `work`, `study`, `gaming`). `deep`,
  `game`, `chores`, `reflect`, `media`, `llm` are retired; do not reintroduce
  them.
- **Enforcement is oracles + one seam, never a second interpretation:**
  `Focus.sceneState` / `Focus.backgroundTaskLevel` are the single resolvers
  (exposed as `focus scene <name>` / `focus bg <task>`); mood transitions fire
  `,scene-apply.sh` (the script lives in hypr `bin/`, this repo never reads its
  contract `etc/scene-managed.json`).
- **Theming goes through roles.** Colors and sizes are `Theme.*` roles read
  from the active palette, never literals — the `tokens` gate enforces it and
  `Theme.qml` is the only file allowed hex literals.

## Commands

```sh
just check        # fmt-check + qmllint + tokens + test + smoke (the gate)
just test         # node --test tests/  — loads real QML, no copies
just smoke        # boots the real config, fails on load errors
just lint tokens  # static only
```

`qmllint` cannot resolve Quickshell plugin types (tuned in `.qmllint.ini`) and
a missing import passes it — `just smoke` is part of the gate for that reason.

## Style

- Complete-sentence comments; keep the existing comment voice in `justfile`.
- No pixel literals in QML (`tokens`); no hex outside `Theme.qml`.
- Do not add a second writer to a policy store; patches go through the owning
  service (`Focus.patchMood`, `Theme`, …).
- Schema, asset, QML literal and tests move together for every store change.

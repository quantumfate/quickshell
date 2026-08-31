# quantumfate quickshell

Desktop shell built on [Quickshell](https://quickshell.outfoxxed.me/).

**See [ARCHITECTURE.md](ARCHITECTURE.md)** for more details.

## Run

```sh
qs -c quantumfate          # config symlinked into ~/.config/quickshell/
qs -p path/to/shell.qml    # run directly from a checkout
```

State files seed themselves on first run from `Store` defaults, so a fresh
checkout just works.

## Install

Symlink the config so edits are live:

```sh
ln -s path/to/quickshell ~/.config/quickshell/quantumfate
```

## Shared state — the Store

A `Store` is a reactive wrapper around a JSON file in
`$XDG_STATE_HOME/<name>.json` that is the single source of truth for a piece of
shared state — the **general mechanism** every singleton uses to persist and
stay live, on the Quickshell side and mirrored on the Lua side.

```qml
Store {
    name: "theme"                    // -> $XDG_STATE_HOME/theme.json
    defaults: ({ palette: "macchiato" })
    // data  — parsed object, reactive
    // get(...keys)  — drill into nested keys
    // set(patch)    — shallow-merge + persist
    // put(obj)      — replace whole document + persist
}
```

- Writes are atomic (tmp + rename) and pretty-printed, so multiple runtimes can
  edit the file and converge automatically.
- `watchChanges` reloads on any external edit (Lua config, a script, a cron job)
  with no coordination — any third reader just reads the JSON.
- `defaults` seeds the file on first run; a fresh checkout needs no setup.

Rule of thumb: **state → a Store (shared file) or a singleton (QML-only);
commands → IPC.** In use by `Theme`, `DofusState`, `ObsidianVault`, `Notify` —
each with its own `name` and file.

## IPC

Non-state commands go over Quickshell's IPC:

```sh
qs -c quantumfate ipc show           # raw signatures of every target
qs -c quantumfate ipc call help all  # annotated overview with examples
qs -c quantumfate ipc call theme cycle
```

Targets are declared as `IpcHandler`s in the services/widgets; the annotated
`help all` lives in `modules/common/IpcHelp.qml`. `qfs` (in the scripts
repo) wraps the surface, and the zsh completions (`completions/_qs`,
`completions/_qfs`) read `ipc show` live so they never go stale.

## Editor setup (QML completion)

`qmlls` (e.g. `qmlls6`, Qt 6.11) with `-I /usr/lib/qt6/qml`. While `qs` runs it
drops a `.qmlls.ini` symlink here pointing at its per-launch VFS, giving type
info for the local components.

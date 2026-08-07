# Obsidian vault bootstrap feature — manifest

A single reference for the Zettelkasten + index-note bootstrap: every file, state
schema, command, and gotcha across the repos. The vault is the source of truth;
everything else is a **projection** of it, rebuilt by one writer — the inverse of
the Dofus feature, where the JSON file is truth and several editors write it.

## Repos

| Repo       | Path                                                                                      | Role                                                            |
| ---------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| scripts    | `~/Projects/github/quantumfate/scripts/bin` (on `$PATH`)                                  | `obsidian_vault.py` bootstrap + `,obsidian-cli-wrapper.sh`      |
| quickshell | `~/Projects/codeberg/quantumfate/quickshell` (symlinked `~/.config/quickshell/quantumfate`) | store view + new-note form (`ObsidianVault` / `ObsidianCreate`) |
| hypr       | `~/.config/hypr` (codeberg `quantumfate/hypr`)                                              | `services/obsidian` submap: MOD+o → new note / status / tree    |

The vault itself is **not** a repo: `~/Documents/Obsidian/Main` with notes flat in
`Zettelkasten/` (~443 notes: 260 atomic, 40 fleeting, 132 moc). Templates:
`Templates/{atomic note,fleeting note,moc note,journal note,blog post}.md`, Templater
helpers in `Templates/__scripts/templater/get_new_uuid.js`.

## Tag model — the `idx` / `meta_idx` semantics

Tags are the index. Three kinds, decided by the final segment:

| Tag ending       | Kind     | Meaning                                                                                          |
| ---------------- | -------- | ------------------------------------------------------------------------------------------------ |
| `Topic`          | leaf     | the note's content topic; repeats freely                                                         |
| `Topic/idx`      | idx      | ONE note per tag: the obsidian-index-notes plugin renders a callout of every note tagged `Topic` |
| `Topic/meta_idx` | meta_idx | ONE note per tag: pretty render of the `<Topic>/idx` sub-indices (surface-level categorization)  |

Uniqueness rule: exactly one note carries a given `idx`/`meta_idx` tag; leaf tags
repeat. A note may carry both its own `idx` and `meta_idx` tags (e.g.
`Security.md`, `Continuous Integration and Delivery.md`). The filename is a
**manual** slug (`Systems.md` ↔ topic `Technology/Systems`), never derived.

## State (single source of truth = the vault)

| File                                     | Writer              | Role                                     |
| ---------------------------------------- | ------------------- | ---------------------------------------- |
| `~/Documents/Obsidian/Main`              | the user            | authoritative content + tags             |
| `$XDG_STATE_HOME/obsidian/tags.json`     | `obsidian_vault.py` | tag-store projection (scan of the vault) |
| `$XDG_STATE_HOME/obsidian/tags.json.gpg` | `obsidian_vault.py` | same store, GPG-encrypted (`batch` mode) |

Join key: the **tag path** (topic), lowercased; notes connect to topics via their
`idx`/`meta_idx`/leaf tags. No note ids are used as join keys (the `note_id`
frontmatter field exists but is cosmetic).

## scripts — files

| Path                           | Responsibility                                                                     |
| ------------------------------ | ---------------------------------------------------------------------------------- |
| `bin/obsidian_vault.py`        | scan → store; infer missing index chain; create notes via Templater + Obsidian CLI |
| `bin/,obsidian-cli-wrapper.sh` | human/agent shell front-end (status/sync/dump/ensure-topic/create)                 |

## Commands

All go through the wrapper (default: `status`). `obsidian_vault.py` is pure
delegation behind it.

| Command                                                             | Effect                                                                     |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `,obsidian-cli-wrapper.sh status`                                   | vault, store paths, recipient, store freshness                             |
| `,obsidian-cli-wrapper.sh sync [--no-encrypt]`                      | rescan vault → rewrite `tags.json` + `.gpg`                                |
| `,obsidian-cli-wrapper.sh dump [--raw]`                             | tree report / raw JSON                                                     |
| `,obsidian-cli-wrapper.sh ensure-topic <topic> [--dry-run]`         | create only the missing `idx`/`meta_idx` chain for a topic                 |
| `,obsidian-cli-wrapper.sh create <note_type> <title> --tag <topic>` | infer chain, then create the note (`atomic\|fleeting\|moc\|journal\|blog`) |

`create` plan order (deepest ancestor first): add missing `meta_idx` tag to each
existing ancestor → create missing `moc` index notes → create the note itself →
`sync`. Options: `--tags a,b` extras, `--open`/`--no-open`, `--no-chain`,
`--dry-run`, `--no-encrypt`.

## Environment

| Var                      | Default                                                 |
| ------------------------ | ------------------------------------------------------- |
| `OBSIDIAN_VAULT`         | `~/Documents/Obsidian/Main`                             |
| `OBSIDIAN_ROOT`          | `Zettelkasten` (relative to vault)                      |
| `OBSIDIAN_CLI`           | `obsidian`                                              |
| `OBSIDIAN_GPG_RECIPIENT` | `45EE29D4AA966DFD`                                      |
| `XDG_STATE_HOME`         | `~/.local/state` (store dir `$XDG_STATE_HOME/obsidian`) |

## Store schema (`tags.json`)

```jsonc
{
  "version": 1, "generated": "<iso-8601>",
  "vault": "<name>", "vault_path": "<abs>", "root": "Zettelkasten",
  "recipient": "45EE29D4AA966DFD",
  "note_count": 443, "topic_count": 196,
  "templates": { "atomic": "Templates/atomic note.md", "...": "..." },
  "notes": { "<title>": { "note_id", "note_type", "file", "tags": [] } },
  "tags": { "<tag>": { "kind": "leaf|idx|meta_idx", "topic", "count", "notes": [] } },
  "topics": { "<topic>": { "title", "idx_note", "meta_idx_note", "leaf_count", "parent", "depth" } },
  "tree": { "<slug>": { "slug", "title", "idx_note", "meta_idx_note", "leaf_count", "children": {} } }
}
```

## quickshell — files

| Path                                  | Responsibility                                                                                                                                            |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `services/ObsidianVault.qml`          | singleton: `Store { name: "obsidian/tags" }` read + domain view (topics/tree/`chainInfo`/`topicPaths`) + actions that shell the wrapper; `obsidian` IPC   |
| `modules/obsidian/ObsidianCreate.qml` | modal new-note form (type pills, title, topic + completion + chain preview, open-in-Obsidian toggle); shells `ObsidianVault.create`; `obsidianCreate` IPC |
| `modules/common/IpcHelp.qml`          | documents both targets                                                                                                                                    |

## IPC surface — `qs -c quantumfate ipc call <target> <fn> [arg]`

| Target           | Function                      | Effect                                                                                 |
| ---------------- | ----------------------------- | -------------------------------------------------------------------------------------- |
| `obsidian`       | `status`                      | vault, note/topic counts, last sync                                                    |
| `obsidian`       | `tree`                        | indented tag-tree report (for `qs.notify`)                                             |
| `obsidian`       | `create <type> <title> <tag>` | shell the wrapper create (type: atomic\|fleeting\|moc\|journal\|blog); toast on result |
| `obsidian`       | `ensure <topic>`              | shell `ensure-topic`; toast on result                                                  |
| `obsidian`       | `reload` / `lastTopic`        | re-read store / last topic the form used                                               |
| `obsidian`       | `setOpenOnCreate <bool>`      | persist the `--open` flag for `create` (default off)                                   |
| `obsidianCreate` | `show` / `hide` / `toggle`    | open/close the create-note popup; toggle + `hide` abort a running create               |

> **Form behavior.** `show`/`toggle` open the popup (focus lands on the title
> field). Re-invoking the bind (`toggle`) or pressing `Esc` closes it — and if a
> create is running, that aborts the process (no note, no toast). Clicking the
> dimmed area does **not** close it. The form's "Open on / Open off" pill flips
> `openOnCreate`, which `ObsidianVault.create` passes to the wrapper as
> `--open`/`--no-open`; it persists in the shell-only `ui.json` store alongside
> `lastTopic`.

## hypr — files

`hypr/services/obsidian/init.lua` (required from `services/init.lua`): submap
`MOD+o` → `n` new note (`obsidianCreate toggle`), `s` vault status, `t` tag tree
(via `qs.notify`). Purely IPC — no window guards, unlike the dofus service: a
capture hotkey is global.

## Gotchas

- **The Obsidian CLI is headless.** `obsidian <cmd>` needs no running app window;
  `pgrep -x obsidian` will be empty yet `templater:create-from-template` and
  `property:set` succeed. `create` only prints a note when the app is closed —
  index-notes callout blocks are appended the next time the app opens the vault.
- **`property:set` writes tags as a YAML block list** (`tags:\n  - a\n  - b`), not
  inline. The store scanner must parse that format; a naive `tags: [...]` parser
  silently drops all but the first tag.
- **`templater:create-from-template`** is the working path; the core Templates
  plugin is disabled and `obsidian create template=…` fails. Templater runs with
  `trigger_on_file_creation_mode: "none"` so the script drives everything.
- **Stub notes.** A topic placeholder may exist as a bare stub (no tags, no
  `note_type`); `ensure` adopts it by adding the `meta_idx` tag rather than
  creating a duplicate index note.
- **`--dry-run` before writing**; the chain inference touches ancestor notes, so
  inspect the plan first.
- **`qs ipc call <target> show` is a no-op.** `ipc` subcommand names (`show`,
  `prop`, `wait`, `listen`) shadow an IPC function with the same name, so the
  CLI prints the target help instead of invoking it. Always use
  `qs ipc call -- <target> <fn>` (the hypr `qs.lua` helper does this) or name
  the function differently. Affected repo-wide: every `show()` IpcHandler
  function.

## Extending — "do more with the tag data"

The store is reactive in the shell via `ObsidianVault` (a `Store` with
`watchChanges`), so any new widget just reads `ObsidianVault.topics` /
`ObsidianVault.tree` / `ObsidianVault.noteCount` and updates live when the
script rebuilds the file. Ideas that fit the existing primitives without new
bridge code: a tag-tree browser panel, a per-topic leaf count in the bar
(`PollText`/`Store`), or a "recent topics" chip row. The vault stays
authoritative and the script stays the only writer — the UI only _renders_ and
shells `create`/`ensure-topic` on request. hypr's `store.lua` (mtime-cached)
can read the same file for keybinds that need tag data.

# Bar

One top bar per monitor (except the excluded portrait panel). Four isles:

## Isle registry (LEO-420)

Every dockable isle carries a stable id — the vocabulary hypr's scene
documents speak when they publish a placement into the `geometry` store's
`docks[screen][isleId]` map (see [`../../services/DockPlacement.js`](../../services/DockPlacement.js)
for the placement contract this repo consumes it against). Adding an isle to
the bar means adding its id here in the same change.

| id               | isle                                                 |
| ---------------- | ---------------------------------------------------- |
| `bar.workspaces` | left isle — workspaces, submap indicator, group chip |
| `dofus.roster`   | Dofus roster (gaming workspace only)                 |
| `bar.center`     | centre isle — media, brightness, volume              |
| `bar.clock`      | right isle — clock, mode pill, calendar entry        |

An isle with no published dock document keeps its resting (today's static)
position — the hypr side does not need to publish every isle at once. A
published document that sets the isle to `false` hides it entirely.

The bar itself is now one transparent, click-through overlay `PanelWindow`
per monitor, anchored on all four sides with `exclusiveZone: 0` (LEO-420 §2):
a docked isle must reserve no space of its own, since the gutter it sits in
is already carved by the scene's own gaps — a second reservation here would
feed back into the tiling. Only the isles' own bounding rects are clickable
(`mask: Region { Region { item: ... } ... }` in `Bar.qml`); everywhere else on
the overlay passes clicks through to the window underneath.

- **left** — where am I: workspaces, submap indicator, group chip, layout glyph.
  The workspace pill's order and icons come from the hyprfocus declaration,
  never a hardcoded list: each monitor shows EVERY scene the active mode
  admits for that monitor's role (`base.scenes[name].icon`, declared order
  from `modes.<id>.scenes`), plus any other real workspace that still holds
  windows, appended after. Entering a mode launches nothing: an admitted
  scene with no windows shows **dormant** (dimmed, `Theme.c.overlay0` +
  reduced opacity — synthesized even when Hyprland has not created its
  workspace yet, so the row is there from mode entry, not just after a
  window appears), one with at least one window shows **playing**
  (`Theme.c.lavender`), and the one active on this monitor is **focused**
  (tinted icon, `Theme.accent`) regardless of whether it is also playing.
  Dormant is a display state only — the workspace is still admitted and its
  row still dispatches `name:<scene>` on click, focusing or creating it. The
  active workspace is read off Hyprland's raw `workspace`/`workspacev2`/
  `focusedmon` events directly rather than the monitor's cached
  `activeWorkspace`, which was observed to lag on a same-monitor switch —
  see `Workspaces.qml`'s `_activeWsName` header for the socket2 evidence.
  See [`WorkspaceSwitch.js`](WorkspaceSwitch.js) for the pure logic
  (`barWorkspaces`, `rowState`, `roleForScreen`, `activeName`) and its
  header for how a monitor's primary/secondary role is read off the
  `geometry` store's `roles` map — hypr's `conf/host.lua` publishes it
  explicitly next to the per-output gaps, so `roleForScreen` reads a real
  fact instead of guessing from the gaps map's key order. An unconnected or
  ignored output is simply absent from the map, never defaulted onto a
  role.
- **Dofus** — appears only on the `gaming` workspace while Dofus clients are
  present. Mirrors the Hyprland group order from `DofusWindows`, highlights the
  focused member, focuses on click, and exposes the swap-detector controls from
  `DofusSwap` (calibrate, learn per character, run/stop). It is a bar isle, not
  attached to any window or Hyprland group.
- **centre** — what's playing / what to adjust: media, brightness, volume.
- **right** — when is it / what's the mood: clock, mode pill, calendar entry.
  The mode pill (`ModePill.qml`) shows the active mode's declared name
  (`hyprfocus.json`'s `modes.<id>.name`; "Work" at rest — `work` is the
  default/resting mode) tinted by `Theme.accent`, which already
  tracks the mode's declared `presentation.accent_role`. Clicking it opens
  `MoodPanel.qml`, whose mode picker offers only the declaration's
  non-`hidden` modes (`Hyprfocus.ids()`) — `neutral` stays reachable solely
  as the hypr modes submap's recovery mode, never as a picker choice and
  never a fallback a lapsed timed mode settles to (see `previous` in
  `schemas/focus.schema.json`), so the resting pill can say "Work" honestly
  without inviting anyone back to `neutral`. Its palette lease field uses
  `modules/common/PalettePicker.qml` (a wrapping swatch grid, readable at any
  palette count) paired with `modules/common/HoverDetail.qml` (a fixed-height
  slot for hover-preview text, so pointing at a chip never resizes the
  panel) — both components are shell-wide, not mood-panel-specific, for the
  theme panel to reuse.

Autohide follows `Hyprfocus.current.presentation.bar_autohide` — the
declaration's own per-mode flag, not the retired `deep`/`game` mode ids. A
SUPER-tap IPC reveal and a thin hot strip at the top edge both wake it.

### Side insets (LEO-340 + scene alignment)

Each bar's left/right insets follow the tiled outer gap of its own screen via
[`services/BarGaps.js`](../../services/BarGaps.js). A scene opts in with
`bar_follows_scene_gaps`; without it the bar rests at the monitor's published
base gap:

1. **Subscribed (opt-in)** — the workspace active on this screen declares
   `bar_follows_scene_gaps: true`; the bar takes the value hyprland resolved
   for that workspace and published to the `geometry` store's `workspaces` map
   (keyed by `default_name` == scene name). That value is the distance from
   the monitor edge to the scene's outermost **visible** window, already
   whole: the engine's own gap ladder — scene `gaps_out` → host workspace-spec
   → live global — folded the way the scene's own layout folds a gap, PLUS the
   workspace rule's `gaps_out` (which the compositor strips from the work area
   before the layout runs) and, on any side the layout left inset, the rule's
   `gaps_in` and the window border. Hyprland folds all of it in
   `hypr/lib/geometry.lua`'s `resolved_gaps`; the bar only reads it — no
   mirroring, no fall-through, no guess, no addition. Until the publish lands
   (an edit that just arrived, or a stale store) the bar rests on the default
   rather than inventing a gap.
2. **Resting** — the monitor's published base gap (`geometry.monitors`, LEO-340),
   then `Theme.barInset * 2`, when the store carries nothing for the monitor.
   An explicit `0` is a real gap, never a fallback signal.

Everything refreshes live, so nothing here ever needs a shell reload: scene
edits re-emit through the `hyprfocus` Store's FileView watchChanges, and the
resolved value follows through the `geometry` store's watchChanges when the
hyprland side re-publishes (at config load from `conf/host.lua`, and on a
scene edit from `hypr/scene/spec.lua`'s first re-read of the declaration). A
workspace switch arrives as the compositor's own
`workspace`/`workspacev2`/`focusedmon` events, which the bar Scope turns into a
per-screen active scene name — the same raw-event source `Workspaces.qml`
root-causes in its `_activeWsName` header.

The Dofus isle uses `DofusWindows.windows` as its membership source and
`DofusSwap` for detector state; it does not rebuild group membership or swap
state.

Bar-triggered panels (projects, calendar, mood, notifications) open on the bar
instance that triggered them. IPC/keybind-triggered panels resolve the active
monitor through [`services/PanelBus.qml`](../services/PanelBus.md).

See [`services/DofusWindows.qml`](../services/DofusWindows.qml) and
[`services/DofusSwap.qml`](../services/DofusSwap.qml) for the data contracts.

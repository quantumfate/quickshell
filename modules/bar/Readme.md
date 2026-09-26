# Bar

One top bar per monitor (except the excluded portrait panel). Five isles:

## Isle registry (LEO-420)

Every dockable isle carries a stable id — the vocabulary hypr's scene
documents speak when they publish a placement into the `geometry` store's
`docks[screen][isleId]` map (see [`../../services/DockPlacement.js`](../../services/DockPlacement.js)
for the placement contract this repo consumes it against). Adding an isle to
the bar means adding its id here in the same change.

| id               | isle                                                                |
| ---------------- | ------------------------------------------------------------------- |
| `bar.workspaces` | left isle — workspaces, scene, submap indicator                     |
| `dofus.roster`   | Dofus roster (gaming workspace only)                                |
| `bar.center`     | centre isle — media, brightness, volume                             |
| `bar.projects`   | right of centre — open projects, and the current project's tab chip |
| `bar.clock`      | right isle — mode pill, clock, notifications entry, power button    |

### Who reserves the top strip

The bar is two layer surfaces and exactly one of them reserves space at a
time: the full-screen overlay while this screen has no placed dock, the thin
strip once it does. Both ask for `Theme.barReserved`, so the handover is meant
to be invisible.

It was not, because the strip asked for its zone at `implicitHeight: 0` — a
layer surface's exclusive zone comes with its own size, so the compositor had
nothing to reserve and the reservation disappeared the moment a scene's docks
arrived. Every tile jumped UP by the bar's height, and the isles, which follow
the published tile geometry, jumped after them: the "bump" on a workspace
swap. Measured in the nested instance with the real bar attached — tile
`y 65 -> 14` across one round trip, `y 65 -> 65` with the strip sized
(`tests/e2e/scenarios/99_bar_reserve_bump.sh` in the hypr repo).

### Reading the bar's own state

```sh
qs -c quantumfate ipc call bar report
```

One line per screen: the scene it believes it is on, the event-cached value
beside it, how many projects the model holds and how many are on that screen,
and the resolved mode of every published dock. Diagnosing "the widget is not
showing" otherwise means guessing at three layers at once — what the desk
published, how the shell resolved it, and what the model found — with a shell
restart between guesses.

### Which scene a widget describes

A scene-scoped widget asks `PanelBus.sceneOn(screenName)`, which reads what
the compositor **published** (`geometry.scenes[screen]`, written by the same
layout pass that places the windows). The event-fed `sceneByScreen` map is
the fallback only: it goes stale the moment an event is missed — measured, a
screen standing on `code-deck` read as `loose`, so every scene-scoped widget
filtered itself down to nothing — and it reports the deck's hold workspace
while a park is in flight.

**A binding tracks properties, not function calls.** `shown: projectsOn(scene)`
evaluated once, while the model was still empty moments after startup,
registered no dependency on `ProjectWindows.projects`, and never ran again —
the widget stayed empty for the life of the shell while the same call made by
hand returned both projects. Read the property inside the binding
(`const all = ProjectWindows.projects`) so the dependency is real.

### Hopping between scenes

An isle's docked position comes from the scene on screen, and two scenes gap
their tiles differently — so a workspace hop changes every docked isle's
coordinates at once. That transition is a **cut, not a slide**: animating it
made every hop end with the isles chasing the new workspace after it had
already drawn. Within one scene, a geometry edit still animates, so a live
gap change stays smooth.

### Projects and tabs

`OpenProjects` names every project with windows open and marks the one you
are in; `ProjectTabs` names that project's tabs and marks the one the
keyboard is in. Both read `ProjectWindows`, which reads the compositor — a
project exists as long as its windows do, and so does a tab.

The tab strip exists because the compositor's groupbar is off (hyprrepo
`hypr/conf.lua`): Hyprland reserves the strip's height inside the group's own
box, so every group and ungroup resized the tile and the isles that follow
the published tile geometry jumped with it. A project is several terminals in
one tile, so without a strip nothing says which one you are typing into.
Tabs read in the template's order, the same order `mod+j`/`mod+k` walk
(hyprrepo `docs/declared-groups.md`); clicking one focuses that window.

The isle docks at the **top-right of the project column** — the scene
declares `docks["bar.projects"] = { at: "top-right", of: "block:N" }` — so
the strip sits over the group it describes rather than across the desk from
it.

### Workspaces

The row is DOTS, one per scene the active mode admits for this monitor, in
declared order: the active one an accent capsule, a scene with windows a
lavender dot, an admitted-but-empty one a smaller dim dot, urgent red. The
scenes' own glyphs moved to `ScenePill` next to it — a row of glyphs beside a
pill drawing the same glyph asked the reader to identify the same thing twice
in two alphabets. The row answers "where am I among how many"; the pill
answers "what is this place". Hovering a dot still names its scene.

### Submap

`SubmapIndicator` sits last in the left isle and says what the keyboard is
doing: a hairline rule (the same divider the project strip uses between a
project and its tabs), a keyboard glyph, and the submap's name. It draws
nothing at root, so the bar never carries dead state.

Its height is its CONTENT's, never `Theme.barHeight`: an isle is as tall as
its tallest child, so a full-bar-height indicator made the whole island grow
when a submap opened and shrink when it closed. The glyph replaced a bold
"map" label for the same reason — one character's width instead of three.

### Scene

`ScenePill` names the scene this screen is standing in, with the scene's own
declared `icon` in front of the name — a bare glyph against a word reads as
that word's icon, which is what the declaration's `icon` is for; the
workspace row beside it draws its glyphs in pills, so the two do not read as
the same kind of thing. A scene with no declared icon shows its name alone.
A scene owns its workspace, its layout and its binding trees,
so it is the answer to why the keys and the tiling behave the way they do
right now — the workspace row beside it says WHERE you are among the row,
this says WHAT that place is. Per screen, never per desk: a mode places
several scenes on several monitors at once.

It reads `PanelBus.sceneByScreen`, which is fed by the compositor's raw
workspace events AND seeded once at startup from `hyprctl monitors` — the
map is event-driven, so a shell that just started has missed every event and
would otherwise render nothing until the first workspace change. A workspace
no scene claims says so rather than blanking.

### Open projects

`OpenProjects` is the way BACK to a project that is already running: it lists
them, marks the focused one, and a click goes there. `,proj.sh pick` offers
only the projects that are NOT open, so the bar and the picker never present
the same choice twice — which makes this the switcher rather than a
decoration. It shows nothing when no project is running.

It reads `ProjectWindows`, which groups `hyprctl clients -j` by the
`Proj-<name>` class, because a project exists exactly as long as its windows
do and there is no state file that could disagree. Not to be confused with
`ProjectsPill`, which is repo HEALTH (branch, dirty counts) over the projects
store; this one is about what is on screen now.

An isle with no published dock document keeps its resting (today's static)
position — the hypr side does not need to publish every isle at once. A
published document that sets the isle to `false` hides it entirely.

Dock placement rejects incomplete hook output and clamps every resolved isle to
the monitor bounds. Empty scenes and monitor-startup geometry therefore use a
safe on-screen position rather than briefly placing a bar outside the output.

### The anchor contract (bars, panels, notifications)

Every floating surface has exactly one declared anchor source, and nothing
anchors implicitly:

- **Bar isles** dock only where the active scene's `docks` declaration names a
  target — a live block, slot or class, or `of = "screen"` on purpose. A
  target that is absent or refused means the isle **rests**; the old implicit
  "same anchor on screen" ladder rung is gone (hypr `docs/scenes.md` "Docks"),
  so two isles on one workspace can no longer disagree about their failure
  mode. Declaring a blanket screen `fallback` on every isle reintroduces
  exactly that: two isles land on one screen anchor, one takes it and the
  other rests, and both move on every window event. **Resting is the bar's
  own row** — the one position that does not follow a window — so each isle's
  resting seat is computed from the row alone, never from a neighbour's live
  `x`: the roster used to ride the left isle's live edge and the project strip
  the clock's, which dragged a resting isle clean across the desk whenever
  its neighbour docked to a window over there.

  An isle is **hidden** only when the screen's published dock map exists and
  does not name it (the scene declining it) or names it `false`. No map at
  all is a screen the desk has not published for yet — a shell that just
  started, a monitor mid-hotplug, a swept pass — and every isle rests;
  reading that as a refusal hid the tab strip on the very scenes that declare
  it.

- **Panels** (projects, calendar, mood, notification centre) anchor to the
  published dock document of the isle that opened them (`PanelBus`
  `anchorIsleId`), so they track a live dock move. An isle that is resting has
  no document, and the panel falls back to the click coordinate — which is on
  the isle, because the click opened it.
- **Toasts** anchor to the active mood's `notifications.position` policy
  (`NotifyPlacement.js`), framed by the same bar-gap resolution the isles
  read — never to a bar widget's live position, so a policy change moves the
  stack without touching the bar.

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
  row still switches or creates it on click. A dot's click runs
  `,desk.sh switch <this bar's screen> <row name>` (one seat, cross-repo: the
  dot's OWN screen, never the keyboard's — a click only ever changes the
  monitor it was clicked on, it never pulls the keyboard across). This
  replaced `Hyprland.dispatch('hl.dsp.workspace(...)')`, which has errored on
  every click since 2026-09-14: on this Hyprland build `hl.dsp.workspace` is a
  table (`change_id move rename swap_monitors toggle_special`), not callable —
  every dot click silently no-opped. See
  [`WorkspaceSwitch.js`](WorkspaceSwitch.js)'s `switchCommand` for the pure
  argv builder (refuses a name `,desk.sh` itself would reject) and
  `WorkspaceSwitcher.qml`'s `sendCommand` for the overlay's seat-scoped
  `switch`/`send` seam. The active workspace is read off Hyprland's raw
  `workspace`/`workspacev2`/`focusedmon` events directly rather than the
  monitor's cached `activeWorkspace`, which was observed to lag on a
  same-monitor switch — see `Workspaces.qml`'s `_activeWsName` header for the
  socket2 evidence. An event is attributed to a screen only when it names
  that screen's monitor explicitly; the old "no monitor named, so it must be
  the focused one" fallback read `monitors[].focused`, which follows the
  POINTER on this desk, not the keyboard — dropped with the same one-seat
  change. `PanelBus.sceneOn(screen)` (the layout's own published scene map)
  is the highlight's fallback when no event has named this screen's row yet.
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
- **right** — what's the mood / when is it / what came in / the way out
  (LEO-425), in this order: mode pill, clock, notifications entry, power
  button. The mode pill (`ModePill.qml`) leads: it shows the active mode's
  declared icon and name (`hyprfocus.json`'s `modes.<id>.icon` / `.name`;
  "Work" at rest — `work` is the default/resting mode) tinted by
  `Theme.accent`, which already tracks the mode's declared
  `presentation.accent_role`. Clicking it opens `MoodPanel.qml`, whose mode
  picker offers only the declaration's non-`hidden` modes (`Hyprfocus.ids()`)
  — `neutral` stays reachable solely as the hypr modes submap's recovery
  mode, never as a picker choice and never a fallback a lapsed timed mode
  settles to (see `previous` in `schemas/focus.schema.json`), so the resting
  pill can say "Work" honestly without inviting anyone back to `neutral`.
  Its palette lease field uses `modules/common/PalettePicker.qml` (a wrapping
  swatch grid, readable at any palette count) paired with
  `modules/common/HoverDetail.qml` (a fixed-height slot for hover-preview
  text, so pointing at a chip never resizes the panel) — both components are
  shell-wide, not mood-panel-specific, for the theme panel to reuse. The
  clock (`Clock.qml`) carries date + time with today's calendar entry count
  folded in and opens `CalendarPanel.qml` on click — the standalone date
  chip is gone. The notifications entry (`NotifIndicator.qml`) reflects DND
  and the unread count and opens the notification center; the power button
  (`Wlogout.qml`) opens the logout menu. Both moved here from SysPanel's
  bottom row.

Autohide follows `Hyprfocus.current.presentation.bar_autohide` — the
declaration's own per-mode flag, not the retired `deep`/`game` mode ids. A
SUPER-tap IPC reveal and a thin hot strip at the top edge both wake it.

### Resting: bars never dance (LEO-340, LEO cross-repo)

An isle that is not docked sits at a fixed position that depends on its
**monitor only** — never the scene, its gaps, or what was last published.
[`services/BarGaps.js`](../../services/BarGaps.js)'s `insetFor` is that rule:
the monitor's published base gap (`geometry.monitors`, LEO-340), else
`Theme.barInset * 2` when the store carries nothing for the monitor. An
explicit `0` is a real gap, never a fallback signal. Every bar instance uses
the same isle order, the same resting slots (each computed from the row
alone, e.g. `restingX: bar.edgeInset.left` or a neighbour's own resting seat
— never a neighbour's live, docked position), and the same reserve strip; the
only per-monitor inputs anywhere in `Bar.qml` are the screen's own size and
its base gap.

Docked isles are unaffected: a scene's `docks` declaration still places them,
cached per monitor+scene in hypr's `dock_publish.lua`, so a hop between
scenes still moves a docked isle — resting isles just do not follow it.

This used to also carry a per-scene opt-in, `bar_follows_scene_gaps`: an
isle whose active scene set the flag rode hyprland's resolved distance to
that workspace's outermost visible window instead of resting, plus a memory
of the last published value to paper over that path's publish lag (a
workspace switch would otherwise snap every resting isle to the bar's
default and slide it back a frame later). It is retired — every one of the
11 shipped scenes had set it, so it was never really an opt-in, just a bar
that redrew itself on every scene gap change, which is exactly the "dance"
this rule now rules out. The schema still accepts the field (marked
deprecated) so a live store written before the retirement stays valid; a
fresh seed no longer writes it, and quickshell no longer reads it anywhere.
Toasts and NotificationCenter, the two surfaces that used to read the
scene's four-side gap for their own placement, now use the same monitor-only
resting inset as the bar (see "Notifications" below) — a later phase
(`SurfacePlacement.js`, published work areas) replaces that with real
per-scene coordinates.

Everything refreshes live, so nothing here ever needs a shell reload: the
monitor's base gap follows through the `geometry` store's watchChanges.

The Dofus isle uses `DofusWindows.windows` as its membership source and
`DofusSwap` for detector state; it does not rebuild group membership or swap
state. It is **content, not a card**: the bar already wraps every isle in a
`Surface` (`Island`, below), so the roster is a bare `RowLayout` that inherits
that material, padding, and height like `Workspaces` and the clock — it used to
draw a second `Surface` inside the first, a frame within a frame. Its active-tab
highlight comes from the compositor's live `activewindowv2` event, resolved by
[`services/DofusFocus.js`](../services/DofusFocus.js); see
[`services/DofusWindows.md`](../services/DofusWindows.md) for that contract.

Bar-triggered panels (projects, calendar, mood, notifications) open on the bar
instance that triggered them and derive their anchor from the isle's published
dock document so they stay aligned with the isle even when it moves. Pills pass
their isle id (`bar.workspaces` or `bar.clock`) to `PanelBus.toggle`. The
notification history panel (`NotificationCenter.qml`) also uses `bar.clock` so
its right edge lines up with the live right-isle position. All folding panels
hang `Theme.space.md` below the bar reserve so they read as separate surfaces,
not an extension of the strip. IPC/keybind-triggered panels resolve the active
monitor through [`services/PanelBus.qml`](../services/PanelBus.md) and fall back
to the click coordinate.

## Notifications (LEO-424)

Two surfaces over one daemon (`services/Notify.qml`, the freedesktop
`NotificationServer`):

- **Toasts** (`Toasts.qml`) — the live queue. Placement is the active mood's
  `notifications.position`, resolved by
  [`services/NotifyPlacement.js`](../../services/NotifyPlacement.js):
  top-centre under the bar by default, any edge/corner a mood names, always on
  the seat's monitor. The stack frames itself with the bar's own RESTING gap
  resolution ([`services/BarGaps.js`](../../services/BarGaps.js)): the sides
  are the bar's monitor-only insets and the vertical edge is the bar's
  reserved strip, so the stack sits exactly where the bar sits on every scene
  — the scene-gap opt-in this used to also ride is retired (see "Resting:
  bars never dance" above). It renders on the **Top** layer, with the
  bar, so the transition veil and the detail panels (Overlay) always cover
  it. Cards enter with a fade + slide and collapse on leave, gated by
  `Theme.motion` (the mood's `motion_energy`; `instant` collapses every
  duration to zero). Hovering a card pauses its countdown line and `Notify`'s
  expiry timer for that toast, so it cannot vanish mid-read; the surface
  stays mapped until the last exit finishes. At most four cards show, with a
  `+N more` pill that opens the history. A toast and its history entry both
  read `services/NotifyCards.js`, so they name the same resolved source.
- **History** (`NotificationCenter.qml`) — the persisted, routed log. Slides in
  from the right edge with the same motion contract; the panel stays mapped
  through the exit before unmapping.

Both bind their `screen` through `PanelBus.screenObject(...)`. The history
panel uses the same monitor-only resting inset as the bar (`BarGaps.insetFor`
— the scene's resolved gaps it used to read are retired, see above): its
right edge is inset from the bar's right edge by a small gap, its top is
dropped below the bar by `Theme.space.md`, and its width is capped at
`Theme.historyWidth` so it cannot span the screen.

See [`services/DofusWindows.qml`](../services/DofusWindows.qml) and
[`services/DofusSwap.qml`](../services/DofusSwap.qml) for the data contracts.

// Workspaces bar module: this monitor's row of scenes, in the active
// hyprfocus mode's declared order, each drawn as a DOT. Every scene the
// active mode admits is shown, whether or not it has a live Hyprland
// workspace yet — WorkspaceSwitch.rowState() names each row's play state:
//   focused → accent, and the only filled dot in the row
//   playing → lavender (has windows)
//   dormant → overlay0, smaller and dimmer (admitted, no windows — may not
//             even exist in Hyprland yet; its key still focuses/creates it)
//   urgent  → red, regardless of state
//
// Dots, not the scenes' own glyphs: `ScenePill` next to this row now draws
// the CURRENT scene's icon beside its name, and a row of glyphs beside it
// asked the reader to identify the same thing twice in two different
// alphabets. The row's question is "where am I among how many", which is
// exactly what a row of dots answers; the pill answers "what is this place".
// The glyphs still live in the declaration and `WorkspaceSwitch.iconFor`
// still reads them for the switcher and the pill.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../services"   // Theme, Hyprfocus
import "WorkspaceSwitch.js" as WorkspaceSwitch

Rectangle {
    id: root

    // The monitor this bar instance lives on; filters which workspaces show.
    required property var screen
    readonly property var _monitor: Hyprland.monitorFor(screen)

    // LEO-368: hypr's conf/host.lua publishes the primary/secondary role map
    // in the same `geometry` store LEO-340 already reads (see
    // WorkspaceSwitch.roleForScreen's header).
    Store { id: _geometry; name: "geometry" }
    readonly property string _role: WorkspaceSwitch.roleForScreen(_geometry.data.roles, root.screen.name)

    // Icons and order come from the hyprfocus declaration (LEO-343): no
    // hardcoded workspace name list or icon map here. This monitor's rows are
    // EVERY scene the active mode admits for `_role`, in declared order —
    // dormant ones included, synthesized even when Hyprland has not created
    // their workspace yet (LEO-373) — plus any other real workspace that
    // still holds windows. Hyprland's list is creation order and named
    // workspaces carry negative auto ids, so the bar must not sort by id.
    // `_tick` re-evaluates on every compositor event.
    property int _tick: 0
    Connections { target: Hyprland; function onRawEvent(e) { root._tick++; } }
    readonly property var _sorted: {
        root._tick; // dependency
        // Two lists, because they answer two different questions.
        //
        // `live` is every real workspace, unfiltered: it is what each row's
        // live state (occupied, urgent, toplevels) is read from, and rows are
        // matched to it BY NAME, which is unique. Filtering it by monitor
        // first was measured to lose that state entirely -- a workspace's own
        // `monitor` comes back unresolved on this build (`w.monitor?.name`
        // was undefined for eleven of twelve workspaces, live 2026-09-25), so
        // both the identity test and a name test drop nearly everything and
        // every row reads as empty.
        //
        // `mine` is the monitor-scoped one, and its only job is the tail of
        // the row: workspaces this mode does not admit that still hold
        // windows. An unresolved monitor simply keeps a workspace out of that
        // tail -- the admitted rows come from the declaration and do not
        // depend on it.
        const monitorName = root._monitor?.name ?? root.screen.name;
        const live = (Hyprland.workspaces?.values ?? [])
            .filter(w => w.id > 0 || !w.name.startsWith("special:"));
        const all = live.filter(w =>
            w.monitor === root._monitor || (w.monitor?.name ?? "") === monitorName);
        const plain = all.map(w => ({
            id: w.id,
            name: w.name,
            occupied: (w.toplevels?.values?.length ?? 0) > 0
        }));
        const order = WorkspaceSwitch.barWorkspaces(Hyprfocus.data, Hyprfocus.mode, root._role, plain);
        // Swap each row's plain stand-in for its live Hyprland object,
        // matched by name (see WorkspaceSwitch.attachLive's header —
        // LEO-344: matching by `id` here collapsed distinct named
        // workspaces onto one another). A synthesized row (id: null — an
        // admitted scene with no live Hyprland workspace) has no live
        // counterpart and passes through as-is; the delegate below already
        // treats an absent `.toplevels`/`.active`/`.urgent` as
        // empty/false/false.
        return WorkspaceSwitch.attachLive(order, live);
    }

    // This monitor's actually-displayed workspace, by NAME. Third bug in
    // this family (after workspace ids going away — see attachLive()'s
    // header). `HyprlandMonitor.activeWorkspace.name` was the prior source,
    // recomputed via `_tick` on every raw event, but that still read stale
    // on a same-monitor switch until a monitor-crossing focus change also
    // fired: bumping `_tick` reruns the binding, but the cached
    // `activeWorkspace` reference Quickshell hands back for the monitor was
    // itself not refreshed yet, so re-reading it early just re-read the old
    // value.
    //
    // Root-caused by reading Hyprland's own socket2 emission for this exact
    // build (src/output/Monitor.cpp, src/desktop/state/FocusState.cpp,
    // commit 92b82c0c1 of hyprland-git — a live probe against a real
    // instance wasn't possible: this host's one DRM device is held
    // exclusively by the running Hyprland session, and Aquamarine's headless
    // backend refuses to substitute once a real DRM/Wayland display exists
    // to fail to nest under, so a second `Hyprland` process here reliably
    // aborts with `CBackend::create() failed!`; a plain socket2 watch would
    // also have needed the user to drive workspace switches on their live
    // session, which risked disrupting it):
    //   - `workspace`/`workspacev2` fire on EVERY workspace change on a
    //     monitor, same-monitor switch or cross-monitor alike — posted
    //     unconditionally from `CMonitor::changeWorkspace`.
    //   - `focusedmon` fires ONLY when the globally-focused monitor itself
    //     changes and carries the workspace NAME.
    //   - `focusedmonv2` fires for the same monitor change but carries a
    //     workspace ID, which must be resolved to a name before the bar can
    //     use it (Hyprland IPC: MONNAME,WORKSPACEID).
    // That lines up exactly with the observed staleness, so this reads the
    // active workspace off the raw event payload directly rather than off
    // the monitor's cached reference — cross-checked against that
    // workspace's own `.monitor` field (independently fresh; `_sorted`
    // above already relies on it) so an event for another monitor is
    // ignored. `focusedmonv2` is handled too, matched by monitor name
    // against `root.screen.name` and resolved through `Hyprland.workspaces`,
    // as a second source for a focus change that crosses monitors without
    // either monitor's active workspace changing.
    property string _activeWsName: root._monitor?.activeWorkspace?.name ?? ""
    Connections {
        target: Hyprland
        function _resolveId(id) {
            const values = Hyprland.workspaces?.values ?? [];
            return values.find(w => w.id === id && w.monitor?.name === root.screen.name)
                || values.find(w => w.id === id);
        }
        function onRawEvent(event) {
            const data = event.data ?? "";
            const comma = data.indexOf(",");
            let name = null;
            if (event.name === "workspace") {
                // payload: WORKSPACENAME
                name = data;
            } else if (event.name === "workspacev2") {
                // payload: WORKSPACEID,WORKSPACENAME
                if (comma === -1) return;
                name = data.slice(comma + 1);
            } else if (event.name === "focusedmon") {
                // payload: MONNAME,WORKSPACENAME
                if (comma === -1) return;
                if (data.slice(0, comma) !== root.screen.name) return;
                name = data.slice(comma + 1);
            } else if (event.name === "focusedmonv2") {
                // payload: MONNAME,WORKSPACEID
                if (comma === -1) return;
                if (data.slice(0, comma) !== root.screen.name) return;
                const id = parseInt(data.slice(comma + 1), 10);
                if (isNaN(id)) return;
                name = _resolveId(id)?.name ?? "";
                if (!name) return;
            }
            if (!name) return;
            // For workspace events the payload does not name the monitor, so
            // match by the workspace's own `.monitor` field; only when the
            // model has not caught up yet fall back to "this event is for the
            // focused monitor", which is what a bare `workspace` event means.
            if (event.name === "workspace" || event.name === "workspacev2") {
                const live = (Hyprland.workspaces?.values ?? []).find(w => w.name === name);
                const onThisScreen = live?.monitor?.name !== undefined
                    ? live.monitor.name === root.screen.name
                    : root._monitor?.focused ?? false;
                if (!onThisScreen) return;
            }
            root._activeWsName = name;
        }
    }

    // A mode switch changes which rows exist without necessarily emitting a
    // workspace event (the target workspace may already be active on this
    // monitor). Re-seed the active workspace name from the monitor's own
    // reference so the highlight updates in the same frame as the row list.
    Connections {
        target: Hyprfocus
        function onModeChanged() {
            root._activeWsName = root._monitor?.activeWorkspace?.name ?? "";
        }
    }

    // Which row is the focused one, and the rule is that it must BE one of
    // this screen's rows.
    //
    // Two sources, both of which lie in their own way. `_activeWsName` is
    // event-fed: it starts empty (a shell restart has missed every event, and
    // the monitor's own `activeWorkspace` can still be unresolved), and its
    // raw-event handler falls back to "this event is for the focused monitor"
    // when a workspace's `monitor.name` comes back undefined — which this
    // build does for nearly every workspace. Measured: an event for `1`, a
    // workspace on the ignored panel, set BOTH bars' active name to `1`, and
    // since no row is called that, every dot read as unfocused.
    //
    // The published scene map is the layout's own truth (written by the pass
    // that places the windows) and is what the scene pill beside this row
    // reads. So: an event wins while it names a row this screen actually has,
    // the publish answers otherwise, and a name belonging to neither leaves
    // the row unhighlighted rather than highlighting the wrong thing.
    readonly property string activeName: {
        const rows = root._sorted || [];
        const has = (name) => name !== "" && rows.some(r => r && r.name === name);
        if (has(root._activeWsName)) return root._activeWsName;
        const published = PanelBus.sceneOn(root.screen?.name ?? "");
        return has(published) ? published : "";
    }

    color: "transparent"
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.sm

        Repeater {
            model: root._sorted

            // Focus is shown by tinting the ICON accent, not by a pill: a
            // filled/bordered background made the active state read as a
            // separate widget rather than "this one scene, highlighted".
            // occupied/dormant still get their own icon-colour tiers below.
            delegate: Rectangle {
                id: wsDelegate
                required property var modelData
                // Name match against root._activeWsName, not modelData.active
                // (see root._activeWsName's header — that flag lags on this
                // Hyprland build).
                readonly property bool active: root.activeName !== "" && modelData.name === root.activeName
                readonly property bool occupied: (modelData.toplevels?.values?.length ?? 0) > 0
                readonly property bool urgent: modelData.urgent ?? false
                // rowState() (tests/workspaceswitch.test.js) names the row's
                // play state; a synthesized row (no live workspace) reads as
                // dormant the same as an existing, empty one.
                readonly property string state: WorkspaceSwitch.rowState({ active: active, occupied: occupied })
                readonly property bool dormant: state === "dormant"

                // The hit target stays a comfortable square even though the
                // dot inside it is small: a 6px click target is not one.
                implicitWidth: Theme.barFontSize
                implicitHeight: Theme.barFontSize
                color: "transparent"

                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    // The active dot is the largest, a dormant one the
                    // smallest: size carries the state as well as colour, so
                    // the row still reads at a glance in a palette where the
                    // tiers are close together.
                    // The active row is a CAPSULE, not a bigger dot: two
                    // colour tiers a few steps apart are hard to tell apart
                    // at 6px, and shape survives any palette. Everything else
                    // stays a dot, dormant ones smaller.
                    implicitWidth: wsDelegate.active ? Theme.space.sm * 3 : dot.implicitHeight
                    implicitHeight: wsDelegate.dormant ? Theme.space.xs : Theme.space.sm
                    width: dot.implicitWidth
                    height: dot.implicitHeight
                    radius: height / 2
                    // Dormant rows read via the same dim tier a fresh/idle
                    // workspace already used (overlay0) — LEO-373 just widens
                    // who reaches that state to admitted-but-windowless rows,
                    // synthesized or real, rather than adding a new colour.
                    color: wsDelegate.urgent ? Theme.c.red
                         : wsDelegate.active ? Theme.accent
                         : ws.hovered ? Theme.c.text
                         : wsDelegate.occupied ? Theme.c.lavender
                         : Theme.c.overlay0
                    opacity: wsDelegate.dormant ? 0.7 : 1.0

                    Behavior on width { NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.ease } }
                    Behavior on color { ColorAnimation { duration: Theme.motion.fast } }
                }

                HoverTip {
                    shown: ws.hovered
                    screenName: root.screen.name
                    // The row lost its labels with the glyphs, so hovering is
                    // where the scene's name still lives.
                    text: wsDelegate.modelData.name
                }

                HoverHandler { id: ws }
                // Dispatched directly, not via modelData.activate(): a named
                // workspace's auto id is an internal handle, so both are
                // spoken through WorkspaceSwitch.selector().
                TapHandler {
                    onTapped: Hyprland.dispatch('hl.dsp.workspace("' + WorkspaceSwitch.selector(wsDelegate.modelData) + '")')
                }
            }
        }
    }
}


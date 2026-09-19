// Workspaces bar module: a surface pill of per-workspace buttons for this
// monitor, in the active hyprfocus mode's declared order, each shown as a
// Nerd Font icon (see WorkspaceSwitch.js). Every scene the active mode
// admits is shown, whether or not it has a live Hyprland workspace yet —
// WorkspaceSwitch.rowState() names each row's play state:
//   focused → icon tinted the active mode's accent colour (no pill/border)
//   playing → lavender (has windows)
//   dormant → overlay0, further dimmed (admitted, no windows — may not even
//             exist in Hyprland yet; its key still focuses/creates it)
//   urgent  → red, regardless of state
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
        const all = (Hyprland.workspaces?.values ?? [])
            .filter(w => w.monitor === root._monitor)
            .filter(w => w.id > 0 || !w.name.startsWith("special:"));
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
        return WorkspaceSwitch.attachLive(order, all);
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
    //   - `focusedmon`/`focusedmonv2` fire ONLY when the globally-focused
    //     monitor itself changes: `CFocusState::rawMonitorFocus` opens with
    //     `if (m_focusMonitor == pMonitor) return;`, so a same-monitor
    //     switch posts no `focusedmon` event at all.
    // That lines up exactly with the observed staleness, so this reads the
    // active workspace off the raw event payload directly rather than off
    // the monitor's cached reference — cross-checked against that
    // workspace's own `.monitor` field (independently fresh; `_sorted`
    // above already relies on it) so an event for another monitor is
    // ignored. `focusedmonv2` is handled too, matched by monitor name
    // against `root.screen.name`, as a second source for a focus change
    // that crosses monitors without either monitor's active workspace
    // changing.
    property string _activeWsName: root._monitor?.activeWorkspace?.name ?? ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const data = event.data ?? "";
            const comma = data.indexOf(",");
            if (event.name === "workspace" || event.name === "workspacev2") {
                // payload: "name" (workspace) or "name,displayName" (workspacev2)
                const name = comma === -1 ? data : data.slice(0, comma);
                const live = (Hyprland.workspaces?.values ?? []).find(w => w.name === name);
                if (live && live.monitor === root._monitor) root._activeWsName = name;
            } else if (event.name === "focusedmon" || event.name === "focusedmonv2") {
                // payload: "monitorName,workspaceNameOrAddress"
                if (comma === -1) return;
                if (data.slice(0, comma) === root.screen.name) root._activeWsName = data.slice(comma + 1);
            }
        }
    }

    color: "transparent"
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.lg

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
                readonly property bool active: root._activeWsName !== "" && modelData.name === root._activeWsName
                readonly property bool occupied: (modelData.toplevels?.values?.length ?? 0) > 0
                readonly property bool urgent: modelData.urgent ?? false
                // rowState() (tests/workspaceswitch.test.js) names the row's
                // play state; a synthesized row (no live workspace) reads as
                // dormant the same as an existing, empty one.
                readonly property string state: WorkspaceSwitch.rowState({ active: active, occupied: occupied })
                readonly property bool dormant: state === "dormant"

                implicitWidth: icon.implicitWidth
                implicitHeight: icon.implicitHeight
                color: "transparent"

                Text {
                    id: icon
                    anchors.centerIn: parent
                    text: WorkspaceSwitch.iconFor(Hyprfocus.data, wsDelegate.modelData.name, wsDelegate.modelData.id)
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
                    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
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

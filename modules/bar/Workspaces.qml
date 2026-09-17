// Workspaces bar module: a surface pill of per-workspace buttons for this
// monitor, in the active hyprfocus mode's declared order, each shown as a
// Nerd Font icon (see WorkspaceSwitch.js), plus the focused scene's name
// (LEO-371) so "which scene am I in" reads without decoding an icon.
// LEO-373: every scene the active mode admits is shown, whether or not it
// has a live Hyprland workspace yet — WorkspaceSwitch.rowState() names each
// row's play state:
//   focused → accent (the active mode's colour), pill background + underline
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
        const byId = new Map(all.map(w => [w.id, w]));
        // A synthesized row (id: null — an admitted scene with no live
        // Hyprland workspace) has no live counterpart to look up: pass it
        // through as-is, the delegate below already treats an absent
        // `.toplevels`/`.active`/`.urgent` as empty/false/false.
        return order.map(w => w.id === null ? w : byId.get(w.id));
    }

    // The focused row's scene name (pure logic, tested in
    // tests/workspaceswitch.test.js): workspaces are named by scene, so this
    // is just picking the active one out of `_sorted`.
    readonly property string _activeName: WorkspaceSwitch.activeName(root._sorted ?? [])

    color: "transparent"
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.lg

        Repeater {
            model: root._sorted

            // The active workspace gets an accent pill (background + a thin
            // underline) behind its icon, not just a colour change — the
            // accent tracks the active mode's role (Theme.accent), so the
            // highlight itself says which mode this scene belongs to.
            delegate: Rectangle {
                id: wsDelegate
                required property var modelData
                readonly property bool active: modelData.active ?? false
                readonly property bool occupied: (modelData.toplevels?.values?.length ?? 0) > 0
                readonly property bool urgent: modelData.urgent ?? false
                // rowState() (tests/workspaceswitch.test.js) names the row's
                // play state; a synthesized row (no live workspace) reads as
                // dormant the same as an existing, empty one.
                readonly property string state: WorkspaceSwitch.rowState({ active: active, occupied: occupied })
                readonly property bool dormant: state === "dormant"

                implicitWidth: icon.implicitWidth + (active ? Theme.space.sm * 2 : 0)
                implicitHeight: icon.implicitHeight + (active ? Theme.space.xs * 2 : 0)
                radius: Theme.radiusPill
                color: active ? Theme.withAlpha(Theme.accent, Theme.surfaceAlpha.island) : "transparent"
                border { width: active ? 1 : 0; color: Theme.accent }

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

        // The focused scene's name, next to the row (LEO-371). Elided on a
        // laptop-width bar rather than pushing the rest of the island off
        // screen.
        Text {
            visible: root._activeName !== ""
            text: root._activeName
            color: Theme.accent
            elide: Text.ElideRight
            Layout.maximumWidth: Theme.space.xl * 5
            font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
        }
    }
}

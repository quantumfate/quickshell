// Workspaces bar module: a surface pill of per-workspace buttons for this
// monitor, in the active hyprfocus mode's declared order, each shown as a
// Nerd Font icon (see WorkspaceSwitch.js).
//   active   → mauve, filled pill
//   occupied → lavender (has windows)
//   idle     → overlay0
//   urgent   → red
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

    // LEO-340's published per-output gaps double as the one role signal the
    // shell has (see WorkspaceSwitch.roleForScreen's header): which monitor
    // is "primary" per the active hyprfocus mode's scene placement.
    Store { id: _geometry; name: "geometry" }
    readonly property string _role: WorkspaceSwitch.roleForScreen(_geometry.data.monitors, root.screen.name)

    // Icons and order come from the hyprfocus declaration (LEO-343): no
    // hardcoded workspace name list or icon map here. This monitor's rows are
    // the active mode's admitted scenes for `_role`, in declared order, plus
    // any other real workspace that still holds windows. Hyprland's list is
    // creation order and named workspaces carry negative auto ids, so the bar
    // must not sort by id. `_tick` re-evaluates on every compositor event.
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
        return order.map(w => byId.get(w.id));
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

            // Icon only — the active workspace is signalled purely by icon colour
            // (mauve), never a background.
            delegate: Text {
                id: wsDelegate
                required property var modelData
                readonly property bool active: modelData.active
                readonly property bool occupied: (modelData.toplevels?.values?.length ?? 0) > 0
                readonly property bool urgent: modelData.urgent ?? false

                text: WorkspaceSwitch.iconFor(Hyprfocus.data, modelData.name, modelData.id)
                color: urgent ? Theme.c.red
                     : active ? Theme.c.mauve
                     : ws.hovered ? Theme.c.text
                     : occupied ? Theme.c.lavender
                     : Theme.c.overlay0
                font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }

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

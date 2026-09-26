// WorkspaceSwitcher — keyboard-first "pick a workspace" overlay. Type to
// filter (by index, name, or a window title on it), Enter to go, Enter+Shift
// to bring the currently focused window along, Escape to dismiss. No mouse
// required, though rows are also clickable.
//
// Toggle from Hyprland:  qs -c quantumfate ipc call workspaceSwitcher toggle
pragma ComponentBehavior: Bound
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, Hypr, Hyprfocus
import "../common"        // Surface
import "WorkspaceSwitch.js" as WorkspaceSwitch

Scope {
    id: scope

    property bool shown: false
    property string query: ""
    property int highlighted: 0

    // Live workspace/window snapshot, rebuilt on the compositor events that can
    // actually move a row. Bumping on EVERY raw event rebuilt the whole list and
    // re-created every delegate for focus and submap traffic that cannot change
    // a row — see the filter below.
    property int _tick: 0
    Connections {
        target: Hyprland
        enabled: scope.shown
        function onRawEvent(e) {
            // Rows carry {id, name, icon, windows}: only events that change
            // which workspaces exist, what is on them, or what they are called
            // can move one. Focus, submap and monitor traffic cannot.
            if (e.name === "openwindow" || e.name === "closewindow"
                || e.name === "movewindow" || e.name === "movewindowv2"
                || e.name === "windowtitle" || e.name === "windowtitlev2"
                || e.name === "createworkspace" || e.name === "destroyworkspace"
                || e.name === "renameworkspace" || e.name === "moveworkspace"
                || e.name === "moveworkspacev2") {
                scope._tick++;
            }
        }
    }

    readonly property var _rows: {
        scope._tick;   // dependency
        // Named (auto-id) workspaces are the real ones: include them, and let
        // WorkspaceSwitch.canonical() merge any id-backed twins. Every real
        // workspace is shown here regardless of the active mode — this
        // overlay's job is "jump to any workspace by search" (LEO-343).
        const workspaces = (Hyprland.workspaces?.values ?? [])
            .filter(w => w.id > 0 || !w.name.startsWith("special:"))
            .map(w => ({ id: w.id, name: w.name }));
        const windows = [];
        for (const t of (Hyprland.toplevels?.values ?? [])) {
            const ipc = t?.lastIpcObject;
            const wsId = (t?.workspace?.id) ?? (ipc?.workspace?.id);
            if (wsId === undefined) continue;
            windows.push({ wsId: wsId, title: ipc?.title ?? t?.title ?? "(untitled)" });
        }
        const ordered = WorkspaceSwitch.canonical(Hyprfocus.data, workspaces);
        return WorkspaceSwitch.buildRows(Hyprfocus.data, ordered, windows);
    }

    readonly property var filtered: WorkspaceSwitch.filterRows(scope._rows, scope.query)

    onFilteredChanged: scope.highlighted = 0
    onShownChanged: if (scope.shown) { scope.query = ""; scope.highlighted = 0; }

    IpcHandler {
        target: "workspaceSwitcher"
        function toggle(): void { scope.shown = !scope.shown; }
        function show(): void { scope.shown = true; }
        function hide(): void { scope.shown = false; }
    }

    // Seat-scoped seam (one seat, cross-repo): the overlay opens over the
    // keyboard's monitor, so it acts there — `switch` moves the workspace to
    // that monitor and focuses it, `send` (bringWindow) additionally follows
    // with the currently focused window. Replaces the old
    // `Hyprland.dispatch('hl.dsp.workspace(...)')`/`movetoworkspace`, which has
    // errored on every call since 2026-09-14: `hl.dsp.workspace` is a table on
    // this Hyprland build, not callable.
    function go(row, bringWindow) {
        if (!row) return;
        const argv = WorkspaceSwitch.sendCommand(PanelBus.activeScreen, row, bringWindow);
        if (argv) { goProc.command = argv; goProc.running = true; }
        scope.shown = false;
    }

    Process { id: goProc }

    PanelWindow {
        id: win
        visible: scope.shown
        screen: PanelBus.screenObject(PanelBus.activeScreen)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Frosted per this namespace in the hypr repo's layerrules.lua, same as
        // the cheatsheet — report: namespace "quickshell-workspace-switcher",
        // elevation "modal" (alpha Theme.surfaceAlpha.modal = 0.97).
        WlrLayershell.namespace: "quickshell-workspace-switcher"

        // Click outside the card dismisses, but there is no dim backdrop.
        MouseArea { anchors.fill: parent; onClicked: scope.shown = false }

        readonly property string _screenName: win.screen?.name ?? ""
        // Placed in the scene's published work area (docs/scenes.md
        // "Areas"): same width/height ratios the card always used against
        // the whole screen, now capped against the area.
        readonly property var _box: PanelBus.surfaceBox(win._screenName, "workspaceswitcher", { width: 520, height: list.contentHeight + input.implicitHeight + Theme.pad * 3 })

        Surface {
            id: card
            x: win._box.x
            y: win._box.y
            width: win._box.width
            height: win._box.height
            elevation: "modal"
            radius: Theme.radius

            ColumnLayout {
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.sm
                    Text {
                        text: "Workspaces"
                        color: Theme.accent
                        font { pixelSize: Theme.fs.lg; bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "enter: go · shift+enter: bring window · esc: close"
                        color: Theme.subtext
                        font.pixelSize: Theme.fs.xs
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

                TextInput {
                    id: input
                    Layout.fillWidth: true
                    color: Theme.text
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.md }
                    clip: true
                    selectByMouse: true
                    text: scope.query
                    // `onTextEdited`, not `onTextChanged`: the latter fires for
                    // programmatic changes too, so `text: scope.query` plus an
                    // assignment on every change was a binding loop that
                    // re-entered on each keystroke. `onTextEdited` only fires
                    // for user input.
                    onTextEdited: scope.query = text

                    Text {
                        visible: input.text === ""
                        text: "type to filter…"
                        color: Theme.overlay
                        font: input.font
                    }

                    Keys.onEscapePressed: scope.shown = false
                    Keys.onReturnPressed: (event) => scope.go(scope.filtered[scope.highlighted], event.modifiers & Qt.ShiftModifier)
                    Keys.onEnterPressed: (event) => scope.go(scope.filtered[scope.highlighted], event.modifiers & Qt.ShiftModifier)
                    Keys.onDownPressed: scope.highlighted = Math.min(scope.filtered.length - 1, scope.highlighted + 1)
                    Keys.onUpPressed: scope.highlighted = Math.max(0, scope.highlighted - 1)
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: scope.filtered
                    spacing: Theme.space.xs
                    currentIndex: scope.highlighted

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width
                        implicitHeight: rowLayout.implicitHeight + Theme.space.md * 2
                        radius: Theme.radiusSmall
                        color: index === scope.highlighted ? Theme.withAlpha(Theme.accent, 0.22)
                             : rowHover.hovered ? Theme.surfaceAlt : "transparent"
                        border { width: 1; color: index === scope.highlighted ? Theme.accent : "transparent" }

                        HoverHandler { id: rowHover }
                        TapHandler { onTapped: scope.go(row.modelData, false) }

                        RowLayout {
                            id: rowLayout
                            anchors { fill: parent; margins: Theme.space.md }
                            spacing: Theme.space.md

                            Text {
                                text: row.modelData.icon
                                color: Theme.accentAlt
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.md }
                            }
                            Text {
                                text: row.modelData.id + (row.modelData.name ? " · " + row.modelData.name : "")
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.md; bold: true }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.space.xs
                                Repeater {
                                    model: row.modelData.windows
                                    delegate: Rectangle {
                                        required property string modelData
                                        radius: Theme.radiusSmall
                                        color: Theme.surface
                                        implicitWidth: chipText.implicitWidth + Theme.space.md * 2
                                        implicitHeight: chipText.implicitHeight + Theme.space.xs * 2
                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            color: Theme.subtext
                                            font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: scope.filtered.length === 0
                    text: "No workspace matches."
                    color: Theme.subtext
                    font.pixelSize: Theme.fs.md
                }
            }

            Component.onCompleted: if (scope.shown) input.forceActiveFocus()
            Connections {
                target: scope
                function onShownChanged() { if (scope.shown) Qt.callLater(() => input.forceActiveFocus()); }
            }
        }
    }
}

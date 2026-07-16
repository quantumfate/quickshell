// Window title control + a small rename widget. Retitles XWayland windows via
// xdotool (the same mechanism the Dofus launch flow uses).
//
//   qs -c quantumfate ipc call window rename "New Title"   # headless, active window
//   qs -c quantumfate ipc call window prompt <pid>         # open the widget for a pid
//
// The widget is opened from the Dofus team submap: Hyprland captures the focused
// window's pid *before* this layer grabs keyboard focus and passes it here, so we
// rename the right window even though focus moves to the input.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"

Scope {
    id: scope

    property bool shown: false
    property string targetPid: ""

    Process { id: applyProc }
    Process {
        id: queryProc
        stdout: StdioCollector {
            onStreamFinished: { input.text = (text || "").trim(); input.selectAll(); }
        }
    }

    IpcHandler {
        target: "window"

        // Headless: rename the currently active window (for scripts/keybinds).
        function rename(title: string): void {
            applyProc.command = [
                "bash", "-c",
                "xdotool set_window --name \"$1\" \"$(xdotool getactivewindow)\"",
                "qfs-window-rename", title
            ];
            applyProc.running = true;
        }

        // Open the rename widget targeting a specific pid, prefilling its title.
        function prompt(pid: string): void {
            scope.targetPid = pid;
            queryProc.command = [
                "bash", "-c",
                "xdotool getwindowname \"$(xdotool search --pid \"$1\" | head -1)\"",
                "qfs-window-query", pid
            ];
            queryProc.running = true;
            scope.shown = true;
        }

        function hide(): void { scope.shown = false; }
    }

    // Apply the input to the captured target pid's window.
    function apply() {
        const title = input.text;
        if (scope.targetPid && title.length > 0) {
            applyProc.command = [
                "bash", "-c",
                "xdotool set_window --name \"$1\" \"$(xdotool search --pid \"$2\" | head -1)\"",
                "qfs-window-rename", title, scope.targetPid
            ];
            applyProc.running = true;
        }
        scope.shown = false;
    }

    PanelWindow {
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: scope.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-window-rename"

        onVisibleChanged: if (visible) input.forceActiveFocus();

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.background, 0.5)
            MouseArea { anchors.fill: parent; onClicked: scope.shown = false }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.4, 460)
            implicitHeight: col.implicitHeight + 2 * Theme.pad
            radius: Theme.radius
            color: Theme.withAlpha(Theme.background, 0.98)
            border { width: 1; color: Theme.border }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                Text {
                    text: "Rename window"
                    color: Theme.accent
                    font { pixelSize: 15; bold: true }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: input.implicitHeight + 12
                    radius: Theme.radiusSmall
                    color: Theme.surface
                    border { width: 1; color: input.activeFocus ? Theme.accent : Theme.border }

                    TextInput {
                        id: input
                        anchors { fill: parent; margins: 6 }
                        color: Theme.text
                        font.pixelSize: 14
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        Keys.onReturnPressed: scope.apply()
                        Keys.onEnterPressed: scope.apply()
                        Keys.onEscapePressed: scope.shown = false
                    }
                }

                Text {
                    text: "Enter to apply · Esc to cancel"
                    color: Theme.subtext
                    font.pixelSize: 11
                }
            }
        }
    }
}

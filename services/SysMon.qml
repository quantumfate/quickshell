pragma Singleton
// SysMon — UI state bus for the system-monitor detail panel. The compact bar
// cluster (SysMonitor) reports hover-peek and pin toggles here; the panel
// (SysPanel) renders wherever this bus points. Split out so the panel is a
// single window driven by state, not one-per-widget.
//
// Toggle the pinned panel from Hyprland:
//   qs -c quantumfate ipc call sysmon toggle
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Screen currently hover-peeking ("" = none) and the anchor x on it.
    property string peekScreen: ""
    property real anchorX: 220
    // Pinned panel (survives hover-out) and which screen it's stuck to.
    property bool pinned: false
    property string pinnedScreen: ""
    // Default screen for keybind/IPC toggles (set by Bar to the wide monitor).
    property string homeScreen: ""

    // The screen the panel should show on, and whether it should show at all.
    readonly property string activeScreen: pinned ? pinnedScreen : peekScreen
    readonly property bool shown: activeScreen !== ""

    function peek(screen, x) { root.anchorX = x; root.peekScreen = screen; }
    function unpeek(screen) { if (root.peekScreen === screen) root.peekScreen = ""; }
    function togglePin(screen, x) {
        if (x !== undefined) root.anchorX = x;
        if (root.pinned && root.pinnedScreen === screen) {
            root.pinned = false; root.pinnedScreen = "";
        } else {
            root.pinned = true; root.pinnedScreen = screen || root.homeScreen;
        }
    }

    IpcHandler {
        target: "sysmon"
        function toggle(): void { root.togglePin(root.homeScreen); }
        function show(): void { root.pinned = true; root.pinnedScreen = root.homeScreen; }
        function hide(): void { root.pinned = false; root.pinnedScreen = ""; }
    }
}

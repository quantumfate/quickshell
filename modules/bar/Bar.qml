// Bar — the top bar, one instance per monitor, replacing waybar.
//
// A Variants spawns one PanelWindow per eligible screen (the small vertical
// HDMI panel is excluded). Each bar has three regions mirroring the old waybar:
//   left    workspaces · cpu · memory · disk · network
//   center  Dofus taskbar · window title · submap · layout · language
//   right   tray · brightness · pulseaudio · mako · clock · wlogout
//
// The Dofus taskbar region collapses via IPC so the bar stays useful elsewhere:
//   qs -c quantumfate ipc call bar toggleTaskbar
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, DofusWindows

Scope {
    id: scope

    // Monitors that must NOT carry the bar (the small portrait panel).
    readonly property var excludedScreens: ["HDMI-A-1"]

    // The abstract taskbar setting: which strip each monitor shows.
    //   "dofus"     — team taskbar (+ swap control), for the multibox screen
    //   "workspace" — default: the active workspace's windows
    // Add/repoint a monitor by editing this map; unlisted monitors get "default".
    readonly property var taskbarByScreen: ({ "DP-1": "dofus" })
    readonly property string defaultTaskbar: "workspace"
    function taskbarMode(name) { return scope.taskbarByScreen[name] || scope.defaultTaskbar; }

    // Show the Dofus taskbar region; toggled from the Hyprland Dofus submap.
    property bool taskbarShown: true

    IpcHandler {
        target: "bar"
        function toggleTaskbar(): void { scope.taskbarShown = !scope.taskbarShown; }
        function showTaskbar(): void { scope.taskbarShown = true; }
        function hideTaskbar(): void { scope.taskbarShown = false; }
    }

    // Back-compat: the Dofus submap in the Hyprland config still drives the old
    // `dofusPanel` target (was the retired HUD). Repointed onto the taskbar so
    // those binds keep working with no hypr-side change.
    IpcHandler {
        target: "dofusPanel"
        function toggle(): void { scope.taskbarShown = !scope.taskbarShown; }
        function show(): void { scope.taskbarShown = true; }
        function hide(): void { scope.taskbarShown = false; }
    }

    // Tooltip surfaces, one per bar screen (drawn below the bar by TipLayer).
    Variants {
        model: Quickshell.screens.filter(s => !scope.excludedScreens.includes(s.name))
        TipLayer { required property var modelData; screen: modelData }
    }

    Variants {
        model: Quickshell.screens.filter(s => !scope.excludedScreens.includes(s.name))

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: 30
            color: "transparent"

            // The team "is here" only when this monitor's active workspace holds
            // Dofus windows — so the Dofus taskbar hides when you switch away.
            // Bumped on every compositor event to track workspace switches.
            property int _wsTick: 0
            Connections { target: Hyprland; function onRawEvent(e) { bar._wsTick++; } }
            readonly property bool dofusOnActiveWs: {
                bar._wsTick;   // dependency
                return DofusWindows.onWorkspace(Hyprland.monitorFor(bar.screen)?.activeWorkspace?.id);
            }

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar"

            Rectangle {
                anchors.fill: parent
                color: Theme.background

                // left region, pinned to the start.
                RowLayout {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Theme.gap }
                    spacing: Theme.gap
                    Workspaces { screen: bar.screen }
                    Cpu {}
                    Memory {}
                    Disk {}
                    Network {}
                }

                // center region, fixed-center like the old waybar.
                RowLayout {
                    anchors.centerIn: parent
                    spacing: Theme.gap
                    // The taskbar strip for this monitor, per the setting above.
                    readonly property string mode: scope.taskbarMode(bar.screen.name)

                    // The Dofus strip is active only on the dofus monitor while its
                    // active workspace holds the team. Both the chips and the swap
                    // controls follow this — everywhere else it's the default bar.
                    readonly property bool dofusActive: scope.taskbarShown && mode === "dofus" && bar.dofusOnActiveWs

                    DofusTaskbar { visible: parent.dofusActive; screenName: bar.screen.name }
                    SwapControl { visible: parent.dofusActive; screenName: bar.screen.name }

                    // Default taskbar: every screen, every workspace where the Dofus
                    // strip isn't showing — so ordinary workspaces (Obsidian, etc.)
                    // get their windows too.
                    WorkspaceTaskbar {
                        screen: bar.screen
                        visible: scope.taskbarShown && !parent.dofusActive
                    }
                    Submap {}
                    HyprLayout {}
                    Language {}
                }

                // right region, pinned to the end.
                RowLayout {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: Theme.gap }
                    spacing: Theme.gap
                    Tray {}
                    Brightness {}
                    Pulseaudio {}
                    Mako {}
                    Clock {}
                    Wlogout {}
                }
            }
        }
    }
}

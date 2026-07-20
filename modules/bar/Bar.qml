// Bar — the top bar, one instance per monitor, replacing waybar.
//
// A Variants spawns one PanelWindow per eligible screen (the small vertical
// HDMI panel is excluded). Each bar has three regions mirroring the old waybar:
//   left    workspaces · sysmonitor (cpu/ram/disk/net, hover-peek) · weather · media
//   center  Dofus taskbar · window title · submap · layout · language
//   right   tray · brightness · volume · battery · power-profile ·
//           notifications · clock · wlogout
//
// The center taskbar is ALWAYS present (Dofus strip on the multibox workspace,
// the generic workspace taskbar everywhere else). Only the on-demand Dofus swap
// controls toggle, from the Hyprland Dofus submap:
//   qs -c quantumfate ipc call dofusPanel toggle
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

    // On-demand Dofus TEAM-MANAGEMENT controls (the swap detector panel), opened
    // from the Hyprland Dofus submap and hidden on leaving it. This does NOT gate
    // the taskbar — a taskbar is always present; only these extra controls toggle.
    property bool dofusControlsShown: false

    IpcHandler {
        target: "bar"
        function toggleTaskbar(): void { scope.dofusControlsShown = !scope.dofusControlsShown; }
        function showTaskbar(): void { scope.dofusControlsShown = true; }
        function hideTaskbar(): void { scope.dofusControlsShown = false; }
    }

    // The Dofus submap drives the `dofusPanel` target (show on demand, hide on
    // leave) — now the swap-controls panel, not the taskbar. Names kept so the
    // existing hypr binds work unchanged.
    IpcHandler {
        target: "dofusPanel"
        function toggle(): void { scope.dofusControlsShown = !scope.dofusControlsShown; }
        function show(): void { scope.dofusControlsShown = true; }
        function hide(): void { scope.dofusControlsShown = false; }
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
            // This monitor's current workspace id, and whether the team is on it.
            readonly property int activeWs: {
                bar._wsTick;   // dependency
                return Hyprland.monitorFor(bar.screen)?.activeWorkspace?.id ?? -1;
            }
            readonly property bool dofusOnActiveWs: {
                bar._wsTick;   // dependency
                return DofusWindows.onWorkspace(bar.activeWs);
            }

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell-bar"
            // Accept the keyboard only while a chip on THIS screen is being
            // renamed. OnDemand (NOT Exclusive): the compositor keeps control and
            // restores focus normally — an Exclusive grab left dangling by a
            // destroyed surface locks up keyboard input system-wide. None the
            // rest of the time so clicking the bar never steals focus.
            WlrLayershell.keyboardFocus: (BarInput.renaming && BarInput.screen === bar.screen.name)
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // First eligible bar screen is the default target for the sysmon
            // keybind/IPC toggle (when no hover has set an anchor yet).
            Component.onCompleted: if (!SysMon.homeScreen) SysMon.homeScreen = bar.screen.name;

            Rectangle {
                anchors.fill: parent
                color: Theme.background

                // left region, pinned to the start: workspaces pill + a stats/media cluster.
                RowLayout {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Theme.gap }
                    spacing: Theme.gap
                    Workspaces { screen: bar.screen }
                    Cluster {
                        SysMonitor { screenName: bar.screen.name }
                        Weather {}
                        Media { screenName: bar.screen.name }
                    }
                }

                // center region, fixed-center like the old waybar.
                RowLayout {
                    anchors.centerIn: parent
                    spacing: Theme.gap
                    // The taskbar strip for this monitor, per the setting above.
                    readonly property string mode: scope.taskbarMode(bar.screen.name)

                    // The Dofus strip is active on the dofus monitor while this
                    // monitor's current workspace holds Dofus windows (special
                    // excluded). Empty ⇒ fall through to the workspace taskbar.
                    // The taskbar is ALWAYS shown; only the swap controls toggle.
                    readonly property bool dofusActive: mode === "dofus" && bar.dofusOnActiveWs

                    DofusTaskbar { visible: parent.dofusActive; screenName: bar.screen.name; activeWs: bar.activeWs }
                    // Team-management (swap detector) controls — on demand only.
                    SwapControl { visible: parent.dofusActive && scope.dofusControlsShown; screenName: bar.screen.name }

                    // Default taskbar: every screen, every workspace where the Dofus
                    // strip isn't showing — so ordinary workspaces (Obsidian, etc.)
                    // get their windows too. Always present.
                    WorkspaceTaskbar {
                        screen: bar.screen
                        visible: !parent.dofusActive
                    }
                    Submap {}
                    HyprLayout {}
                    Language {}
                }

                // right region, pinned to the end: a system-controls cluster,
                // then the clock pill and the standalone power button.
                RowLayout {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: Theme.gap }
                    spacing: Theme.gap
                    Cluster {
                        Tray {}
                        Brightness {}
                        Pulseaudio { screenName: bar.screen.name }
                        Battery { screenName: bar.screen.name }
                        PowerProfile { screenName: bar.screen.name }
                        NotifIndicator { screenName: bar.screen.name }
                    }
                    Clock {}
                    Wlogout {}
                }

                // Hairline along the bottom edge for definition against wallpaper.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.withAlpha(Theme.border, 0.6)
                }
            }
        }
    }
}

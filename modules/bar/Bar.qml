// Bar — the top bar, one instance per monitor, replacing waybar.
//
// A Variants spawns one PanelWindow per eligible screen (the small vertical
// HDMI panel is excluded). The bar is not a strip: it is three translucent
// islands resting on the wallpaper, with the panel itself painting nothing, so
// the space between them is real wallpaper rather than chrome.
//   left    where am I  — workspaces · system · weather · media
//   centre  what is here — taskbar · submap · layout · language
//   right   system state — tray · brightness · volume · battery · power ·
//           idle-inhibit · notifications · clock · wlogout
//
// The center taskbar is ALWAYS present (Dofus strip on the multibox workspace,
// the generic workspace taskbar everywhere else). Only the on-demand Dofus swap
// controls toggle, from the Hyprland Dofus submap:
//   qs -c quantumfate ipc call dofusPanel toggle
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
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
            // The islands' height plus the space they float clear of the edge.
            implicitHeight: Theme.barReserved
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

            Item {
                anchors.fill: parent

                // left island: where am I, and what is the machine doing.
                Island {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.barInset * 2
                    }
                    Workspaces { screen: bar.screen }
                    Separator {}
                    SysMonitor { screenName: bar.screen.name }
                    Weather {}
                    Media { screenName: bar.screen.name }
                }

                // centre island: what is on this workspace, and what mode am I in.
                Island {
                    id: centreIsland
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }

                    readonly property string mode: scope.taskbarMode(bar.screen.name)

                    // The Dofus strip is active on the dofus monitor while this
                    // monitor's current workspace holds Dofus windows (special
                    // excluded). Empty ⇒ fall through to the workspace taskbar.
                    // The taskbar is ALWAYS shown; only the swap controls toggle.
                    readonly property bool dofusActive: mode === "dofus" && bar.dofusOnActiveWs

                    DofusTaskbar { visible: centreIsland.dofusActive; screenName: bar.screen.name; activeWs: bar.activeWs }
                    // Swap-detector controls (recalibrate + run/stop) — visible
                    // whenever the Dofus strip is, so they're always at hand.
                    SwapControl { visible: centreIsland.dofusActive; screenName: bar.screen.name }

                    // Default taskbar: every screen, every workspace where the Dofus
                    // strip isn't showing — so ordinary workspaces (Obsidian, etc.)
                    // get their windows too. Always present.
                    WorkspaceTaskbar {
                        screen: bar.screen
                        visible: !centreIsland.dofusActive
                    }
                    Separator {}
                    Submap {}
                    HyprLayout {}
                    Language {}
                }

                // right island: system state, the clock, and the way out.
                Island {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: Theme.barInset * 2
                    }
                    Tray {}
                    Brightness {}
                    Pulseaudio { screenName: bar.screen.name }
                    Battery { screenName: bar.screen.name }
                    PowerProfile { screenName: bar.screen.name }
                    IdleInhibit { screenName: bar.screen.name }
                    NotifIndicator { screenName: bar.screen.name }
                    Separator {}
                    Clock {}
                    Separator {}
                    Wlogout {}
                }

            }
        }
    }
}

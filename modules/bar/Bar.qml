// Bar — the top bar, one instance per monitor. A status indicator, not a
// taskbar (LEO-221): three islands, nothing that duplicates what a Hyprland
// group's own groupbar already shows. The window list is gone from every
// workspace, including the gaming one — that workspace moves to a group in
// LEO-230, same as the project terminals already do.
//   left    where am I    — workspaces · group chip · layout glyph
//   centre  what's playing — media · brightness · volume
//   right   when is it / where am I — clock · mood · entry to the calendar centre
//
// Everything else (system info, background apps, logout, settings,
// diagnostics, tray, notifications) moved to the on-demand System Center
// (SysPanel.qml), reachable from which-key rather than sitting on the bar.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, Hyprfocus
import "../../services/BarGaps.js" as BarGaps
import "../common"        // Surface

Scope {
    id: scope

    // Monitors that must NOT carry the bar (the small portrait panel).
    readonly property var excludedScreens: ["HDMI-A-1"]

    // LEO-340: per-monitor base left/right outer gap, published by conf/host.lua
    // (hypr repo) so the bar's side insets line up with the tiled gap instead of
    // a constant. One shared Store instance: FileView.watchChanges means every
    // bar re-reads live (e.g. pulling the laptop's external monitor), no restart.
    Store { id: geometryStore; name: "geometry" }

    // Bumped by the IPC `reveal` call below (bound to a SUPER-tap keybind in
    // the hypr repo) so every bar instance drops out of autohide at once.
    property int revealTick: 0

    IpcHandler {
        target: "bar"
        function reveal(): void { scope.revealTick++; }
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

            // --- Autohide (LEO-221): honours the declaration rather than a
            // local guess. `deep`/`game` (the old shedding/autohide ids) are
            // retired (see hypr AGENTS.md's mode-id contract); the current
            // modes speak through `presentation.bar_autohide` instead
            // (work/study autohide, neutral/gaming stay put) — no mode today
            // declares zone-shedding on top of that, so this bar no longer
            // has a `deepMode` concept to key off.
            readonly property bool autohideOn: Hyprfocus.current.presentation?.bar_autohide ?? false

            property bool revealed: true
            Connections { target: scope; function onRevealTickChanged() { bar.revealed = true; idle.restart(); } }

            Timer {
                id: idle
                interval: 2000
                running: bar.autohideOn && bar.revealed
                onTriggered: bar.revealed = false
            }
            // Any hover over the islands themselves counts as activity.
            function wake() { bar.revealed = true; idle.restart(); }

            Item {
                id: content
                anchors.fill: parent
                y: (bar.autohideOn && !bar.revealed) ? -Theme.barReserved : 0
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                HoverHandler { onHoveredChanged: if (hovered) bar.wake() }

                // LEO-340: this screen's tiled outer gap, falling back to the
                // bar's own default inset when the store has no entry for it.
                readonly property var edgeInset: BarGaps.insetFor(geometryStore.data, bar.screen.name, Theme.barInset * 2)

                // left island: where am I.
                Island {
                    id: leftIsland
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: content.edgeInset.left
                    }
                    Workspaces { screen: bar.screen }
                    SubmapIndicator {}
                    GroupChip {}
                    HyprLayout {}
                }

                // Dofus-only isle: appears only on the gaming workspace while
                // Dofus clients are present. Kept separate from the left island
                // so it can come and go without shifting the other controls.
                DofusRoster {
                    id: dofusIsle
                    screen: bar.screen
                    anchors {
                        left: leftIsland.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.barInset * 2
                    }
                }

                // centre island: what's playing / what to adjust.
                Island {
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                    Media { screenName: bar.screen.name }
                    Brightness { screenName: bar.screen.name }
                    Pulseaudio { screenName: bar.screen.name }
                }

                // right island: when is it, the active mood, and the way into
                // the calendar.
                Island {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: content.edgeInset.right
                    }
                    Clock {}
                    // The mood pill stays even while the bar autohides: it
                    // carries the countdown until the mood ends, which is the
                    // one thing you want while the rest of the bar drops away.
                    ModePill { screenName: bar.screen.name }
                    CalendarPill { screenName: bar.screen.name }
                }
            }

            // Thin always-present strip at the true top edge: catches the
            // pointer even while `content` is slid out of view, so autohide
            // has a way back in besides the SUPER-tap IPC reveal.
            MouseArea {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 8
                hoverEnabled: true
                visible: bar.autohideOn
                onEntered: bar.wake()
            }
        }
    }

    // A floating card of bar modules: Surface (the shared material) plus the
    // row layout the bar itself needs — Surface owns only ground/border/radius,
    // never layout, so this stays private to the bar rather than living in
    // modules/common.
    component Island: Surface {
        id: island
        default property alias content: row.data
        property alias spacing: row.spacing

        elevation: "island"
        implicitWidth: row.implicitWidth + Theme.space.lg * 2
        implicitHeight: Theme.barHeight

        RowLayout {
            id: row
            anchors {
                fill: parent
                leftMargin: Theme.space.lg
                rightMargin: Theme.space.lg
            }
            spacing: Theme.space.lg
        }
    }
}

// Passive peek cheatsheet. Sibling to CheatSheet.qml, but deliberately the
// opposite in feel: no dim backdrop, no keyboard focus, no click-to-dismiss. It
// is a hands-off contextual reference that fades in at the screen edge when you
// dwell in a submap, so you can read the binds while still seeing and using the
// window underneath.
//
// Driven entirely by Hyprland's submap event system (hypr/events/peek.lua):
//   qs -c quantumfate ipc call cheatsheetPeek show|hide|toggle
// The Lua side arms a delay on submap entry and hides on the next transition;
// this surface only renders whatever the current submap's binds are.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"
import "CheatParse.js" as CheatParse

Scope {
    id: scope

    property bool shown: false
    property string submap: ""          // "" = root/default
    property var cats: []               // [{ name, rows: [{ combo, desc }] }]
    readonly property var columns: CheatParse.splitColumns(cats)  // [leftCats, rightCats]

    // Preferred category ordering; unlisted categories sort alphabetically after.
    readonly property var categoryOrder: [
        "Window", "Workspace", "Menus", "Media", "Utilities", "Dofus", "Shell", "General"
    ]

    // NB: `qs ipc call <target> show` is swallowed by the quickshell CLI (it
    // prints the target interface instead of invoking), so the peek exposes
    // open/close instead — driven from hypr/events/peek.lua.
    IpcHandler {
        target: "cheatsheetPeek"
        function toggle(): void { scope.shown ? scope.close() : scope.open(); }
        function open(): void { scope.open(); }
        function close(): void { scope.close(); }
    }

    function open() { refresh.running = true; shown = true; }
    function close() { shown = false; }

    // Track the active submap so a show renders the right context. Also drives
    // live follow-along if the submap changes while the peek is visible.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data; // "" at root
        }
    }
    onSubmapChanged: if (scope.shown) refresh.running = true;

    Process {
        id: refresh
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: scope.cats = CheatParse.parse(text, scope.submap, scope.categoryOrder)
        }
    }

    PanelWindow {
        // Stay mapped until the fade-out finishes, so closing actually animates
        // (unmapping the moment `shown` flips false would just pop it away).
        visible: scope.shown || card.opacity > 0
        color: "transparent"
        // Bottom-centre of the screen, sized to content — never fullscreen, so the
        // rest of the screen (and its window) stays visible and interactive.
        anchors { bottom: true }
        margins { bottom: Theme.gap * 12 }
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        exclusiveZone: 0                                   // don't reserve space / shove tiling
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // never steal focus / eat input
        WlrLayershell.namespace: "quickshell-cheatsheet-peek"  // targeted by hypr layerrules

        Rectangle {
            id: card
            // Fixed width: the two-column layout uses fillWidth children, which
            // have no intrinsic width, so the card must define it (content-sizing
            // would collapse). Height still follows content.
            implicitWidth: 420
            implicitHeight: Math.min(header.implicitHeight + cols.implicitHeight + 3 * Theme.pad, 900)
            radius: Theme.radius
            color: Theme.withAlpha(Theme.background, 0.85)
            border { width: 1; color: Theme.border }

            // Almost-instant fade in, gentler fade out. The compositor maps this
            // layer with no animation (see hypr layerrules) so the fade is owned
            // here, giving independent in/out timing.
            opacity: scope.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: scope.shown ? 70 : 320; easing.type: Easing.OutQuad }
            }

            ColumnLayout {
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                Text {
                    id: header
                    text: scope.submap === "" ? "Keybinds" : "Keybinds · " + scope.submap
                    color: Theme.accent
                    font { pixelSize: 15; bold: true }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                // Two balanced columns, each a stack of category sections. Sized to
                // content (no scroll) — the peek is a glance, not a full browse.
                RowLayout {
                    id: cols
                    Layout.fillWidth: true
                    spacing: Theme.pad * 2

                    Repeater {
                        model: 2
                        delegate: ColumnLayout {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1   // equal columns
                            Layout.alignment: Qt.AlignTop
                            spacing: Theme.gap

                            Repeater {
                                model: scope.columns[index]
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: modelData.name.toUpperCase()
                                        color: Theme.accentAlt
                                        font { pixelSize: 10; bold: true; letterSpacing: 1 }
                                        Layout.bottomMargin: 2
                                    }

                                    Repeater {
                                        model: modelData.rows
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: Theme.gap
                                            Rectangle {
                                                radius: Theme.radiusSmall
                                                color: Theme.surface
                                                implicitWidth: keyText.implicitWidth + 12
                                                implicitHeight: keyText.implicitHeight + 4
                                                Text {
                                                    id: keyText
                                                    anchors.centerIn: parent
                                                    text: modelData.combo
                                                    color: Theme.accent
                                                    font { pixelSize: 11; family: "monospace" }
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.desc
                                                color: Theme.text
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: scope.cats.length === 0
                    text: "No described binds in this context."
                    color: Theme.subtext
                    font.pixelSize: 12
                }
            }
        }
    }
}

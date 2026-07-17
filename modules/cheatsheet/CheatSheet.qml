// Keybind cheatsheet overlay. Replaces ,cheatsheet.sh (rofi): reads the same
// `hyprctl binds -j`, whose descriptions come from the Lua bind layer, but
// renders a themed which-key panel instead of a dmenu.
//
// Context-aware: at root it shows global binds; inside a submap it shows only
// that submap's own binds (matching the old script's filtering). The active
// submap is tracked from Hyprland events. Binds are grouped into categories
// (derived from their descriptions) and sorted for tidiness.
//
// Toggle from Hyprland:  qs -c quantumfate ipc call cheatsheet toggle
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

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { scope.shown ? scope.hide() : scope.show(); }
        function show(): void { scope.show(); }
        // Peek: show as a transient preview that auto-hides (submap entry).
        function peek(): void { scope.peek(); }
        function hide(): void { scope.hide(); }
    }

    // Auto-hide countdown for peeks; restarted on each peek, stopped for a
    // manual (persistent) show. See hypr submap.on_enter -> cheatsheet peek.
    Timer { id: peekTimer; interval: 6000; onTriggered: scope.hide(); }

    function show() { refresh.running = true; shown = true; peekTimer.stop(); }
    function peek() { refresh.running = true; shown = true; peekTimer.restart(); }
    function hide() { shown = false; peekTimer.stop(); }

    // Keep the active submap current so a toggle shows the right context.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data; // "" at root
        }
    }

    // Live-update: while the cheatsheet is open, traversing submaps re-fetches
    // so it always shows the current context's binds (which-key follow-along).
    onSubmapChanged: if (scope.shown) refresh.running = true;

    Process {
        id: refresh
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: scope.cats = CheatParse.parse(text, scope.submap, scope.categoryOrder)
        }
    }

    PanelWindow {
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-cheatsheet"   // targeted by hypr layerrules

        // Dim backdrop; click to dismiss.
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.background, 0.5)
            MouseArea { anchors.fill: parent; onClicked: scope.hide() }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.62, 960)
            height: Math.min(parent.height * 0.85, cols.implicitHeight + 2 * Theme.pad + 44)
            radius: Theme.radius
            color: Theme.withAlpha(Theme.background, 0.97)
            border { width: 1; color: Theme.border }

            ColumnLayout {
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                Text {
                    text: scope.submap === "" ? "Keybinds" : "Keybinds · " + scope.submap
                    color: Theme.accent
                    font { pixelSize: 16; bold: true }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: cols.implicitHeight
                    clip: true

                    // Two balanced columns, each a stack of category sections.
                    RowLayout {
                        id: cols
                        width: parent.width
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
                                            font { pixelSize: 11; bold: true; letterSpacing: 1 }
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
                                                        font { pixelSize: 12; family: "monospace" }
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.desc
                                                    color: Theme.text
                                                    font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                }
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
                    font.pixelSize: 13
                }
            }
        }
    }
}

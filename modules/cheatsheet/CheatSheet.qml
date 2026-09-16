// Keybind cheatsheet: a which-key style render of the registry document the
// Lua config dumps (hypr/lib/whichkey.lua) — the same document the submap
// overlay reads, so both surfaces answer with one truth.
//
// Rendered BY CONSTRUCTION (LEO-268): each mode's converge narrows the dump
// to the trees its declaration admits, so the rows are exactly the keys that
// work and no entry can appear that would do nothing when pressed. The
// hyprctl parse and the context filter the old surface needed (LEO-223) are
// gone with it: the document is admission's output, not a scan of binds.
// Nesting itself is Hyprland's: `hypr/lib/submap.lua` owns the stack and
// binds escape to `M.back()` in every submap.
//
// Binds are grouped into categories (derived from their descriptions) and
// sorted for tidiness.
//
// Toggle from Hyprland:  qs -c quantumfate ipc call cheatsheet toggle
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"
import "../common"        // Surface
import "CheatParse.js" as CheatParse

Scope {
    id: scope

    property bool shown: false
    property string submap: ""          // "" = root/default
    // The registry document, mirrored reactively: a converge narrows or re-
    // admits trees and the render follows without any reload.
    readonly property var tree: store.data
    readonly property var cats: CheatParse.parseNode(CheatParse.nodeAs(scope.tree, scope.submap), scope.categoryOrder)
    readonly property var columns: CheatParse.splitColumns(scope.cats)  // [leftCats, rightCats]

    Store {
        id: store
        name: "whichkey"
        defaults: ({})
    }

    // Preferred category ordering; unlisted categories sort alphabetically after.
    readonly property var categoryOrder: [
        "Window", "Workspace", "Menus", "Media", "Utilities", "Dofus", "Shell", "General"
    ]

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { scope.shown ? scope.hide() : scope.show(); }
        function show(): void { scope.show(); }
        function hide(): void { scope.hide(); }
    }

    // Opening is on the input path, so it must never wait on a process: reuse
    // the cached bind table (parsing is pure JS, effectively instant) and only
    // fall back to `hyprctl` the first time, or after a config reload has
    // invalidated it.
    function show() {
        // Fresh open: drop the previous session's reserved height so this one
        // starts from its own content rather than inheriting a stale high
        // watermark (the "never shrink while open" rule only applies within
        // one open session, not across separate ones).
        if (!scope.shown) card.resetReserve = true;
        scope.shown = true;
    }
    function hide() { scope.shown = false; }

    // Follow the submap events: the entered submap names its registry node.
    // A config reload closes (and the re-dump refreshes), so the overlay can
    // never be orphaned on screen (the bug peek.lua once hit).
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data; // "" at root
            else if (event.name === "configreloaded") scope.hide();
        }
    }

    PanelWindow {
        visible: scope.shown
        screen: PanelBus.screenObject(PanelBus.activeScreen)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-cheatsheet"   // targeted by hypr layerrules

        // Click outside the card dismisses, but there is no dim backdrop.
        MouseArea { anchors.fill: parent; onClicked: scope.hide() }

        Surface {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.62, 960)

            // A nested node has fewer rows than its parent almost always, so
            // sizing to the live content would shrink the card on every
            // descent and grow it back on every "back" — a layout jump under
            // the cursor on the one interaction (nesting) that must feel
            // static. Instead the card reserves the tallest size it has
            // needed so far and only grows into a taller one, smoothly; it
            // never shrinks back while open, so descending never moves
            // anything under the pointer.
            readonly property real contentHeight: headerCol.implicitHeight
                + divider.implicitHeight + cols.implicitHeight + footer.implicitHeight + 4 * body.spacing
            property real reservedHeight: contentHeight
            // Set by show() on a fresh open, so this session starts from its
            // own content instead of inheriting the previous session's high
            // watermark — snapped in place (behavior off) rather than grown
            // into, since an open must show the right size immediately.
            property bool resetReserve: false
            onContentHeightChanged: {
                if (resetReserve) {
                    reservedBehavior.enabled = false;
                    reservedHeight = contentHeight;
                    reservedBehavior.enabled = true;
                    resetReserve = false;
                } else if (contentHeight > reservedHeight) {
                    reservedHeight = contentHeight;
                }
            }
            Behavior on reservedHeight { id: reservedBehavior; NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

            height: Math.min(parent.height * 0.85, reservedHeight + 2 * Theme.pad)
            elevation: "modal"
            radius: Theme.radius

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                ColumnLayout {
                    id: headerCol
                    spacing: Theme.space.xs

                // The context path is visually FIRST and distinct from the list
                // below (LEO-306): a smaller, quieter line states where these
                // binds apply, separated from the content with real space.
                Text {
                    text: scope.submap === "" ? "root map"
                        : CheatParse.nodeAs(scope.tree, scope.submap).parent
                    color: Theme.subtext
                    font { pixelSize: Theme.fs.xs; weight: Font.DemiBold }
                    Layout.topMargin: Theme.space.xs
                }
                Text {
                    text: scope.submap === "" ? "Keybinds" : "Keybinds · " + scope.submap
                    color: Theme.accent
                    font { pixelSize: Theme.fs.lg; bold: true }
                    Layout.bottomMargin: Theme.space.sm
                }
                }

                Rectangle { id: divider; Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }

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
                                id: colDelegate
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1   // equal columns
                                Layout.alignment: Qt.AlignTop
                                spacing: Theme.gap

                                Repeater {
                                    model: scope.columns[colDelegate.index]
                                    delegate: ColumnLayout {
                                        id: categoryDelegate
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: Theme.space.xs

                                        Text {
                                            text: categoryDelegate.modelData.name.toUpperCase()
                                            color: Theme.accentAlt
                                            font { pixelSize: Theme.fs.xs; bold: true; letterSpacing: 1 }
                                            Layout.bottomMargin: Theme.space.xs
                                        }

                                        Repeater {
                                            model: categoryDelegate.modelData.rows
                                            delegate: RowLayout {
                                                id: rowDelegate
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
                                                        text: rowDelegate.modelData.combo
                                                        color: Theme.accent
                                                        font { pixelSize: Theme.fs.sm; family: "monospace" }
                                                    }
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: rowDelegate.modelData.desc
                                                    color: Theme.text
                                                    font.pixelSize: Theme.fs.md
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
                    font.pixelSize: Theme.fs.md
                }

                // Footer legend. Escape's actual behaviour (unwind one level,
                // from any depth) is Hyprland's — every submap.lua tree binds
                // it to `M.back()` — this just states it.
                Text {
                    id: footer
                    text: scope.submap === "" ? "esc close" : "esc back"
                    color: Theme.subtextAlt
                    font.pixelSize: Theme.fs.xs
                }
            }
        }
    }
}

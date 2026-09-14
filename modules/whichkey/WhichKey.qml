// Which-key overlay (LEO-222): the SUPER-Space leader's renderer.
//
// Hyprland owns navigation entirely — hypr/lib/submap.lua owns the stack,
// binds each submap's entries, and unconditionally binds escape to one-level
// back — so this overlay is a pure mirror of the submap event: it draws the
// registered tree node for the submap currently entered, in place, with all
// geometry fixed so replacing the list never moves the cursor's target.
//
// The tree itself comes from hypr/lib/whichkey.lua, which records every
// submap.tree node at config load and dumps it to $QF_STORE/whichkey.json, the
// same data plane as hypr/lib/store.lua. The FileView below watches the file,
// so a reload lands a fresh tree without restarting the shell.
//
// Show:    qs -c quantumfate ipc call whichkey show
// Dismiss: qs -c quantumfate ipc call whichkey dismiss   (raised by submap.lua)
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"
import "../common"        // Surface
import "WhichKey.js" as WK

// Which-key opens automatically on any submap enter, so it runs in its own
// layer namespace (quickshell-whichkey) for a dedicated hypr layerrule —
// distinct from the passive cheatsheet's, since the two never stack.
Scope {
    id: scope

    property bool shown: false
    property string submap: ""          // from rawEvent; "" at root
    readonly property var tree: store.data
    readonly property var node: WK.nodeFor(tree, submap)
    property var rows: WK.rowsFor(node)
    readonly property var path: WK.pathFromRoot(tree, submap)

    // Entrance/exit fade, owned here so the layerrule's `popin` never fights
    // it. The duration reads the mode's motion contract: `instant` modes
    // (work/study/gaming) get what is effectively an instant swap, both
    // directions — the overlay tracks the submap stack at keyboard speed, and
    // a fade is motion the mode did not ask for.
    property real cardOpacity: 0
    readonly property int cardFades: Focus.motionEnergy === "instant" ? 30 : 90
    Behavior on cardOpacity { NumberAnimation { duration: scope.cardFades; easing.type: Easing.OutCubic } }

    function open() {
        scope.shown = true;
        scope.cardOpacity = 1;
    }
    function close() {
        // Unmap immediately: dismissal happens ahead of the submap reset (see
        // submap.lua exit()), so there is never a lingering surface to swallow
        // a keystroke meant for the base map.
        scope.shown = false;
        scope.cardOpacity = 0;
    }

    Store {
        id: store
        name: "whichkey"
        defaults: ({})
    }

    IpcHandler {
        target: "whichkey"
        function toggle(): void { scope.shown ? scope.close() : scope.open(); }
        function show(): void { scope.open(); }
        function hide(): void { scope.close(); }
        function dismiss(): void { scope.close(); }
    }

    // Follow the submap stack: entering any registered submap stages its node;
    // "" or "reset" (or anything not in the tree) closes. A config reload
    // closes too, so a stale overlay can never be orphaned on screen.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data;
            else if (event.name === "configreloaded") scope.close();
        }
    }
    onSubmapChanged: {
        if (scope.node) {
            scope.open();
            list.contentY = 0;   // replacing the list starts from the top
        } else {
            scope.close();
        }
    }

    PanelWindow {
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-whichkey"   // targeted by hypr layerrules

        // Dim backdrop; click to dismiss.
        Surface {
            anchors.fill: parent
            elevation: "backdrop"
            radius: 0
            border.width: 0
            MouseArea { anchors.fill: parent; onClicked: scope.close() }
        }

        Surface {
            id: card
            anchors.centerIn: parent
            // Fixed geometry, not content-sized: a nested node almost always
            // has fewer rows than its parent, so sizing to the live content
            // would shrink the card on every descent and grow it on every
            // "back" — a layout jump under the pointer on the one interaction
            // (nesting) that must feel static.
            width: Math.min(parent.width * 0.62, 960)
            height: Math.min(parent.height * 0.85, 460)
            elevation: "modal"
            radius: Theme.radius
            opacity: scope.cardOpacity

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: Theme.pad }
                spacing: Theme.gap

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        id: header
                        text: scope.path.length > 0 ? scope.path.join(" › ") : "Which-key"
                        color: Theme.accent
                        font { pixelSize: Theme.fs.lg; bold: true }
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "esc back"
                        color: Theme.subtextAlt
                        font.pixelSize: Theme.fs.xs
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.border
                }

                Flickable {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: rowsCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: rowsCol
                        width: parent.width
                        spacing: Theme.space.xs

                        Repeater {
                            model: scope.rows
                            delegate: RowLayout {
                                id: row
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
                                        text: row.modelData.combo
                                        color: Theme.accent
                                        font { pixelSize: Theme.fs.sm; family: "monospace" }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.desc
                                    color: Theme.text
                                    font.pixelSize: Theme.fs.md
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: row.modelData.group
                                    text: "›"
                                    color: Theme.accentAlt
                                    font.pixelSize: Theme.fs.md
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: scope.rows.length === 0
                    text: "No described commands here."
                    color: Theme.subtext
                    font.pixelSize: Theme.fs.md
                }
            }
        }
    }
}
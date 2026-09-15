// Which-key overlay (LEO-222 / LEO-300 / LEO-324 / LEO-327): a recursive
// submap HUD.
//
// Hyprland owns navigation entirely — hypr/lib/submap.lua owns the stack,
// binds each submap's entries, and unconditionally binds escape to one-level
// back — so this overlay mirrors the submap stack recursively: it appears when
// you dwell in any submap, stays open while you move from submap to submap, and
// disappears the moment you return to the root map. There is no dim backdrop;
// the panel is information, not a modal.
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
// layer namespace (quickshell-whichkey) for a dedicated hypr layerrule.
Scope {
    id: scope

    property bool shown: false
    property string submap: ""          // from rawEvent; "" or "reset" at root
    readonly property bool inSubmap: scope.submap !== "" && scope.submap !== "reset"
    readonly property var tree: store.data
    readonly property var node: WK.nodeFor(tree, submap)
    property var rows: WK.rowsFor(node)
    readonly property var path: WK.pathFromRoot(tree, submap)

    // Entrance/exit fade, owned here so the layerrule's `popin` never fights
    // it. The duration is the mode's motion contract WORD (LEO-227/300): an
    // `instant` mode gets zero fade so the menu snaps with the key; a `base`
    // mode keeps a gentle fade. The lingering tail is zero by contract —
    // close() unmaps in the same tick the submap leaves.
    property real cardOpacity: 0
    readonly property int cardFades: WK.fadeFor(Focus.motionEnergy, 30, 90)
    Behavior on cardOpacity { NumberAnimation { duration: scope.cardFades; easing.type: Easing.OutCubic } }

    function open() {
        if (!scope.inSubmap || !scope.node) return;
        scope.shown = true;
        scope.cardOpacity = 1;
        if (list) list.contentY = 0;   // replacing the list starts from the top
    }
    function close() {
        // Unmap immediately: dismissal happens ahead of the submap reset (see
        // submap.lua exit()), so there is never a lingering surface to swallow
        // a keystroke meant for the base map.
        scope.shown = false;
        scope.cardOpacity = 0;
    }

    Timer {
        id: dwell
        interval: 350
        repeat: false
        onTriggered: scope.open()
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

    // Recursive submap follow: arm a dwell when the user enters any submap from
    // root; keep the menu open while moving between submaps; dismiss the moment
    // we return to root. A config reload closes too, so a stale overlay can
    // never be orphaned on screen.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") scope.submap = event.data;
            else if (event.name === "configreloaded") scope.close();
        }
    }
    onInSubmapChanged: scope._syncSession()

    function _syncSession() {
        if (scope.inSubmap) {
            // Entering or moving within the submap stack: if already shown,
            // just stay; otherwise arm the dwell for a fresh entry.
            if (!scope.shown && !dwell.running) dwell.start();
        } else {
            // Back at root: stop any pending dwell and dismiss immediately.
            dwell.stop();
            scope.close();
        }
    }
    // The tree document is also runtime truth: a mode that withholds the
    // submap the menu is on removes its node from the dump, and the menu must
    // go with it — a mode change does not fire a submap event by itself, so
    // this is what keeps the overlay from surviving into a mode where its
    // submap no longer exists (LEO-303).
    onNodeChanged: if (!scope.node) scope.close()

    PanelWindow {
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-whichkey"   // targeted by hypr layerrules

        // Click outside the card dismisses, but there is no dim backdrop.
        MouseArea { anchors.fill: parent; onClicked: scope.close() }

        Surface {
            id: card
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Theme.gap * 12
            }
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
            // Swallow clicks so they don't reach the dismiss backdrop.
            MouseArea { anchors.fill: parent }

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

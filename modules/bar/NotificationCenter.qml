// NotificationCenter — the persisted notification history as a right-docked,
// themed panel. Toggled from the bar's bell or from Hyprland:
//
//   qs -c quantumfate ipc call notifications toggle
//
// Reads Notify.history (metadata log) and exposes DND + clear controls. A focus
// popup with a dim, click-to-dismiss backdrop (same pattern as the cheatsheet).
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, Theme
import "../../services/NotifyCards.js" as NotifyCards
import "../common"        // Surface

Scope {
    id: scope
    // Panel visibility is owned by Notify (shared with the bar bell).
    readonly property bool shown: Notify.historyOpen

    IpcHandler {
        target: "notifications"
        function toggle(): void { Notify.toggleHistory(); }
        function show(): void { Notify.showHistory(); }
        function hide(): void { Notify.hideHistory(); }
    }

    // "just now" / "5m ago" / "3h ago" / "Jul 19" from an epoch-ms timestamp.
    function _ago(ts) {
        const s = Math.floor((Date.now() - ts) / 1000);
        if (s < 45) return "just now";
        if (s < 3600) return Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        return Qt.formatDateTime(new Date(ts), "MMM dd");
    }

    PanelWindow {
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-notifications"

        // Dim backdrop; click outside the panel to dismiss.
        Surface {
            anchors.fill: parent
            elevation: "backdrop"
            radius: 0
            border.width: 0
            MouseArea { anchors.fill: parent; onClicked: Notify.hideHistory() }
        }

        Surface {
            id: panel
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: Math.min(parent.width * 0.32, 460)
            radius: 0
            elevation: "modal"
            // Swallow clicks so they don't reach the dismiss backdrop.
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors { fill: parent; margins: Theme.space.xl }
                spacing: Theme.space.lg

                // Header: title · DND · clear.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.lg
                    Text {
                        text: "Notifications"
                        color: Theme.text
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.lg; weight: Font.Bold }
                    }
                    Text {
                        visible: Notify.history.length > 0
                        text: Notify.history.length
                        color: Theme.subtext
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                    }
                    Item { Layout.fillWidth: true }

                    PillButton {
                        label: Notify.dnd ? "󰂛 DND" : "󰂚 DND"
                        active: Notify.dnd
                        onActivated: Notify.toggleDnd()
                    }
                    PillButton {
                        label: "Clear"
                        enabled: Notify.history.length > 0
                        onActivated: Notify.clearHistory()
                    }
                }

                // Empty state.
                Text {
                    visible: Notify.history.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space.xl + Theme.space.md
                    horizontalAlignment: Text.AlignHCenter
                    text: "No notifications"
                    color: Theme.overlay
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.md }
                }

                // History list, newest first.
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: Notify.history.length > 0
                    clip: true
                    spacing: Theme.space.md
                    model: Notify.history

                    delegate: Rectangle {
                        id: histCard
                        required property var modelData
                        readonly property string role: NotifyCards.verdictRole(modelData.route, modelData.level)
                        readonly property color accent: role === "success" ? Theme.success
                            : role === "error" ? Theme.error
                            : role === "pending" ? Theme.pending
                            : role === "info" ? Theme.info : Theme.accent
                        width: ListView.view.width
                        implicitHeight: entry.implicitHeight + 16
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border { width: 1; color: Theme.withAlpha(accent, 0.5) }

                        ColumnLayout {
                            id: entry
                            anchors { fill: parent; margins: Theme.space.md }
                            spacing: Theme.space.xs
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.md
                                Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: histCard.accent; Layout.alignment: Qt.AlignVCenter }
                                Text {
                                    // The sender is the resolved source — what routing
                                    // keyed on — not the app's own claim about itself.
                                    text: NotifyCards.sender(histCard.modelData)
                                    color: histCard.accent
                                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold; capitalization: Font.AllUppercase }
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: !!histCard.modelData.tier && histCard.modelData.trusted !== false
                                    text: NotifyCards.tierLine(histCard.modelData)
                                    color: Theme.overlay
                                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                }
                                Text {
                                    text: scope._ago(histCard.modelData.time)
                                    color: Theme.overlay
                                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                }
                            }
                            Text {
                                visible: !!histCard.modelData.summary
                                text: histCard.modelData.summary
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.md; weight: Theme.barFontWeight }
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                            Text {
                                visible: !!histCard.modelData.body
                                text: histCard.modelData.body
                                textFormat: Text.StyledText
                                color: Theme.subtext
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                            Text {
                                // History is never conditional: the card reads the
                                // verdict the mode applied and the rule that decided,
                                // so a mode that hid something shows what it hid.
                                visible: NotifyCards.routeLine(histCard.modelData) !== "shown"
                                text: NotifyCards.routeLine(histCard.modelData)
                                color: histCard.accent
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // A small themed pill button used in the header.
    component PillButton: Rectangle {
        property string label: ""
        property bool active: false
        property bool enabled: true
        signal activated()
        implicitWidth: t.implicitWidth + 20
        implicitHeight: 26
        radius: Theme.radiusPill
        opacity: enabled ? 1 : 0.4
        color: active ? Theme.withAlpha(Theme.accent, 0.25)
             : h.hovered ? Theme.surfaceAlt : Theme.surface
        border { width: 1; color: active ? Theme.accent : Theme.border }
        Text {
            id: t; anchors.centerIn: parent; text: parent.label
            color: parent.active ? Theme.accent : Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm; weight: Theme.barFontWeight }
        }
        HoverHandler { id: h; enabled: parent.enabled }
        TapHandler { enabled: parent.enabled; onTapped: parent.activated() }
    }
}

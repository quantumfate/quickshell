// NotificationCenter — the persisted notification history as a right-docked,
// themed panel. Toggled from the bar's bell or from Hyprland:
//
//   qs -c quantumfate ipc call notifications toggle
//
// Reads Notify.history (metadata log) and exposes DND + clear controls. A focus
// popup with a dim, click-to-dismiss backdrop (same pattern as the cheatsheet).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, Theme

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
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.background, 0.5)
            MouseArea { anchors.fill: parent; onClicked: Notify.hideHistory() }
        }

        Rectangle {
            id: panel
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: Math.min(parent.width * 0.32, 460)
            color: Theme.background
            border { width: 1; color: Theme.border }
            // Swallow clicks so they don't reach the dismiss backdrop.
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                // Header: title · DND · clear.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: "Notifications"
                        color: Theme.text
                        font { family: Theme.fontFamily; pixelSize: 16; weight: Font.Bold }
                    }
                    Text {
                        visible: Notify.history.length > 0
                        text: Notify.history.length
                        color: Theme.subtext
                        font { family: Theme.fontFamily; pixelSize: 12 }
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
                    Layout.topMargin: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: "No notifications"
                    color: Theme.overlay
                    font { family: Theme.fontFamily; pixelSize: 13 }
                }

                // History list, newest first.
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: Notify.history.length > 0
                    clip: true
                    spacing: 8
                    model: Notify.history

                    delegate: Rectangle {
                        id: histCard
                        required property var modelData
                        readonly property color accent: modelData.level === "success" ? Theme.success
                            : modelData.level === "error" ? Theme.error : Theme.accent
                        width: ListView.view.width
                        implicitHeight: entry.implicitHeight + 16
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border { width: 1; color: Theme.withAlpha(accent, 0.5) }

                        ColumnLayout {
                            id: entry
                            anchors { fill: parent; margins: 8 }
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { width: 6; height: 6; radius: 3; color: histCard.accent; Layout.alignment: Qt.AlignVCenter }
                                Text {
                                    text: histCard.modelData.appName || "notification"
                                    color: histCard.accent
                                    font { family: Theme.fontFamily; pixelSize: 10; weight: Font.Bold; capitalization: Font.AllUppercase }
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: scope._ago(modelData.time)
                                    color: Theme.overlay
                                    font { family: Theme.fontFamily; pixelSize: 10 }
                                }
                            }
                            Text {
                                visible: !!modelData.summary
                                text: modelData.summary
                                color: Theme.text
                                font { family: Theme.fontFamily; pixelSize: 13; weight: Theme.barFontWeight }
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                            Text {
                                visible: !!modelData.body
                                text: modelData.body
                                textFormat: Text.StyledText
                                color: Theme.subtext
                                font { family: Theme.fontFamily; pixelSize: 12 }
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
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
            font { family: Theme.fontFamily; pixelSize: 12; weight: Theme.barFontWeight }
        }
        HoverHandler { id: h; enabled: parent.enabled }
        TapHandler { enabled: parent.enabled; onTapped: parent.activated() }
    }
}

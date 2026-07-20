// Toasts — the live notification queue as themed cards under the bar, top-
// centered on the wide screen. Each card shows app · summary · body, urgency
// accent, action buttons, and a close affordance. Only the cards capture input
// (the rest of the surface stays click-through via the mask).
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, Theme

PanelWindow {
    id: win
    color: "transparent"
    visible: Notify.items.length > 0

    anchors { top: true; left: true; right: true }
    margins { top: 38 }                       // just below the 30px bar
    implicitHeight: Math.max(1, col.implicitHeight)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    // Only the cards are interactive; clicks elsewhere pass through to windows.
    mask: Region { item: col }

    ColumnLayout {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        width: 380
        spacing: 6

        Repeater {
            model: Notify.items

            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property color accent: modelData.level === "success" ? Theme.success
                    : modelData.level === "error" ? Theme.error : Theme.accent

                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 16
                radius: Theme.radiusPill
                color: Theme.withAlpha(Theme.backgroundAlt, 0.97)
                border { width: 1; color: card.accent }

                HoverHandler { id: cardHover }

                RowLayout {
                    id: body
                    anchors { fill: parent; leftMargin: 12; rightMargin: 10; topMargin: 8; bottomMargin: 8 }
                    spacing: 10

                    // Urgency dot.
                    Rectangle {
                        width: 8; height: 8; radius: 4; color: card.accent
                        Layout.alignment: Qt.AlignTop; Layout.topMargin: 4
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        // app · summary
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: card.modelData.appName || "notification"
                                color: card.accent
                                font { family: Theme.fontFamily; pixelSize: 10; weight: Font.Bold; capitalization: Font.AllUppercase }
                                elide: Text.ElideRight
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text {
                            visible: !!card.modelData.summary
                            text: card.modelData.summary
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: 13; weight: Theme.barFontWeight }
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                        Text {
                            visible: !!card.modelData.body
                            text: card.modelData.body
                            textFormat: Text.StyledText   // notifications may use markup
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: 12 }
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        // Action buttons (real notifications only).
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 6
                            visible: (card.modelData.actions || []).length > 0
                            Repeater {
                                model: card.modelData.actions || []
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: aLabel.implicitWidth + 16
                                    implicitHeight: 22
                                    radius: Theme.radiusSmall
                                    color: aHover.hovered ? Theme.surfaceAlt : Theme.surface
                                    border { width: 1; color: Theme.border }
                                    Text {
                                        id: aLabel
                                        anchors.centerIn: parent
                                        text: modelData.text || modelData.id
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: 11; weight: Theme.barFontWeight }
                                    }
                                    HoverHandler { id: aHover }
                                    TapHandler { onTapped: Notify.invokeAction(card.modelData.id, modelData.id) }
                                }
                            }
                        }
                    }

                    // Close — visible on hover, always for sticky (critical) toasts.
                    Text {
                        visible: cardHover.hovered || card.modelData.urgency === "critical"
                        text: "✕"
                        color: closeHover.hovered ? Theme.error : Theme.overlay
                        font { family: Theme.fontFamily; pixelSize: 12 }
                        Layout.alignment: Qt.AlignTop
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: Notify.dismiss(card.modelData.id) }
                    }
                }
            }
        }
    }
}

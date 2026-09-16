// Toasts — the live notification queue as themed cards, anchored by the active
// mood's policy (Focus.notifications.position): top-right under the bar by
// default, bottom-right when the media mood is on. Each card shows
// app · summary · body, urgency accent, action buttons, and a close affordance.
// Only the cards capture input (the rest of the surface stays click-through
// via the mask).
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, Theme, Focus
import "../common"        // Surface

PanelWindow {
    id: win
    color: "transparent"
    visible: Notify.items.length > 0
    screen: PanelBus.screenObject(PanelBus.activeScreen)

    readonly property bool stickyBottom: Focus.notifications.position === "bottom-right"
    anchors { top: !win.stickyBottom; bottom: win.stickyBottom; left: true; right: true }
    margins {
        top: win.stickyBottom ? 0 : Theme.barReserved + Theme.space.xs   // clear of the bar
        bottom: win.stickyBottom ? Theme.space.xs : 0
    }
    implicitHeight: Math.max(1, col.implicitHeight)

    WlrLayershell.layer: WlrLayer.Overlay

    // Named so the compositor can frost it like the rest of the shell.

    WlrLayershell.namespace: "quickshell-toasts"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    // Only the cards are interactive; clicks elsewhere pass through to windows.
    mask: Region { item: col }

    ColumnLayout {
        id: col
        // The top-right / bottom-right corner the policy names — never centered.
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.md
        width: 380
        spacing: Theme.space.md

        Repeater {
            model: Notify.items

            delegate: Surface {
                id: card
                required property var modelData
                readonly property color accent: modelData.level === "success" ? Theme.success
                    : modelData.level === "error" ? Theme.error : Theme.accent

                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 16
                radius: Theme.radiusPill
                elevation: "modal"
                border.color: card.accent

                HoverHandler { id: cardHover }

                RowLayout {
                    id: body
                    anchors { fill: parent; leftMargin: Theme.space.lg; rightMargin: Theme.space.lg; topMargin: Theme.space.md; bottomMargin: Theme.space.md }
                    spacing: Theme.space.lg

                    // Urgency dot.
                    Rectangle {
                        implicitWidth: 8; implicitHeight: 8; radius: 4; color: card.accent
                        Layout.alignment: Qt.AlignTop; Layout.topMargin: Theme.space.sm
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.xs

                        // app · summary
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text {
                                text: card.modelData.appName || "notification"
                                color: card.accent
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold; capitalization: Font.AllUppercase }
                                elide: Text.ElideRight
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text {
                            visible: !!card.modelData.summary
                            text: card.modelData.summary
                            color: Theme.text
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.md; weight: Theme.barFontWeight }
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                        Text {
                            visible: !!card.modelData.body
                            text: card.modelData.body
                            textFormat: Text.StyledText   // notifications may use markup
                            color: Theme.subtext
                            font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        // Action buttons (real notifications only).
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.space.xs
                            spacing: Theme.space.md
                            visible: (card.modelData.actions || []).length > 0
                            Repeater {
                                model: card.modelData.actions || []
                                delegate: Rectangle {
                                    id: actionDelegate
                                    required property var modelData
                                    implicitWidth: aLabel.implicitWidth + 16
                                    implicitHeight: 22
                                    radius: Theme.radiusSmall
                                    color: aHover.hovered ? Theme.surfaceAlt : Theme.surface
                                    border { width: 1; color: Theme.border }
                                    Text {
                                        id: aLabel
                                        anchors.centerIn: parent
                                        text: actionDelegate.modelData.text || actionDelegate.modelData.id
                                        color: Theme.text
                                        font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Theme.barFontWeight }
                                    }
                                    HoverHandler { id: aHover }
                                    TapHandler { onTapped: Notify.invokeAction(card.modelData.id, actionDelegate.modelData.id) }
                                }
                            }
                        }
                    }

                    // Close — visible on hover, always for sticky (critical) toasts.
                    Text {
                        visible: cardHover.hovered || card.modelData.urgency === "critical"
                        text: "✕"
                        color: closeHover.hovered ? Theme.error : Theme.overlay
                        font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
                        Layout.alignment: Qt.AlignTop
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: Notify.dismiss(card.modelData.id) }
                    }
                }
            }
        }
    }
}

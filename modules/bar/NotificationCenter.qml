// NotificationCenter — the persisted notification history as a right-docked,
// themed panel. Toggled from the bar's bell or from Hyprland:
//
//   qs -c quantumfate ipc call notifications toggle
//
// Reads Notify.history (metadata log) and exposes DND + clear controls. Opens
// on the monitor the bell or PanelBus names, with no dim backdrop (LEO-240):
// the panel is information, not a modal.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, PanelBus, Theme
import "../../services/BarGaps.js" as BarGaps
import "../../services/NotifyCards.js" as NotifyCards
import "../common"        // Surface

Scope {
    id: scope
    // Panel visibility is owned by Notify (shared with the bar bell).
    readonly property bool shown: Notify.historyOpen
    // Kept mapped through the exit animation, then unmapped by the timer below
    // (LEO-424): `shown` alone would cut the slide off at the first frame.
    property bool _mounted: false
    Component.onCompleted: if (scope.shown) scope._mounted = true
    onShownChanged: {
        if (scope.shown) { scope._mounted = true; unmount.stop(); }
        else if (scope._mounted) unmount.restart();
    }
    Timer {
        id: unmount
        interval: Theme.motion.exit + 30
        repeat: false
        onTriggered: scope._mounted = false
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { PanelBus.anchorScreen = PanelBus.activeScreen; Notify.toggleHistory(); }
        function show(): void { PanelBus.anchorScreen = PanelBus.activeScreen; Notify.showHistory(); }
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

    // Panel-local reads over the same history: grouped by source, or filtered
    // to what a mode held back (LEO-240's review). Explicit, not hidden:
    // nothing is shown when the view enables both.
    property bool _bySource: false
    property bool _onlySuppressed: false
    readonly property var _suppressed: NotifyCards.suppressed(Notify.history)

    PanelWindow {
        id: win
        visible: scope._mounted
        screen: PanelBus.screenObject(PanelBus.anchorScreen || PanelBus.activeScreen)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-notifications"

        Store { id: geometryStore; name: "geometry" }
        Store { id: hyprfocusStore; name: "hyprfocus" }
        readonly property string _screenName: win.screen?.name ?? ""
        readonly property string _sceneName: PanelBus.sceneByScreen[win._screenName] ?? ""
        readonly property var _sceneGaps: BarGaps.sceneGapsFor(
            geometryStore.data, hyprfocusStore.data, win._sceneName)
        readonly property int _smallGap: Theme.space.xs
        readonly property int _topGap: Theme.barReserved + (win._sceneGaps ? win._sceneGaps.top : 0) + win._smallGap
        readonly property int _bottomGap: (win._sceneGaps ? win._sceneGaps.bottom : 0) + win._smallGap
        readonly property int _rightGap: (win._sceneGaps ? win._sceneGaps.right : 0)
        readonly property int _leftGap: (win._sceneGaps ? win._sceneGaps.left : 0)

        // No dim backdrop (LEO-240): the panel is information, not a modal.
        // A click outside the panel still dismisses it.
        MouseArea { anchors.fill: parent; onClicked: Notify.hideHistory() }

        Surface {
            id: panel
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            anchors.topMargin: win._topGap
            anchors.bottomMargin: win._bottomGap
            anchors.rightMargin: win._rightGap
            // Keep the panel compact: never wider than the history width and
            // always leave the published left gap clear.
            width: Math.min(Theme.historyWidth, parent.width - win._leftGap - win._rightGap)
            radius: Theme.radius
            elevation: "modal"
            // Slide in from the right edge; the exit is the shorter move.
            x: scope.shown ? 0 : panel.width
            Behavior on x {
                NumberAnimation {
                    duration: scope.shown ? Theme.motion.base : Theme.motion.exit
                    easing.type: Theme.motion.ease
                }
            }
            opacity: scope.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: scope.shown ? Theme.motion.base : Theme.motion.exit
                    easing.type: Theme.motion.ease
                }
            }
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
                        label: "By source"
                        active: scope._bySource
                        onActivated: scope._bySource = !scope._bySource
                    }
                    PillButton {
                        label: "Suppressed"
                        active: scope._onlySuppressed
                        enabled: scope._suppressed.length > 0
                        onActivated: scope._onlySuppressed = !scope._onlySuppressed
                    }
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

                // Empty states: an empty history, and the suppressed view
                // with nothing held.
                Text {
                    visible: Notify.history.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space.xl + Theme.space.md
                    horizontalAlignment: Text.AlignHCenter
                    text: "No notifications"
                    color: Theme.overlay
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.md }
                }
                Text {
                    visible: entries.count === 0 && Notify.history.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space.xl + Theme.space.md
                    horizontalAlignment: Text.AlignHCenter
                    text: "Nothing held back"
                    color: Theme.overlay
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.md }
                }

                // History list, newest first; grouping and the suppressed
                // review are panel-local reads over the same store.
                ListView {
                    id: entries
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property int count: scope._onlySuppressed
                        ? scope._suppressed.length
                        : (scope._bySource ? NotifyCards.bySource(Notify.history) : Notify.history).length
                    visible: entries.count > 0
                    clip: true
                    spacing: Theme.space.md
                    model: scope._onlySuppressed ? scope._suppressed
                        : scope._bySource ? NotifyCards.bySource(Notify.history) : Notify.history

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

// Toasts — the live notification queue as themed cards, placed by the active
// mood's policy (Focus.notifications.position, resolved by NotifyPlacement.js):
// top-centre under the bar by default, any edge/corner a mood names. Each card
// shows resolved source · summary · body, an urgency accent, a countdown line,
// action buttons and a close affordance.
//
// Two behaviours here are load-bearing (LEO-424):
//   * The surface stays mapped until the last card's exit finishes, so the
//     leave animation is never cut off by the layer unmapping. `cards` is a
//     local mirror of Notify.items that keeps closing cards until their timer
//     fires.
//   * Hovering a card pauses its own countdown (and Notify's expiry timer for
//     it), so a toast cannot vanish while it is being read or clicked.
//
// Only the cards capture input (the rest of the surface stays click-through
// via the mask).
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Notify, Theme, Focus, PanelBus
import "../../services/BarGaps.js" as BarGaps
import "../../services/NotifyCards.js" as NotifyCards
import "../../services/NotifyPlacement.js" as NotifyPlacement
import "../common"        // Surface

PanelWindow {
    id: win
    color: "transparent"

    readonly property var placement: NotifyPlacement.resolve(Focus.notifications.position)
    readonly property bool isBottom: win.placement.v === "bottom"
    readonly property string hAlign: win.placement.h

    // Deterministic frame, the same one the bar itself uses: the sides are
    // the bar's own resting insets (BarGaps.insetFor — the monitor's
    // published base gap; LEO cross-repo "bars never dance" retired the
    // scene-gap opt-in this used to also ride), and the vertical edge is the
    // bar's reserved strip plus a small gap. The stack therefore sits exactly
    // where the bar sits on every scene.
    Store { id: geometryStore; name: "geometry" }
    Store {
        id: transitionStore
        name: "hyprfocus.transition"
        defaults: ({ active: false, present: false })
    }
    readonly property bool transitionPresent: {
        const p = transitionStore.get("present");
        if (p === true) return true;
        if (p === undefined) return transitionStore.get("active") === true;
        return false;
    }
    readonly property string _screenName: win.screen?.name ?? ""
    readonly property var _inset: BarGaps.insetFor(geometryStore.data, win._screenName, Theme.barInset * 2)
    readonly property int _smallGap: Theme.space.md

    // Rest rule as the fallback for now: a later phase (SurfacePlacement.js,
    // published areas) replaces this fixed strip-height margin with the
    // scene's actual work area.
    readonly property int _topMargin: Theme.barReserved + Theme.space.xs
    readonly property int _bottomMargin: Theme.space.xs
    readonly property int _leftMargin: win._inset.left + win._smallGap
    readonly property int _rightMargin: win._inset.right + win._smallGap

    // Live cards, including ones animating out. Notify.items is the source;
    // this mirror is what the surface renders so a leave has time to play.
    property var cards: []
    property var _closing: ({})
    readonly property int _maxCards: 4
    readonly property int overflow: Math.max(0, win.cards.length - win._maxCards)

    visible: win.cards.length > 0 && !win.transitionPresent
    screen: PanelBus.screenObject(PanelBus.activeScreen)

    anchors { top: !win.isBottom; bottom: win.isBottom; left: true; right: true }
    margins {
        top: win.isBottom ? 0 : win._topMargin
        bottom: win.isBottom ? win._bottomMargin : 0
        left: win._leftMargin
        right: win._rightMargin
    }
    implicitHeight: Math.max(1, col.implicitHeight)

    // Top, not Overlay: the mode-transition veil and the detail panels live on
    // Overlay, and a toast must never float above the veil — a transient card
    // ranks with the bar, not with the surfaces that cover the desk.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-toasts"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    // Only the cards are interactive; clicks elsewhere pass through to windows.
    mask: Region { item: col }

    Component.onCompleted: win._sync()
    Connections {
        target: Notify
        function onItemsChanged() { win._sync(); }
    }

    // Reconcile the mirror with Notify.items: keep what is live, start the
    // exit on what left, and append what arrived. Ids already closing stay
    // until their removal timer fires.
    function _sync() {
        const live = Notify.items || [];
        const liveIds = {};
        for (const it of live) liveIds[it.id] = true;

        const closing = Object.assign({}, win._closing);
        const next = [];
        const seen = {};
        for (const c of win.cards) {
            seen[c.id] = true;
            if (liveIds[c.id]) { next.push(c); continue; }
            if (!closing[c.id]) { closing[c.id] = true; win._scheduleClose(c.id); }
            next.push(c);
        }
        for (const it of live) if (!seen[it.id]) next.push(it);

        win._closing = closing;
        win.cards = next;
    }

    function _scheduleClose(rid) {
        closeTimer.createObject(win, { rid: rid, interval: Math.max(1, Theme.motion.exit + 30) });
    }
    function _remove(rid) {
        const closing = Object.assign({}, win._closing);
        delete closing[rid];
        win._closing = closing;
        win.cards = win.cards.filter(c => c.id !== rid);
    }

    Component {
        id: closeTimer
        Timer {
            property int rid
            running: true
            repeat: false
            onTriggered: { win._remove(rid); destroy(); }
        }
    }

    ColumnLayout {
        id: col
        width: Theme.toastWidth
        // Horizontal alignment from the mood's position; vertical placement is
        // the window's own margins above, and the surface is sized to this
        // column, so no vertical anchor is needed.
        x: win.hAlign === "left" ? 0
            : win.hAlign === "right" ? (parent.width - width)
            : Math.round((parent.width - width) / 2)
        spacing: Theme.space.md

        Repeater {
            model: win.cards.slice(0, win._maxCards)

            delegate: Surface {
                id: card
                required property var modelData
                readonly property bool closing: win._closing[modelData.id] === true
                readonly property color accent: modelData.level === "success" ? Theme.success
                    : modelData.level === "error" ? Theme.error : Theme.accent
                readonly property real fullHeight: body.implicitHeight + Theme.space.xl
                property bool entered: false
                property real remaining: 1

                Component.onCompleted: card.entered = true

                Layout.fillWidth: true
                implicitHeight: card.closing ? 0 : card.fullHeight
                Behavior on implicitHeight {
                    NumberAnimation { duration: Theme.motion.exit; easing.type: Theme.motion.ease }
                }
                opacity: (card.entered && !card.closing) ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: card.closing ? Theme.motion.exit : Theme.motion.base
                        easing.type: Theme.motion.ease
                    }
                }
                transform: Translate {
                    y: (card.entered && !card.closing) ? 0 : (win.isBottom ? Theme.space.md : -Theme.space.md)
                    Behavior on y {
                        NumberAnimation {
                            duration: card.closing ? Theme.motion.exit : Theme.motion.base
                            easing.type: Theme.motion.ease
                        }
                    }
                }
                radius: Theme.radiusPill
                elevation: "modal"
                border.color: card.accent

                // The countdown the toast draws, over the same ttl Notify's
                // expiry timer uses. Hover pauses both together.
                NumberAnimation {
                    id: ttlAnim
                    target: card
                    property: "remaining"
                    from: 1
                    to: 0
                    duration: card.modelData.ttl > 0 ? card.modelData.ttl : 0
                    running: card.modelData.ttl > 0 && card.entered && !card.closing
                }

                HoverHandler {
                    id: cardHover
                    onHoveredChanged: {
                        if (card.closing || !(card.modelData.ttl > 0)) return;
                        if (cardHover.hovered) {
                            ttlAnim.pause();
                            Notify.pause(card.modelData.id);
                        } else {
                            ttlAnim.resume();
                            Notify.resume(card.modelData.id);
                        }
                    }
                }
                // Clicking the card dismisses it; the action and close handlers
                // below are children and take their own taps first.
                TapHandler { onTapped: Notify.dismiss(card.modelData.id) }

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

                        // resolved source · tier
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.md
                            Text {
                                text: NotifyCards.sender(card.modelData)
                                color: card.accent
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: Font.Bold; capitalization: Font.AllUppercase }
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: card.modelData.tier !== undefined
                                text: NotifyCards.tierLine(card.modelData)
                                color: Theme.overlay
                                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                            }
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

                // Countdown line: depletes over the toast's ttl, so a glance
                // says how long is left. Sticky toasts have no line.
                Rectangle {
                    visible: card.modelData.ttl > 0
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.leftMargin: Theme.space.lg
                    anchors.rightMargin: Theme.space.lg
                    anchors.bottomMargin: Theme.space.sm
                    height: Math.max(1, Math.round(Theme.scale))
                    color: Theme.withAlpha(card.accent, 0.55)
                    transform: Scale { origin.x: 0; origin.y: 0; xScale: card.remaining }
                }
            }
        }

        // More than the cap is waiting: one pill opens the history instead of
        // stacking a wall of cards.
        Surface {
            visible: win.overflow > 0
            Layout.fillWidth: true
            implicitHeight: moreLabel.implicitHeight + Theme.space.lg
            radius: Theme.radiusPill
            elevation: "peek"
            Text {
                id: moreLabel
                anchors.centerIn: parent
                text: "+" + win.overflow + " more"
                color: moreHover.hovered ? Theme.text : Theme.subtext
                font { family: Theme.fontFamily; pixelSize: Theme.fs.sm }
            }
            HoverHandler { id: moreHover }
            TapHandler {
                onTapped: {
                    PanelBus.anchorScreen = win._screenName;
                    PanelBus.anchorIsleId = "";
                    PanelBus._fallbackAnchorX = 0;
                    Notify.showHistory();
                }
            }
        }
    }
}

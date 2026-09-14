// Dofus group quick-actions (LEO-244): a transient menu for the group as a
// whole, anchored to the groupbar slot the compositor reserves on the tile.
//
// The compositor's own groupbar is THE attached bar (it insets the client and
// takes the top edge out of the window — the only Wayland-honest mechanism a
// shell can attach to another client's tile). This widget does not draw a
// second bar over it; it draws nothing until asked:
//
//   * a small ≡ affordance sits at the right end of the bar's slot — click it
//     to open the quick-actions menu;
//   * the menu lists the members (one-click focus), the group's iteration
//     (hl.dsp.group.next/prev — LEO-230's primitives), the existing editor
//     panels, and close-the-group; keyboard-navigable (arrows/enter/escape).
//
// Per-member editing (rename, turn-order reorder, turn-hash capture) stays in
// the Team panel/Class panel — the surfaces that own those features (LEO-234).
// Every action funnels through an existing service (DofusWindows / DofusState
// / PanelBus / Notify); no new IPC beyond the menu's own toggle target.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, PanelBus, DofusState, DofusWindows, Notify
import "../common"        // Surface, ClassIcon

Scope {
    id: scope

    // One entry per live Dofus window, in group order (the DofusWindows read
    // model — the list the tile's own groupbar renders).
    readonly property var _live: DofusWindows.windows ?? []

    // The tile the menu hangs off. Group members share one tile, so any
    // member's geometry works; the focused one is the honest choice because
    // it is the window the user is actually looking at.
    readonly property var _anchor:
        scope._live.find(w => w.focused ?? false) ?? (scope._live.length > 0 ? scope._live[0] : null)

    // The compositor monitor the tile lives on. `hyprctl clients` reports
    // `monitor` as the monitor's numeric id, so monitors match by id — a name
    // match never resolves and the widget would never appear.
    readonly property var _mon: scope._anchor
        ? (Hyprland.monitors?.values ?? []).find(m => m.id === scope._anchor.monitorId) ?? null
        : null

    // On stage only while the group's workspace is the monitor's ACTIVE one;
    // gone the moment focus moves off the gaming workspace, exactly like the
    // native bar's own visibility. A member rendering fullscreen takes the
    // affordance and menu away too — Hypr takes its bar then (LEO-243).
    readonly property bool placed: !!scope._anchor && !!scope._mon
        && scope._mon.activeWorkspace?.id === scope._anchor.workspaceId
        && !scope._live.some(w => (w.fullscreen ?? 0) > 0)

    // The menu open state. Closed by an action, a click-away, or the group's
    // workspace losing focus — the menu is attached to the tile, and the tile
    // went away.
    property bool menuOpen: false
    function closeMenu() { scope.menuOpen = false; }
    function toggleMenu() { scope.menuOpen = !scope.menuOpen; }
    onPlacedChanged: if (!scope.placed) scope.closeMenu()

    // Quick actions, in menu order. Tones default to accent; the destructive
    // row carries red.
    readonly property var _menuActions: [
        { id: "next", label: "next character" },
        { id: "prev", label: "previous character" },
        { id: "team", label: "team panel" },
        { id: "classes", label: "class panel" },
        { id: "close-all", label: "close group", tone: Theme.c.red },
    ]

    // One resolver the menu — and nothing else — calls.
    function runMenuAction(id) {
        scope.closeMenu();
        if (id === "next") DofusWindows.iterate(false);
        else if (id === "prev") DofusWindows.iterate(true);
        else if (id === "team") PanelBus.teamSelectorOpen = !PanelBus.teamSelectorOpen;
        else if (id === "classes") PanelBus.classAssignerOpen = !PanelBus.classAssignerOpen;
        else if (id === "close-all") {
            const members = scope._live.length;
            DofusWindows.closeAll();
            Notify.send("Dofus group closed",
                members + " client" + (members === 1 ? "" : "s"), "info");
        }
    }

    // The bar slot Hypr groups reserve on the tile top. Must keep in step with
    // hypr conf.lua `group.groupbar.height` — native bar and affordance share
    // the same strip of pixels.
    readonly property int groupbarHeight: 30

    PanelWindow {
        id: win
        visible: scope.placed
        // Geometry-tracked to the group tile's monitor. A stale screen (the
        // monitor changed under us mid-rebuild) hides rather than mis-anchors.
        screen: scope._mon
            ? (Quickshell.screens.find(s => s.name === (scope._mon.name ?? "")) ?? null)
            : null
        color: "transparent"

        // Full-monitor surface so the menu's click-away catch covers the
        // desktop; only the masked regions ever intercept input.
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        // Only the menu ever needs the keyboard; the affordance is mouse-only,
        // and the Dofus group underneath must receive keystrokes at rest.
        WlrLayershell.keyboardFocus: visible
            ? (scope.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            : WlrKeyboardFocus.None
        // The hypr-side layerrules rule keyed by this namespace (fade + blur)
        // styles the surfaces.
        WlrLayershell.namespace: "quickshell-dofus"

        // While the menu is open the whole window takes input (click-away
        // catch); otherwise only the affordance does — the native bar's tab
        // clicks must reach the compositor underneath.
        mask: scope.menuOpen ? null : affordWin
        Region { id: affordWin; item: afford }

        // Click-away catcher under the menu card, active only while open.
        MouseArea {
            anchors.fill: parent
            enabled: scope.menuOpen
            z: -1
            onClicked: scope.closeMenu()
        }

        // ── The affordance: one small button at the bar slot's right end ───
        Rectangle {
            id: afford
            visible: scope.placed

            x: scope._mon ? (scope._anchor.at.x - scope._mon.x
                + scope._anchor.size.x - afford.width - Theme.space.xs) : 0
            y: scope._mon ? (scope._anchor.at.y - scope._mon.y
                + (scope.groupbarHeight - afford.height) / 2) : 0
            width: Theme.space.xl
            height: Theme.space.xl
            radius: Theme.radiusIsland
            color: affordHover.hovered ? Theme.withAlpha(Theme.accent, 0.22)
                                       : Theme.withAlpha(Theme.surfaceAlt, 0.4)
            border { width: 1; color: Theme.withAlpha(Theme.border, 0.45) }

            Text {
                anchors.centerIn: parent
                text: "≡"
                color: Theme.text
                font { pixelSize: Theme.fs.sm; family: "monospace" }
            }

            HoverHandler { id: affordHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: scope.toggleMenu()
            }
        }

        // ── The quick-actions menu ─────────────────────────────────────────
        Surface {
            id: menu
            visible: scope.menuOpen
            elevation: "peek"
            radius: Theme.radius

            // Under the bar slot's right end, clamped inside the monitor.
            width: 280
            x: Math.max(Theme.space.sm, Math.min(
                scope._anchor.at.x - scope._mon.x + scope._anchor.size.x - width,
                (scope._mon?.width ?? 0) - width - Theme.space.xs))
            y: Math.max(Theme.space.sm, Math.min(
                scope._anchor.at.y - scope._mon.y + scope.groupbarHeight + Theme.space.xs,
                (scope._mon?.height ?? 0) - menu.implicitHeight - Theme.space.xs))
            implicitHeight: menuContent.implicitHeight + Theme.space.lg * 2

            // Arrow-key cursor into the action list. Member rows are
            // mouse-only (they click through to focus); the keyboard here
            // steers actions.
            FocusScope {
                id: menuKeys
                anchors.fill: parent
                focus: scope.menuOpen

                property int cursor: 0
                onCursorChanged: {
                    if (cursor > scope._menuActions.length - 1) cursor = scope._menuActions.length - 1;
                    if (cursor < 0) cursor = 0;
                }

                Keys.onEscapePressed: scope.closeMenu()
                Keys.onBackPressed: scope.closeMenu()
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Down) {
                        menuKeys.cursor = Math.min(scope._menuActions.length - 1, menuKeys.cursor + 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        menuKeys.cursor = Math.max(0, menuKeys.cursor - 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        scope.runMenuAction(scope._menuActions[menuKeys.cursor].id);
                        event.accepted = true;
                    }
                }
            }

            ColumnLayout {
                id: menuContent
                anchors { fill: parent; margins: Theme.space.lg }
                spacing: Theme.space.xs

                // Per-member rows: one-click focus — zone 4 of the team panel,
                // surfaced compactly.
                Repeater {
                    model: scope._live

                    delegate: MouseArea {
                        id: mrow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: mrowRow.implicitHeight
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            DofusWindows.focus(mrow.modelData.selector);
                            scope.closeMenu();
                        }

                        RowLayout {
                            id: mrowRow
                            width: parent.width
                            spacing: Theme.space.sm

                            Text {
                                text: (mrow.index + 1) + "."
                                color: Theme.overlay
                                font { pixelSize: Theme.fs.xs; family: "monospace" }
                            }
                            ClassIcon {
                                cls: mrow.modelData.name
                                    ? DofusState.classOf(mrow.modelData.name) : ""
                                size: 16
                            }
                            Text {
                                text: mrow.modelData.name || "unnamed"
                                color: (mrow.modelData.focused ?? false) ? Theme.accent : Theme.text
                                font { pixelSize: Theme.fs.sm }
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.withAlpha(Theme.border, 0.4)
                }

                // Quick actions: the group as a whole. Bullet marks the
                // keyboard cursor; Enter runs the row.
                Repeater {
                    model: scope._menuActions

                    delegate: MouseArea {
                        id: arow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: actionRow.implicitHeight
                        cursorShape: Qt.PointingHandCursor
                        onClicked: scope.runMenuAction(arow.modelData.id)

                        RowLayout {
                            id: actionRow
                            width: parent.width
                            spacing: Theme.space.sm

                            Text {
                                text: "›"
                                visible: arow.index === menuKeys.cursor
                                color: Theme.accent
                                font { pixelSize: Theme.fs.xs; bold: true }
                            }
                            Text {
                                text: arow.modelData.label
                                color: arow.index === menuKeys.cursor
                                    ? (arow.modelData.tone ?? Theme.accent) : Theme.text
                                font { pixelSize: Theme.fs.sm }
                                Layout.fillWidth: true
                                leftPadding: arow.index === menuKeys.cursor ? 0 : Theme.space.md
                            }
                        }
                    }
                }
            }
        }
    }

    // ipc: qs -c quantumfate ipc call groupMenu <fn> — the keyboard path (the
    // Dofus submap) opens the same menu the affordance does.
    IpcHandler {
        target: "groupMenu"
        function toggle(): void { scope.toggleMenu(); }
        function show(): void { scope.menuOpen = true; }
        function hide(): void { scope.closeMenu(); }
    }
}

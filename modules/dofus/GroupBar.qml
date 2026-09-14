// Dofus group widget (LEO-234/LEO-244): the groupbar's twin, rendered
// ABOVE the Dofus group instead of in the bar.
//
// Two surfaces, one window:
//
//   slide — the always-on chip strip: one chip per group member, in group
//           order, the active tab highlighted. The same list the tile's own
//           groupbar renders, read from DofusWindows — no second opinion, no
//           private join.
//   menu  — right-click context menu: member list with one-click focus, group
//           iteration, the full editors, close the group. Keyboard-navigable
//           (arrows/enter/escape) like the panel editors.
//
// The widget is geometry-tracked, not pinned to a corner: it positions itself
// just above the group tile on the tile's monitor, using the same
// `hyprctl clients` snapshot the roster comes from. It is only visible while
// the group's workspace is the focused one, so leaving gaming takes it away
// with the workspace.
//
// Every action funnels through an existing service (DofusWindows / DofusState
// / PanelBus / Notify) — no new IPC surface.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, PanelBus, DofusState, DofusWindows, Notify
import "../common"        // Surface, ClassIcon

Scope {
    id: scope

    // One entry per live Dofus window, in group order (the DofusWindows read
    // model — the list the tile's groupbar renders).
    readonly property var _live: DofusWindows.windows ?? []

    // The tile the widget hangs off. Group members share one tile, so any
    // member's geometry works; the focused one is the honest choice because
    // it is the window the user is actually looking at.
    readonly property var _anchor:
        scope._live.find(w => w.focused ?? false) ?? (scope._live.length > 0 ? scope._live[0] : null)

    // The compositor monitor the tile lives on (by the name `hyprctl clients`
    // reports), for output-relative geometry math and screen selection.
    readonly property var _mon: scope._anchor
        ? (Hyprland.monitors?.values ?? []).find(m => m.name === scope._anchor.monitor) ?? null
        : null

    // Up only while the group's workspace is the monitor's ACTIVE one. A
    // focus/workspace change that moves attention off the gaming workspace
    // takes the widget — and any open menu — with it.
    readonly property bool placed: !!scope._anchor && !!scope._mon
        && scope._mon.activeWorkspace?.id === scope._anchor.workspaceId

    // The context menu open state. Closed by an action, a click-away, or the
    // group's workspace losing focus — the menu is attached to the tile, and
    // the tile went away.
    property bool menuOpen: false
    function closeMenu() { scope.menuOpen = false; }
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
        // Only the menu ever needs the keyboard; the chip strip is mouse-only.
        WlrLayershell.keyboardFocus: visible
            ? (scope.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            : WlrKeyboardFocus.None
        // Covered by the hypr-side layerrules rule keyed by this namespace
        // (slidefade 20%, blur, ignore_alpha 0.1) — the same landing the old
        // HUD had.
        WlrLayershell.namespace: "quickshell-dofus"

        // While the menu is open the whole window takes input (click-away
        // catch); otherwise only the chip strip does — the Dofus group must
        // receive clicks underneath.
        mask: scope.menuOpen ? null : chipsWin
        Region { id: chipsWin; item: slide }

        // Click-away catcher under the menu card, active only while open.
        MouseArea {
            anchors.fill: parent
            enabled: scope.menuOpen
            z: -1
            onClicked: scope.closeMenu()
        }

        // ── The chip strip: the groupbar itself ─────────────────────────────
        Surface {
            id: slide
            elevation: "island"

            // At least chip-strip wide, never past the monitor's edge.
            implicitWidth: Math.min(
                Math.max(240, scope._anchor?.size?.x ?? 240),
                Math.max(240, (scope._mon?.width ?? 0) - Theme.space.lg * 2))
            implicitHeight: 30
            radius: Theme.radiusIsland

            // Above the tile, in output-local coordinates. The layer-shell
            // window starts at the monitor's (0,0), so a tile at global (tx,ty)
            // on a monitor at (mx,my) sits at (tx-mx, ty-my) here.
            x: scope._mon ? (scope._anchor.at.x - scope._mon.x) : 0
            y: scope._mon
                ? Math.max(Theme.space.sm,
                    scope._anchor.at.y - scope._mon.y - height - Theme.space.xs)
                : 0

            Row {
                anchors { fill: parent; leftMargin: Theme.space.xs; rightMargin: Theme.space.xs }
                spacing: Theme.space.xs

                Repeater {
                    model: scope._live

                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool active: modelData.focused ?? false
                        readonly property bool named: !!modelData.name
                        readonly property string label: chip.modelData.name || ("client " + (chip.index + 1))

                        width: Math.min(labelText.implicitWidth + 16, 150)
                        height: parent.height
                        radius: Theme.radiusIsland
                        color: chip.active
                            ? Theme.withAlpha(Theme.accent, 0.18)
                            : Theme.withAlpha(Theme.surfaceAlt, 0.35)
                        border { width: 1; color: chip.active ? Theme.accent : Theme.border }

                        Text {
                            id: labelText
                            anchors.centerIn: parent
                            width: chip.width - 2 * Theme.space.sm
                            text: chip.label
                            color: chip.active ? Theme.accent
                                 : chip.named ? Theme.text : Theme.overlay
                            font { pixelSize: Theme.fs.xs; family: "monospace" }
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (event) => {
                                if (event.button === Qt.LeftButton) {
                                    DofusWindows.focus(chip.modelData.selector);
                                    scope.closeMenu();
                                } else {
                                    scope.menuOpen = true;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── The context menu ────────────────────────────────────────────────
        Surface {
            id: menu
            visible: scope.menuOpen
            elevation: "peek"
            radius: Theme.radius

            // Below the chip strip, aligned to its left edge; clamped inside
            // the monitor so a low tile can't push the menu off-screen.
            x: slide.x
            width: Math.max(slide.width, 280)
            y: Math.max(Theme.space.sm,
                Math.min(slide.y + slide.height + Theme.space.xs,
                    (scope._mon?.height ?? 0) - menu.implicitHeight - Theme.space.xs))
            implicitHeight: menuContent.implicitHeight + Theme.space.lg * 2

            // Arrow-key cursor into the action list. Member rows are mouse-only
            // (they click through to focus); the keyboard here steers actions.
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
}

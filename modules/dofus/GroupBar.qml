// Dofus group widget (LEO-234/LEO-244): the tile's groupbar, rebuilt.
//
// It sits exactly on the slot the compositor's own groupbar occupies — the top
// of the Dofus tile — and paints over it as a fully-styled tab strip, so the
// group has ONE bar, ours, carrying the actions the old bar taskbar had:
//
//   click the name      focus + raise
//   double-click        rename (retitles the window; team members update team.json)
//   ◀ ▶                 reorder the character in the team's turn order
//   ◎                   capture a turn-hash for the swap detector (during their turn)
//   ✕                   close that window
//   right-click         the group quick-actions menu (LEO-244)
//
// Membership, the active tab, and the tile geometry all read from the group
// (DofusWindows) — never reconstructed. Every action goes through an existing
// service (DofusWindows / DofusState / DofusSwap / PanelBus / Notify); no new
// IPC surface. `stripHeight` must keep in step with the compositor bar's slot:
// hypr/hypr/conf.lua `group.groupbar.height`.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme, PanelBus, DofusState, DofusWindows, DofusSwap, BarInput, Notify
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

    // The compositor monitor the tile lives on. `hyprctl clients` reports
    // `monitor` as the monitor's numeric id, so monitors match by id — a name
    // match never resolves and the widget would never appear.
    readonly property var _mon: scope._anchor
        ? (Hyprland.monitors?.values ?? []).find(m => m.id === scope._anchor.monitorId) ?? null
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

    // Any chip's inline rename; the window takes OnDemand keyboard focus while
    // one is open so the TextInput receives keystrokes.
    property bool editingOpen: false

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
        // Keyboard focus is needed only while a chip rename or the menu has it;
        // the Dofus group underneath must receive keystrokes at rest.
        WlrLayershell.keyboardFocus: visible
            ? (scope.menuOpen || scope.editingOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            : WlrKeyboardFocus.None
        // The hypr-side layerrules rule keyed by this namespace (fade + blur)
        // styles this surface; geometry changes must not re-trigger a travel
        // animation, which is why it is a plain fade.
        WlrLayershell.namespace: "quickshell-dofus"

        // While the menu is open the whole window takes input (click-away
        // catch); otherwise only the strip does — the Dofus group must receive
        // clicks underneath.
        mask: scope.menuOpen ? null : chipsWin
        Region { id: chipsWin; item: slide }

        // Click-away catcher under the menu card, active only while open.
        MouseArea {
            anchors.fill: parent
            enabled: scope.menuOpen
            z: -1
            onClicked: scope.closeMenu()
        }

        // ── The strip: the compositor groupbar's slot, restyled ────────────
        Surface {
            id: slide
            elevation: "island"
            radius: Theme.radiusIsland

            // Near-opaque so the compositor bar's own paint cannot bleed through.
            color: Theme.withAlpha(Theme.backgroundAlt, 0.92)

            // The compositor groupbar's slot: tile's top edge, full tile width,
            // in output-local coordinates (the window origin is the monitor's).
            readonly property int groupbarHeight: 26
            implicitWidth: scope._anchor?.size?.x ?? 240
            implicitHeight: groupbarHeight
            x: scope._mon ? (scope._anchor.at.x - scope._mon.x) : 0
            y: scope._mon ? (scope._anchor.at.y - scope._mon.y) : 0

            Row {
                anchors { fill: parent; leftMargin: Theme.space.xs; rightMargin: Theme.space.xs }
                spacing: Theme.space.xs

                Repeater {
                    model: scope._live

                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property string name: modelData.name || ""
                        readonly property bool focused: modelData.focused ?? false
                        readonly property bool named: !!chip.name
                        // Position of this character in the team's TURN order —
                        // -1 when the window is not a named team member.
                        readonly property int teamIndex: DofusState.team?.indexOf(chip.name) ?? -1
                        readonly property bool inTeam: chip.teamIndex >= 0
                        readonly property bool learned: DofusSwap.learned(chip.name)

                        // Turn-hash state: idle · busy · flash ok/fail.
                        property string flash
                        readonly property bool busy: chip.inTeam && DofusSwap.capturing === chip.name
                        Timer { id: flashTimer; interval: 1400; onTriggered: chip.flash = "" }
                        Connections {
                            enabled: chip.inTeam
                            target: DofusSwap
                            function onCaptured(name, ok) {
                                if (name !== chip.name) return;
                                chip.flash = ok ? "ok" : "fail";
                                flashTimer.restart();
                            }
                        }

                        // If the chip dies mid-rename (window closed, rebuild),
                        // never leave the shell holding a keyboard grab.
                        Component.onDestruction: if (chip._renaming) {
                            chip._renaming = false;
                            scope.editingOpen = false;
                            BarInput.end();
                        }

                        // Hover state for the whole chip (buttons keep their own).
                        HoverHandler { id: chipHover }

                        height: parent.height
                        width: chipRow.implicitWidth
                        radius: Theme.radiusIsland
                        color: chip.focused
                            ? Theme.withAlpha(Theme.accent, 0.28)
                            : chipHover.hovered ? Theme.surfaceAlt : "transparent"
                        border {
                            width: (chip.busy || chip.flash !== "") ? 2 : 1
                            color: chip.flash === "ok" ? Theme.success
                                 : chip.flash === "fail" ? Theme.error
                                 : chip.busy ? Theme.warning
                                 : chip.focused ? Theme.accent
                                 : chip.named ? Theme.border : Theme.withAlpha(Theme.border, 0.4)
                        }

                        // ── chip content: dot · emblem · name/editor · actions
                        RowLayout {
                            id: chipRow
                            anchors { fill: parent; leftMargin: Theme.space.xs; rightMargin: Theme.space.xs }
                            spacing: Theme.space.xs

                            // Learn-state dot: green once a turn-hash exists.
                            Rectangle {
                                visible: chip.inTeam
                                implicitWidth: 6; implicitHeight: 6; radius: 3
                                color: chip.learned ? Theme.success : Theme.overlay
                            }

                            ClassIcon {
                                cls: chip.inTeam ? DofusState.classOf(chip.name) : ""
                                size: 16
                            }

                            // Name — click focuses, double-click renames.
                            Text {
                                id: label
                                visible: !editor.visible
                                text: chip.named ? chip.name : "unnamed"
                                color: chip.focused ? Theme.accent
                                     : chip.named ? Theme.text : Theme.overlay
                                font { pixelSize: Theme.fs.xs; family: "monospace" }
                                elide: Text.ElideRight
                                Layout.maximumWidth: 150

                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onSingleTapped: chip.focusMe()
                                    onDoubleTapped: chip.beginRename()
                                }
                            }

                            // Inline rename field: retitles the window; team
                            // members also rewrite team.json (DofusWindows.rename).
                            TextInput {
                                id: editor
                                visible: false
                                color: Theme.text
                                font { pixelSize: Theme.fs.xs; family: "monospace" }
                                Layout.preferredWidth: Math.max(70, label.implicitWidth)
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true; selectByMouse: true
                                onEditingFinished: chip.commitRename()
                                Keys.onEscapePressed: chip.cancelRename()
                            }

                            // Capture (◎) — press during this character's turn.
                            ChipButton {
                                visible: chip.inTeam
                                symbol: "◎"
                                enabled: DofusSwap.calibrated
                                onActivated: DofusSwap.learn(chip.name)
                            }
                            // Reorder in the team's turn order.
                            ChipButton {
                                visible: chip.inTeam
                                symbol: "◀"
                                enabled: chip.teamIndex > 0
                                onActivated: DofusState.reorder(chip.teamIndex, chip.teamIndex - 1)
                            }
                            ChipButton {
                                visible: chip.inTeam
                                symbol: "▶"
                                enabled: chip.teamIndex >= 0 && chip.teamIndex < (DofusState.team?.length ?? 0) - 1
                                onActivated: DofusState.reorder(chip.teamIndex, chip.teamIndex + 1)
                            }
                            // Close just this window.
                            ChipButton {
                                symbol: "✕"
                                onActivated: DofusWindows.close(chip.modelData.selector)
                            }
                        }

                        // Right-click opens the group quick-actions menu.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: scope.menuOpen = true
                        }

                        // Capture feedback: colour wash only (DofusSwap sends
                        // the words as a toast).
                        Rectangle {
                            anchors.fill: parent
                            radius: chip.radius
                            visible: chip.busy || chip.flash !== ""
                            color: chip.flash === "ok" ? Theme.withAlpha(Theme.success, 0.30)
                                 : chip.flash === "fail" ? Theme.withAlpha(Theme.error, 0.30)
                                 : Theme.withAlpha(Theme.warning, 0.22)
                        }

                        // Inline-rename plumbing, same as the old bar chip.
                        property bool _renaming: false
                        function focusMe() {
                            DofusWindows.focus(chip.modelData.selector);
                            scope.closeMenu();
                        }
                        function beginRename() {
                            if (chip._renaming) return;
                            scope.editingOpen = true;
                            chip._renaming = true;
                            editor.text = chip.inTeam ? chip.name : "";
                            editor.visible = true;
                            Qt.callLater(() => { editor.forceActiveFocus(); editor.selectAll(); });
                        }
                        function commitRename() {
                            if (!chip._renaming) return;
                            chip._renaming = false;
                            scope.editingOpen = false;
                            editor.visible = false;
                            DofusWindows.rename(chip.inTeam ? chip.teamIndex : -1,
                                chip.modelData.pid, editor.text);
                        }
                        function cancelRename() {
                            chip._renaming = false;
                            scope.editingOpen = false;
                            editor.visible = false;
                        }

                        // A tiny square action button.
                        component ChipButton: Rectangle {
                            property string symbol
                            property bool active: true
                            signal activated
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                            radius: Theme.radiusSmall
                            color: btnHover.containsMouse && active ? Theme.overlay : "transparent"
                            Text {
                                anchors.centerIn: parent; text: parent.symbol
                                color: parent.active ? Theme.subtext : Theme.withAlpha(Theme.subtext, 0.3)
                                font.pixelSize: Theme.fs.xs
                            }
                            MouseArea {
                                id: btnHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: if (parent.active) parent.activated()
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

            // Below the strip, aligned to its left edge; clamped inside the
            // monitor so a low tile can't push the menu off-screen.
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

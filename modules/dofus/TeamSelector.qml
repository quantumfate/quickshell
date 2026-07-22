// Dofus Team Manager — a floating panel that edits team.json only; it never
// renames the underlying windows (except the explicit Active-Windows gestures,
// which retitle live clients without touching state). Four stacked zones:
//
//   header  — title + read-only prefix, team pills (select/rename/create/delete)
//   pool    — the character pool: add to team, rename everywhere, remove
//   members — the selected team's roster in F1..Fn order (reorder + remove)
//   windows — live Dofus clients: assign/clear a name, add to pool, copy addr/pid
//
//   qs -c quantumfate ipc call teamSelector toggle | show | hide
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
// Basic style: its ComboBox lets us fully re-theme contentItem/background
// without the active desktop style's editable-combo assumptions.
import QtQuick.Controls.Basic as QC
import "../../services"
import "../common"   // ClassIcon

Scope {
    id: scope

    property bool shown: false

    // At most one inline editor is open at a time; "" / -1 means none.
    property string _renamingTeam: ""   // team key whose pill is being renamed
    property bool   _creatingTeam: false
    property string _renamingChar: ""   // pool character being renamed
    property bool   _addingChar: false
    // A ComboBox popup renders outside `card`'s rect, so while one is open we
    // must widen the input mask to the whole window (else its items aren't
    // clickable — clicks fall through the layer).
    property bool   _popupOpen: false
    // Hiding the panel can skip a popup's onClosed, leaving _popupOpen stuck true
    // -> the (now re-shown) full-screen overlay would eat all input. Clear it.
    onShownChanged: if (!shown) _popupOpen = false

    IpcHandler {
        target: "teamSelector"
        function toggle(): void { scope.shown = !scope.shown; }
        function show(): void { scope.shown = true; }
        function hide(): void { scope.shown = false; }
    }

    // name -> live window, for the pool's ✓/online indicators.
    readonly property var _windowByName: {
        var map = {};
        var all = (DofusWindows.slots || []).concat(DofusWindows.unmatched || []);
        for (var i = 0; i < all.length; i++)
            if (all[i].name && all[i].present) map[all[i].name] = all[i];
        return map;
    }

    // Zone 4 mirrors the taskbar: ONLY live windows — present team slots plus
    // unmatched clients. Absent team slots (present:false) are never shown, so
    // reordering the team never appears to touch a window. Sorted by a stable
    // key (address/pid) so the list doesn't reshuffle when the team reorders.
    readonly property var _liveWindows: {
        var present = (DofusWindows.slots || []).filter(s => s.present);
        var all = present.concat(DofusWindows.unmatched || []);
        all.sort((a, b) => (a.address || "").localeCompare(b.address || "") || (a.pid - b.pid));
        return all;
    }

    // Copy an arbitrary string to the Wayland clipboard.
    function _copy(value) {
        copyProc.command = ["bash", "-c", "printf %s \"$1\" | wl-copy", "qfs-copy", "" + value];
        copyProc.running = true;
    }
    Process { id: copyProc }

    // ── small shared building blocks ────────────────────────────────────────

    // Uppercase section label + inline hint + right-aligned count.
    component SectionHeader: RowLayout {
        property string label
        property string hint
        property string count
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: label
            color: Theme.subtext
            font { pixelSize: 11; bold: true; letterSpacing: 1.5; family: Theme.fontFamily }
        }
        Text {
            text: hint
            color: Theme.overlay
            font.pixelSize: 11
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Text {
            text: count
            color: Theme.overlay
            font.pixelSize: 11
        }
    }

    // Compact labelled button; `tone` colours the border/text (defaults muted).
    component TinyButton: Rectangle {
        id: tb
        property string label
        property color tone: Theme.subtext
        property string glyph: ""
        signal clicked()
        implicitWidth: tbRow.implicitWidth + 16
        implicitHeight: 24
        radius: Theme.radiusSmall
        color: tbHover.hovered ? Theme.withAlpha(tone, 0.14) : Theme.surface
        border { width: 1; color: tbHover.hovered ? tone : Theme.border }
        RowLayout {
            id: tbRow
            anchors.centerIn: parent
            spacing: 3
            Text { visible: tb.glyph.length > 0; text: tb.glyph; color: tb.tone; font { pixelSize: 12; bold: true } }
            Text { text: tb.label; color: tbHover.hovered ? tb.tone : Theme.text; font.pixelSize: 11 }
        }
        HoverHandler { id: tbHover }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
    }

    // Single-line committing text field used by every inline editor.
    component InlineInput: Rectangle {
        id: ii
        property alias text: field.text
        property string placeholder
        signal committed(string value)
        signal cancelled()
        implicitWidth: Math.max(field.implicitWidth + 16, 90)
        implicitHeight: 24
        radius: Theme.radiusSmall
        color: Theme.surface
        border { width: 1; color: field.activeFocus ? Theme.accent : Theme.border }
        function _commit() { ii.committed(field.text); }
        TextInput {
            id: field
            anchors { fill: parent; leftMargin: 7; rightMargin: 7 }
            color: Theme.text
            font.pixelSize: 11
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            Keys.onReturnPressed: ii._commit()
            Keys.onEnterPressed: ii._commit()
            Keys.onEscapePressed: ii.cancelled()
            Text {
                anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                visible: field.text.length === 0 && !field.activeFocus
                text: ii.placeholder
                color: Theme.overlay
                font.pixelSize: 11
            }
        }
    }

    PanelWindow {
        id: win
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        // Team switching drives Hyprland, but the inline editors need the
        // keyboard — take focus on demand so typing works.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "quickshell-team-selector"

        // No mask while a dropdown is open, so the popup (rendered outside
        // `card`) stays clickable; otherwise only `card` captures input.
        mask: scope._popupOpen ? null : cardRegion
        Region { id: cardRegion; item: card }

        Rectangle {
            id: card
            x: win.width - width - 20
            y: 20
            width: 1040
            height: Math.min(win.height - 40, body.implicitHeight + 2 * Theme.pad)
            radius: Theme.radius
            color: Theme.withAlpha(Theme.background, 0.97)
            border { width: 1; color: Theme.border }

            // Drag the whole card by its top strip (kept clear of the header row).
            MouseArea {
                id: dragArea
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 30
                cursorShape: Qt.SizeAllCursor
                property real _lastX: 0
                property real _lastY: 0
                onPressed: (mouse) => { _lastX = mouse.x; _lastY = mouse.y }
                onPositionChanged: (mouse) => {
                    card.x = Math.max(0, Math.min(win.width - card.width, card.x + mouse.x - _lastX));
                    card.y = Math.max(0, Math.min(win.height - card.height, card.y + mouse.y - _lastY));
                }
            }

            // Scroll the zones when they overflow the clamped card height.
            Flickable {
                id: flick
                anchors { fill: parent; margins: Theme.pad }
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QC.ScrollBar.vertical: QC.ScrollBar { policy: QC.ScrollBar.AsNeeded }

                ColumnLayout {
                    id: body
                    width: flick.width
                    spacing: Theme.gap

                    // ── Header: title + read-only prefix ────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle { width: 10; height: 10; radius: 5; color: Theme.accent }
                        Text {
                            text: "Dofus Team Manager"
                            color: Theme.text
                            font { pixelSize: 16; bold: true; family: Theme.fontFamily }
                        }
                        Text {
                            text: "edits team.json only · never renames windows"
                            color: Theme.overlay
                            font.pixelSize: 11
                            Layout.fillWidth: true
                        }
                        Text { text: "prefix"; color: Theme.subtext; font.pixelSize: 11 }
                        Rectangle {
                            implicitWidth: prefixText.implicitWidth + 18
                            implicitHeight: 26
                            radius: Theme.radiusSmall
                            color: Theme.surface
                            border { width: 1; color: Theme.border }
                            Text {
                                id: prefixText
                                anchors.centerIn: parent
                                text: DofusState.titlePrefix.trim()
                                color: Theme.text
                                font { pixelSize: 12; family: "monospace" }
                            }
                        }
                    }

                    // ── Header: team pills ──────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "TEAM"
                            color: Theme.subtext
                            font { pixelSize: 11; bold: true; letterSpacing: 1.5 }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: Object.keys(DofusState.teams)

                                Item {
                                    id: pill
                                    required property string modelData
                                    readonly property bool isActive: modelData === DofusState.selected
                                    readonly property bool editing: scope._renamingTeam === modelData
                                    readonly property int count: (DofusState.teams[modelData] || []).length
                                    implicitWidth: editing ? teamEdit.implicitWidth : pillBox.implicitWidth
                                    implicitHeight: 28

                                    // Display chip: ★ selected marker, name, count badge.
                                    Rectangle {
                                        id: pillBox
                                        visible: !pill.editing
                                        anchors.fill: parent
                                        implicitWidth: pillRow.implicitWidth + 20
                                        radius: Theme.radiusPill
                                        color: pill.isActive ? Theme.withAlpha(Theme.accent, 0.22)
                                             : pillHover.hovered ? Theme.surfaceAlt : Theme.surface
                                        border { width: 1; color: pill.isActive ? Theme.accent : Theme.border }

                                        RowLayout {
                                            id: pillRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Text {
                                                text: pill.isActive ? "★" : "☆"
                                                color: pill.isActive ? Theme.accent : Theme.overlay
                                                font.pixelSize: 11
                                            }
                                            Text {
                                                text: pill.modelData
                                                color: pill.isActive ? Theme.accent : Theme.text
                                                font { pixelSize: 12; bold: pill.isActive }
                                            }
                                            Text {
                                                text: pill.count
                                                color: pill.isActive ? Theme.accent : Theme.subtext
                                                font { pixelSize: 11; family: "monospace" }
                                            }
                                        }

                                        HoverHandler { id: pillHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: DofusState.selectTeam(pill.modelData)      // select as default
                                            onDoubleClicked: {                                    // rename team
                                                scope._renamingTeam = pill.modelData;
                                                teamEdit.text = pill.modelData;
                                                teamEdit.forceActiveFocus();
                                            }
                                        }
                                    }

                                    InlineInput {
                                        id: teamEdit
                                        visible: pill.editing
                                        anchors.fill: parent
                                        placeholder: "team name"
                                        onCommitted: (v) => { DofusState.renameTeam(pill.modelData, v); scope._renamingTeam = ""; }
                                        onCancelled: scope._renamingTeam = ""
                                    }
                                }
                            }

                            // Create a new team (inline name entry).
                            Item {
                                implicitWidth: scope._creatingTeam ? createEdit.implicitWidth : createChip.implicitWidth
                                implicitHeight: 28
                                Rectangle {
                                    id: createChip
                                    visible: !scope._creatingTeam
                                    anchors.fill: parent
                                    implicitWidth: createLabel.implicitWidth + 18
                                    radius: Theme.radiusPill
                                    color: createHover.hovered ? Theme.surfaceAlt : "transparent"
                                    border { width: 1; color: Theme.border }
                                    // Dashed look via a muted, transparent-fill border.
                                    Text {
                                        id: createLabel
                                        anchors.centerIn: parent
                                        text: "+ team"
                                        color: Theme.subtext
                                        font.pixelSize: 12
                                    }
                                    HoverHandler { id: createHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { scope._creatingTeam = true; createEdit.text = ""; createEdit.forceActiveFocus(); }
                                    }
                                }
                                InlineInput {
                                    id: createEdit
                                    visible: scope._creatingTeam
                                    anchors.fill: parent
                                    placeholder: "new team"
                                    onCommitted: (v) => { DofusState.createTeam(v); DofusState.selectTeam(v.trim()); scope._creatingTeam = false; }
                                    onCancelled: scope._creatingTeam = false
                                }
                            }
                        }

                        // Delete the selected team.
                        TinyButton {
                            visible: DofusState.selected.length > 0
                            label: "Delete \"" + DofusState.selected + "\""
                            tone: Theme.error
                            onClicked: DofusState.deleteTeam(DofusState.selected)
                        }
                    }

                    // ── Zone 1: Character pool ──────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: poolCol.implicitHeight + 24
                        radius: Theme.radius
                        color: Theme.withAlpha(Theme.surface, 0.5)
                        border { width: 1; color: Theme.border }

                        ColumnLayout {
                            id: poolCol
                            anchors { fill: parent; margins: 16 }
                            spacing: 10

                            SectionHeader {
                                label: "CHARACTER POOL"
                                hint: "click + or drag into team · double-click to rename"
                                count: DofusState.pool.length + " chars"
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: DofusState.pool

                                    Item {
                                        id: chip
                                        required property string modelData
                                        readonly property bool online: !!scope._windowByName[modelData]
                                        readonly property bool editing: scope._renamingChar === modelData
                                        readonly property bool inTeam: (DofusState.team || []).indexOf(modelData) >= 0
                                        implicitWidth: editing ? chipEdit.implicitWidth : chipBox.implicitWidth
                                        implicitHeight: 28

                                        Rectangle {
                                            id: chipBox
                                            visible: !chip.editing
                                            anchors.fill: parent
                                            implicitWidth: chipRow.implicitWidth + 16
                                            radius: Theme.radiusSmall
                                            color: chip.inTeam ? Theme.withAlpha(Theme.accent, 0.14)
                                                 : chipHover.hovered ? Theme.surfaceAlt : Theme.surface
                                            border { width: 1; color: chip.inTeam ? Theme.withAlpha(Theme.accent, 0.5) : Theme.border }

                                            HoverHandler { id: chipHover }
                                            // Underneath the +/× buttons (declared later, so on top):
                                            // catches a double-click on the name to rename the character.
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onDoubleClicked: {
                                                    scope._renamingChar = chip.modelData;
                                                    chipEdit.text = chip.modelData;
                                                    chipEdit.forceActiveFocus();
                                                }
                                            }

                                            RowLayout {
                                                id: chipRow
                                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                                                spacing: 5
                                                Rectangle { visible: chip.online; width: 5; height: 5; radius: 3; color: Theme.success }
                                                // Class emblem, auto-hides when no class assigned.
                                                ClassIcon {
                                                    cls: DofusState.classOf(chip.modelData)   // DofusState singleton
                                                    size: 22
                                                    Layout.preferredWidth: visible ? size : 0
                                                    Layout.preferredHeight: size
                                                }
                                                Text {
                                                    text: chip.modelData
                                                    color: chip.inTeam ? Theme.accent : Theme.text
                                                    font { pixelSize: 12; bold: chip.inTeam }
                                                }
                                                // ✓ already a team member; + to add it.
                                                Rectangle {
                                                    width: 18; height: 18; radius: Theme.radiusSmall
                                                    color: chip.inTeam ? "transparent"
                                                         : addHover.hovered ? Theme.withAlpha(Theme.success, 0.2) : Theme.withAlpha(Theme.accent, 0.18)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: chip.inTeam ? "✓" : "+"
                                                        color: chip.inTeam ? Theme.success : Theme.accent
                                                        font { pixelSize: 11; bold: true }
                                                    }
                                                    HoverHandler { id: addHover }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: !chip.inTeam
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: DofusState.add(chip.modelData)   // add() blocks duplicates
                                                    }
                                                }
                                                // Remove from the pool.
                                                Rectangle {
                                                    width: 16; height: 16; radius: 8
                                                    color: rmHover.hovered ? Theme.withAlpha(Theme.error, 0.22) : "transparent"
                                                    Text { anchors.centerIn: parent; text: "×"; color: rmHover.hovered ? Theme.error : Theme.overlay; font.pixelSize: 12 }
                                                    HoverHandler { id: rmHover }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: DofusState.removeFromPool(chip.modelData)
                                                    }
                                                }
                                            }
                                        }

                                        InlineInput {
                                            id: chipEdit
                                            visible: chip.editing
                                            anchors.fill: parent
                                            placeholder: "name"
                                            onCommitted: (v) => { DofusWindows.renameCharacter(chip.modelData, v); scope._renamingChar = ""; }
                                            onCancelled: scope._renamingChar = ""
                                        }
                                    }
                                }

                                // Add a brand-new character to the pool.
                                Item {
                                    implicitWidth: scope._addingChar ? addCharEdit.implicitWidth : addCharChip.implicitWidth
                                    implicitHeight: 28
                                    Rectangle {
                                        id: addCharChip
                                        visible: !scope._addingChar
                                        anchors.fill: parent
                                        implicitWidth: addCharLabel.implicitWidth + 18
                                        radius: Theme.radiusSmall
                                        color: addCharHover.hovered ? Theme.surfaceAlt : "transparent"
                                        border { width: 1; color: Theme.border }
                                        Text { id: addCharLabel; anchors.centerIn: parent; text: "+ add character"; color: Theme.subtext; font.pixelSize: 12 }
                                        HoverHandler { id: addCharHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { scope._addingChar = true; addCharEdit.text = ""; addCharEdit.forceActiveFocus(); }
                                        }
                                    }
                                    InlineInput {
                                        id: addCharEdit
                                        visible: scope._addingChar
                                        anchors.fill: parent
                                        placeholder: "character name"
                                        onCommitted: (v) => { DofusState.addToPool(v); scope._addingChar = false; }
                                        onCancelled: scope._addingChar = false
                                    }
                                }
                            }
                        }
                    }

                    // ── Zone 2: Selected team roster (F1..Fn) ───────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: teamCol.implicitHeight + 24
                        radius: Theme.radius
                        color: Theme.withAlpha(Theme.surface, 0.5)
                        border { width: 1; color: Theme.border }

                        ColumnLayout {
                            id: teamCol
                            anchors { fill: parent; margins: 16 }
                            spacing: 8

                            SectionHeader {
                                label: "TEAM · " + (DofusState.selected || "—").toUpperCase()
                                hint: "order = F-key focus order · use arrows"
                                count: (DofusState.team || []).length + " members"
                            }

                            // Fixed-height rows in a plain Column so a dragged row
                            // can be lifted with a Translate without the layout
                            // fighting it.
                            Column {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: DofusState.team

                                    Rectangle {
                                        id: row
                                        required property string modelData
                                        required property int index
                                        width: parent ? parent.width : 0
                                        height: 36
                                        radius: Theme.radiusSmall
                                        color: Theme.surface
                                        border { width: 1; color: Theme.border }

                                        RowLayout {
                                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                            spacing: 8

                                            // F-key badge.
                                            Rectangle {
                                                Layout.preferredWidth: 30; Layout.preferredHeight: 22
                                                radius: Theme.radiusSmall
                                                color: Theme.withAlpha(Theme.accent, 0.2)
                                                Text { anchors.centerIn: parent; text: "F" + (row.index + 1); color: Theme.accent; font { pixelSize: 11; bold: true; family: "monospace" } }
                                            }

                                            // Class emblem, assigned in the pool / Class Assigner.
                                            ClassIcon {
                                                cls: DofusState.classOf(row.modelData)   // DofusState singleton
                                                size: 26
                                                Layout.preferredWidth: visible ? size : 0
                                                Layout.preferredHeight: size
                                            }

                                            Text {
                                                text: row.modelData
                                                color: Theme.text
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            // ↑ / ↓ reorder, × remove (character stays in pool).
                                            TinyButton { glyph: "↑"; label: ""; visible: row.index > 0; onClicked: DofusState.reorder(row.index, row.index - 1) }
                                            TinyButton { glyph: "↓"; label: ""; visible: row.index < DofusState.team.length - 1; onClicked: DofusState.reorder(row.index, row.index + 1) }
                                            TinyButton { glyph: "×"; label: ""; tone: Theme.error; onClicked: DofusState.remove(row.index) }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: (DofusState.team || []).length === 0
                                text: "No members — add characters from the pool above."
                                color: Theme.overlay
                                font.pixelSize: 11
                            }
                        }
                    }

                    // ── Zone 3: Active windows ──────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: winCol.implicitHeight + 24
                        radius: Theme.radius
                        color: Theme.withAlpha(Theme.surface, 0.5)
                        border { width: 1; color: Theme.border }

                        ColumnLayout {
                            id: winCol
                            anchors { fill: parent; margins: 16 }
                            spacing: 8

                            SectionHeader {
                                label: "ACTIVE WINDOWS"
                                hint: "live clients · assign the character name to each"
                                count: scope._liveWindows.length + " open"
                            }

                            Repeater {
                                model: scope._liveWindows

                                Rectangle {
                                    id: wrow
                                    required property var modelData
                                    readonly property var w: modelData
                                    readonly property bool named: !!(w.name) && w.name !== "unnamed"
                                    Layout.fillWidth: true
                                    implicitHeight: 52
                                    radius: Theme.radiusSmall
                                    color: (w.focused ?? false) ? Theme.withAlpha(Theme.accent, 0.12) : Theme.surface
                                    border { width: 1; color: (w.focused ?? false) ? Theme.accent : Theme.border }

                                    // Left accent bar: green when named, muted otherwise.
                                    Rectangle {
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: 3
                                        radius: Theme.radiusSmall
                                        color: wrow.named ? Theme.success : Theme.overlay
                                    }

                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                        spacing: 10

                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            color: (wrow.w.focused ?? false) ? Theme.accent : wrow.named ? Theme.success : Theme.overlay
                                        }

                                        // Class emblem for the assigned character; hides when none.
                                        ClassIcon {
                                            cls: wrow.named ? DofusState.classOf(wrow.w.name) : ""
                                            size: 28
                                            Layout.preferredWidth: visible ? size : 0
                                            Layout.preferredHeight: size
                                        }

                                        // Name assignment dropdown + raw title beneath.
                                        ColumnLayout {
                                            Layout.preferredWidth: 170
                                            spacing: 2
                                            QC.ComboBox {
                                                id: nameBox
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 26
                                                readonly property var opts: ["— unnamed —"].concat(DofusState.pool)
                                                model: opts
                                                currentIndex: Math.max(0, opts.indexOf(wrow.w.name))
                                                font.pixelSize: 12
                                                onActivated: (i) => {
                                                    if (i === 0) DofusWindows.clearName(wrow.w.pid);
                                                    else DofusWindows.setName(wrow.w.pid, opts[i]);
                                                }
                                                contentItem: RowLayout {
                                                    spacing: 6
                                                    // Class emblem of the selected character (hides for "— unnamed —").
                                                    ClassIcon {
                                                        cls: wrow.named ? DofusState.classOf(wrow.w.name) : ""
                                                        size: 18
                                                        Layout.leftMargin: 8
                                                        Layout.preferredWidth: visible ? size : 0
                                                        Layout.preferredHeight: size
                                                    }
                                                    Text {
                                                        leftPadding: 8
                                                        rightPadding: 20
                                                        text: nameBox.displayText
                                                        color: wrow.named ? Theme.text : Theme.overlay
                                                        font.pixelSize: 12
                                                        verticalAlignment: Text.AlignVCenter
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                indicator: Text {
                                                    x: nameBox.width - width - 8
                                                    y: (nameBox.height - height) / 2
                                                    text: "▾"; color: Theme.subtext; font.pixelSize: 10
                                                }
                                                background: Rectangle {
                                                    radius: Theme.radiusSmall
                                                    color: Theme.background
                                                    border { width: 1; color: nameBox.activeFocus ? Theme.accent : Theme.border }
                                                }
                                                delegate: QC.ItemDelegate {
                                                    required property var modelData
                                                    required property int index
                                                    width: nameBox.width
                                                    contentItem: RowLayout {
                                                        spacing: 6
                                                        // Class emblem per option (index 0 is "— unnamed —" -> none).
                                                        ClassIcon {
                                                            cls: index === 0 ? "" : DofusState.classOf(modelData)
                                                            size: 18
                                                            Layout.preferredWidth: visible ? size : 0
                                                            Layout.preferredHeight: size
                                                        }
                                                        Text {
                                                            text: modelData
                                                            color: index === nameBox.currentIndex ? Theme.accent : Theme.text
                                                            font.pixelSize: 12
                                                            verticalAlignment: Text.AlignVCenter
                                                            Layout.fillWidth: true
                                                        }
                                                    }
                                                    background: Rectangle {
                                                        color: highlighted ? Theme.surfaceAlt : Theme.background
                                                    }
                                                    highlighted: nameBox.highlightedIndex === index
                                                }
                                                popup: QC.Popup {
                                                    y: nameBox.height
                                                    width: nameBox.width
                                                    implicitHeight: Math.min(contentItem.implicitHeight, 240)
                                                    padding: 1
                                                    onOpened: scope._popupOpen = true
                                                    onClosed: scope._popupOpen = false
                                                    contentItem: ListView {
                                                        clip: true
                                                        implicitHeight: contentHeight
                                                        model: nameBox.delegateModel
                                                        currentIndex: nameBox.highlightedIndex
                                                        QC.ScrollBar.vertical: QC.ScrollBar {}
                                                    }
                                                    background: Rectangle {
                                                        color: Theme.background
                                                        border { width: 1; color: Theme.border }
                                                        radius: Theme.radiusSmall
                                                    }
                                                }
                                            }
                                            Text {
                                                text: wrow.w.title || "—"
                                                color: Theme.overlay
                                                font { pixelSize: 10; family: "monospace" }
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        // addr / pid metadata.
                                        RowLayout {
                                            spacing: 6
                                            Layout.fillWidth: true
                                            Text { text: "addr"; color: Theme.overlay; font.pixelSize: 10 }
                                            Text { text: wrow.w.address || "—"; color: Theme.subtext; font { pixelSize: 11; family: "monospace" } }
                                            Text { text: "pid"; color: Theme.overlay; font.pixelSize: 10; Layout.leftMargin: 6 }
                                            Text { text: (wrow.w.pid ?? -1) > 0 ? "" + wrow.w.pid : "—"; color: Theme.subtext; font { pixelSize: 11; family: "monospace" } }
                                            Item { Layout.fillWidth: true }
                                        }

                                        // Focus the window and raise it to the top.
                                        TinyButton { glyph: "→"; label: "focus"; tone: Theme.accent; visible: !!(wrow.w.selector); onClicked: DofusWindows.focus(wrow.w.selector) }
                                        TinyButton { glyph: "⧉"; label: "addr"; visible: !!(wrow.w.address); onClicked: scope._copy(wrow.w.address) }
                                        TinyButton { glyph: "⧉"; label: "pid"; visible: (wrow.w.pid ?? -1) > 0; onClicked: scope._copy(wrow.w.pid) }
                                        TinyButton { glyph: "+"; label: "pool"; tone: Theme.success; visible: wrow.named; onClicked: DofusState.addToPool(wrow.w.name) }
                                        TinyButton { label: "clear"; visible: wrow.named; onClicked: DofusWindows.clearName(wrow.w.pid) }
                                    }
                                }
                            }

                            Text {
                                visible: scope._liveWindows.length === 0
                                text: "No Dofus windows open."
                                color: Theme.overlay
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}

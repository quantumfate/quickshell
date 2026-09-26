// ObsidianCreate — modal "new note" form for the Zettelkasten. Collects the
// note type, title, and topic tag path; previews the index chain the script
// will create (live from the reactive ObsidianVault store), then shells
// obsidian_vault.py through the wrapper.
//
// Behaviour:
//   * The bind toggles: MOD+o → n opens, the same bind (or Esc) closes it.
//   * Closing while a create is running ABORTS it (no note is written).
//   * Clicking the dimmed area does NOT close the form.
//   * The "Open in Obsidian" toggle drives the create --open flag.
//
//   qs -c quantumfate ipc call -- obsidianCreate show | hide | toggle
//   (the `--` matters: `show` otherwise collides with the `ipc show` verb)
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"
import "../common"        // Surface

Scope {
    id: scope

    property bool shown: false
    property string noteType: "atomic"
    property string _error: ""
    property int _completionIndex: -1

    readonly property var types: [
        { key: "atomic", label: "Atomic" },
        { key: "fleeting", label: "Fleeting" },
        { key: "moc", label: "MOC" },
        { key: "journal", label: "Journal" },
        { key: "blog", label: "Blog" }
    ]

    // Completion candidates, filtered live from the store's topic paths.
    readonly property var completions: {
        const p = topicInput.text.trim();
        if (p.length < 2) return [];
        return ObsidianVault.topicPaths().filter(t =>
            t.toLowerCase().indexOf(p.toLowerCase()) === 0
        ).slice(0, 8);
    }

    // Index-chain preview: what exists, what will be created.
    readonly property var chain: ObsidianVault.chainInfo(topicInput.text)

    IpcHandler {
        target: "obsidianCreate"
        function toggle(): void { scope.shown ? scope.hide() : scope.show(); }
        function show(): void { scope.show(); }
        function hide(): void { scope.hide(); }
    }

    function show() { scope._open(); }
    function hide() {
        if (ObsidianVault.busy) ObsidianVault.abort();
        scope.shown = false;
    }

    // The singleton notifies on outcome; we only need to close on success.
    Connections {
        target: ObsidianVault
        function onCreated(title, ok) { if (ok) scope.shown = false; }
    }

    function _open() {
        scope.noteType = "atomic";
        scope._error = "";
        scope._completionIndex = -1;
        titleInput.text = "";
        topicInput.text = ObsidianVault.lastTopic;
        scope.shown = true;
        titleInput.forceActiveFocus();
    }

    function _submit() {
        const title = titleInput.text.trim();
        const topic = topicInput.text.trim();
        if (ObsidianVault.busy || !title || !topic) return;
        scope._error = "";
        ObsidianVault.create(scope.noteType, title, topic);
    }

    function _pickCompletion() {
        const list = scope.completions;
        if (scope._completionIndex >= 0 && scope._completionIndex < list.length) {
            topicInput.text = list[scope._completionIndex];
            topicInput.cursorPosition = topicInput.text.length;
        }
        scope._completionIndex = -1;
    }

    function _completionStep(delta) {
        if (scope.completions.length === 0) return;
        const n = scope.completions.length;
        scope._completionIndex = (scope._completionIndex + delta + n) % n;
    }

    PanelWindow {
        id: win
        visible: scope.shown
        screen: PanelBus.screenObject(PanelBus.activeScreen)
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: scope.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-obsidian-create"

        onVisibleChanged: if (visible) titleInput.forceActiveFocus();

        // No dim backdrop: the panel is a form, not a modal. Outside clicks
        // must NOT close (the bind/Esc does, and closing while busy aborts the
        // create), so swallow them so they don't fall through to the bar.
        MouseArea { anchors.fill: parent }

        readonly property string _screenName: win.screen?.name ?? ""
        // Placed in the scene's published work area (docs/scenes.md
        // "Areas"): same width ratio the card always used against the whole
        // screen, now capped against the area.
        readonly property var _box: PanelBus.surfaceBox(win._screenName, "obsidiancreate", { width: 600, height: col.implicitHeight + 2 * 28 })

        Surface {
            id: card
            x: win._box.x
            y: win._box.y
            width: win._box.width
            height: win._box.height
            radius: Theme.radius
            elevation: "modal"

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: Theme.space.xl * 2 }
                spacing: Theme.space.xl

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.lg
                    Rectangle { implicitWidth: 12; implicitHeight: 12; radius: 6; color: Theme.accent }
                    Text {
                        text: "New Obsidian note"
                        color: Theme.text
                        font { pixelSize: Theme.fs.lg; bold: true; family: Theme.fontFamily }
                    }
                    Text {
                        text: "Zettelkasten bootstrap"
                        color: Theme.overlay
                        font.pixelSize: Theme.fs.sm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space.sm
                    spacing: Theme.space.md
                    Text {
                        text: "TYPE"
                        color: Theme.subtext
                        font { pixelSize: Theme.fs.sm; bold: true; letterSpacing: 1.5 }
                    }
                    Repeater {
                        model: scope.types
                        Rectangle {
                            id: typeItem
                            required property var modelData
                            readonly property bool active: scope.noteType === typeItem.modelData.key
                            implicitWidth: typeLabel.implicitWidth + 22
                            implicitHeight: 30
                            radius: Theme.radiusPill
                            color: typeItem.active ? Theme.withAlpha(Theme.accent, 0.22)
                                         : typeHover.hovered ? Theme.surfaceAlt : Theme.surface
                            border { width: 1; color: typeItem.active ? Theme.accent : Theme.border }
                            Text {
                                id: typeLabel
                                anchors.centerIn: parent
                                text: typeItem.modelData.label
                                color: typeItem.active ? Theme.accent : Theme.text
                                font { pixelSize: Theme.fs.sm; bold: typeItem.active }
                            }
                            HoverHandler { id: typeHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.noteType = typeItem.modelData.key
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                Text {
                    text: "TITLE"
                    color: Theme.subtext
                    font { pixelSize: Theme.fs.sm; bold: true; letterSpacing: 1.5 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: titleInput.implicitHeight + 18
                    radius: 6
                    color: Theme.surface
                    border { width: 1; color: titleInput.activeFocus ? Theme.accent : Theme.border }
                    TextInput {
                        id: titleInput
                        anchors { fill: parent; margins: Theme.space.md }
                        color: Theme.text
                        font.pixelSize: Theme.fs.md
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        Keys.onReturnPressed: scope._submit()
                        Keys.onEnterPressed: scope._submit()
                        Keys.onEscapePressed: scope.hide()
                    }
                }

                Text {
                    text: "TOPIC — tag path (chain below is what will be created)"
                    color: Theme.subtext
                    font { pixelSize: Theme.fs.sm; bold: true; letterSpacing: 1.5 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: topicInput.implicitHeight + 18
                    radius: 6
                    color: Theme.surface
                    border { width: 1; color: topicInput.activeFocus ? Theme.accent : Theme.border }
                    TextInput {
                        id: topicInput
                        anchors { fill: parent; margins: Theme.space.md }
                        color: Theme.text
                        font.pixelSize: Theme.fs.md
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        Keys.onDownPressed: scope._completionStep(1)
                        Keys.onUpPressed: scope._completionStep(-1)
                        Keys.onTabPressed: (event) => { scope._pickCompletion(); event.accepted = true; }
                        Keys.onReturnPressed: scope._submit()
                        Keys.onEnterPressed: scope._submit()
                        Keys.onEscapePressed: scope.hide()
                    }
                }

                Rectangle {
                    visible: scope.completions.length > 0
                    Layout.fillWidth: true
                    Layout.maximumHeight: 168
                    radius: 6
                    color: Theme.backgroundAlt
                    border { width: 1; color: Theme.border }
                    clip: true
                    ListView {
                        id: completionList
                        anchors.fill: parent
                        model: scope.completions
                        currentIndex: scope._completionIndex
                        delegate: Rectangle {
                            id: completionItem
                            required property int index
                            required property string modelData
                            readonly property bool highlight: completionList.currentIndex === completionItem.index
                            width: completionList.width
                            implicitHeight: 28
                            color: completionItem.highlight ? Theme.surfaceAlt : "transparent"
                            Text {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                leftPadding: 10
                                elide: Text.ElideRight
                                text: completionItem.modelData
                                color: completionItem.highlight ? Theme.accent : Theme.text
                                font { pixelSize: Theme.fs.sm; family: "monospace" }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    topicInput.text = completionItem.modelData;
                                    topicInput.cursorPosition = topicInput.text.length;
                                    scope._completionIndex = -1;
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: topicInput.text.trim().length > 0
                    Layout.fillWidth: true
                    spacing: Theme.space.sm
                    Repeater {
                        model: scope.chain
                        Row {
                            id: chainRow
                            required property var modelData
                            spacing: Theme.space.md
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                anchors.verticalCenter: parent.verticalCenter
                                color: chainRow.modelData.state === "exists" ? Theme.success
                                     : chainRow.modelData.state === "stub" ? Theme.warning : Theme.overlay
                            }
                            Text {
                                text: chainRow.modelData.path + "  [" + (chainRow.modelData.kind === "idx" ? "idx" : "meta_idx") + "]"
                                color: Theme.subtext
                                font { pixelSize: Theme.fs.xs; family: "monospace" }
                            }
                            Text {
                                text: chainRow.modelData.state === "exists" ? chainRow.modelData.note
                                     : chainRow.modelData.state === "stub" ? chainRow.modelData.note + " (stub)"
                                     : "will create"
                                color: chainRow.modelData.state === "exists" ? Theme.success
                                     : chainRow.modelData.state === "stub" ? Theme.warning : Theme.overlay
                                font.pixelSize: Theme.fs.xs
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space.xs
                    spacing: Theme.space.lg
                    Rectangle {
                        id: openToggle
                        implicitWidth: openState.implicitWidth + 22
                        implicitHeight: 30
                        radius: Theme.radiusPill
                        color: ObsidianVault.openOnCreate ? Theme.withAlpha(Theme.accent, 0.22) : Theme.surface
                        border { width: 1; color: ObsidianVault.openOnCreate ? Theme.accent : Theme.border }
                        Text {
                            id: openState
                            anchors.centerIn: parent
                            text: ObsidianVault.openOnCreate ? "Open on" : "Open off"
                            color: ObsidianVault.openOnCreate ? Theme.accent : Theme.text
                            font { pixelSize: Theme.fs.sm; bold: ObsidianVault.openOnCreate }
                        }
                        HoverHandler { id: openHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ObsidianVault.setOpenOnCreate(!ObsidianVault.openOnCreate)
                        }
                    }
                    Text {
                        text: "Open the created note in Obsidian"
                        color: Theme.subtext
                        font.pixelSize: Theme.fs.sm
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.lg
                    Text {
                        text: scope._error.length > 0 ? scope._error
                             : ObsidianVault.busy ? "Creating… (close to abort)"
                             : "Enter to create · Esc to cancel"
                        color: scope._error.length > 0 ? Theme.error : Theme.subtext
                        font.pixelSize: Theme.fs.sm
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        implicitWidth: submitLabel.implicitWidth + 28
                        implicitHeight: 34
                        radius: Theme.radiusPill
                        color: submitHover.hovered ? Theme.withAlpha(Theme.accent, 0.22) : Theme.surface
                        border { width: 1; color: Theme.accent }
                        Text {
                            id: submitLabel
                            anchors.centerIn: parent
                            text: "Create note"
                            color: Theme.accent
                            font { pixelSize: Theme.fs.sm; bold: true }
                        }
                        HoverHandler { id: submitHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: scope._submit()
                        }
                    }
                }
            }
        }
    }
}

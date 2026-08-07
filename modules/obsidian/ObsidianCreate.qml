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
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services"

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
        visible: scope.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: scope.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "quickshell-obsidian-create"

        onVisibleChanged: if (visible) titleInput.forceActiveFocus();

        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.background, 0.5)
            // Outside clicks must NOT close (the bind/Esc does, and closes while
            // busy aborts the create). Swallow clicks so they don't fall through
            // to the bar behind the dimmer.
            MouseArea { anchors.fill: parent }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.52, 600)
            implicitHeight: col.implicitHeight + 2 * 28
            radius: 12
            color: Theme.withAlpha(Theme.background, 0.98)
            border { width: 1; color: Theme.border }

            ColumnLayout {
                id: col
                anchors { fill: parent; margins: 28 }
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle { width: 12; height: 12; radius: 6; color: Theme.accent }
                    Text {
                        text: "New Obsidian note"
                        color: Theme.text
                        font { pixelSize: 17; bold: true; family: Theme.fontFamily }
                    }
                    Text {
                        text: "Zettelkasten bootstrap"
                        color: Theme.overlay
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    Text {
                        text: "TYPE"
                        color: Theme.subtext
                        font { pixelSize: 12; bold: true; letterSpacing: 1.5 }
                    }
                    Repeater {
                        model: scope.types
                        Rectangle {
                            required property var modelData
                            readonly property bool active: scope.noteType === modelData.key
                            implicitWidth: typeLabel.implicitWidth + 22
                            implicitHeight: 30
                            radius: Theme.radiusPill
                            color: active ? Theme.withAlpha(Theme.accent, 0.22)
                                         : typeHover.hovered ? Theme.surfaceAlt : Theme.surface
                            border { width: 1; color: active ? Theme.accent : Theme.border }
                            Text {
                                id: typeLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: active ? Theme.accent : Theme.text
                                font { pixelSize: 12; bold: active }
                            }
                            HoverHandler { id: typeHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.noteType = modelData.key
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                Text {
                    text: "TITLE"
                    color: Theme.subtext
                    font { pixelSize: 12; bold: true; letterSpacing: 1.5 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: titleInput.implicitHeight + 18
                    radius: 6
                    color: Theme.surface
                    border { width: 1; color: titleInput.activeFocus ? Theme.accent : Theme.border }
                    TextInput {
                        id: titleInput
                        anchors { fill: parent; margins: 8 }
                        color: Theme.text
                        font.pixelSize: 14
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
                    font { pixelSize: 12; bold: true; letterSpacing: 1.5 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: topicInput.implicitHeight + 18
                    radius: 6
                    color: Theme.surface
                    border { width: 1; color: topicInput.activeFocus ? Theme.accent : Theme.border }
                    TextInput {
                        id: topicInput
                        anchors { fill: parent; margins: 8 }
                        color: Theme.text
                        font.pixelSize: 14
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        Keys.onDownPressed: scope._completionStep(1)
                        Keys.onUpPressed: scope._completionStep(-1)
                        Keys.onTabPressed: { scope._pickCompletion(); event.accepted = true; }
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
                            required property int index
                            required property string modelData
                            readonly property bool highlight: completionList.currentIndex === index
                            width: completionList.width
                            implicitHeight: 28
                            color: highlight ? Theme.surfaceAlt : "transparent"
                            Text {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                leftPadding: 10
                                elide: Text.ElideRight
                                text: modelData
                                color: highlight ? Theme.accent : Theme.text
                                font { pixelSize: 12; family: "monospace" }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    topicInput.text = modelData;
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
                    spacing: 4
                    Repeater {
                        model: scope.chain
                        Row {
                            required property var modelData
                            spacing: 8
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.state === "exists" ? Theme.success
                                     : modelData.state === "stub" ? Theme.warning : Theme.overlay
                            }
                            Text {
                                text: modelData.path + "  [" + (modelData.kind === "idx" ? "idx" : "meta_idx") + "]"
                                color: Theme.subtext
                                font { pixelSize: 11; family: "monospace" }
                            }
                            Text {
                                text: modelData.state === "exists" ? modelData.note
                                     : modelData.state === "stub" ? modelData.note + " (stub)"
                                     : "will create"
                                color: modelData.state === "exists" ? Theme.success
                                     : modelData.state === "stub" ? Theme.warning : Theme.overlay
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 12
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
                            font { pixelSize: 12; bold: ObsidianVault.openOnCreate }
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
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: scope._error.length > 0 ? scope._error
                             : ObsidianVault.busy ? "Creating… (close to abort)"
                             : "Enter to create · Esc to cancel"
                        color: scope._error.length > 0 ? Theme.error : Theme.subtext
                        font.pixelSize: 12
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
                            font { pixelSize: 12; bold: true }
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

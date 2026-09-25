// OpenProjects — left isle: which projects are running, and which one you are
// in. Click one to go to it.
//
// The bar is the way BACK to a project that is already open; `,proj.sh pick`
// only offers the ones that are not, so the two never present the same choice
// twice. That makes this the switcher, not a decoration: it shows nothing at
// all when no project is running, and a project disappears from it the moment
// its last window closes, because ProjectWindows reads the compositor rather
// than any remembered list.
//
// Not to be confused with ProjectsPill, which is repo HEALTH (branch, dirty
// counts) over the projects store. This one is about what is on screen now.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../services"   // Theme, ProjectWindows, PanelBus

Row {
    id: root
    property string screenName: ""

    // This screen's scene only (docs: the widgets describe the workspace the
    // bar is on). A project open on another scene is that scene's business.
    // What the DESK says is on this screen (PanelBus.sceneOn): published by
    // the same layout pass that places the windows, so it cannot drift from
    // the layout the way an event-fed cache does.
    readonly property string scene: PanelBus.sceneOn(root.screenName)
    // Scoped to this screen's scene when that is known. When it is NOT --
    // `sceneByScreen` is event-fed and a freshly started shell has missed
    // every event until the first workspace change -- showing everything
    // beats showing nothing: an empty widget reads as a broken one, and this
    // is exactly the state a shell restart lands in.
    readonly property var shown: {
        // Read the property FIRST, every time. A QML binding tracks the
        // properties it reads, not the functions it calls: bound only to
        // `projectsOn(scene)` this evaluated once — while the model was still
        // empty, moments after startup — registered no dependency on
        // `ProjectWindows.projects`, and never ran again. The widget then
        // stayed empty for the life of the shell while a direct call to the
        // same function returned both projects (measured in the nested
        // instance: `filtered=2 shown=0`).
        const all = ProjectWindows.projects;
        return root.scene !== "" ? ProjectWindows.projectsOn(root.scene) : all;
    }

    // Whether this widget has anything to say, asked WITHOUT asking whether
    // it is visible. `visible` in QML is effective visibility: a child of an
    // invisible parent reports `false` whatever it was set to. The isle
    // around this one is drawn only while its contents have something to
    // say, so reading `openProjects.visible` there latched the pair off for
    // the life of the shell -- the isle was invisible because the widget
    // read as invisible because the isle was invisible. The model answers
    // the question; visibility never does.
    readonly property bool hasContent: root.shown.length > 0
    visible: root.hasContent
    Repeater {
        model: root.shown

        Rectangle {
            id: chip
            required property var modelData

            // No fill for the focused project: the chip stays negative space
            // that flows into the isle behind it, and the accent-coloured
            // bold label is the whole indicator. A surface here read as a
            // second shape competing with the tab strip beside it.
            color: hover.hovered ? Theme.surface : "transparent"
            radius: Theme.radiusPill
            implicitWidth: label.implicitWidth + Theme.space.md * 2
            implicitHeight: label.implicitHeight + Theme.space.xs * 2

            Text {
                id: label
                anchors.centerIn: parent
                text: chip.modelData.name
                color: chip.modelData.focused ? Theme.accent
                    : hover.hovered ? Theme.text : Theme.overlay
                font {
                    family: Theme.fontFamily
                    pixelSize: Theme.barFontSize
                    weight: chip.modelData.focused ? Font.Bold : Theme.barFontWeight
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: ProjectWindows.focus(chip.modelData.name)
            }

            HoverHandler { id: hover }
            HoverTip {
                shown: hover.hovered
                screenName: root.screenName
                // The tabs are what the project's own keys reach, so naming
                // them here says what pressing those keys would find.
                text: chip.modelData.name
                    + " · " + chip.modelData.addresses.length + " windows"
                    + (chip.modelData.slots.length > 0
                        ? " · " + chip.modelData.slots.join(" ") : "")
            }
        }
    }
}

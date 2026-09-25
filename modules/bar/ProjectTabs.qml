// ProjectTabs — the tabs of the project you are in, and which one is active.
//
// The compositor's groupbar used to carry this. It is off (hyprrepo
// hypr/conf.lua): Hyprland reserves the strip's height inside the group's own
// box, so every group and ungroup resized the tile and the isles that follow
// the published tile geometry jumped with it. The information is not
// decoration though — a project is four terminals in one tile, and without a
// strip nothing on screen says which of them you are typing into.
//
// Reads ProjectWindows, which reads the compositor: a tab exists exactly as
// long as its window does. Clicking one focuses that window; `mod+j`/`mod+k`
// walk the same list in the same order (hyprrepo docs/declared-groups.md).
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "../../services"   // Theme, ProjectWindows, PanelBus

Row {
    id: root
    // The scene this screen is standing in — the widget describes THIS
    // screen's workspace, never whatever holds the keyboard elsewhere.
    property string screenName: ""

    // What the desk says is on this screen — see OpenProjects.
    readonly property string scene: PanelBus.sceneOn(root.screenName)
    // Same fallback as OpenProjects: before this screen's scene is known, the
    // focused project is better than nothing.
    readonly property var project: {
        // The property read is the dependency — see OpenProjects' `shown`.
        const all = ProjectWindows.projects;
        if (root.scene === "") return ProjectWindows.focusedProject;
        return all.length ? ProjectWindows.projectOn(root.scene) : null;
    }
    readonly property var tabs: root.project ? (root.project.tabs || []) : []

    // Nothing to say when you are not in a project, and nothing worth a strip
    // when the project is a single window. Asked as a property of the MODEL,
    // never as `visible` -- see OpenProjects' `hasContent` for why reading a
    // child's visibility to decide its parent's latches both off.
    readonly property bool hasContent: root.tabs.length > 1
    visible: root.hasContent
    spacing: Theme.space.xs
    leftPadding: Theme.space.xs
    rightPadding: Theme.space.md

    // A rule between the project's name and its tabs: they are two different
    // questions (which project, which tab of it) and read as one list of
    // chips without it. Same height as a tab's text, so it reads as a
    // divider rather than another chip.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: Theme.barFontSize
        color: Theme.overlay
        opacity: 0.5
    }

    Repeater {
        model: root.tabs

        Rectangle {
            id: tab
            required property var modelData

            // Every tab is bare text: the active one is the accent-coloured,
            // bold one. A filled pill here fought the project chip beside it
            // for attention -- two filled shapes in a strip this small read as
            // two lists, not one answer.
            color: "transparent"
            radius: Theme.radiusPill
            implicitWidth: label.implicitWidth + Theme.space.sm * 2
            implicitHeight: label.implicitHeight + Theme.space.xs * 2

            Text {
                id: label
                anchors.centerIn: parent
                // A window still waiting for its `slot:` tag is a real tab
                // with no name yet; a dot keeps the strip's shape rather than
                // collapsing it for the beat before the tag lands.
                text: tab.modelData.slot || "·"
                color: tab.modelData.focused ? Theme.accent
                    : hover.hovered ? Theme.text : Theme.overlay
                font {
                    family: Theme.fontFamily
                    pixelSize: Theme.barFontSize
                    weight: tab.modelData.focused ? Font.Bold : Theme.barFontWeight
                }
            }

            HoverHandler { id: hover }
            TapHandler {
                onTapped: ProjectWindows.focusWindow(tab.modelData.address)
            }
        }
    }
}

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
import QtQuick
import "../../services"   // Theme, ProjectWindows

Row {
    id: root
    property string screenName: ""

    visible: ProjectWindows.projects.length > 0
    spacing: Theme.space.xs
    leftPadding: Theme.space.md
    rightPadding: Theme.space.md

    Repeater {
        model: ProjectWindows.projects

        Rectangle {
            id: chip
            required property var modelData

            // The focused project is the one carrying a surface; the rest are
            // named in the quiet colour. One highlight, so "where am I" is
            // answerable at a glance rather than by reading every label.
            color: modelData.focused ? Theme.surfaceAlt
                : hover.hovered ? Theme.surface : "transparent"
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

// MeterControl — glyph + thin track, the shared shape for brightness and
// volume (04-persistent-bar.md, centre zone). The numeric value rides above
// the track only for a moment after it changes, then fades, leaving the
// track itself as the at-rest read — so neither control ever grows or shifts
// the centre zone's width when its value changes.
pragma ComponentBehavior: Bound
import QtQuick
import "../../services"   // Theme

Item {
    id: root

    property string glyph: ""
    property real ratio: 0          // 0..1 track fill
    property bool muted: false
    property string valueText: ""   // shown briefly on change
    property string screenName: ""
    property string tip: ""

    signal tapped()
    signal wheelUp()
    signal wheelDown()

    implicitWidth: row.implicitWidth
    implicitHeight: 22

    // The numeric readout is transient: 1200ms visible, then a fade, then
    // gone — the track is the permanent signal, the number is a courtesy.
    property bool _flash: false
    Timer { id: flashOff; interval: 1200; onTriggered: root._flash = false }
    onValueTextChanged: { root._flash = true; flashOff.restart(); }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.sm

        Text {
            text: root.glyph
            color: root.muted ? Theme.error : Theme.text
            font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            id: trackBox
            width: 48; height: 12
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 2; radius: 1
                color: Theme.surfaceAlt
                opacity: root.muted ? 0.4 : 1.0

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.ratio))
                    height: parent.height; radius: parent.radius
                    color: root.muted ? Theme.error : Theme.accent
                    visible: !root.muted
                }
            }

            Text {
                anchors { bottom: track.top; horizontalCenter: track.horizontalCenter; bottomMargin: 2 }
                text: root.valueText
                color: Theme.subtext
                font { family: Theme.fontFamily; pixelSize: Theme.fs.xs }
                opacity: root._flash ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.tapped()
        onWheel: (w) => w.angleDelta.y > 0 ? root.wheelUp() : root.wheelDown()
    }

    HoverHandler { id: hover }
    HoverTip { shown: hover.hovered && root.tip !== ""; screenName: root.screenName; text: root.tip }
}

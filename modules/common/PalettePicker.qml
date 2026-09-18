// PalettePicker — a reusable swatch grid for choosing a palette by name.
// Built for LEO-384: the mode panel used to lay every palette option out in
// one fixed-width row, so each new palette made every label narrower until
// they collided. A Flow wraps instead of squeezing: each chip keeps a fixed
// footprint no matter how many palettes exist — 4 or 40 entries render the
// same chip size, only the row count changes. Swatch first, name never
// shrinks below legibility.
//
// Hovering a chip never resizes anything — only its own border/background
// color changes. Hover DETAIL (a preview line, sample hexes, whatever the
// caller wants) is deliberately not drawn here: report it through
// `onHoverName`/`onHoverEnd` and render it in a HoverDetail.qml sibling,
// which reserves its own space so the surrounding layout never jumps.
//
// Shared with the theme panel (LEO-366) — keep this file mode/theme agnostic.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../services"   // Theme

Flow {
    id: root

    // [{ name, swatch }] — caller resolves the representative colour
    // (e.g. Theme.palettes[name].base) so this component never reaches into
    // a particular store.
    property var entries: []
    property string value: ""
    property var onPick: null        // (name) => void
    property var onHoverName: null   // (name) => void, or null to skip hover reporting
    property var onHoverEnd: null    // () => void, or null

    Layout.fillWidth: true
    spacing: Theme.space.xs

    Repeater {
        model: root.entries
        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool active: chip.modelData.name === root.value

            // Fixed footprint: this is what keeps the picker readable at any
            // palette count — a new entry adds a row, never shrinks a chip.
            width: Theme.fs.xl * 4.5
            implicitHeight: Theme.fs.sm * 2 + Theme.space.sm * 2
            radius: Theme.radiusSmall
            color: chip.active ? Theme.withAlpha(Theme.accent, 0.18) : Theme.withAlpha(Theme.surface, 0.5)
            border { width: 1; color: chip.active ? Theme.accent : Theme.withAlpha(Theme.border, 0.5) }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                spacing: Theme.space.xs

                Rectangle {
                    width: Theme.fs.sm
                    height: Theme.fs.sm
                    radius: 3
                    color: chip.modelData.swatch
                    border { width: 1; color: Theme.withAlpha(Theme.border, 0.6) }
                }
                Text {
                    Layout.fillWidth: true
                    text: chip.modelData.name
                    color: chip.active ? Theme.accent : Theme.subtext
                    font { family: Theme.fontFamily; pixelSize: Theme.fs.xs; weight: chip.active ? Font.Bold : Font.Normal }
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: if (root.onHoverName) root.onHoverName(chip.modelData.name)
                onExited: if (root.onHoverEnd) root.onHoverEnd()
                onClicked: if (root.onPick) root.onPick(chip.modelData.name)
            }
        }
    }
}

pragma Singleton
// Central theme. One place every widget reads colors from, so a future
// "reload my whole theme" is a single palette switch here (and eventually the
// seam to unify Hyprland/GTK/etc. theming under Quickshell).
//
// The active palette name is backed by a Store ($XDG_STATE_HOME/theme.json),
// so it can be changed live from anywhere and every binding reacts:
//   qs -c quantumfate ipc call theme set mocha    (once more palettes exist)
//   or just edit theme.json -> { "palette": "frappe" }
import Quickshell
import Quickshell.Io
import QtQuick
import "."

Singleton {
    id: root

    Store { id: store; name: "theme" }

    readonly property string name: store.get("palette") ?? "frappe"

    // Raw palettes. Add more here; switching is just a name change.
    readonly property var palettes: ({
        frappe: {
            rosewater: "#f2d5cf", flamingo: "#eebebe", pink: "#f4b8e4", mauve: "#ca9ee6",
            red: "#e78284", maroon: "#ea999c", peach: "#ef9f76", yellow: "#e5c890",
            green: "#a6d189", teal: "#81c8be", sky: "#99d1db", sapphire: "#85c1dc",
            blue: "#8caaee", lavender: "#babbf1",
            text: "#c6d0f5", subtext1: "#b5bfe2", subtext0: "#a5adce",
            overlay2: "#949cbb", overlay1: "#838ba7", overlay0: "#737994",
            surface2: "#626880", surface1: "#51576d", surface0: "#414559",
            base: "#303446", mantle: "#292c3c", crust: "#232634"
        }
    })

    // Current raw palette (named colors: Theme.c.mauve, ...).
    readonly property var c: palettes[name] ?? palettes.frappe

    // Semantic roles — prefer these in widgets so a palette swap Just Works.
    readonly property color background:    c.base
    readonly property color backgroundAlt: c.mantle
    readonly property color surface:       c.surface0
    readonly property color surfaceAlt:    c.surface1
    readonly property color overlay:       c.overlay0
    readonly property color border:        c.surface2
    readonly property color text:          c.text
    readonly property color subtext:       c.subtext0
    readonly property color accent:        c.mauve
    readonly property color accentAlt:     c.lavender
    readonly property color success:       c.green
    readonly property color warning:       c.yellow
    readonly property color error:         c.red

    // Shape/spacing tokens, so widgets stay visually consistent too.
    readonly property int radius: 12
    readonly property int radiusSmall: 6
    readonly property int gap: 8
    readonly property int pad: 12

    // color + alpha (0..1) -> rgba, for translucent panels/backdrops.
    function withAlpha(color, a) {
        return Qt.rgba(color.r, color.g, color.b, a);
    }

    // ipc: qs -c quantumfate ipc call theme set <palette> | get
    IpcHandler {
        target: "theme"
        function set(palette: string): void {
            if (root.palettes[palette]) store.set({ palette: palette });
        }
        function get(): string { return root.name; }
    }
}

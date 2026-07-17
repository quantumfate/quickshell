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

    Store {
        id: store
        name: "theme"
        defaults: ({ palette: "macchiato", cheatsheet_peek_ms: 6000 })
    }

    readonly property string name: store.get("palette") ?? "macchiato"

    // Raw palettes. Add more here; switching is just a name change. `cycle`
    // walks them in insertion order.
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
        },
        macchiato: {
            rosewater: "#f4dbd6", flamingo: "#f0c6c6", pink: "#f5bde6", mauve: "#c6a0f6",
            red: "#ed8796", maroon: "#ee99a0", peach: "#f5a97f", yellow: "#eed49f",
            green: "#a6da95", teal: "#8bd5ca", sky: "#91d7e3", sapphire: "#7dc4e4",
            blue: "#8aadf4", lavender: "#b7bdf8",
            text: "#cad3f5", subtext1: "#b8c0e0", subtext0: "#a5adcb",
            overlay2: "#939ab7", overlay1: "#8087a2", overlay0: "#6e738d",
            surface2: "#5b6078", surface1: "#494d64", surface0: "#363a4f",
            base: "#24273a", mantle: "#1e2030", crust: "#181926"
        },
        mocha: {
            rosewater: "#f5e0dc", flamingo: "#f2cdcd", pink: "#f5c2e7", mauve: "#cba6f7",
            red: "#f38ba8", maroon: "#eba0ac", peach: "#fab387", yellow: "#f9e2af",
            green: "#a6e3a1", teal: "#94e2d5", sky: "#89dceb", sapphire: "#74c7ec",
            blue: "#89b4fa", lavender: "#b4befe",
            text: "#cdd6f4", subtext1: "#bac2de", subtext0: "#a6adc8",
            overlay2: "#9399b2", overlay1: "#7f849c", overlay0: "#6c7086",
            surface2: "#585b70", surface1: "#45475a", surface0: "#313244",
            base: "#1e1e2e", mantle: "#181825", crust: "#11111b"
        },
        latte: {
            rosewater: "#dc8a78", flamingo: "#dd7878", pink: "#ea76cb", mauve: "#8839ef",
            red: "#d20f39", maroon: "#e64553", peach: "#fe640b", yellow: "#df8e1d",
            green: "#40a02b", teal: "#179299", sky: "#04a5e5", sapphire: "#209fb5",
            blue: "#1e66f5", lavender: "#7287fd",
            text: "#4c4f69", subtext1: "#5c5f77", subtext0: "#6c6f85",
            overlay2: "#7c7f93", overlay1: "#8c8fa1", overlay0: "#9ca0b0",
            surface2: "#acb0be", surface1: "#bcc0cc", surface0: "#ccd0da",
            base: "#eff1f5", mantle: "#e6e9ef", crust: "#dce0e8"
        }
    })

    // Current raw palette (named colors: Theme.c.mauve, ...).
    readonly property var c: palettes[name] ?? palettes.macchiato

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

    // Behaviour tokens (stored, editable in theme.json).
    readonly property int cheatsheetPeekMs: store.get("cheatsheet_peek_ms") ?? 6000

    // color + alpha (0..1) -> rgba, for translucent panels/backdrops.
    function withAlpha(color, a) {
        return Qt.rgba(color.r, color.g, color.b, a);
    }

    // ipc: qs -c quantumfate ipc call theme set <palette> | get | cycle
    IpcHandler {
        target: "theme"
        function set(palette: string): void {
            if (root.palettes[palette]) store.set({ palette: palette });
        }
        function get(): string { return root.name; }
        // Advance to the next palette in insertion order (wraps).
        function cycle(): string {
            const names = Object.keys(root.palettes);
            const next = names[(names.indexOf(root.name) + 1) % names.length];
            store.set({ palette: next });
            return next;
        }
    }
}

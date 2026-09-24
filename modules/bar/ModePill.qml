// ModePill — the bar's view of hyprfocus.
//
// The question a mode indicator answers changed. "Which mode is on" barely
// earns a bar slot; once a schedule can change the mode on its own, the
// question becomes "which mode, who put me in it, and what is it taking
// away" — and the answer to the second part is the one you want at the moment
// the desk surprises you.
//
// Read-only over Hyprfocus. Clicking opens the mode surface; this mirrors,
// it never writes.
import Quickshell
import QtQuick
import "../../services"   // Theme, Hyprfocus, PanelBus

Text {
    id: root
    property string screenName: ""

    // Ticks once a second so `remaining` counts down without polling anything.
    readonly property var _clock: SystemClock { precision: SystemClock.Seconds }

    readonly property bool running: !Hyprfocus.resting
    readonly property string remaining: {
        root._clock.date;   // dependency: recompute every tick
        if (!root.running || !Hyprfocus.until) return "";
        const ms = Date.parse(Hyprfocus.until) - Date.now();
        if (ms <= 0) return "";
        const m = Math.ceil(ms / 60000);
        return m >= 60 ? Math.floor(m / 60) + "h " + (m % 60) + "m" : m + "m";
    }

    // A mode the declaration does not have is a real state — a store edited by
    // hand, or one replaced under a running shell. Saying so beats rendering a
    // blank pill that looks like nothing is on.
    readonly property string name: Hyprfocus.known ? Hyprfocus.label(Hyprfocus.mode)
        : Hyprfocus.mode + " (undeclared)"

    // The mode's declared glyph (LEO-425): every mode names an icon in the
    // hyprfocus declaration, shown next to its name in the same tint. A mode
    // without one degrades to the name alone, never a broken glyph.
    readonly property string icon: (Hyprfocus.data.modes?.[Hyprfocus.mode]?.icon) || ""

    // Automation gets its own colour. A desk that changed by itself should not
    // look identical to one you changed, or the pill answers the wrong half of
    // the question.
    readonly property color tint: !root.running ? Theme.c.subtext1
        : Hyprfocus.source === "manual" ? Theme.accent : Theme.c.peach

    color: hover.hovered ? Theme.text : root.tint
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    text: (root.icon ? root.icon + " " : "") + root.name + (root.remaining ? " · " + root.remaining : "")

    MouseArea {
        anchors.fill: parent
        onClicked: PanelBus.toggle("mood", root.screenName, root.mapToItem(null, root.width / 2, 0).x, "bar.clock")
    }

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: {
            const lines = [root.name];
            // Provenance first: it is what you came to the pill to find out
            // when the desk changed without you.
            lines.push("set " + (Hyprfocus.source === "manual" ? "by hand"
                : Hyprfocus.source === "schedule" ? "by the schedule" : "by a timer"));
            if (root.remaining) lines.push(root.remaining + " left");
            else if (root.running) lines.push("open-ended");
            // "and more" rather than a number: the shell reports what the
            // declaration says in as many words and does not resolve, so a
            // mode using an exclusive set withholds more than it can name.
            const gone = Hyprfocus.withholds(Hyprfocus.mode);
            const partial = Hyprfocus.narrows(Hyprfocus.mode);
            if (gone.length) lines.push("withholding " + gone.join(", ") + (partial ? " and more" : ""));
            else if (partial) lines.push("narrowed to what it declares");
            return lines.join(" · ") + " · click to configure";
        }
    }
}

// ScenePill — left isle: which scene this screen is standing in.
//
// A scene owns its workspace, its layout and its bindings, so "which scene"
// is the question behind why the keys and the tiling behave the way they do
// right now. The workspace row next to this says WHERE you are among the
// row; this says WHAT that place is.
//
// Per screen, not per desk: a mode places several scenes on several monitors
// at once, so the answer is only ever about the screen this bar is on.
//
// Read-only. Nothing here writes, and it has no click target — the scene is
// changed by going to its workspace, not by a menu on a label.
import Quickshell
import QtQuick
import "../../services"   // Theme, Hyprfocus, PanelBus

Text {
    id: root
    property string screenName: ""

    // The scene the DESK published for this screen, not the event-fed cache:
    // the cache goes stale whenever a workspace event is missed, and this
    // pill then names a scene the screen left (measured in the nested
    // instance: `loose` while the screen stood on `code-deck`).
    readonly property string scene: PanelBus.sceneOn(root.screenName)

    // The scene's own entry in the declaration, or nothing for a workspace no
    // scene claims (a bare numbered one, a special).
    readonly property var declared: (Hyprfocus.data.base?.scenes?.[root.scene]) ?? null

    // A workspace no scene claims is a real state worth showing plainly
    // rather than blanking the pill, which would read as "nothing on".
    readonly property bool claimed: root.declared !== null

    visible: root.scene !== ""
    color: hover.hovered ? Theme.text : (root.claimed ? Theme.accent : Theme.c.subtext1)
    font { family: Theme.fontFamily; pixelSize: Theme.barFontSize; weight: Theme.barFontWeight }
    leftPadding: Theme.space.md; rightPadding: Theme.space.md
    // The scene's own glyph in front of its name. It was left off once for
    // fear of reading as another workspace chip, but the row beside it draws
    // glyphs in their own pills -- a bare glyph sitting against a word reads
    // as that word's icon, which is what a scene's declared `icon` is for.
    // A scene with no icon (or a workspace no scene claims) still gets its
    // name, never a placeholder.
    readonly property string glyph: (root.declared && root.declared.icon) ? root.declared.icon : ""
    text: root.glyph !== "" ? (root.glyph + "  " + root.scene) : root.scene

    HoverHandler { id: hover }
    HoverTip {
        shown: hover.hovered; screenName: root.screenName
        text: {
            if (!root.claimed) return root.scene + " · no scene claims this workspace";
            const lines = [root.scene];
            // The layout is why the windows sit the way they do, and the
            // binding trees are why the keys do what they do — the two things
            // a scene actually decides.
            lines.push((root.declared.layout ?? "scene") + " layout");
            const trees = root.declared.bindings ?? [];
            if (trees.length) lines.push("binds: " + trees.join(", "));
            return lines.join(" · ");
        }
    }
}

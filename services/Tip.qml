pragma Singleton
// Tip — the shared hover-tooltip bus. Controls-ToolTip popups are clipped inside
// the 30px bar window, so tooltips are drawn by TipLayer (its own layer surface
// below the bar) instead. HoverTip reports the hovered control's text + screen-
// local x here; TipLayer for that screen renders it. Keyed by screen name so each
// monitor's bar shows its own tip.
import Quickshell
import QtQuick

Singleton {
    id: root

    // screenName -> { text:string, x:real }  (x = screen-local center of anchor).
    property var byScreen: ({})

    function show(screenName, text, x) {
        if (!screenName || !text) return;
        const m = Object.assign({}, root.byScreen);
        m[screenName] = { text, x };
        root.byScreen = m;
    }
    function hide(screenName) {
        if (!screenName || root.byScreen[screenName] === undefined) return;
        const m = Object.assign({}, root.byScreen);
        delete m[screenName];
        root.byScreen = m;
    }
}

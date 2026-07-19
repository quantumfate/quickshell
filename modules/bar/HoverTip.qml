// HoverTip — reports a control's tooltip to the Tip bus, which draws it below the
// bar via TipLayer (a Controls ToolTip would be clipped inside the bar window).
// Non-visual; place inside a control and drive `visible` from a HoverHandler:
//
//   HoverHandler { id: h }
//   HoverTip { text: "Capture this turn's hash"; visible: h.hovered; screenName: chip.screenName }
import QtQuick
import "../../services"   // Tip

Item {
    id: root

    property string text: ""
    property string screenName: ""
    // Show/hide is driven by the caller (a HoverHandler binding).
    property bool shown: false

    onShownChanged: root._sync()
    onTextChanged: if (root.shown) root._sync()

    function _sync() {
        if (root.shown && root.text && root.screenName)
            Tip.show(root.screenName, root.text, root._centerX());
        else
            Tip.hide(root.screenName);
    }

    // Screen-local x of the anchor control's center (the bar fills the screen,
    // so window coords == screen coords).
    function _centerX() {
        return parent ? parent.mapToItem(null, parent.width / 2, 0).x : 0;
    }

    Component.onDestruction: Tip.hide(root.screenName)
}

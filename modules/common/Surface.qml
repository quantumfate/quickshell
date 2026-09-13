// Surface — the one card material every translucent panel in the shell paints
// itself with: ground, hairline border, corner radius. It owns ONLY the
// material — layout, padding, and content stay the caller's job — so a later
// aesthetic pass is one edit here instead of a tour of every panel.
//
// `elevation` names a step in Theme.surfaceAlpha rather than taking a raw
// alpha: the compositor blurs a layer surface only above its own
// `ignore_alpha` threshold, set per WlrLayershell.namespace in the hypr repo
// (hypr/hypr/layerrules.lua). Picking an alpha here without checking that
// threshold gives either an unblurred card or a blurred backdrop.
import QtQuick
import "../../services"   // Theme

Rectangle {
    id: root

    // island   — bar clusters, floating and translucent
    // modal    — near-opaque focused cards over a dim backdrop
    // backdrop — the dim scrim behind a modal
    // peek     — lighter, non-interactive glance panels
    // solid    — fully opaque, no frosting needed
    property string elevation: "island"
    readonly property real alpha: Theme.surfaceAlpha[root.elevation] ?? Theme.surfaceAlpha.island
    property color tint: Theme.backgroundAlt

    radius: Theme.radiusIsland
    color: Theme.withAlpha(root.tint, root.alpha)
    border { width: 1; color: Theme.withAlpha(Theme.border, 0.45) }
}

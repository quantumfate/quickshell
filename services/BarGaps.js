.pragma library

// LEO-340: the bar's side insets follow each monitor's tiled outer gap.
//
// conf/host.lua (hypr repo) publishes the resolved per-monitor base
// left/right outer gap to the `geometry` store — base gap only, never the
// transient solo widen (hypr/events/solo_gaps.lua widens a lone tile, which
// is a per-workspace correction, not the monitor's resting geometry). A
// monitor absent from the store (an older store, or a fingerprint the store
// has not been rewritten for yet) falls back to the bar's own default inset.

/**
 * The bar's left/right inset for one screen: that monitor's published gap,
 * or `fallback` (Theme.barInset*2, in px) when the store has no entry.
 *
 * @param {object} storeData the `geometry` Store's decoded document
 * @param {string} screenName e.g. "DP-1", "eDP-1"
 * @param {number} fallback px, used whole for both sides
 * @returns {{left: number, right: number}}
 */
function insetFor(storeData, screenName, fallback) {
    const monitors = (storeData && storeData.monitors) || {};
    const gap = monitors[screenName];
    if (!gap || typeof gap.left !== "number" || typeof gap.right !== "number") {
        return { left: fallback, right: fallback };
    }
    return { left: gap.left, right: gap.right };
}

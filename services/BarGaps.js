.pragma library

// An isle that is not docked rests at a fixed position that depends on its
// MONITOR ONLY — never the scene, its gaps, or what was last published
// (LEO cross-repo "bars never dance"). `insetFor` is that rule: the
// monitor's published base gap (`geometry.monitors`, LEO-340), else the
// bar's own default (`Theme.barInset * 2`).
//
// This used to also carry a per-scene opt-in (`bar_follows_scene_gaps`) that
// rode hyprland's resolved distance to the workspace's outermost window, plus
// a memory (`insetPublished`/`pruneInsetMemory`, since removed) that existed
// only to mask that path's publish lag — a resting isle would otherwise snap
// to the bar's default the instant a workspace switch landed and slide back
// once the scene's gap republished. Retired: every shipped scene set the
// flag, so it was never actually an opt-in, and a bar that redraws itself on
// every scene gap change is the "dance" the resting rule exists to rule out.
// Docked isles still follow their scene — that is a placement, not a rest,
// and hypr's own dock cache (per monitor+scene) already covers its lag.
//
// Needs no reload or poll: the monitor gap arrives through the `geometry`
// store's watchChanges, same as before.

/**
 * One screen's resting left/right bar inset: the monitor's published base
 * gap, else the fallback, used whole for both sides.
 *
 * @param {object|null} geometryStore the `geometry` Store's decoded document
 * @param {string} screenName e.g. "DP-1", "eDP-1"
 * @param {number} fallback px, used whole for both sides
 * @returns {{left: number, right: number}}
 */
function insetFor(geometryStore, screenName, fallback) {
  var monitors = (geometryStore && geometryStore.monitors) || {};
  var monitorGap = monitors[screenName];
  var monitorLeft = monitorGap && typeof monitorGap.left === "number" ? monitorGap.left : null;
  var monitorRight = monitorGap && typeof monitorGap.right === "number" ? monitorGap.right : null;

  return {
    left: monitorLeft != null ? monitorLeft : fallback,
    right: monitorRight != null ? monitorRight : fallback,
  };
}

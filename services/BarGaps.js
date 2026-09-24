.pragma library

// The bar's side insets are either subscribed from hyprland or resting:
//
//   1. An opt-in scene (bar_follows_scene_gaps) rides the value hyprland
//      already decided: the FINAL distance from the monitor edge to the
//      scene's outermost visible window — the engine's gap ladder (scene
//      gaps_out → host workspace-spec → live global) PLUS the workspace rule's
//      gaps_out (which the compositor removes from the work area before the
//      layout runs) and, on any side the layout left inset, the rule's gaps_in
//      and the window border. hyprland folds it all in hypr/lib/geometry.lua's
//      `resolved_gaps` and publishes the left/right pair to the `geometry`
//      store's `workspaces` map — at config load by conf/host.lua, and
//      re-published by the scene engine (hypr/scene/spec.lua) the first time
//      it re-reads a scene edit. Quickshell never mirrors or re-derives a gap,
//      so the bar cannot drift from the visible window; hyprland spells the
//      sides itself.
//   2. Without the flag the bar rests on its screen's published base gap
//      (`geometry.monitors`, LEO-340), then the bar's own default
//      (Theme.barInset*2) — the previous algorithm, unchanged.
//
// Neither path needs a reload or a poll: a scene edit lands through the
// `hyprfocus` Store's watchChanges (the file re-read re-emits `data`), the
// resolved value through the `geometry` store's watchChanges when hyprland
// re-publishes, and the active scene on a screen is fed by the compositor's
// own `workspace`/`workspacev2` events, mirrored by Bar.qml from
// Workspaces.qml's `_activeWsName` handling (see its header for the socket2
// evidence on why raw events, not the monitor's cached activeWorkspace).

/**
 * The active scene's resolved four-side gap, whole — but only when the scene
 * opts in (`bar_follows_scene_gaps`). `null` otherwise, so a caller can keep
 * its own resting default rather than guessing. This is the same opt-in rule
 * `insetFor` applies to the bar's sides, spelled for surfaces (Toasts) that
 * also need the top/bottom the bar itself never reads.
 *
 * @param {object|null} geometryStore the `geometry` Store's decoded document
 * @param {object|null} hyprfocusStore the `hyprfocus` Store's decoded document
 * @param {string|null} activeSceneName the workspace name active on this screen
 * @returns {{top: number, right: number, bottom: number, left: number}|null}
 */
function sceneGapsFor(geometryStore, hyprfocusStore, activeSceneName) {
  var scenes = hyprfocusStore && hyprfocusStore.base && hyprfocusStore.base.scenes;
  var scene = activeSceneName && scenes && scenes[activeSceneName];
  if (!scene || scene.bar_follows_scene_gaps !== true) return null;
  var workspaces = (geometryStore && geometryStore.workspaces) || {};
  var gap = workspaces[activeSceneName];
  if (gap
    && typeof gap.top === "number" && typeof gap.right === "number"
    && typeof gap.bottom === "number" && typeof gap.left === "number") {
    return { top: gap.top, right: gap.right, bottom: gap.bottom, left: gap.left };
  }
  return null;
}

/**
 * One screen's left/right bar inset.
 *
 * Subscribed when the active scene opts in (`bar_follows_scene_gaps`): the
 * resolved value hyprland published for that workspace, whole. Resting
 * otherwise: the monitor's published base gap, else the bar's default.
 *
 * @param {object|null} geometryStore the `geometry` Store's decoded document
 * @param {object|null} hyprfocusStore the `hyprfocus` Store's decoded document
 * @param {string|null} activeSceneName the workspace name active on this screen
 * @param {string} screenName e.g. "DP-1", "eDP-1"
 * @param {number} fallback px, used whole for both sides
 * @returns {{left: number, right: number}}
 */
function insetFor(geometryStore, hyprfocusStore, activeSceneName, screenName, fallback) {
  // Subscribed path: the active scene opts in, so the inset is hyprland's
  // resolved distance to the visible window for that workspace — sides as
  // hyprland spelled them, with no folding, no fall-through, and no
  // scene-side choice of its own.
  var scenes = hyprfocusStore && hyprfocusStore.base && hyprfocusStore.base.scenes;
  var scene = activeSceneName && scenes && scenes[activeSceneName];
  if (scene && scene.bar_follows_scene_gaps === true) {
    var workspaces = (geometryStore && geometryStore.workspaces) || {};
    var gap = activeSceneName && workspaces[activeSceneName];
    if (gap && typeof gap.left === "number" && typeof gap.right === "number") {
      return { left: gap.left, right: gap.right };
    }
    // hyprland has not published this workspace yet (the edit just landed, or
    // the store is stale). The bar rests on its default rather than guessing.
    return { left: fallback, right: fallback };
  }

  // Resting bar: the monitor's published base gap, then the default.
  var monitors = (geometryStore && geometryStore.monitors) || {};
  var monitorGap = monitors[screenName];
  var monitorLeft = monitorGap && typeof monitorGap.left === "number" ? monitorGap.left : null;
  var monitorRight = monitorGap && typeof monitorGap.right === "number" ? monitorGap.right : null;

  return {
    left: monitorLeft != null ? monitorLeft : fallback,
    right: monitorRight != null ? monitorRight : fallback,
  };
}
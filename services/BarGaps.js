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
// A THIRD state exists and is the reason `insetPublished` and
// `pruneInsetMemory` are here: an opt-in scene whose resolved gap hyprland
// has not published yet. `insetFor` answers the bare fallback there, which on
// a workspace switch snapped every resting isle to the bar's default inset
// and slid it back once the publish landed. The caller remembers the last
// PUBLISHED inset per scene and uses it while that gap is missing; these two
// functions are what make the remembering honest — one says whether an
// answer is hyprland's or the fallback (so only real values are remembered),
// the other drops scenes that no longer exist or no longer opt in (so the
// memory cannot outlive its declaration). The memory is never authoritative:
// a publish always overwrites it.
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

/**
 * Whether `insetFor`'s answer for this scene is hyprland's published value
 * rather than the caller's fallback.
 *
 * Only the subscribed path can be unpublished: a resting bar's answer is the
 * monitor's gap or the default, and both are as good as they will ever be.
 * So this is false for a scene that does not opt in — there is nothing to
 * remember and nothing to wait for.
 *
 * @param {object|null} geometryStore the `geometry` Store's decoded document
 * @param {object|null} hyprfocusStore the `hyprfocus` Store's decoded document
 * @param {string|null} activeSceneName the workspace name active on this screen
 * @returns {boolean}
 */
function insetPublished(geometryStore, hyprfocusStore, activeSceneName) {
  var scenes = hyprfocusStore && hyprfocusStore.base && hyprfocusStore.base.scenes;
  var scene = activeSceneName && scenes && scenes[activeSceneName];
  if (!scene || scene.bar_follows_scene_gaps !== true) return false;
  var workspaces = (geometryStore && geometryStore.workspaces) || {};
  var gap = workspaces[activeSceneName];
  return !!gap && typeof gap.left === "number" && typeof gap.right === "number";
}

/**
 * The remembered insets worth keeping: entries whose scene is still declared
 * and still opts in.
 *
 * This is the invalidation that a publish cannot do. A publish overwrites one
 * scene's entry, which covers an edited gap; it says nothing about a scene
 * that was deleted from the declaration, or one that stopped subscribing —
 * both leave an entry that would be handed back the next time that name came
 * around. Called when the declaration changes, which is the only moment
 * either can happen.
 *
 * Returns a new object rather than mutating: QML only re-evaluates bindings
 * on assignment, and a mutated map would leave readers on the old value.
 *
 * @param {object|null} memory scene name -> {left, right}
 * @param {object|null} hyprfocusStore the `hyprfocus` Store's decoded document
 * @returns {object} the kept entries
 */
function pruneInsetMemory(memory, hyprfocusStore) {
  var scenes = (hyprfocusStore && hyprfocusStore.base && hyprfocusStore.base.scenes) || {};
  var kept = {};
  for (var name in memory || {}) {
    var scene = scenes[name];
    if (scene && scene.bar_follows_scene_gaps === true) kept[name] = memory[name];
  }
  return kept;
}

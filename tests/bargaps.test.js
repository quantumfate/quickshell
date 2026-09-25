// The bar's side insets are either subscribed from hyprland or resting. For
// an opt-in scene (bar_follows_scene_gaps) the inset is the value hyprland
// resolved for that workspace and published to `geometry.workspaces` — the
// bar never derives, folds, or falls through on its own. Without the flag it
// rests on the monitor's published gap, then the default. Every lookup must
// fall back cleanly on a missing store, a missing entry, or a malformed one.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadLibrary } from "./qml.js";

const { insetFor, sceneGapsFor, insetPublished, pruneInsetMemory } = loadLibrary("services/BarGaps.js");

const monitors = {
  "DP-1": { left: 40, right: 40 },
  "DP-2": { left: 14, right: 14 },
};
const workspaces = {
  code: { left: 25, right: 25 },
  media: { left: 25, right: 60 },
};
const geometry = { monitors, workspaces };
const scenes = (s) => ({ base: { scenes: s } });

test("a monitor with a published gap uses it while the bar rests", () => {
  assert.deepEqual(insetFor(geometry, {}, "code", "DP-1", 24), {
    left: 40,
    right: 40,
  });
  assert.deepEqual(insetFor(geometry, {}, "media", "DP-2", 24), {
    left: 14,
    right: 14,
  });
});

test("a monitor absent from the store falls back to the bar's default inset", () => {
  assert.deepEqual(insetFor(geometry, {}, "code", "eDP-1", 24), {
    left: 24,
    right: 24,
  });
});

test("an empty or null store falls back for every screen", () => {
  assert.deepEqual(insetFor({}, {}, "code", "DP-1", 16), {
    left: 16,
    right: 16,
  });
  assert.deepEqual(insetFor(null, {}, "code", "DP-1", 16), {
    left: 16,
    right: 16,
  });
});

test("a malformed entry (missing a side) falls back per side", () => {
  const lopsided = { monitors: { "DP-1": { left: 40 } } };
  assert.deepEqual(insetFor(lopsided, {}, "code", "DP-1", 24), {
    left: 40,
    right: 24,
  });
});

test("an opt-in scene rides hyprland's published resolved gap, sides as published", () => {
  const s = scenes({ media: { bar_follows_scene_gaps: true } });
  // 25/60 is what hyprland resolved (a sided scene gap), not what the bar
  // chose: it is read whole from geometry.workspaces.
  assert.deepEqual(insetFor(geometry, s, "media", "DP-2", 24), {
    left: 25,
    right: 60,
  });
});

test("an opt-in scene ignores its own gaps_out: hyprland spelled the sides", () => {
  // The scene's declared gap and printed sides are data HYPRLAND folds; the
  // bar takes the published value even when the scene table disagrees.
  const s = scenes({
    media: { bar_follows_scene_gaps: true, gaps_out: 91 },
  });
  assert.deepEqual(insetFor(geometry, s, "media", "DP-2", 24), {
    left: 25,
    right: 60,
  });
});

test("an opt-in scene without a published entry rests on the default, never guesses", () => {
  const s = scenes({ stream: { bar_follows_scene_gaps: true } });
  // No geometry.workspaces["stream"] yet (publish has not landed): the bar
  // must not reach for the monitor or blend anything — it rests.
  assert.deepEqual(insetFor(geometry, s, "stream", "DP-2", 24), {
    left: 24,
    right: 24,
  });
});

test("a malformed published entry (missing a side) is a whole fallback, not a partial", () => {
  // hyprland publishes complete {left,right} pairs; a partial entry is a
  // malformed/stale state, and the bar does not invent the other side.
  const partial = {
    monitors,
    workspaces: { media: { left: 25 } },
  };
  const s = scenes({ media: { bar_follows_scene_gaps: true } });
  assert.deepEqual(insetFor(partial, s, "media", "DP-2", 24), {
    left: 24,
    right: 24,
  });
});

test("a scene with gaps_out but no bar_follows_scene_gaps never leaves the resting chain", () => {
  const s = scenes({ media: { gaps_out: 91 } });
  assert.deepEqual(insetFor(geometry, s, "media", "DP-2", 24), {
    left: 14,
    right: 14,
  });
});

test("a missing or malformed hyprfocus store never crashes, and no scene matches a null active name", () => {
  const s = scenes({ media: { bar_follows_scene_gaps: true } });
  assert.deepEqual(insetFor(geometry, null, "media", "DP-2", 24), {
    left: 14,
    right: 14,
  });
  assert.deepEqual(insetFor(geometry, { base: null }, "media", "DP-2", 24), {
    left: 14,
    right: 14,
  });
  assert.deepEqual(insetFor(geometry, s, null, "DP-2", 24), {
    left: 14,
    right: 14,
  });
  assert.deepEqual(insetFor(geometry, s, "", "DP-2", 24), {
    left: 14,
    right: 14,
  });
});

test("laptop-solo: both monitors take the same published gap", () => {
  const store = {
    monitors: {
      "eDP-1": { left: 8, right: 8 },
      "HDMI-A-1": { left: 8, right: 8 },
    },
  };
  assert.deepEqual(insetFor(store, {}, "code", "eDP-1", 24), {
    left: 8,
    right: 8,
  });
  assert.deepEqual(insetFor(store, {}, "code", "HDMI-A-1", 24), {
    left: 8,
    right: 8,
  });
});

test("an explicit published zero is a real gap, not a fallback signal", () => {
  const store = {
    monitors,
    workspaces: { code: { left: 0, right: 0 } },
  };
  const s = scenes({ code: { bar_follows_scene_gaps: true } });
  assert.deepEqual(insetFor(store, s, "code", "DP-1", 24), {
    left: 0,
    right: 0,
  });
});

// sceneGapsFor: the four-side resolved gap for surfaces that need the
// top/bottom the bar never reads (Toasts) — same opt-in rule, null otherwise.
test("sceneGapsFor: an opt-in scene gets its resolved four-side gap, whole", () => {
  const store = {
    workspaces: { media: { top: 12, right: 60, bottom: 40, left: 25 } },
  };
  const s = scenes({ media: { bar_follows_scene_gaps: true } });
  assert.deepEqual(sceneGapsFor(store, s, "media"), {
    top: 12,
    right: 60,
    bottom: 40,
    left: 25,
  });
});

test("sceneGapsFor: a scene that does not opt in reads as null, never a guess", () => {
  const store = {
    workspaces: { media: { top: 12, right: 60, bottom: 40, left: 25 } },
  };
  assert.equal(sceneGapsFor(store, scenes({ media: { gaps_out: 91 } }), "media"), null);
  assert.equal(sceneGapsFor(store, {}, "media"), null);
  assert.equal(sceneGapsFor(store, null, "media"), null);
  assert.equal(sceneGapsFor(store, scenes({ media: { bar_follows_scene_gaps: true } }), null), null);
});

test("sceneGapsFor: a missing or partial published entry is null, not a partial frame", () => {
  const s = scenes({ media: { bar_follows_scene_gaps: true } });
  assert.equal(sceneGapsFor({ workspaces: {} }, s, "media"), null);
  assert.equal(sceneGapsFor({ workspaces: { media: { top: 12, left: 25 } } }, s, "media"), null);
  assert.equal(sceneGapsFor(null, s, "media"), null);
});

// --- the caller's memory of the last published inset --------------------
//
// An opt-in scene whose gap hyprland has not published yet takes the bare
// fallback, and on a workspace switch that snapped every resting isle to the
// bar's default inset and slid it back a frame later. The caller keeps the
// last published value per scene; these two functions are what keep that
// memory honest.

test("insetPublished() says whether the answer is hyprland's or the fallback", () => {
  const opted = scenes({ media: { bar_follows_scene_gaps: true } });
  assert.equal(insetPublished(geometry, opted, "media"), true);
  // Opts in, but nothing published for it yet: insetFor answers the fallback,
  // so there is something to remember instead.
  assert.equal(insetPublished({ workspaces: {} }, opted, "media"), false);
  assert.equal(insetPublished(null, opted, "media"), false);
});

test("insetPublished() is false for a scene that does not subscribe", () => {
  // A resting bar's answer is the monitor's gap or the default — as good as
  // it will ever be, with nothing to wait for and nothing to remember.
  assert.equal(insetPublished(geometry, scenes({ code: {} }), "code"), false);
  assert.equal(insetPublished(geometry, {}, "code"), false);
  assert.equal(insetPublished(geometry, scenes({ code: {} }), null), false);
});

test("pruneInsetMemory() drops what a publish cannot invalidate", () => {
  const memory = {
    media: { left: 25, right: 60 },
    retired: { left: 10, right: 10 },
    resting: { left: 8, right: 8 },
  };
  const declaration = scenes({
    media: { bar_follows_scene_gaps: true },
    // Still declared, but no longer subscribing: its remembered inset must
    // not be handed back the next time that name comes around.
    resting: {},
  });

  assert.deepEqual(pruneInsetMemory(memory, declaration), {
    media: { left: 25, right: 60 },
  });
  assert.deepEqual(pruneInsetMemory(memory, {}), {}, "no declaration keeps nothing");
  assert.deepEqual(pruneInsetMemory(null, declaration), {});
});

test("pruneInsetMemory() returns a new object, never the one it was given", () => {
  // QML re-evaluates bindings on assignment; a mutated map would leave every
  // reader on the value it already had.
  const memory = { media: { left: 25, right: 60 } };
  const declaration = scenes({ media: { bar_follows_scene_gaps: true } });
  const kept = pruneInsetMemory(memory, declaration);
  assert.notEqual(kept, memory);
  assert.deepEqual(kept, memory);
});

.pragma library

// Default placement requests for quickshell's own surfaces (docs/scenes.md
// "Areas", services/PanelBus.md "Surfaces"), used whenever the active
// scene's declaration does not override a surface (`base.scenes[name]
// .surfaces[id]`). Kept as plain data, one function, so it is testable from
// node and shared between PanelBus.surfaceRequest and the schema/docs table.
//
// `notifications` and `toasts` grow from the last column's top-right corner
// — the same corner the bar's bell sits under — so history and the live
// stack read as one place. `systemcenter` keeps its right-edge dock. Every
// centered dialog asks for `work` with the SAME width ratio it used to size
// itself against the whole screen (LEO's original `win.width * ratio`
// formulas) — now sized against the scene's usable area instead, so a wide
// scene gap or a docked column no longer lets the dialog drift under a bar.
// A surface that was a fixed pixel width regardless of screen size (no
// ratio in its own formula) gets `FIXED_WIDTH`: just above the schema's
// `exclusiveMinimum`, small enough that `scale * area.width` never beats its
// own content width on any real monitor, so it keeps that width until the
// area itself is too small to fit it.
var FIXED_WIDTH = 0.01;

var DEFAULTS = {
  notifications: { of: "column:last", scale: 0.33, align: "right", valign: "top" },
  toasts: { of: "column:last", scale: 0.33, align: "right", valign: "top" },
  control: { of: "work", scale: 0.72, align: "center", valign: "center" },
  systemcenter: { of: "work", scale: 0.34, align: "right", valign: "top" },
  cheatsheet: { of: "work", scale: 0.62, align: "center", valign: "center" },
  workspaceswitcher: { of: "work", scale: 0.42, align: "center", valign: "center" },
  windowrename: { of: "work", scale: 0.4, align: "center", valign: "center" },
  obsidiancreate: { of: "work", scale: 0.52, align: "center", valign: "center" },
  classassigner: { of: "work", scale: FIXED_WIDTH, align: "center", valign: "top" },
  teamselector: { of: "work", scale: FIXED_WIDTH, align: "right", valign: "top" },
  sysmon: { of: "work", scale: FIXED_WIDTH, align: "center", valign: "top" },
};

var FALLBACK = { of: "work", scale: 1, align: "center", valign: "center" };

/**
 * The default request for a surface id, falling back to a centered,
 * work-area-capped box for anything not listed above. `whichkey` has no
 * entry on purpose: it is a full-screen overlay by design (docs/scenes.md
 * "Areas", services/PanelBus.md "Surfaces") and never asks for a placed box.
 *
 * @param {string} surfaceId
 * @returns {{of: string, scale?: number, align?: string, valign?: string}}
 */
function defaultFor(surfaceId) {
  return DEFAULTS[surfaceId] || FALLBACK;
}

/** Every surface id with an explicit (non-fallback) default, for tests/docs. */
function ids() {
  return Object.keys(DEFAULTS);
}

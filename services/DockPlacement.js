.pragma library

// LEO-420: pure placement math for a docked bar isle. hypr publishes, per
// screen and isle id, a document under the `geometry` store's `docks` key:
//
//   geometry.docks["DP-1"]["bar.workspaces"] = {
//     region: { x, y, w, h },   // monitor-local gutter the isle may occupy
//     anchor: { x, y },         // the point the isle's growth corner aligns to
//     grow:   "up"|"down"|"left"|"right",  // away from the window
//     orientation: "horizontal"|"vertical",
//     state:  "docked"|"fallback"|"resting",
//   }
//
// This module never touches the store or Quickshell types — it is plain JS so
// `node --test` can exercise every anchor/grow/clamp case without a running
// shell. Bar.qml is the only caller; it feeds real isle sizes and screen
// bounds and applies the returned rect.

/**
 * The growth-corner rect for an isle of the given size against a dock
 * document's anchor + grow, with NO clamping applied yet.
 *
 * The anchor point is the corner of the isle that touches the window: for a
 * vertical growth ("up"/"down") anchor.x is the isle's left edge and
 * anchor.y is the touching edge; for a horizontal growth ("left"/"right")
 * anchor.y is the isle's top edge and anchor.x is the touching edge.
 *
 * @param {{x:number,y:number}} anchor
 * @param {"up"|"down"|"left"|"right"} grow
 * @param {number} width
 * @param {number} height
 * @returns {{x:number,y:number}}
 */
function rawRect(anchor, grow, width, height) {
  switch (grow) {
    case "up":
      return { x: anchor.x, y: anchor.y - height };
    case "down":
      return { x: anchor.x, y: anchor.y };
    case "left":
      return { x: anchor.x - width, y: anchor.y };
    case "right":
      return { x: anchor.x, y: anchor.y };
    default:
      return { x: anchor.x, y: anchor.y };
  }
}

/**
 * Place an isle per its published dock document.
 *
 * Clamp rule (LEO-420 §4): an isle larger than its region forfeits the
 * surplus — it is centred in the gutter (`region`), then clamped inside the
 * screen bounds. `clamped` is true whenever either step moved the isle off
 * the raw anchor placement, so the caller can warn once per state change
 * rather than per frame.
 *
 * @param {object} dock the per-screen, per-isle dock document (region/anchor/grow)
 * @param {{width:number,height:number}} isleSize the isle's own natural size
 * @param {{width:number,height:number}} screenSize the monitor's size
 * @returns {{x:number,y:number,clamped:boolean}}
 */
function placeDock(dock, isleSize, screenSize) {
  const region = dock.region;
  const overflows = isleSize.width > region.w || isleSize.height > region.h;

  let x, y;
  if (overflows) {
    // Forfeit the surplus: centre in the gutter rather than honour the anchor.
    x = region.x + (region.w - isleSize.width) / 2;
    y = region.y + (region.h - isleSize.height) / 2;
  } else {
    const rect = rawRect(dock.anchor, dock.grow, isleSize.width, isleSize.height);
    x = rect.x;
    y = rect.y;
  }

  const maxX = Math.max(0, screenSize.width - isleSize.width);
  const maxY = Math.max(0, screenSize.height - isleSize.height);
  const clampedX = Math.min(Math.max(x, 0), maxX);
  const clampedY = Math.min(Math.max(y, 0), maxY);

  return {
    x: clampedX,
    y: clampedY,
    clamped: overflows || clampedX !== x || clampedY !== y,
  };
}

/**
 * Whether a clamp warning should fire now: exactly on the false->true edge,
 * never while already clamped and never on recovery. Caller keeps the
 * previous `clamped` value per isle id and calls this before updating it.
 *
 * @param {boolean} wasClamped
 * @param {boolean} isClamped
 * @returns {boolean}
 */
function shouldWarnClamp(wasClamped, isClamped) {
  return !wasClamped && isClamped;
}

/**
 * Resolve which dock document (if any) applies, and what visual state the
 * isle should render.
 *
 * - No published dock for this screen/isle -> "resting": today's static
 *   layout, unaffected by anything below. This is the defensive default
 *   while the hypr side has not published yet.
 * - `dock === false` -> "hidden": the isle draws nothing.
 * - dock.state "docked" -> placed per placeDock.
 * - dock.state "fallback" -> keep the isle at its last docked rect (frozen),
 *   or resting if it was never docked.
 * - dock.state "resting" -> today's static layout, same as no document.
 *
 * @param {object|null|undefined} docksForScreen geometry.docks[screenName]
 * @param {string} isleId
 * @returns {"resting"|"hidden"|"docked"|"fallback"} the mode Bar.qml should render
 */
function resolveDockMode(docksForScreen, isleId) {
  const dock = docksForScreen ? docksForScreen[isleId] : undefined;
  if (dock === undefined) return "resting";
  if (dock === false) return "hidden";
  if (dock.state === "docked") return "docked";
  if (dock.state === "fallback") return "fallback";
  return "resting";
}

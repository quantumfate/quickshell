// LEO-378: the mood picker must not offer neutral (or any other hidden mode)
// as a choice. Source-level lint, same pattern as panelrouting.test.js -
// MoodPanel.qml is a UI component, not a pure function, so the contract this
// pins is "the picker's id list comes from the declaration's `hidden` flag",
// checked against HyprfocusRead.ids() (covered directly by
// hyprfocusread.test.js) rather than re-implemented inline.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const panel = readFileSync(join(root, "modules/bar/MoodPanel.qml"), "utf8");

test("the mood chip list is derived from Hyprfocus.ids(), not the raw policy-store keys", () => {
    assert.match(panel, /moodIds:\s*Hyprfocus\.ids\(\)/);
});

test("no chip-list logic hardcodes the neutral id by name", () => {
    // Grab just the moodIds declaration line so a `neutral` string used
    // elsewhere in the file (the header, the "stop" button, labels) does not
    // trip this check.
    const line = panel.split("\n").find((l) => l.includes("readonly property var moodIds"));
    assert.ok(line, "MoodPanel.qml must declare moodIds");
    assert.doesNotMatch(line, /neutral/);
});

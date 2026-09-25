.pragma library
// Pure logic behind ProjectWindows.qml: turning a `hyprctl clients -j`
// snapshot into one entry per OPEN PROJECT. Kept separate from the QML so the
// grouping is covered by tests/projectwindows.test.js without a compositor.
//
// A project is a set of kitty windows classed `Proj-<name>` (hyprrepo
// bin/,proj.sh). `Proj-picker` and `Proj-confirm` wear the same prefix so the
// scene floats them as strays, but they are prompts and never a project.

const CLASS_PREFIX = "Proj-";
const NOT_A_PROJECT = ["picker", "confirm"];

// Hyprland reports an address with the 0x, but its event payloads do not.
function normalize(address) {
    if (!address) return "";
    const s = "" + address;
    return s.startsWith("0x") ? s : "0x" + s;
}

// The project a class names, or "" for any other window.
function projectName(cls) {
    if (!cls || cls.indexOf(CLASS_PREFIX) !== 0) return "";
    const name = cls.slice(CLASS_PREFIX.length);
    if (!name || NOT_A_PROJECT.indexOf(name) !== -1) return "";
    return name;
}

// The scene a `scene:<name>` tag names, or "".
function sceneTag(tag) {
    const m = /^scene:([^*]+)/.exec(tag || "");
    return m ? m[1] : "";
}

// The role a `slot:<role>` tag names, or "" — Hyprland renders a tag it set
// itself with a trailing `*`.
function slotRole(tag) {
    const m = /^slot:([^*]+)/.exec(tag || "");
    return m ? m[1] : "";
}

// `,proj.sh`'s fixed template order. A role outside it (a declared scope, an
// untagged window still being stamped) sorts after the template rather than
// displacing a tab.
const TEMPLATE_ROLES = ["nvim", "clin", "yazi", "zsh", "run"];

function tabRank(slot) {
    const i = TEMPLATE_ROLES.indexOf(slot || "");
    return i === -1 ? TEMPLATE_ROLES.length : i;
}

// Whether a project belongs to `scene` -- it has a window standing there, or
// parked on a hold while that scene shows something else. A bar shows the
// scene its own screen is standing in, never "whatever is focused": with two
// project scenes open at once, reading focus meant the knowledge screen's
// strip described the project you were typing into on the code screen.
function onScene(project, scene) {
    if (!scene) return false;
    for (const ws of (project.workspaces || [])) {
        if (ws === scene) return true;
        if (ws.indexOf("special:") === 0 && project.scene === scene) return true;
    }
    return false;
}

// The projects standing on one scene, and the one focused among them.
function forScene(projects, scene) {
    return (projects || []).filter(p => onScene(p, scene));
}

// One entry per open project, sorted by name, from a clients snapshot.
// `active` is the focused window's address, and decides both which project is
// marked and which window a click on it focuses — returning to a project
// should land where you left it.
function group(clients, active) {
    const focused = normalize(active);
    const byName = {};
    for (const c of clients || []) {
        const name = projectName(c.class);
        if (!name) continue;
        const entry = byName[name] || (byName[name] = {
            name: name, windowClass: c.class, addresses: [], slots: [],
            tabs: [], selector: "", focused: false, workspaces: [], scene: "",
        });
        // Every workspace this project has windows on. A deck parks what it
        // does not show on a hold workspace, so a project that IS on `code`
        // reads as being on `special:deck-hold` too -- which is why this is a
        // list and not one name.
        const ws = (c.workspace && c.workspace.name) || "";
        if (ws && entry.workspaces.indexOf(ws) === -1) entry.workspaces.push(ws);
        const address = normalize(c.address);
        entry.addresses.push(address);
        let role = "";
        for (const tag of (c.tags || [])) {
            // `scene:<name>`, stamped by the compositor's own compile pass, is
            // where this window BELONGS -- the answer a parked window's
            // workspace (a hold) cannot give.
            const home = sceneTag(tag);
            if (home && !entry.scene) entry.scene = home;
            const r = slotRole(tag);
            if (!r) continue;
            role = r;
            if (entry.slots.indexOf(r) === -1) entry.slots.push(r);
        }
        // One tab per window, carrying what it takes to draw a tab strip and
        // click it: the role it plays, the window to focus, and whether it is
        // the one the keyboard is in. A window whose `slot:` tag has not
        // landed yet (kitty maps before `,proj.sh` stamps it) is still a tab
        // -- it is on screen -- and says so rather than being left out.
        entry.tabs.push({ slot: role, address: address, focused: !!address && address === focused });
        if (address && address === focused) entry.focused = true;
    }

    return Object.keys(byName).sort().map(name => {
        const p = byName[name];
        p.selector = "address:" + (p.focused ? focused : p.addresses[0]);
        // Tabs read in the project's declared order (`,proj.sh`'s template:
        // nvim, yazi, zsh, run, then anything else), which is the order the
        // compositor's group is sorted into as well -- so the strip matches
        // what mod+j/k walks. An unknown or missing role sorts last.
        p.tabs.sort((a, b) => tabRank(a.slot) - tabRank(b.slot));
        return p;
    });
}

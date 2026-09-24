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

// The role a `slot:<role>` tag names, or "" — Hyprland renders a tag it set
// itself with a trailing `*`.
function slotRole(tag) {
    const m = /^slot:([^*]+)/.exec(tag || "");
    return m ? m[1] : "";
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
            selector: "", focused: false,
        });
        const address = normalize(c.address);
        entry.addresses.push(address);
        for (const tag of (c.tags || [])) {
            const role = slotRole(tag);
            if (role && entry.slots.indexOf(role) === -1) entry.slots.push(role);
        }
        if (address && address === focused) entry.focused = true;
    }

    return Object.keys(byName).sort().map(name => {
        const p = byName[name];
        p.selector = "address:" + (p.focused ? focused : p.addresses[0]);
        return p;
    });
}

// Loading QML sources into node for testing.
//
// Neither file here is reachable by `import`: CheatParse.js is a QML
// `.pragma library` and Theme.qml is QML. Rather than duplicate their contents
// into a fixture — which is how a test starts passing while the thing it tests
// is broken — both are read from the real source and evaluated or parsed here.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Evaluates a QML `.pragma library` JS file and returns the names it declares.
 *
 * Runs in THIS realm, not a fresh vm context: a separate context returns arrays
 * and objects with their own prototypes, and `deepStrictEqual` then rejects two
 * structurally identical values. Wrapping in a function keeps the globals out
 * of scope without paying that price.
 */
export function loadLibrary(relPath, names) {
    const src = readFileSync(join(root, relPath), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const declared = names ?? [...src.matchAll(/^function\s+(\w+)/gm)].map(m => m[1]);
    const factory = vm.runInThisContext(
        `(function () {\n${src}\nreturn { ${declared.join(", ")} };\n})`,
        { filename: relPath }
    );
    return factory();
}

/**
 * Extracts the `palettes` table and the semantic colour roles from Theme.qml.
 * Parsed from the source rather than mirrored, so a palette edit is covered the
 * moment it lands.
 */
export function loadTheme() {
    const src = readFileSync(join(root, "services/Theme.qml"), "utf8");

    const start = src.indexOf("readonly property var palettes:");
    if (start === -1) throw new Error("Theme.qml: no `palettes` property found");
    const open = src.indexOf("({", start);
    let depth = 0, end = -1;
    for (let i = open + 1; i < src.length; i++) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}") { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end === -1) throw new Error("Theme.qml: unterminated `palettes` object");

    const palettes = vm.runInThisContext("(" + src.slice(open + 1, end + 1) + ")");

    // `readonly property color accent: c.mauve` -> { accent: "mauve" }
    const roles = {};
    for (const m of src.matchAll(/readonly\s+property\s+color\s+(\w+):\s*c\.(\w+)/g)) {
        roles[m[1]] = m[2];
    }

    const fallback = src.match(/palettes\[name\]\s*\?\?\s*palettes\.(\w+)/)?.[1];
    return { palettes, roles, fallback };
}

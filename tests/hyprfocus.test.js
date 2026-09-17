// hyprfocus.json's contract. The declaration is the single source for the
// compositor, the shell and the CLI, so a malformed one is not a cosmetic
// problem — it is a desk that materialises wrongly, or not at all.
//
// This is LINT over the declaration, deliberately not an evaluation of it:
// reference integrity, grammar conformance and reachability. Computing the
// resolved desk is the resolver's job and lives in the hypr repo; duplicating
// it here would give two implementations that could disagree about what a mode
// means, which is the failure this whole design exists to remove.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => JSON.parse(readFileSync(join(root, p), "utf8"));

const schema = read("schemas/hyprfocus.schema.json");
const declaration = read("assets/hyprfocus.default.json");

/** Resource kinds carrying the only/add/remove delta grammar. */
const KINDS = ["bindings", "services", "projects"];
/** A `requires`/`wants` reference is singular and qualified: `service:obsidian`. */
const REF_KIND = {
    scene: "scenes",
    binding: "bindings",
    service: "services",
    project: "projects",
};
/** Monitor roles a scene placement may name (the host files' roles). */
const ROLES = new Set(schema.$defs.scene_placement.properties.monitor.enum);

/** Every problem with the declaration, as readable lines. */
function lint(doc) {
    const base = doc.base;
    const known = Object.fromEntries(KINDS.map(k => [k, new Set(base[k] ?? [])]));
    known.scenes = new Set(Object.keys(base.scenes ?? {}));
    const errors = [];
    const say = (where, msg) => errors.push(`${where}: ${msg}`);

    for (const [mode, spec] of Object.entries(doc.modes)) {
        for (const kind of KINDS) {
            const delta = spec[kind];
            if (!delta) continue;
            if (delta.only && (delta.add || delta.remove)) {
                say(`${mode}.${kind}`, "`only` cannot be combined with `add` or `remove`");
            }
            for (const field of ["only", "add", "remove"]) {
                for (const name of delta[field] ?? []) {
                    if (!known[kind].has(name))
                        say(`${mode}.${kind}.${field}`, `unknown ${kind} '${name}'`);
                }
            }
        }

        // The scene set: known scenes on known roles, each once, no shared claim.
        const listed = new Set();
        const claims = new Map();
        for (const { name, monitor } of spec.scenes ?? []) {
            if (!known.scenes.has(name)) say(`${mode}.scenes`, `unknown scene '${name}'`);
            if (!ROLES.has(monitor)) say(`${mode}.scenes`, `unknown monitor '${monitor}'`);
            if (listed.has(name)) say(`${mode}.scenes`, `duplicate scene '${name}'`);
            listed.add(name);
            for (const block of base.scenes?.[name]?.blocks ?? []) {
                for (const cls of block.classes) {
                    const owner = claims.get(cls);
                    if (owner && owner !== name)
                        say(`${mode}.scenes`, `class '${cls}' claimed by ${owner} and ${name}`);
                    else claims.set(cls, name);
                }
            }
        }
    }

    for (const strength of ["requires", "wants"]) {
        for (const [from, refs] of Object.entries(base[strength] ?? {})) {
            for (const ref of [from, ...refs]) {
                const [kind, name] = ref.split(":");
                if (!REF_KIND[kind]) {
                    say(`base.${strength}`, `'${ref}' is not a qualified reference`);
                } else if (!known[REF_KIND[kind]].has(name)) {
                    say(`base.${strength}`, `'${ref}' names an undeclared ${REF_KIND[kind]}`);
                }
            }
        }
    }

    return errors;
}

test("the shipped declaration is internally consistent", () => {
    assert.deepEqual(lint(declaration), []);
});

test("neutral exists and is hidden, because it is the recovery fallback", () => {
    assert.ok(declaration.modes.neutral, "no neutral mode");
    assert.equal(schema.properties.modes.required[0], "neutral");
    assert.equal(declaration.modes.neutral.hidden, true);
    for (const [mode, spec] of Object.entries(declaration.modes)) {
        if (mode !== "neutral") assert.ok(!spec.hidden, `${mode} is hidden`);
    }
});

test("every mode carries a human-readable name and a scene set", () => {
    for (const [mode, spec] of Object.entries(declaration.modes)) {
        assert.equal(typeof spec.name, "string", `${mode} has no name`);
        assert.ok(spec.name.length > 0, `${mode} has an empty name`);
        assert.ok(Array.isArray(spec.scenes), `${mode} has no scene set`);
        assert.equal(spec.workspaces, undefined, `${mode} still names workspaces`);
    }
});

test("the lint catches an unknown scene rather than letting it resolve to nothing", () => {
    // A typo must fail here, not silently produce a desk missing a workspace.
    const broken = structuredClone(declaration);
    broken.modes.gaming.scenes = [{ name: "gamming", monitor: "primary" }];
    assert.deepEqual(lint(broken), ["gaming.scenes: unknown scene 'gamming'"]);
});

test("the lint catches an unknown monitor role and a duplicate scene", () => {
    const broken = structuredClone(declaration);
    broken.modes.study.scenes = [
        { name: "code", monitor: "DP-1" },
        { name: "code", monitor: "primary" },
    ];
    assert.deepEqual(lint(broken), [
        "study.scenes: unknown monitor 'DP-1'",
        "study.scenes: duplicate scene 'code'",
    ]);
});

test("the lint catches two active scenes claiming one class", () => {
    const broken = structuredClone(declaration);
    broken.base.scenes.pokemon.blocks[1].classes = ["zen-gaming-media"];
    assert.deepEqual(lint(broken), [
        "gaming.scenes: class 'zen-gaming-media' claimed by dofus and pokemon",
    ]);
});

test("the lint catches `only` combined with `add`", () => {
    const broken = structuredClone(declaration);
    broken.modes.work.services = { only: ["theme-auto"], add: ["obsidian"] };
    assert.ok(lint(broken).some((e) => e.includes("cannot be combined")));
});

test("the lint catches an unqualified dependency reference", () => {
    const broken = structuredClone(declaration);
    broken.base.wants = { "service:obsidian": ["linear-sync"] };
    assert.ok(lint(broken).some((e) => e.includes("not a qualified reference")));
});

test("the lint catches a dependency on something the base never declares", () => {
    const broken = structuredClone(declaration);
    broken.base.wants = { "service:obsidian": ["service:ghost"] };
    assert.ok(
        lint(broken).some((e) => e.includes("names an undeclared services")),
    );
});

test("dependency strengths mean different things and the schema says so", () => {
    // `requires` reports a conflict when a mode removes it; `wants` yields.
    // Collapsing them would make shipping behaviour inexpressible: the media
    // mode keeps Obsidian open while stopping its indexer and sync.
    const desk = schema.$defs.desk.properties;
    assert.ok(desk.requires.description.includes("CANNOT FUNCTION"));
    assert.ok(desk.wants.description.includes("can run without"));
    assert.ok(
        declaration.base.wants["service:obsidian"].includes(
            "service:obsidian-index",
        ),
    );
    assert.equal(declaration.base.requires?.["service:obsidian"], undefined);
});

test("the dofus tree is scene-scoped, not a base.requires dependency", () => {
    // `dofus` used to sit in base.bindings with a `binding:dofus requires
    // scene:dofus` edge (LEO-376: that let it stay admitted in modes, like
    // gaming's non-dofus scenes, whose desk never lists the dofus scene). The
    // tree now lives directly in base.scenes.dofus.bindings, the same model
    // as shelf-ankama/shelf-lutris, so it is admitted only while that scene is
    // focused — no base.bindings entry, no requires edge to check.
    assert.ok(!(declaration.base.bindings ?? []).includes("dofus"));
    assert.ok(declaration.base.scenes.dofus.bindings.includes("dofus"));
    assert.equal(declaration.base.requires?.["binding:dofus"], undefined);
    for (const [mode, spec] of Object.entries(declaration.modes)) {
        const addsDofus = (spec.bindings?.add ?? []).includes("dofus");
        const onlyDofus = (spec.bindings?.only ?? []).includes("dofus");
        assert.ok(
            !addsDofus && !onlyDofus,
            `${mode} names dofus in its own bindings delta; it should follow the scene instead`,
        );
    }
});

test("every mode declares a distinct accent role (LEO-330's four)", () => {
    // This declaration is the single accent store (LEO-334 item 12, LEO-339):
    // the compositor's colors.lua and the shell's Focus.accentRole both read
    // `modes.*.presentation.accent_role` here, so a study/work collision here
    // is a study/work collision on the desk.
    const roles = Object.fromEntries(
        Object.entries(declaration.modes).map(([mode, spec]) => [mode, spec.presentation?.accent_role]),
    );
    assert.deepEqual(roles, { neutral: "peach", work: "blue", study: "red", gaming: "lavender" });
    assert.equal(new Set(Object.values(roles)).size, 4, "two modes share an accent role");
});

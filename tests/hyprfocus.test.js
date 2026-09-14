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
const KINDS = ["workspaces", "bindings", "services", "projects"];
/** A `requires`/`wants` reference is singular and qualified: `service:obsidian`. */
const REF_KIND = {
    workspace: "workspaces",
    binding: "bindings",
    service: "services",
    project: "projects",
};

/** Every problem with the declaration, as readable lines. */
function lint(doc) {
    const base = doc.base;
    const known = Object.fromEntries(KINDS.map(k => [k, new Set(base[k] ?? [])]));
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

    for (const workspace of Object.keys(base.scenes ?? {})) {
        if (!known.workspaces.has(workspace)) {
            say("base.scenes", `'${workspace}' is not a declared workspace`);
        }
    }

    return errors;
}

test("the shipped declaration is internally consistent", () => {
    assert.deepEqual(lint(declaration), []);
});

test("neutral exists, because it is the resting state", () => {
    assert.ok(declaration.modes.neutral, "no neutral mode");
    assert.equal(schema.properties.modes.required[0], "neutral");
});

test("every mode carries a human-readable name", () => {
    for (const [mode, spec] of Object.entries(declaration.modes)) {
        assert.equal(typeof spec.name, "string", `${mode} has no name`);
        assert.ok(spec.name.length > 0, `${mode} has an empty name`);
    }
});

test("the lint catches an unknown name rather than letting it resolve to nothing", () => {
    // A typo must fail here, not silently produce a desk missing a workspace.
    const broken = structuredClone(declaration);
    broken.modes.gaming.workspaces = { only: ["gamming"] };
    assert.deepEqual(lint(broken), [
        "gaming.workspaces.only: unknown workspaces 'gamming'",
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

test("a scene is keyed by a workspace that exists", () => {
    // A scene arranges a workspace. One keyed by a workspace nothing declares
    // is geometry with nowhere to apply.
    const broken = structuredClone(declaration);
    broken.base.scenes.nowhere = { blocks: [] };
    assert.ok(
        lint(broken).some((e) => e.includes("is not a declared workspace")),
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
    assert.equal(declaration.base.requires["service:obsidian"], undefined);
});

test("a mode that withholds a workspace also withholds the binds that need it", () => {
    // `binding:dofus` requires `workspace:gaming`, so a mode without gaming
    // must not be left offering keys that act on a workspace that is gone.
    assert.deepEqual(declaration.base.requires["binding:dofus"], [
        "workspace:gaming",
    ]);
    for (const [mode, spec] of Object.entries(declaration.modes)) {
        const only = spec.workspaces?.only;
        const removed = new Set(spec.workspaces?.remove ?? []);
        const hasGaming = only ? only.includes("gaming") : !removed.has("gaming");
        const dropsDofus = (spec.bindings?.remove ?? []).includes("dofus");
        const keepsDofus = spec.bindings?.only
            ? spec.bindings.only.includes("dofus")
            : !dropsDofus;
        if (!hasGaming) {
            assert.ok(
                !keepsDofus,
                `${mode} withholds gaming but keeps the dofus binds`,
            );
        }
    }
});

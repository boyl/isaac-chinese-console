const fs = require("fs");
const vm = require("vm");

function assert(condition, message) { if (!condition) throw new Error(message); }
const context = { window: { IsaacHost: { available: false } }, JSON, Date };
context.window.window = context.window;
vm.createContext(context);
vm.runInContext(fs.readFileSync("desktop/state.js", "utf8"), context, { filename: "desktop/state.js" });
const state = context.window.IsaacState;

const migrated = state.normalizeForTest({
  schemaVersion: 2,
  favorites: { "182": true, "t:1": true, "bad": true },
  queueDraft: [
    { stepId: "c", command: "giveitem c182", repeat: 99 },
    { stepId: "t", command: "giveitem t1", repeat: 99 },
    { stepId: "k", command: "giveitem k1", repeat: 2 },
    { stepId: "p", command: "giveitem p0", repeat: 3 },
    { stepId: "spawn", command: "spawn 5.10.3", repeat: 4 },
    { stepId: "other", command: "debug 3", repeat: 5 }
  ]
});
assert(migrated.schemaVersion === 3, "state schema did not migrate to v3");
assert(migrated.favorites["c:182"] && migrated.favorites["t:1"] && !migrated.favorites.bad, "typed favorite migration failed");
assert(JSON.stringify(migrated.queueDraft.map(step => step.repeat)) === JSON.stringify([99,1,1,1,4,1]), "queue repeat normalization changed");

const oldCatalog = state.normalizeCatalogForTest({ schemaVersion: 1, sourcePath: "old", items: [
  { id: 182, description: "旧缓存说明" }, { id: 1, desc: "另一个说明" }
] });
assert(oldCatalog.schemaVersion === 2 && oldCatalog.descriptionCount === 2, "catalog v1 migration failed");
assert(oldCatalog.descriptions["c:182"] === "旧缓存说明", "catalog v1 description key migration failed");
assert(state.normalizeCatalogForTest({ broken: true }) === null, "corrupt catalog must be rejected");
console.log("state migration tests passed");

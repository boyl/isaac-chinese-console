const fs = require("fs");
const vm = require("vm");

function assert(condition, message) { if (!condition) throw new Error(message); }

const context = { window: {} };
vm.createContext(context);
for (const file of ["desktop/catalog.js", "desktop/objects.js", "desktop/search.js"]) {
  vm.runInContext(fs.readFileSync(file, "utf8"), context, { filename: file });
}

const catalog = context.window.IsaacCatalog;
const rows = context.window.IsaacObjectRows;
const search = context.window.IsaacSearch;
const expectedCategories = ["featured","all_items","trinkets","cards","pills","damage","defense","economy","explore","active","familiar","fun","debug","supply","stage"];
assert(JSON.stringify(catalog.categories.map(value => value.id)) === JSON.stringify(expectedCategories), "15 category ids/order changed");
assert(catalog.curatedItems.length === 74, "expected 74 curated items");
assert(new Set(catalog.curatedItems.map(value => value.id)).size === 74, "curated ids must be unique");
assert(catalog.commands.filter(value => value.cat === "debug").length === 8, "expected 8 debug commands");
assert(catalog.commands.filter(value => value.cat === "supply").length === 8, "expected 8 supply commands");
assert(catalog.commands.filter(value => value.cat === "stage" && value.stageMode !== "greed").length === 45, "expected 45 normal stages");
assert(catalog.commands.filter(value => value.cat === "stage" && value.stageMode === "greed").length === 7, "expected 7 greed stages");

assert(rows.length === 1056, "expected 1056 built-in objects");
const counts = { c: 0, t: 0, k: 0, p: 0 };
const keys = new Set();
for (const row of rows) {
  counts[row[0]]++;
  const key = `${row[0]}:${row[1]}`;
  assert(!keys.has(key), `duplicate object key ${key}`);
  keys.add(key);
  assert(row[2] && row[3] && row[4] && row[5], `incomplete built-in search row ${key}`);
}
assert(JSON.stringify(counts) === JSON.stringify({ c: 721, t: 188, k: 97, p: 50 }), "object type counts changed");
for (const missing of ["c:43","c:61","c:235","c:587","c:613","c:620","c:630","c:648","c:662","c:666","c:718","t:47"]) {
  assert(!keys.has(missing), `reserved object id included: ${missing}`);
}

search.configure(catalog.curatedItems, catalog.commands, {
  schemaVersion: 2,
  descriptionCount: 2,
  descriptions: { "t:1": "EID 饰品说明", "k:1": "EID 卡牌说明" }
});
assert(search.getItems().length === 1056, "built-in catalog object count changed after configure");
assert(search.getObject("t:1").description === "EID 饰品说明", "EID description enhancement failed");
assert(search.getItem(182).name === "圣心", "curated overlay must win for c:182");
assert(search.search("圣心")[0].objectKey === "c:182", "Chinese exact search failed");
assert(search.search("Sacred Heart")[0].objectKey === "c:182", "English exact search failed");
assert(search.search("shengxin")[0].objectKey === "c:182", "pinyin search failed");
assert(search.search("sx").some(value => value.objectKey === "c:182"), "initials search failed");
assert(search.search("c:182")[0].objectKey === "c:182", "typed collectible id search failed");
assert(search.search("t:1")[0].objectKey === "t:1", "typed trinket id search failed");
assert(search.search("k:1")[0].objectKey === "k:1", "typed card id search failed");
assert(search.search("p:0")[0].objectKey === "p:0", "typed pill id search failed");
assert(search.search("giveitem t1")[0].objectKey === "t:1", "full object command search failed");
const numericCollision = search.search("1").filter(value => value.kind === "item" && value.id === 1).map(value => value.objectType);
assert(JSON.stringify(numericCollision.slice(0, 4)) === JSON.stringify(["c","t","k","p"]), "bare numeric collision order changed");
assert(search.search("stage 1")[0].cmd === "stage 1", "exact command sorting failed");
assert(search.search("definitely-no-result").length === 0, "empty result search failed");

console.log("search/catalog tests passed");

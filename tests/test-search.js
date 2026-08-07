const fs = require("fs");
const vm = require("vm");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const context = { window: {} };
vm.createContext(context);
for (const file of ["desktop/catalog.js", "desktop/curated-aliases.js", "desktop/search.js"]) {
  vm.runInContext(fs.readFileSync(file, "utf8"), context, { filename: file });
}

const catalog = context.window.IsaacCatalog;
const search = context.window.IsaacSearch;
const expectedCategories = ["featured","damage","defense","economy","explore","active","familiar","fun","debug","supply","stage"];
assert(JSON.stringify(catalog.categories.map(value => value.id)) === JSON.stringify(expectedCategories), "category ids/order changed");
assert(!catalog.categories.some(value => value.id === "all_items"), "all_items category must not exist");
assert(catalog.curatedItems.length === 74, "expected 74 curated items");
assert(new Set(catalog.curatedItems.map(value => value.id)).size === 74, "curated ids must be unique");
assert(catalog.commands.filter(value => value.cat === "debug").length === 8, "expected 8 debug commands");
assert(catalog.commands.filter(value => value.cat === "supply").length === 8, "expected 8 supply commands");
assert(catalog.commands.filter(value => value.cat === "stage" && value.stageMode !== "greed").length === 45, "expected 45 normal stages");
assert(catalog.commands.filter(value => value.cat === "stage" && value.stageMode === "greed").length === 7, "expected 7 greed stages");

const imported = { items: [] };
for (let id = 1; id <= 732; id++) imported.items.push({ id, name: `目录道具${id}`, en: `Catalog Item ${id}`, pinyin: `mulu${id}`, initials: `ml${id}`, command: `giveitem c${id}` });
imported.items[181] = { id: 182, name: "EID 圣心", en: "EID Sacred Heart", pinyin: "shengxin", initials: "sx", command: "giveitem c182" };
search.configure(catalog.curatedItems, catalog.commands, imported);
assert(search.getItems().length === 732, "imported catalog must merge to 732 unique ids");
assert(search.getItem(182).name === "圣心", "curated overlay must win for id 182");
assert(search.search("圣心")[0].id === 182, "Chinese exact search failed");
assert(search.search("Sacred Heart")[0].id === 182, "English exact search failed");
assert(search.search("shengxin")[0].id === 182, "pinyin search failed");
assert(search.search("182")[0].id === 182, "numeric id search failed");
assert(search.search("giveitem c182")[0].id === 182, "command search failed");
assert(search.search("ml700").some(value => value.id === 700), "imported initials search failed");
assert(search.search("definitely-no-result").length === 0, "empty result search failed");

console.log("search/catalog tests passed");

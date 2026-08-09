const fs = require("fs");
const vm = require("vm");

function assert(condition, message) { if (!condition) throw new Error(message); }
function element(id) {
  return { id, value: "", innerText: "", innerHTML: "", className: "", disabled: false,
    style: {}, scrollTop: 0, tagName: "DIV", focus() { this.focused = true; } };
}

const ids = [
  "statusDot","statusText","catalogStatus","nav","queueCount","search","stageMode","stageNormal","stageGreed",
  "pageIndicator","pageTitle","eyebrow","pageDesc","sectionLabel","resultCount","resultSource","cards","content",
  "manualCommand","manualRisk","repeatCount","sendMode","detailBody","detailDrawer","queueDrawer","queueSummary",
  "queueProgress","queueList","executeQueueBtn","cancelQueueBtn","modalTitle","modalBody","modalBackdrop","toast","sendBtn"
];
const elements = {};
for (const id of ids) elements[id] = element(id);
elements.search.tagName = elements.manualCommand.tagName = elements.repeatCount.tagName = "INPUT";
elements.sendMode.tagName = "SELECT";
elements.manualCommand.value = "giveitem c182";
elements.repeatCount.value = "1";
elements.sendMode.value = "auto";

const document = {
  documentElement: { clientWidth: 1280 },
  getElementById(id) { if (!elements[id]) elements[id] = element(id); return elements[id]; },
  onkeydown: null
};
const window = {
  document, location: { pathname: "/C:/test/IsaacConsole.hta" }, screen: { availWidth: 1920, availHeight: 1080 },
  resizeTo() {}, moveTo() {}, setTimeout, clearTimeout, setInterval() { return 1; }, clearInterval() {},
  confirm() { return true; }, prompt() { return "测试方案"; }, event: null
};
window.window = window;
window.IsaacHost = { available: false, fso: null, shell: null, shellApplication: null, error: "ActiveX blocked by policy" };

const context = { window, document, location: window.location, screen: window.screen, setTimeout, clearTimeout,
  setInterval: window.setInterval, clearInterval: window.clearInterval, confirm: window.confirm, prompt: window.prompt, console };
vm.createContext(context);
for (const file of ["desktop/catalog.js","desktop/objects.js","desktop/state.js","desktop/search.js","desktop/queue.js","desktop/app.js"]) {
  vm.runInContext(fs.readFileSync(file, "utf8"), context, { filename: file });
}

window.onload();
assert(window.IsaacState.isMemoryMode(), "blocked host bridge did not fall back to memory mode");
assert(elements.statusText.innerText.includes("脚本桥错误：ActiveX blocked by policy"), "blocked script bridge was not reported");
assert(elements.nav.innerHTML.includes("全部收藏品") && elements.nav.innerHTML.includes("胶囊效果"), "15-category navigation did not render");
assert(elements.cards.innerHTML.includes("圣心"), "featured cards did not render");
assert(elements.resultCount.innerText === "12 项", "default featured count changed");
assert(elements.catalogStatus.innerText.includes("内置目录 1056 项"), "built-in catalog status missing");

window.IsaacApp.selectCategory("all_items");
assert(elements.resultCount.innerText === "721 项", "collectible category count is wrong");
assert(elements.pageIndicator.innerText === "1 / 41", "1280px collectible pagination is wrong");
window.IsaacApp.toggleFavorite(0);
assert(window.IsaacState.get().favorites["c:1"], "collectible favorite key is not typed");

window.IsaacApp.selectCategory("trinkets");
assert(elements.resultCount.innerText === "188 项", "trinket category count is wrong");
window.IsaacApp.toggleFavorite(0);
assert(window.IsaacState.get().favorites["t:1"] && window.IsaacState.get().favorites["c:1"], "typed ID collision corrupted favorites");
elements.repeatCount.value = "9";
window.IsaacApp.addEntry(0);
assert(elements.queueList.innerHTML.includes('value="1"'), "trinket repeat was not normalized");
window.IsaacApp.openDetail(0);
assert(elements.detailBody.innerHTML.includes("remove t1"), "trinket removal semantics missing");

window.IsaacApp.selectCategory("cards");
window.IsaacApp.openDetail(0);
assert(!elements.detailBody.innerHTML.includes("remove k"), "cards must not expose removal");
window.IsaacApp.selectCategory("pills");
assert(elements.resultCount.innerText === "50 项", "pill category count is wrong");

window.IsaacApp.selectCategory("stage");
assert(elements.resultCount.innerText === "45 项", "normal stage count is wrong");
assert(elements.stageMode.className.includes("show"), "stage sub-filter is hidden");
assert(elements.pageIndicator.innerText === "1 / 3", "1280px stage page budget should be 18 entries");
window.IsaacApp.setStageMode("greed");
assert(elements.resultCount.innerText === "7 项", "greed stage count is wrong");

elements.manualCommand.value = "custom command";
elements.repeatCount.value = "9";
window.IsaacApp.addManualToQueue();
assert(elements.queueList.innerHTML.includes("custom command"), "arbitrary single-line command was not queued");
assert(elements.queueList.innerHTML.includes('value="1"'), "unknown command repeat was not normalized");

window.IsaacApp.setStageMode("normal");
window.IsaacApp.selectCategory("stage");
document.documentElement.clientWidth = 1024; window.onresize();
assert(elements.pageIndicator.innerText === "1 / 4", "1024px page budget should be 12 entries");
document.documentElement.clientWidth = 900; window.onresize();
assert(elements.pageIndicator.innerText === "1 / 4", "900px minimum layout page budget failed");
document.documentElement.clientWidth = 1920; window.onresize();
assert(elements.pageIndicator.innerText === "1 / 3", "wide layout page budget failed");
console.log("app DOM smoke tests passed");

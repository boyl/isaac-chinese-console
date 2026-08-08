const fs = require("fs");
const vm = require("vm");

function assert(condition, message) { if (!condition) throw new Error(message); }

const state = { queueDraft: [] };
const window = {
  IsaacHost: { available: true, fso: {}, shell: {}, shellApplication: {} },
  IsaacState: {
    get() { return state; },
    save() { return true; },
    normalizeSteps(steps) { return steps || []; }
  },
  setTimeout, clearTimeout,
  clipboardData: { setData() { return true; } }
};
window.window = window;
const context = { window, setTimeout, clearTimeout };
vm.createContext(context);
vm.runInContext(fs.readFileSync("desktop/queue.js", "utf8"), context, { filename: "desktop/queue.js" });
window.IsaacQueue.init("C:\\test", {});
assert(window.IsaacQueue.bridgeAvailable(), "external queue module did not accept the inline HTA host bridge");
assert(window.IsaacQueue.getBridgeError() === "", "available host bridge reported an error");
console.log("HTA host bridge tests passed");

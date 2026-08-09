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

const hta = fs.readFileSync("IsaacConsole.hta", "utf8");
const inline = hta.match(/<script type="text\/javascript">([\s\S]*?)<\/script>/i);
assert(inline, "startup error handler script missing");
let createCount = 0, renderCount = 0, logText = "", pageText = "";
const startupFso = {
  FolderExists() { return true; },
  CreateFolder() {},
  BuildPath(folder, name) { return folder + "\\\\" + name; },
  CreateTextFile() {
    createCount++;
    return {
      WriteLine(value) { logText += String(value) + "\r\n"; },
      Write(value) { logText += String(value); },
      Close() {}
    };
  }
};
const startupShell = { ExpandEnvironmentStrings() { return "C:\\LocalAppData"; } };
const startupDocument = { body: {} };
Object.defineProperty(startupDocument.body, "innerHTML", {
  set(value) { renderCount++; pageText = String(value); }
});
const startupWindow = { document: startupDocument };
startupWindow.window = startupWindow;
const startupContext = {
  window: startupWindow,
  document: startupDocument,
  ActiveXObject: function (name) {
    if (name === "Scripting.FileSystemObject") return startupFso;
    if (name === "WScript.Shell") return startupShell;
    if (name === "Shell.Application") return {};
    throw new Error(name);
  }
};
vm.createContext(startupContext);
vm.runInContext(inline[1], startupContext, { filename: "IsaacConsole.hta:inline" });
startupWindow.onerror("first failure", "first.js", 12);
startupWindow.onerror("second failure", "second.js", 34);
assert(createCount === 1, "later startup error overwrote first log");
assert(renderCount === 1, "later startup error overwrote first page");
assert(logText.includes("first failure") && !logText.includes("second failure"), "startup log did not retain first error");
assert(pageText.includes("first failure") && !pageText.includes("second failure"), "startup page did not retain first error");
console.log("HTA host bridge tests passed");

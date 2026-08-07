(function (root) {
  "use strict";

  var MAX_FAVORITES = 2048;
  var MAX_HISTORY = 100;
  var MAX_SAVED_QUEUES = 50;
  var MAX_QUEUE_STEPS = 200;
  var fso = null;
  var shell = null;
  var baseDir = "";
  var statePath = "";
  var backupPath = "";
  var catalogPath = "";
  var state = null;
  var memoryMode = false;

  function objects() {
    if (typeof ActiveXObject === "undefined") { memoryMode = true; return; }
    if (!fso) fso = new ActiveXObject("Scripting.FileSystemObject");
    if (!shell) shell = new ActiveXObject("WScript.Shell");
  }

  function defaults() {
    return {
      schemaVersion: 2,
      favorites: {},
      history: [],
      queueDraft: [],
      savedQueues: [],
      ui: { lastCategory: "featured", stageMode: "normal", consoleMode: "auto" },
      catalog: { sourcePath: "", sourceHash: "", importedAt: "", itemCount: 0, pinyinAvailable: false }
    };
  }

  function parse(text, fallback) {
    try { return JSON.parse(String(text)); } catch (ignore) { return fallback; }
  }

  function readText(path) {
    objects();
    if (!fso.FileExists(path)) return "";
    var file = fso.OpenTextFile(path, 1, false, -1);
    try { return file.ReadAll(); } finally { file.Close(); }
  }

  function writeText(path, text) {
    objects();
    var file = fso.CreateTextFile(path, true, true);
    try { file.Write(String(text)); } finally { file.Close(); }
  }

  function ensureFolder(path) {
    objects();
    if (!fso.FolderExists(path)) fso.CreateFolder(path);
  }

  function trimSteps(steps) {
    var result = [], source = steps && steps.length ? steps : [];
    for (var i = 0; i < source.length && result.length < MAX_QUEUE_STEPS; i++) {
      var step = source[i] || {}, command = String(step.command || "").replace(/^\s+|\s+$/g, "");
      if (!command || command.length > 500 || /[\r\n]/.test(command)) continue;
      var repeat = parseInt(step.repeat, 10);
      if (isNaN(repeat) || repeat < 1) repeat = 1;
      if (repeat > 99) repeat = 99;
      if (!/^\s*(giveitem|spawn)\s+/i.test(command)) repeat = 1;
      result.push({
        stepId: String(step.stepId || ("step-" + new Date().getTime() + "-" + i)),
        label: String(step.label || command).slice(0, 120),
        command: command,
        repeat: repeat,
        source: String(step.source || "manual").slice(0, 32)
      });
    }
    return result;
  }

  function normalize(raw) {
    var clean = defaults(), key, count = 0;
    raw = raw || {};
    if (raw.favorites) {
      for (key in raw.favorites) {
        if (raw.favorites.hasOwnProperty(key) && raw.favorites[key] && /^\d+$/.test(key) && count < MAX_FAVORITES) {
          clean.favorites[key] = true;
          count++;
        }
      }
    }
    if (raw.history && raw.history.length) clean.history = raw.history.slice(0, MAX_HISTORY);
    clean.queueDraft = trimSteps(raw.queueDraft);
    if (raw.savedQueues && raw.savedQueues.length) {
      for (var i = 0; i < raw.savedQueues.length && clean.savedQueues.length < MAX_SAVED_QUEUES; i++) {
        var saved = raw.savedQueues[i] || {}, steps = trimSteps(saved.steps);
        if (steps.length) clean.savedQueues.push({
          id: String(saved.id || ("queue-" + i)),
          name: String(saved.name || "未命名方案").slice(0, 60),
          updatedAt: String(saved.updatedAt || ""),
          steps: steps
        });
      }
    }
    if (raw.ui) {
      clean.ui.lastCategory = String(raw.ui.lastCategory || "featured");
      clean.ui.stageMode = raw.ui.stageMode === "greed" ? "greed" : "normal";
      clean.ui.consoleMode = raw.ui.consoleMode === "open" ? "open" : "auto";
    }
    if (raw.catalog) {
      clean.catalog.sourcePath = String(raw.catalog.sourcePath || "");
      clean.catalog.sourceHash = String(raw.catalog.sourceHash || "");
      clean.catalog.importedAt = String(raw.catalog.importedAt || "");
      clean.catalog.itemCount = Math.max(0, parseInt(raw.catalog.itemCount, 10) || 0);
      clean.catalog.pinyinAvailable = raw.catalog.pinyinAvailable === true;
    }
    return clean;
  }

  function migrateLegacy() {
    var migrated = defaults();
    try {
      var favorites = parse(localStorage.getItem("isaac_favorites") || "{}", {}), key;
      for (key in favorites) if (favorites.hasOwnProperty(key) && favorites[key]) migrated.favorites[key] = true;
      var legacyHistory = parse(localStorage.getItem("isaac_history") || "[]", []);
      for (var i = 0; i < legacyHistory.length && i < MAX_HISTORY; i++) {
        migrated.history.push({
          timestamp: "",
          label: "旧版记录",
          command: String(legacyHistory[i]).replace(/ ×\d+$/, ""),
          requested: parseInt(String(legacyHistory[i]).match(/ ×(\d+)$/) ? RegExp.$1 : "1", 10),
          submitted: parseInt(String(legacyHistory[i]).match(/ ×(\d+)$/) ? RegExp.$1 : "1", 10),
          state: "legacy",
          note: "由 v1.3.0 localStorage 迁移"
        });
      }
    } catch (ignore) {}
    return normalize(migrated);
  }

  function init() {
    objects();
    if (memoryMode) { state = defaults(); return state; }
    baseDir = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") + "\\IsaacChineseConsole";
    ensureFolder(baseDir);
    statePath = baseDir + "\\state-v2.json";
    backupPath = baseDir + "\\state-v2.json.bak";
    catalogPath = baseDir + "\\catalog-cache-v1.json";
    var loaded = parse(readText(statePath), null);
    if (!loaded) loaded = parse(readText(backupPath), null);
    state = loaded ? normalize(loaded) : migrateLegacy();
    save();
    return state;
  }

  function save() {
    if (!state) return false;
    if (memoryMode) return true;
    objects();
    var temp = statePath + ".tmp";
    try {
      writeText(temp, JSON.stringify(normalize(state)));
      if (fso.FileExists(statePath)) fso.CopyFile(statePath, backupPath, true);
      if (fso.FileExists(statePath)) fso.DeleteFile(statePath, true);
      fso.MoveFile(temp, statePath);
      return true;
    } catch (ignore) {
      try { if (fso.FileExists(temp)) fso.DeleteFile(temp, true); } catch (ignored) {}
      return false;
    }
  }

  function loadCatalog() {
    if (memoryMode) return null;
    var raw = parse(readText(catalogPath), null);
    if (!raw || raw.schemaVersion !== 1 || !raw.items || !raw.items.length) return null;
    return raw;
  }

  function addHistory(entries) {
    if (!entries || !entries.length) return;
    for (var i = entries.length - 1; i >= 0; i--) state.history.unshift(entries[i]);
    state.history = state.history.slice(0, MAX_HISTORY);
    save();
  }

  function saveNamedQueue(name, steps) {
    name = String(name || "").replace(/^\s+|\s+$/g, "").slice(0, 60);
    steps = trimSteps(steps);
    if (!name || !steps.length) return false;
    var match = -1, i;
    for (i = 0; i < state.savedQueues.length; i++) if (state.savedQueues[i].name === name) match = i;
    var entry = { id: "queue-" + new Date().getTime(), name: name, updatedAt: new Date().toISOString(), steps: steps };
    if (match >= 0) state.savedQueues.splice(match, 1);
    state.savedQueues.unshift(entry);
    state.savedQueues = state.savedQueues.slice(0, MAX_SAVED_QUEUES);
    save();
    return true;
  }

  root.IsaacState = {
    init: init,
    get: function () { return state; },
    save: save,
    normalizeSteps: trimSteps,
    addHistory: addHistory,
    saveNamedQueue: saveNamedQueue,
    loadCatalog: loadCatalog,
    getStatePath: function () { return statePath; },
    getCatalogPath: function () { return catalogPath; },
    getBaseDir: function () { return baseDir; },
    isMemoryMode: function () { return memoryMode; }
  };
}(window));

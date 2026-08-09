(function (root) {
  "use strict";

  var MAX_FAVORITES = 2048, MAX_HISTORY = 100, MAX_SAVED_QUEUES = 50, MAX_QUEUE_STEPS = 200;
  var fso = null, shell = null, baseDir = "", statePath = "", backupPath = "", catalogPath = "";
  var state = null, memoryMode = false, startupError = "";

  function objects() {
    var host = root.IsaacHost;
    if (host && host.available && host.fso && host.shell) {
      fso = host.fso; shell = host.shell; memoryMode = false; startupError = ""; return;
    }
    fso = null; shell = null; memoryMode = true;
    startupError = String(host && host.error || "HTA 宿主桥不可用");
  }
  function defaults() {
    return {
      schemaVersion: 3,
      favorites: {}, history: [], queueDraft: [], savedQueues: [],
      ui: { lastCategory: "featured", stageMode: "normal", consoleMode: "auto" },
      catalog: { sourcePath: "", sourceHash: "", importedAt: "", descriptionCount: 0 }
    };
  }
  function parse(text, fallback) { try { return JSON.parse(String(text)); } catch (ignore) { return fallback; } }
  function readText(path) {
    objects(); if (!fso || !fso.FileExists(path)) return "";
    var file = fso.OpenTextFile(path, 1, false, -1);
    try { return file.ReadAll(); } finally { file.Close(); }
  }
  function writeText(path, text) {
    objects(); var file = fso.CreateTextFile(path, true, true);
    try { file.Write(String(text)); } finally { file.Close(); }
  }
  function ensureFolder(path) { objects(); if (!fso.FolderExists(path)) fso.CreateFolder(path); }
  function favoriteKey(value) {
    value = String(value || "");
    if (/^\d+$/.test(value)) return "c:" + value;
    return /^[ctkp]:\d+$/.test(value) ? value : "";
  }
  function safeRepeat(command) {
    command = String(command || "").replace(/^\s+|\s+$/g, "");
    if (/^giveitem\s+[tkp]\d+\s*$/i.test(command)) return false;
    return /^(giveitem|spawn)\s+/i.test(command);
  }
  function trimSteps(steps) {
    var result = [], source = steps && steps.length ? steps : [];
    for (var i = 0; i < source.length && result.length < MAX_QUEUE_STEPS; i++) {
      var step = source[i] || {}, command = String(step.command || "").replace(/^\s+|\s+$/g, "");
      if (!command || command.length > 500 || /[\r\n]/.test(command)) continue;
      var repeat = parseInt(step.repeat, 10);
      if (isNaN(repeat) || repeat < 1) repeat = 1;
      if (repeat > 99) repeat = 99;
      if (!safeRepeat(command)) repeat = 1;
      result.push({
        stepId: String(step.stepId || ("step-" + new Date().getTime() + "-" + i)),
        label: String(step.label || command).slice(0, 120), command: command, repeat: repeat,
        source: String(step.source || "manual").slice(0, 32)
      });
    }
    return result;
  }
  function normalize(raw) {
    var clean = defaults(), key, normalized, count = 0, i;
    raw = raw || {};
    if (raw.favorites) for (key in raw.favorites) {
      normalized = favoriteKey(key);
      if (raw.favorites.hasOwnProperty(key) && raw.favorites[key] && normalized && count < MAX_FAVORITES) {
        clean.favorites[normalized] = true; count++;
      }
    }
    if (raw.history && raw.history.length) clean.history = raw.history.slice(0, MAX_HISTORY);
    clean.queueDraft = trimSteps(raw.queueDraft);
    if (raw.savedQueues && raw.savedQueues.length) for (i = 0; i < raw.savedQueues.length && clean.savedQueues.length < MAX_SAVED_QUEUES; i++) {
      var saved = raw.savedQueues[i] || {}, savedSteps = trimSteps(saved.steps);
      if (savedSteps.length) clean.savedQueues.push({
        id: String(saved.id || ("queue-" + i)), name: String(saved.name || "未命名方案").slice(0, 60),
        updatedAt: String(saved.updatedAt || ""), steps: savedSteps
      });
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
      clean.catalog.descriptionCount = Math.max(0, parseInt(raw.catalog.descriptionCount || raw.catalog.itemCount, 10) || 0);
    }
    return clean;
  }
  function migrateLegacyStorage() {
    var migrated = defaults();
    try {
      var favorites = parse(localStorage.getItem("isaac_favorites") || "{}", {}), key;
      for (key in favorites) if (favorites.hasOwnProperty(key) && favorites[key] && favoriteKey(key)) migrated.favorites[favoriteKey(key)] = true;
      var history = parse(localStorage.getItem("isaac_history") || "[]", []);
      for (var i = 0; i < history.length && i < MAX_HISTORY; i++) migrated.history.push({
        timestamp: "", label: "旧版记录", command: String(history[i]).replace(/ ×\d+$/, ""),
        requested: parseInt(String(history[i]).match(/ ×(\d+)$/) ? RegExp.$1 : "1", 10),
        submitted: parseInt(String(history[i]).match(/ ×(\d+)$/) ? RegExp.$1 : "1", 10),
        state: "legacy", note: "由 v1.3.0 localStorage 迁移"
      });
    } catch (ignore) {}
    return normalize(migrated);
  }
  function init() {
    objects(); if (memoryMode) { state = defaults(); return state; }
    try {
      baseDir = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") + "\\IsaacChineseConsole";
      ensureFolder(baseDir);
      statePath = baseDir + "\\state-v3.json"; backupPath = statePath + ".bak";
      catalogPath = baseDir + "\\catalog-v2.json";
      var loaded = parse(readText(statePath), null) || parse(readText(backupPath), null);
      if (!loaded) loaded = parse(readText(baseDir + "\\state-v2.json"), null);
      state = loaded ? normalize(loaded) : migrateLegacyStorage();
      save();
    } catch (error) {
      fso = null; shell = null; memoryMode = true;
      startupError = String(error && (error.description || error.message) || "LocalAppData unavailable");
      baseDir = ""; statePath = ""; backupPath = ""; catalogPath = ""; state = defaults();
    }
    return state;
  }
  function save() {
    if (!state || memoryMode) return true;
    objects(); var temp = statePath + ".tmp";
    try {
      writeText(temp, JSON.stringify(normalize(state)));
      if (fso.FileExists(statePath)) fso.CopyFile(statePath, backupPath, true);
      if (fso.FileExists(statePath)) fso.DeleteFile(statePath, true);
      fso.MoveFile(temp, statePath); return true;
    } catch (ignore) {
      try { if (fso.FileExists(temp)) fso.DeleteFile(temp, true); } catch (ignored) {}
      return false;
    }
  }
  function normalizeCatalog(raw) {
    if (!raw) return null;
    if (raw.schemaVersion === 2 && raw.descriptions) return raw;
    if (raw.schemaVersion !== 1 || !raw.items) return null;
    var descriptions = {}, count = 0;
    for (var i = 0; i < raw.items.length; i++) {
      var item = raw.items[i] || {}, description = String(item.description || item.desc || "");
      if (item.id && description) { descriptions["c:" + parseInt(item.id, 10)] = description; count++; }
    }
    return { schemaVersion: 2, sourcePath: raw.sourcePath || "", sourceHash: raw.sourceHash || "", importedAt: raw.importedAt || "", descriptionCount: count, descriptions: descriptions };
  }
  function loadCatalog() {
    if (memoryMode) return null;
    var raw = normalizeCatalog(parse(readText(catalogPath), null));
    if (!raw) raw = normalizeCatalog(parse(readText(catalogPath + ".bak"), null));
    if (!raw) raw = normalizeCatalog(parse(readText(baseDir + "\\catalog-cache-v1.json"), null));
    return raw;
  }
  function addHistory(values) {
    if (!values || !values.length) return;
    for (var i = values.length - 1; i >= 0; i--) state.history.unshift(values[i]);
    state.history = state.history.slice(0, MAX_HISTORY); save();
  }
  function saveNamedQueue(name, steps) {
    name = String(name || "").replace(/^\s+|\s+$/g, "").slice(0, 60); steps = trimSteps(steps);
    if (!name || !steps.length) return false;
    var match = -1, i;
    for (i = 0; i < state.savedQueues.length; i++) if (state.savedQueues[i].name === name) match = i;
    var entry = { id: "queue-" + new Date().getTime(), name: name, updatedAt: new Date().toISOString(), steps: steps };
    if (match >= 0) state.savedQueues.splice(match, 1);
    state.savedQueues.unshift(entry); state.savedQueues = state.savedQueues.slice(0, MAX_SAVED_QUEUES); save(); return true;
  }

  root.IsaacState = {
    init: init, get: function () { return state; }, save: save, normalizeSteps: trimSteps,
    addHistory: addHistory, saveNamedQueue: saveNamedQueue, loadCatalog: loadCatalog,
    getStatePath: function () { return statePath; }, getCatalogPath: function () { return catalogPath; },
    getBaseDir: function () { return baseDir; }, isMemoryMode: function () { return memoryMode; },
    getStartupError: function () { return startupError; }, normalizeForTest: normalize, normalizeCatalogForTest: normalizeCatalog
  };
}(window));

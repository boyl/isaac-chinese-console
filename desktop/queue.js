(function (root) {
  "use strict";

  var fso = null, shell = null, appDir = "", steps = [], active = null, pollTimer = null, bridgeAvailable = true, bridgeError = "";
  var onChanged = function () {}, onProgress = function () {}, onFinished = function () {};

  function objects() {
    var host = root.IsaacHost;
    if (host && host.available && host.fso && host.shell) {
      fso = host.fso; shell = host.shell; bridgeAvailable = true; bridgeError = ""; return;
    }
    fso = null; shell = null; bridgeAvailable = false;
    bridgeError = String(host && host.error || "HTA 宿主桥不可用");
  }
  function trim(value) { return String(value || "").replace(/^\s+|\s+$/g, ""); }
  function safeRepeat(command) { return /^\s*(giveitem|spawn)\s+/i.test(String(command || "")); }
  function normalize(command, repeat) {
    command = trim(command);
    if (!command || command.length > 500 || /[\r\n]/.test(command)) return null;
    repeat = parseInt(repeat, 10);
    if (isNaN(repeat) || repeat < 1) repeat = 1;
    if (repeat > 99) repeat = 99;
    if (!safeRepeat(command)) repeat = 1;
    return { command: command, repeat: repeat };
  }
  function id(prefix) { return prefix + "-" + new Date().getTime() + "-" + Math.floor(Math.random() * 100000); }
  function copyStep(step) {
    return { stepId: String(step.stepId), label: String(step.label), command: String(step.command), repeat: parseInt(step.repeat, 10) || 1, source: String(step.source || "manual") };
  }
  function persist() {
    var state = root.IsaacState.get();
    state.queueDraft = root.IsaacState.normalizeSteps(steps);
    root.IsaacState.save();
    onChanged(steps);
  }
  function add(command, label, repeat, source) {
    if (steps.length >= 200) return { ok: false, code: "QUEUE_LIMIT" };
    var clean = normalize(command, repeat);
    if (!clean) return { ok: false, code: "INVALID_COMMAND" };
    steps.push({ stepId: id("step"), label: trim(label) || clean.command, command: clean.command, repeat: clean.repeat, source: source || "manual" });
    persist();
    return { ok: true, repeatLimited: clean.repeat !== parseInt(repeat, 10) && parseInt(repeat, 10) > 1 };
  }
  function remove(index) { if (index >= 0 && index < steps.length) { steps.splice(index, 1); persist(); } }
  function move(from, to) {
    if (from < 0 || from >= steps.length || to < 0 || to >= steps.length || from === to) return;
    var value = steps.splice(from, 1)[0]; steps.splice(to, 0, value); persist();
  }
  function updateRepeat(index, repeat) {
    if (index < 0 || index >= steps.length) return false;
    var clean = normalize(steps[index].command, repeat);
    if (!clean) return false;
    steps[index].repeat = clean.repeat; persist(); return clean.repeat === parseInt(repeat, 10);
  }
  function replace(newSteps) { steps = root.IsaacState.normalizeSteps(newSteps); persist(); }
  function clear() { steps = []; persist(); }
  function risk(command) {
    var value = trim(command).toLowerCase();
    if (/^(giveitem|spawn)\s+/.test(value)) return { key: "repeatable", label: "可重复" };
    if (/^(remove|stage|goto|restart|kill|debug|lua|luamod|reloadshaders)(\s|$)/.test(value)) return { key: "danger", label: "状态变更" };
    return { key: "unknown", label: "自定义" };
  }
  function writeText(path, value) {
    objects(); var file = fso.CreateTextFile(path, true, true);
    try { file.Write(String(value)); } finally { file.Close(); }
  }
  function readJson(path) {
    objects(); if (!fso.FileExists(path)) return null;
    var file = fso.OpenTextFile(path, 1, false, -1), text;
    try { text = file.ReadAll(); } finally { file.Close(); }
    try { return JSON.parse(text); } catch (ignore) { return null; }
  }
  function quote(value) { return '"' + String(value).replace(/"/g, '""') + '"'; }
  function cleanup(run) {
    objects();
    var paths = [run.jobPath, run.cancelPath, run.statusPath];
    for (var i = 0; i < paths.length; i++) try { if (fso.FileExists(paths[i])) fso.DeleteFile(paths[i], true); } catch (ignore) {}
  }
  function terminal(value) { return value === "completed" || value === "partial" || value === "cancelled" || value === "failed"; }
  function historyFromStatus(status) {
    var values = [], results = status.stepResults || [];
    for (var i = 0; i < results.length; i++) {
      var result = results[i];
      values.push({
        timestamp: new Date().toISOString(),
        label: String(result.label || result.command || "命令"),
        command: String(result.command || ""),
        requested: parseInt(result.requested, 10) || 1,
        submitted: parseInt(result.submitted, 10) || 0,
        state: String(result.state || status.state),
        note: String(result.note || status.errorCode || "输入已提交；请在游戏内确认实际效果")
      });
    }
    return values;
  }
  function poll() {
    if (!active) return;
    var status = readJson(active.statusPath);
    if (status && status.jobId === active.jobId) {
      active.lastStatus = status;
      onProgress(status);
      if (terminal(status.state)) {
        var run = active; active = null;
        if (pollTimer) clearTimeout(pollTimer);
        root.IsaacState.addHistory(historyFromStatus(status));
        cleanup(run);
        onFinished(status);
        return;
      }
    }
    if (new Date().getTime() > active.deadline) {
      var timeoutRun = active; active = null;
      var fallback = timeoutRun.lastStatus || { schemaVersion: 1, jobId: timeoutRun.jobId, state: "failed", errorCode: "TIMEOUT", canResume: true, stepResults: [], remainingSteps: timeoutRun.job.steps };
      cleanup(timeoutRun); onFinished(fallback); return;
    }
    pollTimer = setTimeout(poll, 140);
  }
  function execute(sourceSteps, consoleMode, dryRun) {
    if (active) return { ok: false, code: "BUSY" };
    var clean = root.IsaacState.normalizeSteps(sourceSteps);
    if (!clean.length) return { ok: false, code: "EMPTY_QUEUE" };
    objects();
    if (!bridgeAvailable) return { ok: false, code: "NO_BRIDGE" };
    var temp = fso.GetSpecialFolder(2).Path, jobId = id("job"), totalRepeats = 0;
    for (var repeatIndex = 0; repeatIndex < clean.length; repeatIndex++) totalRepeats += clean[repeatIndex].repeat;
    var run = {
      jobId: jobId,
      jobPath: fso.BuildPath(temp, "isaac-cn-job-" + jobId + ".json"),
      statusPath: fso.BuildPath(temp, "isaac-cn-status-" + jobId + ".json"),
      cancelPath: fso.BuildPath(temp, "isaac-cn-cancel-" + jobId + ".flag"),
      deadline: new Date().getTime() + Math.min(300000, 20000 + clean.length * 1800 + totalRepeats * 700),
      job: { schemaVersion: 1, jobId: jobId, consoleMode: consoleMode === "open" ? "open" : "auto", steps: clean }
    };
    writeText(run.jobPath, JSON.stringify(run.job));
    var command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + quote(appDir + "\\send-command.ps1") +
      ' -JobFile ' + quote(run.jobPath) + ' -StatusFile ' + quote(run.statusPath) + ' -CancelFile ' + quote(run.cancelPath) + (dryRun ? ' -DryRun' : '');
    active = run;
    shell.Run(command, 0, false);
    pollTimer = setTimeout(poll, 120);
    return { ok: true, jobId: jobId };
  }
  function cancel() {
    if (!active) return false;
    try { writeText(active.cancelPath, "cancel"); return true; } catch (ignore) { return false; }
  }
  function probe(callback) {
    objects();
    if (!bridgeAvailable) { callback(false, { errorCode: "NO_BRIDGE" }); return; }
    var temp = fso.GetSpecialFolder(2).Path, probeId = id("probe"), path = fso.BuildPath(temp, "isaac-cn-" + probeId + ".json");
    var command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + quote(appDir + "\\send-command.ps1") + ' -ProbeOnly -StatusFile ' + quote(path);
    shell.Run(command, 0, false);
    var started = new Date().getTime();
    function wait() {
      var status = readJson(path);
      if (status) {
        try { fso.DeleteFile(path, true); } catch (ignore) {}
        callback(status.running === true, status); return;
      }
      if (new Date().getTime() - started > 4500) { callback(false, { errorCode: "TIMEOUT" }); return; }
      setTimeout(wait, 160);
    }
    setTimeout(wait, 160);
  }

  root.IsaacQueue = {
    init: function (rootDir, handlers) {
      appDir = rootDir; handlers = handlers || {};
      objects();
      onChanged = handlers.changed || onChanged; onProgress = handlers.progress || onProgress; onFinished = handlers.finished || onFinished;
      steps = root.IsaacState.normalizeSteps(root.IsaacState.get().queueDraft); onChanged(steps);
    },
    getSteps: function () { var result = []; for (var i = 0; i < steps.length; i++) result.push(copyStep(steps[i])); return result; },
    add: add, remove: remove, move: move, updateRepeat: updateRepeat, replace: replace, clear: clear,
    risk: risk, safeRepeat: safeRepeat, execute: execute, cancel: cancel, probe: probe,
    isBusy: function () { return !!active; },
    copyText: function (value) { try { window.clipboardData.setData("Text", String(value)); return true; } catch (ignore) { return false; } },
    bridgeAvailable: function () { return bridgeAvailable; },
    getBridgeError: function () { return bridgeError; }
  };
}(window));

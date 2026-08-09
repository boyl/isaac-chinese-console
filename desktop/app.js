(function (root) {
  "use strict";

  var catalog = root.IsaacCatalog;
  var state, importedCatalog, currentCategory = "featured", currentPage = 1, stageMode = "normal";
  var pageEntries = [], allVisible = [], selectedIndex = 0, detailEntry = null, searchTimer = null, toastTimer = null;
  var dragIndex = -1, importBusy = false;
  var defaultFeatured = [182,331,118,313,581,64,580,105,723,360,698,721];

  function el(id) { return document.getElementById(id); }
  function trim(value) { return String(value || "").replace(/^\s+|\s+$/g, ""); }
  function esc(value) { return String(value == null ? "" : value).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#39;"); }
  function appDir() {
    var path = decodeURIComponent(location.pathname).replace(/^\//, "").replace(/\//g, "\\");
    return path.substring(0, path.lastIndexOf("\\"));
  }
  function categoryById(id) {
    for (var i = 0; i < catalog.categories.length; i++) if (catalog.categories[i].id === id) return catalog.categories[i];
    return catalog.categories[0];
  }
  function validCategory(id) {
    for (var i = 0; i < catalog.categories.length; i++) if (catalog.categories[i].id === id) return true;
    return false;
  }
  function toast(message, type) {
    var node = el("toast"); node.className = "toast " + (type || ""); node.innerText = message; node.style.display = "block";
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { node.style.display = "none"; }, 3400);
  }
  function pageSize() { return document.documentElement.clientWidth >= 1180 ? 18 : 12; }
  function isFavorite(entry) { return !!(entry && entry.objectKey && state.favorites[entry.objectKey]); }

  function loadCatalog() {
    importedCatalog = root.IsaacState.loadCatalog();
    root.IsaacSearch.configure(catalog.curatedItems, catalog.commands, importedCatalog);
    var count = importedCatalog && importedCatalog.descriptionCount ? importedCatalog.descriptionCount : 0;
    el("catalogStatus").innerText = "内置目录 1056 项 · " + (count ? ("EID 说明 " + count + " 条") : "EID 说明未导入");
  }

  function categoryEntries(id) {
    var result = [], items = root.IsaacSearch.getItems(), commands = root.IsaacSearch.getCommands(), i;
    if (id === "featured") {
      var seen = {}, featured;
      for (i = 0; i < defaultFeatured.length; i++) {
        featured = root.IsaacSearch.getItem(defaultFeatured[i]);
        if (featured) { result.push(featured); seen[featured.objectKey] = true; }
      }
      for (i = 0; i < items.length; i++) if (isFavorite(items[i]) && !seen[items[i].objectKey]) result.push(items[i]);
      return result;
    }
    if (id === "all_items" || id === "trinkets" || id === "cards" || id === "pills") {
      for (i = 0; i < items.length; i++) if (items[i].catalogCategory === id) result.push(items[i]);
      return result;
    }
    for (i = 0; i < items.length; i++) if (items[i].curatedOrder != null && items[i].cat === id) result.push(items[i]);
    for (i = 0; i < commands.length; i++) {
      if (commands[i].cat !== id) continue;
      if (id === "stage" && ((commands[i].stageMode === "greed") !== (stageMode === "greed"))) continue;
      result.push(commands[i]);
    }
    return result;
  }

  function countCategory(id) { return categoryEntries(id).length; }
  function renderNav() {
    var html = "", group = "", categories = catalog.categories;
    for (var i = 0; i < categories.length; i++) {
      var c = categories[i];
      if (group !== c.group) { group = c.group; html += '<div class="nav-label">' + esc(group) + '</div>'; }
      html += '<button class="nav-btn ' + (c.id === currentCategory ? 'active' : '') + '" onclick="IsaacApp.selectCategory(\'' + c.id + '\')">' +
        '<span class="nav-icon">' + esc(c.icon) + '</span>' + esc(c.name) + '<span class="nav-count">' + countCategory(c.id) + '</span></button>';
    }
    el("nav").innerHTML = html;
  }

  function currentQuery() { return trim(el("search").value); }
  function refreshVisible() {
    var query = currentQuery(), c = categoryById(currentCategory);
    allVisible = query ? root.IsaacSearch.search(query) : categoryEntries(currentCategory);
    var pages = Math.max(1, Math.ceil(allVisible.length / pageSize()));
    if (currentPage > pages) currentPage = pages;
    if (currentPage < 1) currentPage = 1;
    var start = (currentPage - 1) * pageSize(); pageEntries = allVisible.slice(start, start + pageSize());
    el("pageIndicator").innerText = currentPage + " / " + pages;
    el("pageTitle").innerText = query ? "全局搜索" : c.name;
    el("eyebrow").innerText = query ? "GLOBAL SEARCH" : c.eyebrow;
    el("pageDesc").innerText = query ? ("中文、英文、拼音、命令和 ID：" + query) : c.desc;
    el("sectionLabel").innerText = query ? "匹配项目" : (currentCategory === "featured" ? "优先推荐" : "全部项目");
    el("resultCount").innerText = allVisible.length + " 项";
    el("resultSource").innerText = query ? "内置完整目录" : "";
    el("stageMode").className = "stage-mode" + (!query && currentCategory === "stage" ? " show" : "");
    el("stageNormal").className = stageMode === "normal" ? "active" : "";
    el("stageGreed").className = stageMode === "greed" ? "active" : "";
  }

  function sigilClass(entry) {
    if (entry.cat === "explore") return " blue";
    if (entry.cat === "defense" || entry.cat === "economy") return " green";
    return entry.tier === "S" ? "" : " gold";
  }
  function renderCard(entry, index) {
    var isItem = entry.kind === "item", command = entry.command || entry.cmd, description = entry.desc || entry.description || "本机目录条目；执行前请核对实际命令。";
    var favorite = isItem && entry.canFavorite ? '<button class="fav ' + (isFavorite(entry) ? 'on' : '') + '" title="收藏" onclick="event.cancelBubble=true;IsaacApp.toggleFavorite(' + index + ')">★</button>' : '';
    return '<div class="card-wrap"><div class="card ' + (entry.hot ? 'hot ' : '') + '" id="card-' + index + '" tabindex="0" onclick="IsaacApp.openDetail(' + index + ')" onfocus="IsaacApp.focusCard(' + index + ')">' +
      '<div class="card-head"><div class="sigil' + sigilClass(entry) + '">' + esc(isItem && entry.objectType ? entry.objectType + entry.id : (entry.icon || '⚙')) + '</div><div class="item-main"><div class="item-name">' + esc(entry.name) + '</div><div class="item-en">' + esc(entry.en) + '</div></div>' +
      (entry.tier ? '<span class="tier ' + (entry.tier === 'A' ? 'a' : '') + '">' + esc(entry.tier) + '</span>' : '') + favorite + '</div>' +
      '<div class="item-desc">' + esc(description) + '</div><div class="card-foot"><span class="code">' + esc(command) + '</span>' +
      '<button class="card-action" onclick="event.cancelBubble=true;IsaacApp.addEntry(' + index + ')">入队</button><button class="card-action primary" onclick="event.cancelBubble=true;IsaacApp.sendEntry(' + index + ')">' + (isItem ? '给予' : '执行') + '</button></div></div></div>';
  }
  function renderCards() {
    refreshVisible();
    var html = "";
    if (!pageEntries.length) html = '<div class="empty"><div>⌁</div><br />没有找到匹配内容</div>';
    else for (var i = 0; i < pageEntries.length; i++) html += renderCard(pageEntries[i], i);
    el("cards").innerHTML = '<div class="grid">' + html + '</div>';
    selectedIndex = Math.min(selectedIndex, Math.max(0, pageEntries.length - 1));
  }
  function renderAll() { renderNav(); renderCards(); renderQueue(); }

  function selectCategory(id) {
    if (!validCategory(id)) return;
    currentCategory = id; currentPage = 1; selectedIndex = 0; el("search").value = "";
    state.ui.lastCategory = id; root.IsaacState.save(); renderAll(); el("content").scrollTop = 0;
  }
  function setStageMode(mode) {
    stageMode = mode === "greed" ? "greed" : "normal"; state.ui.stageMode = stageMode; root.IsaacState.save(); currentPage = 1; renderAll();
  }
  function changePage(delta) { currentPage += delta; renderCards(); el("content").scrollTop = 0; }
  function focusCard(index) { selectedIndex = index; }
  function focusSelected() { var node = el("card-" + selectedIndex); if (node) node.focus(); }

  function setManual(entry) {
    el("manualCommand").value = entry.command || entry.cmd;
    el("manualRisk").innerText = root.IsaacQueue.risk(entry.command || entry.cmd).label;
  }
  function normalizeManualRepeat() {
    var value = parseInt(el("repeatCount").value.replace(/[^0-9]/g, ""), 10);
    if (isNaN(value) || value < 1) value = 1; if (value > 99) value = 99;
    var command = trim(el("manualCommand").value);
    if (!root.IsaacQueue.safeRepeat(command) && value > 1) { value = 1; toast("该命令按安全规则固定执行 1 次。", "warn"); }
    el("repeatCount").value = String(value); return value;
  }
  function adjustManualRepeat(delta) { el("repeatCount").value = String(Math.max(1, Math.min(99, normalizeManualRepeat() + delta))); normalizeManualRepeat(); }
  function entryAt(index) { return index >= 0 && index < pageEntries.length ? pageEntries[index] : null; }
  function toggleFavorite(index) {
    var entry = entryAt(index); if (!entry || !entry.objectKey) return;
    var key = entry.objectKey; if (state.favorites[key]) delete state.favorites[key]; else state.favorites[key] = true;
    root.IsaacState.save(); renderAll();
  }
  function openDetail(index) {
    var entry = entryAt(index); if (!entry) return; detailEntry = entry; setManual(entry);
    var isItem = entry.kind === "item", removable = isItem && entry.canRemove, description = entry.desc || entry.description || "内置目录条目；当前没有详细说明。";
    var removeCommand = removable ? "remove " + entry.objectType + entry.id : "";
    el("detailBody").innerHTML = '<div class="detail-name">' + esc(entry.name) + '</div><div class="detail-en">' + esc(entry.en) + (entry.objectKey ? ' · ID ' + entry.objectKey : '') + '</div>' +
      '<div class="detail-desc">' + esc(description) + '</div><div class="detail-code">' + esc(entry.command || entry.cmd) + '</div>' +
      (removable ? '<div class="detail-note">移除只会提交 ' + esc(removeCommand) + '；它不会回滚已经产生的资源、实体、房间或生命变化。</div>' : '<div class="detail-note">此类型不提供移除；自定义及流程命令请在一次性测试存档中使用。</div>') +
      '<div class="detail-actions">' + (isItem ? '<button class="small-btn" onclick="IsaacApp.detailFavorite()">' + (isFavorite(entry) ? '取消收藏' : '收藏') + '</button>' : '') +
      (removable ? '<button class="danger-btn" onclick="IsaacApp.removeDetailItem()">移除本体</button>' : '') + '<button class="small-btn" onclick="IsaacApp.addDetailToQueue()">加入队列</button><button class="danger-btn" onclick="IsaacApp.sendDetail()">立即执行</button></div>';
    el("detailDrawer").className = "drawer open"; el("queueDrawer").className = "drawer";
  }
  function closeDrawers() { el("detailDrawer").className = "drawer"; el("queueDrawer").className = "drawer"; }

  function addCommand(command, label, repeat, source) {
    var result = root.IsaacQueue.add(command, label, repeat, source);
    if (!result.ok) { toast(result.code === "QUEUE_LIMIT" ? "队列最多 200 步。" : "命令必须为单行且不超过 500 字符。", "warn"); return false; }
    if (result.repeatLimited) toast("该命令已按安全规则改为 1 次并加入队列。", "warn"); else toast("已加入队列。", "ok");
    return true;
  }
  function addEntry(index) { var entry = entryAt(index); if (entry) { setManual(entry); addCommand(entry.command || entry.cmd, entry.name, normalizeManualRepeat(), entry.kind); } }
  function sendSteps(values) {
    var mode = el("sendMode").value; state.ui.consoleMode = mode; root.IsaacState.save();
    var result = root.IsaacQueue.execute(values, mode, false);
    if (!result.ok) toast(result.code === "NO_BRIDGE" ? "Windows 脚本组件被拦截，当前无法发送命令。" : (result.code === "BUSY" ? "上一项任务仍在发送。" : "没有可执行的命令。"), "warn");
    else { toast("任务已提交给发送器。", "ok"); openQueue(); }
  }
  function sendEntry(index) { var entry = entryAt(index); if (!entry) return; setManual(entry); var count = normalizeManualRepeat(); sendSteps([{stepId:"direct-"+new Date().getTime(),label:entry.name,command:entry.command||entry.cmd,repeat:count,source:entry.kind}]); }
  function addManualToQueue() { addCommand(el("manualCommand").value, "手动命令", normalizeManualRepeat(), "manual"); }
  function sendManual() { var command = trim(el("manualCommand").value); sendSteps([{stepId:"manual-"+new Date().getTime(),label:"手动命令",command:command,repeat:normalizeManualRepeat(),source:"manual"}]); }
  function copyManual() { toast(root.IsaacQueue.copyText(el("manualCommand").value) ? "命令已复制。" : "无法访问剪贴板。", "ok"); }

  function renderQueue() {
    var steps = root.IsaacQueue.getSteps(), html = "", total = 0;
    el("queueCount").innerText = steps.length;
    for (var i = 0; i < steps.length; i++) {
      var step = steps[i], risk = root.IsaacQueue.risk(step.command); total += step.repeat;
      html += '<div class="queue-step" draggable="true" ondragstart="IsaacApp.dragStart(' + i + ')" ondragover="IsaacApp.dragOver(event)" ondrop="IsaacApp.dropStep(' + i + ')">' +
        '<div class="queue-line"><span class="queue-label">' + (i + 1) + '. ' + esc(step.label) + '</span><span class="risk ' + risk.key + '">' + risk.label + '</span></div><div class="queue-command">' + esc(step.command) + '</div>' +
        '<div class="queue-tools"><button onclick="IsaacApp.moveStep(' + i + ',-1)">↑</button><button onclick="IsaacApp.moveStep(' + i + ',1)">↓</button><button onclick="IsaacApp.removeStep(' + i + ')">删除</button><span style="margin-left:auto">次数 </span><input value="' + step.repeat + '" onchange="IsaacApp.updateStepRepeat(' + i + ',this.value)" /></div></div>';
    }
    el("queueList").innerHTML = html || '<div class="empty">队列为空</div>';
    el("queueSummary").innerText = steps.length ? (steps.length + " 步 · 共提交 " + total + " 次输入；执行前仅做结构校验。") : "队列为空";
    el("executeQueueBtn").disabled = !steps.length || root.IsaacQueue.isBusy();
    el("cancelQueueBtn").disabled = !root.IsaacQueue.isBusy();
  }
  function openQueue() { el("queueDrawer").className = "drawer open"; el("detailDrawer").className = "drawer"; renderQueue(); }
  function moveStep(index, delta) { root.IsaacQueue.move(index, index + delta); }
  function removeStep(index) { root.IsaacQueue.remove(index); }
  function updateStepRepeat(index, value) { if (!root.IsaacQueue.updateRepeat(index, value)) toast("该命令只能执行 1 次。", "warn"); }
  function clearQueue() { if (!root.IsaacQueue.isBusy() && confirm("清空当前队列？")) root.IsaacQueue.clear(); }
  function dragStart(index) { dragIndex = index; }
  function dragOver(event) { event = event || window.event; if (event.preventDefault) event.preventDefault(); event.returnValue = false; }
  function dropStep(index) { if (dragIndex >= 0) root.IsaacQueue.move(dragIndex, index); dragIndex = -1; }
  function executeQueue() {
    var steps = root.IsaacQueue.getSteps(); if (!steps.length) return;
    if (!confirm("将按顺序向游戏提交 " + steps.length + " 步命令。\n\n状态仅表示输入已提交，实际效果请在游戏内确认。")) return;
    sendSteps(steps);
  }
  function cancelQueue() { if (root.IsaacQueue.cancel()) toast("将在当前输入完成后取消。", "warn"); }
  function saveCurrentQueue() { var name = prompt("方案名称：", "我的方案"); if (name && root.IsaacState.saveNamedQueue(name, root.IsaacQueue.getSteps())) toast("方案已保存。", "ok"); }

  function showModal(title, html) { el("modalTitle").innerText = title; el("modalBody").innerHTML = html; el("modalBackdrop").className = "modal-backdrop open"; }
  function closeModal() { el("modalBackdrop").className = "modal-backdrop"; }
  function showHistory() {
    var history = state.history, html = "";
    for (var i = 0; i < history.length; i++) {
      var h = history[i]; html += '<div class="modal-row"><strong>' + esc(h.label || "命令") + '</strong>　<code>' + esc(h.command) + '</code><br />请求 ' + esc(h.requested) + ' · 已提交 ' + esc(h.submitted) + ' · ' + esc(h.state) + '<br /><span>' + esc(h.timestamp || "旧版记录") + '　' + esc(h.note || "") + '</span></div>';
    }
    showModal("最近 100 条提交记录", html || '<div class="empty">暂无记录</div>');
  }
  function showSavedQueues() {
    var queues = state.savedQueues, html = "";
    for (var i = 0; i < queues.length; i++) html += '<div class="modal-row"><strong>' + esc(queues[i].name) + '</strong>　' + queues[i].steps.length + ' 步 <button class="small-btn" onclick="IsaacApp.loadSavedQueue(' + i + ')">载入</button><button class="small-btn" onclick="IsaacApp.deleteSavedQueue(' + i + ')">删除</button></div>';
    showModal("已保存方案", html || '<div class="empty">暂无方案</div>');
  }
  function loadSavedQueue(index) { if (state.savedQueues[index]) { root.IsaacQueue.replace(state.savedQueues[index].steps); closeModal(); openQueue(); toast("方案已载入，尚未执行。", "ok"); } }
  function deleteSavedQueue(index) { if (state.savedQueues[index] && confirm("删除方案“" + state.savedQueues[index].name + "”？")) { state.savedQueues.splice(index, 1); root.IsaacState.save(); showSavedQueues(); } }

  function runImport(path) {
    if (importBusy) return; importBusy = true; toast("正在从本机 EID 导入详细说明…", "");
    var host = root.IsaacHost;
    if (!host || !host.available || !host.fso || !host.shell) { importBusy = false; toast("Windows 脚本宿主桥不可用，无法导入 EID。", "warn"); return; }
    var fso = host.fso, shell = host.shell, temp = fso.GetSpecialFolder(2).Path;
    var statusPath = fso.BuildPath(temp, "isaac-cn-import-" + new Date().getTime() + ".json");
    function quote(value) { return '"' + String(value).replace(/"/g, '""') + '"'; }
    var command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + quote(appDir() + "\\import-eid-catalog.ps1") + ' -OutputFile ' + quote(root.IsaacState.getCatalogPath()) + ' -StatusFile ' + quote(statusPath) + (path ? ' -EidPath ' + quote(path) : '');
    shell.Run(command, 0, false); var started = new Date().getTime();
    function pollImport() {
      if (fso.FileExists(statusPath)) {
        var file = fso.OpenTextFile(statusPath, 1, false, -1), text = file.ReadAll(); file.Close();
        try { fso.DeleteFile(statusPath, true); } catch (ignore) {}
        var result = null; try { result = JSON.parse(text); } catch (ignore2) {}
        importBusy = false;
        if (result && result.success) {
          state.catalog = result.details; root.IsaacState.save(); loadCatalog(); renderAll(); toast(result.message, "ok"); return;
        }
        if ((!result || result.code === "EID_NOT_FOUND") && !path) { chooseEidFolder(); return; }
        toast(result ? result.message : "EID 导入结果无法解析。", "warn"); return;
      }
      if (new Date().getTime() - started > 120000) { importBusy = false; toast("EID 导入超时。", "warn"); return; }
      setTimeout(pollImport, 250);
    }
    setTimeout(pollImport, 250);
  }
  function chooseEidFolder() {
    importBusy = false;
    try {
      var shellApplication = root.IsaacHost && root.IsaacHost.shellApplication;
      if (!shellApplication) { toast("系统目录选择器不可用；内置 1056 项仍可完整使用。", "warn"); return; }
      var dialog = shellApplication.BrowseForFolder(0, "选择 External Item Descriptions 根目录", 0, 0);
      if (dialog) runImport(dialog.Self.Path); else toast("未选择 EID 目录；内置 1056 项仍可完整使用。", "warn");
    } catch (ignore) { toast("未找到 EID；内置 1056 项仍可完整使用。", "warn"); }
  }
  function importCatalog() {
    if (!root.IsaacQueue.bridgeAvailable() || root.IsaacState.isMemoryMode()) { toast("Windows 脚本组件被拦截，当前只能浏览内置目录。请运行一键环境检测。", "warn"); return; }
    runImport("");
  }

  function onQueueProgress(status) {
    var node = el("queueProgress"); node.style.display = "block";
    node.innerText = "正在提交步骤 " + status.currentStep + "/" + status.stepCount + "　次数 " + status.repeatDone + "/" + status.repeatTotal;
    renderQueue();
  }
  function onQueueFinished(status) {
    var node = el("queueProgress"), message;
    if (status.state === "completed") {
      root.IsaacQueue.clear(); message = status.errorCode === "CLOSE_FAILED" ? "输入已全部提交，但 Esc 关闭可能被系统拦截。" : "输入已全部提交；请在游戏内确认实际效果。";
      toast(message, status.errorCode ? "warn" : "ok");
    } else {
      if (status.remainingSteps && status.remainingSteps.length) root.IsaacQueue.replace(status.remainingSteps);
      message = "任务" + (status.state === "cancelled" ? "已取消" : "未完整提交") + "（" + (status.errorCode || status.state) + "）；队列已仅保留未提交部分。";
      toast(message, "warn");
    }
    node.style.display = "block"; node.innerText = message; renderQueue();
  }
  function updateGameStatus() {
    if (root.IsaacQueue.isBusy()) return;
    root.IsaacQueue.probe(function (running, status) {
      el("statusDot").className = "status-dot" + (running ? " online" : "");
      el("statusText").innerText = status && status.errorCode === "NO_BRIDGE" ? ("脚本桥错误：" + root.IsaacQueue.getBridgeError()) : (running ? "游戏运行中" : "未检测到游戏");
    });
  }

  function keyboard(event) {
    event = event || window.event; var target = event.srcElement || event.target, tag = target && target.tagName ? target.tagName.toLowerCase() : "";
    if (event.ctrlKey && event.keyCode === 75) { el("search").focus(); event.returnValue = false; return; }
    if (event.ctrlKey && event.keyCode === 13) { executeQueue(); event.returnValue = false; return; }
    if (event.keyCode === 27) { closeDrawers(); closeModal(); return; }
    if (tag === "input" || tag === "select") return;
    if (event.keyCode === 37 || event.keyCode === 38) { selectedIndex = Math.max(0, selectedIndex - 1); focusSelected(); event.returnValue = false; }
    if (event.keyCode === 39 || event.keyCode === 40) { selectedIndex = Math.min(pageEntries.length - 1, selectedIndex + 1); focusSelected(); event.returnValue = false; }
    if (event.keyCode === 13 && pageEntries[selectedIndex]) { sendEntry(selectedIndex); event.returnValue = false; }
  }

  function init() {
    try { window.resizeTo(1280, 840); window.moveTo(Math.max(0,(screen.availWidth-1280)/2), Math.max(0,(screen.availHeight-840)/2)); } catch (ignore) {}
    state = root.IsaacState.init(); currentCategory = validCategory(state.ui.lastCategory) ? state.ui.lastCategory : "featured"; stageMode = state.ui.stageMode; el("sendMode").value = state.ui.consoleMode;
    loadCatalog();
    if (root.IsaacState.isMemoryMode()) el("catalogStatus").innerText += " · 临时浏览模式";
    root.IsaacQueue.init(appDir(), { changed: function () { renderQueue(); }, progress: onQueueProgress, finished: onQueueFinished });
    renderAll(); updateGameStatus(); setInterval(updateGameStatus, 4000);
    el("search").onkeyup = function () { if (searchTimer) clearTimeout(searchTimer); searchTimer = setTimeout(function () { currentPage = 1; selectedIndex = 0; renderCards(); }, 120); };
    el("manualCommand").onkeyup = function () { el("manualRisk").innerText = root.IsaacQueue.risk(this.value).label; };
    el("repeatCount").onblur = normalizeManualRepeat;
    el("manualCommand").onkeydown = function (event) { event = event || window.event; if (event.keyCode === 13 && !event.ctrlKey) sendManual(); };
    window.onresize = function () { renderCards(); };
    document.onkeydown = keyboard;
  }

  root.IsaacApp = {
    init: init, selectCategory: selectCategory, setStageMode: setStageMode, changePage: changePage, focusCard: focusCard,
    openDetail: openDetail, closeDrawers: closeDrawers, openQueue: openQueue, toggleFavorite: toggleFavorite,
    addEntry: addEntry, sendEntry: sendEntry, adjustManualRepeat: adjustManualRepeat, addManualToQueue: addManualToQueue, sendManual: sendManual, copyManual: copyManual,
    moveStep: moveStep, removeStep: removeStep, updateStepRepeat: updateStepRepeat, clearQueue: clearQueue, executeQueue: executeQueue, cancelQueue: cancelQueue,
    dragStart: dragStart, dragOver: dragOver, dropStep: dropStep, saveCurrentQueue: saveCurrentQueue,
    showHistory: showHistory, showSavedQueues: showSavedQueues, closeModal: closeModal, loadSavedQueue: loadSavedQueue, deleteSavedQueue: deleteSavedQueue,
    importCatalog: importCatalog,
    detailFavorite: function () { if (!detailEntry || !detailEntry.objectKey) return; var fake = pageEntries.indexOf ? pageEntries.indexOf(detailEntry) : -1; if (fake >= 0) toggleFavorite(fake); else { var key=detailEntry.objectKey; if(state.favorites[key])delete state.favorites[key];else state.favorites[key]=true;root.IsaacState.save();renderAll(); } closeDrawers(); },
    removeDetailItem: function () { var command; if (detailEntry && detailEntry.canRemove) { command="remove "+detailEntry.objectType+detailEntry.id; if (confirm("提交 " + command + "？\n\n这只会移除本体，不会回滚已经产生的效果。")) sendSteps([{stepId:"remove-"+new Date().getTime(),label:"移除 "+detailEntry.name,command:command,repeat:1,source:"detail"}]); } },
    addDetailToQueue: function () { if (detailEntry) addCommand(detailEntry.command||detailEntry.cmd,detailEntry.name,normalizeManualRepeat(),detailEntry.kind); },
    sendDetail: function () { if (detailEntry) sendSteps([{stepId:"detail-"+new Date().getTime(),label:detailEntry.name,command:detailEntry.command||detailEntry.cmd,repeat:normalizeManualRepeat(),source:detailEntry.kind}]); }
  };
  window.onload = init;
}(window));

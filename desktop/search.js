(function (root) {
  "use strict";

  var entries = [], items = [], commands = [], byKey = {};
  var typeOrder = { c: 0, t: 1, k: 2, p: 3 };
  var typeMeta = {
    c: { cat: "all_items", icon: "物", desc: "官方收藏品；可重复给予，移除只影响道具本体。", canRemove: true, repeatMax: 99 },
    t: { cat: "trinkets", icon: "饰", desc: "官方饰品；固定单次给予，可移除饰品本体。", canRemove: true, repeatMax: 1 },
    k: { cat: "cards", icon: "卡", desc: "官方卡牌或符文；固定单次给予。", canRemove: false, repeatMax: 1 },
    p: { cat: "pills", icon: "药", desc: "官方胶囊效果；固定单次给予。", canRemove: false, repeatMax: 1 }
  };

  function trim(value) { return String(value || "").replace(/^\s+|\s+$/g, ""); }
  function lower(value) { return trim(value).toLowerCase(); }
  function compact(value) { return lower(value).replace(/[\s_'".,!?·—\-:]+/g, ""); }
  function copy(source) {
    var target = {}, key;
    for (key in source) if (source.hasOwnProperty(key)) target[key] = source[key];
    return target;
  }

  function index(entry, order) {
    entry.order = order;
    entry.command = entry.command || entry.cmd || "";
    entry.cmd = entry.command;
    entry._name = lower(entry.name);
    entry._en = lower(entry.en);
    entry._command = lower(entry.command);
    entry._id = entry.id == null ? "" : String(entry.id);
    entry._typedId = entry.objectType ? entry.objectType + entry._id : "";
    entry._search = lower([
      entry.name, entry.en, entry.description || entry.desc, entry.id, entry.objectKey,
      entry._typedId, entry.command, entry.pinyin, entry.initials, entry.aliases
    ].join(" "));
    entry._compact = compact(entry._search);
    return entry;
  }

  function createObject(row, descriptions) {
    var type = row[0], id = parseInt(row[1], 10), meta = typeMeta[type], key = type + ":" + id;
    var description = descriptions[key] || meta.desc;
    return {
      id: id,
      objectType: type,
      objectKey: key,
      name: row[2],
      en: row[3],
      pinyin: row[4],
      initials: row[5],
      cat: meta.cat,
      catalogCategory: meta.cat,
      icon: meta.icon,
      desc: description,
      description: description,
      descSource: descriptions[key] ? "EID" : "内置目录",
      command: "giveitem " + type + id,
      kind: "item",
      canFavorite: true,
      canRemove: meta.canRemove,
      repeatMax: meta.repeatMax
    };
  }

  function configure(curated, commandSource, enhancedCatalog) {
    entries = []; items = []; commands = []; byKey = {};
    var descriptions = enhancedCatalog && enhancedCatalog.descriptions ? enhancedCatalog.descriptions : {};
    var rows = root.IsaacObjectRows || [], i, entry, key, overlay;
    for (i = 0; i < rows.length; i++) {
      entry = createObject(rows[i], descriptions);
      byKey[entry.objectKey] = entry;
      items.push(entry);
    }
    for (i = 0; i < curated.length; i++) {
      key = "c:" + parseInt(curated[i].id, 10);
      entry = byKey[key];
      if (!entry) continue;
      overlay = curated[i];
      for (var property in overlay) if (overlay.hasOwnProperty(property)) entry[property] = overlay[property];
      entry.objectType = "c";
      entry.objectKey = key;
      entry.catalogCategory = "all_items";
      entry.command = "giveitem c" + entry.id;
      entry.kind = "item";
      entry.canFavorite = true;
      entry.canRemove = true;
      entry.repeatMax = 99;
      entry.descSource = "内置精选";
      entry.curatedOrder = i;
    }
    items.sort(function (a, b) {
      if (typeOrder[a.objectType] !== typeOrder[b.objectType]) return typeOrder[a.objectType] - typeOrder[b.objectType];
      return a.id - b.id;
    });
    for (i = 0; i < items.length; i++) { index(items[i], i); entries.push(items[i]); }
    for (i = 0; i < commandSource.length; i++) {
      entry = copy(commandSource[i]);
      entry.kind = "command";
      entry.canFavorite = false;
      entry.canRemove = false;
      entry.repeatMax = /^\s*(giveitem|spawn)\s+/i.test(entry.cmd || "") ? 99 : 1;
      index(entry, i);
      commands.push(entry); entries.push(entry);
    }
  }

  function score(entry, query) {
    var q = lower(query), cq = compact(query);
    if (!q) return -1;
    if (entry._command === q || entry._typedId === q || entry.objectKey === q || entry._id === q) return 0;
    if (entry._name === q || entry._en === q) return 1;
    if (entry._name.indexOf(q) === 0 || entry._en.indexOf(q) === 0 || entry._command.indexOf(q) === 0) return 2;
    if (entry._search.indexOf(q) >= 0) return 3;
    if (cq && entry._compact.indexOf(cq) >= 0) return 4;
    var tokens = q.split(/\s+/), matched = true;
    for (var i = 0; i < tokens.length; i++) if (entry._search.indexOf(tokens[i]) < 0) matched = false;
    return matched ? 5 : -1;
  }

  function search(query) {
    var found = [], i, rank;
    for (i = 0; i < entries.length; i++) {
      rank = score(entries[i], query);
      if (rank >= 0) found.push({ value: entries[i], rank: rank });
    }
    found.sort(function (a, b) {
      if (a.rank !== b.rank) return a.rank - b.rank;
      if (a.value.kind !== b.value.kind) return a.value.kind === "item" ? -1 : 1;
      if (a.value.kind === "item" && typeOrder[a.value.objectType] !== typeOrder[b.value.objectType]) {
        return typeOrder[a.value.objectType] - typeOrder[b.value.objectType];
      }
      return a.value.order - b.value.order;
    });
    var result = [];
    for (i = 0; i < found.length; i++) result.push(found[i].value);
    return result;
  }

  root.IsaacSearch = {
    configure: configure,
    search: search,
    getItems: function () { return items; },
    getCommands: function () { return commands; },
    getObject: function (key) { return byKey[String(key || "").toLowerCase()] || null; },
    getItem: function (id) { return byKey["c:" + parseInt(id, 10)] || null; }
  };
}(window));

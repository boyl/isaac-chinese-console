(function (root) {
  "use strict";

  var entries = [];
  var items = [];
  var byId = {};
  var commands = [];

  function trim(value) { return String(value || "").replace(/^\s+|\s+$/g, ""); }
  function lower(value) { return trim(value).toLowerCase(); }
  function compact(value) { return lower(value).replace(/[\s_'".,!?·—\-]+/g, ""); }

  function copy(source) {
    var target = {}, key;
    for (key in source) if (source.hasOwnProperty(key)) target[key] = source[key];
    return target;
  }

  function index(entry, order) {
    var aliases = entry.aliases || "";
    if (!aliases && root.IsaacCuratedAliases) aliases = root.IsaacCuratedAliases[entry.name] || "";
    entry.aliases = aliases;
    entry.command = entry.command || entry.cmd || (entry.id ? "giveitem c" + entry.id : "");
    entry.cmd = entry.command;
    entry.kind = entry.id ? "item" : "command";
    entry.order = order;
    entry._name = lower(entry.name);
    entry._en = lower(entry.en);
    entry._command = lower(entry.command);
    entry._id = entry.id ? String(entry.id) : "";
    entry._search = lower([
      entry.name, entry.en, entry.description || entry.desc, entry.id, entry.command,
      entry.pinyin, entry.initials, aliases
    ].join(" "));
    entry._compact = compact(entry._search);
    return entry;
  }

  function configure(curated, commandSource, importedCatalog) {
    entries = [];
    items = [];
    byId = {};
    commands = [];
    var imported = importedCatalog && importedCatalog.items ? importedCatalog.items : [];
    var i, entry, id;
    for (i = 0; i < imported.length; i++) {
      entry = copy(imported[i]);
      id = parseInt(entry.id, 10);
      if (!id || byId[id]) continue;
      entry.id = id;
      entry.catalogOnly = true;
      entry = index(entry, items.length);
      byId[id] = entry;
      items.push(entry);
    }
    for (i = 0; i < curated.length; i++) {
      id = parseInt(curated[i].id, 10);
      entry = byId[id] || {};
      var overlay = curated[i], key;
      for (key in overlay) if (overlay.hasOwnProperty(key)) entry[key] = overlay[key];
      entry.id = id;
      entry.catalogOnly = false;
      entry = index(entry, i);
      if (!byId[id]) items.push(entry);
      byId[id] = entry;
    }
    items.sort(function (a, b) { return a.id - b.id; });
    for (i = 0; i < items.length; i++) {
      index(items[i], i);
      entries.push(items[i]);
    }
    for (i = 0; i < commandSource.length; i++) {
      entry = index(copy(commandSource[i]), i);
      commands.push(entry);
      entries.push(entry);
    }
  }

  function score(entry, query) {
    var q = lower(query), cq = compact(query);
    if (!q) return -1;
    if (entry._id === q || entry._command === q) return 0;
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
    getItem: function (id) { return byId[parseInt(id, 10)] || null; }
  };
}(window));

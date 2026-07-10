// Renders three views from github-action-benchmark BENCHMARK_DATA objects.
// app.js owns all data loading so there is no dependency on script-tag
// onload/onerror ordering. __SIZE__ / __SPEED__ are the two suites
// (smaller-better / bigger-better).

window.__SIZE__ = null;
window.__SPEED__ = null;

// j1 yellow / j2 blue / j4 green; the cpu+cache variants reuse their base hue in
// a pastel (lighter) shade so all five overlay on one chart, cache visibly tied
// to its cpu: j2c = pastel blue, j4c = pastel green.
var VARIANT_COLOR = {
  j1: "#e6b800", j2: "#1f77b4", j4: "#2ca02c",
  j2a: "#ff7f0e", j2ac: "#fdd0a2",
  j2c: "#9ecae1", j4c: "#a1d99b"
};
var VARIANT_LABEL = { j1: "J1", j2: "J2", j4: "J4",
  j2a: "J2A", j2ac: "J2A+cache",
  j2c: "J2+cache", j4c: "J4+cache" };

function variantOf(extra) {
  var e = (extra || "").toLowerCase();
  if (e.indexOf("j2ac") >= 0) return "j2ac";
  if (e.indexOf("j2a") >= 0) return "j2a";
  if (e.indexOf("j2c") >= 0) return "j2c";  // before j2/j4 (j4c contains "j4")
  if (e.indexOf("j4c") >= 0) return "j4c";
  if (e.indexOf("j1") >= 0) return "j1";
  if (e.indexOf("j4") >= 0) return "j4";
  return "j2"; // default incl. legacy "direct-rom72"
}

// Benchmark metric names carry a "[j1]"/"[j4]"/"[J2+cache]"/"[J4+cache]" suffix so
// github-action-benchmark keys each variant as its own series (J2 stays bare =
// continuous history). The dashboard derives the variant from that suffix
// (falling back to `extra` for historical bare-J2 points) and groups on the
// suffix-stripped base name, so all five variants overlay on one chart.
function variantOfBench(name, extra) {
  var m = /\s\[(j[124]|j2a)\]$/.exec(name || "");
  if (m) return m[1];
  if (/\s\[J2A\+cache\]$/.test(name || "")) return "j2ac";
  if (/\s\[J2\+cache\]$/.test(name || "")) return "j2c";
  if (/\s\[J4\+cache\]$/.test(name || "")) return "j4c";
  return variantOf(extra);
}
function baseName(name) {
  // Strip the variant suffix (incl. the cpu+cache labels) so all five variants
  // group onto one chart per base metric.
  return (name || "").replace(/\s\[(j[124]|j2a|J2A\+cache|J2\+cache|J4\+cache)\]$/, "");
}

// Load a script that assigns window.BENCHMARK_DATA; resolve with that value
// captured at load time (the next load overwrites the global).
function loadData(src) {
  return new Promise(function (resolve, reject) {
    var s = document.createElement("script");
    s.src = src;
    s.onload = function () { resolve(window.BENCHMARK_DATA); };
    s.onerror = function () { reject(new Error("failed to load " + src)); };
    document.head.appendChild(s);
  });
}

// Production: ./bench-{size,speed}/data.js. Local dev fallback: ./fixtures/data.js
// (one fixture standing in for both suites). Loads are sequential so the global
// is captured before the next overwrites it.
function boot() {
  loadData("./bench-size/data.js")
    .then(function (size) { window.__SIZE__ = size; }, function () { /* size suite absent */ })
    .then(function () { return loadData("./bench-speed/data.js"); })
    .then(function (speed) { window.__SPEED__ = speed; }, function () { /* speed suite absent */ })
    .then(function () {
      if (window.__SIZE__ || window.__SPEED__) return;
      // Local dev: no published suites — fall back to the committed fixture
      // (one object standing in for both suites).
      return loadData("./fixtures/data.js").then(function (d) {
        window.__SIZE__ = d; window.__SPEED__ = d;
      });
    })
    .then(render)
    .catch(function (e) { console.error("no benchmark data available", e); });
}

function seriesByName(data) {
  // -> { metricName: { variant: [ {x: date, y: value, commit} ] } }
  var out = {};
  if (!data || !data.entries) return out;
  Object.keys(data.entries).forEach(function (suite) {
    data.entries[suite].forEach(function (run) {
      run.benches.forEach(function (b) {
        var v = variantOfBench(b.name, b.extra);
        var base = baseName(b.name);
        if (!out[base]) out[base] = {};
        if (!out[base][v]) out[base][v] = [];
        out[base][v].push({ x: run.date, y: b.value, commit: run.commit });
      });
    });
  });
  return out;
}

// variantMap: { variant: [ {x,y,commit} ] } for a single metric.
function lineCard(parent, title, variantMap, unit, budget) {
  var card = document.createElement("div"); card.className = "card";
  var cv = document.createElement("canvas"); card.appendChild(cv); parent.appendChild(card);
  var datasets = Object.keys(variantMap).sort().map(function (v) {
    var pts = variantMap[v].slice().sort(function (a, b) { return a.x - b.x; });
    var color = VARIANT_COLOR[v] || "#888888";
    return {
      label: VARIANT_LABEL[v] || v.toUpperCase(),
      data: pts,
      borderColor: color,
      backgroundColor: color,
      tension: 0.2,
      pointRadius: 3
    };
  });
  if (budget) {
    // Flat reference line spanning the data's x-range at y = budget.
    var xs = [];
    datasets.forEach(function (d) { d.data.forEach(function (p) { xs.push(p.x); }); });
    if (xs.length) {
      var xmin = Math.min.apply(null, xs), xmax = Math.max.apply(null, xs);
      datasets.push({
        label: "up5k budget (" + budget + ")",
        data: [{ x: xmin, y: budget }, { x: xmax, y: budget }],
        borderColor: "#d62728",
        borderDash: [6, 4],
        pointRadius: 0,
        fill: false,
        tension: 0
      });
    }
  }
  new Chart(cv, {
    type: "line",
    data: { datasets: datasets },
    options: {
      parsing: false,
      scales: { x: { type: "linear", ticks: { callback: function (v) { return new Date(v).toISOString().slice(0, 10); } } } },
      plugins: {
        legend: { display: true },
        title: { display: true, text: title + (unit ? " (" + unit + ")" : "") },
        tooltip: { callbacks: { title: function (it) { return new Date(it[0].parsed.x).toISOString().slice(0, 10); } } }
      }
    }
  });
}

function unitFor(name) {
  if (name.indexOf("Fmax") >= 0) return "MHz";
  if (name.indexOf("WNS") >= 0 || name.indexOf("TNS") >= 0) return "ns";
  if (name.indexOf("power") >= 0) return "mW";
  if (name.indexOf("area") >= 0) return "um2";
  return "";
}

// Flatten a { variant: points } map into a single sorted point array.
// Used by callers that need a flat list (perblock, latestBenches consumers).
// When multiple variants exist, J2 is preferred as the reference variant;
// fall back to the first alphabetical variant if J2 is absent.
function flattenVariants(variantMap) {
  var keys = Object.keys(variantMap).sort();
  var key = variantMap["j2"] ? "j2" : keys[0];
  return variantMap[key] ? variantMap[key].slice() : [];
}

function render() {
  var size = seriesByName(window.__SIZE__), speed = seriesByName(window.__SPEED__);
  var all = Object.assign({}, size, speed);
  // Route each metric into its target's section; strip the "<target> · " prefix
  // from the card title since the section heading already names the target.
  var grids = {
    "asic-nangate45": { grid: "trends-asic", section: "asic-section", any: false },
    "ecp5-lfe5u-85f": { grid: "trends-ecp5", section: "fpga-section", any: false },
    "ice40-up5k": { grid: "trends-ice40", section: "ice40-section", any: false }
  };
  Object.keys(all).sort().forEach(function (name) {
    var parts = name.split(" · ");
    var target = parts[0];
    var dest = grids[target] || grids["ecp5-lfe5u-85f"];  // unknown target -> FPGA
    dest.any = true;
    var label = parts.length > 1 ? parts.slice(1).join(" · ") : name;
    var budget = (name === "ice40-up5k · cpu/SB_LUT4") ? 5280 : null;
    lineCard(document.getElementById(dest.grid), label, all[name], unitFor(name), budget);
  });
  Object.keys(grids).forEach(function (t) {
    if (grids[t].any) document.getElementById(grids[t].section).hidden = false;
  });
  renderPerBlock();
  renderVariants(all);
}

function latestBenches(data) {
  // newest run across the suite -> {name: bench}
  // The bench value is read from the J2 (reference) variant, or the first
  // available variant when J2 is absent, to stay consistent with pre-variant
  // behavior.
  var best = null;
  if (data && data.entries) Object.keys(data.entries).forEach(function (s) {
    data.entries[s].forEach(function (run) { if (!best || run.date > best.date) best = run; });
  });
  var map = {};
  if (best) best.benches.forEach(function (b) {
    var v = variantOfBench(b.name, b.extra);
    var base = baseName(b.name);
    // Key on the suffix-stripped base name; keep the J2 entry per metric (if J2
    // never appears, keep first seen).
    if (!map[base] || v === "j2") map[base] = b;
  });
  return map;
}

function renderPerBlock() {
  var latest = latestBenches(window.__SIZE__);
  var blocks = ["decode", "datapath", "mult", "register_file"];
  var present = blocks.filter(function (b) { return latest["asic-nangate45 · " + b + "/area"]; });
  // Per-block ASIC area isn't emitted yet (the ASIC flow is flattened); keep the
  // section hidden until at least one block reports, so we don't show zero bars.
  if (!present.length) return;
  document.getElementById("perblock-section").hidden = false;
  var vals = blocks.map(function (b) { var k = "asic-nangate45 · " + b + "/area"; return latest[k] ? latest[k].value : 0; });
  new Chart(document.getElementById("perblock"), {
    type: "bar",
    data: { labels: blocks, datasets: [{ label: "area (um2)", data: vals }] },
    options: { plugins: { legend: { display: false } } }
  });
}

function renderVariants(all) {
  // Group latest value per (variant, metric) from the nested seriesByName shape.
  // Each all[name] is { variant: [points] }; we pick the last point per variant.
  var rows = {}, variants = {};
  Object.keys(all).forEach(function (name) {
    var variantMap = all[name];
    Object.keys(variantMap).forEach(function (v) {
      var pts = variantMap[v];
      if (!pts || !pts.length) return;
      var last = pts.slice().sort(function (a, b) { return a.x - b.x; })[pts.length - 1];
      variants[v] = true;
      (rows[name] = rows[name] || {})[v] = last.y;
    });
  });
  var vlist = Object.keys(variants).sort();
  var html = "<table><tr><th>metric</th>" + vlist.map(function (v) {
    var color = VARIANT_COLOR[v] || "";
    return "<th" + (color ? " style=\"color:" + color + "\"" : "") + ">" + v.toUpperCase() + "</th>";
  }).join("") + "</tr>";
  Object.keys(rows).sort().forEach(function (name) {
    html += "<tr><td>" + name + "</td>" + vlist.map(function (v) { return "<td>" + (rows[name][v] != null ? rows[name][v] : "—") + "</td>"; }).join("") + "</tr>";
  });
  html += "</table>";
  document.getElementById("variants").innerHTML = html;
}

boot();

// Renders three views from github-action-benchmark BENCHMARK_DATA objects.
// app.js owns all data loading so there is no dependency on script-tag
// onload/onerror ordering. __SIZE__ / __SPEED__ are the two suites
// (smaller-better / bigger-better).

window.__SIZE__ = null;
window.__SPEED__ = null;

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
  // -> { metricName: [ {x: date, y: value, commit} ] }
  var out = {};
  if (!data || !data.entries) return out;
  Object.keys(data.entries).forEach(function (suite) {
    data.entries[suite].forEach(function (run) {
      run.benches.forEach(function (b) {
        (out[b.name] = out[b.name] || []).push({ x: run.date, y: b.value, commit: run.commit });
      });
    });
  });
  return out;
}

function lineCard(parent, title, points, unit) {
  var card = document.createElement("div"); card.className = "card";
  var cv = document.createElement("canvas"); card.appendChild(cv); parent.appendChild(card);
  new Chart(cv, {
    type: "line",
    data: { datasets: [{ label: title + " (" + unit + ")", data: points, tension: 0.2, pointRadius: 3 }] },
    options: { parsing: false, scales: { x: { type: "linear", ticks: { callback: function (v) { return new Date(v).toISOString().slice(0, 10); } } } },
               plugins: { legend: { display: true }, tooltip: { callbacks: { title: function (it) { return new Date(it[0].parsed.x).toISOString().slice(0, 10); } } } } }
  });
}

function render() {
  var size = seriesByName(window.__SIZE__), speed = seriesByName(window.__SPEED__);
  var all = Object.assign({}, size, speed);
  var trends = document.getElementById("trends");
  Object.keys(all).sort().forEach(function (name) {
    var unit = name.indexOf("Fmax") >= 0 ? "MHz" : (name.indexOf("area") >= 0 ? "um2" : "");
    lineCard(trends, name, all[name].slice().sort(function (a, b) { return a.x - b.x; }), unit);
  });
  renderPerBlock();
  renderVariants(all);
}

function latestBenches(data) {
  // newest run across the suite -> {name: bench}
  var best = null;
  if (data && data.entries) Object.keys(data.entries).forEach(function (s) {
    data.entries[s].forEach(function (run) { if (!best || run.date > best.date) best = run; });
  });
  var map = {}; if (best) best.benches.forEach(function (b) { map[b.name] = b; });
  return map;
}

function renderPerBlock() {
  var latest = latestBenches(window.__SIZE__);
  var blocks = ["decode", "datapath", "mult", "register_file"];
  var vals = blocks.map(function (b) { var k = "asic-nangate45 · " + b + "/area"; return latest[k] ? latest[k].value : 0; });
  new Chart(document.getElementById("perblock"), {
    type: "bar",
    data: { labels: blocks, datasets: [{ label: "area (um2)", data: vals }] },
    options: { plugins: { legend: { display: false } } }
  });
}

function renderVariants(all) {
  // Group latest value per (variant, metric). With one variant today this is a
  // single column; it grows as variants are added.
  var rows = {}, variants = {};
  Object.keys(all).forEach(function (name) {
    var pts = all[name]; if (!pts.length) return;
    var last = pts.slice().sort(function (a, b) { return a.x - b.x; })[pts.length - 1];
    var v = "current"; variants[v] = true;
    (rows[name] = rows[name] || {})[v] = last.y;
  });
  var vlist = Object.keys(variants);
  var html = "<table><tr><th>metric</th>" + vlist.map(function (v) { return "<th>" + v + "</th>"; }).join("") + "</tr>";
  Object.keys(rows).sort().forEach(function (name) {
    html += "<tr><td>" + name + "</td>" + vlist.map(function (v) { return "<td>" + (rows[name][v] != null ? rows[name][v] : "—") + "</td>"; }).join("") + "</tr>";
  });
  html += "</table>";
  document.getElementById("variants").innerHTML = html;
}

boot();

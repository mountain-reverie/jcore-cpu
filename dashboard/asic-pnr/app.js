// Renders the bench-asic-pnr history: one chart per metric (suffix-stripped),
// one line per variant. Reads window.BENCHMARK_DATA (github-action-benchmark).
(function () {
  var data = window.BENCHMARK_DATA;
  var host = document.getElementById("trends");
  if (!data || !data.entries) { document.getElementById("empty").hidden = false; return; }
  var COLORS = { J1: "#e6b800", J2: "#1f77b4", J4: "#2ca02c",
                 "J2+cache": "#9467bd", "J4+cache": "#d62728" };
  // Flatten all suites' entries (there is one pnr suite).
  var entries = [];
  Object.keys(data.entries).forEach(function (k) { entries = entries.concat(data.entries[k]); });
  entries.sort(function (a, b) { return a.commit.timestamp - b.commit.timestamp || a.date - b.date; });

  // group: metric (name without " [variant]" suffix) -> variant -> [{x,y}]
  var groups = {};
  entries.forEach(function (e, i) {
    (e.benches || []).forEach(function (b) {
      var m = b.name.match(/^(.*?)(?: \[([^\]]+)\])?$/);
      var base = m[1], variant = m[2] || "J2";
      groups[base] = groups[base] || {};
      (groups[base][variant] = groups[base][variant] || []).push({ x: i, y: b.value });
    });
  });

  Object.keys(groups).sort().forEach(function (base) {
    var card = document.createElement("div"); card.className = "card";
    var cv = document.createElement("canvas"); card.appendChild(cv); host.appendChild(card);
    var ds = Object.keys(groups[base]).sort().map(function (v) {
      return { label: v, data: groups[base][v], borderColor: COLORS[v] || "#888",
               backgroundColor: COLORS[v] || "#888", tension: 0.1, pointRadius: 2 };
    });
    new Chart(cv, { type: "line", data: { datasets: ds },
      options: { plugins: { title: { display: true, text: base } },
                 scales: { x: { type: "linear", title: { display: true, text: "run #" } } } } });
  });
})();

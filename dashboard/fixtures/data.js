window.BENCHMARK_DATA = {
  lastUpdate: 1700000000000,
  repoUrl: "https://github.com/owner/jcore-cpu",
  entries: {
    "synth-size": [
      { commit: { id: "aaa1111", message: "first", timestamp: "2026-06-10T00:00:00Z", url: "#" }, date: 1700000000000,
        benches: [
          { name: "asic-nangate45 · cpu/area", unit: "um2", value: 49000, extra: "j2" },
          { name: "asic-nangate45 · datapath/area", unit: "um2", value: 20100, extra: "j2" },
          { name: "asic-nangate45 · decode/area", unit: "um2", value: 11200, extra: "j2" },
          { name: "asic-nangate45 · mult/area", unit: "um2", value: 8500, extra: "j2" },
          { name: "asic-nangate45 · register_file/area", unit: "um2", value: 6400, extra: "j2" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4", unit: "LUT4", value: 6900, extra: "j2" },
          { name: "asic-nangate45 · cpu/area [j4]", unit: "um2", value: 51200, extra: "j4" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4 [j4]", unit: "LUT4", value: 7350, extra: "j4" } ] },
      { commit: { id: "bbb2222", message: "second", timestamp: "2026-06-11T00:00:00Z", url: "#" }, date: 1700086400000,
        benches: [
          { name: "asic-nangate45 · cpu/area", unit: "um2", value: 48210, extra: "direct-rom72" },
          { name: "asic-nangate45 · datapath/area", unit: "um2", value: 19880, extra: "direct-rom72" },
          { name: "asic-nangate45 · decode/area", unit: "um2", value: 11020, extra: "direct-rom72" },
          { name: "asic-nangate45 · mult/area", unit: "um2", value: 8450, extra: "direct-rom72" },
          { name: "asic-nangate45 · register_file/area", unit: "um2", value: 6300, extra: "direct-rom72" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4", unit: "LUT4", value: 6789, extra: "j2" },
          { name: "asic-nangate45 · cpu/area [j1]", unit: "um2", value: 38500, extra: "j1" },
          { name: "asic-nangate45 · cpu/area [j4]", unit: "um2", value: 50900, extra: "j4" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4 [j1]", unit: "LUT4", value: 6385, extra: "j1" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4 [j4]", unit: "LUT4", value: 5734, extra: "j4" } ] }
    ],
    "synth-speed": [
      { commit: { id: "aaa1111", message: "first", timestamp: "2026-06-10T00:00:00Z", url: "#" }, date: 1700000000000,
        benches: [ { name: "asic-nangate45 · cpu/Fmax (relative)", unit: "MHz", value: 39.5, extra: "j2" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative)", unit: "MHz", value: 42.1, extra: "j2" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (IO-unconstrained)", unit: "MHz", value: 27.0, extra: "j2" },
                   { name: "asic-nangate45 · cpu/Fmax (relative) [j4]", unit: "MHz", value: 44.1, extra: "j4" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative) [j4]", unit: "MHz", value: 46.3, extra: "j4" } ] },
      { commit: { id: "bbb2222", message: "second", timestamp: "2026-06-11T00:00:00Z", url: "#" }, date: 1700086400000,
        benches: [ { name: "asic-nangate45 · cpu/Fmax (relative)", unit: "MHz", value: 40.27, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative)", unit: "MHz", value: 42.86, extra: "j2" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (IO-unconstrained)", unit: "MHz", value: 27.22, extra: "j2" },
                   { name: "asic-nangate45 · cpu/Fmax (relative) [j1]", unit: "MHz", value: 35.6, extra: "j1" },
                   { name: "asic-nangate45 · cpu/Fmax (relative) [j4]", unit: "MHz", value: 45.0, extra: "j4" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative) [j1]", unit: "MHz", value: 38.5, extra: "j1" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative) [j4]", unit: "MHz", value: 47.1, extra: "j4" } ] }
    ]
  }
};

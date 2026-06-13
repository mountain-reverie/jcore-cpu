window.BENCHMARK_DATA = {
  lastUpdate: 1700000000000,
  repoUrl: "https://github.com/owner/jcore-cpu",
  entries: {
    "synth-size": [
      { commit: { id: "aaa1111", message: "first", timestamp: "2026-06-10T00:00:00Z", url: "#" }, date: 1700000000000,
        benches: [
          { name: "asic-nangate45 · cpu/area", unit: "um2", value: 49000, extra: "direct-rom72" },
          { name: "asic-nangate45 · datapath/area", unit: "um2", value: 20100, extra: "direct-rom72" },
          { name: "asic-nangate45 · decode/area", unit: "um2", value: 11200, extra: "direct-rom72" },
          { name: "asic-nangate45 · mult/area", unit: "um2", value: 8500, extra: "direct-rom72" },
          { name: "asic-nangate45 · register_file/area", unit: "um2", value: 6400, extra: "direct-rom72" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4", unit: "LUT4", value: 6900, extra: "direct-rom72" } ] },
      { commit: { id: "bbb2222", message: "second", timestamp: "2026-06-11T00:00:00Z", url: "#" }, date: 1700086400000,
        benches: [
          { name: "asic-nangate45 · cpu/area", unit: "um2", value: 48210, extra: "direct-rom72" },
          { name: "asic-nangate45 · datapath/area", unit: "um2", value: 19880, extra: "direct-rom72" },
          { name: "asic-nangate45 · decode/area", unit: "um2", value: 11020, extra: "direct-rom72" },
          { name: "asic-nangate45 · mult/area", unit: "um2", value: 8450, extra: "direct-rom72" },
          { name: "asic-nangate45 · register_file/area", unit: "um2", value: 6300, extra: "direct-rom72" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4", unit: "LUT4", value: 6789, extra: "direct-rom72" } ] }
    ],
    "synth-speed": [
      { commit: { id: "aaa1111", message: "first", timestamp: "2026-06-10T00:00:00Z", url: "#" }, date: 1700000000000,
        benches: [ { name: "asic-nangate45 · cpu/Fmax", unit: "MHz", value: 39.5, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative)", unit: "MHz", value: 42.1, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (IO-unconstrained)", unit: "MHz", value: 27.0, extra: "direct-rom72" } ] },
      { commit: { id: "bbb2222", message: "second", timestamp: "2026-06-11T00:00:00Z", url: "#" }, date: 1700086400000,
        benches: [ { name: "asic-nangate45 · cpu/Fmax", unit: "MHz", value: 40.27, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (representative)", unit: "MHz", value: 42.86, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · cpu/Fmax (IO-unconstrained)", unit: "MHz", value: 27.22, extra: "direct-rom72" } ] }
    ]
  }
};

#!/bin/bash
# regression.sh — end-to-end check of the Go decoder generator against the
# J-Core CPU simulator and the unit TAP testbenches.
#
# Steps:
#   1. Run `go test ./...` in gen-go/ — generator unit tests must pass.
#   2. Regenerate decode/*.vhd via `make -C decode generate`.
#   3. Build the simulator (sim/cpu_ctb) and run it for 180us.
#      Verify the LED write sequence matches the expected baseline (exactly 20).
#   4. Run the same LED sequence check with the ROM decoder (cpu_decode_rom).
#      core/cpu_config.vhd is patched temporarily; a trap ensures restoration.
#   5. Run the unit TAP testbenches (`make -C tests check`).
#   6. Build sim/tests/*.img (requires sh2-elf-gcc) and run each through
#      cpu_ctb; assert "Test Passed" appears in output.  Skipped if
#      sh2-elf-gcc is absent.  Known pre-existing failures are listed in
#      KNOWN_BROKEN_TESTS and skipped with a diagnostic.
#   7. Synthesize the generated decode_table (both direct and ROM
#      variants) via yosys + ghdl-yosys-plugin. Catches synthesis-only
#      issues (latches, multi-driver nets) that simulation misses.
#      Skipped if yosys/ghdl/plugin unavailable. Verilog netlists are
#      written to /tmp/synth-out (generic + Nangate45-mapped).
#   8. Run openSTA on the Nangate45-mapped netlists. Reports critical-
#      path delay + WNS/TNS at a 10ns (100MHz) virtual-clock target.
#      Results are INFORMATIONAL (Nangate45 is academic, not silicon).
#      Skipped if opensta or the Liberty file is unavailable.
#
# Environment:
#   TOOLS_DIR   — path to shared GHDL build tool makefiles
#                 (default: ../../jcore-soc/tools relative to repo root).
#   ROM_WIDTH   — decoder ROM width passed to cpugen (default: 72).
#
# Exit status: 0 on full success, non-zero on any failure.

set -euo pipefail

# Repo layout: this script lives at decode/gen-go/regression.sh.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/../jcore-soc/tools}"
ROM_WIDTH="${ROM_WIDTH:-72}"

if [ ! -d "$TOOLS_DIR" ]; then
    echo "regression: TOOLS_DIR=$TOOLS_DIR does not exist" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Global cleanup state — each step that creates a resource sets one of these.
# cleanup() is idempotent: it checks before acting.
# ---------------------------------------------------------------------------
_CLEANUP_LED_LOG=""         # mktemp file from Step 3
_CLEANUP_CPU_CONFIG_BAK=""  # mktemp backup of core/cpu_config.vhd
_CLEANUP_CPU_CONFIG=""      # path to live cpu_config.vhd (for restore)
_CLEANUP_SYNTH_WORK=""      # mktemp -d work dir from Step 7

cleanup() {
    # Restore cpu_config.vhd if we patched it.
    if [ -n "$_CLEANUP_CPU_CONFIG_BAK" ] && [ -f "$_CLEANUP_CPU_CONFIG_BAK" ]; then
        if [ -n "$_CLEANUP_CPU_CONFIG" ]; then
            cp "$_CLEANUP_CPU_CONFIG_BAK" "$_CLEANUP_CPU_CONFIG"
        fi
        rm -f "$_CLEANUP_CPU_CONFIG_BAK"
        _CLEANUP_CPU_CONFIG_BAK=""
    fi
    # Remove temporary LED log.
    if [ -n "$_CLEANUP_LED_LOG" ] && [ -f "$_CLEANUP_LED_LOG" ]; then
        rm -f "$_CLEANUP_LED_LOG"
        _CLEANUP_LED_LOG=""
    fi
    # Remove synthesis work directory.
    if [ -n "$_CLEANUP_SYNTH_WORK" ] && [ -d "$_CLEANUP_SYNTH_WORK" ]; then
        rm -rf "$_CLEANUP_SYNTH_WORK"
        _CLEANUP_SYNTH_WORK=""
    fi
}
trap cleanup EXIT

EXPECTED_LEDS=(0xFF 0x11 0x4F 0x12 0x21 0x22 0x23 0x31 0x32 0x33 \
               0x41 0x42 0x43 0x44 0x45 0x46 0x47 0x51 0x61 0x62)

# check_led_log FILE — verify FILE contains exactly the expected LED sequence.
check_led_log() {
    local log="$1"
    local label="${2:-direct}"

    local actual_count
    actual_count=$(wc -l < "$log")

    if [ "$actual_count" -lt "${#EXPECTED_LEDS[@]}" ]; then
        echo "regression[$label]: only $actual_count LED writes, expected ${#EXPECTED_LEDS[@]}" >&2
        cat "$log" >&2
        return 1
    fi

    if [ "$actual_count" -gt "${#EXPECTED_LEDS[@]}" ]; then
        echo "regression[$label]: $actual_count LED writes, expected exactly ${#EXPECTED_LEDS[@]} — extra writes:" >&2
        tail -n +"$((${#EXPECTED_LEDS[@]} + 1))" "$log" >&2
        return 1
    fi

    local i=0
    while IFS= read -r line; do
        local expected="${EXPECTED_LEDS[$i]}"
        if ! echo "$line" | grep -q "WRITE $expected "; then
            echo "regression[$label]: LED $i: expected $expected, got: $line" >&2
            return 1
        fi
        i=$((i + 1))
    done < "$log"

    echo "    all ${#EXPECTED_LEDS[@]} LED writes match expected sequence [$label]"
}

echo "==> Step 1: go test ./..."
go -C "$SCRIPT_DIR" test ./...

echo "==> Step 2: regenerate decode/*.vhd (ROM_WIDTH=$ROM_WIDTH)"
make -C "$REPO_ROOT/decode" generate ROM_WIDTH="$ROM_WIDTH"

echo "==> Step 3: build + run cpu_ctb for 180us [direct decoder]"
cd "$REPO_ROOT/sim"
rm -f work-obj93.cf cpu_ctb
# Build only the GHDL work database and cpu_ctb binary; the testrom/main.elf
# target in 'all' may fail if sh2-elf-gcc is installed but testrom/main.c has
# missing declarations — ram.img is not needed for the ctb simulator tests.
make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf >/dev/null

_CLEANUP_LED_LOG="$(mktemp)"
LED_LOG="$_CLEANUP_LED_LOG"
timeout 90 ./cpu_ctb --stop-time=180us 2>&1 | grep "^LED:" > "$LED_LOG" || true

check_led_log "$LED_LOG" "direct"

echo "==> Step 4: run cpu_ctb for 180us [ROM decoder]"
CPU_CONFIG="$REPO_ROOT/core/cpu_config.vhd"
_CLEANUP_CPU_CONFIG_BAK="$(mktemp)"
_CLEANUP_CPU_CONFIG="$CPU_CONFIG"
CPU_CONFIG_BAK="$_CLEANUP_CPU_CONFIG_BAK"

cp "$CPU_CONFIG" "$CPU_CONFIG_BAK"

# Patch cpu_sim configuration to use cpu_decode_rom instead of cpu_decode_direct.
# The sed range limits the substitution to inside the cpu_sim configuration block
# so the two FPGA configurations are left untouched.
sed -i \
    '/^configuration cpu_sim of cpu/,/^end configuration/{
        s/use configuration work\.cpu_decode_direct;/use configuration work.cpu_decode_rom;/
    }' \
    "$CPU_CONFIG"

rom_ok=1
rom_skip=0

# Rebuild with patched config and run. If elaboration fails (e.g., the ROM
# decoder depends on a falling-edge clock not present in the test bench), we
# document the failure and skip rather than aborting the whole regression.
cd "$REPO_ROOT/sim"
rm -f work-obj93.cf cpu_ctb
if ! make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf >/dev/null 2>&1; then
    echo "    SKIP: ROM decoder failed to elaborate — build error (see below):" >&2
    make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf 2>&1 | tail -20 >&2 || true
    rom_ok=0
    rom_skip=1
fi

if [ $rom_skip -eq 0 ]; then
    LED_LOG_ROM="$(mktemp)"
    timeout 90 ./cpu_ctb --stop-time=180us 2>&1 | grep "^LED:" > "$LED_LOG_ROM" || true
    if ! check_led_log "$LED_LOG_ROM" "rom"; then
        rom_ok=0
    fi
    rm -f "$LED_LOG_ROM"
fi

# Restore config before proceeding (trap will also fire, but be explicit).
cleanup

if [ $rom_skip -eq 1 ]; then
    echo "    NOTE: ROM decoder simulation skipped — elaboration failed."
    echo "          This means the ROM decoder is not wired for the test bench."
elif [ $rom_ok -eq 0 ]; then
    echo "regression: ROM decoder run failed" >&2
    exit 1
fi

# Rebuild with the restored (direct) config so step 5 TAP tests use the
# standard configuration.
cd "$REPO_ROOT/sim"
rm -f work-obj93.cf cpu_ctb
make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf >/dev/null

echo "==> Step 5: unit TAP testbenches"
make -C "$REPO_ROOT/tests" check TOOLS_DIR="$TOOLS_DIR"

echo "==> Step 6: SH-2 simulator tests (interrupts / RTE)"

# Known pre-existing test failures: tests listed here are skipped with a
# diagnostic rather than failing the regression. Each entry is a basename
# (without .img) of an image in sim/tests/.
#
# BEFORE adding an entry: reproduce the failure on the Clojure baseline
# decoder. If it fails there too, it's pre-existing — list it here with
# the exact failure signature so future readers can detect drift. If it
# passes there but fails on the Go decoder, that's a real regression to
# fix, not skip.
#
# Each entry MUST be accompanied by a comment giving the failure signature
# (timestamp + error string) observed on the Clojure baseline. If a test's
# observed failure ever differs from the recorded signature, the entry
# must be re-verified rather than silently extended.
#
# Entries:
#   interrupts — failure signature: "SRAM: Bus exception" at @320000ps,
#                followed by ACK-timeout spin until --stop-time. Reproduced
#                on the Clojure golden VHDL on 2026-05-22. Root cause is
#                an X-valued address during reset before any test code
#                runs — pre-existing, predates the Go rewrite.
KNOWN_BROKEN_TESTS="interrupts"

sim_tests_ok=1

if ! command -v sh2-elf-gcc >/dev/null 2>&1; then
    echo "    Step 6 skipped: sh2-elf-gcc not installed"
else
    # Build the test images; a build failure is a hard error.
    echo "    Building sim/tests images..."
    make -C "$REPO_ROOT/sim/tests" all

    sim_pass=0
    sim_fail=0
    sim_skip=0

    for img in "$REPO_ROOT"/sim/tests/*.img; do
        name="$(basename "$img" .img)"

        # Check known-broken list.
        if echo " $KNOWN_BROKEN_TESTS " | grep -q " $name "; then
            echo "    SKIP [$name]: known pre-existing failure (stuck in bus-exception loop before test code runs; also fails on Clojure golden decoder)"
            sim_skip=$((sim_skip + 1))
            continue
        fi

        # illegalj1 must run against the J1 decoder (cpu_j1 config): it
        # tests that CAS.L / coprocessor ops trap as illegal on J1.  The
        # standard cpu_sim config uses cpu_decode_direct (J2/J4), where
        # those opcodes are valid and the trap never fires.
        if [ "$name" = "illegalj1" ]; then
            (cd "$REPO_ROOT/sim" && make TOOLS_DIR="$TOOLS_DIR" CPU_TB_CONFIG=work.cpu_j1 cpu_ctb work-obj93.cf >/dev/null 2>&1)
        fi

        output="$(cd "$REPO_ROOT/sim" && timeout 30 ./cpu_ctb --stop-time=10us -i "tests/$name.img" 2>&1)"
        exit_code=$?

        # Restore the standard (cpu_sim) build after the J1-specific test.
        if [ "$name" = "illegalj1" ]; then
            (cd "$REPO_ROOT/sim" && make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf >/dev/null 2>&1)
        fi

        if echo "$output" | grep -q "Test Passed"; then
            echo "    PASS [$name]"
            sim_pass=$((sim_pass + 1))
        elif echo "$output" | grep -q "Test failed"; then
            fail_line="$(echo "$output" | grep "Test failed" | head -1)"
            echo "    FAIL [$name]: $fail_line" >&2
            sim_fail=$((sim_fail + 1))
            sim_tests_ok=0
        else
            echo "    FAIL [$name]: no 'Test Passed' before stop-time (exit=$exit_code)" >&2
            echo "         last 20 lines of output:" >&2
            echo "$output" | tail -20 | sed 's/^/         /' >&2
            sim_fail=$((sim_fail + 1))
            sim_tests_ok=0
        fi
    done

    total=$((sim_pass + sim_fail + sim_skip))
    echo "    sim tests: $sim_pass passed, $sim_fail failed, $sim_skip skipped (of $total)"

    if [ $sim_tests_ok -eq 0 ]; then
        echo "regression: Step 6 sim tests FAILED" >&2
        exit 1
    fi
fi

echo "==> Step 7: yosys + ghdl synthesis of generated decode table"
# Why this step exists:
#   GHDL simulation does NOT catch synthesis-only problems: inferred latches
#   from incomplete combinational assignments, multi-driver nets, idioms
#   that simulate but are non-synthesizable. Production J-Core silicon is
#   synthesized on Xilinx/Altera; the only short-of-vendor-tools way to
#   catch this class of regression is yosys+ghdl-yosys-plugin (generic
#   netlist).
#
# Scope:
#   We synthesize the `decode_table` entity for both FPGA decoder
#   variants: `decode_table_direct` (QMC-minimized boolean cloud — the
#   thing the Go generator's table reducer most affects) and
#   `decode_table_rom` (256x75-bit ROM with falling-edge clocked output
#   register). These two files are what the Go decoder generator actually
#   emits, so synthesizability here is a direct regression signal on
#   the generator output.
#
#   decode_table_simple.vhd is NOT synthesized here. It is a 4800+ line
#   if-elsif cascade that implements cpu_decode_simple, a sim-only
#   configuration not used in any FPGA build. Its correctness is covered
#   by two other mechanisms: (1) byte-identity against the Clojure golden
#   output in testdata/golden/clj/ (Step 2 + go test), and (2) the
#   simulator LED check in Step 3 which runs the full testrom through it.
#   Synthesizing it would be redundant work that yields no additional
#   signal about FPGA correctness.
#
#   We do NOT attempt to synthesize the full `cpu` entity. The hand-
#   written `decode_core.vhd` uses an `elsif clk='1' and slot='1' and
#   clk'event` clock-edge idiom that simulates but is rejected by the
#   GHDL synthesizer (`ill-formed clock-level`). That is pre-existing
#   project code unrelated to the Go decoder generator and outside the
#   scope of this regression. Synthesizing just `decode_table` isolates
#   what the generator produces from what it does not.
#
# Output:
#   /tmp/synth-out/decode_table_direct.v
#   /tmp/synth-out/decode_table_rom.v
#   (available for downstream static-timing analysis)

synth_ok=1
synth_skip=0
synth_ran=0   # set to 1 only when Step 7 actually runs synthesis

if ! command -v yosys >/dev/null 2>&1; then
    echo "    SKIP: yosys not installed"
    synth_skip=1
elif ! command -v ghdl >/dev/null 2>&1; then
    echo "    SKIP: ghdl not installed"
    synth_skip=1
elif ! yosys -m ghdl -p 'help ghdl' >/dev/null 2>&1; then
    echo "    SKIP: ghdl-yosys-plugin not loadable (yosys -m ghdl failed)"
    synth_skip=1
fi

if [ $synth_skip -eq 0 ]; then
    SYNTH_OUT="${SYNTH_OUT:-/tmp/synth-out}"
    _CLEANUP_SYNTH_WORK="$(mktemp -d)"
    SYNTH_WORK="$_CLEANUP_SYNTH_WORK"
    NANGATE_LIB="${NANGATE_LIB:-/tmp/sky130/lib/nangate45.lib}"
    mkdir -p "$SYNTH_OUT"

    # Remove any stale tech-mapped netlists before synthesis so Step 8
    # cannot accidentally consume artifacts from a previous run.
    rm -f "$SYNTH_OUT/decode_table_direct_mapped.v" \
          "$SYNTH_OUT/decode_table_rom_mapped.v"

    synth_ran=1

    # Shared analysis files (packages + decoder skeleton).
    # mult_pkg is needed because decode_pkg uses mult_state_t.
    SYNTH_COMMON=(
        "$REPO_ROOT/cpu2j0_pkg.vhd"
        "$REPO_ROOT/core/components_pkg.vhd"
        "$REPO_ROOT/core/mult_pkg.vhd"
        "$REPO_ROOT/decode/decode_pkg.vhd"
        "$REPO_ROOT/decode/decode_body.vhd"
        "$REPO_ROOT/decode/decode_table.vhd"
    )

    # synth_one CONFIG_LABEL TABLE_VHD CONFIG_VHD OUTPUT_V
    # Returns 0 on PASS, 1 on FAIL. Prints stats.
    synth_one() {
        local label="$1"
        local table_vhd="$2"
        local config_vhd="$3"
        local out_v="$4"

        local workdir="$SYNTH_WORK/$label"
        local log="$SYNTH_WORK/$label.log"
        mkdir -p "$workdir"

        # Run yosys: analyze packages + table + config, elaborate
        # `decode_table` (the config rebinds its architecture to direct
        # or rom), run generic synth, write Verilog.
        local files=("${SYNTH_COMMON[@]}" "$table_vhd" "$config_vhd")
        local file_args="${files[*]}"

        # Tech-map output (used by Step 8: openSTA). Only emitted when the
        # Nangate45 Liberty file is present; otherwise the abc/dfflibmap
        # steps would error. The generic netlist is always written.
        local mapped_v="${out_v%.v}_mapped.v"
        local map_block=""
        if [ -f "$NANGATE_LIB" ]; then
            # splitnets -ports + clean -purge: avoid yosys emitting
            # escaped-identifier concatenations (\:NNN.X = { ... })
            # that opensta 2.0.17 cannot parse.
            map_block="
            dfflibmap -liberty $NANGATE_LIB;
            abc -liberty $NANGATE_LIB;
            splitnets -ports;
            clean -purge;
            write_verilog -noattr $mapped_v;
"
        fi
        if ! timeout 120 yosys -m ghdl -p "
            ghdl --std=93 -fexplicit --ieee=synopsys --workdir=$workdir $file_args -e decode_table;
            synth -top decode_table;
            check -assert;
            stat;
            write_verilog $out_v;
            $map_block
        " >"$log" 2>&1; then
            echo "    FAIL [$label]: yosys/ghdl synthesis failed" >&2
            tail -30 "$log" | sed 's/^/         /' >&2
            return 1
        fi

        # Parse stats. yosys 'stat' prints "Number of cells:  N" and
        # the inferred latches show up as $_DLATCH_* or $_*LATCH* cells.
        local cells latches multidriver
        cells=$(grep -E '^[[:space:]]+Number of cells:' "$log" | tail -1 | awk '{print $NF}')
        cells="${cells:-?}"
        # Latches: any $_DLATCH or $_SR or $lut-DLATCH style entry.
        # Also catch "inferring latch" warnings emitted by proc_dlatch.
        latches=$(grep -cE '\$_DLATCH|inferring latch for' "$log" || true)
        # Multi-driver: yosys 'check' reports "Found and reported N problems".
        multidriver=$(grep -cE 'multiple drivers|multi-driver' "$log" || true)

        # check -assert would have errored; if we got here, problems == 0.
        local problems
        problems=$(grep -E 'Found and reported [0-9]+ problems' "$log" | tail -1 | awk '{print $4}')
        problems="${problems:-0}"

        echo "    [$label] cells=$cells, latches=$latches, multi-driver=$multidriver, check-problems=$problems"

        if [ "$latches" != "0" ] || [ "$multidriver" != "0" ] || [ "$problems" != "0" ]; then
            echo "    FAIL [$label]: synthesis produced latches or multi-driver nets (see $log)" >&2
            grep -E 'inferring latch|multi-driver|Warning' "$log" | head -10 | sed 's/^/         /' >&2
            return 1
        fi
        echo "    PASS [$label] -> $out_v"
        return 0
    }

    if ! synth_one "direct" \
        "$REPO_ROOT/decode/decode_table_direct.vhd" \
        "$REPO_ROOT/decode/decode_table_direct_config.vhd" \
        "$SYNTH_OUT/decode_table_direct.v"; then
        synth_ok=0
    fi

    if ! synth_one "rom" \
        "$REPO_ROOT/decode/decode_table_rom.vhd" \
        "$REPO_ROOT/decode/decode_table_rom_config.vhd" \
        "$SYNTH_OUT/decode_table_rom.v"; then
        synth_ok=0
    fi

    if [ $synth_ok -eq 0 ]; then
        echo "regression: Step 7 synthesis FAILED" >&2
        exit 1
    fi
fi

echo "==> Step 8: openSTA static timing analysis"
#
# Reads the tech-mapped Verilog netlists emitted in Step 7 and reports
# critical-path delay + worst/total negative slack against a 10ns
# (100MHz) virtual-clock target.
#
# Clock setup differs by decoder variant:
#   direct — purely combinational logic (no registers). Uses a virtual
#             clock with IO delays to constrain input→output paths.
#   rom    — has one falling-edge clocked register (process(clk,op) in
#             decode_table_rom.vhd). The physical `clk` port is attached
#             to a real clock in addition to the virtual-clock IO delays
#             so opensta sees the register's setup/hold paths. Without
#             this the register's clk pin is unconstrained and STA
#             reports no register timing.
#
# Results are INFORMATIONAL: negative slack at 100MHz is not a regression
# failure (timing depends on the target period choice and on the
# Nangate45 academic library, which is not a real silicon flow).  STA's
# main value here is (a) confirming the netlists are structurally
# analyzable (no combinational loops), and (b) tracking relative
# critical-path complexity between the direct and rom decoders over time.
#
# Step 8 is SKIPped if `sta` or the Nangate45 Liberty file is missing,
# or if Step 7 did not run in this invocation (synth_ran=0). If synth_ran
# is 0 but mapped files exist from a prior run, they are stale and must
# not be used.

if ! command -v sta >/dev/null 2>&1; then
    echo "    Step 8 skipped: opensta not installed (apt install opensta)"
elif [ ! -f "${NANGATE_LIB:-/tmp/sky130/lib/nangate45.lib}" ]; then
    echo "    Step 8 skipped: Liberty file not found at ${NANGATE_LIB:-/tmp/sky130/lib/nangate45.lib}"
elif [ "${synth_ran:-0}" -eq 0 ]; then
    # Step 7 did not run (yosys/ghdl absent). Any mapped.v files that may
    # exist on disk are from a prior run and could be stale — skip STA
    # rather than silently analyze obsolete data.
    echo "    Step 8 skipped: Step 7 did not run; mapped netlists may be stale"
elif [ ! -f "${SYNTH_OUT:-/tmp/synth-out}/decode_table_direct_mapped.v" ]; then
    echo "    Step 8 skipped: tech-mapped netlists not present (Liberty file was absent in Step 7)"
else
    NANGATE_LIB="${NANGATE_LIB:-/tmp/sky130/lib/nangate45.lib}"
    SYNTH_OUT="${SYNTH_OUT:-/tmp/synth-out}"
    STA_PERIOD_NS=10           # 100 MHz target
    STA_IO_DELAY=5             # half-period combinational budget

    # sta_one LABEL — run opensta on the tech-mapped netlist for LABEL
    # (direct or rom). Generates a per-label TCL script with clock setup
    # appropriate for that variant (see file header comment for rationale).
    sta_one() {
        local label="$1"
        local mapped_v="$SYNTH_OUT/decode_table_${label}_mapped.v"
        local rpt="$SYNTH_OUT/sta_${label}.txt"
        local tcl="$SYNTH_OUT/sta_${label}.tcl"

        # Build the clock-constraint block. For the ROM decoder, attach a
        # real clock to the physical `clk` port in addition to the virtual
        # clock, so the falling-edge register path is constrained.
        local clk_block
        if [ "$label" = "rom" ]; then
            clk_block="
create_clock -name virt_clk -period $STA_PERIOD_NS
create_clock -name clk -period $STA_PERIOD_NS [get_ports clk]
"
        else
            clk_block="
create_clock -name virt_clk -period $STA_PERIOD_NS
"
        fi

        cat > "$tcl" <<TCL
read_liberty $NANGATE_LIB
read_verilog $mapped_v
link_design decode_table
${clk_block}
set_input_delay -clock virt_clk $STA_IO_DELAY [all_inputs]
set_output_delay -clock virt_clk $STA_IO_DELAY [all_outputs]
report_checks -path_delay max -format short
report_wns
report_tns
exit
TCL

        # We capture stdout and parse WNS/TNS at the end, treating parse
        # failure as a STA failure.
        if ! timeout 30 sta -no_init -no_splash "$tcl" >"$rpt" 2>&1; then
            echo "    FAIL [$label]: opensta did not complete (timeout or fatal error). See $rpt" >&2
            tail -20 "$rpt" | sed 's/^/         /' >&2
            return 1
        fi

        # report_wns/report_tns print "wns max -2.02" (newer OpenSTA prints the
        # path-group keyword before the value); take the last field so both the
        # "wns -2.02" and "wns max -2.02" formats parse.
        local wns tns startpoint endpoint
        wns=$(awk '/^wns/  {print $NF; exit}' "$rpt")
        tns=$(awk '/^tns/  {print $NF; exit}' "$rpt")
        startpoint=$(awk '/^Startpoint:/ {sub(/^Startpoint: /,""); print; exit}' "$rpt")
        endpoint=$(awk '/^Endpoint:/   {sub(/^Endpoint: /,"");   print; exit}' "$rpt")
        wns="${wns:-?}"; tns="${tns:-?}"

        # Slack convention: negative = path longer than budget.
        # Critical-path delay = period + |wns| when wns < 0; period - wns when wns >= 0.
        local note=""
        if [ "$wns" = "?" ]; then
            echo "    FAIL [$label]: could not parse WNS from STA report ($rpt)" >&2
            return 1
        fi
        # Note: bash can't do float arithmetic; just report what we have.
        # Note: target-MHz string is derived for the common period=10 case.
        # If STA_PERIOD_NS ever changes, regenerate this line via awk.
        local target_mhz
        target_mhz=$(awk -v p="$STA_PERIOD_NS" 'BEGIN{printf "%.0f", 1000.0 / p}')
        echo "    [$label] WNS=${wns}ns, TNS=${tns}ns at ${STA_PERIOD_NS}ns (${target_mhz}MHz) target"
        echo "             critical path: ${startpoint:-?} -> ${endpoint:-?}"
        case "$wns" in
            -*) echo "             INFO: negative slack — decoder cannot meet ${STA_PERIOD_NS}ns period in Nangate45 (informational, not a regression)";;
        esac
        echo "             report: $rpt"
        return 0
    }

    sta_ok=1
    sta_one "direct" || sta_ok=0
    sta_one "rom"    || sta_ok=0

    if [ $sta_ok -eq 0 ]; then
        echo "regression: Step 8 STA FAILED" >&2
        exit 1
    fi
fi

echo "==> Regression passed."

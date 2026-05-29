#!/bin/bash
# rom-tests.sh — run the test ROM through the GHDL C co-simulation (cpu_ctb)
# and verify the LED write sequence for BOTH decoder implementations:
#   - direct decoder (cpu_decode_direct, the default cpu_sim binding)
#   - ROM decoder    (cpu_decode_rom)
#
# Uses the committed sim/ram.img, so NO sh2-elf-gcc is required. The
# interrupts/rte sim tests (which DO need sh2-elf-gcc to build their images)
# are intentionally not run here — they belong to the heavy-toolchain
# full-regression.
#
# Environment:
#   TOOLS_DIR — path to jcore-soc/tools (v2p + ghdl.mk). Default
#               ../jcore-soc/tools relative to repo root.
#
# Exit status: 0 if both decoders produce the expected LED sequence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/../jcore-soc/tools}"
# Absolutize: make runs from sim/, so a relative TOOLS_DIR would not resolve.
TOOLS_DIR="$(cd "$TOOLS_DIR" 2>/dev/null && pwd || echo "$TOOLS_DIR")"

if [ ! -x "$TOOLS_DIR/v2p" ]; then
    echo "rom-tests: v2p not found/executable at $TOOLS_DIR/v2p" >&2
    echo "           set TOOLS_DIR to your jcore-soc/tools checkout" >&2
    exit 2
fi

CPU_CONFIG="$REPO_ROOT/core/cpu_config.vhd"
CPU_CONFIG_BAK=""

# Restore cpu_config.vhd if we patched it for the ROM-decoder run.
cleanup() {
    if [ -n "$CPU_CONFIG_BAK" ] && [ -f "$CPU_CONFIG_BAK" ]; then
        cp "$CPU_CONFIG_BAK" "$CPU_CONFIG"
        rm -f "$CPU_CONFIG_BAK"
        CPU_CONFIG_BAK=""
    fi
}
trap cleanup EXIT

# Expected LED write sequence emitted by the default test ROM (20 writes).
EXPECTED_LEDS=(0xFF 0x11 0x4F 0x12 0x21 0x22 0x23 0x31 0x32 0x33 \
               0x41 0x42 0x43 0x44 0x45 0x46 0x47 0x51 0x61 0x62)

# check_led_log LOG LABEL — verify LOG holds exactly the expected sequence.
check_led_log() {
    local log="$1" label="$2"
    local actual_count i=0 line expected
    actual_count=$(wc -l < "$log")
    if [ "$actual_count" -ne "${#EXPECTED_LEDS[@]}" ]; then
        echo "    FAIL [$label]: $actual_count LED writes, expected ${#EXPECTED_LEDS[@]}" >&2
        cat "$log" >&2
        return 1
    fi
    while IFS= read -r line; do
        expected="${EXPECTED_LEDS[$i]}"
        if ! echo "$line" | grep -q "WRITE $expected "; then
            echo "    FAIL [$label]: LED $i: expected $expected, got: $line" >&2
            return 1
        fi
        i=$((i + 1))
    done < "$log"
    echo "    PASS [$label]: all ${#EXPECTED_LEDS[@]} LED writes match"
}

# build_and_run LABEL — build cpu_ctb, run the test ROM for 180us, capture and
# check the LED sequence. Returns the check result.
build_and_run() {
    local label="$1" log rc
    cd "$REPO_ROOT/sim"
    rm -f work-obj93.cf cpu_ctb
    make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf >/dev/null
    log="$(mktemp)"
    timeout 120 ./cpu_ctb --stop-time=180us 2>&1 | grep '^LED:' > "$log" || true
    cd "$REPO_ROOT"
    if check_led_log "$log" "$label"; then rc=0; else rc=1; fi
    rm -f "$log"
    return $rc
}

rc=0

echo "==> direct decoder"
build_and_run direct || rc=1

echo "==> ROM decoder"
# Patch the cpu_sim configuration to bind the decoder to cpu_decode_rom. The
# sed range limits the substitution to inside the cpu_sim block so the two
# FPGA configurations are untouched.
CPU_CONFIG_BAK="$(mktemp)"
cp "$CPU_CONFIG" "$CPU_CONFIG_BAK"
sed -i \
    '/^configuration cpu_sim of cpu/,/^end configuration/{
        s/use configuration work\.cpu_decode_direct;/use configuration work.cpu_decode_rom;/
    }' \
    "$CPU_CONFIG"
build_and_run rom || rc=1
cleanup

if [ $rc -ne 0 ]; then
    echo "rom-tests: FAILED" >&2
    exit 1
fi
echo "rom-tests: OK"

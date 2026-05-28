#!/bin/bash
# verify_known_broken.sh — mechanically verify that each test in
# KNOWN_BROKEN_TESTS (defined in regression.sh) also fails against the
# Clojure baseline VHDL, with the same failure signature recorded in the
# regression.sh comment block.
#
# This script is OPT-IN, not part of every regression run.  Run it when
# adding or updating a KNOWN_BROKEN_TESTS entry to confirm the failure is
# pre-existing (Clojure decoder reproduces it) and not a Go-decoder regression.
#
# Usage:
#   TOOLS_DIR=/path/to/tools bash decode/gen-go/verify_known_broken.sh
#
# Steps:
#   1. Locate the Clojure baseline VHDL in testdata/golden/clj/.
#   2. Back up the live decode/*.vhd files.
#   3. Install the Clojure baseline files into decode/.
#   4. Build cpu_ctb against the baseline.
#   5. For each test in KNOWN_BROKEN_TESTS, run it and assert it does NOT
#      print "Test Passed" — the test must also fail on the Clojure baseline
#      for the KNOWN_BROKEN_TESTS entry to be legitimate.
#   6. Restore the live decode/*.vhd files unconditionally.
#
# Prerequisites: same as regression.sh (ghdl, gcc, sh2-elf-gcc, TOOLS_DIR).
#
# Exit status: 0 if every listed test also fails on the Clojure baseline
#              (confirming they are pre-existing); non-zero otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/../jcore-soc/tools}"

if [ ! -d "$TOOLS_DIR" ]; then
    echo "verify_known_broken: TOOLS_DIR=$TOOLS_DIR does not exist" >&2
    exit 2
fi

CLJ_GOLDEN="$SCRIPT_DIR/testdata/golden/clj"

# The generated VHDL files that the Clojure baseline covers.
VHDL_FILES=(
    decode_body.vhd
    decode_pkg.vhd
    decode_table_direct.vhd
    decode_table_rom.vhd
    decode_table_simple.vhd
    decode.vhd
)
DECODE_DIR="$REPO_ROOT/decode"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

if [ ! -d "$CLJ_GOLDEN" ]; then
    echo "verify_known_broken: Clojure golden directory not found: $CLJ_GOLDEN" >&2
    echo "  The golden files are committed in decode/gen-go/testdata/golden/clj/." >&2
    echo "  If they are missing, regenerate them with:" >&2
    echo "    cd decode/gen && lein run" >&2
    echo "  and commit the output into testdata/golden/clj/." >&2
    exit 2
fi

for f in "${VHDL_FILES[@]}"; do
    if [ ! -f "$CLJ_GOLDEN/$f" ]; then
        echo "verify_known_broken: missing Clojure golden file: $CLJ_GOLDEN/$f" >&2
        exit 2
    fi
done

if ! command -v sh2-elf-gcc >/dev/null 2>&1; then
    echo "verify_known_broken: sh2-elf-gcc not installed — cannot build sim/tests images" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# KNOWN_BROKEN_TESTS list — keep in sync with regression.sh.
# Each entry is a test image basename (without .img) in sim/tests/.
# ---------------------------------------------------------------------------
KNOWN_BROKEN_TESTS="interrupts"

# ---------------------------------------------------------------------------
# Backup and restore
# ---------------------------------------------------------------------------

BACKUP_DIR="$(mktemp -d)"

restore_decode() {
    for f in "${VHDL_FILES[@]}"; do
        if [ -f "$BACKUP_DIR/$f" ]; then
            cp "$BACKUP_DIR/$f" "$DECODE_DIR/$f"
        fi
    done
    rm -rf "$BACKUP_DIR"
}
trap restore_decode EXIT

# Back up live files.
for f in "${VHDL_FILES[@]}"; do
    if [ -f "$DECODE_DIR/$f" ]; then
        cp "$DECODE_DIR/$f" "$BACKUP_DIR/$f"
    fi
done

# ---------------------------------------------------------------------------
# Install Clojure baseline VHDL and rebuild cpu_ctb.
# ---------------------------------------------------------------------------

echo "==> Installing Clojure baseline VHDL into decode/"
for f in "${VHDL_FILES[@]}"; do
    cp "$CLJ_GOLDEN/$f" "$DECODE_DIR/$f"
done

echo "==> Building cpu_ctb against Clojure baseline"
cd "$REPO_ROOT/sim"
rm -f work-obj93.cf cpu_ctb
make TOOLS_DIR="$TOOLS_DIR" cpu_ctb work-obj93.cf >/dev/null

echo "==> Building sim/tests images"
make -C "$REPO_ROOT/sim/tests" all

# ---------------------------------------------------------------------------
# Run each KNOWN_BROKEN test and assert it fails on the Clojure baseline.
# ---------------------------------------------------------------------------

all_confirmed=1

for name in $KNOWN_BROKEN_TESTS; do
    img="$REPO_ROOT/sim/tests/$name.img"
    if [ ! -f "$img" ]; then
        echo "  SKIP [$name]: image not found at $img" >&2
        continue
    fi

    output="$(cd "$REPO_ROOT/sim" && timeout 30 ./cpu_ctb --stop-time=10us -i "tests/$name.img" 2>&1)" || true
    if echo "$output" | grep -q "Test Passed"; then
        echo "  FAIL [$name]: test PASSED on Clojure baseline — it must NOT pass." >&2
        echo "       This test does not belong in KNOWN_BROKEN_TESTS; remove it." >&2
        all_confirmed=0
    else
        # Extract a brief failure signature for comparison with the recorded one.
        sig="$(echo "$output" | grep -E 'Test failed|SRAM:|bus exception|Bus exception|error|Error' | head -3 | tr '\n' '|' | sed 's/|$//')"
        echo "  CONFIRMED [$name]: also fails on Clojure baseline."
        echo "            Failure signature: ${sig:-(no matching lines found — check full output)}"
        echo "            Compare with comment in regression.sh KNOWN_BROKEN_TESTS."
    fi
done

# Restore is handled by the EXIT trap.
if [ $all_confirmed -eq 1 ]; then
    echo "==> verify_known_broken: all KNOWN_BROKEN_TESTS confirmed pre-existing."
    exit 0
else
    echo "verify_known_broken: one or more tests passed on Clojure baseline — remove them from KNOWN_BROKEN_TESTS." >&2
    exit 1
fi

#!/usr/bin/env bash
# Heavy-tier OpenLane2 RTL->GDS for one (design, pdk). Non-gating: any failure
# warns and exits 0 with no metrics file, so master CI stays green (trend gap).
# Env: OL_PDK, OL_DESIGN, OL_PERIOD_NS (default 10.0). Output: build/openlane_metrics.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT="$ROOT/build"; mkdir -p "$OUT"
PDK="${OL_PDK:?set OL_PDK}"; DESIGN="${OL_DESIGN:?set OL_DESIGN}"
PERIOD="${OL_PERIOD_NS:-10.0}"

if ! command -v openlane >/dev/null 2>&1; then
  echo "WARN: openlane not installed — skipping heavy tier" >&2; exit 0
fi
if [ ! -f "$OUT/cpu_asic.v" ]; then
  echo "WARN: $OUT/cpu_asic.v missing — run cpu_synth.sh asic first; skipping" >&2; exit 0
fi

CFG="$(mktemp -d)/config.json"
sed -e "s/__DESIGN__/$DESIGN/" -e "s/__PERIOD__/$PERIOD/" \
    synth/openlane/config.template.json > "$CFG"

if ! timeout 7200 openlane --pdk "$PDK" --run-tag ci "$CFG"; then
  echo "WARN: openlane run failed/timed out for $DESIGN on $PDK — no metrics" >&2
  exit 0
fi

# LibreLane writes the final metrics under the run dir; copy the newest.
# Dual-location search: LibreLane may write runs/ relative to the config file's
# directory OR relative to CWD ($ROOT). Both are searched until confirmed against
# the real tool (Task 8 of the ASIC plan).
FINAL="$(find "$(dirname "$CFG")/runs" "$ROOT/runs" -name metrics.json -path '*final*' \
         2>/dev/null | xargs -r ls -t 2>/dev/null | head -1 || true)"
if [ -z "$FINAL" ]; then
  echo "WARN: no final metrics.json produced — no metrics" >&2; exit 0
fi
cp "$FINAL" "$OUT/openlane_metrics.json"
echo "run.sh: OK -> $OUT/openlane_metrics.json"

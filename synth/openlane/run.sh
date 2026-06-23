#!/usr/bin/env bash
# Heavy-tier LibreLane RTL->GDS for one (design, pdk). Non-gating: any failure
# warns and exits 0 with no metrics file, so master CI stays green (trend gap).
# Env: OL_PDK, OL_DESIGN, OL_PERIOD_NS (default 10.0), OL_IMAGE (optional: run
# LibreLane via `docker run <image>` instead of a librelane binary on PATH — the
# LibreLane image is Nix-based and can't be a GHA job container, so CI runs it
# through docker on a plain runner). Output: build/openlane_metrics.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT="$ROOT/build"; mkdir -p "$OUT"
PDK="${OL_PDK:?set OL_PDK}"; DESIGN="${OL_DESIGN:?set OL_DESIGN}"
PERIOD="${OL_PERIOD_NS:-10.0}"
OL_IMAGE="${OL_IMAGE:-}"

# How to invoke LibreLane: a native binary if present, else via docker run with
# the repo bind-mounted at the same path and CWD=$ROOT (so runs/ lands under
# $ROOT and the bind-mounted config/netlist resolve identically inside/outside).
if command -v librelane >/dev/null 2>&1; then
  LIBRELANE=(librelane)
elif [ -n "$OL_IMAGE" ] && command -v docker >/dev/null 2>&1; then
  LIBRELANE=(docker run --rm -v "$ROOT:$ROOT" -w "$ROOT" "$OL_IMAGE" librelane)
else
  echo "WARN: no librelane binary and no OL_IMAGE/docker — skipping heavy tier" >&2; exit 0
fi
if [ ! -f "$OUT/cpu_asic.v" ]; then
  echo "WARN: $OUT/cpu_asic.v missing — run cpu_synth.sh asic first; skipping" >&2; exit 0
fi

# Config lives in build/ (inside the bind-mounted repo) alongside cpu_asic.v, so
# the template's `dir::cpu_asic.v` resolves relative to the config's directory.
CFG="$OUT/openlane_config.json"
sed -e "s/__DESIGN__/$DESIGN/" -e "s/__PERIOD__/$PERIOD/" \
    synth/openlane/config.template.json > "$CFG"

if ! timeout 7200 "${LIBRELANE[@]}" --pdk "$PDK" --run-tag ci "$CFG"; then
  echo "WARN: librelane run failed/timed out for $DESIGN on $PDK — no metrics" >&2
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

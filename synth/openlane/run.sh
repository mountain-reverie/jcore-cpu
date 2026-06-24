#!/usr/bin/env bash
# Heavy-tier LibreLane RTL->GDS for one (design, pdk). Non-gating: any failure
# warns and exits 0 with no metrics file, so master CI stays green (trend gap).
# Env: OL_PDK, OL_DESIGN, OL_PERIOD_NS (default 10.0), OL_TIMEOUT (seconds,
# default 7200), OL_IMAGE (optional: run LibreLane via `docker run <image>`
# instead of a librelane binary on PATH — the LibreLane image is Nix-based and
# can't be a GHA job container, so CI runs it through docker on a plain runner).
# Output: build/openlane_metrics.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
OUT="$ROOT/build"; mkdir -p "$OUT"
PDK="${OL_PDK:?set OL_PDK}"; DESIGN="${OL_DESIGN:?set OL_DESIGN}"
PERIOD="${OL_PERIOD_NS:-10.0}"
OL_IMAGE="${OL_IMAGE:-}"
OL_TIMEOUT="${OL_TIMEOUT:-7200}"

# Pick the invocation mode: a native binary if present, else docker run.
USE_DOCKER=0
if command -v librelane >/dev/null 2>&1; then
  USE_DOCKER=0
elif [ -n "$OL_IMAGE" ] && command -v docker >/dev/null 2>&1; then
  USE_DOCKER=1
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

# Run LibreLane under a HARD wall-clock cap. The previous `timeout NNN docker
# run ...` did NOT work: `timeout` signals the docker *client*, not the
# container, so OpenROAD's detail router kept going and the cell burned to
# GitHub's 6h job cap. For the docker path we name the container and a watchdog
# `docker kill`s it on expiry (which makes `docker run` return non-zero); for the
# native path plain `timeout --kill-after` is sufficient.
rc=0
if [ "$USE_DOCKER" -eq 1 ]; then
  CNAME="pnr-${DESIGN}-${PDK}-$$"
  docker rm -f "$CNAME" >/dev/null 2>&1 || true
  ( sleep "$OL_TIMEOUT"
    echo "WARN: ${OL_TIMEOUT}s wall-clock cap hit — killing container $CNAME" >&2
    docker kill "$CNAME" >/dev/null 2>&1 ) &
  WD=$!
  docker run --rm --name "$CNAME" -v "$ROOT:$ROOT" -w "$ROOT" \
    "$OL_IMAGE" librelane --pdk "$PDK" --run-tag ci "$CFG" || rc=$?
  kill "$WD" >/dev/null 2>&1 || true
  wait "$WD" 2>/dev/null || true
else
  timeout --kill-after=60 "$OL_TIMEOUT" librelane --pdk "$PDK" --run-tag ci "$CFG" || rc=$?
fi
if [ "$rc" -ne 0 ]; then
  echo "WARN: librelane failed/killed for $DESIGN on $PDK (rc=$rc) — no metrics" >&2
  exit 0
fi

# LibreLane writes the final metrics under the run dir; copy the newest.
# Dual-location search: LibreLane may write runs/ relative to the config file's
# directory OR relative to CWD ($ROOT). Both are searched until confirmed against
# the real tool (Phase B of the ASIC plan).
FINAL="$(find "$(dirname "$CFG")/runs" "$ROOT/runs" -name metrics.json -path '*final*' \
         2>/dev/null | xargs -r ls -t 2>/dev/null | head -1 || true)"
if [ -z "$FINAL" ]; then
  echo "WARN: no final metrics.json produced — no metrics" >&2; exit 0
fi
cp "$FINAL" "$OUT/openlane_metrics.json"
echo "run.sh: OK -> $OUT/openlane_metrics.json"

#!/usr/bin/env bash
# Run <cmd...> with an ISA-overlay decoder present, then ALWAYS restore base.
# Usage: synth/with_overlay_decoder.sh <sh2a|sh4> -- <cmd...>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
overlay="${1:?usage: with_overlay_decoder.sh <sh2a|sh4> -- <cmd...>}"; shift
[ "${1:-}" = "--" ] && shift
case "$overlay" in
  sh2a) gen="generate-j2a" ;;
  sh4)  gen="generate-j4"  ;;
  *) echo "with_overlay_decoder.sh: unknown overlay '$overlay' (want sh2a|sh4)" >&2; exit 2 ;;
esac
restore_base() {
  make -C "$ROOT/decode" generate >/dev/null 2>&1 || true
  git -C "$ROOT" diff --quiet -- decode/ 2>/dev/null \
    || echo "with_overlay_decoder.sh: WARNING base decoder not clean after restore" >&2
}
trap restore_base EXIT
echo "== with_overlay_decoder: $gen ==" >&2
make -C "$ROOT/decode" "$gen" >/dev/null
"$@"

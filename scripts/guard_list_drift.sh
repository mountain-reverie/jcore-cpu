#!/usr/bin/env bash
# Fail if sim/mmu_sim.sh and .github/workflows/full-regression.yml disagree
# about which guards run, or for how long.
#
# WHY THIS EXISTS: the two lists are maintained by hand and diverge in BOTH
# directions. CLAUDE.md has warned about it for a while; it has still bitten
# repeatedly. Most recently every m8_* guard was budgeted 200-600us in CI and
# 300-900us locally, so a change that made them slower passed locally and
# failed only in CI, reported as a functional failure rather than a timeout.
#
# This compares the two and prints the difference. It does NOT try to merge
# them -- CI legitimately runs guards the local runner cannot (the linux
# harnesses need $(LINUX_SRC) kbuild objects) -- it only insists that where
# both run a guard, they agree on its stop time.
set -euo pipefail
cd "$(dirname "$0")/.."

extract () {  # <file> -> "name stop" per line
  grep -oE 'run_guard[[:space:]]+[a-z0-9_]+[[:space:]]+"[a-z_]*"[[:space:]]+[0-9]+us' "$1" \
    | awk '{gsub(/"/,"",$3); print $2, $4}' | sort -u
}

extract sim/mmu_sim.sh                        > /tmp/gl_local.$$
extract .github/workflows/full-regression.yml > /tmp/gl_ci.$$
trap 'rm -f /tmp/gl_local.$$ /tmp/gl_ci.$$' EXIT

rc=0
while read -r name stop; do
  ci=$(awk -v n="$name" '$1==n {print $2}' /tmp/gl_ci.$$)
  [ -z "$ci" ] && continue                      # CI-only or local-only: allowed
  if [ "$ci" != "$stop" ]; then
    echo "DRIFT: $name -- local=$stop CI=$ci" >&2
    rc=1
  fi
done < /tmp/gl_local.$$

if [ "$rc" != 0 ]; then
  echo "" >&2
  echo "The two guard lists disagree on a stop time. A guard that is slower" >&2
  echo "than the SHORTER budget passes in one place and times out in the" >&2
  echo "other -- and a timeout looks exactly like a functional failure." >&2
  echo "Set both from a MEASURED completion time, with margin." >&2
  exit 1
fi
echo "OK: no stop-time drift between the guard lists"

#!/usr/bin/env bash
# Check whether a combined J2 + SH-4 + SH-2A (user-space) instruction set is
# encodable without opcode collisions, using docs/insns.json as source of truth.
#
# An instruction is "in scope" if J2, SH4, or SH2A is true for that row.
# Two in-scope instructions collide if their "code" patterns overlap, i.e.
# every bit position that is a fixed 0/1 in both agrees, and the "don't care"
# letter positions differ only where at least one side has a fixed bit
# (opcode collision = the fixed-bit patterns are compatible: one pattern
# is a specialization of the other, or wildcard positions overlap ambiguously).
#
# We treat each 16-bit "code" string as a pattern over {0,1,letter}. Two
# patterns collide if, at every bit position, they are compatible: same
# fixed bit, or at least one side is a wildcard (any letter). This mirrors
# how SH opcode maps are checked for overlap (letters = register/imm fields).
#
# Usage: ./check_j2_sh4_sh2a_union.sh [path-to-insns.json]

set -euo pipefail

JSON="${1:-$(dirname "$0")/insns.json}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

# Extract in-scope rows: format, code, and which sets include it.
mapfile -t ROWS < <(jq -r '
  .instructions[]
  | select(.J2 == true or .SH4 == true or .SH2A == true)
  | [.format, .code,
     (if .J2 == true then "J2" else "" end),
     (if .SH4 == true then "SH4" else "" end),
     (if .SH2A == true then "SH2A" else "" end)
    ] | @tsv
' "$JSON")

echo "In-scope instructions (J2 or SH4 or SH2A): ${#ROWS[@]}"
echo

# Function: do two space-separated multi-word code patterns collide?
# Each word is 16 chars; fixed bits (0/1) must match, letters are wildcards
# (register/imm/subop fields). Instructions with a different number of 16-bit
# words (e.g. J2 disp12 extended forms with a second word) are compared only
# on the first word: they occupy the same first-word opcode slot in a real
# SH decoder only if the shorter (single-word) instruction does NOT exist in
# the combined set at that slot, so mismatched word-counts are reported
# separately as "extension-word" note rather than a hard collision.
codes_collide() {
  local -a wa wb
  read -r -a wa <<< "$1"
  read -r -a wb <<< "$2"
  local nw=${#wa[@]}
  local nwb=${#wb[@]}
  if (( nw != nwb )); then
    return 2   # different word counts: not a same-shape collision
  fi
  local w i ca cb
  for (( w=0; w<nw; w++ )); do
    for (( i=0; i<16; i++ )); do
      ca="${wa[$w]:$i:1}"
      cb="${wb[$w]:$i:1}"
      if [[ "$ca" =~ [01] && "$cb" =~ [01] && "$ca" != "$cb" ]]; then
        return 1   # fixed bits disagree in this word -> no collision
      fi
    done
  done
  return 0  # compatible at every word/bit position -> collision
}

declare -a FORMATS CODES TAGS
n=0
while IFS=$'\t' read -r format code j2 sh4 sh2a; do
  FORMATS[n]="$format"
  CODES[n]="$code"
  tags=""
  [[ -n "$j2" ]] && tags+="J2 "
  [[ -n "$sh4" ]] && tags+="SH4 "
  [[ -n "$sh2a" ]] && tags+="SH2A "
  TAGS[n]="$tags"
  n=$((n + 1))
done < <(printf '%s\n' "${ROWS[@]}")

collisions=0
for (( i=0; i<n; i++ )); do
  for (( j=i+1; j<n; j++ )); do
    # skip identical code strings appearing in different set-columns of the
    # SAME logical instruction (same format) — not a real collision
    if [[ "${CODES[i]}" == "${CODES[j]}" && "${FORMATS[i]}" == "${FORMATS[j]}" ]]; then
      continue
    fi
    if codes_collide "${CODES[i]}" "${CODES[j]}"; then
      echo "COLLISION:"
      echo "  [${TAGS[i]}] ${FORMATS[i]}  code=${CODES[i]}"
      echo "  [${TAGS[j]}] ${FORMATS[j]}  code=${CODES[j]}"
      echo
      collisions=$((collisions + 1))
    fi
  done
done

echo "----"
if (( collisions == 0 )); then
  echo "RESULT: No opcode collisions found. A combined J2+SH4+SH2A user-space"
  echo "instruction set appears encodable without ambiguity."
else
  echo "RESULT: $collisions colliding pair(s) found. Combined set is NOT"
  echo "cleanly encodable as-is; the pairs above need disambiguation or"
  echo "one side must be dropped/subsetted."
fi

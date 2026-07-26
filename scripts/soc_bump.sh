#!/usr/bin/env bash
# soc_bump.sh -- drive jcore-soc submodule-bump PRs from jcore-cpu CI.
#
# Why this exists: jcore-soc pins jcore-cpu as a submodule, and between manual
# bumps the pin drifts arbitrarily far behind master (it reached +164 commits,
# which is how the ULX3S ECP5 Fmax regression at 569715f went unnoticed until
# it took a bisect to find). jcore-soc's board-synth.yml already benchmarks
# Fmax on every pull_request -- the only missing piece was a PR to measure.
# This script opens and retires those PRs.
#
# Subcommands:
#   sync <sha> <pr#|master>   create/refresh the bump branch + PR in jcore-soc
#   close <pr#>               close the draft bump PR for a closed jcore-cpu PR
#   comment <pr#> <soc-url>   post/update the sticky link-back on the cpu PR
#
# Flags:
#   --dry-run   print what would be pushed/created; make no remote changes
#
# Env:
#   SOC_PAT     token with contents:write + pull_requests:write on jcore-soc
#   SOC_REPO    default mountain-reverie/jcore-soc
#   CPU_REPO    default mountain-reverie/jcore-cpu
#
# Sourcing with SOC_BUMP_LIB_ONLY=1 defines the helpers without running main,
# which is what scripts/tests/soc_bump_test.sh does.
set -euo pipefail

SOC_REPO="${SOC_REPO:-mountain-reverie/jcore-soc}"
CPU_REPO="${CPU_REPO:-mountain-reverie/jcore-cpu}"
DRY_RUN="${DRY_RUN:-0}"

log() { printf 'soc_bump: %s\n' "$1" >&2; }
die() { log "$1"; exit 1; }

# bump_branch <pr#|master> -> the jcore-soc branch name for that source.
bump_branch() {
  local src="${1:-}"
  case "$src" in
    master) printf 'cpu-bump/master\n' ;;
    *[!0-9]* | '') log "bump_branch: expected a PR number or 'master', got '$src'"; exit 2 ;;
    *) printf 'cpu-bump/pr-%s\n' "$src" ;;
  esac
}

# bump_title <sha> <pr#|master>
bump_title() {
  local sha="$1" src="$2" short="${1:0:7}"
  if [ "$src" = master ]; then
    printf 'chore(cpu): bump jcore-cpu to %s (master)\n' "$short"
  else
    printf 'chore(cpu): bump jcore-cpu to %s (jcore-cpu#%s)\n' "$short" "$src"
  fi
}

# bump_body <sha> <pr#|master>
bump_body() {
  local sha="$1" src="$2"
  printf 'Automated submodule bump opened by jcore-cpu CI (`scripts/soc_bump.sh`).\n\n'
  printf 'Pins `components/cpu` to `%s` and commits the resulting `make soc_gen` output.\n\n' "$sha"
  if [ "$src" = master ]; then
    printf 'Source: `%s` **master** at `%s`.\n\n' "$CPU_REPO" "$sha"
    printf 'Left open for human review -- check the board-synth Fmax benchmark before merging.\n'
  else
    printf 'Source: %s#%s (still open).\n\n' "$CPU_REPO" "$src"
    printf '**Do not merge.** This draft exists so board-synth measures the SoC-level\n'
    printf 'impact (notably ULX3S Fmax) of that PR while it is still reviewable. It is\n'
    printf 'closed automatically when the jcore-cpu PR closes.\n'
  fi
}

comment_marker() { printf '<!-- soc-drift-bot -->\n'; }

# comment_body <soc_pr_url>
comment_body() {
  comment_marker
  printf 'SoC drift check: %s\n\n' "$1"
  printf 'That draft PR pins jcore-soc to this branch and runs `board-synth`, which\n'
  printf 'reports the ULX3S Fmax benchmark. It is informational and does not block\n'
  printf 'this PR. Updated in place on each push.\n'
}

main() {
  die "main not implemented yet"
}

if [ "${SOC_BUMP_LIB_ONLY:-0}" != 1 ]; then
  main "$@"
fi

#!/usr/bin/env bash
# TAP self-test for the pure helper functions in scripts/soc_bump.sh.
# Sources the script with SOC_BUMP_LIB_ONLY=1 so no side effects run.
# No network, no git writes -- safe to run anywhere.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# shellcheck source=/dev/null
SOC_BUMP_LIB_ONLY=1 . scripts/soc_bump.sh

count=0
fails=0

ok() { # ok <desc> <actual> <expected>
  count=$((count + 1))
  if [ "$2" = "$3" ]; then
    echo "ok $count - $1"
  else
    fails=$((fails + 1))
    echo "not ok $count - $1"
    echo "#   expected: $3"
    echo "#   actual:   $2"
  fi
}

ok_contains() { # ok_contains <desc> <haystack> <needle>
  count=$((count + 1))
  case "$2" in
    *"$3"*) echo "ok $count - $1" ;;
    *)
      fails=$((fails + 1))
      echo "not ok $count - $1"
      echo "#   expected to contain: $3"
      ;;
  esac
}

ok_exits() { # ok_exits <desc> <expected_code> <cmd...>
  count=$((count + 1))
  local desc="$1" expected="$2"
  shift 2
  local rc=0
  # Subshell is load-bearing: the helpers call `exit`, which would otherwise
  # terminate this test script rather than being caught here.
  ( "$@" ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$expected" ]; then
    echo "ok $count - $desc"
  else
    fails=$((fails + 1))
    echo "not ok $count - $desc"
    echo "#   expected exit $expected, got $rc"
  fi
}

# --- bump_branch ---------------------------------------------------------
ok "bump_branch numeric -> pr branch" "$(bump_branch 12)" "cpu-bump/pr-12"
ok "bump_branch master -> master branch" "$(bump_branch master)" "cpu-bump/master"
ok_exits "bump_branch rejects garbage" 2 bump_branch "not-a-pr"
ok_exits "bump_branch rejects empty" 2 bump_branch ""
ok_exits "bump_branch rejects leading zero" 2 bump_branch "012"

# --- bump_title ----------------------------------------------------------
ok_contains "title carries short sha" "$(bump_title 850fb17deadbeef 12)" "850fb17"
ok_contains "pr title marks it as a draft check" "$(bump_title 850fb17deadbeef 12)" "jcore-cpu#12"
ok_contains "master title says master" "$(bump_title 850fb17deadbeef master)" "master"

# --- bump_body -----------------------------------------------------------
body="$(bump_body 850fb17deadbeef 12)"
ok_contains "pr body links the cpu PR" "$body" "mountain-reverie/jcore-cpu#12"
ok_contains "pr body warns against merging" "$body" "Do not merge"
mbody="$(bump_body 850fb17deadbeef master)"
ok_contains "master body invites review" "$mbody" "review"
case "$mbody" in
  *"Do not merge"*)
    count=$((count + 1)); fails=$((fails + 1))
    echo "not ok $count - master body must NOT warn against merging" ;;
  *)
    count=$((count + 1)); echo "ok $count - master body must NOT warn against merging" ;;
esac

# --- comment -------------------------------------------------------------
ok "marker is exact" "$(comment_marker)" "<!-- soc-drift-bot -->"
cbody="$(comment_body https://github.com/mountain-reverie/jcore-soc/pull/99)"
ok "comment body starts with marker" "$(printf '%s\n' "$cbody" | head -1)" "<!-- soc-drift-bot -->"
ok_contains "comment body links the soc PR" "$cbody" "jcore-soc/pull/99"

# --- main dispatch -------------------------------------------------------
# main is reachable only via a subshell run of the script itself.
run_script() { DRY_RUN=1 bash scripts/soc_bump.sh "$@"; }

ok_exits "unknown subcommand exits 2" 2 run_script bogus
ok_exits "sync without args exits 2" 2 run_script sync
ok_exits "sync with one arg exits 2" 2 run_script sync deadbeef
ok_exits "close without args exits 2" 2 run_script close

echo "1..$count"
[ "$fails" -eq 0 ]

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
    0[0-9]*) log "bump_branch: expected a PR number or 'master', got '$src'"; exit 2 ;;
    *[!0-9]* | '') log "bump_branch: expected a PR number or 'master', got '$src'"; exit 2 ;;
    *) printf 'cpu-bump/pr-%s\n' "$src" ;;
  esac
}

# bump_title <sha> <pr#|master>
bump_title() {
  local src="$2" short="${1:0:7}"
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

# soc_pr_url <pr#|master> -> URL of the open bump PR, or empty.
soc_pr_url() {
  local branch
  branch="$(bump_branch "$1")"
  gh pr list --repo "$SOC_REPO" --head "$branch" --state open \
    --json url --jq '.[0].url // empty'
}

# cmd_close <pr#> -- retire the draft bump PR for a now-closed jcore-cpu PR.
cmd_close() {
  local src="$1" branch num
  branch="$(bump_branch "$src")"
  num="$(gh pr list --repo "$SOC_REPO" --head "$branch" --state open \
          --json number --jq '.[0].number // empty')"

  if [ -n "$num" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      log "DRY RUN: would close $SOC_REPO#$num and delete $branch"
      return 0
    fi

    log "closing $SOC_REPO#$num and deleting $branch"
    gh pr close "$num" --repo "$SOC_REPO" --delete-branch \
      --comment "jcore-cpu#${src} closed; retiring this drift check."
    return 0
  fi

  log "no open bump PR for $branch"

  # No PR (e.g. it was cancelled/interrupted between the sync job's
  # force-push and PR creation) can still leave the branch pushed to
  # jcore-soc with nothing to close it. Clean that up directly.
  if gh api "repos/${SOC_REPO}/branches/${branch}" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      log "DRY RUN: would delete orphaned branch $branch"
      return 0
    fi

    log "deleting orphaned branch $branch"
    gh api -X DELETE "repos/${SOC_REPO}/git/refs/heads/${branch}"
  else
    log "no remote branch $branch -- nothing to close"
  fi
}

# cmd_comment <pr#> <soc_pr_url> -- sticky link-back on the jcore-cpu PR.
# Edited in place, so a 20-push PR accumulates one comment rather than twenty.
cmd_comment() {
  local src="$1" url="$2" marker body existing
  marker="$(comment_marker)"
  body="$(comment_body "$url")"

  existing="$(gh api "repos/${CPU_REPO}/issues/${src}/comments" --paginate \
    --jq "map(select(.body | contains(\"${marker}\"))) | .[0].id // empty")"

  if [ "$DRY_RUN" = 1 ]; then
    if [ -n "$existing" ]; then
      log "DRY RUN: would edit comment $existing on ${CPU_REPO}#${src}"
    else
      log "DRY RUN: would create a comment on ${CPU_REPO}#${src}"
    fi
    printf '%s\n' "$body" >&2
    return 0
  fi

  if [ -n "$existing" ]; then
    log "updating sticky comment $existing on ${CPU_REPO}#${src}"
    gh api -X PATCH "repos/${CPU_REPO}/issues/comments/${existing}" \
      -f body="$body" --silent
  else
    log "creating sticky comment on ${CPU_REPO}#${src}"
    gh pr comment "$src" --repo "$CPU_REPO" --body "$body"
  fi
}

# cmd_sync <sha> <pr#|master>
cmd_sync() {
  local sha="$1" src="$2"
  local branch draft workdir askpass existing_url
  branch="$(bump_branch "$src")"
  # `[ x = y ] && draft=""` would return 1 for the master case and `set -e`
  # would kill the script, so this must be an if.
  if [ "$src" = master ]; then draft=""; else draft="--draft"; fi

  : "${SOC_PAT:?SOC_PAT must be set (DEPENDABOT_RECREATE_PAT)}"

  workdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  # Never let SOC_PAT touch argv or a git config file: a GIT_ASKPASS helper
  # reads it from the environment at run time instead. The helper and the
  # clone both live under $workdir, so the trap above cleans them up; the
  # only thing that ends up in .git/config is the token-free username@host
  # URL, which is not a secret.
  askpass="$workdir/askpass.sh"
  cat > "$askpass" <<'EOF'
#!/bin/sh
printf '%s\n' "$SOC_PAT"
EOF
  chmod 700 "$askpass"
  export GIT_ASKPASS="$askpass"
  export GIT_TERMINAL_PROMPT=0

  log "cloning $SOC_REPO"
  git clone --quiet --branch master \
    "https://x-access-token@github.com/${SOC_REPO}.git" "$workdir/soc"
  cd "$workdir/soc"

  git config user.name  "soc-drift-bot"
  git config user.email "soc-drift-bot@users.noreply.github.com"

  log "pinning components/cpu to $sha"
  git submodule update --init components/cpu
  git -C components/cpu fetch --quiet origin "$sha"
  git -C components/cpu checkout --quiet --detach FETCH_HEAD

  log "running make soc_gen"
  make soc_gen

  git add -A
  if git diff --cached --quiet; then
    log "submodule already at $sha and soc_gen is clean -- nothing to do"
    return 0
  fi

  git commit --quiet -m "$(bump_title "$sha" "$src")" \
    -m "Automated bump by jcore-cpu scripts/soc_bump.sh. Includes make soc_gen output."

  # No-op guard: if an existing bump branch already has this exact tree, a
  # force-push would only churn the PR and re-trigger a multi-hour synth run
  # for an identical result.
  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    git fetch --quiet origin "$branch"
    if [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse "origin/${branch}^{tree}")" ]; then
      log "tree identical to existing $branch -- skipping push"
      return 0
    fi
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "DRY RUN: would force-push $branch and ensure a PR exists"
    git --no-pager show --stat HEAD >&2
    return 0
  fi

  log "force-pushing $branch"
  git push --quiet --force origin "HEAD:refs/heads/$branch"

  # Plain assignment on its own line so a gh failure (rate limit, transient
  # auth error) trips set -e and is caught below, instead of a failed command
  # substitution silently vanishing inside `[ -n "$(...)" ]` and being
  # mistaken for "no PR is open".
  existing_url="$(soc_pr_url "$src")" \
    || die "could not determine whether a bump PR already exists for $branch -- aborting rather than risk opening a duplicate"
  if [ -n "$existing_url" ]; then
    log "PR already open for $branch -- force-push updated it in place"
    return 0
  fi

  log "opening PR for $branch"
  # shellcheck disable=SC2086
  gh pr create --repo "$SOC_REPO" --base master --head "$branch" \
    --title "$(bump_title "$sha" "$src")" \
    --body "$(bump_body "$sha" "$src")" $draft
}

main() {
  local args=()
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY_RUN=1 ;;
      *) args+=("$a") ;;
    esac
  done
  [ "${#args[@]}" -ge 1 ] || { log "usage: soc_bump.sh <sync|close|comment> ..."; exit 2; }

  local sub="${args[0]}"
  case "$sub" in
    sync)
      [ "${#args[@]}" -eq 3 ] || { log "usage: soc_bump.sh sync <sha> <pr#|master>"; exit 2; }
      cmd_sync "${args[1]}" "${args[2]}" ;;
    close)
      [ "${#args[@]}" -eq 2 ] || { log "usage: soc_bump.sh close <pr#>"; exit 2; }
      cmd_close "${args[1]}" ;;
    comment)
      [ "${#args[@]}" -eq 3 ] || { log "usage: soc_bump.sh comment <pr#> <soc-url>"; exit 2; }
      cmd_comment "${args[1]}" "${args[2]}" ;;
    *)
      log "unknown subcommand '$sub'"; exit 2 ;;
  esac
}

if [ "${SOC_BUMP_LIB_ONLY:-0}" != 1 ]; then
  main "$@"
fi

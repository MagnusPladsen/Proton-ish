#!/bin/sh
# shellcheck disable=SC2016
# Merges NotProton's main into a branch and opens a PR, or an issue when the merge conflicts.
# Usage: scripts/sync/notproton.sh   (run from any directory of the checkout)
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh
. scripts/sync/common.sh

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/NotProtonNot/NotProton.git}"
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch -q upstream main
git fetch -q origin main

if git merge-base --is-ancestor upstream/main origin/main; then
  sync_log "notproton: origin/main already has upstream/main"
  exit 0
fi

sha=$(git rev-parse --short=7 upstream/main)
branch="sync/notproton-$sha"
if branch_exists "$branch" || pr_exists "$branch" || issue_exists "NotProton $sha"; then
  sync_log "notproton: $sha is already in a PR or issue"
  exit 0
fi

commits=$(git log --oneline origin/main..upstream/main)
git_identity
git checkout -q -B "$branch" origin/main
if git merge --no-ff --no-edit -m "Merge NotProton $sha" upstream/main >/dev/null 2>&1; then
  git push -q -u origin "$branch"
  "$GH" pr create -R "$REPO" --base main --head "$branch" \
    --title "sync: merge NotProton $sha" --label upstream-sync --label notproton \
    --body "$(printf '## What\nMerges upstream NotProton `%s` into main. Clean merge.\n\n## Upstream commits\n```\n%s\n```\n\n## Before merging\n- CI must be green, including `brandcheck`.\n- Add a dated line under "Changes from upstream" in README.md if the change is user-visible.\n%s' "$sha" "$commits" "$(footer)")"
  sync_log "notproton: opened a PR for $sha"
else
  conflicts=$(git diff --name-only --diff-filter=U)
  git merge --abort
  git checkout -q origin/main
  git branch -q -D "$branch"
  "$GH" issue create -R "$REPO" --title "NotProton $sha does not merge cleanly" --label upstream-sync --label notproton \
    --body "$(printf '## Conflicts\n```\n%s\n```\n\n## Upstream commits\n```\n%s\n```\n\nMerge `upstream/main` by hand on a branch and open a PR.%s' "$conflicts" "$commits" "$(footer)")"
  sync_log "notproton: $sha conflicts, opened an issue"
fi

#!/bin/sh
# shellcheck disable=SC2016
# Shared by the upstream sync scripts. Sourced, not run.
# GH names the gh binary (tests stub it); REPO is this fork for gh calls.

GH="${GH:-gh}"
REPO="${REPO:-MagnusPladsen/Proton-ish}"

sync_log() { printf 'sync: %s\n' "$*"; }

# 0 when a branch of that name exists on origin
branch_exists() { git ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1; }

# 0 when an open upstream-sync issue mentions the text
issue_exists() {
  [ -n "$("$GH" issue list -R "$REPO" --label upstream-sync --state open --search "$1" --json number -q '.[0].number' 2>/dev/null)" ]
}

# 0 when an open PR comes from the branch
pr_exists() {
  [ -n "$("$GH" pr list -R "$REPO" --head "$1" --state open --json number -q '.[0].number' 2>/dev/null)" ]
}

# Bot commits carry the no-reply identity, never a work address
git_identity() {
  git config user.name "Proton-ish sync"
  git config user.email "93226629+MagnusPladsen@users.noreply.github.com"
}

footer() {
  printf '\n---\nOpened by the upstream-sync workflow. It never bumps `dylib/version.h`, so merging this does not publish a release.\n'
}

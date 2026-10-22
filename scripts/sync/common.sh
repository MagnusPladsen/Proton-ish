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

# 0 when an upstream-sync issue in any state mentions the text. A failed listing fails the job:
# guessing "none" would open a second issue
issue_ever_exists() {
  found=$("$GH" issue list -R "$REPO" --label upstream-sync --state all --search "$1" --json number -q '.[0].number') ||
    { echo "sync: cannot list issues for $1" >&2; exit 1; }
  [ -n "$found" ]
}

# 0 when a PR in any state, open, closed or merged, came from the branch
pr_ever_exists() {
  found=$("$GH" pr list -R "$REPO" --head "$1" --state all --json number -q '.[0].number') ||
    { echo "sync: cannot list PRs for $1" >&2; exit 1; }
  [ -n "$found" ]
}

# Copies the engine manifests HighballKit <version> ships into the directory
fetch_manifests() {   # version dir
  git clone -q --depth 1 --filter=blob:none --sparse --branch "v$1" "${HIGHBALL_REPO:-https://github.com/gauthierpiarrette/highball.git}" "$2.git"
  git -C "$2.git" sparse-checkout set spike/engines
  mkdir -p "$2"
  cp "$2.git"/spike/engines/*.json "$2/"
  rm -rf "$2.git"
}

# Bot commits carry the no-reply identity, never a work address
git_identity() {
  git config user.name "Proton-ish sync"
  git config user.email "93226629+MagnusPladsen@users.noreply.github.com"
}

# The version the next release gets: the current one while it has no tag yet (a bump still
# waiting to ship is reused), otherwise the next beta, or the next patch after 1.0
next_version() {   # current
  if ! git ls-remote --exit-code --tags origin "refs/tags/v$1" >/dev/null 2>&1; then
    printf '%s\n' "$1"
    return
  fi
  case "$1" in
    *-beta.*) printf '%s-beta.%s\n' "${1%%-beta.*}" "$(( ${1##*-beta.} + 1 ))" ;;
    *) printf '%s.%s\n' "${1%.*}" "$(( ${1##*.} + 1 ))" ;;
  esac
}

# Adds a dated line at the end of CHANGELOG.md's "Changes from upstream" list
changelog_line() {   # text
  awk -v line="- $(date +%Y-%m-%d): $1" '
    /^## Changes from upstream/ { section = 1 }
    section && /^## / && !/^## Changes from upstream/ { for (i = 1; i <= held; i++) print held_line[i]; print line; held = 0; section = 0 }
    section && /^$/ { held_line[++held] = $0; next }
    section { for (i = 1; i <= held; i++) print held_line[i]; held = 0 }
    { print }
    END { for (i = 1; i <= held; i++) print held_line[i]; if (section) print line }
  ' CHANGELOG.md > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md
}

# Commits the release bump on the current branch and prints the version: merging the PR then
# publishes it through the release workflow
bump_release() {   # changelog text
  current=$(sed -n 's/^#define NOTPROTON_VERSION "\(.*\)"/\1/p' dylib/version.h)
  version=$(next_version "$current")
  [ "$version" = "$current" ] || sed -i.bak "s/^#define NOTPROTON_VERSION \"$current\"/#define NOTPROTON_VERSION \"$version\"/" dylib/version.h
  rm -f dylib/version.h.bak
  changelog_line "$1"
  git add dylib/version.h CHANGELOG.md
  git commit -q -m "Release $version: $1

Co-Authored-By: Proton-ish sync <93226629+MagnusPladsen@users.noreply.github.com>"
  printf '%s\n' "$version"
}

# The PR merges itself once the required checks pass. Right after a push GitHub has not
# registered the new head's checks yet and refuses auto-merge, so it is asked again
enable_auto_merge() {   # branch
  tries=1
  until "$GH" pr merge --auto --merge -R "$REPO" "$1" >/dev/null; do
    [ "$tries" -lt 5 ] || { echo "sync: auto-merge for $1 refused $tries times" >&2; return 1; }
    tries=$((tries + 1))
    sleep "${AUTO_MERGE_WAIT:-15}"
  done
}

footer() {   # version
  printf '\n---\nOpened by the upstream-sync workflow. It bumps `dylib/version.h`, so merging this publishes %s; the PR merges itself once CI passes.\n' "$1"
}

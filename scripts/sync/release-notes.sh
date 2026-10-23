#!/bin/sh
# Prints the release notes for a release commit or tag: the CHANGELOG.md entries added since the
# release before it, without their dates. A sync PR's description, which lists the upstream
# commits, follows them; any other PR's description is written for its reviewers and stays out.
# Needs the history and tags fetched.
# Usage: scripts/sync/release-notes.sh [<commit or tag>]
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh disable=SC1091
. scripts/sync/common.sh

at=$(git rev-parse --verify "${1:-HEAD}^{commit}")
prev=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$at^" 2>/dev/null) || prev=""
# The first release has every entry: compare with the empty tree
[ -n "$prev" ] || prev=$(git hash-object -t tree /dev/null)

# An entry is "- YYYY-MM-DD: text", wrapped onto lines indented by two spaces
entries=$(git diff "$prev" "$at" -- CHANGELOG.md | awk '
  /^\+- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]: / { if (e != "") print e; e = "- " substr($0, 16); next }
  /^\+  +[^ ]/ && e != "" { sub(/^\+ +/, ""); e = e " " $0; next }
  { if (e != "") print e; e = "" }
  END { if (e != "") print e }')
[ -n "$entries" ] || entries=$(git log -1 --format=%s "$at")
printf '%s\n' "$entries"

sync_body=$("$GH" api "repos/$REPO/commits/$at/pulls" \
  -q '.[0] | select(any(.labels[]; .name == "upstream-sync")) | .body // empty' 2>/dev/null) || sync_body=""
# A sync PR ends with a footer for maintainers, below a rule; the notes stop there
[ -z "$sync_body" ] || printf '\n%s\n' "$sync_body" | sed '/^---$/,$d'

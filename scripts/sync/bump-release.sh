#!/bin/sh
# Bumps dylib/version.h to the next release and adds the dated README line, as one commit on the
# current branch. For merges done by hand; the sync scripts do the same on their own.
# Usage: scripts/sync/bump-release.sh "NotProton 2791679 merged"
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh disable=SC1091
. scripts/sync/common.sh

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: scripts/sync/bump-release.sh \"<changelog text>\"" >&2; exit 2; }
# Your own identity when you have one; the bot's where nothing is configured (CI)
[ -n "$(git config user.email)" ] || git_identity
# next_version asks origin for the tag directly; a local tag fetch can fail on a re-tagged
# release and would end the script silently
version=$(bump_release "$1")
sync_log "release $version bumped on $(git branch --show-current); merging the PR publishes it"

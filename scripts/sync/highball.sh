#!/bin/sh
# shellcheck disable=SC2016
# Bumps the HighballKit pin to Highball's latest release and refreshes the highball-db snapshot,
# in one PR when both changed. Needs swift (package resolve) and the refresh script's network access.
# Usage: scripts/sync/highball.sh
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh disable=SC1091
. scripts/sync/common.sh

SWIFT="${SWIFT:-swift}"
REFRESH_DB="${REFRESH_DB:-scripts/refresh-highball-db.sh}"

latest=$("$GH" release list -R gauthierpiarrette/highball --exclude-pre-releases --limit 1 --json tagName -q '.[0].tagName')
latest=${latest#v}
pinned=$(sed -n 's/.*gauthierpiarrette\/highball", exact: "\([^"]*\)".*/\1/p' app/Package.swift)
[ -n "$pinned" ] || { echo "sync: no HighballKit pin found in app/Package.swift" >&2; exit 1; }
newer_kit=""
if [ -n "$latest" ] && [ "$latest" != "$pinned" ] && [ "$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)" = "$latest" ]; then
  newer_kit="$latest"
fi

db_head=$("$GH" api repos/gauthierpiarrette/highball-db/commits/main -q .sha)
db_pinned=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["source"]["commit"])' third_party/highball-db/highball-db.json)
newer_db=""
[ -n "$db_head" ] && [ "$db_head" != "$db_pinned" ] && newer_db="$db_head"

if [ -z "$newer_kit" ] && [ -z "$newer_db" ]; then
  sync_log "highball: HighballKit $pinned and highball-db $(printf %.7s "$db_pinned") are current"
  exit 0
fi

branch="sync/highball"
[ -z "$newer_kit" ] || branch="$branch-$newer_kit"
[ -z "$newer_db" ] || branch="$branch-db-$(printf %.7s "$newer_db")"
if branch_exists "$branch" || pr_exists "$branch"; then
  sync_log "highball: $branch already has a PR"
  exit 0
fi

git fetch -q origin main
git_identity
git checkout -q -B "$branch" origin/main
notes=""
if [ -n "$newer_kit" ]; then
  sed -i.bak "s/gauthierpiarrette\/highball\", exact: \"$pinned\"/gauthierpiarrette\/highball\", exact: \"$newer_kit\"/" app/Package.swift
  sed -i.bak "s/highballKitVersion = \"$pinned\"/highballKitVersion = \"$newer_kit\"/" app/Sources/HighballEnvCore/HighballEnvCore.swift
  rm -f app/Package.swift.bak app/Sources/HighballEnvCore/HighballEnvCore.swift.bak
  "$SWIFT" package --package-path app resolve >/dev/null
  git add app/Package.swift app/Package.resolved app/Sources/HighballEnvCore/HighballEnvCore.swift
  notes="$notes- HighballKit $pinned → $newer_kit: https://github.com/gauthierpiarrette/highball/releases/tag/v$newer_kit
"
fi
if [ -n "$newer_db" ]; then
  "$REFRESH_DB" "$newer_db" >/dev/null
  git add third_party/highball-db
  notes="$notes- highball-db $(printf %.7s "$db_pinned") → $(printf %.7s "$newer_db"): https://github.com/gauthierpiarrette/highball-db/compare/$db_pinned...$newer_db
"
fi
git commit -q -m "Sync Highball: ${newer_kit:+HighballKit $newer_kit}${newer_kit:+${newer_db:+, }}${newer_db:+highball-db $(printf %.7s "$newer_db")}

$notes
Co-Authored-By: Proton-ish sync <93226629+MagnusPladsen@users.noreply.github.com>"
git push -q -u origin "$branch"
"$GH" pr create -R "$REPO" --base main --head "$branch" \
  --title "sync: Highball ${newer_kit:+$newer_kit }${newer_db:+db $(printf %.7s "$newer_db")}" --label upstream-sync --label highball \
  --body "$(printf '## What\n%s\n## Before merging\n- CI green: a HighballKit bump can change the API `highball-env` builds against.\n- Read the Highball release notes for engine changes that need a new `SupportedRunner` entry.\n- Add a dated line under "Changes from upstream" in README.md.\n%s' "$notes" "$(footer)")"
sync_log "highball: opened a PR on $branch"

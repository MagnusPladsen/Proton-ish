#!/bin/sh
# shellcheck disable=SC2016
# Bumps the HighballKit pin to Highball's latest release, refreshes the highball-db snapshot and pins
# engine revisions on a Wine build Proton-ish supports, in one PR. Needs swift (package resolve) and
# network access for the database refresh and Highball's engine manifests.
# Usage: scripts/sync/highball.sh
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh disable=SC1091
. scripts/sync/common.sh

SWIFT="${SWIFT:-swift}"
REFRESH_DB="${REFRESH_DB:-scripts/refresh-highball-db.sh}"
engines_text=""

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

# The engine manifests of the HighballKit the branch ends up with: revisions it brings on a Wine
# build Proton-ish supports are pinned on every run, with or without a HighballKit bump
if [ -z "${HIGHBALL_MANIFESTS:-}" ]; then
  manifests_tmp=$(mktemp -d)
  trap 'rm -rf "$manifests_tmp"' EXIT
  HIGHBALL_MANIFESTS="$manifests_tmp/engines"
  fetch_manifests "${newer_kit:-$pinned}" "$HIGHBALL_MANIFESTS"
fi
to_pin=""
if ls "$HIGHBALL_MANIFESTS"/*.json >/dev/null 2>&1; then
  to_pin=$(sh scripts/sync/pin-engines.sh --dry-run "$HIGHBALL_MANIFESTS" | sed -n 's/^pinned \([^ ]*\) .*/\1/p')
else
  sync_log "highball: no engine manifests at $HIGHBALL_MANIFESTS, engine revisions not checked"
fi

if [ -z "$newer_kit" ] && [ -z "$newer_db" ] && [ -z "$to_pin" ]; then
  sync_log "highball: HighballKit $pinned and highball-db $(printf %.7s "$db_pinned") are current"
  exit 0
fi

branch="sync/highball"
[ -z "$newer_kit" ] || branch="$branch-$newer_kit"
[ -z "$newer_db" ] || branch="$branch-db-$(printf %.7s "$newer_db")"
[ -n "$newer_kit$newer_db" ] || branch="sync/highball-engines-$(printf '%s\n' "$to_pin" | tail -1)"
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
  sed -i.bak "s/highballKitVersion = \"[^\"]*\"/highballKitVersion = \"$newer_kit\"/" app/Sources/HighballEnvCore/HighballEnvCore.swift
  rm -f app/Package.swift.bak app/Sources/HighballEnvCore/HighballEnvCore.swift.bak
  "$SWIFT" package --package-path app resolve >/dev/null
  git add app/Package.swift app/Package.resolved app/Sources/HighballEnvCore/HighballEnvCore.swift
  notes="$notes- HighballKit $pinned → $newer_kit: https://github.com/gauthierpiarrette/highball/releases/tag/v$newer_kit
"
fi
if [ -n "$to_pin" ]; then
  pins=$(sh scripts/sync/pin-engines.sh "$HIGHBALL_MANIFESTS")
  for engine in $to_pin; do
    notes="$notes- Highball engine $engine is supported: the same Wine build as $(printf '%s\n' "$pins" | sed -n "s/^pinned $engine like \([^ ,]*\).*/\1/p")
"
    engines_text="${engines_text:+$engines_text, }${engine##*-}"
  done
  for engine in $(printf '%s\n' "$pins" | sed -n 's/^unknown \([^ ]*\) .*/\1/p'); do
    notes="$notes- Highball engine $engine brings a new Wine build and stays unsupported here; the engines job checks it
"
  done
  git add Makefile app/Sources/NotProtonApp/Model/SupportedRunner.swift app/Sources/NotProtonApp/Model/NtdllPatcher.swift
fi
if [ -n "$newer_db" ]; then
  "$REFRESH_DB" "$newer_db" >/dev/null
  git add third_party/highball-db
  notes="$notes- highball-db $(printf %.7s "$db_pinned") → $(printf %.7s "$newer_db"): https://github.com/gauthierpiarrette/highball-db/compare/$db_pinned...$newer_db
"
fi
summary="${newer_kit:+HighballKit $newer_kit}${newer_kit:+${newer_db:+, }}${newer_db:+highball-db $(printf %.7s "$newer_db")}"
git commit -q -m "Sync Highball: ${summary:-engines $engines_text}

$notes
Co-Authored-By: Proton-ish sync <93226629+MagnusPladsen@users.noreply.github.com>"
if [ -n "$summary" ]; then
  version=$(bump_release "$summary: Highball's fixes and per-game data as of this release.${engines_text:+ Supports Highball engine $engines_text.}")
else
  version=$(bump_release "Supports Highball engine $engines_text.")
fi
git push -q -u origin "$branch"
title="${newer_kit:+$newer_kit }${newer_db:+db $(printf %.7s "$newer_db")}"
title=${title% }
[ -n "$title" ] || title="engines $engines_text"
"$GH" pr create -R "$REPO" --base main --head "$branch" \
  --title "sync: Highball $title" --label upstream-sync --label highball \
  --body "$(printf '## What\n%sReleased as %s.\n\nA HighballKit bump can change the API `highball-env` builds against; CI builds it. Engine revisions on a Wine build Proton-ish supports are pinned here; the engines job turns a new Wine build into a review PR when it matches a supported one, or an issue when it needs new detour work.\n%s' "$notes" "$version" "$(footer "$version")")"
enable_auto_merge "$branch"
sync_log "highball: opened a PR on $branch, releases $version when CI passes"

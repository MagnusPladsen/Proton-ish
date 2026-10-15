#!/bin/sh
# shellcheck disable=SC2016
# Opens an issue for each highball-engine release newer than the newest engine Proton-ish supports.
# Usage: scripts/sync/highball-engine.sh
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh disable=SC1091
. scripts/sync/common.sh

known=$(tr -d ' \n' < scripts/sync/known-highball-engine)
# Tags are engine-wine-<version>-<ISO timestamp>-<serial>-<name>; the timestamp orders them
"$GH" release list -R gauthierpiarrette/highball-engine --limit 50 --json tagName -q '.[].tagName' |
  grep '^engine-wine-' | sort | while IFS= read -r tag; do
    # Newer when it sorts after the known tag
    [ "$tag" != "$known" ] && [ "$(printf '%s\n%s\n' "$known" "$tag" | sort | tail -1)" = "$tag" ] || continue
    if issue_exists "$tag"; then
      sync_log "engine: $tag already has an issue"
      continue
    fi
    "$GH" issue create -R "$REPO" --title "New Highball engine $tag" --label upstream-sync --label highball-engine \
      --body "$(printf 'Highball published a new engine build: https://github.com/gauthierpiarrette/highball-engine/releases/tag/%s\n\nSupporting it in Proton-ish is manual work:\n\n- [ ] Find the engine manifest id in Highball'"'"'s `spike/engines/` that uses this build\n- [ ] Build the detour payloads and record the clean/patched ntdll and loader hashes (see `docs/superpowers/plans/2026-10-14-m2a-highball-runner.md`, Task 5)\n- [ ] Add the `RunnerBuild` to `SupportedRunner.swift` and the id to `HIGHBALL_ENGINES` in the Makefile\n- [ ] Launch a game through it; update README and `scripts/sync/known-highball-engine`\n%s' "$tag" "$(footer)")"
    sync_log "engine: opened an issue for $tag"
  done

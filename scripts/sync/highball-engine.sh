#!/bin/sh
# shellcheck disable=SC2016
# Turns a new Highball Wine build into a review PR when its ntdll resolves like a pinned build's
# (same hooks, caves and exports, so that build's detour payloads carry over), or into an issue
# with resolve.py's report when it does not. A build counts once a manifest in the pinned
# HighballKit package uses it, and only the newest revision on such a build is handled. One PR or
# issue per build, ever: closing the PR turns the build down. The PR never merges itself and
# never bumps the version; a person launches a game through the engine first. When main moves
# on and the PR conflicts, the next run redoes the pin on main and force-pushes the same branch.
# HIGHBALL_MANIFESTS names a manifest directory instead of the pinned package's, DOWNLOAD fetches
# a URL into a file, RESOLVE and APPLY stand in for ntdll-patch's scripts (tests stub all four).
# Usage: scripts/sync/highball-engine.sh
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=scripts/sync/common.sh disable=SC1091
. scripts/sync/common.sh

DOWNLOAD="${DOWNLOAD:-curl -fsSL --retry 3 -o}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# One value from a JSON file by a dotted path: empty when missing or null, a list one per line
json_value() {   # file path
  python3 -I -c '
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value.get(key) if isinstance(value, dict) else None
print("\n".join(value) if isinstance(value, list) else "" if value is None else value)' "$1" "$2"
}

manifests="${HIGHBALL_MANIFESTS:-}"
if [ -z "$manifests" ]; then
  pinned=$(sed -n 's/.*gauthierpiarrette\/highball", exact: "\([^"]*\)".*/\1/p' app/Package.swift)
  [ -n "$pinned" ] || { echo "sync: no HighballKit pin found in app/Package.swift" >&2; exit 1; }
  manifests="$scratch/manifests"
  fetch_manifests "$pinned" "$manifests"
fi
pins=$(sh scripts/sync/pin-engines.sh --dry-run "$manifests")
# The newest revision on a Wine build Proton-ish has not pinned; older ones are superseded
unknown=$(printf '%s\n' "$pins" | sed -n 's/^unknown //p' | tail -1)
if [ -z "$unknown" ]; then
  sync_log "engine: every Highball engine revision is on a pinned Wine build"
  exit 0
fi
engine=${unknown%% *}
manifest="$manifests/$engine.json"
sha=$(json_value "$manifest" components.wine.sha256)
short=$(printf %.12s "$sha")
branch="sync/engine-$short"
# An open PR GitHub calls conflicting is redone on main as it is now, unless a person has
# committed to it; any other PR or issue for the build stands
refresh=
if pr_ever_exists "$branch"; then
  state=$("$GH" pr view "$branch" -R "$REPO" --json state,mergeable -q '.state + " " + .mergeable') ||
    { echo "sync: cannot read the PR for $branch" >&2; exit 1; }
  if [ "$state" != "OPEN CONFLICTING" ]; then
    sync_log "engine: Wine build $short of $engine already has a PR"
    exit 0
  fi
  git fetch -q origin main "+refs/heads/$branch:refs/remotes/origin/$branch"
  if git log --format=%ae "origin/main..origin/$branch" | grep -qvx "93226629+MagnusPladsen@users.noreply.github.com"; then
    sync_log "engine: the PR on $branch conflicts with main, but a person has committed to it; leaving it"
    exit 0
  fi
  refresh=1
elif issue_ever_exists "$short"; then
  sync_log "engine: Wine build $short of $engine already has an issue"
  exit 0
fi

url=$(json_value "$manifest" components.wine.url)
size=$(json_value "$manifest" components.wine.size)
subpath=$(json_value "$manifest" components.wine.extract.subpath)
subpath="${subpath:-engine}"
# shellcheck disable=SC2086
$DOWNLOAD "$scratch/wine.tar.gz" "$url"
got=$(wc -c < "$scratch/wine.tar.gz" | tr -d ' ')
[ "$got" = "$size" ] || { echo "sync: $url is $got bytes, its manifest says $size" >&2; exit 1; }
got=$(shasum -a 256 "$scratch/wine.tar.gz" | cut -d' ' -f1)
[ "$got" = "$sha" ] || { echo "sync: $url has sha256 $got, its manifest says $sha" >&2; exit 1; }
mkdir "$scratch/wine"
tar -xzf "$scratch/wine.tar.gz" -C "$scratch/wine" \
  "$subpath/bin/wine" "$subpath/lib/wine/x86_64-windows/ntdll.dll" "$subpath/lib/wine/i386-windows/ntdll.dll"
python3 -I scripts/sync/wine_build.py check "$scratch/wine/$subpath" > "$scratch/check.json"

match=$(json_value "$scratch/check.json" match)
serial=$(python3 -I -B -c 'import json, sys; sys.path.insert(0, "scripts/sync"); import wine_build; print(wine_build.serial(json.load(open(sys.argv[1]))["components"]["wine"]))' "$manifest")
hashes=$(printf -- '- Wine build: %s, %s\n- Loader: `%s`\n- Clean ntdll: x86_64 `%s`, i386 `%s`' "$short" "$url" \
  "$(json_value "$scratch/check.json" loader)" \
  "$(json_value "$scratch/check.json" clean.x86_64-windows)" "$(json_value "$scratch/check.json" clean.i386-windows)")

if [ -z "$match" ] && [ -n "$refresh" ]; then
  sync_log "engine: Wine build $short of $engine no longer resolves like a pinned build; its PR is left as it is"
  exit 0
fi
if [ -z "$match" ]; then
  "$GH" issue create -R "$REPO" --title "Highball engine $engine: Wine build $serial needs new detour work" \
    --label upstream-sync --label highball-engine \
    --body "$(printf '## What\nHighball engine `%s` uses Wine build %s, which Proton-ish has not pinned. Its ntdll does not resolve like any pinned build'"'"'s, so the detour payloads need new work.\n\n%s\n\n## Differences from the newest pinned build\n```\n%s\n```\n\n## resolve.py\n```\n%s\n```\n\n## To do (`docs/superpowers/plans/2026-10-14-m2a-highball-runner.md`, Task 5)\n- [ ] Build detour payloads for the new constants with `ntdll-patch/build-ntdll.sh`\n- [ ] Pin the hashes in `ntdll-patch/resolve.py`, `apply.py` and `build-ntdll.sh`, `NtdllPatcher.swift`, `SupportedRunner.swift` and the Makefile'"'"'s `HIGHBALL_ENGINES`\n- [ ] Launch a game through `%s`\n\n---\nOpened by the upstream-sync workflow'"'"'s engines job.\n' \
      "$engine" "$serial" "$hashes" "$(json_value "$scratch/check.json" differences)" "$(json_value "$scratch/check.json" report)" "$engine")"
  sync_log "engine: opened an issue for Wine build $short of $engine"
  exit 0
fi

git fetch -q origin main
git_identity
git checkout -q -B "$branch" origin/main
python3 -I scripts/sync/wine_build.py pin "$engine" "$manifest" < "$scratch/check.json"
git add Makefile ntdll-patch/resolve.py ntdll-patch/apply.py ntdll-patch/build-ntdll.sh \
  app/Sources/NotProtonApp/Model/SupportedRunner.swift app/Sources/NotProtonApp/Model/NtdllPatcher.swift
git commit -q -m "Pin Highball engine $engine on Wine build $serial

Its ntdll resolves like $match's, so it takes that build's detour payloads;
the launcher and ntdll hashes are its own.

Co-Authored-By: Proton-ish sync <93226629+MagnusPladsen@users.noreply.github.com>"
# A branch left by a run that failed before its PR has no PR to lose
git push -q -f -u origin "$branch"
if [ -n "$refresh" ]; then
  sync_log "engine: refreshed the PR on $branch for $engine on main as it is now"
  exit 0
fi
"$GH" pr create -R "$REPO" --base main --head "$branch" \
  --title "sync: Highball engine $engine, Wine build $serial" --label upstream-sync --label highball-engine \
  --body "$(printf '## What\nHighball engine `%s` uses Wine build %s, which Proton-ish has not pinned. Its ntdll resolves like `%s`'"'"'s: same hooks, stolen bytes, caves and exports, so it takes that build'"'"'s detour payloads.\n\n%s\n- Patched ntdll: x86_64 `%s`, i386 `%s`\n\n## Before merging\n- [ ] Download the engine in the app and launch a game through %s\n- [ ] If it should ship, run `scripts/sync/bump-release.sh "Supports Highball engine %s."` on this branch; merged without it, nothing is released\n\n---\nOpened by the upstream-sync workflow'"'"'s engines job. It does not merge itself: a new Wine build is code the detours have not met. Closing it turns this build down for good.\n' \
    "$engine" "$serial" "$match" "$hashes" \
    "$(json_value "$scratch/check.json" patched.x86_64-windows)" "$(json_value "$scratch/check.json" patched.i386-windows)" "$engine" "$engine")"
sync_log "engine: opened a PR on $branch for $engine; it waits for a review"

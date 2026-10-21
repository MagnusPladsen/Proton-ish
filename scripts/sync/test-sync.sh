#!/bin/sh
# Exercises the upstream sync scripts against fixture repositories and a stubbed gh.
# Usage: sh scripts/sync/test-sync.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n         want [%s]\n         got  [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1" "a line matching $2" "$(cat "$3" 2>/dev/null)"; fi; }
hasnt() { if grep -q -- "$2" "$3" 2>/dev/null; then bad "$1" "no line matching $2" "$(grep -- "$2" "$3")"; else ok "$1"; fi; }

# A gh that records every call and answers from files the cases write
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "issue list") cat "$STUB_DIR/issues" 2>/dev/null ;;
  "pr list") cat "$STUB_DIR/prs" 2>/dev/null ;;
  "release list") cat "$STUB_DIR/releases" 2>/dev/null ;;
  "api repos/gauthierpiarrette/highball-db/commits/main") cat "$STUB_DIR/dbhead" 2>/dev/null ;;
  "pr create"|"issue create") echo "https://example.invalid/1" ;;
  # GitHub refuses auto-merge until it has registered the new head's checks
  "pr merge")
    left=$(cat "$STUB_DIR/merge-refusals" 2>/dev/null || echo 0)
    if [ "$left" -gt 0 ]; then echo $((left - 1)) > "$STUB_DIR/merge-refusals"; echo "Pull request is in clean status" >&2; exit 1; fi ;;
esac
STUB
chmod +x "$work/bin/gh"
export GH="$work/bin/gh" REPO="example/fork" STUB_DIR="$work/stub" STUB_LOG="$work/gh.log" AUTO_MERGE_WAIT=0
mkdir -p "$STUB_DIR"
git_quiet() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@"; }

# The version header and changelog a release bump edits, as the fork lays them out
release_files() {
  mkdir -p "$1/dylib"
  printf '#define NOTPROTON_VERSION "0.1.0-beta.5"\n' > "$1/dylib/version.h"
  printf '# Fork\n\n## Changes from upstream\n\n- 2026-10-01: the first line,\n  wrapped.\n\n## Next section\n\ntext\n' > "$1/CHANGELOG.md"
  printf '# Fork\n\ntext\n' > "$1/README.md"
}
version_on() { git -C "$1" show "$2:dylib/version.h" | sed -n 's/^#define NOTPROTON_VERSION "\(.*\)"/\1/p'; }

# A checkout with the sync scripts in it, an origin and an upstream to talk to
checkout() {
  rm -rf "$work/repo" "$work/origin.git" "$work/upstream.git" "$work/seed"
  git_quiet init -q "$work/seed"
  mkdir -p "$work/seed/scripts/sync"
  cp "$here"/common.sh "$here"/notproton.sh "$here"/highball.sh "$here"/highball-engine.sh "$here"/bump-release.sh "$here"/known-highball-engine "$work/seed/scripts/sync/"
  printf 'line one\nline two\n' > "$work/seed/steam.cpp"
  release_files "$work/seed"
  git_quiet -C "$work/seed" add -A && git_quiet -C "$work/seed" commit -q -m "base"
  git_quiet -C "$work/seed" tag v0.1.0-beta.5 && git_quiet -C "$work/seed" tag v1.0.0
  git_quiet clone -q --bare "$work/seed" "$work/origin.git"
  git_quiet clone -q --bare "$work/seed" "$work/upstream.git"
  git_quiet clone -q "$work/origin.git" "$work/repo"
  git_quiet -C "$work/repo" remote add upstream "$work/upstream.git"
}
upstream_commit() {   # file content message
  rm -rf "$work/up"; git_quiet clone -q "$work/upstream.git" "$work/up"
  printf '%s' "$2" > "$work/up/$1"; git_quiet -C "$work/up" add -A; git_quiet -C "$work/up" commit -q -m "$3"; git_quiet -C "$work/up" push -q origin main
  git_quiet -C "$work/up" rev-parse --short=7 HEAD
}
origin_commit() {
  rm -rf "$work/or"; git_quiet clone -q "$work/origin.git" "$work/or"
  printf '%s' "$2" > "$work/or/$1"; git_quiet -C "$work/or" add -A; git_quiet -C "$work/or" commit -q -m "$3"; git_quiet -C "$work/or" push -q origin main
}
run() { : > "$STUB_LOG"; sh "$work/repo/scripts/sync/$1" > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"; }

echo "== NotProton: nothing new =="
checkout
run notproton.sh
has "reports main already has upstream" "already has upstream/main" "$work/out"
hasnt "opens nothing" "create" "$STUB_LOG"

echo "== NotProton: a clean merge becomes a PR =="
sha=$(upstream_commit fix.c 'int fixed;' "Fix output logging")
run notproton.sh
has "a PR is created from the sync branch" "pr create .* --head sync/notproton-$sha" "$STUB_LOG"
has "the PR carries the upstream-sync label" "--label upstream-sync --label notproton" "$STUB_LOG"
is "the branch is pushed to origin" "1" "$(git -C "$work/origin.git" branch --list "sync/notproton-$sha" | wc -l | tr -d ' ')"
is "the merge commit is the bot's" "Proton-ish sync" "$(git -C "$work/origin.git" log -1 --format=%an "sync/notproton-$sha")"
is "the version is bumped past the released one" "0.1.0-beta.6" "$(version_on "$work/origin.git" "sync/notproton-$sha")"
is "the changelog gets a dated line naming the merge, after the last entry" "1" \
  "$(git -C "$work/origin.git" show "sync/notproton-$sha:CHANGELOG.md" | grep -c "^- $(date +%Y-%m-%d): NotProton $sha merged")"
is "the wrapped last entry stays whole" "  wrapped." "$(git -C "$work/origin.git" show "sync/notproton-$sha:CHANGELOG.md" | sed -n '/^- 2026-10-01/{n;p;}')"
is "the next section still follows a blank line" "" "$(git -C "$work/origin.git" show "sync/notproton-$sha:CHANGELOG.md" | sed -n '/^## Next section/{x;p;}')"
has "auto-merge is turned on for the PR" "pr merge --auto --merge .* sync/notproton-$sha" "$STUB_LOG"
has "the PR says what merging publishes" "publishes 0.1.0-beta.6" "$STUB_LOG"
run notproton.sh
hasnt "a second run opens no second PR" "pr create" "$STUB_LOG"
has "and says why" "already in a PR or issue" "$work/out"

echo "== Auto-merge before GitHub has the checks =="
checkout
upstream_commit fix.c 'int fixed;' "Fix output logging" > /dev/null
printf '2\n' > "$STUB_DIR/merge-refusals"
run notproton.sh
is "a refused auto-merge is asked for again until it is on" "3" "$(grep -c '^pr merge --auto' "$STUB_LOG")"
hasnt "and the sync succeeds" "^exit" "$work/out"
checkout
upstream_commit fix.c 'int fixed;' "Fix output logging" > /dev/null
printf '9\n' > "$STUB_DIR/merge-refusals"
run notproton.sh
is "it gives up after five tries" "5" "$(grep -c '^pr merge --auto' "$STUB_LOG")"
has "and fails, so the run shows red" "^exit 1" "$work/out"
rm -f "$STUB_DIR/merge-refusals"

echo "== Bump by hand =="
checkout
git_quiet -C "$work/repo" checkout -q -b by-hand
sh "$work/repo/scripts/sync/bump-release.sh" "NotProton abc1234 merged" > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"
is "the version is bumped on the current branch" "0.1.0-beta.6" "$(version_on "$work/repo" HEAD)"
is "the changelog line is committed" "1" "$(git -C "$work/repo" show HEAD:CHANGELOG.md | grep -c "^- $(date +%Y-%m-%d): NotProton abc1234 merged")"
has "it says what merging publishes" "release 0.1.0-beta.6 bumped on by-hand" "$work/out"
sh "$work/repo/scripts/sync/bump-release.sh" > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"
has "without text it refuses" "exit 2" "$work/out"

echo "== Next version =="
nv() { (cd "$work/repo" && sh -c '. scripts/sync/common.sh; next_version "$1"' _ "$1"); }
is "a released beta moves to the next beta" "0.1.0-beta.6" "$(nv 0.1.0-beta.5)"
is "a version with no tag yet is kept" "0.1.0-beta.7" "$(nv 0.1.0-beta.7)"
is "a released final version moves to the next patch" "1.0.1" "$(nv 1.0.0)"

echo "== NotProton: the fork's README wins a README conflict =="
checkout
rm -rf "$work/or"; git_quiet clone -q "$work/origin.git" "$work/or"
cp "$here/../../.gitattributes" "$work/or/.gitattributes"
sed -i.bak '1s/.*/# Fork, our own words/' "$work/or/README.md" && rm -f "$work/or/README.md.bak"
git_quiet -C "$work/or" add -A && git_quiet -C "$work/or" commit -q -m "our README" && git_quiet -C "$work/or" push -q origin main
rm -rf "$work/up"; git_quiet clone -q "$work/upstream.git" "$work/up"
sed -i.bak '1s/.*/# NotProton, upstream words/' "$work/up/README.md" && rm -f "$work/up/README.md.bak"
printf 'int fixed;\n' > "$work/up/fix.c"
git_quiet -C "$work/up" add -A && git_quiet -C "$work/up" commit -q -m "their README and a fix" && git_quiet -C "$work/up" push -q origin main
sha=$(git_quiet -C "$work/up" rev-parse --short=7 HEAD)
run notproton.sh
has "a README-only conflict still becomes a PR" "pr create .* --head sync/notproton-$sha" "$STUB_LOG"
hasnt "and no issue" "issue create" "$STUB_LOG"
is "the README keeps the fork's text" "# Fork, our own words" "$(git -C "$work/origin.git" show "sync/notproton-$sha:README.md" | head -1)"
is "upstream's code change is merged" "int fixed;" "$(git -C "$work/origin.git" show "sync/notproton-$sha:fix.c")"

echo "== NotProton: a conflict becomes an issue =="
checkout
origin_commit steam.cpp 'line one\nours\n' "our change"
sha=$(upstream_commit steam.cpp 'line one\ntheirs\n' "their change")
run notproton.sh
has "an issue is created" "issue create .* --title NotProton $sha does not merge cleanly" "$STUB_LOG"
hasnt "no PR is created" "pr create" "$STUB_LOG"
is "no branch is pushed" "0" "$(git -C "$work/origin.git" branch --list "sync/notproton-*" | wc -l | tr -d ' ')"
is "the checkout is left clean" "" "$(git -C "$work/repo" status --porcelain)"
printf '7\n' > "$STUB_DIR/issues"
run notproton.sh
hasnt "with the issue open, no second issue" "issue create" "$STUB_LOG"
rm -f "$STUB_DIR/issues"

echo "== Highball: pin and database =="
hb() {   # pinned-kit db-commit
  rm -rf "$work/hb" "$work/hb-origin.git"
  mkdir -p "$work/hb/app/Sources/HighballEnvCore" "$work/hb/third_party/highball-db" "$work/hb/scripts/sync"
  cp "$here"/common.sh "$here"/highball.sh "$work/hb/scripts/sync/"
  printf '        .package(url: "https://github.com/gauthierpiarrette/highball", exact: "%s"),\n' "$1" > "$work/hb/app/Package.swift"
  printf 'public static let highballKitVersion = "%s"\n' "$1" > "$work/hb/app/Sources/HighballEnvCore/HighballEnvCore.swift"
  printf '{"source":{"commit":"%s"},"games":[],"recipes":[]}\n' "$2" > "$work/hb/third_party/highball-db/highball-db.json"
  : > "$work/hb/app/Package.resolved"
  release_files "$work/hb"
  git_quiet -C "$work/hb" init -q && git_quiet -C "$work/hb" add -A && git_quiet -C "$work/hb" commit -q -m base
  git_quiet -C "$work/hb" tag v0.1.0-beta.5
  git_quiet clone -q --bare "$work/hb" "$work/hb-origin.git"
  git_quiet -C "$work/hb" remote add origin "$work/hb-origin.git"
  git_quiet -C "$work/hb" fetch -q origin
}
# swift resolve and the database refresh are stubbed: they touch the network
cat > "$work/bin/swift" <<'STUB'
#!/bin/sh
echo resolved > app/Package.resolved
STUB
cat > "$work/bin/refresh-db" <<'STUB'
#!/bin/sh
printf '{"source":{"commit":"%s"},"games":[],"recipes":[]}\n' "$1" > third_party/highball-db/highball-db.json
STUB
chmod +x "$work/bin/swift" "$work/bin/refresh-db"
export SWIFT="$work/bin/swift" REFRESH_DB="$work/bin/refresh-db"
runhb() { : > "$STUB_LOG"; sh "$work/hb/scripts/sync/highball.sh" > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"; }

hb 0.10.15 aaaaaaa1111
printf 'v0.10.15\n' > "$STUB_DIR/releases"; printf 'aaaaaaa1111\n' > "$STUB_DIR/dbhead"
runhb
has "nothing newer reports current" "are current" "$work/out"
hasnt "and opens nothing" "create" "$STUB_LOG"

printf 'v0.10.16\n' > "$STUB_DIR/releases"
runhb
has "a newer Highball release opens a PR" "pr create .* --head sync/highball-0.10.16 " "$STUB_LOG"
is "the pin is bumped" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:app/Package.swift | grep -c 'exact: "0.10.16"')"
is "the helper's version constant follows" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:app/Sources/HighballEnvCore/HighballEnvCore.swift | grep -c '"0.10.16"')"
is "the version is bumped on the Highball branch" "0.1.0-beta.6" "$(version_on "$work/hb-origin.git" sync/highball-0.10.16)"
is "the changelog names the HighballKit bump" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:CHANGELOG.md | grep -c "^- $(date +%Y-%m-%d): HighballKit 0.10.16")"
has "auto-merge is turned on for the Highball PR" "pr merge --auto --merge .* sync/highball-0.10.16" "$STUB_LOG"
runhb
hasnt "a second run opens no second PR" "pr create" "$STUB_LOG"

hb 0.10.15 aaaaaaa1111
printf 'public static let highballKitVersion = "0.10.1"\n' > "$work/hb/app/Sources/HighballEnvCore/HighballEnvCore.swift"
git_quiet -C "$work/hb" commit -q -am "drifted constant" && git_quiet -C "$work/hb" push -q origin main
printf 'v0.10.16\n' > "$STUB_DIR/releases"
runhb
is "a drifted HighballKit constant follows the pin" 'public static let highballKitVersion = "0.10.16"' "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:app/Sources/HighballEnvCore/HighballEnvCore.swift)"

hb 0.10.15 aaaaaaa1111
printf 'v0.10.9\n' > "$STUB_DIR/releases"
runhb
hasnt "an older release is not a downgrade" "pr create" "$STUB_LOG"

hb 0.10.15 aaaaaaa1111
printf 'v0.10.16\n' > "$STUB_DIR/releases"; printf 'bbbbbbb2222\n' > "$STUB_DIR/dbhead"
runhb
has "both newer go in one PR" "--head sync/highball-0.10.16-db-bbbbbbb " "$STUB_LOG"
is "the snapshot is refreshed" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16-db-bbbbbbb:third_party/highball-db/highball-db.json | grep -c bbbbbbb2222)"

echo "== Highball engines =="
eng() {
  rm -rf "$work/eng"; mkdir -p "$work/eng/scripts/sync"
  cp "$here"/common.sh "$here"/highball-engine.sh "$work/eng/scripts/sync/"
  printf 'engine-wine-11.0-20261005T184024Z-0019-forza-trial\n' > "$work/eng/scripts/sync/known-highball-engine"
}
runeng() { : > "$STUB_LOG"; sh "$work/eng/scripts/sync/highball-engine.sh" > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"; }
eng
printf 'engine-wine-11.0-20261014T003801Z-0024-app-packages\nd3dmetal-tsshim-20261014\nengine-wine-11.0-20261005T184024Z-0019-forza-trial\nengine-wine-11.0-20261001T000000Z-0015-old\n' > "$STUB_DIR/releases"
runeng
is "only the newer engine gets an issue" "1" "$(grep -c "issue create" "$STUB_LOG")"
has "named after its tag" "New Highball engine engine-wine-11.0-20261014T003801Z-0024-app-packages" "$STUB_LOG"
printf '3\n' > "$STUB_DIR/issues"
runeng
hasnt "with its issue open, nothing new" "issue create" "$STUB_LOG"
rm -f "$STUB_DIR/issues"

echo "== Highball engine pins =="
manifest() {   # dir id wine-sha minMacOS displayName
  printf '{"id":"%s","minMacOS":"%s","displayName":"%s","components":{"wine":{"sha256":"%s","url":"https://example.invalid/%s.tar.xz"}}}\n' \
    "$2" "$4" "$5" "$3" "$3" > "$1/$2.json"
}
# The fork's real Makefile and Swift pins, with manifests for the revisions they pin
pins() {
  rm -rf "$work/pin"; mkdir -p "$work/pin/scripts/sync" "$work/pin/app/Sources/NotProtonApp/Model" "$work/pin/engines"
  cp "$here"/pin-engines.sh "$here"/engine_pins.py "$work/pin/scripts/sync/"
  cp "$here/../../Makefile" "$work/pin/Makefile"
  cp "$here/../../app/Package.swift" "$work/pin/app/Package.swift"
  cp "$here/../../app/Sources/NotProtonApp/Model/SupportedRunner.swift" "$here/../../app/Sources/NotProtonApp/Model/NtdllPatcher.swift" \
    "$work/pin/app/Sources/NotProtonApp/Model/"
  manifest "$work/pin/engines" x64-crossover26.3-r19 wine0019 14.0 "Wine 11.0 (CrossOver 26.3) r19"
  for r in 24 25 27; do manifest "$work/pin/engines" "x64-crossover26.3-r$r" wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r$r"; done
  manifest "$work/pin/engines" x64-crossover26.3-r26 wine0024 27.0 "Wine 11.0 (CrossOver 26.3) r26, D3DMetal 4.0 beta 3"
  manifest "$work/pin/engines" x64-sikarugir10.0_6-r40 sika 14.0 "Wine 10.0 (Sikarugir) r40"
}
runpin() { (cd "$work/pin" && sh scripts/sync/pin-engines.sh engines) > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"; }
runner="$work/pin/app/Sources/NotProtonApp/Model/SupportedRunner.swift"
patcher="$work/pin/app/Sources/NotProtonApp/Model/NtdllPatcher.swift"
# The bundle versions of SupportedRunners.all's Highball entries, in order
highball_order() { sed -n 's/^ *bundleVersion: "\(x64-crossover[^"]*\)",$/\1/p' "$runner" | tr '\n' ' ' | sed 's/ $//'; }
# One field of the RunnerBuild with that bundle version
field() { awk -v id="$1" '$0 ~ "bundleVersion: \"" id "\"" { p = 1 } p && /^        \),$/ { exit } p' "$runner" | sed -n "s/.*$2: \"\([^\"]*\)\".*/\1/p" | head -1; }

pins
runpin
is "nothing new pins nothing" "" "$(cat "$work/out")"
is "and changes nothing" "x64-crossover26.3-r19 x64-crossover26.3-r25 x64-crossover26.3-r26 x64-crossover26.3-r27" "$(highball_order)"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r28"
runpin
is "a revision on a pinned Wine build is pinned" "pinned x64-crossover26.3-r28 like x64-crossover26.3-r27" "$(cat "$work/out")"
is "it comes last, so it is the download" "x64-crossover26.3-r19 x64-crossover26.3-r25 x64-crossover26.3-r26 x64-crossover26.3-r27 x64-crossover26.3-r28" "$(highball_order)"
is "it carries the loader hash of the build it shares" "$(field x64-crossover26.3-r27 loaderSHA256)" "$(field x64-crossover26.3-r28 loaderSHA256)"
is "its release version is the revision" "r28" "$(field x64-crossover26.3-r28 releaseVersion)"
is "its tool is its own" "protonish-highball-x64-crossover26.3-r28" "$(field x64-crossover26.3-r28 name)"
is "its tool says which revision it is" "Highball Wine 11 (r28)" "$(field x64-crossover26.3-r28 display)"
has "it patches like the build it shares" '^        "x64-crossover26.3-r28": highballBuild0024,$' "$patcher"
has "it joins the engines the app bundles" '^HIGHBALL_ENGINES := .* x64-crossover26.3-r27 x64-crossover26.3-r28$' "$work/pin/Makefile"
runpin
is "a second run pins nothing" "" "$(cat "$work/out")"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r28"
(cd "$work/pin" && sh scripts/sync/pin-engines.sh --dry-run engines) > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"
is "a dry run says what it would pin" "pinned x64-crossover26.3-r28 like x64-crossover26.3-r27" "$(cat "$work/out")"
hasnt "and writes nothing" 'x64-crossover26.3-r28' "$runner"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0024 27.0 "Wine 11.0 (CrossOver 26.3) r28, D3DMetal 5"
runpin
is "a revision needing a newer macOS is pinned and says so" "pinned x64-crossover26.3-r28 like x64-crossover26.3-r27, needs macOS 27.0" "$(cat "$work/out")"
is "it goes before the download, which stays" "x64-crossover26.3-r19 x64-crossover26.3-r25 x64-crossover26.3-r26 x64-crossover26.3-r28 x64-crossover26.3-r27" "$(highball_order)"
is "its tool names what it adds" "Highball Wine 11 (r28, D3DMetal 5)" "$(field x64-crossover26.3-r28 display)"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0025 14.0 "Wine 11.0 (CrossOver 26.3) r28"
manifest "$work/pin/engines" x64-crossover26.3-r29 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r29"
runpin
has "a new Wine build is reported, not pinned" "^unknown x64-crossover26.3-r28 https://example.invalid/wine0025.tar.xz$" "$work/out"
has "a later revision on a known build still pins" "^pinned x64-crossover26.3-r29 like x64-crossover26.3-r27$" "$work/out"
hasnt "the unknown build gets no entry" 'x64-crossover26.3-r28' "$runner"
hasnt "nor a patch" 'x64-crossover26.3-r28' "$patcher"
runpin
is "a skipped revision older than a pinned one is not reported again" "" "$(cat "$work/out")"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0025 14.0 "Wine 11.0 (CrossOver 26.3) r28"
runpin; runpin
is "a new Wine build alone is reported on every run until someone pins it" "unknown x64-crossover26.3-r28 https://example.invalid/wine0025.tar.xz" "$(cat "$work/out")"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r28"
manifest "$work/pin/engines" x64-crossover26.3-r29 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r29"
runpin
is "several revisions pin in order" "x64-crossover26.3-r19 x64-crossover26.3-r25 x64-crossover26.3-r26 x64-crossover26.3-r27 x64-crossover26.3-r28 x64-crossover26.3-r29" "$(highball_order)"

pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r28"
manifest "$work/pin/engines" x64-crossover26.3-r29 wine0024 27.0 "Wine 11.0 (CrossOver 26.3) r29"
runpin
is "one needing a newer macOS goes before the comment of the download" "x64-crossover26.3-r28 ships" \
  "$(grep -B2 'bundleVersion: "x64-crossover26.3-r28"' "$runner" | sed -n '1s/^ *\/\/ \([^ ]* ships\).*/\1/p')"
hasnt "older revisions and other engine lines are left alone" 'x64-crossover26.3-r24\|sikarugir' "$work/pin/Makefile"

echo "== Highball: a HighballKit bump pins its engines =="
hb 0.10.15 aaaaaaa1111
cp "$here"/pin-engines.sh "$here"/engine_pins.py "$work/hb/scripts/sync/"
pins
manifest "$work/pin/engines" x64-crossover26.3-r28 wine0024 14.0 "Wine 11.0 (CrossOver 26.3) r28"
mkdir -p "$work/hb/app/Sources/NotProtonApp/Model"
cp "$work/pin/Makefile" "$work/hb/Makefile"
cp "$work/pin/app/Sources/NotProtonApp/Model/"*.swift "$work/hb/app/Sources/NotProtonApp/Model/"
printf '    platforms: [.macOS("15.0")],\n' >> "$work/hb/app/Package.swift"
git_quiet -C "$work/hb" add -A && git_quiet -C "$work/hb" commit -q -m "real pins" && git_quiet -C "$work/hb" push -q origin HEAD:main
printf 'v0.10.16\n' > "$STUB_DIR/releases"; printf 'aaaaaaa1111\n' > "$STUB_DIR/dbhead"
export HIGHBALL_MANIFESTS="$work/pin/engines"
runhb
unset HIGHBALL_MANIFESTS
is "the engine is pinned on the Highball branch" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:Makefile | grep -c 'x64-crossover26.3-r27 x64-crossover26.3-r28$')"
is "its Swift pins are committed with it" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:app/Sources/NotProtonApp/Model/NtdllPatcher.swift | grep -c '"x64-crossover26.3-r28": highballBuild0024')"
is "the changelog says the engine is supported" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:CHANGELOG.md | grep -c "^- $(date +%Y-%m-%d): HighballKit 0.10.16: .*Supports Highball engine r28\.")"
has "the PR names the pinned engine" "x64-crossover26.3-r28 is supported" "$STUB_LOG"

echo "== resolve.py modes =="
resolve="$here/../../ntdll-patch/resolve.py"
json_field() { python3 -I -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1" 2>/dev/null || :; }
if ! python3 -I -c 'import capstone' 2>/dev/null; then
  echo "  skip  resolve.py needs capstone"
else
  out=$(python3 -I "$resolve" --pinned e606762e531e8d749cb4075a3fea2ba063f4833dad9903074ec1762f91efc1a3 2>/dev/null) || :
  is "a pinned ntdll's hook is printed as a number" "296179" "$(printf '%s' "$out" | json_field hookRVA)"
  is "and its work register" "r15" "$(printf '%s' "$out" | json_field wm)"
  python3 -I "$resolve" --pinned 0000000000000000000000000000000000000000000000000000000000000000 > "$work/out" 2>&1 && st=0 || st=$?
  is "an unpinned sha exits 1" "1" "$st"
  is "and prints nothing" "" "$(cat "$work/out")"
  r25="$HOME/Library/Application Support/Highball/engines/x64-crossover26.3-r25/engine/lib/wine/x86_64-windows/ntdll.dll"
  if [ -f "$r25" ]; then
    out=$(python3 -I "$resolve" --json "$r25" 2>/dev/null) || :
    is "a real ntdll resolves to its hook" "296179" "$(printf '%s' "$out" | json_field hookRVA)"
    is "and its cave" "499872" "$(printf '%s' "$out" | json_field caveRVA)"
  else
    echo "  skip  no Highball r25 engine on this Mac"
  fi
fi

echo "== Wine build check =="
# resolve.py without capstone: pins come from its PINNED literal, constants from files a case writes
cat > "$work/bin/resolve" <<'STUB'
#!/usr/bin/env python3
import ast, hashlib, json, os, pathlib, sys
def pinned():
    tree = ast.parse(pathlib.Path(os.environ["REAL_RESOLVE"]).read_text())
    node = next(n for n in tree.body if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "PINNED")
    return ast.literal_eval(node.value)
if sys.argv[1] == "--pinned":
    pins = pinned()
    if sys.argv[2] not in pins: sys.exit(1)
    print(json.dumps(pins[sys.argv[2]])); sys.exit(0)
path = sys.argv[-1]
base = pathlib.Path(os.environ["STUB_DIR"], "resolve", hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest())
if base.with_suffix(".err").exists():
    sys.stderr.write(base.with_suffix(".err").read_text()); sys.exit(1)
print(base.with_suffix(".json").read_text() if sys.argv[1] == "--json" else f"report for {path}")
STUB
# apply.py's output stands in as the input, a marker and the payload
cat > "$work/bin/apply" <<'STUB'
#!/bin/sh
cat "$1" > "$2"; printf patched >> "$2"; cat "$3" >> "$2"
STUB
chmod +x "$work/bin/resolve" "$work/bin/apply"
export REAL_RESOLVE="$here/../../ntdll-patch/resolve.py"
# A repository with the real pins and payloads, and an engine of three made-up files
wb() {
  rm -rf "$work/wb" "$STUB_DIR/resolve"; mkdir -p "$work/wb/scripts/sync" "$work/wb/app/Sources/NotProtonApp" "$STUB_DIR/resolve"
  cp "$here"/wine_build.py "$here"/engine_pins.py "$work/wb/scripts/sync/" 2>/dev/null || :
  cp "$here/../../Makefile" "$work/wb/"; cp "$here/../../app/Package.swift" "$work/wb/app/"
  cp -R "$here/../../app/Sources/NotProtonApp/Model" "$here/../../app/Sources/NotProtonApp/Resources" "$work/wb/app/Sources/NotProtonApp/"
  engine="$work/wb-engine"; rm -rf "$engine"; mkdir -p "$engine/bin" "$engine/lib/wine/x86_64-windows" "$engine/lib/wine/i386-windows"
  printf 'a new launcher' > "$engine/bin/wine"
  printf 'a new 64-bit ntdll' > "$engine/lib/wine/x86_64-windows/ntdll.dll"
  printf 'a new 32-bit ntdll' > "$engine/lib/wine/i386-windows/ntdll.dll"
}
sha_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
# What resolve.py finds in a made-up ntdll: build 0024's constants, with any field overridden
resolved() {   # arch dll [field=python-literal ...]
  python3 -I - "$REAL_RESOLVE" "$STUB_DIR/resolve/$(sha_of "$2").json" "$@" <<'EOF'
import ast, json, pathlib, sys
real, out, arch, _dll, *overrides = sys.argv[1:]
tree = ast.parse(pathlib.Path(real).read_text())
pins = ast.literal_eval(next(n for n in tree.body if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "PINNED").value)
key = {"x86_64-windows": "e606762e531e8d749cb4075a3fea2ba063f4833dad9903074ec1762f91efc1a3",
       "i386-windows": "54137f366a4f15403d9eecbbf3ce575b3129251e2eebdad125b55bd4b532e5ce"}[arch]
r = {k: v for k, v in pins[key].items() if k != "payload"}
r.update({"x86_64-windows": dict(placement="padding", fill=0, machine=0x8664, magic=0x20b, imageBase=0x170000000),
          "i386-windows": dict(placement="section", fill=0, machine=0x14c, magic=0x10b, imageBase=0x7bc00000)}[arch])
for item in overrides:
    name, value = item.split("=", 1); r[name] = ast.literal_eval(value)
pathlib.Path(out).write_text(json.dumps(r))
EOF
}
runcheck() { (cd "$work/wb" && RESOLVE="$work/bin/resolve" APPLY="$work/bin/apply" python3 -I scripts/sync/wine_build.py check "$engine") > "$work/check.json" 2> "$work/out" || echo "exit $?" >> "$work/out"; }
check_field() { python3 -I -c 'import json, sys; v = json.load(open(sys.argv[1])); [v := v[int(k)] if isinstance(v, list) else v[k] for k in sys.argv[2:]]; print(json.dumps(v) if isinstance(v, (list, dict)) or v is None else v)' "$work/check.json" "$@" 2>/dev/null || :; }

wb
resolved x86_64-windows "$engine/lib/wine/x86_64-windows/ntdll.dll"
resolved i386-windows "$engine/lib/wine/i386-windows/ntdll.dll"
runcheck
is "a build resolving like a pinned one matches the newest of them" "x64-crossover26.3-r27" "$(check_field match)"
is "with no differences" "[]" "$(check_field differences)"
is "its loader hash is the launcher's" "$(sha_of "$engine/bin/wine")" "$(check_field loader)"
is "its clean hashes are the ntdlls'" "$(sha_of "$engine/lib/wine/i386-windows/ntdll.dll")" "$(check_field clean i386-windows)"
"$work/bin/apply" "$engine/lib/wine/x86_64-windows/ntdll.dll" "$work/patched64" "$work/wb/app/Sources/NotProtonApp/Resources/detour2-hb-r19.bin"
is "its patched hash comes from apply.py with the pinned build's payload" "$(sha_of "$work/patched64")" "$(check_field patched x86_64-windows)"
has "the report is resolve.py's" "report for" "$work/check.json"
is "and it exits 0" "" "$(cat "$work/out")"

wb
resolved x86_64-windows "$engine/lib/wine/x86_64-windows/ntdll.dll" hookRVA=0x484f4
resolved i386-windows "$engine/lib/wine/i386-windows/ntdll.dll"
runcheck
is "a different hook is no match" "null" "$(check_field match)"
is "and says what differs" '["x86_64-windows hookRVA 0x484f3 != 0x484f4"]' "$(check_field differences)"
is "with nothing patched" "null" "$(check_field patched)"
is "still exiting 0" "" "$(cat "$work/out")"

wb
resolved x86_64-windows "$engine/lib/wine/x86_64-windows/ntdll.dll" \
  "exports={'LdrGetDllHandle': 0x170014fe0, 'LdrLoadDll': 0x170015b50, 'NtProtectVirtualMemory': 0x17000f380, 'NtClose': 0x17000eb60}"
resolved i386-windows "$engine/lib/wine/i386-windows/ntdll.dll"
runcheck
is "exports the payload does not use are not compared" "x64-crossover26.3-r27" "$(check_field match)"

wb
resolved x86_64-windows "$engine/lib/wine/x86_64-windows/ntdll.dll" "exports={'LdrGetDllHandle': 0x170014fe0, 'LdrLoadDll': 0x170015b50}"
resolved i386-windows "$engine/lib/wine/i386-windows/ntdll.dll"
runcheck
is "a missing export the payload uses is a difference" '["x86_64-windows exports.NtProtectVirtualMemory 0x17000f380 != None"]' "$(check_field differences)"

wb
resolved x86_64-windows "$engine/lib/wine/x86_64-windows/ntdll.dll" fill=0xcc
resolved i386-windows "$engine/lib/wine/i386-windows/ntdll.dll"
runcheck
is "a cave filled differently than the app expects is no match" '["x86_64-windows fill 0x0 != 0xcc"]' "$(check_field differences)"

wb
resolved x86_64-windows "$engine/lib/wine/x86_64-windows/ntdll.dll"
printf 'cannot find build_module\n' > "$STUB_DIR/resolve/$(sha_of "$engine/lib/wine/i386-windows/ntdll.dll").err"
runcheck
is "an ntdll resolve.py refuses is no match" "null" "$(check_field match)"
is "and the refusal is the difference" "i386-windows: cannot find build_module" "$(check_field differences 0)"
has "and the report" "cannot find build_module" "$work/check.json"
is "it is an answer, not a failure" "" "$(cat "$work/out")"

echo "== Wine build pin =="
A=$(printf 'a%.0s' $(seq 64)); B=$(printf 'b%.0s' $(seq 64)); C=$(printf 'c%.0s' $(seq 64)); D=$(printf 'd%.0s' $(seq 64)); L=$(printf 'e%.0s' $(seq 64))
WINE=1d1a130c0108aaaabbbbccccddddeeeeffff0000111122223333444455556666
pinfix() {   # match tag
  wb
  mkdir -p "$work/wb/ntdll-patch"
  cp "$here/../../ntdll-patch/resolve.py" "$here/../../ntdll-patch/apply.py" "$here/../../ntdll-patch/build-ntdll.sh" "$work/wb/ntdll-patch/"
  printf '{"loader":"%s","clean":{"x86_64-windows":"%s","i386-windows":"%s"},"patched":{"x86_64-windows":"%s","i386-windows":"%s"},"match":%s,"differences":[],"report":""}\n' \
    "$L" "$A" "$B" "$C" "$D" "$1" > "$work/pin.json"
  printf '{"id":"x64-crossover26.3-r90","minMacOS":"14.0","displayName":"Wine 11.0 (CrossOver 26.3) r90","components":{"wine":{"sha256":"%s","url":"https://example.invalid/%s/%s.tar.gz"}}}\n' \
    "$WINE" "$2" "$2" > "$work/r90.json"
  (cd "$work/wb" && find . -type f -exec shasum {} + | sort) > "$work/before"
}
runwbpin() { (cd "$work/wb" && python3 -I scripts/sync/wine_build.py pin x64-crossover26.3-r90 "$work/r90.json" < "$work/pin.json") > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"; }
wbfile() { printf '%s' "$work/wb/$1"; }

pinfix '"x64-crossover26.3-r27"' engine-wine-11.0-20261101T000000Z-0025-test
runwbpin
is "pinning prints nothing" "" "$(cat "$work/out")"
has "resolve.py pins the new 64-bit ntdll" "^    '$A':$" "$(wbfile ntdll-patch/resolve.py)"
has "and the 32-bit one" "^    '$B':$" "$(wbfile ntdll-patch/resolve.py)"
is "with the pinned build's constants" "$(python3 -I -c 'import ast,sys; t=ast.parse(open(sys.argv[1]).read()); p=ast.literal_eval(next(n for n in t.body if isinstance(n,ast.Assign) and getattr(n.targets[0],"id","")=="PINNED").value); print(p[sys.argv[2]]==p["e606762e531e8d749cb4075a3fea2ba063f4833dad9903074ec1762f91efc1a3"])' "$(wbfile ntdll-patch/resolve.py)" "$A")" "True"
has "apply.py gives the 64-bit ntdll the pinned payload" "^    \"$A\": \"detour2-hb-r19.bin\",$" "$(wbfile ntdll-patch/apply.py)"
has "and the 32-bit one its own" "^    \"$B\": \"detour32-hb-r19.bin\",$" "$(wbfile ntdll-patch/apply.py)"
has "build-ntdll.sh knows the clean hash" "^HB_0025_CLEAN_X86_64=$A$" "$(wbfile ntdll-patch/build-ntdll.sh)"
has "and the patched one" "^HB_0025_PATCHED_I386=$D$" "$(wbfile ntdll-patch/build-ntdll.sh)"
is "and has the flavor in its tools and patch cases" "2" "$(grep -c '^    hb-0025)' "$(wbfile ntdll-patch/build-ntdll.sh)")"
has "and detects it" 'echo hb-0025; return 0 ;;' "$(wbfile ntdll-patch/build-ntdll.sh)"
has "and offers it" 'hb-r25, hb-0025, fex' "$(wbfile ntdll-patch/build-ntdll.sh)"
if sh -n "$(wbfile ntdll-patch/build-ntdll.sh)" && { ! command -v shellcheck >/dev/null || shellcheck "$(wbfile ntdll-patch/build-ntdll.sh)"; }; then ok "the edited build-ntdll.sh still lints"; else bad "the edited build-ntdll.sh still lints" "clean" "errors"; fi
has "NtdllPatcher names a table after the build" '^    static let highballBuild0025 = highballBuild0024$' "$(wbfile app/Sources/NotProtonApp/Model/NtdllPatcher.swift)"
has "and gives the engine that table" '^        "x64-crossover26.3-r90": highballBuild0025,$' "$(wbfile app/Sources/NotProtonApp/Model/NtdllPatcher.swift)"
runner="$work/wb/app/Sources/NotProtonApp/Model/SupportedRunner.swift"
is "the engine carries its own launcher hash" "$L" "$(field x64-crossover26.3-r90 loaderSHA256)"
is "and its own patched ntdll" "1" "$(awk '/bundleVersion: "x64-crossover26.3-r90"/{p=1} p&&/^        \),$/{exit} p' "$runner" | grep -c "i386Windows: \"$D\"")"
is "and is the download" "x64-crossover26.3-r90" "$(highball_order | tr ' ' '\n' | tail -1)"
has "the app bundles it" '^HIGHBALL_ENGINES := .* x64-crossover26.3-r90$' "$(wbfile Makefile)"

pinfix '"x64-crossover26.3-r27"' engine-wine-11.0-nightly
runwbpin
has "a tag with no serial names the build by its hash" '^    static let highballBuild1d1a130c0108 = highballBuild0024$' "$(wbfile app/Sources/NotProtonApp/Model/NtdllPatcher.swift)"
has "everywhere" '^HB_1D1A130C0108_CLEAN_X86_64=' "$(wbfile ntdll-patch/build-ntdll.sh)"

pinfix null engine-wine-11.0-20261101T000000Z-0025-test
runwbpin
has "a result with no match is refused" "exit 2" "$work/out"
is "and nothing is written" "$(cat "$work/before")" "$(cd "$work/wb" && find . -type f -exec shasum {} + | sort)"

if [ "$fails" -ne 0 ]; then echo "==> sync: $fails check(s) failed"; exit 1; fi
echo "==> sync: NotProton merges and conflicts, Highball bumps, engines and engine pins all answer"

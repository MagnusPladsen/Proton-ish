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
esac
STUB
chmod +x "$work/bin/gh"
export GH="$work/bin/gh" REPO="example/fork" STUB_DIR="$work/stub" STUB_LOG="$work/gh.log"
mkdir -p "$STUB_DIR"
git_quiet() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@"; }

# The version header and README changelog a release bump edits, as the fork lays them out
release_files() {
  mkdir -p "$1/dylib"
  printf '#define NOTPROTON_VERSION "0.1.0-beta.5"\n' > "$1/dylib/version.h"
  printf '# Fork\n\n## Changes from upstream\n\n- 2026-10-01: the first line,\n  wrapped.\n\n## Next section\n\ntext\n' > "$1/README.md"
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
  "$(git -C "$work/origin.git" show "sync/notproton-$sha:README.md" | grep -c "^- $(date +%Y-%m-%d): NotProton $sha merged")"
is "the wrapped last entry stays whole" "  wrapped." "$(git -C "$work/origin.git" show "sync/notproton-$sha:README.md" | sed -n '/^- 2026-10-01/{n;p;}')"
is "the next section still follows a blank line" "" "$(git -C "$work/origin.git" show "sync/notproton-$sha:README.md" | sed -n '/^## Next section/{x;p;}')"
has "auto-merge is turned on for the PR" "pr merge --auto --merge .* sync/notproton-$sha" "$STUB_LOG"
has "the PR says what merging publishes" "publishes 0.1.0-beta.6" "$STUB_LOG"
run notproton.sh
hasnt "a second run opens no second PR" "pr create" "$STUB_LOG"
has "and says why" "already in a PR or issue" "$work/out"

echo "== Bump by hand =="
checkout
git_quiet -C "$work/repo" checkout -q -b by-hand
sh "$work/repo/scripts/sync/bump-release.sh" "NotProton abc1234 merged" > "$work/out" 2>&1 || echo "exit $?" >> "$work/out"
is "the version is bumped on the current branch" "0.1.0-beta.6" "$(version_on "$work/repo" HEAD)"
is "the changelog line is committed" "1" "$(git -C "$work/repo" show HEAD:README.md | grep -c "^- $(date +%Y-%m-%d): NotProton abc1234 merged")"
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
is "the changelog names the HighballKit bump" "1" "$(git -C "$work/hb-origin.git" show sync/highball-0.10.16:README.md | grep -c "^- $(date +%Y-%m-%d): HighballKit 0.10.16")"
has "auto-merge is turned on for the Highball PR" "pr merge --auto --merge .* sync/highball-0.10.16" "$STUB_LOG"
runhb
hasnt "a second run opens no second PR" "pr create" "$STUB_LOG"

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

if [ "$fails" -ne 0 ]; then echo "==> sync: $fails check(s) failed"; exit 1; fi
echo "==> sync: NotProton merges and conflicts, Highball bumps and engines all answer"

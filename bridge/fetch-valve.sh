#!/bin/sh
# Fetch the Valve binaries the bridge stages, from Valve's client packages.
#
#   ./fetch.sh            download, verify every hash, report
#   ./fetch.sh --install  also copy them into the bridge
#
# The ten Valve files in the bridge come from two pinned Steam client packages. The
# pins, the CDN hosts and every file hash live in the manifest this reads, which the
# app reads as a bundled resource too, so there is one definition rather than one per
# consumer. That file also records where the package names come from, and why two of
# the paths inside the packages look misplaced.
#
# The shim once linked steam_api.dll and steam_api64.dll, which are in no client
# package and could not be fetched. That dependency is gone: steam.cpp loads
# steamclient64.dll and calls its CreateInterface instead, so every payload file is
# either built here or fetchable.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/Library/Application Support/protonish/bridge}"
WORK="${WORK:-$repo/scratch/valve-fetch}"
MANIFEST="${MANIFEST:-$repo/app/Sources/NotProtonApp/Resources/valve-packages.manifest}"
[ -f "$MANIFEST" ] || { echo "==> no package manifest at $MANIFEST" >&2; exit 1; }

# Akamai is listed first and the rest are fallbacks. All three serve identical bytes.
BASES="${BASES:-$(awk '$1 == "base" { printf "%s ", $2 }' "$MANIFEST")}"

install=0
[ "${1:-}" = "--install" ] && install=1

# id | CDN filename | sha256
PACKAGES="$(awk '$1 == "package" { print $2 "|" $3 "|" $4 }' "$MANIFEST")"

# bridge path | package id | path inside the package | sha256
FILES="$(awk '$1 == "file" { print $2 "|" $3 "|" $4 "|" $5 }' "$MANIFEST")"

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Downloads once and keeps the package, so a second run verifies without refetching.
get_pkg() {
    name="$1"
    want="$2"
    out="$WORK/$name"
    if [ -f "$out" ] && [ "$(sha "$out")" = "$want" ]; then
        echo "==> have $name"
        return 0
    fi
    for base in $BASES; do
        echo "==> fetching $name from $base"
        if curl -fsS -o "$out.part" "$base/$name"; then
            got="$(sha "$out.part")"
            if [ "$got" = "$want" ]; then
                mv "$out.part" "$out"
                return 0
            fi
            echo "    sha256 mismatch: got $got" >&2
            echo "    wanted           $want" >&2
            rm -f "$out.part"
        fi
    done
    rm -f "$out.part"
    echo "==> could not fetch $name from any base" >&2
    return 1
}

mkdir -p "$WORK"
for spec in $PACKAGES; do
    get_pkg "$(echo "$spec" | cut -d'|' -f2)" "$(echo "$spec" | cut -d'|' -f3)"
done

# Extracted fresh every run so a stale extract cannot pass the hash check by luck.
EX="$WORK/extract"
rm -rf "$EX"
mkdir -p "$EX"
for spec in $FILES; do
    inner="$(echo "$spec" | cut -d'|' -f3)"
    id="$(echo "$spec" | cut -d'|' -f2)"
    pkg="$(echo "$PACKAGES" | awk -F'|' -v id="$id" '$1 == id { print $2 }')"
    [ -n "$pkg" ] || { echo "==> file row names unknown package $id" >&2; exit 1; }
    [ -f "$EX/$inner" ] || unzip -q -o "$WORK/$pkg" "$inner" -d "$EX"
done

echo "==> verifying"
bad=0
for spec in $FILES; do
    rel="$(echo "$spec" | cut -d'|' -f1)"
    inner="$(echo "$spec" | cut -d'|' -f3)"
    want="$(echo "$spec" | cut -d'|' -f4)"
    got="$(sha "$EX/$inner" 2>/dev/null || echo missing)"
    if [ "$got" = "$want" ]; then
        printf '    %-40s ok\n' "$rel"
    else
        printf '    %-40s BAD  got %s\n' "$rel" "$got"
        bad=$((bad + 1))
    fi
done

[ "$bad" -eq 0 ] || { echo "==> $bad file(s) failed, not installing" >&2; exit 1; }

if [ "$install" -eq 0 ]; then
    echo "==> verified, pass --install to copy into the bridge"
    exit 0
fi

for spec in $FILES; do
    rel="$(echo "$spec" | cut -d'|' -f1)"
    inner="$(echo "$spec" | cut -d'|' -f3)"
    mkdir -p "$BRIDGE_DIR/$(dirname "$rel")"
    if cmp -s "$EX/$inner" "$BRIDGE_DIR/$rel"; then
        printf '    %-40s unchanged\n' "$rel"
    else
        cp -f "$EX/$inner" "$BRIDGE_DIR/$rel"
        printf '    %-40s installed\n' "$rel"
    fi
done
echo "==> done. RUN_SCRIPT stages these on the next launch."
